<?php

namespace Database\Seeders\Demo;

use App\Actions\AdjustStockAction;
use App\Actions\CreditTreasuryForSaleAction;
use App\Actions\RecordCreditNoteAccountingEntryAction;
use App\Actions\RecordSaleAccountingEntryAction;
use App\Models\CreditNote;
use App\Models\Customer;
use App\Models\CustomerAdvance;
use App\Models\CustomerReminder;
use App\Models\LivestockLot;
use App\Models\Product;
use App\Models\Quote;
use App\Models\Receivable;
use App\Models\Sale;
use App\Models\SaleLine;
use Carbon\CarbonImmutable;
use Illuminate\Database\Seeder;

/**
 * Ticket 14.31 (Sprint 14) — VENTES de démonstration.
 *
 * ⚠️ SÉQUENCE IDENTIQUE À `PosInterface::validateSale()` : `Sale` + lignes →
 * `AdjustStockAction` par ligne → encaissement (`CreditTreasuryForSaleAction`,
 * ticket 14.32) → créance si vente à crédit → transmission MeCeF →
 * `RecordSaleAccountingEntryAction`. C'est cette fidélité qui fait que le
 * chiffre d'affaires du tableau de bord, le stock, la trésorerie, les créances
 * et le Grand Livre affichent tous le même montant.
 *
 * ⚠️ CE QUI EST VENDU SORT DE CE QUI A ÉTÉ PRODUIT. Les œufs vendus viennent
 * de la ponte enregistrée sur les fiches, les poulets des bandes écoulées. Un
 * jeu de démonstration qui vendrait plus que la ferme ne produit remplirait
 * les écrans tout en rendant le stock incohérent — et c'est précisément ce que
 * le rapprochement stock/ventes est censé détecter.
 *
 * ⚠️ `mecef_status = 'transmise'` : sans lui, la Déclaration TVA reste vide.
 * `VatDeclarationService::tvaCollectee()` ne retient que les ventes validées ET
 * transmises à la plateforme MeCeF de la DGI — un filtre volontaire (une vente
 * non normalisée n'est pas déclarable), qui rendrait pourtant l'écran muet si
 * la simulation l'ignorait.
 */
class DemoVentesSeeder extends Seeder
{
    public function __construct(private DemoContexte $ctx) {}

    public function run(): void
    {
        $clients = Customer::orderBy('name')->get();
        $ventes = 0;

        foreach ($this->ctx->jours() as $jour) {
            // Le dimanche, la ferme ne vend pas au comptoir.
            if ($jour->dayOfWeek === CarbonImmutable::SUNDAY) {
                continue;
            }

            foreach (range(1, $this->ctx->entre(1, 4)) as $ignore) {
                if ($this->creerVente($jour, $clients)) {
                    $ventes++;
                }
            }
        }

        $this->reglerCreances();
        $this->creerAvoirs();
        $this->creerDevis($clients);
        $this->creerAvances($clients);
        $this->creerRelances();

        $this->command?->info('  Ventes : '.$ventes.' ventes, '.Receivable::count().' créances, '
            .CreditNote::count().' avoirs, '.Quote::count().' devis.');
    }

    /** @param  \Illuminate\Support\Collection<int, Customer>  $clients */
    private function creerVente(CarbonImmutable $jour, $clients): bool
    {
        $catalogue = $this->catalogueDuJour();

        if (empty($catalogue)) {
            return false;
        }

        $lignes = [];
        $total = 0.0;

        // ⚠️ QUANTITÉS DÉJÀ RETENUES DANS CE MÊME PANIER. Rafraîchir le modèle
        // ne suffit pas : deux lignes d'une même vente portant le même produit
        // voyaient toutes deux le stock ENTIER, puisque le décrément n'a lieu
        // qu'après la constitution du panier. D'où des stocks légèrement
        // négatifs malgré un contrôle de disponibilité apparemment correct.
        $reserve = [];

        foreach (range(1, $this->ctx->entre(1, 3)) as $ignore) {
            $sku = $this->ctx->parmi($catalogue);

            // ⚠️ INSTANCE RAFRAÎCHIE À CHAQUE LIGNE. `DemoContexte::produit()`
            // mémorise les modèles pour éviter des milliers de requêtes — mais
            // l'instance en cache garde le `stock_qty` lu au premier accès,
            // sans voir les décréments des ventes précédentes. Le contrôle de
            // disponibilité portait donc sur un stock périmé, et la simulation
            // finissait avec des stocks négatifs qu'elle croyait avoir évités.
            $produit = $this->ctx->produit($sku)->refresh();

            // ⚠️ On ne vend jamais plus que le stock disponible : au-delà, la
            // vente serait certes enregistrée (l'alerte du ticket 14.30 n'est
            // pas bloquante) mais la démonstration afficherait des stocks
            // négatifs partout, ce qui ferait passer une alerte légitime pour
            // un défaut du logiciel.
            $disponible = (int) floor((float) $produit->stock_qty) - ($reserve[$sku] ?? 0);

            if ($disponible < 1) {
                continue;
            }

            $qte = min($this->ctx->entre(1, 6), $disponible);
            $reserve[$sku] = ($reserve[$sku] ?? 0) + $qte;
            $prix = $this->ctx->entre((int) $produit->price_min, (int) $produit->price_max);
            $montant = $qte * $prix;

            $lignes[] = ['produit' => $produit, 'qty' => $qte, 'montant' => $montant];
            $total += $montant;
        }

        if (empty($lignes)) {
            return false;
        }

        // Répartition des modes de règlement proche du terrain : l'essentiel
        // au comptant, du Mobile Money, et du crédit pour les revendeurs.
        $mode = match (true) {
            $this->ctx->chance(58) => 'especes',
            $this->ctx->chance(45) => 'mobile_money',
            $this->ctx->chance(50) => 'credit',
            default => 'virement',
        };

        // Une vente à crédit suppose un client identifié : on ne fait pas
        // crédit à un client anonyme.
        // ⚠️ TIRAGE PAR LA GRAINE DU CONTEXTE, JAMAIS PAR `random()`.
        // `Collection::random()` et `inRandomOrder()` tirent hors de
        // `mt_srand()` — le premier via `random_int()`, le second côté SGBD.
        // La simulation n'était donc PAS reproductible malgré sa graine fixe :
        // deux exécutions du même code donnaient des trésoreries différentes
        // (constaté : −149 269 puis −3 696 184 sur la banque, à code
        // identique). Un jeu de démonstration irreproductible ne se débogue
        // pas, et un chiffre montré au client ne peut pas être rejoué.
        $solvables = $clients->where('credit_limit', '>', 0)->values();

        $client = $mode === 'credit'
            ? ($solvables->isEmpty() ? null : $solvables[$this->ctx->entre(0, $solvables->count() - 1)])
            : ($this->ctx->chance(55) ? $clients[$this->ctx->entre(0, $clients->count() - 1)] : null);

        if ($mode === 'credit' && ! $client) {
            $mode = 'especes';
        }

        $vente = Sale::create([
            'customer_id' => $client?->id,
            'payment_mode' => $mode,
            'subtotal' => $total,
            'discount' => 0,
            'total' => $total,
            'cash_received' => $mode === 'especes' ? $total : null,
            'change_due' => $mode === 'especes' ? 0 : null,
            'delivery_fee' => 0,
            'status' => 'validee',
            'mecef_status' => 'transmise',
            'mecef_qr_ref' => 'MECEF-'.strtoupper(substr(md5($jour->timestamp.$total), 0, 12)),
            'created_at' => $jour->addHours($this->ctx->entre(8, 17)),
            'updated_at' => $jour,
        ]);

        foreach ($lignes as $l) {
            SaleLine::create([
                'sale_id' => $vente->id,
                'product_id' => $l['produit']->id,
                // Ticket 14.44 — LA SIMULATION SUIVAIT UNE RÈGLE PLUS LÂCHE QUE
                // L'ÉCRAN RÉEL : `PosInterface::confirmWeightAdd()` EXIGE la
                // bande source pour tout produit lié à une espèce (contrôle de
                // rémanence vétérinaire), le seeder n'en imputait aucune. Le
                // Bilan Technico-Économique restait donc vide sur un jeu de
                // démonstration pourtant riche en ventes.
                'lot_id' => $this->bandeSource($l['produit']),
                'qty' => $l['qty'],
                'unit_price' => round($l['montant'] / $l['qty'], 2),
                'manual_total_amount' => $l['montant'],
                'is_manual_price' => true,
                'created_at' => $jour, 'updated_at' => $jour,
            ]);

            app(AdjustStockAction::class)->execute(
                $l['produit'], -$l['qty'], 'sale', $vente->id, $jour->toDateTime()
            );
        }

        app(CreditTreasuryForSaleAction::class)->execute($vente);

        if ($mode === 'credit' && $client) {
            Receivable::create([
                'customer_id' => $client->id,
                'sale_id' => $vente->id,
                'amount' => $total,
                // ⚠️ AUCUN PRÉ-REMPLISSAGE : les règlements sont enregistrés
                // ensuite par `reglerCreances()`, à travers la même Action que
                // l'écran. Écrire `amount_paid` directement aurait montré des
                // créances partiellement payées sans la moindre écriture
                // d'encaissement en face — exactement le défaut corrigé au
                // ticket 14.34.
                'amount_paid' => 0,
                'due_date' => $jour->addDays(30)->format('Y-m-d'),
                'status' => 'en_cours',
                'created_at' => $jour, 'updated_at' => $jour,
            ]);
        }

        app(RecordSaleAccountingEntryAction::class)->execute($vente->fresh('lines'));

        return true;
    }

    /**
     * Bande d'origine d'un produit vendu. Nulle pour tout produit sans espèce.
     *
     * ⚠️ CE CHOIX TIENT LIEU DU GESTE DU CAISSIER. Dans l'écran réel, la bande
     * est DÉSIGNÉE à la caisse — ce n'est pas une déduction du logiciel. La
     * simulation n'a personne pour la désigner : elle retient la plus ancienne
     * bande active de l'espèce, encore peuplée. Convention de simulation,
     * jamais une règle métier — aucun écran ne l'applique.
     *
     * ⚠️ `orderBy` EXPLICITE : sans lui, le SGBD ne garantit AUCUN ordre et la
     * simulation cesserait d'être reproductible d'une exécution à l'autre.
     */
    private function bandeSource(Product $produit): ?string
    {
        if (! $produit->species_id) {
            return null;
        }

        return LivestockLot::where('species_id', $produit->species_id)
            ->where('is_active', true)
            ->where('current_quantity', '>', 0)
            ->orderBy('created_date')
            ->orderBy('code')
            ->value('id');
    }

    /**
     * Ce que la ferme peut réellement vendre à cette date : uniquement des
     * produits effectivement en stock.
     *
     * @return array<int, string>
     */
    private function catalogueDuJour(): array
    {
        return Product::where('is_active', true)
            ->where('pricing_mode', 'fourchette')
            ->where('stock_qty', '>', 0)
            // Les INTRANTS ne se revendent pas : provende et médicaments sont
            // consommés par l'exploitation (ticket 14.36).
            ->whereNotIn('sku', ['ALI-001', 'ALI-002', 'ALI-003', 'ALI-004', 'ALI-005',
                'MED-001', 'MED-002', 'MED-003', 'MED-004'])
            // ⚠️ ORDRE EXPLICITE : sans `orderBy`, MySQL ne garantit rien et le
            // tirage `parmi()` ne portait pas sur la même liste d'une exécution
            // à l'autre — la simulation n'était donc pas reproductible malgré
            // sa graine fixe.
            ->orderBy('sku')
            ->pluck('sku')
            ->all();
    }

    /**
     * Encaissements de créances, par la même Action que l'écran
     * (`RecordSettlementAccountingEntryAction`, ticket 14.34).
     *
     * ⚠️ Trois sorts différents, parce qu'un portefeuille de créances réel n'a
     * jamais un seul visage : soldées, partiellement réglées, et impayées.
     * Un jeu où toutes seraient réglées viderait le suivi des créances et les
     * relances de leur objet ; un jeu où aucune ne le serait donnerait une
     * ferme qui n'encaisse jamais.
     */
    private function reglerCreances(): void
    {
        $caisse = $this->ctx->tresorerie('531');
        $action = app(\App\Actions\RecordSettlementAccountingEntryAction::class);

        if (! $caisse) {
            return;
        }

        foreach (Receivable::with('customer')->orderBy('created_at')->orderBy('id')->get() as $creance) {
            $part = match (true) {
                $this->ctx->chance(35) => 1.0,      // soldée
                $this->ctx->chance(45) => 0.5,      // partiellement réglée
                default => 0.0,                     // impayée
            };

            if ($part <= 0) {
                continue;
            }

            $montant = round((float) $creance->amount * $part, 2);

            // Encaissement daté APRÈS l'échéance de la vente, jamais avant.
            $date = \Carbon\CarbonImmutable::parse($creance->created_at)->addDays($this->ctx->entre(5, 40));

            if ($date->gt($this->ctx->fin)) {
                $date = $this->ctx->fin;
            }

            $creance->update([
                'amount_paid' => $montant,
                'status' => $part >= 1.0 ? 'soldee' : 'en_cours',
            ]);

            $caisse->increment('balance', $montant);

            $action->collectFromCustomer(
                $caisse, $montant, $creance->customer?->name, $creance->id, $date->format('Y-m-d')
            );
        }
    }

    /**
     * Retours et avoirs — quelques-uns seulement : un taux de retour élevé
     * décrirait une exploitation en difficulté.
     */
    private function creerAvoirs(): void
    {
        $ventes = Sale::whereNotNull('customer_id')
            ->where('status', 'validee')
            ->with('lines')
            ->orderBy('created_at')
            ->get()
            // Un retour sur 40 environ, réparti sur toute la période plutôt
            // que tiré au sort : sélection déterministe.
            ->filter(fn ($v, $i) => $i % 40 === 7)
            ->take(6);

        foreach ($ventes as $vente) {
            $ligne = $vente->lines->first();

            if (! $ligne) {
                continue;
            }

            $date = $vente->created_at->addDays($this->ctx->entre(1, 5));

            if ($date->gt($this->ctx->fin)) {
                continue;
            }

            $qte = 1;
            $montant = round((float) $ligne->manual_total_amount / max(1, (float) $ligne->qty) * $qte, 2);
            $decision = $this->ctx->chance(60) ? 'reintegre' : 'reforme';

            $avoir = CreditNote::create([
                'credit_note_number' => CreditNote::generateCreditNoteNumber(),
                'sale_id' => $vente->id,
                'product_id' => $ligne->product_id,
                'qty' => $qte,
                'amount' => $montant,
                'reason' => $this->ctx->parmi([
                    'Produit détérioré à la livraison',
                    'Erreur de quantité livrée',
                    'Sujet malade constaté par le client',
                    'Commande annulée par le client',
                ]),
                'decision' => $decision,
                'inspection_notes' => $decision === 'reforme' ? 'Sujet non récupérable — réformé.' : 'Produit sain, remis en stock.',
                'status' => $this->ctx->chance(70) ? 'traite' : 'en_attente',
                'created_at' => $date, 'updated_at' => $date,
            ]);

            if ($decision === 'reintegre') {
                $produit = Product::find($ligne->product_id);

                if ($produit) {
                    app(AdjustStockAction::class)->execute(
                        $produit, (float) $qte, 'credit_note', $avoir->id, $date->toDateTime()
                    );
                }
            }

            app(RecordCreditNoteAccountingEntryAction::class)->execute($avoir->load('product'));
        }
    }

    /** @param  \Illuminate\Support\Collection<int, Customer>  $clients */
    private function creerDevis($clients): void
    {
        foreach ([
            ['Fourniture de 200 poulets goliath vifs pour la fête de fin d\'année', 1_100_000, 'envoye'],
            ['Cages galvanisées 6 compartiments — 10 unités montées et livrées', 780_000, 'accepte'],
            ['Approvisionnement mensuel en œufs de table — 60 plateaux/semaine', 540_000, 'envoye'],
            ['Lot de 40 lapins vifs pour repeuplement', 320_000, 'refuse'],
            ['Formation pratique en cuniculture — 15 stagiaires', 450_000, 'brouillon'],
        ] as $i => [$description, $montant, $statut]) {
            $date = $this->ctx->fin->subDays(($i + 1) * 11);

            Quote::create([
                'quote_number' => 'DEV-2026-'.str_pad((string) ($i + 1), 3, '0', STR_PAD_LEFT),
                'customer_id' => $clients[$this->ctx->entre(0, $clients->count() - 1)]->id,
                'articles_description' => $description,
                'amount' => $montant,
                'tva_rate' => 0,
                'validity_days' => 30,
                'quote_date' => $date->format('Y-m-d'),
                'status' => $statut,
                'is_active' => true,
                'created_at' => $date, 'updated_at' => $date,
            ]);
        }
    }

    /** @param  \Illuminate\Support\Collection<int, Customer>  $clients */
    private function creerAvances($clients): void
    {
        foreach ($clients->where('credit_limit', '>', 0)->take(4) as $i => $client) {
            $date = $this->ctx->fin->subDays(($i + 1) * 17);

            CustomerAdvance::create([
                'customer_id' => $client->id,
                'amount' => $this->ctx->entre(5, 20) * 10_000,
                'amount_used' => 0,
                'advance_date' => $date->format('Y-m-d'),
                'is_active' => true,
                'created_at' => $date, 'updated_at' => $date,
            ]);
        }
    }

    /** Relances sur les créances réellement échues — jamais sur les autres. */
    private function creerRelances(): void
    {
        $echues = Receivable::whereDate('due_date', '<', $this->ctx->fin->format('Y-m-d'))
            ->whereColumn('amount_paid', '<', 'amount')
            ->limit(8)
            ->get();

        foreach ($echues as $creance) {
            $date = CarbonImmutable::parse($creance->due_date)->addDays($this->ctx->entre(3, 12));

            if ($date->gt($this->ctx->fin)) {
                continue;
            }

            CustomerReminder::create([
                'customer_id' => $creance->customer_id,
                'receivable_id' => $creance->id,
                'channel' => $this->ctx->parmi(['sms', 'whatsapp', 'email', 'courrier']),
                'reminder_date' => $date->format('Y-m-d'),
                'message' => 'Rappel amiable : solde de '
                    .number_format((float) $creance->amount - (float) $creance->amount_paid, 0, ',', ' ')
                    .' FCFA échu depuis le '.CarbonImmutable::parse($creance->due_date)->format('d/m/Y').'.',
                'created_at' => $date, 'updated_at' => $date,
            ]);
        }
    }
}
