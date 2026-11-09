<?php

namespace Tests\Feature;

use App\Livewire\Parametres\FacturationEmecef;
use App\Models\AuditLog;
use App\Models\CompanySetting;
use App\Models\User;
use App\Services\Mecef\EmecefGateway;
use App\Services\Mecef\MecefConfigurationTesteur;
use App\Services\Mecef\MecefReglage;
use App\Support\MecefMode;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket CONF-1 — VALEURS DE REPLI e-MECeF LUES DE `.env` (`SGMEF_*`, variables du paquet de référence).
 *
 * Priorité : réglage saisi à l'écran (base) > `.env` > valeur par défaut du logiciel. Le jeton de `.env` n'est jamais affiché,
 * jamais servi au poste, jamais journalisé. Délais et vérification SSL s'appliquent à la passerelle et au testeur.
 */
class MecefEnvRepliTest extends TestCase
{
    use RefreshDatabase;

    private const JETON_ENV = 'jeton-de-env-ABCDEF123456';

    private const JETON_BASE = 'jeton-de-base-ZYXWVU987654';

    private const URL_ENV = 'https://sgmef.env.test/api';

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->admin = User::create(['name' => 'Admin', 'username' => 'adm', 'email' => 'adm@x.bj', 'password' => bcrypt('x'), 'is_active' => true]);
        $this->admin->assignRole('admin');
        CompanySetting::current()->update(['company_name' => 'Ferme', 'mecef_mode' => 'emecef']);
    }

    private function env(array $valeurs = []): void
    {
        config(['mecef.sgmef' => array_merge([
            'api_url' => self::URL_ENV, 'token' => self::JETON_ENV, 'default_ifu' => '3201700000001',
            'default_operator_name' => 'Opérateur env', 'default_operator_id' => '7',
            'http_timeout' => 30, 'connect_timeout' => 10, 'verify_ssl' => true,
        ], $valeurs)]);
    }

    public function test_les_valeurs_par_defaut_sont_celles_du_paquet(): void
    {
        $defauts = require base_path('config/mecef.php');

        $this->assertSame(30, $defauts['sgmef']['http_timeout']);
        $this->assertSame(10, $defauts['sgmef']['connect_timeout']);
        $this->assertTrue($defauts['sgmef']['verify_ssl']);
    }

    public function test_sans_rien_en_base_les_variables_d_environnement_servent_de_repli(): void
    {
        $this->env();

        $e = app(MecefReglage::class)->emecef();

        $this->assertSame('3201700000001', $e['ifu']);
        $this->assertSame(self::URL_ENV, $e['url']);
        $this->assertSame(self::JETON_ENV, $e['jeton']);
        $this->assertSame('7', $e['operateur_id']);
        $this->assertSame('Opérateur env', $e['operateur_nom']);
        $this->assertTrue(app(MecefReglage::class)->jetonConfigure());
        $this->assertTrue(app(MecefReglage::class)->jetonDepuisConfiguration());
    }

    public function test_sans_variables_ni_base_les_valeurs_du_logiciel_restent_celles_d_avant(): void
    {
        $this->env(['api_url' => null, 'token' => null, 'default_ifu' => null, 'default_operator_name' => null, 'default_operator_id' => null]);

        $e = app(MecefReglage::class)->emecef();

        $this->assertSame(MecefMode::URL_PAR_DEFAUT, $e['url']);
        $this->assertSame('', $e['jeton']);
        $this->assertSame('1', $e['operateur_id']);
        $this->assertSame('Caissier', $e['operateur_nom']);
        $this->assertFalse(app(MecefReglage::class)->jetonConfigure());
    }

    public function test_le_reglage_saisi_a_l_ecran_prime_sur_l_environnement(): void
    {
        $this->env();
        CompanySetting::current()->update([
            'ifu' => '3202601234567', 'mecef_api_url' => 'https://saisie.test/api', 'mecef_jeton_encrypted' => self::JETON_BASE,
            'mecef_operateur_id' => '2', 'mecef_operateur_nom' => 'Awa',
        ]);

        $e = app(MecefReglage::class)->emecef();

        $this->assertSame('3202601234567', $e['ifu']);
        $this->assertSame('https://saisie.test/api', $e['url']);
        $this->assertSame(self::JETON_BASE, $e['jeton']);
        $this->assertSame('2', $e['operateur_id']);
        $this->assertSame('Awa', $e['operateur_nom']);
        $this->assertFalse(app(MecefReglage::class)->jetonDepuisConfiguration());
    }

    public function test_la_passerelle_applique_les_delais_et_la_verification_ssl_de_l_environnement(): void
    {
        $this->env(['http_timeout' => 45, 'connect_timeout' => 7, 'verify_ssl' => false]);

        $requete = new \ReflectionMethod(EmecefGateway::class, 'requete');
        $pending = $requete->invoke(app(EmecefGateway::class), app(MecefReglage::class)->emecef());
        $options = (new \ReflectionProperty($pending, 'options'))->getValue($pending);

        $this->assertSame(45, $options['timeout']);
        $this->assertSame(7, $options['connect_timeout']);
        $this->assertFalse($options['verify']);
    }

    public function test_les_defauts_de_la_passerelle_sont_30_10_et_ssl_verifie(): void
    {
        $this->env();

        $requete = new \ReflectionMethod(EmecefGateway::class, 'requete');
        $pending = $requete->invoke(app(EmecefGateway::class), app(MecefReglage::class)->emecef());
        $options = (new \ReflectionProperty($pending, 'options'))->getValue($pending);

        $this->assertSame(30, $options['timeout']);
        $this->assertSame(10, $options['connect_timeout']);
        $this->assertTrue($options['verify']);
    }

    public function test_le_testeur_emploie_l_adresse_le_jeton_et_l_ifu_de_l_environnement_sans_les_afficher(): void
    {
        $this->env();
        Http::fake([self::URL_ENV.'/info/status' => Http::response(['status' => true, 'tokenValid' => true, 'ifu' => '3201700000001'])]);

        // Le formulaire envoie des champs VIDES : l'enregistré, donc le repli, s'applique.
        $r = app(MecefConfigurationTesteur::class)->tester(['mode' => 'emecef', 'ifu' => '', 'url' => '', 'jeton' => '']);

        $this->assertTrue($r['ok'], $r['resume']);
        Http::assertSent(fn (Request $q) => $q->url() === self::URL_ENV.'/info/status' && $q->hasHeader('Authorization', 'Bearer '.self::JETON_ENV));
        $this->assertStringNotContainsString(self::JETON_ENV, json_encode($r));
    }

    public function test_le_testeur_lit_les_delais_et_le_ssl_de_l_environnement(): void
    {
        $source = (string) file_get_contents(app_path('Services/Mecef/MecefConfigurationTesteur.php'));

        $this->assertStringContainsString("reseau()", $source);
        $this->assertStringContainsString("'verify' => \$reseau['verifier_ssl']", $source);
    }

    public function test_l_ecran_dit_que_le_jeton_est_defini_dans_la_configuration_sans_le_montrer(): void
    {
        $this->env();

        $html = Livewire::actingAs($this->admin)->test(FacturationEmecef::class)
            ->assertSee('Jeton défini dans la configuration du serveur')
            ->assertSet('mecefApiUrl', self::URL_ENV)
            ->assertSet('ifu', '3201700000001')
            ->html();

        $this->assertStringNotContainsString(self::JETON_ENV, $html);
        $this->assertStringNotContainsString(base64_encode(self::JETON_ENV), $html);
    }

    public function test_un_jeton_saisi_remplace_le_message_de_configuration(): void
    {
        $this->env();
        CompanySetting::current()->update(['mecef_jeton_encrypted' => self::JETON_BASE]);

        Livewire::actingAs($this->admin)->test(FacturationEmecef::class)->assertDontSee('Jeton défini dans la configuration du serveur');
    }

    public function test_enregistrer_l_ecran_n_ecrit_jamais_le_jeton_de_l_environnement_en_base_ni_dans_le_journal(): void
    {
        $this->env();

        Livewire::actingAs($this->admin)->test(FacturationEmecef::class)
            ->set('mecefMode', 'emecef')->call('save')->assertHasNoErrors();

        $this->assertSame('', (string) CompanySetting::current()->mecef_jeton_encrypted);
        $this->assertStringNotContainsString(self::JETON_ENV, json_encode(AuditLog::all()->toArray()));
    }

    public function test_le_poste_ne_voit_qu_un_temoin_configure(): void
    {
        $this->env();

        $reponse = $this->actingAs($this->admin, 'sanctum')->getJson('/api/sync/pull')->assertOk();

        $reponse->assertJsonPath('company_settings.mecef_jeton_configure', true);
        $this->assertStringNotContainsString(self::JETON_ENV, $reponse->getContent());
        $this->assertStringNotContainsString(base64_encode(self::JETON_ENV), $reponse->getContent());
        $this->assertArrayNotHasKey('mecef_jeton', $reponse->json('company_settings'));

        $this->env(['token' => null]);
        $this->actingAs($this->admin, 'sanctum')->getJson('/api/sync/pull')->assertJsonPath('company_settings.mecef_jeton_configure', false);
    }

    public function test_les_exemples_d_environnement_documentent_les_variables_sans_secret(): void
    {
        foreach (['.env.example', '.env.production.example'] as $fichier) {
            $texte = (string) file_get_contents(base_path($fichier));

            foreach (['SGMEF_API_URL', 'SGMEF_TOKEN', 'SGMEF_DEFAULT_IFU', 'SGMEF_DEFAULT_OPERATOR_NAME', 'SGMEF_DEFAULT_OPERATOR_ID', 'SGMEF_HTTP_TIMEOUT', 'SGMEF_CONNECT_TIMEOUT', 'SGMEF_VERIFY_SSL'] as $variable) {
                $this->assertMatchesRegularExpression('/^#\s*'.$variable.'=/m', $texte, "{$fichier} : {$variable} doit être documentée (commentée)");
            }

            // Aucune valeur active, aucun secret : tout le bloc est commenté.
            $this->assertDoesNotMatchRegularExpression('/^SGMEF_/m', $texte, "{$fichier} : aucune variable SGMEF_ active");
            $this->assertMatchesRegularExpression('/^#\s*SGMEF_TOKEN=\s*$/m', $texte, "{$fichier} : le jeton reste vide");
        }
    }

    public function test_les_reglages_hors_perimetre_du_paquet_ne_sont_pas_lus(): void
    {
        $config = (string) file_get_contents(base_path('config/mecef.php'));

        foreach (['SGMEF_WEB_INTERFACE_ENABLED', 'SGMEF_QUEUE', 'SGMEF_ROUTE_PREFIX', 'SGMEF_POLLING_SECONDS'] as $variable) {
            $this->assertStringNotContainsString("env('{$variable}", $config);
        }
    }
}
