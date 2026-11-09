<?php

namespace Tests\Feature;

use App\Http\Controllers\Api\SyncController;
use App\Livewire\Facturation\Facturation;
use App\Livewire\Ventes\Devis;
use App\Models\Permission;
use App\Models\Role;
use App\Models\Sale;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Livewire\Livewire;
use Tests\Feature\Concerns\AvecEmecef;
use Tests\TestCase;

/**
 * Ticket CONF-5 (3), DV-06 — LE CAISSIER CONSULTE ET RÉIMPRIME SES FACTURES, RIEN DE PLUS.
 *
 * Le menu montrait « Facturation » au caissier alors que `/facturation` (`can:view-facturation`) lui répondait 403. Il reçoit
 * `view-facturation` : il ouvre la liste et réimprime le PDF. Il n'a toujours NI `manage-facturation` (conversion de devis),
 * NI `correct-invoices` (avoir fiscal), NI la retransmission. Rôles : le VRAI seeder.
 */
class CaissierFacturationLectureTest extends TestCase
{
    use AvecEmecef;
    use RefreshDatabase;

    private User $caissier;

    private User $comptable;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->decorVentes();
        $this->reglerEmecef();

        $this->caissier = $this->compte('caissier');
        $this->comptable = $this->compte('comptable');
    }

    private function compte(string $role): User
    {
        $u = User::create([
            'name' => 'Compte '.$role, 'username' => 'c-'.$role, 'email' => $role.'@fermeolouwachegoun.com',
            'password' => bcrypt('LogiAgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    /** @return array<int, string> */
    private function droits(string $role): array
    {
        return Role::findByName($role, 'web')->permissions->pluck('name')->sort()->values()->all();
    }

    public function test_la_matrice_seedee_donne_la_lecture_de_la_facturation_au_caissier_et_aucune_ecriture(): void
    {
        $this->assertSame(['export-ventes', 'manage-ventes', 'view-facturation', 'view-ventes'], $this->droits('caissier'));
        $this->assertTrue($this->caissier->can('view-facturation'));
        foreach (['manage-facturation', 'correct-invoices', 'retransmettre-facture', 'avoir-client-fiscal'] as $interdit) {
            $this->assertFalse($this->caissier->can($interdit), "le caissier ne doit pas avoir {$interdit}");
        }
        // `retransmettre-facture` est une Gate (manage-facturation OU correct-invoices) : refusée au caissier.
        $this->assertTrue(\Illuminate\Support\Facades\Gate::forUser($this->caissier)->denies('retransmettre-facture'));
        $this->assertTrue(\Illuminate\Support\Facades\Gate::forUser($this->comptable)->allows('retransmettre-facture'));
    }

    public function test_le_caissier_ouvre_facturation_et_le_menu_ne_ment_plus(): void
    {
        $this->actingAs($this->caissier);
        $this->get('/facturation')->assertOk();
        // Le menu montre « Facturation » au caissier : la route lui répond désormais 200, jamais 403.
        $this->get('/dashboard')->assertOk()->assertSee('href="/facturation"', false);
    }

    public function test_le_caissier_reimprime_le_pdf_d_une_facture(): void
    {
        $vente = $this->venteAFacturer();
        $this->actingAs($this->caissier);

        Livewire::test(Facturation::class)
            ->call('imprimerFacture', $vente->id)
            ->assertOk()->assertFileDownloaded('facture-'.$vente->fresh()->numero_facture.'.pdf');
    }

    public function test_aucun_geste_d_ecriture_de_facturation_n_est_ouvert_au_caissier(): void
    {
        $vente = $this->venteAFacturer();
        $this->actingAs($this->caissier);

        // Retransmettre : refusé, et le bouton n'est pas montré.
        Livewire::test(Facturation::class)->call('retryMecef', $vente->id)->assertForbidden();
        Livewire::test(Facturation::class)->assertDontSee('wire:click="retryMecef', false);
        $this->assertNotSame('transmise', $vente->fresh()->mecef_status);

        // Convertir un devis en facture : `manage-ventes` ET `manage-facturation`.
        Livewire::test(Devis::class)->call('convertToInvoice', 'inexistant')->assertForbidden();
    }

    public function test_le_comptable_voit_toujours_le_bouton_de_retransmission(): void
    {
        $this->venteAFacturer();
        $this->actingAs($this->comptable);

        Livewire::test(Facturation::class)->assertSee('wire:click="retryMecef', false);
    }

    public function test_le_tirage_du_caissier_ne_recoit_que_ce_qu_il_doit_et_jamais_le_jeton_mecef(): void
    {
        $servies = SyncController::tablesServies($this->caissier);

        foreach (['sales', 'sale_lines', 'customers', 'receivables', 'quotes', 'credit_notes'] as $table) {
            $this->assertContains($table, $servies, "le caissier lit déjà {$table}");
        }
        foreach (['accounting_entries', 'purchase_orders', 'employees', 'corbeille', 'permissions'] as $table) {
            $this->assertNotContains($table, $servies, "le caissier ne reçoit pas {$table}");
        }
        // `view-facturation` n'a ouvert AUCUNE table de plus : la liste ne dépend pas de ce droit.
        $this->assertStringNotContainsString('view-facturation', json_encode(SyncController::PERMISSIONS_DE_TIRAGE));

        $reponse = $this->actingAs($this->caissier, 'sanctum')->getJson('/api/sync/pull')->assertOk();
        $this->assertStringNotContainsString(self::JETON, $reponse->getContent());
    }

    // ------------------------------------------------------------------ Migration

    private function migration(): object
    {
        return require database_path('migrations/2026_11_08_000005_accorder_view_facturation_caissier_conf5.php');
    }

    public function test_la_migration_accorde_la_lecture_au_caissier_existant_sans_rien_retirer_et_se_rejoue_sans_effet(): void
    {
        // Base « de production » d'avant CONF-5 : le caissier n'a pas la lecture ; un droit ajouté à la main reste.
        Role::findByName('caissier', 'web')->revokePermissionTo('view-facturation');
        Permission::findOrCreate('manage-stocks', 'web');
        Role::findByName('caissier', 'web')->givePermissionTo('manage-stocks');
        $comptableAvant = $this->droits('comptable');
        $animalierAvant = $this->droits('animalier');
        $adminAvant = $this->droits('admin');
        $this->assertFalse($this->caissier->fresh()->can('view-facturation'));

        $this->migration()->up();

        $this->assertSame(['export-ventes', 'manage-stocks', 'manage-ventes', 'view-facturation', 'view-ventes'], $this->droits('caissier'));
        $this->assertSame($comptableAvant, $this->droits('comptable'));
        $this->assertSame($animalierAvant, $this->droits('animalier'));
        $this->assertSame($adminAvant, $this->droits('admin'));

        $this->migration()->up();
        $this->assertSame(['export-ventes', 'manage-stocks', 'manage-ventes', 'view-facturation', 'view-ventes'], $this->droits('caissier'));
        $this->assertSame(1, Permission::where('name', 'view-facturation')->count());
        $this->assertSame(1, DB::table('role_has_permissions')
            ->where('role_id', Role::findByName('caissier', 'web')->id)
            ->where('permission_id', Permission::where('name', 'view-facturation')->value('id'))->count());
    }

    public function test_la_migration_cree_le_droit_s_il_manque_et_ignore_un_role_absent(): void
    {
        DB::table('role_has_permissions')->delete();
        DB::table('model_has_roles')->delete();
        Role::query()->delete();
        Permission::where('name', 'view-facturation')->delete();

        $this->migration()->up();
        $this->migration()->up();

        $this->assertSame(1, Permission::where('name', 'view-facturation')->count());
    }

    // ------------------------------------------------------------------ Gardes qui lisent les sources (mutations)

    public function test_source_le_seeder_donne_la_lecture_seule_au_caissier_et_les_gestes_portent_leurs_gardes(): void
    {
        // Sans les commentaires (le bloc du caissier cite les droits refusés pour l'expliquer).
        $seeder = preg_replace('#^\s*//.*$#m', '', file_get_contents(base_path('database/seeders/RolesAndPermissionsSeeder.php')));
        $this->assertMatchesRegularExpression("/findByName\\('caissier'\\)->givePermissionTo\\(\\[[^\\]]*'view-facturation'[^\\]]*\\]\\)/s", $seeder);
        $this->assertDoesNotMatchRegularExpression("/findByName\\('caissier'\\)->givePermissionTo\\(\\[[^\\]]*(manage-facturation|correct-invoices)/s", $seeder);

        $facturation = file_get_contents(base_path('app/Livewire/Facturation/Facturation.php'));
        $this->assertStringContainsString("authorize('retransmettre-facture')", $facturation);
        $this->assertStringContainsString("authorize('view-facturation')", $facturation);
        $this->assertStringContainsString("@can('retransmettre-facture')", file_get_contents(resource_path('views/livewire/facturation/facturation.blade.php')));
        $this->assertStringContainsString("authorize('manage-facturation')", file_get_contents(base_path('app/Livewire/Ventes/Devis.php')));
    }
}
