<?php

namespace Tests\Feature;

use App\Livewire\Parametres\ReinitialisationDonnees;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\CompanySetting;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\Sale;
use App\Models\Supplier;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Services\ReinitialisationDonneesService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.56 (Sprint 14) — RÉINITIALISATION DES DONNÉES DE TEST.
 *
 * Les tests qui comptent le plus sont ceux des VERROUS et des PRÉSERVATIONS :
 * une opération destructrice se juge à ce qu'elle refuse de faire.
 */
class ReinitialisationDonneesTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-parametres', 'manage-parametres'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('admin', 'web')->givePermissionTo(['view-parametres', 'manage-parametres']);
        Role::findOrCreate('caissier', 'web');

        $this->admin = User::create([
            'name' => 'Directeur', 'username' => 'admin', 'email' => 'dg@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->admin->assignRole('admin');

        CompanySetting::create(['company_name' => 'Ferme École OLOUWACHEGOUN']);

        $this->actingAs($this->admin);
    }

    private function donneesDActivite(): void
    {
        Supplier::create(['name' => 'Provenderie', 'phone' => '+22997000000', 'is_active' => true]);

        Sale::create([
            'payment_mode' => 'especes', 'subtotal' => 21_000, 'discount' => 0,
            'total' => 21_000, 'status' => 'validee',
        ]);
    }

    /** ⚠️ VERROU 1 : la bascule est FAUSSE par défaut. */
    public function test_the_demo_mode_is_off_by_default(): void
    {
        $this->assertFalse((bool) CompanySetting::first()->demo_mode_enabled);

        Livewire::test(ReinitialisationDonnees::class)
            ->assertSee('Réinitialisation verrouillée');
    }

    /** ⚠️ Sans la bascule, la réinitialisation est refusée même appelée directement. */
    public function test_without_the_toggle_the_reset_is_refused(): void
    {
        $this->donneesDActivite();

        Livewire::test(ReinitialisationDonnees::class)
            ->set('confirmation', 'REINITIALISER')
            ->call('reinitialiser')
            ->assertDispatched('toast');

        $this->assertEquals(1, Sale::count(), 'la vente est intacte');
    }

    /** L'activation de la bascule est journalisée : c'est un acte administratif. */
    public function test_enabling_the_demo_mode_is_journalled(): void
    {
        Livewire::test(ReinitialisationDonnees::class)->call('basculerModeDemo');

        $this->assertTrue((bool) CompanySetting::first()->demo_mode_enabled);
        $this->assertEquals(1, AuditLog::where('action', 'demo_mode.enabled')->count());
    }

    /**
     * ⚠️ VERROU 2 : un mot de confirmation doit être recopié. Une modale à un
     * seul bouton se clique par réflexe.
     */
    public function test_a_wrong_confirmation_word_stops_everything(): void
    {
        CompanySetting::first()->update(['demo_mode_enabled' => true]);
        $this->donneesDActivite();

        Livewire::test(ReinitialisationDonnees::class)
            ->set('confirmation', 'oui')
            ->call('reinitialiser')
            ->assertHasErrors('confirmation');

        $this->assertEquals(1, Sale::count());
    }

    /** Avec les deux verrous levés, la réinitialisation s'exécute. */
    public function test_with_both_locks_lifted_the_reset_runs(): void
    {
        CompanySetting::first()->update(['demo_mode_enabled' => true]);
        $this->donneesDActivite();

        Livewire::test(ReinitialisationDonnees::class)
            ->set('confirmation', 'REINITIALISER')
            ->call('reinitialiser')
            ->assertHasNoErrors();

        $this->assertEquals(0, Sale::count());
        $this->assertEquals(0, Supplier::count());
    }

    /**
     * ⚠️⚠️ LES COMPTES SURVIVENT. Les vider verrouillerait l'application hors
     * de portée de tout le monde, y compris de l'administrateur qui vient de
     * lancer l'opération.
     */
    public function test_users_and_roles_survive(): void
    {
        $this->donneesDActivite();

        app(ReinitialisationDonneesService::class)->executer();

        $this->assertEquals(1, User::count());
        $this->assertTrue($this->admin->fresh()->hasRole('admin'));
    }

    /**
     * ⚠️ LE JOURNAL D'AUDIT SURVIT — c'est la trace de ce qui s'est passé, y
     * compris de cette réinitialisation. L'effacer supprimerait la preuve de
     * l'effacement.
     */
    public function test_the_audit_log_survives_and_records_the_reset(): void
    {
        AuditLog::record('test.avant', 'parametres');

        app(ReinitialisationDonneesService::class)->executer();

        $this->assertEquals(1, AuditLog::where('action', 'test.avant')->count());
        $this->assertEquals(1, AuditLog::where('action', 'donnees.reinitialisees')->count());
    }

    /** Les référentiels et réglages survivent : ce sont les paramètres de base. */
    public function test_referentials_and_settings_survive(): void
    {
        ChartOfAccount::create(['code' => '601', 'label' => 'Achats', 'class' => 6, 'is_active' => true]);
        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);
        Product::create([
            'sku' => 'ALI-001', 'name' => 'Aliment ponte', 'category_id' => $categorie->id,
            'unit' => 'sac', 'pricing_mode' => 'fourchette', 'tva_rate' => 0,
            'stock_qty' => 40, 'is_active' => true,
        ]);

        // Ticket 15.19 : la migration de rattrapage ouvre le compte 419 dans TOUTE base de test.
        // Le test comptait « 1 » en supposant un plan vide ; il compare désormais à l'avant.
        $plansAvant = ChartOfAccount::count();

        app(ReinitialisationDonneesService::class)->executer();

        $this->assertEquals($plansAvant, ChartOfAccount::count());
        $this->assertEquals(1, Product::count());
        $this->assertEquals('Ferme École OLOUWACHEGOUN', CompanySetting::first()->company_name);
    }

    /**
     * ⚠️ SANS CETTE ÉTAPE, L'ÉTAT SERAIT PIRE QU'AVANT : un stock et une caisse
     * sans aucune écriture pour les justifier.
     */
    public function test_derived_balances_are_reset(): void
    {
        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);
        Product::create([
            'sku' => 'ALI-001', 'name' => 'Aliment ponte', 'category_id' => $categorie->id,
            'unit' => 'sac', 'pricing_mode' => 'fourchette', 'tva_rate' => 0,
            'stock_qty' => 40, 'is_active' => true,
        ]);
        TreasuryAccount::create([
            'type' => 'caisse', 'label' => 'Caisse Principale', 'account_code' => '531',
            'balance' => 250_000, 'is_active' => true,
        ]);

        app(ReinitialisationDonneesService::class)->executer();

        $this->assertEquals(0, (float) Product::first()->stock_qty);
        $this->assertEquals(0, (float) TreasuryAccount::first()->balance);
    }

    /** ⚠️ VERROU 3 : un non-administrateur ne peut ni basculer ni réinitialiser. */
    public function test_a_non_admin_can_neither_toggle_nor_reset(): void
    {
        $caissier = User::create([
            'name' => 'Caissière', 'username' => 'caisse', 'email' => 'caisse@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $caissier->assignRole('caissier');

        CompanySetting::first()->update(['demo_mode_enabled' => true]);
        $this->donneesDActivite();
        $this->actingAs($caissier);

        // ⚠️ On verifie la GARANTIE — rien n'est efface — plutot que la forme
        // du refus, qui depend du harnais Livewire.
        Livewire::test(ReinitialisationDonnees::class)
            ->set('confirmation', 'REINITIALISER')
            ->call('reinitialiser')
            ->assertForbidden();

        $this->assertEquals(1, Sale::count(), 'la vente est intacte');
        $this->assertEquals(1, Supplier::count());
        $this->assertEquals(0, AuditLog::where('action', 'donnees.reinitialisees')->count());
    }

    /** Les deux listes de tables ne se recoupent jamais. */
    public function test_the_two_table_lists_never_overlap(): void
    {
        $commun = array_intersect(
            ReinitialisationDonneesService::tablesTransactionnelles(),
            ReinitialisationDonneesService::tablesPreservees(),
        );

        $this->assertEmpty($commun,
            'une table ne peut pas etre a la fois videe et preservee');
    }
}
