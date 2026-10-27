<?php

namespace Tests\Feature;

use App\Livewire\Achats\DettesFournisseurs;
use App\Models\Payable;
use App\Models\Permission;
use App\Models\Role;
use App\Models\Supplier;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket AC-4 — LA COLONNE « ACTIONS » DE « DETTES FOURNISSEURS » : « Régler » ouvre la modale sur le fournisseur de la
 * ligne (le bouton d'en-tête l'ouvre sans fournisseur) ; une dette soldée n'offre rien.
 */
class DettesFournisseursActionsTest extends TestCase
{
    use RefreshDatabase;

    private User $acheteur;

    protected function setUp(): void
    {
        parent::setUp();

        Permission::findOrCreate('manage-achats', 'web');
        Permission::findOrCreate('view-achats', 'web');
        Role::findOrCreate('acheteur', 'web')->givePermissionTo(['manage-achats', 'view-achats']);
        $this->acheteur = User::create([
            'name' => 'Acheteur', 'username' => 'acheteur', 'email' => 'acheteur@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->acheteur->assignRole('acheteur');
    }

    public function test_regler_preselectionne_le_fournisseur_de_la_ligne_et_le_bouton_d_en_tete_ne_choisit_personne(): void
    {
        $this->actingAs($this->acheteur);
        $f1 = Supplier::create(['name' => 'Quincaillerie ADJOVI', 'category' => 'Matériel', 'is_active' => true]);
        $f2 = Supplier::create(['name' => 'Provenderie du Plateau', 'category' => 'Aliments', 'is_active' => true]);
        Payable::create(['supplier_id' => $f1->id, 'amount' => 100000, 'amount_paid' => 40000, 'due_date' => now()->addDays(5), 'status' => 'en_cours']);
        Payable::create(['supplier_id' => $f2->id, 'amount' => 50000, 'amount_paid' => 50000, 'due_date' => now()->addDays(5), 'status' => 'soldee']);

        $page = Livewire::test(DettesFournisseurs::class)
            ->assertSee('Actions')
            ->assertSeeHtml("openPaymentModal('{$f1->id}')")
            ->assertDontSeeHtml("openPaymentModal('{$f2->id}')");

        $page->call('openPaymentModal', $f1->id)->assertSet('paymentSupplierId', $f1->id);
        $page->call('openPaymentModal')->assertSet('paymentSupplierId', '');
        $page->call('openPaymentModal', '99999999-9999-4999-8999-999999999999')->assertSet('paymentSupplierId', '');
    }
}
