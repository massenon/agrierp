<?php

namespace Tests\Feature;

use App\Livewire\Comptabilite\Bilan;
use App\Livewire\Dashboard\Index;
use App\Livewire\Rapports\RapportsExportsHub;
use App\Livewire\Rapports\RecettesDepenses;
use App\Models\FiscalYear;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Demande du client (07/11/2026) — impression d'un état depuis le Tableau de bord AVEC UNE PÉRIODE : la période n'est
 * plus désactivée ; choisir un état + une période ouvre l'état avec CETTE période (Rapports & Exports : `startDate` /
 * `endDate` ; Bilan simplifié : `asOfDate` = fin de période), bornée à l'exercice affiché ; l'impression se fait ensuite
 * depuis l'écran de l'état, qui exporte la période reçue.
 */
class TableauDeBordPeriodeTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow('2026-07-15 10:00:00');
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $u = User::create(['name' => 'Admin', 'username' => 'admin', 'email' => 'dg@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'), 'is_active' => true]);
        $u->assignRole('admin');
        $this->actingAs($u);
        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    public function test_les_options_du_selecteur_sont_la_liste_blanche_du_composant(): void
    {
        preg_match_all('#<option value="([^"]+)">([^<]+)</option>#u', Livewire::test(Index::class)->html(), $m);

        $this->assertSame(Index::ETATS, array_combine(array_map('html_entity_decode', $m[2]), $m[1]));
    }

    public function test_la_periode_est_editable_et_par_defaut_du_premier_du_mois_a_aujourd_hui(): void
    {
        $test = Livewire::test(Index::class)->assertSet('periodeDu', '2026-07-01')->assertSet('periodeAu', '2026-07-15');
        $html = $test->html();

        $this->assertMatchesRegularExpression('#<input type="date" id="date-du"[^>]*x-model="du"[^>]*min="2026-01-01" max="2026-12-31"#', $html);
        $this->assertMatchesRegularExpression('#<input type="date" id="date-au"[^>]*x-model="au"[^>]*min="2026-01-01" max="2026-12-31"#', $html);
        $this->assertDoesNotMatchRegularExpression('#<input type="date"[^>]*\sdisabled#', $html);
        $this->assertStringContainsString("du: '2026-07-01'", $html);
        $this->assertStringContainsString("au: '2026-07-15'", $html);
    }

    public function test_le_bouton_est_desactive_sans_etat_ou_quand_du_depasse_au(): void
    {
        $html = Livewire::test(Index::class)->html();

        $this->assertStringContainsString(':disabled="!report || !du || !au || du > au"', $html);
        $this->assertMatchesRegularExpression('#<button[^\n]*id="export-pdf"[^\n]*\sdisabled><span#', $html);
    }

    public function test_du_apres_au_ou_aucun_etat_n_ouvre_rien(): void
    {
        Livewire::test(Index::class)
            ->call('ouvrirEtat', '/rapports-exports?tab=tresorerie', '2026-07-20', '2026-07-10')
            ->assertNoRedirect()
            ->assertDispatched('toast')
            ->call('ouvrirEtat', '', '2026-07-01', '2026-07-10')
            ->assertNoRedirect()
            ->call('ouvrirEtat', '/page-inconnue', '2026-07-01', '2026-07-10')
            ->assertNoRedirect();
    }

    public function test_un_etat_de_rapports_exports_s_ouvre_avec_la_periode_choisie(): void
    {
        Livewire::test(Index::class)
            ->call('ouvrirEtat', '/rapports-exports?tab=tresorerie', '2026-07-03', '2026-07-12')
            ->assertRedirect('/rapports-exports?tab=tresorerie&startDate=2026-07-03&endDate=2026-07-12');
    }

    public function test_la_periode_est_bornee_a_l_exercice_affiche(): void
    {
        Livewire::test(Index::class)
            ->call('ouvrirEtat', '/rapports-exports?tab=dettes', '2025-12-01', '2027-02-01')
            ->assertRedirect('/rapports-exports?tab=dettes&startDate=2026-01-01&endDate=2026-12-31');
    }

    public function test_le_bilan_simplifie_recoit_la_fin_de_periode_comme_date_d_arrete(): void
    {
        Livewire::test(Index::class)
            ->call('ouvrirEtat', '/rapport-bilan', '2026-07-03', '2026-07-12')
            ->assertRedirect('/rapport-bilan?asOfDate=2026-07-12');
    }

    public function test_l_ecran_rapports_exports_recoit_la_periode_de_l_adresse_et_l_exporte(): void
    {
        Livewire::withQueryParams(['tab' => 'tresorerie', 'startDate' => '2026-07-03', 'endDate' => '2026-07-12'])
            ->test(RapportsExportsHub::class)
            ->assertSet('tab', 'tresorerie')
            ->assertSet('startDate', '2026-07-03')
            ->assertSet('endDate', '2026-07-12')
            ->call('exportPdf')
            ->assertDispatched('export-report', format: 'pdf', startDate: '2026-07-03', endDate: '2026-07-12');
    }

    public function test_l_export_de_l_etat_utilise_la_periode_recue(): void
    {
        Livewire::test(RecettesDepenses::class, ['startDate' => '2026-07-01', 'endDate' => '2026-07-31'])
            ->call('exportReport', 'csv', '2026-07-03', '2026-07-12')
            ->assertSet('startDate', '2026-07-03')
            ->assertSet('endDate', '2026-07-12');
    }

    public function test_le_bilan_lit_sa_date_d_arrete_dans_l_adresse_et_la_borne(): void
    {
        Livewire::withQueryParams(['asOfDate' => '2026-07-12'])->test(Bilan::class)->assertSet('asOfDate', '2026-07-12');
        Livewire::withQueryParams(['asOfDate' => '2031-01-01'])->test(Bilan::class)->assertSet('asOfDate', '2026-12-31');
        Livewire::withQueryParams([])->test(Bilan::class)->assertSet('asOfDate', '2026-07-15');
    }
}
