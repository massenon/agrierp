<?php

namespace Tests\Feature;

use App\Livewire\Comptabilite\ClotureExercice;
use App\Livewire\Comptabilite\JournalComptable;
use App\Models\AccountingEntry;
use App\Models\AccountingEntryLine;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\Permission;
use App\Models\PeriodicClosure;
use App\Models\Role;
use App\Models\User;
use App\Services\AccountingEntryService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.14 (Sprint 14) — Clôture Périodique.
 *
 * Le test central est celui du VERROU : une clôture qui n'empêche aucune
 * écriture n'est qu'une liste décorative. Les autres vérifient les deux
 * garde-fous — balance obligatoirement équilibrée avant de clôturer, et
 * déclôture réservée à l'Administrateur.
 */
class ClotturePeriodiqueTest extends TestCase
{
    use RefreshDatabase;

    private ChartOfAccount $caisse;

    private ChartOfAccount $ventes;

    protected function setUp(): void
    {
        parent::setUp();

        FiscalYear::create([
            'year' => 2026,
            'start_date' => '2026-01-01',
            'end_date' => '2026-12-31',
            'status' => 'ouvert',
        ]);

        $this->caisse = ChartOfAccount::create(['code' => '531', 'label' => 'Caisse', 'class' => 5, 'is_active' => true]);
        $this->ventes = ChartOfAccount::create(['code' => '701', 'label' => 'Ventes', 'class' => 7, 'is_active' => true]);
    }

    private function actingAsRole(string $role, array $permissions): User
    {
        foreach ($permissions as $name) {
            Permission::findOrCreate($name, 'web');
        }
        $r = Role::findOrCreate($role, 'web');
        $r->givePermissionTo($permissions);

        $user = User::create([
            'name' => 'Test '.$role,
            'email' => $role.'.test@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'),
        ]);
        $user->assignRole($r);
        $this->actingAs($user);

        return $user;
    }

    private function ecriture(string $date): void
    {
        app(AccountingEntryService::class)
            ->recordManual($this->caisse->id, $this->ventes->id, 10_000, $date, 'OD-0001 — Vente');
    }

    /**
     * LE TEST CENTRAL : sans ce blocage, la clôture périodique n'aurait
     * aucun effet réel.
     */
    public function test_a_closed_month_really_refuses_new_entries(): void
    {
        $this->actingAsRole('admin', ['view-comptabilite', 'manage-comptabilite']);

        PeriodicClosure::create(['period' => '2026-07', 'closed_at' => now()]);

        Livewire::test(JournalComptable::class)
            ->set('entryDate', '2026-07-15')
            ->set('label', 'Écriture antidatée')
            ->set('debitAccountId', $this->caisse->id)
            ->set('creditAccountId', $this->ventes->id)
            ->set('amount', 5_000)
            ->call('saveEntry')
            ->assertHasErrors('entryDate');

        $this->assertEquals(0, AccountingEntry::count(), 'Aucune écriture ne doit avoir été créée dans un mois clôturé.');
    }

    public function test_an_open_month_still_accepts_entries(): void
    {
        $this->actingAsRole('admin', ['view-comptabilite', 'manage-comptabilite']);

        PeriodicClosure::create(['period' => '2026-07', 'closed_at' => now()]);

        Livewire::test(JournalComptable::class)
            ->set('entryDate', '2026-08-15')     // mois NON clôturé
            ->set('label', 'Écriture normale')
            ->set('debitAccountId', $this->caisse->id)
            ->set('creditAccountId', $this->ventes->id)
            ->set('amount', 5_000)
            ->call('saveEntry')
            ->assertHasNoErrors();

        $this->assertEquals(1, AccountingEntry::count());
    }

    /** Une déclôture lève réellement le verrou. */
    public function test_reopening_a_month_lifts_the_lock(): void
    {
        $this->actingAsRole('admin', ['view-comptabilite', 'manage-comptabilite']);

        $closure = PeriodicClosure::create(['period' => '2026-07', 'closed_at' => now()]);

        $this->assertTrue(PeriodicClosure::isDateLocked('2026-07-15'));

        $closure->update(['reopened_at' => now()]);

        $this->assertFalse(PeriodicClosure::isDateLocked('2026-07-15'));
    }

    /** La clôture est refusée côté SERVEUR si la balance du mois est déséquilibrée. */
    public function test_an_unbalanced_month_cannot_be_closed(): void
    {
        $this->actingAsRole('admin', ['view-comptabilite', 'close-fiscal-year', 'manage-modules']);

        // Écriture DÉSÉQUILIBRÉE injectée directement (le service la refuserait).
        $entry = AccountingEntry::create([
            'fiscal_year_id' => FiscalYear::first()->id,
            'entry_date' => '2026-07-10',
            'reference' => 'OD-CORROMPUE — déséquilibrée',
            'source_type' => 'manual',
            'is_active' => true,
        ]);
        AccountingEntryLine::create([
            'entry_id' => $entry->id,
            'account_id' => $this->caisse->id,
            'debit' => 50_000,
            'credit' => 0,
        ]);

        Livewire::test(ClotureExercice::class)
            ->set('periodeACloturer', '2026-07')
            ->call('cloturerPeriode');

        $this->assertEquals(0, PeriodicClosure::count(), 'Un mois déséquilibré ne doit jamais pouvoir être clôturé.');
    }

    public function test_a_balanced_month_can_be_closed(): void
    {
        $this->actingAsRole('admin', ['view-comptabilite', 'close-fiscal-year', 'manage-modules']);

        $this->ecriture('2026-07-10');

        Livewire::test(ClotureExercice::class)
            ->set('periodeACloturer', '2026-07')
            ->call('cloturerPeriode');

        $this->assertEquals(1, PeriodicClosure::where('period', '2026-07')->count());
        $this->assertTrue(PeriodicClosure::isDateLocked('2026-07-20'));
    }

    /** Déclôture réservée à l'Administrateur — un comptable ne peut pas. */
    public function test_only_an_administrator_can_reopen_a_month(): void
    {
        $this->actingAsRole('comptable', ['view-comptabilite', 'close-fiscal-year']);   // sans manage-modules

        $closure = PeriodicClosure::create(['period' => '2026-07', 'closed_at' => now()]);

        Livewire::test(ClotureExercice::class)
            ->call('decloturerPeriode', $closure->id)
            ->assertForbidden();

        $this->assertTrue($closure->fresh()->isLocked(), 'Le mois doit rester verrouillé.');
    }

    public function test_an_administrator_reopening_is_traced(): void
    {
        $admin = $this->actingAsRole('admin', ['view-comptabilite', 'close-fiscal-year', 'manage-modules']);

        $closure = PeriodicClosure::create(['period' => '2026-07', 'closed_at' => now()]);

        Livewire::test(ClotureExercice::class)->call('decloturerPeriode', $closure->id);

        $closure->refresh();

        $this->assertFalse($closure->isLocked());
        $this->assertNotNull($closure->reopened_at);
        $this->assertEquals($admin->id, $closure->reopened_by, "L'identité de l'auteur doit être tracée.");
        // La ligne est conservée, jamais supprimée : l'historique reste consultable.
        $this->assertEquals(1, PeriodicClosure::count());
    }
}
