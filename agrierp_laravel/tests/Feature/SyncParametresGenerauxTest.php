<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\CompanySetting;
use App\Models\ModuleConfig;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Ticket 14.84 (Sprint 14) — LE HUB PARAMÈTRES GÉNÉRAL DESCEND AU POSTE.
 *
 * Six onglets : Rôles & Permissions, Données de l'Entreprise, Modules Actifs,
 * Gestion Utilisateurs, Modes de Paiement, Audit Logs.
 *
 * 🔴🔴 AUCUN SECRET NE DESCEND. `company_settings` porte
 * `smtp_password_encrypted`, `twilio_auth_token_encrypted` et
 * `vonage_api_secret_encrypted`. Un poste volé donnerait alors la boîte mail et
 * le compte SMS de la ferme. Le tirage ne sert QUE l'identité et les taux —
 * c'est vérifié ici sur la charge utile entière, pas sur une intention.
 *
 * 🔴🔴 LE PIÈGE DES UUID DE SPATIE, DÉJÀ DOCUMENTÉ SUR LE SEEDER, S'ÉTAIT
 * REPRODUIT ICI. `Spatie\Permission\Models\Role` déclare sa clé
 * auto-incrémentée : Eloquent caste alors `roles.id` en entier, et l'UUID
 * « 01a01168-71ea-… » descendait au poste sous la forme « 1 ». Les QUATRE rôles
 * portaient le même identifiant, et la relation `permissions` ne retrouvait
 * plus une seule ligne du pivot — la matrice des droits serait arrivée vide.
 * `App\Models\Role`, qui ajoute `HasUuids`, est le seul modèle à utiliser.
 */
class SyncParametresGenerauxTest extends TestCase
{
    use RefreshDatabase;

    private User $administrateur;

    protected function setUp(): void
    {
        parent::setUp();

        $this->administrateur = User::create([
            'name' => 'Manager Olouwachegoun', 'username' => 'admin',
            'email' => 'dg@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);

        // Ticket S3 : le journal d'audit ne descend qu'aux comptes qui gèrent les utilisateurs. Permission
        // directe, sans rôle : ces tests créent eux-mêmes les rôles dont ils vérifient le transport.
        Permission::findOrCreate('manage-users', 'web');
        $this->administrateur->givePermissionTo('manage-users');
    }

    private function tirer(): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($this->administrateur, 'sanctum')
            ->getJson('/api/sync/pull');
    }

    private function role(string $nom, array $permissions): Role
    {
        $role = Role::create(['name' => $nom, 'guard_name' => 'web']);

        foreach ($permissions as $permission) {
            $role->givePermissionTo(
                Permission::firstOrCreate(['name' => $permission, 'guard_name' => 'web'])
            );
        }

        return $role;
    }

    /**
     * 🔴🔴 LE DÉFAUT QUE LE POSTE A SIGNALÉ AU PREMIER TIRAGE RÉEL : contrainte
     * d'unicité violée sur `roles_applicatifs.id`, parce que les quatre rôles
     * arrivaient avec l'identifiant « 1 ».
     */
    public function test_each_role_travels_with_its_own_uuid(): void
    {
        $this->role('admin', ['view-parametres']);
        $this->role('comptable', ['view-comptabilite']);
        $this->role('caissier', ['view-ventes']);

        $reponse = $this->tirer()->assertOk();

        $identifiants = collect($reponse->json('roles'))->pluck('id');

        $this->assertCount(3, $identifiants);
        $this->assertCount(
            3,
            $identifiants->unique(),
            'Les rôles descendent avec le même identifiant : le poste refuse le référentiel entier.'
        );

        foreach ($identifiants as $identifiant) {
            $this->assertMatchesRegularExpression(
                '/^[0-9a-f]{8}-[0-9a-f]{4}-/',
                $identifiant,
                "L'identifiant « {$identifiant} » n'est pas un UUID : la clé a été castée en entier."
            );
        }
    }

    /**
     * 🔴 SANS SES PERMISSIONS, UN RÔLE N'EST QU'UN NOM. La matrice des droits du
     * poste coche une colonne par permission `view-*` : une liste vide
     * afficherait quatre rôles sans aucun droit, ce qui est faux et alarmant.
     */
    public function test_a_role_travels_with_its_named_permissions(): void
    {
        $this->role('comptable', ['view-comptabilite', 'close-fiscal-year']);

        $permissions = $this->tirer()->assertOk()->json('roles.0.permissions');

        $this->assertContains('view-comptabilite', $permissions);
        $this->assertContains('close-fiscal-year', $permissions);
    }

    /**
     * 🔴🔴 LA GARDE LA PLUS IMPORTANTE DU TICKET : aucun secret, sous aucune
     * clé, nulle part dans la charge utile.
     */
    public function test_no_secret_ever_reaches_the_device(): void
    {
        CompanySetting::query()->delete();

        CompanySetting::create([
            'company_name' => 'Ferme École OLOUWACHEGOUN',
            'promoter_name' => 'OLOUKOUNLE Olouchégoun Hassimiyou',
            'ifu' => '3202601234567',
            'smtp_password_encrypted' => encrypt('secret-smtp-de-la-ferme'),
            'twilio_auth_token_encrypted' => encrypt('jeton-twilio'),
            'vonage_api_secret_encrypted' => encrypt('secret-vonage'),
        ]);

        $charge = $this->tirer()->assertOk()->json();
        $entreprise = $charge['company_settings'];

        $this->assertSame('Ferme École OLOUWACHEGOUN', $entreprise['company_name']);
        $this->assertSame('3202601234567', $entreprise['ifu']);

        foreach (['password', 'secret', 'token', 'api_key'] as $interdit) {
            foreach (array_keys($entreprise) as $cle) {
                $this->assertStringNotContainsString(
                    $interdit,
                    $cle,
                    "La clé « {$cle} » descend au poste : un poste perdu ouvrirait le service correspondant."
                );
            }
        }

        $serialise = json_encode($charge, JSON_UNESCAPED_UNICODE);

        $this->assertStringNotContainsString('secret-smtp-de-la-ferme', $serialise);
        $this->assertStringNotContainsString('jeton-twilio', $serialise);
        $this->assertStringNotContainsString('secret-vonage', $serialise);
    }

    /**
     * 🔴 NI MOT DE PASSE NI JETON POUR LES UTILISATEURS NON PLUS. La liste sert
     * à savoir QUI travaille sur la ferme ; l'authentification du poste passe
     * par `POST /api/auth/login`.
     */
    public function test_the_user_list_carries_no_credential(): void
    {
        $utilisateurs = $this->tirer()->assertOk()->json('users');

        $this->assertNotEmpty($utilisateurs);

        foreach ($utilisateurs as $utilisateur) {
            $this->assertArrayNotHasKey('password', $utilisateur);
            $this->assertArrayNotHasKey('remember_token', $utilisateur);
            $this->assertArrayHasKey('name', $utilisateur);
        }
    }

    /**
     * 🔴🔴 `modules_config` DÉCIDE DES ESPÈCES VISIBLES AU POSTE. L'héliciculture
     * est éteinte sur cette ferme, et le poste proposait pourtant la fiche
     * Escargots — la maquette, elle, masque les blocs `data-module="helico"`.
     */
    public function test_the_module_switches_reach_the_device(): void
    {
        ModuleConfig::query()->delete();

        ModuleConfig::create(['species_code' => 'cuniculture', 'is_enabled' => true]);
        ModuleConfig::create(['species_code' => 'helico', 'is_enabled' => false]);

        $modules = collect($this->tirer()->assertOk()->json('modules_config'))
            ->keyBy('species_code');

        $this->assertTrue((bool) $modules['cuniculture']['is_enabled']);
        $this->assertFalse((bool) $modules['helico']['is_enabled']);
    }

    /**
     * ⚠️ PAS TOUT L'HISTORIQUE : la table grossit d'une ligne par action, et un
     * poste n'a pas à en porter des années. Ticket U14 : DEUX CENTS lignes, la
     * liste de l'onglet du web (`AuditLogs::getLogsProperty()`, `limit(200)`),
     * et non cent — l'onglet du poste montre la même liste.
     */
    public function test_le_journal_tire_est_plafonne_a_la_liste_du_web(): void
    {
        AuditLog::query()->delete();

        for ($i = 0; $i < 220; $i++) {
            AuditLog::create([
                'user_id' => $this->administrateur->id,
                'action' => 'api.login',
                'module' => 'auth',
                'ip_address' => '127.0.0.1',
            ]);
        }

        $traces = $this->tirer()->assertOk()->json('audit_logs');

        $this->assertCount(200, $traces);
    }

    /**
     * ⚠️ LES COMPTES DE TRÉSORERIE PORTENT LEUR TYPE : c'est lui qui range un
     * compte sous « Caisse Physique », « Comptes Bancaires » ou « Mobile
     * Money » — les trois sections de la maquette.
     */
    public function test_treasury_accounts_travel_with_their_family(): void
    {
        $types = collect(DB::table('treasury_accounts')->pluck('type'))->unique();

        $servis = collect($this->tirer()->assertOk()->json('treasury_accounts'))
            ->pluck('type')
            ->unique();

        $this->assertEqualsCanonicalizing($types->all(), $servis->all());
    }
}
