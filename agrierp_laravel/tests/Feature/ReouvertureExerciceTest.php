<?php

namespace Tests\Feature;

use App\Livewire\Comptabilite\ClotureExercice;
use App\Models\AccountingEntry;
use App\Models\AccountingEntryLine;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\User;
use App\Services\AccountingEntryService;
use App\Services\ReinitialisationDonneesService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.53 — UN EXERCICE CLÔTURÉ PEUT ÊTRE ROUVERT (décision client du 17/10/2026).
 *
 * La réouverture défait la clôture SANS RIEN EFFACER : le report à nouveau de N+1 est contre-passé, les
 * écritures de N sont déverrouillées, N repasse « ouvert ». Une nouvelle clôture repasse un report sur les
 * soldes corrigés : le bilan d'ouverture de N+1 reste juste. Chiffres attendus calculés à la main.
 */
class ReouvertureExerciceTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    private ChartOfAccount $capital;

    private ChartOfAccount $caisse;

    protected function setUp(): void
    {
        parent::setUp();
        // Ticket EX4 — la clôture de 2026 n'est admise qu'après son échéance (Q2) : on se place en février 2027.
        \Carbon\Carbon::setTestNow('2027-02-15 10:00:00');
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $this->admin = $this->compte('admin');

        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
        $compte = fn ($code, $libelle, $classe) => ChartOfAccount::create(['code' => $code, 'label' => $libelle, 'class' => $classe, 'is_active' => true]);
        $compte('131', 'Résultat - Bénéfice', 1);
        $compte('139', 'Résultat - Perte', 1);
        $this->capital = $compte('101', 'Capital', 1);
        $this->caisse = $compte('531', 'Caisse', 5);

        app(AccountingEntryService::class)->recordManual($this->caisse->id, $this->capital->id, 1_000_000, '2026-03-01');
    }

    protected function tearDown(): void
    {
        \Carbon\Carbon::setTestNow();
        parent::tearDown();
    }

    private function compte(string $role): User
    {
        $u = User::create([
            'name' => ucfirst($role), 'username' => $role, 'email' => $role.'@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    private function cloturer(): void
    {
        $this->actingAs($this->admin);
        // Ticket EX4 — l'étape 1 doit être confirmée (aucune charge ni produit : l'étape 2 n'a rien à solder).
        Livewire::test(ClotureExercice::class)->set('selectedYear', '2026')->call('confirmStep1')->call('confirmCloture');
    }

    /** Solde débiteur de la caisse sur les écritures ACTIVES datées dans [début, fin]. */
    private function soldeCaisse(string $debut, string $fin): float
    {
        return (float) AccountingEntryLine::query()
            ->join('accounting_entries', 'accounting_entries.id', '=', 'accounting_entry_lines.entry_id')
            ->where('accounting_entries.is_active', true)
            ->whereBetween('accounting_entries.entry_date', [$debut, $fin])
            ->where('account_id', $this->caisse->id)
            ->selectRaw('COALESCE(SUM(debit - credit), 0) as solde')->value('solde');
    }

    public function test_rouvrir_contre_passe_le_report_deverrouille_et_rouvre(): void
    {
        $this->cloturer();
        $this->assertSame(1_000_000.0, $this->soldeCaisse('2027-01-01', '2027-12-31'), 'report à nouveau passé');

        Livewire::test(ClotureExercice::class)->set('selectedYear', '2026')->call('rouvrirExercice');

        $n = FiscalYear::where('year', 2026)->sole();
        $this->assertSame(['ouvert', null, null], [$n->status, $n->closed_at, $n->closed_by]);
        $this->assertSame(0, AccountingEntry::where('fiscal_year_id', $n->id)->where('is_locked', true)->count());
        // Contre-passé, pas effacé : le report reste au journal, et son inverse l'annule.
        $this->assertSame(1, AccountingEntry::where('source_type', 'ran')->count());
        $this->assertSame(1, AccountingEntry::where('source_type', 'ran_reversal')->count());
        $this->assertSame(0.0, $this->soldeCaisse('2027-01-01', '2027-12-31'));
        $this->assertSame(1, AuditLog::where('action', 'fiscal_year.reopened')->count());
    }

    public function test_une_correction_apres_reouverture_puis_nouvelle_cloture_donne_le_bon_a_nouveau(): void
    {
        $this->cloturer();
        Livewire::test(ClotureExercice::class)->set('selectedYear', '2026')->call('rouvrirExercice');

        // Apport complémentaire découvert après coup, daté de 2026.
        app(AccountingEntryService::class)->recordManual($this->caisse->id, $this->capital->id, 250_000, '2026-11-30');
        $this->cloturer();

        // 1 000 000 (premier report) − 1 000 000 (contre-passation) + 1 250 000 (nouveau report).
        $this->assertSame(1_250_000.0, $this->soldeCaisse('2027-01-01', '2027-12-31'));
        $this->assertSame('cloture', FiscalYear::where('year', 2026)->sole()->status);
    }

    public function test_rouvrir_n_est_refuse_si_n_plus_un_est_cloture(): void
    {
        $this->cloturer();
        FiscalYear::where('year', 2027)->update(['status' => 'cloture']);

        Livewire::test(ClotureExercice::class)->set('selectedYear', '2026')->call('rouvrirExercice')
            ->assertDispatched('toast', type: 'error');

        $this->assertSame('cloture', FiscalYear::where('year', 2026)->sole()->status);
        $this->assertSame(0, AccountingEntry::where('source_type', 'ran_reversal')->count());
    }

    public function test_seul_l_administrateur_peut_rouvrir(): void
    {
        $this->cloturer();
        $this->actingAs($this->compte('comptable'));

        Livewire::test(ClotureExercice::class)->set('selectedYear', '2026')->call('rouvrirExercice')->assertForbidden();

        $this->assertSame('cloture', FiscalYear::where('year', 2026)->sole()->status);
    }

    public function test_la_reinitialisation_rouvre_les_exercices_clotures(): void
    {
        $this->cloturer();

        app(ReinitialisationDonneesService::class)->executer();

        $this->assertSame(['ouvert'], FiscalYear::distinct()->pluck('status')->all());
    }
}
