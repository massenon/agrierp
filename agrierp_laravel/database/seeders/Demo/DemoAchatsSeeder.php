<?php

namespace Database\Seeders\Demo;

use App\Actions\AdjustStockAction;
use App\Actions\RecordPurchaseAccountingEntryAction;
use App\Models\Payable;
use App\Models\Product;
use App\Models\Purchase;
use App\Models\PurchaseLine;
use App\Models\PurchaseOrder;
use App\Models\PurchaseOrderLine;
use App\Models\Supplier;
use App\Models\TreasuryAccount;
use Illuminate\Database\Seeder;

/**
 * Ticket 14.31 (Sprint 14) — ACHATS de démonstration.
 *
 * ⚠️ CE SEEDER PASSE EN PREMIER APRÈS LES TIERS, ET CE N'EST PAS ARBITRAIRE :
 * le PMP se calcule exclusivement depuis `purchase_lines`
 * (`Product::computePmp()`). Sans historique d'achat, TOUTE la valorisation de
 * stock — Note 3 des États Financiers, tableau des stocks, synthèse par
 * filière — resterait vide, et les ventes ultérieures n'auraient aucun coût en
 * face. L'ordre des seeders porte donc une dépendance réelle, pas une
 * préférence de lecture.
 *
 * ⚠️ SÉQUENCE IDENTIQUE À CELLE DE `EnregistrerAchat::submitAchat()` :
 * `Purchase` + lignes → `AdjustStockAction` par ligne → décrément de
 * trésorerie → `Payable` si règlement partiel → `RecordPurchaseAccountingEntryAction`.
 * Recopier ces étapes plutôt qu'insérer les lignes à la main est ce qui garantit
 * que le stock, la trésorerie, la dette fournisseur et le grand livre racontent
 * la même histoire — et cela exerce le code réel au passage.
 *
 * 🔴→✅ GAP CORRIGÉ AU TICKET 14.36 : le catalogue ne contenait QUE des
 * produits vendables, aucun produit d'ENTRÉE. Provende et produits
 * vétérinaires ont rejoint `ProductsSeeder` — c'est du référentiel, pas de la
 * donnée de démonstration. Ce seeder se contente désormais de les ACHETER,
 * aux SKU et à l'unité du prototype (`ALI-001` « Aliment ponte 25kg », comptés
 * en SACS de 25 kg).
 */
class DemoAchatsSeeder extends Seeder
{
    public function __construct(private DemoContexte $ctx) {}

    public function run(): void
    {
        $this->appliquerTvaSurTransformes();

        $achats = 0;
        $caisse = $this->ctx->tresorerie('531');
        $banque = $this->ctx->tresorerie('521101');

        $provenderie = Supplier::where('name', 'Provenderie du Plateau')->firstOrFail();
        $veterinaire = Supplier::where('name', 'SODIVET Bénin')->firstOrFail();
        $couvoir = Supplier::where('name', 'Couvoir Avicole de Kétou')->firstOrFail();
        $quincaillerie = Supplier::where('name', 'Quincaillerie ADJOVI')->firstOrFail();

        // --- Provende : un réapprovisionnement par mois, le 3 ---------------
        for ($mois = $this->ctx->debut; $mois->lte($this->ctx->fin); $mois = $mois->addMonth()) {
            $date = $mois->startOfMonth()->addDays(2);

            if ($date->gt($this->ctx->fin)) {
                break;
            }

            $lignes = [];

            // ⚠️ QUANTITÉS CALÉES SUR LA CONSOMMATION RÉELLE des bandes, pas
            // sur un chiffre rond. 200 pondeuses à 110 g/jour consomment 22 kg
            // soit ~27 sacs par mois ; les acheter 40 faisait gonfler le stock
            // à 162 sacs en cinq mois — une exploitation qui immobilise six
            // mois de provende dans son magasin.
            foreach (['ALI-001' => 28, 'ALI-002' => 20, 'ALI-003' => 2, 'ALI-004' => 12, 'ALI-005' => 18] as $sku => $sacs) {
                $produit = $this->ctx->produit($sku);

                // ⚠️ Quantité en SACS, unité réelle du produit — plus de
                // conversion en kilos : le catalogue compte désormais en sacs
                // de 25 kg, comme le prototype (ticket 14.36).
                $quantite = $sacs + $this->ctx->entre(-2, 4);

                $lignes[] = ['product_id' => $produit->id, 'qty' => $quantite, 'unit_price' => (float) $produit->price_min];
            }

            // Règlement partiel un mois sur trois : c'est ce qui alimente
            // réellement le suivi des dettes fournisseurs et l'écriture à
            // quatre lignes (trésorerie + 401).
            $partiel = $this->ctx->entre(1, 3) === 1;

            // ⚠️ PROVENDE PAYÉE EN ESPÈCES, depuis la caisse.
            //
            // C'est l'usage réel du bassin d'Ikpinlè, et c'est surtout ce qui
            // garde la trésorerie cohérente : les ventes alimentent la CAISSE
            // (58 % au comptant) et le Mobile Money, presque jamais la banque.
            // Faire porter à la banque 5,4 M FCFA d'aliment sur cinq mois la
            // faisait plonger à −3,3 M pendant que la caisse débordait — un
            // solde impossible, faute de virement interne entre comptes.
            //
            // 🔴 GAP RÉEL SIGNALÉ : l'application n'offre AUCUN transfert entre
            // comptes de trésorerie. Une ferme qui encaisse en espèces et paie
            // par virement ne peut pas modéliser son dépôt en banque.
            // ⚠️ ON PAIE DEPUIS LE COMPTE QUI A LES FONDS — c'est ce que fait
            // un gérant, et c'est la seule règle qui tienne ici.
            //
            // 🔴 GAP RÉEL : l'application n'offre AUCUN VIREMENT INTERNE entre
            // comptes de trésorerie. Une ferme qui encaisse en espèces et par
            // Mobile Money ne peut donc pas alimenter sa banque, ni l'inverse.
            // Chaque compte vit isolé de ses recettes propres. Faire porter la
            // provende à un compte fixe le vidait mécaniquement, quel que soit
            // celui choisi : la banque à −3,3 M, puis la caisse à −262 000,
            // puis le Mobile Money à −154 000. Répartir selon le solde
            // disponible est le contournement le plus honnête tant que le
            // virement interne n'existe pas.
            $achats += $this->enregistrer(
                $provenderie, $lignes, $date, null, null, $partiel ? 0.6 : 1.0
            );
        }

        // --- Produits vétérinaires : tous les 2 mois ------------------------
        for ($mois = $this->ctx->debut; $mois->lte($this->ctx->fin); $mois = $mois->addMonths(2)) {
            $date = $mois->startOfMonth()->addDays(11);

            if ($date->gt($this->ctx->fin)) {
                break;
            }

            $produit = $this->ctx->produit('MED-002');

            $achats += $this->enregistrer(
                $veterinaire,
                [['product_id' => $produit->id, 'qty' => $this->ctx->entre(8, 18), 'unit_price' => (float) $produit->price_min]],
                $date, null, null, 1.0
            );
        }

        // --- Poussins d'un jour : deux bandes lancées ----------------------
        foreach ([$this->ctx->debut->addDays(6), $this->ctx->debut->addMonths(2)->addDays(9)] as $date) {
            if ($date->gt($this->ctx->fin)) {
                continue;
            }

            $poussin = $this->ctx->produit('AVI-003');

            $achats += $this->enregistrer(
                $couvoir,
                [['product_id' => $poussin->id, 'qty' => 250, 'unit_price' => 520]],
                $date, null, null, 1.0
            );
        }

        // --- Équipement : cages, une fois ----------------------------------
        $date = $this->ctx->debut->addMonths(1)->addDays(17);

        if ($date->lte($this->ctx->fin)) {
            $cage = $this->ctx->produit('EQP-002');

            $achats += $this->enregistrer(
                $quincaillerie,
                [['product_id' => $cage->id, 'qty' => 4, 'unit_price' => 78_000]],
                $date, null, null, 0.5
            );
        }

        $this->creerBonDeCommandeEnCours($provenderie);

        $this->command?->info('  Achats : '.$achats.' achats, '.Payable::count().' dettes fournisseurs.');
    }

    /**
     * Enregistre un achat exactement comme le fait l'écran, dans le même ordre.
     *
     * @param  array<int, array{product_id: string, qty: float, unit_price: float}>  $lignes
     * @param  float  $ratioRegle  part réellement payée (1.0 = solde)
     */
    private function enregistrer(
        Supplier $fournisseur,
        array $lignes,
        \Carbon\CarbonImmutable $date,
        ?TreasuryAccount $tresorerie,
        ?string $modeReglement,
        float $ratioRegle,
    ): int {
        // Compte non imposé : on retient celui qui porte le solde le plus
        // élevé à cet instant, et le mode de règlement s'en déduit.
        $tresorerie ??= $this->ctx->compteSolvable(round($this->totalDesLignes($lignes) * $ratioRegle, 2));

        if (! $tresorerie) {
            return 0;
        }

        $modeReglement ??= match ($tresorerie->account_code) {
            '531' => 'especes',
            '521201' => 'mobile_money',
            default => 'virement',
        };

        $total = round($this->totalDesLignes($lignes), 2);
        $regle = round($total * $ratioRegle, 2);

        $achat = Purchase::create([
            'supplier_id' => $fournisseur->id,
            'payment_mode' => $modeReglement,
            'total' => $total,
            'purchase_date' => $date->format('Y-m-d'),
            'created_at' => $date, 'updated_at' => $date,
        ]);

        foreach ($lignes as $l) {
            PurchaseLine::create([
                'purchase_id' => $achat->id,
                'product_id' => $l['product_id'],
                'qty' => $l['qty'],
                'unit_price' => $l['unit_price'],
                'created_at' => $date, 'updated_at' => $date,
            ]);

            $produit = Product::find($l['product_id']);

            if ($produit) {
                // ⚠️ Date du mouvement forcée à la date d'achat : sans elle,
                // tout l'historique de stock se tasserait sur aujourd'hui et le
                // journal des mouvements ne montrerait aucune chronologie.
                app(AdjustStockAction::class)->execute(
                    $produit, (float) $l['qty'], 'purchase', $achat->id, $date->toDateTime()
                );
            }
        }

        if ($regle > 0) {
            $tresorerie->decrement('balance', $regle);
        }

        if ($regle < $total) {
            Payable::create([
                'supplier_id' => $fournisseur->id,
                'purchase_id' => $achat->id,
                'amount' => $total,
                'amount_paid' => $regle,
                'due_date' => $date->addDays(30)->format('Y-m-d'),
                'status' => 'en_cours',
                'created_at' => $date, 'updated_at' => $date,
            ]);
        }

        app(RecordPurchaseAccountingEntryAction::class)
            ->execute($achat->fresh('lines'), $tresorerie->id, $regle);

        return 1;
    }

    /** @param  array<int, array{qty: float, unit_price: float}>  $lignes */
    private function totalDesLignes(array $lignes): float
    {
        $total = 0.0;

        foreach ($lignes as $l) {
            $total += $l['qty'] * $l['unit_price'];
        }

        return $total;
    }

    /** Compte comptable du compte de trésorerie réellement sélectionné. */
    private function compteDeTresorerie(TreasuryAccount $tresorerie): ?\App\Models\ChartOfAccount
    {
        return $tresorerie->account_code
            ? \App\Models\ChartOfAccount::where('code', $tresorerie->account_code)->first()
            : null;
    }

    /**
     * 🔴→✅ `ProductsSeeder` pose `tva_rate => 0` sur les 18 produits, sans
     * aucune distinction. La Déclaration TVA — exigence impérative du module
     * M14 (CGI Bénin art. 162 bis et 1084-40) — était donc structurellement
     * vide sur données réelles, quel que soit le chiffre d'affaires.
     *
     * La règle appliquée ici est celle que le code énonce déjà lui-même, dans
     * `VatDeclarationService` : « des lignes à 0% (produits bruts, exonérés) et
     * à 18% (transformés/services) ». Seuls les TRANSFORMÉS et les ÉQUIPEMENTS
     * passent à 18 % ; les produits bruts (sujets vifs, œufs, légumes) restent
     * exonérés. Rien d'inventé — mais à faire valider par le Cabinet FAGUEZ,
     * la ventilation par produit ne figurant dans aucun document.
     */
    private function appliquerTvaSurTransformes(): void
    {
        Product::whereIn('sku', ['AVI-005', 'AVI-006', 'TRA-001', 'EQP-001', 'EQP-002', 'EQP-003'])
            ->update(['tva_rate' => 18]);
    }

    /** Un bon de commande encore ouvert — l'écran ne doit pas être vide. */
    private function creerBonDeCommandeEnCours(Supplier $fournisseur): void
    {
        $bon = PurchaseOrder::create([
            'supplier_id' => $fournisseur->id,
            'expected_delivery_date' => $this->ctx->fin->addDays(6)->format('Y-m-d'),
            'status' => 'envoye',
            'created_at' => $this->ctx->fin->subDays(3),
            'updated_at' => $this->ctx->fin->subDays(3),
        ]);

        foreach (['ALI-001' => 40, 'ALI-004' => 20] as $sku => $qte) {   // en sacs
            $produit = $this->ctx->produit($sku);

            PurchaseOrderLine::create([
                'purchase_order_id' => $bon->id,
                'product_id' => $produit->id,
                'qty' => $qte,
                'estimated_unit_price' => (float) $produit->price_min,
            ]);
        }
    }
}
