<?php

namespace Tests\Feature;

use App\Livewire\Parametres\DonneesEntreprise;
use App\Models\AuditLog;
use App\Models\CompanySetting;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use App\Services\Mecef\MecefReglage;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * MECEF-1 — LE RÉGLAGE DU MODE de facturation normalisée (désactivé / e-MECeF / boîtier), et le JETON JWT, qui est un SECRET :
 * chiffré en base, masqué à l'écran, jamais servi au poste, jamais journalisé.
 */
class MecefModeReglageTest extends TestCase
{
    use RefreshDatabase;

    private const JETON = 'eyJhbGciOiJIUzI1NiJ9.SECRET-JETON-DGI.signature';

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->admin = User::create(['name' => 'Admin', 'username' => 'adm', 'email' => 'adm@x.bj', 'password' => bcrypt('x'), 'is_active' => true]);
        $this->admin->assignRole('admin');
        CompanySetting::current()->update(['company_name' => 'Ferme', 'ifu' => '3202601234567']);
    }

    private function ecran()
    {
        return Livewire::actingAs($this->admin)->test(DonneesEntreprise::class);
    }

    public function test_sans_reglage_le_commutateur_general_decide_et_actif_est_derive_du_mode(): void
    {
        $reglage = app(MecefReglage::class);

        config(['mecef.actif' => false]);
        $this->assertSame('desactive', $reglage->mode());
        $this->assertFalse($reglage->actif());

        config(['mecef.actif' => true]);
        $this->assertSame('simule', $reglage->mode(), 'rien n\'est réglé : la démonstration des tests / du développement');
        $this->assertTrue($reglage->actif());

        // Le réglage enregistré prime sur le commutateur.
        CompanySetting::current()->update(['mecef_mode' => 'desactive']);
        $this->assertFalse($reglage->actif());
        CompanySetting::current()->update(['mecef_mode' => 'boitier']);
        $this->assertSame('boitier', $reglage->mode());
        $this->assertTrue($reglage->actif());
    }

    public function test_l_ecran_enregistre_le_mode_les_champs_e_mecef_et_chiffre_le_jeton(): void
    {
        $this->ecran()
            ->set('mecefMode', 'emecef')->set('mecefApiUrl', 'https://emcf.test/api')
            ->set('mecefOperateurId', '12')->set('mecefOperateurNom', 'Caissière Awa')->set('mecefJeton', self::JETON)
            ->call('save')->assertHasNoErrors()->assertSet('mecefJeton', '');

        $r = CompanySetting::current();
        $this->assertSame('emecef', $r->mecef_mode);
        $this->assertSame('https://emcf.test/api', $r->mecef_api_url);
        $this->assertSame('12', $r->mecef_operateur_id);
        $this->assertSame('Caissière Awa', $r->mecef_operateur_nom);
        $this->assertSame(self::JETON, $r->mecef_jeton_encrypted, 'relu clair par le cast');

        $brut = DB::table('company_settings')->value('mecef_jeton_encrypted');
        $this->assertNotSame(self::JETON, $brut);
        $this->assertStringNotContainsString('SECRET-JETON', (string) $brut, 'chiffré en base, jamais en clair');
    }

    public function test_le_jeton_est_masque_a_l_ecran_et_se_remplace_sans_jamais_etre_relu(): void
    {
        CompanySetting::current()->update(['mecef_mode' => 'emecef', 'mecef_jeton_encrypted' => self::JETON]);

        $ecran = $this->ecran();
        $ecran->assertSee('••••')->assertSee('Remplacer')->assertDontSee('SECRET-JETON')->assertSet('mecefJeton', '');
        $this->assertStringNotContainsString('SECRET-JETON', $ecran->html());
        $this->assertStringNotContainsString('SECRET-JETON', json_encode($ecran->snapshot), 'rien du secret dans l\'état envoyé au navigateur');

        // Enregistrer sans remplacer : le jeton est CONSERVÉ.
        $ecran->call('save')->assertHasNoErrors();
        $this->assertSame(self::JETON, CompanySetting::current()->mecef_jeton_encrypted);

        // Remplacer : le champ de saisie apparaît, le nouveau jeton prend la place.
        $ecran->call('$set', 'remplacerJeton', true)->set('mecefJeton', 'NOUVEAU-JETON')->call('save');
        $this->assertSame('NOUVEAU-JETON', CompanySetting::current()->mecef_jeton_encrypted);
    }

    public function test_emecef_exige_un_ifu_de_13_chiffres_et_n_ecrit_rien_sinon(): void
    {
        $this->ecran()->set('ifu', '12345')->set('mecefMode', 'emecef')->call('save')
            ->assertHasErrors('ifu')->assertSee("L'IFU doit comporter 13 chiffres pour la facturation e-MECeF.");

        $this->assertNull(CompanySetting::current()->mecef_mode);
        $this->assertSame('3202601234567', CompanySetting::current()->ifu);

        // Hors mode e-MECeF, un IFU court reste accepté (comportement d'avant).
        $this->ecran()->set('ifu', '12345')->set('mecefMode', 'desactive')->call('save')->assertHasNoErrors();
    }

    public function test_une_adresse_d_api_invalide_est_refusee_en_francais(): void
    {
        $this->ecran()->set('mecefMode', 'emecef')->set('mecefApiUrl', 'pas une adresse')->call('save')
            ->assertHasErrors('mecefApiUrl')->assertSee("L'adresse de l'API e-MECeF doit être une adresse web complète");
    }

    public function test_l_audit_dit_que_le_reglage_a_change_sans_jamais_porter_de_valeur(): void
    {
        $this->ecran()->set('mecefMode', 'emecef')->set('mecefJeton', self::JETON)->set('mecefApiUrl', 'https://emcf.test/api')->call('save');

        $this->assertSame(1, AuditLog::where('action', 'company_settings.mecef_updated')->count());
        $this->assertSame('Réglage de la facturation normalisée (MeCeF) modifié', AuditLog::where('action', 'company_settings.mecef_updated')->first()->action_label);
        $this->assertStringNotContainsString('SECRET-JETON', json_encode(AuditLog::all()->toArray()));

        // Rien n'a changé : pas de nouvelle ligne dédiée.
        $this->ecran()->call('save');
        $this->assertSame(1, AuditLog::where('action', 'company_settings.mecef_updated')->count());
    }

    public function test_le_tirage_sert_le_mode_et_un_booleen_jamais_le_jeton(): void
    {
        CompanySetting::current()->update(['mecef_mode' => 'emecef', 'mecef_jeton_encrypted' => self::JETON, 'mecef_api_url' => 'https://emcf.test/api', 'mecef_operateur_nom' => 'Awa']);

        $reponse = $this->actingAs($this->admin, 'sanctum')->getJson('/api/sync/pull')->assertOk();

        $reponse->assertJsonPath('company_settings.mecef_actif', true)
            ->assertJsonPath('company_settings.mecef_mode', 'emecef')
            ->assertJsonPath('company_settings.mecef_jeton_configure', true)
            ->assertJsonPath('company_settings.mecef_operateur_nom', 'Awa');
        $this->assertStringNotContainsString('SECRET-JETON', $reponse->getContent());
        $this->assertStringNotContainsString(base64_encode(self::JETON), $reponse->getContent());
        $this->assertArrayNotHasKey('mecef_jeton_encrypted', $reponse->json('company_settings'));
        $this->assertArrayNotHasKey('mecef_jeton', $reponse->json('company_settings'));

        CompanySetting::current()->update(['mecef_mode' => 'desactive', 'mecef_jeton_encrypted' => null]);
        $this->actingAs($this->admin, 'sanctum')->getJson('/api/sync/pull')
            ->assertJsonPath('company_settings.mecef_actif', false)->assertJsonPath('company_settings.mecef_jeton_configure', false);
    }

    private function demande(array $payload)
    {
        $id = (string) \Illuminate\Support\Str::uuid();

        return [$id, $this->actingAs($this->admin, 'sanctum')->postJson('/api/sync/push', [
            'device_id' => 'poste-test', 'settings_requests' => [['id' => $id, 'kind' => 'entreprise', 'payload' => $payload]],
        ])];
    }

    private function entreprise(array $plus = []): array
    {
        return $plus + [
            'companyName' => 'Ferme', 'ifu' => '3202601234567', 'vpsRate' => 4, 'cnssEmployeeRate' => 3.6, 'cnssEmployerPensionRate' => 6.4,
            'cnssEmployerFamilyRate' => 9, 'cnssEmployerRiskRate' => 2,
        ];
    }

    public function test_la_demande_du_poste_regle_le_mode_et_ne_touche_jamais_au_jeton(): void
    {
        CompanySetting::current()->update(['mecef_jeton_encrypted' => self::JETON]);

        [$id, $r] = $this->demande($this->entreprise(['mecefMode' => 'boitier', 'mecefApiUrl' => 'https://emcf.test/api', 'mecefOperateurNom' => 'Awa']));

        $r->assertOk()->assertJsonPath('settings_requests.accepted.0', $id);
        $c = CompanySetting::current();
        $this->assertSame('boitier', $c->mecef_mode);
        $this->assertSame('Awa', $c->mecef_operateur_nom);
        $this->assertSame(self::JETON, $c->mecef_jeton_encrypted, 'le jeton du serveur reste intact');
    }

    public function test_une_demande_d_un_poste_ancien_sans_cles_mecef_laisse_le_reglage_tel_quel(): void
    {
        CompanySetting::current()->update(['mecef_mode' => 'emecef', 'mecef_operateur_nom' => 'Awa', 'mecef_jeton_encrypted' => self::JETON]);

        [, $r] = $this->demande($this->entreprise(['companyName' => 'Ferme renommée']));

        $r->assertOk();
        $c = CompanySetting::current();
        $this->assertSame('Ferme renommée', $c->company_name);
        $this->assertSame('emecef', $c->mecef_mode);
        $this->assertSame('Awa', $c->mecef_operateur_nom);
        $this->assertSame(self::JETON, $c->mecef_jeton_encrypted);
    }

    public function test_la_demande_du_poste_est_refusee_avec_le_meme_motif_que_le_web(): void
    {
        [, $r] = $this->demande($this->entreprise(['ifu' => '123', 'mecefMode' => 'emecef']));
        $this->assertStringContainsString("L'IFU doit comporter 13 chiffres pour la facturation e-MECeF.", $r->json('settings_requests.rejected.0.reason'));

        [, $r] = $this->demande($this->entreprise(['mecefMode' => 'nimporte']));
        $this->assertStringContainsString('Le mode de facturation normalisée doit être', $r->json('settings_requests.rejected.0.reason'));
    }
}
