<?php

namespace Tests\Feature;

use App\Livewire\Parametres\DonneesEntreprise;
use App\Livewire\Parametres\EmailSmtp;
use App\Livewire\Parametres\FacturationEmecef;
use App\Livewire\Parametres\GestionUtilisateurs;
use App\Livewire\Parametres\ModulesActifs;
use App\Livewire\Parametres\PostesAppairage;
use App\Livewire\Parametres\ReinitialisationDonnees;
use App\Livewire\Parametres\Sauvegardes;
use App\Models\CompanySetting;
use App\Models\Role;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket CONF-1 — LES ONGLETS DU HUB PARAMÈTRES REFUSENT L'OUVERTURE SANS LEUR DROIT.
 *
 * Le hub n'exige que `view-parametres`. Avant, `FacturationEmecef::mount` et `DonneesEntreprise::mount` n'avaient pas le
 * `abort_unless` d'`EmailSmtp::mount` : qui n'avait que `view-parametres` voyait mode, IFU, adresse, opérateur et « jeton configuré ».
 * Chaque composant monté dans le hub a maintenant la garde de ses actions.
 */
class ParametresDroitsOuvertureTest extends TestCase
{
    use RefreshDatabase;

    private const JETON = 'jeton-secret-dgi-9f8e7d6c';

    private const MOT_DE_PASSE_SMTP = 'mdp-smtp-secret-7a6b5c4d';

    private User $lecteur;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolesAndPermissionsSeeder::class);

        CompanySetting::current()->update([
            'company_name' => 'Ferme', 'ifu' => '3202601234567', 'mecef_mode' => 'emecef',
            'mecef_jeton_encrypted' => self::JETON, 'smtp_host' => 'smtp.exemple.bj', 'smtp_password_encrypted' => self::MOT_DE_PASSE_SMTP,
        ]);

        // Un compte qui peut OUVRIR le hub (`view-parametres`) sans rien gérer.
        Role::findOrCreate('observateur', 'web')->givePermissionTo('view-parametres');
        $this->lecteur = User::create(['name' => 'Obs', 'username' => 'obs', 'email' => 'obs@x.bj', 'password' => bcrypt('x'), 'is_active' => true]);
        $this->lecteur->assignRole('observateur');
    }

    /** @return array<string, array{0: class-string, 1: string}> */
    public static function onglets(): array
    {
        return [
            'entreprise' => [DonneesEntreprise::class, 'entreprise'],
            'facturation' => [FacturationEmecef::class, 'facturation'],
            'email' => [EmailSmtp::class, 'email'],
            'modules' => [ModulesActifs::class, 'modules'],
            'utilisateurs' => [GestionUtilisateurs::class, 'utilisateurs'],
            'postes' => [PostesAppairage::class, 'postes'],
            'reinitialisation' => [ReinitialisationDonnees::class, 'reinitialisation'],
            'sauvegardes' => [Sauvegardes::class, 'sauvegardes'],
        ];
    }

    /** @dataProvider onglets */
    public function test_un_compte_sans_le_droit_recoit_403_a_l_ouverture_et_aucune_donnee(string $composant, string $onglet): void
    {
        $this->actingAs($this->lecteur);

        Livewire::test($composant)->assertForbidden();

        $reponse = $this->get('/parametres-hub?tab='.$onglet)->assertForbidden();
        $corps = $reponse->getContent();

        foreach ([self::JETON, self::MOT_DE_PASSE_SMTP, '3202601234567', 'smtp.exemple.bj'] as $secret) {
            $this->assertStringNotContainsString($secret, $corps, "« {$secret} » ne doit pas figurer dans la réponse de l'onglet {$onglet}");
        }
    }

    /** @dataProvider onglets */
    public function test_l_administrateur_ouvre_chaque_onglet(string $composant, string $onglet): void
    {
        $admin = User::create(['name' => 'Admin', 'username' => 'adm', 'email' => 'adm@x.bj', 'password' => bcrypt('x'), 'is_active' => true]);
        $admin->assignRole('admin');

        $this->actingAs($admin)->get('/parametres-hub?tab='.$onglet)->assertOk();
    }

    public function test_le_jeton_et_le_mot_de_passe_ne_sont_jamais_dans_le_corps_meme_pour_l_administrateur(): void
    {
        $admin = User::create(['name' => 'Admin', 'username' => 'adm', 'email' => 'adm@x.bj', 'password' => bcrypt('x'), 'is_active' => true]);
        $admin->assignRole('admin');

        foreach (['facturation', 'email'] as $onglet) {
            $corps = $this->actingAs($admin)->get('/parametres-hub?tab='.$onglet)->assertOk()->getContent();
            $this->assertStringNotContainsString(self::JETON, $corps);
            $this->assertStringNotContainsString(self::MOT_DE_PASSE_SMTP, $corps);
        }
    }

    public function test_chaque_composant_du_hub_a_une_garde_a_l_ouverture(): void
    {
        // Garde de structure : tout composant monté dans le hub (hors lecture seule déclarée) porte `abort_unless(Gate::allows(…), 403)` dans `mount`.
        $hub = (string) file_get_contents(resource_path('views/livewire/parametres/parametres-hub.blade.php'));
        preg_match_all('/<livewire:parametres\.([a-z-]+)/', $hub, $m);

        // Lecture seule ou garde propre (admin, `authorize` au rendu) : RolesPermissions, ModesPaiement, AuditLogs, Corbeille, BaremeIts.
        $exceptions = ['roles-permissions', 'modes-paiement', 'audit-logs', 'corbeille'];

        foreach (array_unique($m[1]) as $nom) {
            if (in_array($nom, $exceptions, true)) {
                continue;
            }

            $classe = \Illuminate\Support\Str::studly($nom);
            $source = (string) file_get_contents(app_path('Livewire/Parametres/'.$classe.'.php'));
            $this->assertMatchesRegularExpression('/function mount\(\)[^{]*\{[^}]*abort_unless\(\s*(\\\\Illuminate\\\\Support\\\\Facades\\\\)?Gate::allows\(/s', $source, "{$classe}::mount doit refuser l'ouverture sans droit");
        }
    }
}
