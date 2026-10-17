<?php

namespace Tests\Feature;

use App\Actions\RecordSaleAccountingEntryAction;
use App\Livewire\Dashboard\Index as Dashboard;
use App\Livewire\Facturation\Facturation;
use App\Livewire\Rapports\RecettesDepenses;
use App\Livewire\Ventes\HistoriqueVentes;
use App\Livewire\Ventes\ProfileClient;
use App\Livewire\Ventes\RetoursAvoirs;
use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\CreditNote;
use App\Models\Customer;
use App\Models\FiscalYear;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\Sale;
use App\Models\SaleLine;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Services\VatDeclarationService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.31 — LES VENTES SE DATENT SUR `sold_at ?? created_at` PARTOUT.
 *
 * Jusqu'ici seuls l'écriture comptable, la rémanence et le mouvement de stock
 * (15.30) lisaient la vraie date de la vente. Les rapports, le tableau de bord,
 * l'historique, la déclaration de TVA, la facturation, la fiche client et le
 * tirage lisaient `created_at`, la date d'ENREGISTREMENT : une vente du 30/09
 * saisie le 14/10 tombait dans le chiffre d'affaires d'octobre, et sa TVA dans
 * la déclaration d'octobre alors que son écriture comptable est en septembre.
 * Aucune erreur levée : seuls les chiffres étaient faux.
 *
 * Jeu d'essai (date figée au 14/10/2026), trois ventes enregistrées le 14/10 :
 *   A — vendue le 30/09 (rétroactive, mois précédent)   1 000
 *   B — sans `sold_at` (historique / ancien poste)      2 000  → daté du 14/10
 *   C — vendue le 10/10 (rétroactive, même mois)        4 000
 */
class VentesDateEffectiveTest extends TestCase
{
    use RefreshDatabase;

    private Sale $a;

    private Sale $b;

    private Sale $c;

    private Customer $client;

    private Product $produit;

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow('2026-10-14 12:00:00');

        foreach (['view-ventes', 'manage-ventes'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('caissier', 'web');
        $role->givePermissionTo(['view-ventes', 'manage-ventes']);
        $user = User::create(['name' => 'Caissière', 'username' => 'caisse', 'email' => 'de@olouwachegoun.bj', 'password' => bcrypt('AgriERP@2026'), 'is_active' => true]);
        $user->assignRole($role);
        $this->actingAs($user);

        $this->client = Customer::create(['name' => 'GBAGUIDI Solange', 'phone' => '+22997000000', 'is_active' => true]);
        $categorie = ProductCategory::create(['label' => 'Test', 'is_active' => true]);
        $this->produit = Product::create([
            'sku' => 'DE-001', 'name' => 'Produit', 'category_id' => $categorie->id, 'unit' => 'u',
            'pricing_mode' => 'fourchette', 'price_min' => 100, 'price_max' => 5_000,
            'tva_rate' => 18, 'stock_qty' => 100, 'is_active' => true,
        ]);

        $this->a = $this->vente(1_000, '2026-09-30 09:00:00', '2026-10-14 08:00:00');
        $this->b = $this->vente(2_000, null, '2026-10-14 09:00:00');
        $this->c = $this->vente(4_000, '2026-10-10 15:00:00', '2026-10-14 10:00:00');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();

        parent::tearDown();
    }

    private function vente(int $montant, ?string $vendueLe, string $enregistreeLe): Sale
    {
        $vente = new Sale([
            'customer_id' => $this->client->id, 'payment_mode' => 'especes',
            'subtotal' => $montant, 'discount' => 0, 'total' => $montant, 'delivery_fee' => 0,
            'status' => 'validee', 'mecef_status' => 'transmise', 'sold_at' => $vendueLe,
        ]);
        $vente->created_at = $enregistreeLe;
        $vente->updated_at = $enregistreeLe;
        $vente->save();

        SaleLine::create([
            'sale_id' => $vente->id, 'product_id' => $this->produit->id, 'qty' => 1,
            'unit_price' => $montant, 'manual_total_amount' => $montant, 'is_manual_price' => true,
        ]);

        return $vente;
    }

    /** @return array<int, string> */
    private function ids(iterable $ventes): array
    {
        return collect($ventes)->pluck('id')->all();
    }

    // ── Le point unique : le modèle ─────────────────────────────────────────

    public function test_la_date_effective_est_sold_at_sinon_created_at(): void
    {
        $this->assertSame('2026-09-30', $this->a->fresh()->date_effective->toDateString());
        $this->assertSame('2026-10-14', $this->b->fresh()->date_effective->toDateString(), 'Sans sold_at : created_at, comportement inchangé.');
        $this->assertSame('2026-10-10', $this->c->fresh()->date_effective->toDateString());
    }

    public function test_le_scope_de_periode_juge_sur_la_date_effective_et_inclut_les_deux_bornes(): void
    {
        $this->assertEqualsCanonicalizing([$this->a->id], $this->ids(Sale::soldBetween('2026-09-01', '2026-09-30')->get()));
        $this->assertEqualsCanonicalizing([$this->b->id, $this->c->id], $this->ids(Sale::soldBetween('2026-10-01', '2026-10-31')->get()));
        // bornes incluses, sur la journée entière
        $this->assertEqualsCanonicalizing([$this->c->id], $this->ids(Sale::soldBetween('2026-10-10', '2026-10-10')->get()));
        $this->assertEqualsCanonicalizing([$this->a->id], $this->ids(Sale::soldBetween('2026-09-30', '2026-09-30')->get()));
    }

    public function test_le_scope_depuis_et_l_ordre_chronologique(): void
    {
        $this->assertEqualsCanonicalizing([$this->b->id, $this->c->id], $this->ids(Sale::soldSince(Carbon::parse('2026-10-01'))->get()));
        $this->assertSame([$this->b->id, $this->c->id, $this->a->id], $this->ids(Sale::orderByEffectiveDate()->get()));
        $this->assertSame([$this->a->id, $this->c->id, $this->b->id], $this->ids(Sale::orderByEffectiveDate('asc')->get()));
    }

    // ── Tableau de bord ─────────────────────────────────────────────────────

    public function test_le_chiffre_d_affaires_du_tableau_de_bord_suit_la_date_de_vente(): void
    {
        $kpis = Livewire::test(Dashboard::class)->instance()->getKpisProperty();

        $this->assertEquals(6_000.0, $kpis['ca']['value'], 'Octobre = B + C ; A (vendue le 30/09) n\'en fait pas partie.');
        $this->assertEquals(1_000.0, $kpis['ca']['previous'], 'Septembre = A.');
    }

    public function test_le_graphique_ventes_depenses_place_chaque_vente_dans_son_mois(): void
    {
        $chart = Livewire::test(Dashboard::class)->instance()->getChartVentesDepensesProperty();

        $this->assertEquals(1_000.0, $chart['ca'][4], 'Septembre');
        $this->assertEquals(6_000.0, $chart['ca'][5], 'Octobre');
    }

    public function test_les_transactions_recentes_du_tableau_de_bord_sont_triees_sur_la_date_de_vente(): void
    {
        $t = Livewire::test(Dashboard::class)->instance()->getTransactionsRecentesProperty();

        $this->assertSame([$this->b->id, $this->c->id, $this->a->id], $this->ids($t['sale']));
        $this->assertSame([$this->b->id, $this->c->id, $this->a->id], $this->ids($t['invoices']));
    }

    public function test_le_top_produits_du_mois_ignore_une_vente_du_mois_precedent(): void
    {
        $top = Livewire::test(Dashboard::class)->instance()->getTopProduitsProperty();

        $this->assertEquals(6_000.0, $top[0]['ca'], 'Les lignes de A (vendue en septembre) ne comptent pas pour octobre.');
    }

    // ── Historique des ventes ───────────────────────────────────────────────

    public function test_l_historique_filtre_la_periode_sur_la_date_de_vente(): void
    {
        $composant = Livewire::test(HistoriqueVentes::class)->set('dateFrom', '2026-10-01')->set('dateTo', '2026-10-14');
        $this->assertEqualsCanonicalizing([$this->b->id, $this->c->id], $this->ids($composant->instance()->getSalesInRangeProperty()));

        $composant->set('dateFrom', '2026-09-01')->set('dateTo', '2026-09-30');
        $this->assertSame([$this->a->id], $this->ids($composant->instance()->getSalesInRangeProperty()));
    }

    public function test_l_historique_ordonne_et_affiche_la_date_de_vente(): void
    {
        $composant = Livewire::test(HistoriqueVentes::class);

        $this->assertSame([$this->b->id, $this->c->id, $this->a->id], $this->ids($composant->instance()->getSalesProperty()));
        $composant->assertSee('30/09/2026')->assertSee('10/10/2026');
    }

    // ── Retours & avoirs ────────────────────────────────────────────────────

    public function test_les_ventes_proposees_aux_retours_sont_ordonnees_sur_la_date_de_vente(): void
    {
        $this->assertSame(
            [$this->b->id, $this->c->id, $this->a->id],
            $this->ids(Livewire::test(RetoursAvoirs::class)->instance()->getRecentSalesProperty()),
        );
    }

    public function test_le_taux_de_retour_compte_les_ventes_du_mois_par_date_de_vente(): void
    {
        CreditNote::create([
            'credit_note_number' => 'AV-2026-001', 'sale_id' => $this->c->id, 'product_id' => $this->produit->id,
            'qty' => 1, 'amount' => 500, 'reason' => 'défaut', 'decision' => 'reintegre', 'status' => 'en_attente',
        ]);

        $kpis = Livewire::test(RetoursAvoirs::class)->instance()->getKpisProperty();

        // 1 retour pour 2 ventes d'octobre (B, C) = 50 % ; sur created_at on aurait 3 ventes = 33,3 %.
        $this->assertEquals(50.0, $kpis['taux_retour']);
    }

    // ── Rapport recettes & dépenses ─────────────────────────────────────────

    public function test_le_rapport_recettes_depenses_retient_les_ventes_de_la_periode_par_date_de_vente(): void
    {
        $octobre = Livewire::test(RecettesDepenses::class, ['startDate' => '2026-10-01', 'endDate' => '2026-10-31'])->instance();
        $recettes = collect($octobre->getRecettesProperty());

        $this->assertEquals(6_000.0, $recettes->sum('amount'));
        $this->assertEqualsCanonicalizing(['2026-10-14', '2026-10-10'], $recettes->pluck('date')->all());

        $septembre = Livewire::test(RecettesDepenses::class, ['startDate' => '2026-09-01', 'endDate' => '2026-09-30'])->instance();
        $this->assertEquals(1_000.0, collect($septembre->getRecettesProperty())->sum('amount'));
        $this->assertSame(['2026-09-30'], collect($septembre->getRecettesProperty())->pluck('date')->all());
    }

    // ── Déclaration de TVA ──────────────────────────────────────────────────

    public function test_la_tva_collectee_tombe_dans_le_mois_de_la_vente(): void
    {
        $service = app(VatDeclarationService::class);

        $septembre = $service->tvaCollectee('2026-09-01', '2026-09-30');
        $this->assertCount(1, $septembre['rows']);
        $this->assertSame('2026-09-30', $septembre['rows'][0]['date']);
        $this->assertEquals(1_000.0, $septembre['total_ttc']);

        $octobre = $service->tvaCollectee('2026-10-01', '2026-10-31');
        $this->assertCount(2, $octobre['rows']);
        $this->assertEquals(6_000.0, $octobre['total_ttc']);
        $this->assertSame(['2026-10-14', '2026-10-10'], array_column($octobre['rows'], 'date'), 'Ordre décroissant sur la date de vente.');
    }

    public function test_la_declaration_de_tva_tombe_dans_le_meme_mois_que_l_ecriture_comptable(): void
    {
        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
        foreach ([['411', 'Clients', 4], ['531', 'Caisse', 5], ['701', 'Ventes', 7], ['443', 'TVA collectée', 4]] as [$code, $label, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $classe, 'is_active' => true]);
        }
        TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);

        app(RecordSaleAccountingEntryAction::class)->execute($this->a->fresh('lines'));

        $dateEcriture = AccountingEntry::query()->latest('created_at')->first()->entry_date;
        $mois = Carbon::parse($dateEcriture)->format('Y-m');
        $this->assertSame('2026-09', $mois, 'L\'écriture est en septembre (sold_at).');

        $declaration = app(VatDeclarationService::class)->tvaCollectee($mois.'-01', Carbon::parse($mois.'-01')->endOfMonth()->toDateString());
        $this->assertCount(1, $declaration['rows'], 'La TVA de la vente tombe dans le mois de son écriture.');
        $this->assertSame(Carbon::parse($dateEcriture)->toDateString(), $declaration['rows'][0]['date']);
    }

    // ── Facturation, fiche client ───────────────────────────────────────────

    public function test_la_facturation_compte_le_mois_et_ordonne_sur_la_date_de_vente(): void
    {
        $composant = Livewire::test(Facturation::class)->instance();

        $this->assertSame(2, $composant->getKpisProperty()['factures_mois'], 'B et C ; A est une facture de septembre.');
        $this->assertSame([$this->b->id, $this->c->id, $this->a->id], $this->ids($composant->getSalesProperty()));
    }

    public function test_la_fiche_client_ordonne_ses_ventes_sur_la_date_de_vente(): void
    {
        $composant = Livewire::test(ProfileClient::class, ['customer' => $this->client])->instance();

        $this->assertSame([$this->b->id, $this->c->id, $this->a->id], $this->ids($composant->getSalesProperty()));
    }

    // ── Tirage (API) ────────────────────────────────────────────────────────

    public function test_le_tirage_sert_les_factures_dans_l_ordre_de_la_date_de_vente_et_garde_le_repli(): void
    {
        $jeton = $this->postJson('/api/auth/login', [
            'identifiant' => 'caisse', 'password' => 'AgriERP@2026', 'device_name' => 'poste-01',
        ])->json('token');

        $factures = $this->withHeader('Authorization', 'Bearer '.$jeton)
            ->getJson('/api/sync/pull')->assertOk()->json('sales');

        $this->assertSame([$this->b->id, $this->c->id, $this->a->id], array_column($factures, 'id'));
        $this->assertSame(Carbon::parse('2026-10-14 09:00:00')->toIso8601String(), collect($factures)->firstWhere('id', $this->b->id)['sold_at'], 'Repli created_at inchangé.');
    }
}
