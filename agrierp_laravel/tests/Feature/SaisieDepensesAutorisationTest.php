<?php

namespace Tests\Feature;

use App\Models\Expense;
use App\Models\Permission;
use App\Models\Role;
use App\Models\TreasuryAccount;
use App\Models\User;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.62 (Sprint 14) — DÉPENSER DEMANDE PLUS QUE LIRE.
 *
 * ⚠️⚠️ LE DÉFAUT CORRIGÉ. `submitExpense()`, `editExpense()` et
 * `archiveExpense()` ne portaient **aucune autorisation** : seul le middleware
 * de route `can:view-achats` protégeait l'écran. Un droit de **lecture**
 * suffisait donc à décaisser la trésorerie et à passer une écriture SYSCOHADA,
 * ou à retirer une dépense des états.
 *
 * La règle du projet est explicite et n'était pas appliquée ici : autorisation
 * de route **ET** `authorize('manage-{module}')` en première ligne de toute
 * méthode mutante. Masquer un menu n'est pas une autorisation.
 */
class SaisieDepensesAutorisationTest extends TestCase
{
    use RefreshDatabase;

    private TreasuryAccount $caisse;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-achats', 'manage-achats'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }

        // Un rôle qui ne peut que CONSULTER les achats.
        Role::findOrCreate('lecteur', 'web')->givePermissionTo(['view-achats']);
        Role::findOrCreate('acheteur', 'web')
            ->givePermissionTo(['view-achats', 'manage-achats']);

        $this->caisse = TreasuryAccount::create([
            'label' => 'Caisse Physique',
            'account_code' => '531',
            'type' => 'caisse',
            'balance' => 500000,
            'is_active' => true,
        ]);
    }

    private function utilisateur(string $role): User
    {
        $u = User::create([
            'name' => ucfirst($role), 'username' => $role,
            'email' => $role.'@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    /**
     * ⚠️⚠️ LE TEST QUI COMPTE : un droit de lecture ne décaisse pas.
     */
    public function test_a_read_only_user_cannot_spend(): void
    {
        Livewire::actingAs($this->utilisateur('lecteur'))
            ->test(\App\Livewire\Achats\SaisieDepenses::class)
            ->set('expenseDate', now()->toDateString())
            ->set('label', 'Sac de provende')
            ->set('category', '601 - Aliments')
            ->set('amount', 25000)
            ->set('treasuryAccountId', $this->caisse->id)
            ->call('submitExpense')
            ->assertForbidden();

        // La garantie, pas seulement l'exception : rien n'a bougé.
        $this->assertEquals(0, Expense::count());
        $this->assertEquals(500000.0, (float) $this->caisse->fresh()->balance,
            'une caisse qui baisse sans droit est le defaut lui-meme');
    }

    /** ⚠️ Archiver retire la dépense des états : même exigence. */
    public function test_a_read_only_user_cannot_archive(): void
    {
        $depense = Expense::create([
            'expense_date' => now()->toDateString(),
            'label' => 'Sac de provende',
            'category' => '601 - Aliments',
            'amount' => 25000,
            'treasury_account_id' => $this->caisse->id,
            'status' => 'payee',
            'is_active' => true,
        ]);

        Livewire::actingAs($this->utilisateur('lecteur'))
            ->test(\App\Livewire\Achats\SaisieDepenses::class)
            ->call('archiveExpense', $depense->id)
            ->assertForbidden();

        $this->assertTrue((bool) $depense->fresh()->is_active,
            'la depense doit rester active');
    }

    /** Le rôle qui gère les achats, lui, passe sans entrave. */
    public function test_a_manager_may_open_the_form(): void
    {
        Livewire::actingAs($this->utilisateur('acheteur'))
            ->test(\App\Livewire\Achats\SaisieDepenses::class)
            ->call('editExpense', $this->depenseExistante()->id)
            ->assertOk();
    }

    private function depenseExistante(): Expense
    {
        return Expense::create([
            'expense_date' => now()->toDateString(),
            'label' => 'Gasoil groupe',
            'category' => '605 - Énergie',
            'amount' => 12000,
            'treasury_account_id' => $this->caisse->id,
            'status' => 'payee',
            'is_active' => true,
        ]);
    }
}
