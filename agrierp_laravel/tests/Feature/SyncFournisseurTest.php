<?php

namespace Tests\Feature;

use App\Livewire\Achats\AjouterFournisseur;
use App\Models\Permission;
use App\Models\Role;
use App\Models\Supplier;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.17 — fiches fournisseurs créées, modifiées, archivées au poste
 * (`/sync/push`, table `suppliers`), et non-régression de la page web, dont les règles
 * passent dans `SupplierCatalogService`.
 */
class SyncFournisseurTest extends TestCase
{
    use RefreshDatabase;

    private User $acheteur;

    private User $caissier;

    protected function setUp(): void
    {
        parent::setUp();

        Permission::findOrCreate('manage-achats', 'web');
        Role::findOrCreate('acheteur', 'web')->givePermissionTo('manage-achats');
        Role::findOrCreate('caissier', 'web');

        foreach (['acheteur', 'caissier'] as $role) {
            $u = User::create([
                'name' => ucfirst($role), 'username' => $role, 'email' => $role.'@olouwachegoun.bj',
                'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
            ]);
            $u->assignRole($role);
            $this->{$role} = $u;
        }
    }

    private function fiche(array $remplace = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'name' => 'Provenderie du Plateau',
            'category' => 'Aliments',
            'phone' => '+229 97 12 34 56',
            'address' => 'Ikpinlè',
            'is_active' => true,
        ], $remplace);
    }

    private function pousser(User $u, array ...$fiches): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($u, 'sanctum')->postJson('/api/sync/push', [
            'device_id' => 'poste-test',
            'suppliers' => $fiches,
        ])->assertOk();
    }

    public function test_une_fiche_du_poste_est_creee_avec_son_uuid(): void
    {
        $f = $this->fiche();
        $r = $this->pousser($this->acheteur, $f);

        $this->assertSame([$f['id']], $r->json('suppliers.accepted'));
        $cree = Supplier::find($f['id']);
        $this->assertNotNull($cree, "le serveur garde l'UUID du poste");
        $this->assertSame('Provenderie du Plateau', $cree->name);
        $this->assertTrue((bool) $cree->is_active);
        $this->assertDatabaseHas('audit_logs', ['action' => 'supplier.created']);
        $this->assertSame(0, $r->json('referentiels_ignored'));
    }

    public function test_un_renvoi_du_meme_id_modifie_sans_doublon(): void
    {
        $f = $this->fiche();
        $this->pousser($this->acheteur, $f);
        $r = $this->pousser($this->acheteur, array_merge($f, ['phone' => '+229 90 00 00 00']));

        $this->assertSame([$f['id']], $r->json('suppliers.accepted'));
        $this->assertSame(1, Supplier::count());
        $this->assertSame('+229 90 00 00 00', Supplier::find($f['id'])->phone);
        $this->assertDatabaseHas('audit_logs', ['action' => 'supplier.updated']);
    }

    public function test_archiver_met_is_active_a_faux_sans_rien_effacer(): void
    {
        $f = $this->fiche();
        $this->pousser($this->acheteur, $f);

        $this->pousser($this->acheteur, array_merge($f, ['is_active' => false]));

        $this->assertFalse((bool) Supplier::find($f['id'])->is_active);
        $this->assertSame(1, Supplier::count(), 'archiver ne supprime pas');
        $this->assertDatabaseHas('audit_logs', ['action' => 'supplier.archived']);
    }

    public function test_un_archive_ne_descend_plus_au_tirage(): void
    {
        $f = $this->fiche();
        $this->pousser($this->acheteur, $f);
        $this->pousser($this->acheteur, array_merge($f, ['is_active' => false]));

        $ids = collect(
            $this->actingAs($this->acheteur, 'sanctum')->getJson('/api/sync/pull')->assertOk()->json('suppliers'),
        )->pluck('id');

        $this->assertNotContains($f['id'], $ids->all());
    }

    public function test_l_email_du_serveur_n_est_pas_efface_par_un_poste_qui_ne_l_envoie_pas(): void
    {
        $f = $this->fiche();
        Supplier::create(['name' => 'X', 'category' => 'Aliments', 'phone' => '1', 'email' => 'x@y.bj', 'is_active' => true]);
        $existant = Supplier::first();

        $this->pousser($this->acheteur, array_merge($f, ['id' => $existant->id]));

        $this->assertSame('x@y.bj', $existant->fresh()->email);
    }

    public function test_nom_categorie_telephone_sont_obligatoires(): void
    {
        $r = $this->pousser(
            $this->acheteur,
            $this->fiche(['name' => '']),
            $this->fiche(['category' => '']),
            $this->fiche(['phone' => '']),
            $this->fiche(['id' => 'pas-un-uuid']),
        );

        $this->assertSame([], $r->json('suppliers.accepted'));
        $this->assertCount(4, $r->json('suppliers.rejected'));
        $this->assertSame(0, Supplier::count());
    }

    public function test_sans_le_droit_manage_achats_rien_n_est_ecrit(): void
    {
        $f = $this->fiche();
        $r = $this->pousser($this->caissier, $f);

        $this->assertSame([], $r->json('suppliers.accepted'));
        $this->assertSame($f['id'], $r->json('suppliers.rejected.0.id'));
        $this->assertStringContainsString('rôle', $r->json('suppliers.rejected.0.reason'));
        $this->assertSame(0, Supplier::count());
    }

    public function test_un_achat_du_meme_envoi_peut_viser_le_fournisseur_cree(): void
    {
        $f = $this->fiche();

        $r = $this->actingAs($this->acheteur, 'sanctum')->postJson('/api/sync/push', [
            'device_id' => 'poste-test',
            // ⚠️ listé AVANT : l'ordre du paquet ne compte pas.
            'purchases' => [[
                'id' => (string) Str::uuid(),
                'supplier_id' => $f['id'],
                'payment_mode' => 'especes',
                'amount_paid' => 0,
                'purchase_date' => now()->toDateString(),
                'lines' => [],
            ]],
            'suppliers' => [$f],
        ])->assertOk();

        $this->assertSame([$f['id']], $r->json('suppliers.accepted'));
        // Le motif éventuel du refus de l'achat n'est PAS « fournisseur inconnu ».
        foreach ($r->json('purchases.rejected') as $refus) {
            $this->assertStringNotContainsString('supplier', strtolower($refus['reason']));
        }
    }

    // ── La page web, refactorisée pour partager le service ──────────────────

    public function test_la_page_web_cree_et_archive_comme_avant(): void
    {
        $this->actingAs($this->acheteur);

        Livewire::test(AjouterFournisseur::class)
            ->set('name', 'Quincaillerie ADJOVI')
            ->set('category', 'Matériel')
            ->set('phone', '+229 96 00 00 00')
            ->call('saveSupplier')
            ->assertHasNoErrors();

        $s = Supplier::where('name', 'Quincaillerie ADJOVI')->first();
        $this->assertNotNull($s);
        $this->assertTrue((bool) $s->is_active);

        Livewire::test(AjouterFournisseur::class)->call('archiveSupplier', $s->id);
        $this->assertFalse((bool) $s->fresh()->is_active);
    }

    public function test_la_page_web_exige_les_memes_champs(): void
    {
        $this->actingAs($this->acheteur);

        Livewire::test(AjouterFournisseur::class)
            ->set('name', '')
            ->call('saveSupplier')
            ->assertHasErrors(['name', 'category', 'phone']);
    }
}
