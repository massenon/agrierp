<?php

namespace Database\Seeders\Demo;

use App\Models\Customer;
use App\Models\Supplier;
use Illuminate\Database\Seeder;

/**
 * Ticket 14.31 (Sprint 14) — fournisseurs et clients de démonstration.
 *
 * Noms, villes et métiers repris du contexte réel de l'exploitation : Ikpinlè
 * et son bassin (Pobè, Sakété, Kétou, Porto-Novo, Cotonou), fournisseurs de
 * provende et vétérinaires du plateau. Ni noms génériques ni « Client 1 » —
 * un jeu de démonstration sert aussi à montrer l'application au client, et des
 * données plausibles se lisent, se critiquent et se corrigent.
 *
 * ⚠️ `credit_limit` renseignée sur les clients qui achètent à crédit : c'est
 * la donnée que consomment le suivi des créances et les relances. La laisser à
 * zéro aurait rendu ces écrans muets tout en paraissant peuplés.
 */
class DemoTiersSeeder extends Seeder
{
    public function __construct(private DemoContexte $ctx) {}

    public function run(): void
    {
        $this->poserSituationDouverture();

        foreach ([
            ['Provenderie du Plateau', 'Aliments', '+22997112233', 'Pobè'],
            ['SODIVET Bénin', 'Produits vétérinaires', '+22997224455', 'Porto-Novo'],
            ['Couvoir Avicole de Kétou', 'Poussins d\'un jour', '+22996335566', 'Kétou'],
            ['Quincaillerie ADJOVI', 'Équipements et matériel', '+22995446677', 'Sakété'],
            ['Ferme Semencière du Sud', 'Semences et intrants', '+22997557788', 'Ikpinlè'],
            ['Transport GBENOU & Fils', 'Transport et logistique', '+22996668899', 'Ikpinlè'],
        ] as [$nom, $categorie, $tel, $ville]) {
            Supplier::firstOrCreate(
                ['name' => $nom],
                ['category' => $categorie, 'phone' => $tel, 'address' => $ville, 'is_active' => true]
            );
        }

        foreach ([
            ['GBAGUIDI Solange', '+22997101010', 'Ikpinlè', 150_000],
            ['Restaurant LA TERRASSE', '+22997202020', 'Porto-Novo', 400_000],
            ['HOUNKPATIN Mathieu', '+22996303030', 'Pobè', 0],
            ['Supermarché EREVAN Cotonou', '+22921404040', 'Cotonou', 800_000],
            ['ADJIBODOU Rachidatou', '+22997505050', 'Sakété', 100_000],
            ['Collège Privé LES GENIES', '+22996606060', 'Ikpinlè', 250_000],
            ['DOSSOU-YOVO Bernard', '+22997707070', 'Kétou', 0],
            ['Maquis LE BAOBAB', '+22995808080', 'Pobè', 200_000],
            ['AGOSSOU Félicité', '+22997909090', 'Ikpinlè', 0],
            ['Boucherie moderne de Sakété', '+22996111213', 'Sakété', 300_000],
        ] as [$nom, $tel, $ville, $plafond]) {
            Customer::firstOrCreate(
                ['name' => $nom],
                ['phone' => $tel, 'city' => $ville, 'credit_limit' => $plafond, 'is_active' => true]
            );
        }

        $this->command?->info('  Tiers : '.Supplier::count().' fournisseurs, '.Customer::count().' clients.');
    }

    /**
     * Fonds de roulement d'ouverture de la simulation.
     *
     * ⚠️ POURQUOI RELEVER LES SOLDES SEMÉS. `TreasuryAccountsSeeder` ouvre
     * l'exploitation avec 1 600 000 FCFA au total. Or la simulation lui fait
     * porter ~1 000 000 FCFA de provende par mois : aucune ferme ne finance
     * cinq mois d'aliment avec un mois et demi de trésorerie.
     *
     * ⚠️ ET SURTOUT, LE SEEDER PASSE TOUS LES ACHATS AVANT LA PREMIÈRE VENTE.
     * C'est un ordre d'exécution, jamais une chronologie : dans la réalité,
     * achats et ventes s'entrelacent jour après jour. Cette compression fait
     * supporter à la trésorerie d'ouverture l'intégralité des cinq mois de
     * dépenses avant le moindre encaissement — d'où des comptes profondément
     * négatifs en cours de route, sans que l'exploitation simulée soit pour
     * autant en difficulté. Le fonds de roulement posé ici absorbe cet
     * artefact ; il ne masque aucun défaut de l'application.
     */
    private function poserSituationDouverture(): void
    {
        $soldes = [
            '531' => 800_000,        // caisse d'exploitation
            '521101' => 4_500_000,   // compte bancaire, fonds de roulement
            '521201' => 300_000,     // Mobile Money
        ];

        $lignes = [];

        foreach ($soldes as $code => $solde) {
            \App\Models\TreasuryAccount::where('account_code', $code)->update(['balance' => $solde]);

            $compte = \App\Models\ChartOfAccount::where('code', $code)->first();

            if ($compte) {
                $lignes[] = ['account_id' => $compte->id, 'debit' => $solde, 'credit' => 0];
            }
        }

        // ⚠️ LE FONDS DE ROULEMENT S'ÉCRIT, IL NE SE POSE PAS.
        //
        // Renseigner `treasury_accounts.balance` sans écriture en face recréait
        // exactement le défaut corrigé au ticket 14.32 : la TABLE de trésorerie
        // et les COMPTES DE CLASSE 5 du grand livre divergeaient — de
        // 5 600 000 FCFA ici, soit tout le fonds de roulement. Le Bilan
        // affichait 3 M de trésorerie quand les comptes en portaient 8,6 M.
        //
        // Un bilan d'ouverture se passe comme n'importe quelle écriture :
        //     Débit comptes de trésorerie / Crédit 101 Capital social
        // Cette contrepartie est la bonne — ces fonds ont été APPORTÉS, ils ne
        // proviennent ni d'une vente ni d'un emprunt.
        $capital = \App\Models\ChartOfAccount::where('code', '101')->first();

        if (! $capital || empty($lignes)) {
            return;
        }

        $lignes[] = ['account_id' => $capital->id, 'debit' => 0, 'credit' => array_sum($soldes)];

        app(\App\Services\AccountingEntryService::class)->record(
            lines: $lignes,
            entryDate: $this->ctx->debut->format('Y-m-d'),
            reference: "Situation d'ouverture — apport en fonds de roulement",
            sourceType: 'opening_balance',
        );
    }
}
