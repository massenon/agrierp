<?php

namespace Tests\Feature;

use App\Livewire\Parametres\FacturationEmecef;
use App\Models\AuditLog;
use App\Models\CompanySetting;
use App\Models\User;
use App\Services\Mecef\MecefConfigurationTesteur;
use App\Support\MecefMode;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Le formulaire « Facturation normalisée (e-MECeF) » et son bouton « Tester la configuration » : contrôles locaux (IFU, jeton,
 * adresse, mode) puis UN appel de LECTURE sans effet (`GET /info/status`), jamais la création d'une facture ; résultat en
 * français ; le jeton n'est jamais affiché ni journalisé. Aucun appel réel : `Http::fake`.
 */
class MecefTestConfigurationTest extends TestCase
{
    use RefreshDatabase;

    private const URL = 'https://emcf.test/api';

    private const JETON = 'SECRET-JETON-NE-JAMAIS-MONTRER';

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->admin = User::create(['name' => 'Admin', 'username' => 'adm', 'email' => 'adm@x.bj', 'password' => bcrypt('x'), 'is_active' => true]);
        $this->admin->assignRole('admin');
        CompanySetting::current()->update(['company_name' => 'Ferme', 'ifu' => '3202601234567', 'mecef_mode' => 'emecef', 'mecef_api_url' => self::URL, 'mecef_jeton_encrypted' => self::JETON]);
    }

    private function ecran()
    {
        return Livewire::actingAs($this->admin)->test(FacturationEmecef::class);
    }

    /** Une seule réponse simulée à la fois (les `Http::fake` successifs d'un même test s'empilent : le premier gagnerait toujours). */
    private function faux(mixed $reponse): void
    {
        Http::swap(new \Illuminate\Http\Client\Factory);
        Http::fake([self::URL.'/info/status' => $reponse]);
    }

    private function lectures(): int
    {
        return Http::recorded(fn (Request $r) => $r->method() === 'GET' && $r->url() === self::URL.'/info/status')->count();
    }

    public function test_configuration_valide_un_seul_appel_de_lecture_jamais_de_facture(): void
    {
        $this->faux(Http::response(['status' => true, 'ifu' => '3202601234567', 'tokenValid' => true, 'version' => '1.0'], 200));

        $ecran = $this->ecran()->call('tester');

        $this->assertTrue($ecran->get('resultatTest')['ok']);
        $this->assertSame('Configuration valide.', $ecran->get('resultatTest')['resume']);
        $ecran->assertSee('Configuration valide.');

        // UN appel, en lecture, avec le jeton en Bearer ; rien d'autre n'a été tenté.
        Http::assertSentCount(1);
        $this->assertSame(1, $this->lectures());
        Http::assertSent(fn (Request $r) => $r->method() === 'GET' && $r->hasHeader('Authorization', 'Bearer '.self::JETON));
        Http::assertNotSent(fn (Request $r) => str_contains($r->url(), '/invoice'));
    }

    public function test_jeton_refuse_401_et_403(): void
    {
        foreach ([401, 403] as $statut) {
            $this->faux(Http::response('', $statut));

            $r = $this->ecran()->call('tester')->get('resultatTest');

            $this->assertFalse($r['ok']);
            $this->assertStringStartsWith('Jeton refusé ('.$statut.')', $r['resume']);
        }
    }

    public function test_hote_injoignable(): void
    {
        Http::fake(fn () => throw new ConnectionException('cURL error 6: Could not resolve host: emcf.test'));

        $r = $this->ecran()->call('tester')->get('resultatTest');

        $this->assertFalse($r['ok']);
        $this->assertStringStartsWith('Hôte injoignable', $r['resume']);
        $this->assertStringNotContainsString('cURL', json_encode($r), 'le message technique de l\'exception n\'est jamais repris');
    }

    public function test_service_indisponible_adresse_introuvable_reponse_inattendue(): void
    {
        $this->faux(Http::response('', 503));
        $this->assertStringStartsWith('Service e-MECeF indisponible (503)', $this->ecran()->call('tester')->get('resultatTest')['resume']);

        $this->faux(Http::response('Not found', 404));
        $this->assertStringStartsWith('Adresse introuvable (404)', $this->ecran()->call('tester')->get('resultatTest')['resume']);

        $this->faux(Http::response('<html>page</html>', 200));
        $this->assertStringStartsWith('Réponse inattendue', $this->ecran()->call('tester')->get('resultatTest')['resume']);
    }

    public function test_jeton_signale_non_valide_ou_ifu_du_jeton_different(): void
    {
        $this->faux(Http::response(['status' => true, 'tokenValid' => false], 200));
        $this->assertStringStartsWith('Jeton refusé par la DGI', $this->ecran()->call('tester')->get('resultatTest')['resume']);

        $this->faux(Http::response(['status' => true, 'tokenValid' => true, 'ifu' => '9999999999999'], 200));
        $r = $this->ecran()->call('tester')->get('resultatTest');
        $this->assertFalse($r['ok']);
        $this->assertStringContainsString("L'IFU du jeton (9999999999999) n'est pas celui de l'entreprise (3202601234567)", $r['resume']);
    }

    public function test_les_verifications_locales_arretent_avant_tout_appel(): void
    {
        Http::fake();

        // IFU de 12 chiffres, adresse invalide, jeton absent, mode désactivé : quatre points, zéro appel.
        CompanySetting::current()->update(['mecef_jeton_encrypted' => null]);
        $r = $this->ecran()->set('ifu', '123456789012')->set('mecefApiUrl', 'pas une adresse')->set('mecefMode', 'desactive')->call('tester')->get('resultatTest');

        $this->assertFalse($r['ok']);
        $this->assertStringStartsWith('Configuration incomplète', $r['resume']);
        $details = implode(' | ', array_column($r['lignes'], 'detail'));
        foreach (['désactivée', "L'IFU doit comporter 13 chiffres.", 'Adresse invalide', 'Aucun jeton'] as $attendu) {
            $this->assertStringContainsString($attendu, $details);
        }
        Http::assertNothingSent();

        // Mode boîtier : dit que ce n'est pas encore disponible.
        $r = $this->ecran()->set('mecefMode', 'boitier')->call('tester')->get('resultatTest');
        $this->assertStringContainsString('Mode boîtier', implode(' | ', array_column($r['lignes'], 'detail')));
        Http::assertNothingSent();
    }

    public function test_un_jeton_expire_est_signale_sans_appel(): void
    {
        Http::fake();
        $expire = 'x.'.rtrim(strtr(base64_encode(json_encode(['exp' => now()->subDays(3)->timestamp])), '+/', '-_'), '=').'.y';
        CompanySetting::current()->update(['mecef_jeton_encrypted' => $expire]);

        $r = $this->ecran()->call('tester')->get('resultatTest');

        $this->assertFalse($r['ok']);
        $this->assertStringContainsString('Jeton expiré depuis le '.now()->subDays(3)->format('d/m/Y'), json_encode($r, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
        Http::assertNothingSent();
    }

    public function test_on_teste_la_saisie_sans_l_enregistrer_et_un_jeton_tape_est_utilise(): void
    {
        $this->faux(Http::response(['status' => true, 'tokenValid' => true], 200));

        $this->ecran()->call('$set', 'remplacerJeton', true)->set('mecefJeton', 'NOUVEAU-JETON-TAPE')->call('tester');

        Http::assertSent(fn (Request $r) => $r->hasHeader('Authorization', 'Bearer NOUVEAU-JETON-TAPE'));
        $this->assertSame(self::JETON, CompanySetting::current()->mecef_jeton_encrypted, 'tester n\'enregistre rien');
    }

    public function test_le_jeton_n_est_jamais_affiche_ni_journalise(): void
    {
        Log::spy();
        $this->faux(Http::response('', 401));

        $ecran = $this->ecran()->call('tester');

        $this->assertStringNotContainsString(self::JETON, $ecran->html());
        $this->assertStringNotContainsString(self::JETON, json_encode($ecran->snapshot));
        $this->assertStringNotContainsString(self::JETON, json_encode($ecran->get('resultatTest')));
        $this->assertStringNotContainsString(self::JETON, json_encode(AuditLog::all()->toArray()));
        Log::shouldNotHaveReceived('error');
        Log::shouldNotHaveReceived('warning');
        Log::shouldNotHaveReceived('info');
    }

    public function test_le_formulaire_est_clair_explications_prereglages_remplacer_effacer(): void
    {
        $ecran = $this->ecran();

        $ecran->assertSee('Facturation normalisée (e-MECeF)')
            ->assertSee('Où trouver le jeton ?')
            ->assertSee('portail e-MECeF de la DGI')
            ->assertSee('Tester la configuration')
            ->assertSee('Remplacer')->assertSee('Effacer')->assertSee('••••')
            ->assertSee('Production (DGI)')->assertSee("Environnement d'essai (DGI)");

        // Préréglages : les deux adresses viennent d'une source, rien d'inventé.
        $ecran->call('choisirUrl', 'production')->assertSet('mecefApiUrl', MecefMode::URL_PRODUCTION)
            ->call('choisirUrl', 'essai')->assertSet('mecefApiUrl', MecefMode::URL_ESSAI)
            ->call('choisirUrl', 'inconnu')->assertSet('mecefApiUrl', MecefMode::URL_ESSAI);

        // L'adresse par défaut est celle de l'ESSAI : un premier essai ne part jamais en production par inadvertance.
        $this->assertSame(MecefMode::URL_ESSAI, MecefMode::URL_PAR_DEFAUT);
    }

    public function test_effacer_le_jeton_le_retire_sans_rien_journaliser_de_sa_valeur(): void
    {
        $this->ecran()->call('effacerJeton')->assertDispatched('toast');

        $this->assertSame('', (string) CompanySetting::current()->mecef_jeton_encrypted);
        $this->assertSame(1, AuditLog::where('action', 'company_settings.mecef_updated')->count());
        $this->assertStringNotContainsString(self::JETON, json_encode(AuditLog::all()->toArray()));
    }

    public function test_reserve_aux_comptes_qui_gerent_les_parametres(): void
    {
        $lecteur = User::create(['name' => 'Lecteur', 'username' => 'lec', 'email' => 'lec@x.bj', 'password' => bcrypt('x'), 'is_active' => true]);
        $lecteur->assignRole('animalier');
        Http::fake();

        // CONF-1 : l'onglet lui-même refuse l'ouverture (avant, seules les actions étaient refusées).
        Livewire::actingAs($lecteur)->test(FacturationEmecef::class)->assertForbidden();
        Http::assertNothingSent();
    }

    public function test_l_onglet_est_dans_le_hub_des_parametres(): void
    {
        $this->actingAs($this->admin)->get(route('parametres.hub', ['tab' => 'facturation']))
            ->assertOk()->assertSee('Facturation normalisée (e-MECeF)')->assertSee('Tester la configuration');
    }

    public function test_le_testeur_ne_connait_aucun_chemin_d_ecriture(): void
    {
        $source = (string) file_get_contents(app_path('Services/Mecef/MecefConfigurationTesteur.php'));
        $code = preg_replace('#/\*.*?\*/#s', '', $source);

        $this->assertStringContainsString("->get('/info/status')", (string) $code);
        foreach (['->post(', '->put(', '->delete(', '->patch(', "'/invoice", 'Log::', 'report('] as $interdit) {
            $this->assertStringNotContainsString($interdit, (string) $code, $interdit);
        }
        $this->assertInstanceOf(MecefConfigurationTesteur::class, app(MecefConfigurationTesteur::class));
    }
}
