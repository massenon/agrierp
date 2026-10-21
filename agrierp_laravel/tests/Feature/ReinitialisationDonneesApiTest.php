<?php

namespace Tests\Feature;

use App\Http\Controllers\Api\ReinitialisationDonneesController;
use App\Livewire\Parametres\ReinitialisationDonnees;
use App\Models\AuditLog;
use App\Models\CompanySetting;
use App\Models\Sale;
use App\Models\Supplier;
use App\Models\User;
use App\Services\ReinitialisationDonneesService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket R-1 — « RÉINITIALISATION DES DONNÉES » DEPUIS LE POSTE : la MÊME action que l'onglet web.
 *
 * Même droit (`manage-parametres`), mêmes verrous dans le même ordre (mode démonstration, puis le mot recopié),
 * même service, même marque, même journal, mêmes messages. Le jeton du poste qui lance l'opération est conservé
 * (comme la session de l'administrateur au web) ; tous les autres sont révoqués.
 */
class ReinitialisationDonneesApiTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    private string $jetonAdmin;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $this->admin = $this->compte('admin', 'dg');
        $this->jetonAdmin = $this->admin->createToken('poste-bureau')->plainTextToken;

        CompanySetting::create(['company_name' => 'Ferme École OLOUWACHEGOUN']);
    }

    private function compte(string $role, string $identifiant): User
    {
        $u = User::create([
            'name' => ucfirst($identifiant), 'username' => $identifiant, 'email' => $identifiant.'@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    private function activite(): void
    {
        Supplier::create(['name' => 'Provenderie', 'phone' => '+22997000000', 'is_active' => true]);
        Sale::create([
            'payment_mode' => 'especes', 'subtotal' => 21_000, 'discount' => 0,
            'total' => 21_000, 'status' => 'validee',
        ]);
    }

    private function modeDemo(bool $actif = true): void
    {
        CompanySetting::first()->update(['demo_mode_enabled' => $actif]);
    }

    private function enTantQue(string $jeton): static
    {
        $this->app['auth']->forgetGuards();

        return $this->withToken($jeton);
    }

    public function test_l_administrateur_reinitialise_depuis_le_poste_comme_au_web(): void
    {
        $this->modeDemo();
        $this->activite();
        $jetonCaisse = $this->compte('caissier', 'caisse')->createToken('poste-caisse')->plainTextToken;
        $this->travelTo(now()->setTime(10, 30, 0));

        $reponse = $this->enTantQue($this->jetonAdmin)
            ->postJson('/api/parametres/reinitialisation', ['confirmation' => 'REINITIALISER'])
            ->assertOk()
            // Message du web, au nombre réel (vente + fournisseur + jeton de la caisse n'est pas une donnée).
            ->assertJsonPath('message', 'Réinitialisation effectuée — 2 enregistrement(s) supprimé(s).')
            ->assertJsonPath('total', 2);

        $this->assertSame(0, Sale::count());
        $this->assertSame(0, Supplier::count());

        // Même marque que celle que le tirage sert : le poste ne purgera pas une seconde fois.
        $marque = CompanySetting::first()->data_reset_at;
        $this->assertNotNull($marque);
        $reponse->assertJsonPath('data_reset_at', $marque->toIso8601String());

        // Même journal que le web, au nom de l'administrateur du jeton.
        $trace = AuditLog::where('action', 'donnees.reinitialisees')->sole();
        $this->assertSame($this->admin->id, $trace->user_id);

        // Le jeton du poste qui a lancé l'opération reste valide (il tire aussitôt) ; celui de la caisse est révoqué.
        $this->assertSame(['poste-bureau'], DB::table('personal_access_tokens')->pluck('name')->all());
        $this->enTantQue($this->jetonAdmin)->getJson('/api/sync/pull')
            ->assertOk()->assertJsonPath('data_reset_at', $marque->toIso8601String());
        $this->enTantQue($jetonCaisse)->getJson('/api/sync/pull')->assertUnauthorized();

        // L'envoi qui suit, portant la marque reçue, est accepté (15.50).
        $this->enTantQue($this->jetonAdmin)->postJson('/api/sync/push', [
            'device_id' => 'poste-bureau', 'data_reset_at' => $reponse->json('data_reset_at'),
        ])->assertOk();
    }

    /** ⚠️ Même droit que l'onglet web : `manage-parametres`, que seul l'administrateur porte. */
    public function test_un_autre_role_est_refuse_en_francais_et_rien_n_est_efface(): void
    {
        $this->modeDemo();
        $this->activite();

        foreach (['caissier' => 'caisse', 'comptable' => 'compta', 'animalier' => 'elevage'] as $role => $id) {
            $jeton = $this->compte($role, $id)->createToken('poste-'.$id)->plainTextToken;

            $this->enTantQue($jeton)->getJson('/api/parametres/reinitialisation')
                ->assertForbidden()->assertJsonPath('message', ReinitialisationDonneesController::REFUS_ROLE);
            $this->enTantQue($jeton)->postJson('/api/parametres/reinitialisation/mode-demo')
                ->assertForbidden()->assertJsonPath('message', ReinitialisationDonneesController::REFUS_ROLE);
            $this->enTantQue($jeton)
                ->postJson('/api/parametres/reinitialisation', ['confirmation' => 'REINITIALISER'])
                ->assertForbidden()->assertJsonPath('message', 'Votre rôle ne permet pas de réinitialiser les données.');
        }

        $this->assertSame(1, Sale::count());
        $this->assertTrue((bool) CompanySetting::first()->demo_mode_enabled, 'la bascule est intacte');
        $this->assertNull(CompanySetting::first()->data_reset_at);
        $this->assertSame(0, AuditLog::whereIn('action', ['donnees.reinitialisees', 'demo_mode.disabled'])->count());
    }

    /** ⚠️ VERROU 2 du web : le mot recopié. Manquant ou faux : 422, message du web, rien d'effacé. */
    public function test_la_confirmation_manquante_ou_fausse_est_refusee(): void
    {
        $this->modeDemo();
        $this->activite();

        foreach ([[], ['confirmation' => ''], ['confirmation' => 'oui'], ['confirmation' => 'reinitialiser']] as $corps) {
            $this->enTantQue($this->jetonAdmin)->postJson('/api/parametres/reinitialisation', $corps)
                ->assertStatus(422)
                ->assertJsonPath('message', 'Saisissez REINITIALISER pour confirmer.')
                ->assertJsonPath('errors.confirmation.0', 'Saisissez REINITIALISER pour confirmer.');
        }

        $this->assertSame(1, Sale::count());
        $this->assertNull(CompanySetting::first()->data_reset_at);
    }

    /** ⚠️ VERROU 1 du web : sans le mode démonstration, refus (message du toast web), même avec le bon mot. */
    public function test_sans_le_mode_demonstration_la_reinitialisation_est_refusee(): void
    {
        $this->activite();

        $this->enTantQue($this->jetonAdmin)
            ->postJson('/api/parametres/reinitialisation', ['confirmation' => 'REINITIALISER'])
            ->assertStatus(409)
            ->assertJsonPath('message', 'Réinitialisation refusée : le mode démonstration n\'est pas activé.');

        $this->assertSame(1, Sale::count());
    }

    /** La bascule du poste est celle du web : même état, même journal, mêmes messages. */
    public function test_la_bascule_du_mode_demonstration_est_celle_du_web(): void
    {
        $this->enTantQue($this->jetonAdmin)->getJson('/api/parametres/reinitialisation')
            ->assertOk()->assertJson(['mode_demo_actif' => false, 'mot_de_confirmation' => 'REINITIALISER']);

        $this->enTantQue($this->jetonAdmin)->postJson('/api/parametres/reinitialisation/mode-demo')
            ->assertOk()
            ->assertJson([
                'mode_demo_actif' => true, 'type' => 'warning',
                'message' => 'Mode démonstration activé — l\'onglet de réinitialisation est accessible.',
            ]);
        $this->assertTrue((bool) CompanySetting::first()->demo_mode_enabled);
        $this->assertSame($this->admin->id, AuditLog::where('action', 'demo_mode.enabled')->sole()->user_id);

        $this->enTantQue($this->jetonAdmin)->postJson('/api/parametres/reinitialisation/mode-demo')
            ->assertOk()->assertJson(['mode_demo_actif' => false, 'message' => 'Mode démonstration désactivé.']);
        $this->assertSame(1, AuditLog::where('action', 'demo_mode.disabled')->count());
    }

    /** Une base sans activité : le message du web pour « rien à supprimer ». */
    public function test_rien_a_supprimer_reprend_le_message_du_web(): void
    {
        $this->modeDemo();

        $this->enTantQue($this->jetonAdmin)
            ->postJson('/api/parametres/reinitialisation', ['confirmation' => 'REINITIALISER'])
            ->assertOk()->assertJsonPath('message', 'Aucune donnée d\'activité à supprimer.');
    }

    /** L'écran web garde ses messages : ils viennent désormais du même service que la route du poste. */
    public function test_l_ecran_web_et_la_route_disent_la_meme_chose(): void
    {
        $this->actingAs($this->admin);
        $this->modeDemo();
        $this->activite();

        Livewire::test(ReinitialisationDonnees::class)
            ->set('confirmation', 'non')->call('reinitialiser')
            ->assertHasErrors(['confirmation'])
            ->assertSee(ReinitialisationDonneesService::messageConfirmation())
            ->set('confirmation', 'REINITIALISER')->call('reinitialiser')
            ->assertDispatched('toast', message: ReinitialisationDonneesService::messageResultat(2), type: 'success');
    }
}
