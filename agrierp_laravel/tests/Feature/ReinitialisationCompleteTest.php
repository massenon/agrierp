<?php

namespace Tests\Feature;

use App\Models\CompanySetting;
use App\Models\Notification;
use App\Models\User;
use App\Services\ReinitialisationDonneesService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Ticket 15.50 — LA RÉINITIALISATION VIDE TOUT, ET LE POSTE LE SAIT.
 *
 * 🔴 Avant :
 *  - la liste nommait `correspondences`, table inexistante : les courriers (`mails`) n'étaient JAMAIS vidés ;
 *  - transferts entre bandes, immobilisations et notifications survivaient (registre d'immobilisations sans
 *    écriture, alertes pointant vers des bandes effacées) ;
 *  - quinze tables n'étaient classées nulle part : la prochaine table oubliée l'aurait été sans bruit ;
 *  - un poste hors ligne au moment de la réinitialisation renvoyait ensuite ses données effacées.
 */
class ReinitialisationCompleteTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);

        $this->admin = User::create([
            'name' => 'Directeur', 'username' => 'admin', 'email' => 'dg@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->admin->assignRole('admin');

        CompanySetting::create(['company_name' => 'Ferme École OLOUWACHEGOUN']);
    }

    /** ⚠️ Le garde-fou qui aurait évité les oublis : chaque table du schéma est classée UNE fois. */
    public function test_chaque_table_du_schema_est_classee_une_seule_fois(): void
    {
        $listes = [
            'vidées' => ReinitialisationDonneesService::tablesTransactionnelles(),
            'préservées' => ReinitialisationDonneesService::tablesPreservees(),
            'techniques' => ReinitialisationDonneesService::tablesTechniques(),
        ];
        $schema = array_map(fn ($t) => $t['name'], Schema::getTables());

        foreach ($schema as $table) {
            $classements = array_keys(array_filter($listes, fn ($l) => in_array($table, $l, true)));
            $this->assertCount(1, $classements, "« {$table} » : classée ".count($classements).' fois');
        }

        foreach (array_merge(...array_values($listes)) as $table) {
            $this->assertContains($table, $schema, "« {$table} » est listée mais n'existe pas");
        }
    }

    public function test_courriers_notifications_transferts_et_immobilisations_sont_vides(): void
    {
        DB::table('mails')->insert([
            'id' => (string) Str::uuid(), 'reference' => 'CR-2026-001', 'type' => 'entrant',
            'subject' => 'Courrier', 'party' => 'Mairie', 'mail_date' => '2026-10-01', 'is_active' => true,
        ]);
        Notification::create([
            'target_role' => 'admin', 'type' => 'stock_low', 'severity' => 'moyen',
            'title' => 'Stock sous le seuil', 'message' => 'x', 'link_url' => '/seuils-alerte', 'is_read' => false,
        ]);

        $supprimees = app(ReinitialisationDonneesService::class)->executer();

        $this->assertSame(0, DB::table('mails')->count());
        $this->assertSame(0, Notification::count());
        $this->assertSame(1, $supprimees['mails']);
        $this->assertSame(1, $supprimees['notifications']);
        foreach (['livestock_transfers', 'fixed_assets'] as $table) {
            $this->assertContains($table, ReinitialisationDonneesService::tablesTransactionnelles());
        }
    }

    public function test_la_marque_de_reinitialisation_est_posee_et_servie_au_tirage(): void
    {
        Sanctum::actingAs($this->admin);
        $this->getJson('/api/sync/pull')->assertOk()->assertJsonPath('data_reset_at', null);

        $this->travelTo(now()->setTime(10, 30, 0));
        app(ReinitialisationDonneesService::class)->executer();

        $marque = CompanySetting::first()->data_reset_at;
        $this->assertNotNull($marque);
        $this->getJson('/api/sync/pull')->assertOk()->assertJsonPath('data_reset_at', $marque->toIso8601String());
    }

    /** 🔴 Le poste qui n'a pas vu la réinitialisation ne ressuscite rien. */
    public function test_un_envoi_sans_la_marque_est_refuse_en_bloc_apres_reinitialisation(): void
    {
        app(ReinitialisationDonneesService::class)->executer();
        Sanctum::actingAs($this->admin);

        $this->postJson('/api/sync/push', ['device_id' => 'poste-1', 'mails' => [$this->courrier()]])
            ->assertStatus(409)
            ->assertJsonPath('message', fn ($m) => str_contains($m, 'réinitialisées le'));

        $this->postJson('/api/sync/push', [
            'device_id' => 'poste-1', 'data_reset_at' => '2020-01-01T00:00:00+00:00', 'mails' => [$this->courrier()],
        ])->assertStatus(409);

        $this->assertSame(0, DB::table('mails')->count());
    }

    public function test_un_envoi_portant_la_marque_connue_est_traite(): void
    {
        app(ReinitialisationDonneesService::class)->executer();
        Sanctum::actingAs($this->admin);
        $marque = CompanySetting::first()->data_reset_at->toIso8601String();

        $this->postJson('/api/sync/push', [
            'device_id' => 'poste-1', 'data_reset_at' => $marque, 'mails' => [$this->courrier()],
        ])->assertOk();

        $this->assertSame(1, DB::table('mails')->count());
    }

    /** Une ferme qui n'a jamais réinitialisé n'exige rien des postes (anciens compris). */
    public function test_sans_reinitialisation_aucune_marque_n_est_exigee(): void
    {
        Sanctum::actingAs($this->admin);

        $this->postJson('/api/sync/push', ['device_id' => 'poste-1', 'mails' => [$this->courrier()]])->assertOk();

        $this->assertSame(1, DB::table('mails')->count());
    }

    private function courrier(): array
    {
        return [
            'id' => '77777777-7777-4777-8777-777777777777', 'type' => 'entrant',
            'subject' => 'Courrier du poste', 'party' => 'Mairie', 'mail_date' => now()->toDateString(),
            'is_active' => true,
        ];
    }
}
