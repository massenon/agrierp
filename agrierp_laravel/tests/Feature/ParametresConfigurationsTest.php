<?php

namespace Tests\Feature;

use App\Livewire\Parametres\DonneesEntreprise;
use App\Livewire\Parametres\EmailSmtp;
use App\Livewire\Parametres\Integrations;
use App\Livewire\Parametres\PostesAppairage;
use App\Models\AuditLog;
use App\Models\CompanySetting;
use App\Models\DemandeSynchronisation;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Mail\Transport\ArrayTransport;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Mail;
use Laravel\Sanctum\PersonalAccessToken;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Tickets CFG-1 (décision client du 19/10/2026, D-CFG-1) — CONFIGURATIONS DANS PARAMÈTRES, AU WEB.
 *
 * Onglet « Email (SMTP) » : UNE seule saisie SMTP (elle existait en double, Données de l'Entreprise et Intégrations),
 * mot de passe CHIFFRÉ en base, jamais réaffiché, champ vide = inchangé, effacement explicite, e-mail de test réel.
 *
 * Onglet « Postes & Appairage » : les postes appairés (jetons Sanctum nommés d'après le poste) avec l'état H3, la
 * demande de synchronisation S-T6 et la révocation de l'appairage — après laquelle le jeton du poste ne vaut plus rien.
 */
class ParametresConfigurationsTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        CompanySetting::firstOrCreate([], ['company_name' => 'Ferme École OLOUWACHEGOUN']);
    }

    private function compte(string $role): User
    {
        $u = User::create([
            'name' => ucfirst($role), 'username' => $role, 'email' => $role.'@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    // ── Hub ─────────────────────────────────────────────────────────────────────

    public function test_le_hub_porte_les_deux_onglets_de_configuration(): void
    {
        $this->actingAs($this->compte('admin'));

        $this->get('/parametres-hub')->assertOk()
            ->assertSeeInOrder(['Données de l&#039;Entreprise', 'Email (SMTP)', 'Modules Actifs', 'Gestion Utilisateurs', 'Postes &amp; Appairage', 'Modes de Paiement'], false);

        $this->get('/parametres-hub?tab=email')->assertOk()->assertSee('Enregistrer la Configuration SMTP');
        $this->get('/parametres-hub?tab=postes')->assertOk()->assertSee("Aucun poste n'est appairé au serveur pour le moment.", false);
    }

    // ── Email (SMTP) ────────────────────────────────────────────────────────────

    public function test_le_mot_de_passe_est_chiffre_en_base_et_jamais_reaffiche(): void
    {
        $this->actingAs($this->compte('admin'));

        Livewire::test(EmailSmtp::class)
            ->set('smtpHost', 'smtp.ferme.bj')
            ->set('smtpPort', 465)
            ->set('smtpSecurity', 'ssl')
            ->set('smtpUser', 'notifications@fermeolouwachegoun.com')
            ->set('smtpPassword', 'secret-smtp-de-la-ferme')
            ->set('fromAddress', 'ne-pas-repondre@fermeolouwachegoun.com')
            ->call('save')
            ->assertHasNoErrors()
            ->assertSet('smtpPassword', '')
            ->assertDispatched('toast', type: 'success');

        $brut = DB::table('company_settings')->value('smtp_password_encrypted');
        $this->assertNotSame('secret-smtp-de-la-ferme', $brut, 'Le mot de passe est stocké en clair.');
        $this->assertStringNotContainsString('secret-smtp-de-la-ferme', (string) $brut);
        $this->assertSame('secret-smtp-de-la-ferme', decrypt($brut, false));

        $s = CompanySetting::current();
        $this->assertSame(['smtp.ferme.bj', 465, 'ssl', 'notifications@fermeolouwachegoun.com', 'ne-pas-repondre@fermeolouwachegoun.com'],
            [$s->smtp_host, (int) $s->smtp_port, $s->smtp_security, $s->smtp_user, $s->smtp_from_address]);
        $this->assertTrue(AuditLog::where('action', 'company_settings.smtp_updated')->exists());

        // Réouverture : le champ reste vide, l'écran dit seulement qu'un mot de passe existe.
        Livewire::test(EmailSmtp::class)
            ->assertSet('smtpPassword', '')
            ->assertSee('Mot de passe enregistré')
            ->assertSee('Effacer le mot de passe')
            ->assertDontSee('secret-smtp-de-la-ferme');
        $this->get('/parametres-hub?tab=email')->assertOk()->assertDontSee('secret-smtp-de-la-ferme');
    }

    /** ⚠️⚠️ Un enregistrement sans retaper le mot de passe ne doit pas l'effacer. */
    public function test_un_champ_vide_laisse_le_mot_de_passe_inchange(): void
    {
        $this->actingAs($this->compte('admin'));
        CompanySetting::current()->update(['smtp_host' => 'smtp.ferme.bj', 'smtp_password_encrypted' => 'ancien-secret']);

        Livewire::test(EmailSmtp::class)
            ->assertSet('smtpHost', 'smtp.ferme.bj')
            ->set('smtpPort', 2525)
            ->call('save')
            ->assertHasNoErrors();

        $s = CompanySetting::current();
        $this->assertSame('ancien-secret', $s->smtp_password_encrypted);
        $this->assertSame(2525, (int) $s->smtp_port);
    }

    public function test_le_mot_de_passe_s_efface_explicitement(): void
    {
        $this->actingAs($this->compte('admin'));
        CompanySetting::current()->update(['smtp_host' => 'smtp.ferme.bj', 'smtp_password_encrypted' => 'ancien-secret']);

        Livewire::test(EmailSmtp::class)
            ->call('effacerMotDePasse')
            ->assertDispatched('toast', type: 'success')
            ->assertSee('Aucun mot de passe enregistré')
            ->assertDontSee('Effacer le mot de passe');

        $this->assertNull(DB::table('company_settings')->value('smtp_password_encrypted'));
        $this->assertTrue(AuditLog::where('action', 'company_settings.smtp_password_cleared')->exists());
        $this->assertSame('Mot de passe SMTP effacé', AuditLog::where('action', 'company_settings.smtp_password_cleared')->first()->action_label);
    }

    public function test_les_valeurs_majuscules_de_l_ancien_bloc_sont_reprises(): void
    {
        $this->actingAs($this->compte('admin'));
        CompanySetting::current()->update(['smtp_host' => 'smtp.ferme.bj', 'smtp_security' => 'SSL']);

        Livewire::test(EmailSmtp::class)->assertSet('smtpSecurity', 'ssl');
    }

    public function test_l_onglet_smtp_est_reserve_a_qui_gere_les_parametres(): void
    {
        foreach (['comptable', 'caissier', 'animalier'] as $role) {
            $this->actingAs($this->compte($role));
            Livewire::test(EmailSmtp::class)->assertForbidden();
            $this->get('/parametres-hub?tab=email')->assertForbidden();
        }
    }

    public function test_l_e_mail_de_test_part_reellement_avec_la_configuration_enregistree(): void
    {
        $this->actingAs($this->compte('admin'));
        CompanySetting::current()->update([
            'email' => 'contact@fermeolouwachegoun.com',
            'smtp_host' => 'smtp.ferme.bj', 'smtp_port' => 587, 'smtp_security' => 'tls',
            'smtp_user' => 'notifications@fermeolouwachegoun.com', 'smtp_password_encrypted' => 'secret',
            'smtp_from_address' => 'ne-pas-repondre@fermeolouwachegoun.com',
        ]);

        // Le transport SMTP est remplacé par un transport mémoire : le message part par la vraie chaîne d'envoi.
        $transport = new ArrayTransport;
        Mail::extend('smtp', fn () => $transport);

        Livewire::test(EmailSmtp::class)
            ->assertSet('testEmailTo', 'ne-pas-repondre@fermeolouwachegoun.com')
            ->set('testEmailTo', 'dg@fermeolouwachegoun.com')
            ->call('sendTestEmail')
            ->assertDispatched('toast', type: 'success', message: 'E-mail de test envoyé à dg@fermeolouwachegoun.com.');

        $this->assertCount(1, $transport->messages());
        $envoye = $transport->messages()->first()->getOriginalMessage();
        $this->assertSame('dg@fermeolouwachegoun.com', $envoye->getTo()[0]->getAddress());
        $this->assertSame('ne-pas-repondre@fermeolouwachegoun.com', $envoye->getFrom()[0]->getAddress());
        $this->assertSame('smtp', config('mail.default'));
        $this->assertSame('smtp.ferme.bj', config('mail.mailers.smtp.host'));
        $this->assertSame('secret', config('mail.mailers.smtp.password'));
        $this->assertTrue(AuditLog::where('action', 'company_settings.smtp_tested')->exists());
    }

    public function test_un_echec_d_envoi_est_annonce_et_rien_n_est_simule(): void
    {
        $this->actingAs($this->compte('admin'));
        // Port 1 de la machine locale : connexion refusée immédiatement.
        CompanySetting::current()->update(['smtp_host' => '127.0.0.1', 'smtp_port' => 1, 'smtp_security' => null]);

        Livewire::test(EmailSmtp::class)
            ->set('testEmailTo', 'dg@fermeolouwachegoun.com')
            ->call('sendTestEmail')
            ->assertDispatched('toast', type: 'error');

        $this->assertFalse(AuditLog::where('action', 'company_settings.smtp_tested')->exists());
    }

    public function test_sans_hote_enregistre_le_test_est_refuse(): void
    {
        $this->actingAs($this->compte('admin'));

        Livewire::test(EmailSmtp::class)
            ->set('testEmailTo', 'dg@fermeolouwachegoun.com')
            ->call('sendTestEmail')
            ->assertDispatched('toast', type: 'error', message: "Enregistrez d'abord l'hôte SMTP avant d'envoyer un e-mail de test.");
    }

    public function test_l_expediteur_retombe_sur_l_e_mail_de_contact(): void
    {
        $s = CompanySetting::current();
        $s->update(['email' => 'contact@fermeolouwachegoun.com', 'smtp_host' => 'smtp.ferme.bj']);
        $s->applyMailConfig();
        $this->assertSame('contact@fermeolouwachegoun.com', config('mail.from.address'));

        $s->update(['smtp_from_address' => 'ne-pas-repondre@fermeolouwachegoun.com']);
        $s->fresh()->applyMailConfig();
        $this->assertSame('ne-pas-repondre@fermeolouwachegoun.com', config('mail.from.address'));
    }

    /** ⚠️⚠️ UNE SEULE SAISIE : Données de l'Entreprise et Intégrations ne portent plus de champ SMTP. */
    public function test_la_saisie_smtp_n_existe_plus_qu_a_un_endroit(): void
    {
        $this->actingAs($this->compte('admin'));
        CompanySetting::current()->update([
            'smtp_host' => 'smtp.ferme.bj', 'smtp_port' => 465, 'smtp_security' => 'ssl',
            'smtp_user' => 'notifications@fermeolouwachegoun.com', 'smtp_password_encrypted' => 'secret', 'ifu' => '3202601234567',
        ]);

        $donnees = Livewire::test(DonneesEntreprise::class)
            ->assertDontSee('wire:model="smtpPassword"', false)
            ->assertDontSee('wire:model="smtpHost"', false)
            ->assertSee(route('parametres.hub', ['tab' => 'email']), false);
        $this->assertFalse(property_exists(DonneesEntreprise::class, 'smtpPassword'));
        $this->assertFalse(method_exists(DonneesEntreprise::class, 'testSmtpConnection'));

        // Enregistrer les données de l'entreprise ne touche plus le SMTP.
        $donnees->set('companyName', 'Ferme École OLOUWACHEGOUN')->call('save')->assertHasNoErrors();
        $s = CompanySetting::current();
        $this->assertSame(['smtp.ferme.bj', 465, 'ssl', 'secret'], [$s->smtp_host, (int) $s->smtp_port, $s->smtp_security, $s->smtp_password_encrypted]);

        Livewire::test(Integrations::class)
            ->assertDontSee('wire:model="smtpPassword"', false)
            ->assertDontSee('wire:model="smtpHost"', false)
            ->assertSee(route('parametres.hub', ['tab' => 'email']), false)
            ->assertSee('SMS — Fournisseur API');
        $this->assertFalse(method_exists(Integrations::class, 'saveSmtp'));
    }

    // ── Postes & Appairage ──────────────────────────────────────────────────────

    public function test_la_liste_des_postes_appairés_porte_les_jetons_et_l_etat_h3(): void
    {
        $admin = $this->compte('admin');
        $caissier = $this->compte('caissier');

        $jeton = $caissier->createToken('poste-caisse01', ['*'], now()->addDays(90))->accessToken;
        $jeton->forceFill(['created_at' => '2026-10-01 08:00:00', 'last_used_at' => now()->subHour()])->save();
        $admin->createToken('poste-bureau02');

        $this->actingAs($admin);
        Livewire::test(PostesAppairage::class)
            ->assertSee('poste-caisse01')
            ->assertSee('Caissier')
            ->assertSee('01/10/2026 08:00')
            ->assertSee(now()->addDays(90)->format('d/m/Y'))
            ->assertSee('À jour')
            ->assertSee('poste-bureau02')
            // Sans date propre, l'expiration est celle de Sanctum (`sanctum.expiration`), comptée depuis la création.
            ->assertSee(now()->addMinutes((int) config('sanctum.expiration'))->format('d/m/Y'));
    }

    /**
     * ⚠️⚠️ RÉVOQUER = LE JETON NE VAUT PLUS RIEN. Tous les jetons du poste (tous comptes) sont supprimés, ceux des
     * autres postes restent ; le poste ne peut plus ni se présenter (`/api/auth/me`) ni tirer (`/api/sync/pull`).
     */
    public function test_revoquer_l_appairage_supprime_les_jetons_du_poste_et_coupe_sa_synchronisation(): void
    {
        $admin = $this->compte('admin');
        $caissier = $this->compte('caissier');
        $animalier = $this->compte('animalier');

        $clair = $caissier->createToken('poste-caisse01')->plainTextToken;
        $animalier->createToken('poste-caisse01');
        $autre = $animalier->createToken('poste-elevage03')->plainTextToken;

        $this->withToken($clair)->getJson('/api/auth/me')->assertOk();
        $this->app['auth']->forgetGuards();

        $this->actingAs($admin);
        Livewire::test(PostesAppairage::class)
            ->call('revoquer', 'poste-caisse01')
            ->assertDispatched('toast', type: 'success')
            ->assertDontSee('poste-caisse01')
            ->assertSee('poste-elevage03');

        $this->assertSame(0, PersonalAccessToken::where('name', 'poste-caisse01')->count());
        $this->assertSame(1, PersonalAccessToken::where('name', 'poste-elevage03')->count());
        $this->assertTrue(AuditLog::where('action', 'sync.appairage_revoque')->where('user_id', $admin->id)->exists());

        $this->app['auth']->forgetGuards();
        $this->withToken($clair)->getJson('/api/auth/me')->assertUnauthorized();
        $this->app['auth']->forgetGuards();
        $this->withToken($clair)->getJson('/api/sync/pull')->assertUnauthorized();
        $this->app['auth']->forgetGuards();
        $this->withToken($autre)->getJson('/api/auth/me')->assertOk();
    }

    public function test_un_poste_inconnu_n_est_pas_revoque(): void
    {
        $admin = $this->compte('admin');
        $admin->createToken('poste-bureau02');
        // Jeton expiré : absent de la liste, donc non révocable depuis l'écran.
        $admin->createToken('poste-expire', ['*'], now()->subDay());

        $this->actingAs($admin);
        Livewire::test(PostesAppairage::class)
            ->call('revoquer', 'poste-forge')
            ->assertDispatched('toast', type: 'error')
            ->call('revoquer', 'poste-expire')
            ->assertDispatched('toast', type: 'error');

        $this->assertSame(2, PersonalAccessToken::count());
        $this->assertFalse(AuditLog::where('action', 'sync.appairage_revoque')->exists());
    }

    public function test_demander_la_synchronisation_depuis_l_onglet(): void
    {
        $admin = $this->compte('admin');
        $admin->createToken('poste-bureau02');

        $this->actingAs($admin);
        Livewire::test(PostesAppairage::class)
            ->call('demander', 'poste-bureau02')
            ->assertDispatched('toast', type: 'success')
            ->call('demander')
            ->assertDispatched('toast', type: 'success')
            ->call('demander', 'poste-forge')
            ->assertDispatched('toast', type: 'error');

        $this->assertSame(['poste-bureau02', null], DemandeSynchronisation::orderBy('demandee_le')->orderBy('created_at')->pluck('poste')->all());
    }

    public function test_l_onglet_postes_est_reserve_a_l_administrateur(): void
    {
        foreach (['comptable', 'caissier', 'animalier'] as $role) {
            $this->actingAs($this->compte($role));
            Livewire::test(PostesAppairage::class)->assertForbidden();
        }
    }
}
