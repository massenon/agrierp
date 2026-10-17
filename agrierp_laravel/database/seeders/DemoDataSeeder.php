<?php

namespace Database\Seeders;

use App\Models\LivestockLot;
use App\Models\Purchase;
use App\Models\Sale;
use Database\Seeders\Demo\DemoAchatsSeeder;
use Database\Seeders\Demo\DemoAdministrationSeeder;
use Database\Seeders\Demo\DemoComptabiliteSeeder;
use Database\Seeders\Demo\DemoContexte;
use Database\Seeders\Demo\DemoElevageSeeder;
use Database\Seeders\Demo\DemoRhSeeder;
use Database\Seeders\Demo\DemoTiersSeeder;
use Database\Seeders\Demo\DemoVentesSeeder;
use Illuminate\Database\Seeder;

/**
 * Ticket 14.31 (Sprint 14) — SIMULATION COMPLÈTE DE L'EXPLOITATION.
 *
 * Peuple tous les modules avec ~5 mois d'activité cohérente : achats, élevage
 * au jour le jour, ventes, paie, administration et comptabilité. Destiné à la
 * démonstration client et à la recette manuelle — jamais à la production.
 *
 * ⚠️ TOUT PASSE PAR LES VRAIES ACTIONS, JAMAIS PAR DES INSERTIONS DIRECTES.
 * `AdjustStockAction`, `RecordPurchaseAccountingEntryAction`,
 * `RecordSaleAccountingEntryAction`, `RecordPayrollAccountingEntryAction`,
 * `RecordCreditNoteAccountingEntryAction`, `RecordDepreciationEntryAction`.
 *
 * C'est la décision structurante de ce seeder. Écrire les écritures
 * comptables à la main aurait produit un décor : rien ne garantirait
 * Σ débits = Σ crédits, le stock ne réconcilierait pas ses mouvements, et la
 * moindre évolution d'une règle métier ferait diverger la démonstration du
 * logiciel qu'elle est censée montrer. En passant par les Actions, la
 * cohérence est vraie par construction — et le seeder exerce le code réel :
 * s'il tourne, c'est que la chaîne fonctionne de bout en bout.
 *
 * ⚠️ ORDRE PORTEUR DE DÉPENDANCES RÉELLES, pas de confort de lecture :
 *   1. Tiers      — fournisseurs et clients
 *   2. Achats     — établissent le PMP, sans lequel AUCUNE valorisation de
 *                   stock n'existe (`Product::computePmp()` lit
 *                   `purchase_lines`), et alimentent le stock que les ventes
 *                   décrémenteront
 *   3. Élevage    — consomme la provende achetée, produit les sujets vendus
 *   4. Ventes     — décrémentent le stock, alimentent créances et fiches
 *   5. RH         — paie et pointage
 *   6. Admin      — dépenses, courriers, documents
 *   7. Comptabilité — dotations aux amortissements, arrêtée en dernier parce
 *                   qu'elle constate ce que les autres ont produit
 *
 * Lancement :
 *   php artisan db:seed --class=DemoDataSeeder
 *
 * Pour repartir d'une base propre :
 *   php artisan migrate:fresh --seed
 *   php artisan db:seed --class=DemoDataSeeder
 */
class DemoDataSeeder extends Seeder
{
    public function run(): void
    {
        // ⚠️ GARDE-FOU : ce seeder n'est PAS idempotent — il rejouerait 5 mois
        // d'activité par-dessus l'existante, doublant stock, écritures et
        // chiffre d'affaires. Mieux vaut refuser franchement que produire une
        // base au double de son activité réelle, anomalie très difficile à
        // diagnostiquer après coup.
        if (Sale::exists() || Purchase::exists() || LivestockLot::exists()) {
            $this->command?->error('Des données d\'activité existent déjà (ventes, achats ou bandes).');
            $this->command?->warn('Repartez d\'une base propre : php artisan migrate:fresh --seed');

            return;
        }

        $ctx = new DemoContexte();

        $this->command?->info('Simulation du '.$ctx->debut->format('d/m/Y').' au '.$ctx->fin->format('d/m/Y').'.');

        foreach ([
            DemoTiersSeeder::class,
            DemoAchatsSeeder::class,
            DemoElevageSeeder::class,
            DemoVentesSeeder::class,
            DemoRhSeeder::class,
            DemoAdministrationSeeder::class,
            DemoComptabiliteSeeder::class,
        ] as $seeder) {
            if (! class_exists($seeder)) {
                continue;
            }

            $instance = new $seeder($ctx);
            $instance->setCommand($this->command);
            $instance->run();
        }

        $this->command?->info('Simulation terminée.');
    }
}
