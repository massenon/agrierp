<?php

namespace Tests\Feature;

use App\Livewire\Ventes\ListeClients;
use App\Models\Customer;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.18 — fiches clients créées, modifiées, archivées au poste
 * (`/sync/push`, table `customers`), et non-régression de la page web, dont les règles
 * passent dans `CustomerCatalogService`.
 */
class SyncClientTest extends TestCase
{
    use RefreshDatabase;

    private User $vendeur;

    private User $eleveur;

    protected function setUp(): void
    {
        parent::setUp();

        Permission::findOrCreate('manage-ventes', 'web');
        Role::findOrCreate('vendeur', 'web')->givePermissionTo('manage-ventes');
        Role::findOrCreate('eleveur', 'web');

        foreach (['vendeur', 'eleveur'] as $role) {
            $u = User::create([
                'name' => ucfirst($role), 'username' => $role, 'email' => $role.'@fermeolouwachegoun.com',
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
            'name' => 'Restaurant Chez Mama',
            'phone' => '+229 97 12 34 56',
            'email' => 'mama@resto.bj',
            'city' => 'Cotonou',
            'is_active' => true,
        ], $remplace);
    }

    private function pousser(User $u, array ...$fiches): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($u, 'sanctum')->postJson('/api/sync/push', [
            'device_id' => 'poste-test',
            'customers' => $fiches,
        ])->assertOk();
    }

    public function test_une_fiche_du_poste_est_creee_avec_son_uuid(): void
    {
        $f = $this->fiche();
        $r = $this->pousser($this->vendeur, $f);

        $this->assertSame([$f['id']], $r->json('customers.accepted'));
        $cree = Customer::find($f['id']);
        $this->assertNotNull($cree, "le serveur garde l'UUID du poste");
        $this->assertSame('Restaurant Chez Mama', $cree->name);
        $this->assertSame('mama@resto.bj', $cree->email);
        $this->assertTrue((bool) $cree->is_active);
        $this->assertDatabaseHas('audit_logs', ['action' => 'customer.created']);
        $this->assertSame(0, $r->json('referentiels_ignored'));
    }

    public function test_seul_le_nom_est_obligatoire(): void
    {
        $f = $this->fiche(['phone' => null, 'email' => null, 'city' => null]);
        $r = $this->pousser($this->vendeur, $f);

        $this->assertSame([$f['id']], $r->json('customers.accepted'));
        $c = Customer::find($f['id']);
        $this->assertNull($c->phone);
        $this->assertNull($c->city);
    }

    public function test_un_renvoi_du_meme_id_modifie_sans_doublon(): void
    {
        $f = $this->fiche();
        $this->pousser($this->vendeur, $f);
        $r = $this->pousser($this->vendeur, array_merge($f, ['city' => 'Parakou']));

        $this->assertSame([$f['id']], $r->json('customers.accepted'));
        $this->assertSame(1, Customer::count());
        $this->assertSame('Parakou', Customer::find($f['id'])->city);
        $this->assertDatabaseHas('audit_logs', ['action' => 'customer.updated']);
    }

    public function test_archiver_met_is_active_a_faux_sans_rien_effacer(): void
    {
        $f = $this->fiche();
        $this->pousser($this->vendeur, $f);

        $this->pousser($this->vendeur, array_merge($f, ['is_active' => false]));

        $this->assertFalse((bool) Customer::find($f['id'])->is_active);
        $this->assertSame(1, Customer::count(), 'archiver ne supprime pas');
        $this->assertDatabaseHas('audit_logs', ['action' => 'customer.archived']);
    }

    public function test_le_plafond_de_credit_n_est_jamais_ecrit_par_un_poste(): void
    {
        $f = $this->fiche();
        $this->pousser($this->vendeur, $f);
        Customer::find($f['id'])->update(['credit_limit' => 50000]);

        $this->pousser($this->vendeur, array_merge($f, ['credit_limit' => 9999999]));

        $this->assertEquals(50000, Customer::find($f['id'])->credit_limit);
    }

    public function test_nom_vide_email_invalide_et_uuid_invalide_sont_refuses_avec_motif(): void
    {
        $r = $this->pousser(
            $this->vendeur,
            $this->fiche(['name' => '']),
            $this->fiche(['email' => 'pas-un-email']),
            $this->fiche(['id' => 'pas-un-uuid']),
        );

        $this->assertSame([], $r->json('customers.accepted'));
        $this->assertCount(3, $r->json('customers.rejected'));
        $this->assertSame(0, Customer::count());
    }

    public function test_sans_le_droit_manage_ventes_rien_n_est_ecrit(): void
    {
        $f = $this->fiche();
        $r = $this->pousser($this->eleveur, $f);

        $this->assertSame([], $r->json('customers.accepted'));
        $this->assertSame($f['id'], $r->json('customers.rejected.0.id'));
        $this->assertStringContainsString('rôle', $r->json('customers.rejected.0.reason'));
        $this->assertSame(0, Customer::count());
    }

    public function test_le_tirage_sert_l_email_et_les_archives_modifies(): void
    {
        $f = $this->fiche();
        $this->pousser($this->vendeur, $f);
        $this->pousser($this->vendeur, array_merge($f, ['is_active' => false]));

        $ligne = collect(
            $this->actingAs($this->vendeur, 'sanctum')->getJson('/api/sync/pull')->assertOk()->json('customers'),
        )->firstWhere('id', $f['id']);

        $this->assertNotNull($ligne, 'un archivé descend, avec is_active faux');
        $this->assertSame('mama@resto.bj', $ligne['email']);
        $this->assertFalse((bool) $ligne['is_active']);
    }

    public function test_une_vente_du_meme_envoi_peut_viser_le_client_cree(): void
    {
        $f = $this->fiche();

        $r = $this->actingAs($this->vendeur, 'sanctum')->postJson('/api/sync/push', [
            'device_id' => 'poste-test',
            // ⚠️ listé AVANT : l'ordre du paquet ne compte pas.
            'sales' => [[
                'id' => (string) Str::uuid(),
                'customer_id' => $f['id'],
                'payment_mode' => 'especes',
                'sale_date' => now()->toDateString(),
                'lines' => [],
            ]],
            'customers' => [$f],
        ])->assertOk();

        $this->assertSame([$f['id']], $r->json('customers.accepted'));
        foreach ($r->json('sales.rejected') as $refus) {
            $this->assertStringNotContainsString('customer', strtolower($refus['reason']));
        }
    }

    // ── La page web, refactorisée pour partager le service ──────────────────

    public function test_la_page_web_cree_modifie_et_archive_comme_avant(): void
    {
        $this->actingAs($this->vendeur);

        Livewire::test(ListeClients::class)
            ->set('name', 'Boulangerie Soleil')
            ->set('city', 'Porto-Novo')
            ->call('saveCustomer')
            ->assertHasNoErrors();

        $c = Customer::where('name', 'Boulangerie Soleil')->first();
        $this->assertNotNull($c);
        $this->assertTrue((bool) $c->is_active);

        Livewire::test(ListeClients::class)
            ->call('editCustomer', $c->id)
            ->set('city', 'Ouidah')
            ->call('saveCustomer')
            ->assertHasNoErrors();
        $this->assertSame('Ouidah', $c->fresh()->city);

        Livewire::test(ListeClients::class)->call('archiveCustomer', $c->id);
        $this->assertFalse((bool) $c->fresh()->is_active);
    }

    public function test_la_page_web_exige_le_nom_et_un_email_valide(): void
    {
        $this->actingAs($this->vendeur);

        Livewire::test(ListeClients::class)
            ->set('name', '')
            ->set('email', 'x')
            ->call('saveCustomer')
            ->assertHasErrors(['name', 'email']);
    }

    public function test_l_archivage_en_masse_ne_compte_que_les_actifs(): void
    {
        $this->actingAs($this->vendeur);
        $a = Customer::create(['name' => 'A', 'is_active' => true]);
        $b = Customer::create(['name' => 'B', 'is_active' => true]);
        $deja = Customer::create(['name' => 'C', 'is_active' => false]);

        Livewire::test(ListeClients::class)
            ->set('selectedIds', [$a->id, $b->id, $deja->id])
            ->call('bulkArchiveCustomers');

        $this->assertSame(0, Customer::where('is_active', true)->count());
        $this->assertSame(3, Customer::count(), 'jamais un DELETE');
    }
}
