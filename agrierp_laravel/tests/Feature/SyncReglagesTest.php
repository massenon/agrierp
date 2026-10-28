<?php

namespace Tests\Feature;

use App\Models\AccountingEntry;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\CompanySetting;
use App\Models\FiscalYear;
use App\Models\IncomeTaxBracket;
use App\Models\Permission;
use App\Models\Role;
use App\Models\TreasuryAccount;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Tickets PA-2, PA-3, PA-4, PA-7, PA-8 — LES RÉGLAGES DE LA FERME SE DEMANDENT AU POSTE (`settings_requests`).
 *
 * Chaque type passe par le service du web : mêmes règles, mêmes messages, mêmes audits, mêmes verrous.
 */
class SyncReglagesTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    private User $gestionnaire;

    private User $lecteur;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['manage-parametres', 'view-parametres', 'manage-comptabilite', 'manage-users'] as $p) {
            Permission::findOrCreate($p, 'web');
        }
        Role::findOrCreate('admin', 'web')->givePermissionTo(['manage-parametres', 'view-parametres', 'manage-comptabilite', 'manage-users']);
        Role::findOrCreate('comptable', 'web')->givePermissionTo(['view-parametres', 'manage-parametres']);
        Role::findOrCreate('lecteur', 'web')->givePermissionTo('view-parametres');
        $this->admin = $this->utilisateur('admin');
        $this->gestionnaire = $this->utilisateur('comptable');
        $this->lecteur = $this->utilisateur('lecteur');
    }

    private function utilisateur(string $role): User
    {
        $u = User::create(['name' => ucfirst($role), 'username' => $role, 'email' => $role.'@fermeolouwachegoun.com', 'password' => bcrypt('x'), 'is_active' => true]);
        $u->assignRole($role);

        return $u;
    }

    private function envoyer(User $u, string $kind, array $payload, ?string $id = null)
    {
        $id ??= (string) Str::uuid();

        return [$id, $this->actingAs($u, 'sanctum')->postJson('/api/sync/push', [
            'device_id' => 'poste-test', 'settings_requests' => [['id' => $id, 'kind' => $kind, 'payload' => $payload]],
        ])];
    }

    private function entreprise(array $remplace = []): array
    {
        return array_merge([
            'companyName' => 'Ferme École OLOUWACHEGOUN', 'promoterName' => 'Dr MASSENON', 'address' => 'Ikpinlè', 'phone' => '0197000000',
            'email' => 'contact@ferme.test', 'ifu' => '3201700000000', 'rccm' => 'RB/ABC/17', 'tvaEnabled' => true,
            'vpsRate' => 4, 'cnssEmployeeRate' => 3.6, 'cnssEmployerPensionRate' => 6.4, 'cnssEmployerFamilyRate' => 9, 'cnssEmployerRiskRate' => 2,
        ], $remplace);
    }

    public function test_l_entreprise_est_enregistree_puis_ses_taux_sont_arretes_pour_les_non_administrateurs(): void
    {
        [$id, $r] = $this->envoyer($this->gestionnaire, 'entreprise', $this->entreprise());
        $r->assertOk()->assertJsonPath('settings_requests.accepted.0', $id);
        $this->assertSame('Ferme École OLOUWACHEGOUN', CompanySetting::current()->company_name);
        $this->assertNotNull(CompanySetting::current()->payroll_settings_edited_at);

        // Identité modifiable, taux arrêtés : un non-administrateur est refusé avec le motif du web.
        [, $r] = $this->envoyer($this->gestionnaire, 'entreprise', $this->entreprise(['vpsRate' => 2]));
        $this->assertStringContainsString('Seul un administrateur', $r->json('settings_requests.rejected.0.reason'));
        $this->assertEquals(4, CompanySetting::current()->vps_rate);

        [$id, $r] = $this->envoyer($this->admin, 'entreprise', $this->entreprise(['vpsRate' => 2]));
        $r->assertJsonPath('settings_requests.accepted.0', $id);
        $this->assertEquals(2, CompanySetting::current()->vps_rate);
    }

    public function test_le_logo_et_le_favicon_du_poste_sont_ranges_comme_au_web_et_servis_au_poste(): void
    {
        Storage::fake('public');
        $png = base64_encode(base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='));

        [$id, $r] = $this->envoyer($this->gestionnaire, 'entreprise', $this->entreprise(['logoB64' => $png, 'faviconB64' => $png]));
        $r->assertOk()->assertJsonPath('settings_requests.accepted.0', $id);

        $e = CompanySetting::current();
        $this->assertStringStartsWith('company/', $e->logo_path);
        $this->assertStringEndsWith('.png', $e->favicon_path);
        Storage::disk('public')->assertExists($e->logo_path);

        // Le tirage porte les chemins ; le fichier se télécharge ensuite.
        $tirage = $this->actingAs($this->gestionnaire, 'sanctum')->getJson('/api/sync/pull')->assertOk();
        $this->assertSame($e->logo_path, $tirage->json('company_settings.logo_path'));
        $this->actingAs($this->gestionnaire, 'sanctum')->get('/api/sync/company-file/logo')->assertOk();
        $this->actingAs($this->gestionnaire, 'sanctum')->get('/api/sync/company-file/autre')->assertNotFound();
    }

    public function test_un_logo_qui_n_est_pas_une_image_ou_trop_gros_est_refuse(): void
    {
        Storage::fake('public');

        [, $r] = $this->envoyer($this->gestionnaire, 'entreprise', $this->entreprise(['logoB64' => base64_encode('pas une image')]));
        $this->assertStringContainsString('doit être une image', $r->json('settings_requests.rejected.0.reason'));
        $this->assertNull(CompanySetting::query()->first()?->logo_path);

        $gros = base64_encode(base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==').str_repeat("\0", 600 * 1024));
        [, $r] = $this->envoyer($this->gestionnaire, 'entreprise', $this->entreprise(['faviconB64' => $gros]));
        $this->assertStringContainsString('500 Ko', $r->json('settings_requests.rejected.0.reason'));
    }

    public function test_les_regles_de_l_entreprise_sont_celles_du_web(): void
    {
        [, $r] = $this->envoyer($this->gestionnaire, 'entreprise', $this->entreprise(['ifu' => '12AB', 'cnssEmployerRiskRate' => 9]));

        $this->assertNotEmpty($r->json('settings_requests.rejected.0.reason'));
        $this->assertNull(CompanySetting::query()->first()?->ifu);
    }

    public function test_le_bareme_its_est_remplace_verifie_et_arrete(): void
    {
        $bon = [['from' => 0, 'to' => 60000, 'rate' => 0], ['from' => 60000, 'to' => 150000, 'rate' => 10], ['from' => 150000, 'to' => null, 'rate' => 15]];
        [$id, $r] = $this->envoyer($this->gestionnaire, 'bareme_its', ['tranches' => $bon]);
        $r->assertJsonPath('settings_requests.accepted.0', $id);
        $this->assertSame(3, IncomeTaxBracket::count());

        [, $r] = $this->envoyer($this->gestionnaire, 'bareme_its', ['tranches' => $bon]);
        $this->assertStringContainsString('Seul un administrateur', $r->json('settings_requests.rejected.0.reason'));

        [, $r] = $this->envoyer($this->admin, 'bareme_its', ['tranches' => [['from' => 0, 'to' => 60000, 'rate' => 0], ['from' => 70000, 'to' => null, 'rate' => 10]]]);
        $this->assertStringContainsString('sans trou ni chevauchement', $r->json('settings_requests.rejected.0.reason'));
        $this->assertSame(3, IncomeTaxBracket::count(), 'un barème refusé ne touche pas à l\'ancien');
    }

    public function test_un_compte_bancaire_et_une_ligne_momo_sont_crees_une_seule_fois(): void
    {
        $banque = ['geste' => 'banque', 'bankName' => 'Ecobank', 'holderName' => 'Ferme', 'rib' => 'BJ0001', 'iban' => 'BJ66BJ0001', 'accountCode' => '5211'];
        [$id, $r] = $this->envoyer($this->gestionnaire, 'mode_paiement', $banque);
        $r->assertJsonPath('settings_requests.accepted.0', $id);
        $this->envoyer($this->gestionnaire, 'mode_paiement', $banque, $id);

        $compte = TreasuryAccount::findOrFail($id);
        $this->assertSame(['banque', 'Ecobank - 5211', '5211'], [$compte->type, $compte->label, $compte->account_code]);
        $this->assertSame(1, TreasuryAccount::count());

        [$mid] = $this->envoyer($this->gestionnaire, 'mode_paiement', ['geste' => 'momo', 'operatorName' => 'MTN', 'phoneNumber' => '0197']);
        $this->assertSame('5212', TreasuryAccount::findOrFail($mid)->account_code);

        [, $r] = $this->envoyer($this->gestionnaire, 'mode_paiement', ['geste' => 'banque', 'bankName' => '', 'rib' => '', 'iban' => '']);
        $this->assertNotEmpty($r->json('settings_requests.rejected.0.reason'));
    }

    public function test_un_virement_interne_ne_se_rejoue_pas_et_refuse_un_solde_insuffisant(): void
    {
        Permission::findOrCreate('manage-comptabilite', 'web');
        $this->gestionnaire->givePermissionTo('manage-comptabilite');
        FiscalYear::create(['year' => (int) now()->format('Y'), 'start_date' => now()->startOfYear()->toDateString(), 'end_date' => now()->endOfYear()->toDateString(), 'status' => 'ouvert']);
        foreach ([['531', 'Caisse'], ['521', 'Banque']] as [$c, $l]) {
            ChartOfAccount::firstOrCreate(['code' => $c], ['label' => $l, 'class' => 5, 'is_active' => true]);
        }
        $caisse = TreasuryAccount::create(['label' => 'Caisse', 'type' => 'caisse', 'account_code' => '531', 'balance' => 100000, 'is_active' => true]);
        $banque = TreasuryAccount::create(['label' => 'Banque', 'type' => 'banque', 'account_code' => '521', 'balance' => 0, 'is_active' => true]);
        $v = ['geste' => 'virement', 'transferFromId' => $caisse->id, 'transferToId' => $banque->id, 'transferAmount' => 40000, 'transferReason' => 'Dépôt'];

        [$id, $r] = $this->envoyer($this->gestionnaire, 'mode_paiement', $v);
        $r->assertJsonPath('settings_requests.accepted.0', $id);
        $this->envoyer($this->gestionnaire, 'mode_paiement', $v, $id);

        $this->assertEquals(60000, $caisse->fresh()->balance);
        $this->assertEquals(40000, $banque->fresh()->balance);
        $this->assertSame(1, AccountingEntry::where('source_type', 'treasury_transfer')->where('source_id', $id)->count());

        [, $r] = $this->envoyer($this->gestionnaire, 'mode_paiement', array_merge($v, ['transferAmount' => 999999]));
        $this->assertSame([], $r->json('settings_requests.accepted'));
        $this->assertStringContainsString('Solde insuffisant', $r->json('settings_requests.rejected.0.reason'));
    }

    public function test_les_roles_sont_reserves_a_l_administrateur_avec_les_garde_fous_du_web(): void
    {
        $perm = Permission::findOrCreate('view-ventes', 'web');

        [, $r] = $this->envoyer($this->lecteur, 'role', ['roleName' => 'x', 'permissions' => []]);
        $this->assertSame([], $r->json('settings_requests.accepted'));

        [$id, $r] = $this->envoyer($this->admin, 'role', ['roleName' => 'responsable-achats', 'permissions' => ['view-ventes']]);
        $r->assertJsonPath('settings_requests.accepted.0', $id);
        $this->assertTrue(Role::where('name', 'responsable-achats')->first()->hasPermissionTo($perm));

        [, $r] = $this->envoyer($this->admin, 'role', ['roleName' => 'Mauvais Nom', 'permissions' => []]);
        $this->assertStringContainsString('lettres minuscules', $r->json('settings_requests.rejected.0.reason'));

        [, $r] = $this->envoyer($this->admin, 'role', ['geste' => 'supprimer', 'roleName' => 'comptable']);
        $this->assertStringContainsString('4 rôles fondamentaux', $r->json('settings_requests.rejected.0.reason'));

        [$id, $r] = $this->envoyer($this->admin, 'role', ['geste' => 'supprimer', 'roleName' => 'responsable-achats']);
        $r->assertJsonPath('settings_requests.accepted.0', $id);
        $this->assertNull(Role::where('name', 'responsable-achats')->first());
    }

    public function test_la_configuration_sms_garde_le_secret_existant_s_il_est_laisse_vide(): void
    {
        $this->envoyer($this->gestionnaire, 'sms', ['smsProvider' => 'twilio', 'twilioSid' => 'AC1', 'twilioFrom' => '+229', 'twilioToken' => 'secret-1']);
        $this->envoyer($this->gestionnaire, 'sms', ['smsProvider' => 'twilio', 'twilioSid' => 'AC2', 'twilioFrom' => '+229', 'twilioToken' => '']);

        $c = CompanySetting::current()->fresh();
        $this->assertSame('AC2', $c->twilio_account_sid);
        $this->assertSame('secret-1', $c->twilio_auth_token_encrypted);

        [, $r] = $this->envoyer($this->gestionnaire, 'sms', ['smsProvider' => 'autre']);
        $this->assertNotEmpty($r->json('settings_requests.rejected.0.reason'));
    }

    public function test_un_lecteur_ne_peut_rien_regler_et_le_tirage_ne_sert_jamais_un_secret(): void
    {
        [, $r] = $this->envoyer($this->lecteur, 'entreprise', $this->entreprise());
        $this->assertSame([], $r->json('settings_requests.accepted'));
        [, $r] = $this->envoyer($this->lecteur, 'type-inconnu', []);
        $this->assertSame([], $r->json('settings_requests.accepted'));

        CompanySetting::current()->update(['sms_provider' => 'twilio', 'twilio_account_sid' => 'AC9', 'twilio_auth_token_encrypted' => 'TOP-SECRET']);
        $json = $this->actingAs($this->gestionnaire, 'sanctum')->getJson('/api/sync/pull')->assertOk();
        $this->assertStringNotContainsString('TOP-SECRET', $json->getContent());
        $this->assertTrue($json->json('company_settings.sms_secret_set'));
        $this->assertArrayNotHasKey('twilio_account_sid', $this->actingAs($this->lecteur, 'sanctum')->getJson('/api/sync/pull')->json('company_settings') ?? []);
    }
}
