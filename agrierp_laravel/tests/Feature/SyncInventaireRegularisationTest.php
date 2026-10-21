<?php

namespace Tests\Feature;

use App\Actions\AdjustStockAction;
use App\Livewire\Stocks\GestionStocks;
use App\Livewire\Ventes\PosInterface;
use App\Models\AccountingEntryLine;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Purchase;
use App\Models\PurchaseLine;
use App\Models\StockMovement;
use App\Models\Supplier;
use App\Models\TreasuryAccount;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket S-T12 — LE MOUVEMENT FAIT AVANT UN COMPTAGE MAIS ARRIVÉ APRÈS LUI (reste de S-T10).
 *
 * Le comptage d'un instant T est la vérité physique à T. Une vente faite avant T sur une caisse restée hors ligne, un
 * achat du poste fait avant T, une vente antidatée saisie au web après un inventaire (15.30) : les rayons comptés les
 * reflétaient déjà. Avant ce ticket, le serveur les décomptait (ou les entrait) EN PLUS du comptage — le stock
 * finissait faux, sans erreur, et la perte d'inventaire restait au journal alors que les sacs avaient été vendus.
 *
 * Règle (`InventaireAuComptageService::compenserMouvementAnterieur`, appelée par `AdjustStockAction`) : le mouvement
 * est gardé à SA date ; une régularisation d'inventaire de sens opposé, datée du comptage, recalcule l'écart de ce
 * comptage ; la perte au journal suit (reclassée en achats consommés quand le « manquant » était une vente).
 *
 * Toutes les valeurs attendues sont calculées à la main dans les commentaires. PMP = 18 000 F.
 */
class SyncInventaireRegularisationTest extends TestCase
{
    use RefreshDatabase;

    private Product $produit;

    private User $admin;

    private Supplier $fournisseur;

    private TreasuryAccount $caisse;

    protected function setUp(): void
    {
        parent::setUp();

        config(['app.timezone' => 'Africa/Porto-Novo']);
        date_default_timezone_set('Africa/Porto-Novo');
        Carbon::setTestNow('2026-10-19 08:00:00');

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $this->admin = User::create([
            'name' => 'Administrateur', 'username' => 'admin', 'email' => 'dg@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->admin->assignRole('admin');

        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
        foreach ([
            ['601', "Achats d'aliments", 6], ['657', 'Pertes sur stocks', 6], ['401', 'Fournisseurs', 4],
            ['411', 'Clients', 4], ['443', 'TVA collectée', 4], ['531', 'Caisse', 5], ['701', 'Ventes', 7],
        ] as [$code, $libelle, $classe]) {
            ChartOfAccount::firstOrCreate(['code' => $code], ['label' => $libelle, 'class' => $classe, 'is_active' => true]);
        }
        $this->caisse = TreasuryAccount::create([
            'type' => 'caisse', 'label' => 'Caisse Principale', 'account_code' => '531', 'balance' => 1_000_000, 'is_active' => true,
        ]);

        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);
        $this->produit = Product::create([
            'sku' => 'ALI-001', 'name' => 'Provende ponte', 'category_id' => $categorie->id, 'unit' => 'sac',
            'pricing_mode' => 'fourchette', 'price_min' => 20_000, 'price_max' => 25_000, 'tva_rate' => 0,
            'stock_qty' => 100, 'is_active' => true,
        ]);

        // PMP = 18 000 F (100 sacs achetés à 18 000 F le 01/10).
        $this->fournisseur = Supplier::create(['name' => 'Provenderie du Sud', 'phone' => '97000010', 'is_active' => true]);
        $achat = Purchase::create([
            'supplier_id' => $this->fournisseur->id, 'payment_mode' => 'especes', 'total' => 1_800_000, 'purchase_date' => '2026-10-01',
        ]);
        PurchaseLine::create(['purchase_id' => $achat->id, 'product_id' => $this->produit->id, 'qty' => 100, 'unit_price' => 18_000]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function envoyer(array $corps)
    {
        return $this->actingAs($this->admin, 'sanctum')->postJson('/api/sync/push', $corps)->assertOk();
    }

    /** Le comptage du bureau (S-T10) : quantité comptée et instant du comptage. */
    private function comptage(float $compte, string $instant, string $ref = 'inv-1'): array
    {
        return [
            'client_ref' => $ref, 'product_id' => $this->produit->id, 'type' => 'sortie', 'quantity' => 1,
            'reference_type' => 'inventaire', 'reason' => 'Vol / Disparition',
            'counted_quantity' => $compte, 'counted_at' => $instant,
        ];
    }

    /** Une vente d'une caisse : `sold_at` est l'instant de la vente au poste. */
    private function vente(string $id, float $qte, string $soldAt): array
    {
        return [
            'id' => $id, 'payment_mode' => 'especes', 'subtotal' => $qte * 22_000, 'discount' => 0,
            'total' => $qte * 22_000, 'status' => 'validee', 'sold_at' => $soldAt,
            'lines' => [[
                'product_id' => $this->produit->id, 'qty' => $qte, 'unit_price' => 22_000, 'manual_total_amount' => $qte * 22_000,
            ]],
        ];
    }

    private function achat(string $id, float $qte, ?string $achete = null, string $jour = '2026-10-19'): array
    {
        return array_filter([
            'id' => $id, 'supplier_id' => $this->fournisseur->id, 'payment_mode' => 'especes',
            'treasury_account_id' => $this->caisse->id, 'amount_paid' => $qte * 18_000, 'purchase_date' => $jour,
            'purchased_at' => $achete,
            'lines' => [['product_id' => $this->produit->id, 'qty' => $qte, 'unit_price' => 18_000]],
        ], fn ($v) => $v !== null);
    }

    private function stock(): float
    {
        return (float) $this->produit->fresh()->stock_qty;
    }

    /** Solde débiteur du 657 (pertes sur stocks), toutes écritures confondues. */
    private function pertes(): float
    {
        $compte = ChartOfAccount::where('code', '657')->value('id');

        return round((float) AccountingEntryLine::where('account_id', $compte)->sum('debit')
            - (float) AccountingEntryLine::where('account_id', $compte)->sum('credit'), 2);
    }

    /** Stock reconstruit depuis le grand livre (ouverture 100 sans mouvement). */
    private function grandLivre(): float
    {
        return 100 + (float) StockMovement::where('product_id', $this->produit->id)->get()
            ->sum(fn ($m) => $m->type === 'entree' ? (float) $m->quantity : -(float) $m->quantity);
    }

    /**
     * ⚠️⚠️ LE CAS DU TICKET. 09h00 : la caisse 2, hors ligne, vend 2 sacs (le serveur n'en sait rien : 100). 10h30 : le
     * bureau compte 95 sacs — les 2 vendus sont partis, 3 ont disparu. 11h00 : le comptage arrive (serveur : écart
     * 95 − 100 = −5 ; perte 5 × 18 000 = 90 000 F). 15h00 : la vente de 09h00 arrive enfin.
     *
     * Attendu : stock 95 (les rayons comptés), pas 93 ; la vente au grand livre à 09h00, une régularisation +2 datée
     * de 10h30 ; perte nette 3 × 18 000 = 54 000 F (2 sacs « manquants » étaient vendus : reclassés, −36 000 F).
     */
    public function test_une_vente_hors_ligne_anterieure_au_comptage_arrivee_apres_lui_n_est_pas_decomptee_en_plus(): void
    {
        Carbon::setTestNow('2026-10-19 11:00:00');
        $this->envoyer(['stock_adjustments' => [$this->comptage(95, '2026-10-19T10:30:00+01:00')]]);
        $this->assertSame(95.0, $this->stock());
        $this->assertSame(90000.0, $this->pertes());

        Carbon::setTestNow('2026-10-19 15:00:00');
        $id = (string) Str::uuid();
        $this->envoyer(['sales' => [$this->vente($id, 2, '2026-10-19T09:00:00+01:00')]])->assertJsonPath('sales.accepted.0', $id);

        $this->assertSame(95.0, $this->stock(), 'le comptage reflétait déjà la vente de 09h00');
        $this->assertSame($this->grandLivre(), $this->stock(), 'stock = grand livre');
        $vente = StockMovement::where('reference_type', 'sale')->where('reference_id', $id)->sole();
        $this->assertSame('2026-10-19 09:00:00', $vente->movement_date->format('Y-m-d H:i:s'), 'la vente reste à sa date');
        $regularisation = StockMovement::where('reference_type', 'inventaire')->where('reference_id', $vente->id)->sole();
        $this->assertSame('entree', $regularisation->type);
        $this->assertSame(2.0, (float) $regularisation->quantity);
        $this->assertSame('2026-10-19 10:30:00', $regularisation->movement_date->format('Y-m-d H:i:s'), 'datée du comptage');
        $this->assertStringContainsString('vente du 19/10/2026 09:00', $regularisation->reason);
        $this->assertSame(54000.0, $this->pertes(), 'la perte est celle des 3 sacs disparus');
        $this->assertSame(1, AuditLog::where('action', 'stock.inventaire_regularise')->count());

        // Le renvoi de la vente (accusé perdu) ne rejoue rien, régularisation comprise.
        $this->envoyer(['sales' => [$this->vente($id, 2, '2026-10-19T09:00:00+01:00')]]);
        $this->assertSame(95.0, $this->stock());
        $this->assertSame(1, StockMovement::where('reference_type', 'inventaire')->where('reference_id', $vente->id)->count());
    }

    /**
     * Une vente POSTÉRIEURE au comptage, arrivée après lui : elle compte normalement. 10h30 comptage 95 ; vente de
     * 12h00 (2 sacs) reçue à 15h00 → 93, aucune régularisation.
     */
    public function test_une_vente_posterieure_au_comptage_compte_normalement(): void
    {
        Carbon::setTestNow('2026-10-19 11:00:00');
        $this->envoyer(['stock_adjustments' => [$this->comptage(95, '2026-10-19T10:30:00+01:00')]]);

        Carbon::setTestNow('2026-10-19 15:00:00');
        $this->envoyer(['sales' => [$this->vente((string) Str::uuid(), 2, '2026-10-19T12:00:00+01:00')]]);

        $this->assertSame(93.0, $this->stock());
        $this->assertSame(0, AuditLog::where('action', 'stock.inventaire_regularise')->count());
        $this->assertSame(90000.0, $this->pertes());
    }

    /**
     * ⚠️ UN ACHAT DU POSTE est daté de l'achat (`purchased_at`), plus de sa réception. 09h00 : achat de 10 sacs au poste
     * hors ligne (rangés aussitôt). 10h30 : le bureau compte 110 (le serveur : 100) — écart +10, un excédent, sans
     * écriture. 15h00 : l'achat arrive.
     *
     * Attendu : 110, pas 120 ; l'entrée au grand livre à 09h00 ; régularisation −10 à 10h30 ; aucune perte (l'écart
     * recalculé est nul). Avant ce ticket : l'achat daté de 15h00, compté en plus du comptage.
     */
    public function test_un_achat_du_poste_anterieur_au_comptage_arrive_apres_lui_n_entre_pas_deux_fois(): void
    {
        Carbon::setTestNow('2026-10-19 11:00:00');
        $this->envoyer(['stock_adjustments' => [$this->comptage(110, '2026-10-19T10:30:00+01:00')]]);
        $this->assertSame(110.0, $this->stock());

        Carbon::setTestNow('2026-10-19 15:00:00');
        $id = (string) Str::uuid();
        $this->envoyer(['purchases' => [$this->achat($id, 10, '2026-10-19T08:00:00Z')]])->assertJsonPath('purchases.accepted.0', $id);

        $this->assertSame(110.0, $this->stock());
        $this->assertSame($this->grandLivre(), $this->stock());
        $entree = StockMovement::where('reference_type', 'purchase')->where('reference_id', $id)->sole();
        $this->assertSame('2026-10-19 09:00:00', $entree->movement_date->format('Y-m-d H:i:s'), '08h00 UTC = 09h00 au Bénin');
        $this->assertSame('sortie', StockMovement::where('reference_type', 'inventaire')->where('reference_id', $entree->id)->sole()->type);
        $this->assertSame(0.0, $this->pertes());
    }

    /**
     * L'achat antérieur qui CREUSE un manquant : le comptage de 10h30 trouve 95 contre 100 (perte 5 = 90 000 F) ; un
     * achat de 10 sacs fait à 09h00 arrive à 15h00 → le stock à 10h30 était 110, l'écart réel −15. Stock 95, perte
     * 15 × PMP. PMP après l'achat : (100 × 18 000 + 10 × 18 000) / 110 = 18 000 F → 270 000 F.
     */
    public function test_un_achat_anterieur_qui_creuse_le_manquant_ajoute_la_perte(): void
    {
        Carbon::setTestNow('2026-10-19 11:00:00');
        $this->envoyer(['stock_adjustments' => [$this->comptage(95, '2026-10-19T10:30:00+01:00')]]);

        Carbon::setTestNow('2026-10-19 15:00:00');
        $this->envoyer(['purchases' => [$this->achat((string) Str::uuid(), 10, '2026-10-19T09:00:00+01:00')]]);

        $this->assertSame(95.0, $this->stock());
        $this->assertSame(270000.0, $this->pertes());
    }

    /**
     * L'achat et le comptage dans le MÊME envoi (le serveur traite les achats avant les ajustements) : l'achat de 09h00
     * est au grand livre quand le comptage de 10h30 est évalué → stock à 10h30 = 110, écart 105 − 110 = −5 ; aucune
     * régularisation ; final 105.
     */
    public function test_achat_et_comptage_du_meme_envoi(): void
    {
        Carbon::setTestNow('2026-10-19 15:00:00');
        $this->envoyer([
            'purchases' => [$this->achat((string) Str::uuid(), 10, '2026-10-19T09:00:00+01:00')],
            'stock_adjustments' => [$this->comptage(105, '2026-10-19T10:30:00+01:00')],
        ]);

        $this->assertSame(105.0, $this->stock());
        $this->assertSame(0, AuditLog::where('action', 'stock.inventaire_regularise')->count());
        $this->assertSame(90000.0, $this->pertes());
    }

    /**
     * Le PREMIER comptage qui suit le mouvement est régularisé. Comptages le 18 à 10h (98) et le 19 à 10h30 (95) ;
     * une vente de 3 sacs du 17 arrive le 19 à 15h → régularisation +3 au 18 à 10h ; le comptage du 19, parti du
     * stock du 18, n'est pas touché ; final 95.
     */
    public function test_le_premier_comptage_apres_le_mouvement_est_regularise(): void
    {
        Carbon::setTestNow('2026-10-18 11:00:00');
        $this->envoyer(['stock_adjustments' => [$this->comptage(98, '2026-10-18T10:00:00+01:00', 'inv-18')]]);
        Carbon::setTestNow('2026-10-19 11:00:00');
        $this->envoyer(['stock_adjustments' => [$this->comptage(95, '2026-10-19T10:30:00+01:00', 'inv-19')]]);

        Carbon::setTestNow('2026-10-19 15:00:00');
        $this->envoyer(['sales' => [$this->vente((string) Str::uuid(), 3, '2026-10-17T16:00:00+01:00')]]);

        $this->assertSame(95.0, $this->stock());
        $regularisation = StockMovement::where('reference_type', 'inventaire')->whereNotIn('reference_id', ['inv-18', 'inv-19'])->sole();
        $this->assertSame('2026-10-18 10:00:00', $regularisation->movement_date->format('Y-m-d H:i:s'));
        $this->assertSame($this->grandLivre(), $this->stock());
    }

    /**
     * ⚠️ Un achat d'un poste ANCIEN (sans `purchased_at`) daté d'un jour passé est placé à ce JOUR seul (minuit) ; le
     * jour même d'un comptage, il le SUIT (son heure n'est pas connue, il est enregistré après) — la règle des dates
     * seules de S-T10. Comptage le 19 à 10h30 (95) ; achat « du 19 » reçu à 15h → 105, sans régularisation. Le même
     * achat « du 18 » précède le comptage → régularisé → 95.
     */
    public function test_un_achat_date_du_seul_jour(): void
    {
        Carbon::setTestNow('2026-10-19 11:00:00');
        $this->envoyer(['stock_adjustments' => [$this->comptage(95, '2026-10-19T10:30:00+01:00')]]);

        Carbon::setTestNow('2026-10-19 15:00:00');
        $duJour = (string) Str::uuid();
        $this->envoyer(['purchases' => [$this->achat($duJour, 10)]]);
        $this->assertSame(105.0, $this->stock());
        $this->assertSame('2026-10-19 15:00:00', StockMovement::where('reference_id', $duJour)->sole()->movement_date->format('Y-m-d H:i:s'),
            'achat du jour sans instant : reçu maintenant, comme avant');

        $veille = (string) Str::uuid();
        $this->envoyer(['purchases' => [$this->achat($veille, 10, null, '2026-10-18')]]);
        $this->assertSame('2026-10-18 00:00:00', StockMovement::where('reference_id', $veille)->sole()->movement_date->format('Y-m-d H:i:s'));
        $this->assertSame(105.0, $this->stock(), 'l\'achat de la veille était dans les rayons comptés : régularisé');
    }

    /**
     * Un instant d'achat qui ne tombe pas le jour de `purchase_date` n'est pas cru : le jour seul fait foi.
     * Un instant dans le futur est borné à la réception.
     */
    public function test_un_instant_d_achat_incoherent_ou_futur(): void
    {
        Carbon::setTestNow('2026-10-19 15:00:00');
        $incoherent = (string) Str::uuid();
        $futur = (string) Str::uuid();
        $this->envoyer(['purchases' => [
            $this->achat($incoherent, 1, '2026-10-19T09:00:00+01:00', '2026-10-17'),
            $this->achat($futur, 1, '2026-10-19T18:00:00+01:00'),
        ]]);

        $this->assertSame('2026-10-17 00:00:00', StockMovement::where('reference_id', $incoherent)->sole()->movement_date->format('Y-m-d H:i:s'));
        $this->assertSame('2026-10-19 15:00:00', StockMovement::where('reference_id', $futur)->sole()->movement_date->format('Y-m-d H:i:s'));
    }

    /**
     * ⚠️⚠️ LA MÊME RÈGLE AU WEB (doctrine, article 5 : le web est le maître). 10h00 : inventaire au web, Gestion des Stocks
     * — 95 comptés contre 100 (perte 90 000 F). 15h00 : la caisse web saisit une vente d'HIER de 2 sacs (15.30) : le
     * comptage d'aujourd'hui la reflétait. Stock 95 ; perte 54 000 F. Avant ce ticket : 93.
     */
    public function test_au_web_une_vente_antidatee_apres_un_inventaire(): void
    {
        Carbon::setTestNow('2026-10-19 10:00:00');
        Livewire::actingAs($this->admin)->test(GestionStocks::class)
            ->set('adjProductId', $this->produit->id)
            ->set('adjPhysical', 95)
            ->set('adjReason', 'Vol / Disparition')
            ->call('validateAdjustment');
        $this->assertSame(95.0, $this->stock());

        Carbon::setTestNow('2026-10-19 15:00:00');
        Livewire::actingAs($this->admin)->test(PosInterface::class)
            ->set('dateVente', '2026-10-18')
            ->call('selectProduct', $this->produit->id)
            ->set('weightQty', 2)
            ->set('weightPrice', 44_000)
            ->call('confirmWeightAdd')
            ->set('paymentMode', 'especes')
            ->set('cashReceived', 44_000)
            ->call('validateSale');

        $this->assertSame(1, StockMovement::where('reference_type', 'sale')->count(), 'la vente est enregistrée');
        $this->assertSame(95.0, $this->stock());
        $this->assertSame($this->grandLivre(), $this->stock());
        $this->assertSame(54000.0, $this->pertes());
    }

    /** Au web, une vente du jour (non antidatée) après l'inventaire compte normalement : 95 − 2 = 93. */
    public function test_au_web_une_vente_du_jour_apres_un_inventaire_compte(): void
    {
        Carbon::setTestNow('2026-10-19 10:00:00');
        Livewire::actingAs($this->admin)->test(GestionStocks::class)
            ->set('adjProductId', $this->produit->id)->set('adjPhysical', 95)->set('adjReason', 'Casse')
            ->call('validateAdjustment');

        Carbon::setTestNow('2026-10-19 15:00:00');
        Livewire::actingAs($this->admin)->test(PosInterface::class)
            ->call('selectProduct', $this->produit->id)
            ->set('weightQty', 2)->set('weightPrice', 44_000)->call('confirmWeightAdd')
            ->set('paymentMode', 'especes')->set('cashReceived', 44_000)
            ->call('validateSale');

        $this->assertSame(93.0, $this->stock());
        $this->assertSame(0, AuditLog::where('action', 'stock.inventaire_regularise')->count());
    }

    /**
     * Un mouvement à la seconde même du comptage le SUIT (enregistré après lui) ; un ajout « du jour » le jour du
     * comptage aussi (règle des dates seules). Ni l'un ni l'autre n'est régularisé : 95 − 1 + 30 = 124.
     */
    public function test_meme_seconde_et_date_seule_du_jour_suivent_le_comptage(): void
    {
        Carbon::setTestNow('2026-10-19 11:00:00');
        $this->envoyer(['stock_adjustments' => [$this->comptage(95, '2026-10-19T10:30:00+01:00')]]);

        Carbon::setTestNow('2026-10-19 15:00:00');
        app(AdjustStockAction::class)->execute($this->produit->fresh(), -1, 'sale', (string) Str::uuid(), Carbon::parse('2026-10-19 10:30:00'));
        app(AdjustStockAction::class)->execute($this->produit->fresh(), 30, 'manual_addition', null, Carbon::parse('2026-10-19'));

        $this->assertSame(124.0, $this->stock());
        $this->assertSame(0, AuditLog::where('action', 'stock.inventaire_regularise')->count());
    }
}
