<?php

namespace Tests\Feature;

use App\Livewire\Parametres\DonneesEntreprise;
use App\Models\AuditLog;
use App\Models\CompanySetting;
use App\Models\User;
use App\Services\EntrepriseService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket CONF-1 — TÉLÉVERSEMENT DU LOGO ET DU FAVICON : formats (le favicon accepte ICO, que la règle `image` de Laravel refuse),
 * jugement sur l'EN-TÊTE binaire, TOUT jugé avant d'écrire, ancien fichier effacé, suppression, glisser-déposer, mêmes messages
 * au web et à l'API (le poste les recopie).
 */
class LogoFaviconTest extends TestCase
{
    use RefreshDatabase;

    private const PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

    private const WEBP = 'UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA==';

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('public');
        Storage::fake('local');
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $this->admin = $this->compte('admin');
        CompanySetting::current()->update(['company_name' => 'Ferme', 'ifu' => '3202601234567']);
    }

    private function compte(string $role): User
    {
        $u = User::create(['name' => ucfirst($role), 'username' => $role, 'email' => $role.'@x.bj', 'password' => bcrypt('x'), 'is_active' => true]);
        $u->assignRole($role);

        return $u;
    }

    private function png(): string
    {
        return base64_decode(self::PNG);
    }

    private function ico(): string
    {
        return "\x00\x00\x01\x00\x01\x00\x01\x01\x00\x00\x01\x00\x20\x00\x04\x00\x00\x00\x16\x00\x00\x00\x00\x00\x00\x00";
    }

    private function fichier(string $nom, string $octets): UploadedFile
    {
        return UploadedFile::fake()->createWithContent($nom, $octets);
    }

    private function ecran()
    {
        return Livewire::actingAs($this->admin)->test(DonneesEntreprise::class);
    }

    /** @return array<int, string> */
    private function fichiersRanges(): array
    {
        return Storage::disk('public')->files('company');
    }

    // ── Formats ────────────────────────────────────────────────────────────────

    public function test_le_logo_accepte_png_jpg_et_webp(): void
    {
        $jpg = (string) file_get_contents(__DIR__.'/../../public/assets/images/logo.png');
        $this->assertNotSame('', $jpg);

        foreach (['logo.png' => $this->png(), 'logo.webp' => base64_decode(self::WEBP)] as $nom => $octets) {
            $this->ecran()->set('logoFile', $this->fichier($nom, $octets))->assertHasNoErrors('logoFile');
        }

        $img = imagecreatetruecolor(2, 2);
        ob_start();
        imagejpeg($img);
        $jpeg = (string) ob_get_clean();
        $this->ecran()->set('logoFile', $this->fichier('logo.jpg', $jpeg))->assertHasNoErrors('logoFile');
    }

    public function test_le_logo_refuse_gif_svg_ico_et_faux_png_avec_le_message_exact(): void
    {
        $refus = [
            'logo.gif' => base64_decode('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'),
            'logo.svg' => '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>',
            'logo.ico' => $this->ico(),
            'faux.png' => 'ceci est du texte, pas une image',
            'logo.exe' => $this->png(),
        ];

        foreach ($refus as $nom => $octets) {
            $this->ecran()->set('logoFile', $this->fichier($nom, $octets))
                ->assertHasErrors(['logoFile'])
                ->assertSet('logoFile', null)
                ->assertSee('Le logo doit être une image PNG, JPG ou WEBP.');
        }
    }

    public function test_le_favicon_accepte_ico_et_png_et_refuse_le_reste(): void
    {
        // Le cas annoncé par la consigne : « ICO ou PNG ».
        $this->ecran()->set('faviconFile', $this->fichier('favicon.ico', $this->ico()))->assertHasNoErrors('faviconFile');
        $this->ecran()->set('faviconFile', $this->fichier('favicon.png', $this->png()))->assertHasNoErrors('faviconFile');

        foreach (['favicon.webp' => base64_decode(self::WEBP), 'favicon.ico ' => 'MZ pas un ico', 'faux.ico' => "\x00\x00\x02\x00\x01\x00"] as $nom => $octets) {
            $this->ecran()->set('faviconFile', $this->fichier(trim($nom), $octets))
                ->assertHasErrors(['faviconFile'])
                ->assertSee("L'icône du site doit être un fichier ICO ou PNG.");
        }
    }

    public function test_un_ico_dont_l_annuaire_est_tronque_est_refuse(): void
    {
        $this->ecran()->set('faviconFile', $this->fichier('f.ico', "\x00\x00\x01\x00\x05\x00\x01\x01"))->assertHasErrors(['faviconFile']);
    }

    public function test_les_tailles_maximales_sont_celles_annoncees(): void
    {
        $this->ecran()->set('logoFile', $this->fichier('gros.png', $this->png().str_repeat("\0", 2 * 1024 * 1024)))
            ->assertHasErrors(['logoFile'])->assertSee('Le logo ne doit pas dépasser 2 Mo.');

        $this->ecran()->set('faviconFile', $this->fichier('gros.ico', $this->ico().str_repeat("\0", 501 * 1024)))
            ->assertHasErrors(['faviconFile'])->assertSee("L'icône du site ne doit pas dépasser 500 Ko.");

        $this->ecran()->set('faviconFile', $this->fichier('ok.png', $this->png().str_repeat("\0", 400 * 1024)))->assertHasNoErrors('faviconFile');
    }

    // ── Enregistrement ─────────────────────────────────────────────────────────

    public function test_le_logo_et_le_favicon_sont_ranges_et_servent_aussitot(): void
    {
        $this->ecran()
            ->set('logoFile', $this->fichier('logo.png', $this->png()))
            ->set('faviconFile', $this->fichier('favicon.ico', $this->ico()))
            ->call('save')->assertHasNoErrors();

        $e = CompanySetting::current();
        $this->assertStringEndsWith('.png', $e->logo_path);
        $this->assertStringEndsWith('.ico', $e->favicon_path);
        $this->assertCount(2, $this->fichiersRanges());
    }

    public function test_tout_est_juge_avant_d_ecrire_un_logo_valide_n_est_pas_range_quand_le_favicon_est_refuse(): void
    {
        // On force les deux fichiers dans l'état du composant, comme un envoi qui contourne le jugement au dépôt.
        $composant = $this->ecran();
        $composant->set('logoFile', $this->fichier('logo.png', $this->png()));
        $composant->set('faviconFile', $this->fichier('favicon.ico', $this->ico()));
        $this->assertCount(0, $this->fichiersRanges());

        // Côté service (poste et web) : un logo valide ET un favicon refusé → aucune écriture.
        try {
            app(EntrepriseService::class)->fichiersDepuis([
                'logo' => ['octets' => $this->png(), 'nom' => 'logo.png'],
                'favicon' => ['octets' => 'pas une icône', 'nom' => 'favicon.ico'],
            ]);
            $this->fail('Le favicon refusé aurait dû lever une erreur.');
        } catch (ValidationException $e) {
            $this->assertArrayHasKey('faviconFile', $e->errors());
            $this->assertArrayNotHasKey('logoFile', $e->errors());
        }

        $this->assertSame([], $this->fichiersRanges());
        $this->assertNull(CompanySetting::current()->logo_path);
    }

    public function test_un_refus_a_l_enregistrement_n_abandonne_aucun_fichier_sur_le_disque(): void
    {
        $this->ecran()
            ->set('logoFile', $this->fichier('logo.png', $this->png()))
            ->set('ifu', '')               // refusé par les règles
            ->call('save')->assertHasErrors(['ifu']);

        $this->assertSame([], $this->fichiersRanges());

        // Refus tardif du service (e-MECeF exige 13 chiffres) : le fichier déjà rangé est retiré.
        CompanySetting::current()->update(['mecef_mode' => 'emecef']);
        $service = app(EntrepriseService::class);
        $fichiers = $service->fichiersDepuis(['logo' => ['octets' => $this->png()]]);
        $this->assertCount(1, $this->fichiersRanges());

        try {
            $service->enregistrer($this->valeurs(['ifu' => '123', 'mecefMode' => 'emecef']), $this->admin, $fichiers);
            $this->fail('IFU invalide accepté.');
        } catch (ValidationException) {
        }

        $this->assertSame([], $this->fichiersRanges());
    }

    public function test_remplacer_efface_l_ancien_fichier(): void
    {
        $this->ecran()->set('logoFile', $this->fichier('un.png', $this->png()))->call('save');
        $ancien = CompanySetting::current()->logo_path;
        Storage::disk('public')->assertExists($ancien);

        $this->ecran()->set('logoFile', $this->fichier('deux.png', $this->png()))->call('save');
        $nouveau = CompanySetting::current()->logo_path;

        $this->assertNotSame($ancien, $nouveau);
        Storage::disk('public')->assertMissing($ancien);
        Storage::disk('public')->assertExists($nouveau);
        $this->assertCount(1, $this->fichiersRanges());
    }

    public function test_enregistrer_sans_nouveau_fichier_conserve_les_anciens(): void
    {
        $this->ecran()->set('logoFile', $this->fichier('un.png', $this->png()))->call('save');
        $chemin = CompanySetting::current()->logo_path;

        $this->ecran()->set('companyName', 'Ferme 2')->call('save')->assertHasNoErrors();

        $this->assertSame($chemin, CompanySetting::current()->logo_path);
        Storage::disk('public')->assertExists($chemin);
    }

    public function test_supprimer_retire_la_colonne_et_le_fichier_et_laisse_l_autre(): void
    {
        $this->ecran()->set('logoFile', $this->fichier('un.png', $this->png()))
            ->set('faviconFile', $this->fichier('f.ico', $this->ico()))->call('save');
        $logo = CompanySetting::current()->logo_path;
        $favicon = CompanySetting::current()->favicon_path;

        $this->ecran()->call('supprimerFichier', 'logo')->assertDispatched('toast', type: 'success');

        $this->assertNull(CompanySetting::current()->logo_path);
        Storage::disk('public')->assertMissing($logo);
        $this->assertSame($favicon, CompanySetting::current()->favicon_path);
        Storage::disk('public')->assertExists($favicon);
        $this->assertSame(1, AuditLog::where('action', 'company_settings.fichier_supprime')->count());

        $this->ecran()->call('supprimerFichier', 'favicon');
        $this->assertSame([], $this->fichiersRanges());

        $this->ecran()->call('supprimerFichier', 'autre')->assertNotFound();
    }

    public function test_le_bouton_supprimer_demande_confirmation_et_n_apparait_que_s_il_y_a_un_fichier(): void
    {
        $this->ecran()->assertDontSee('supprimerFichier', false);

        $this->ecran()->set('logoFile', $this->fichier('un.png', $this->png()))->call('save');

        $this->ecran()->assertSee("supprimerFichier('logo')", false)->assertDontSee("supprimerFichier('favicon')", false)
            ->assertSee('wire:confirm="Supprimer le logo de l\'entreprise ? Le fichier sera effacé."', false);
    }

    // ── API (demande `entreprise` du poste) ────────────────────────────────────

    /** @return array<string, mixed> */
    private function valeurs(array $remplace = []): array
    {
        return array_merge([
            'companyName' => 'Ferme', 'ifu' => '3202601234567', 'vpsRate' => 4, 'cnssEmployeeRate' => 3.6,
            'cnssEmployerPensionRate' => 6.4, 'cnssEmployerFamilyRate' => 9, 'cnssEmployerRiskRate' => 2,
        ], $remplace);
    }

    private function envoyer(array $payload)
    {
        $id = (string) Str::uuid();

        return $this->actingAs($this->admin, 'sanctum')->postJson('/api/sync/push', [
            'device_id' => 'poste-test', 'settings_requests' => [['id' => $id, 'kind' => 'entreprise', 'payload' => $this->valeurs($payload)]],
        ]);
    }

    public function test_l_api_accepte_un_favicon_ico_et_juge_tout_avant_d_ecrire(): void
    {
        $this->envoyer(['faviconB64' => base64_encode($this->ico())])->assertJsonPath('settings_requests.accepted.0', fn ($v) => $v !== null);
        $this->assertStringEndsWith('.ico', CompanySetting::current()->favicon_path);
        $this->assertCount(1, $this->fichiersRanges());

        $r = $this->envoyer(['logoB64' => base64_encode($this->png()), 'faviconB64' => base64_encode('pas une icône')]);
        $this->assertSame("L'icône du site doit être un fichier ICO ou PNG.", $r->json('settings_requests.rejected.0.reason'));
        $this->assertNull(CompanySetting::current()->logo_path, 'le logo valide ne doit pas être écrit quand le favicon est refusé');
        $this->assertCount(1, $this->fichiersRanges());
    }

    public function test_les_messages_de_l_api_sont_ceux_du_web(): void
    {
        $web = [
            'logo.format' => 'Le logo doit être une image PNG, JPG ou WEBP.',
            'logo.taille' => 'Le logo ne doit pas dépasser 2 Mo.',
            'favicon.format' => "L'icône du site doit être un fichier ICO ou PNG.",
            'favicon.taille' => "L'icône du site ne doit pas dépasser 500 Ko.",
        ];

        foreach ($web as $cle => $message) {
            [$genre, $motif] = explode('.', $cle);
            $this->assertSame($message, EntrepriseService::messageFichier($genre, $motif));
        }

        $r = $this->envoyer(['logoB64' => base64_encode('texte')]);
        $this->assertSame($web['logo.format'], $r->json('settings_requests.rejected.0.reason'));

        $r = $this->envoyer(['logoB64' => base64_encode($this->png().str_repeat("\0", 2 * 1024 * 1024))]);
        $this->assertSame($web['logo.taille'], $r->json('settings_requests.rejected.0.reason'));
    }

    public function test_l_api_remplace_et_supprime_en_effacant_l_ancien_fichier(): void
    {
        $this->envoyer(['logoB64' => base64_encode($this->png())]);
        $ancien = CompanySetting::current()->logo_path;

        $this->envoyer(['logoB64' => base64_encode($this->png().'x')]);
        Storage::disk('public')->assertMissing($ancien);
        $courant = CompanySetting::current()->logo_path;
        Storage::disk('public')->assertExists($courant);

        $this->envoyer(['logoSupprimer' => true]);
        $this->assertNull(CompanySetting::current()->logo_path);
        Storage::disk('public')->assertMissing($courant);

        // Sans clé de suppression ni fichier : rien ne change.
        $this->envoyer(['faviconB64' => base64_encode($this->png())]);
        $this->envoyer([]);
        $this->assertNotNull(CompanySetting::current()->favicon_path);
    }

    // ── Droits ─────────────────────────────────────────────────────────────────

    public function test_l_ecran_est_ferme_sans_manage_parametres(): void
    {
        \App\Models\Role::findOrCreate('lecteur-param', 'web')->givePermissionTo('view-parametres');
        $lecteur = $this->compte('lecteur-param');

        Livewire::actingAs($lecteur)->test(DonneesEntreprise::class)->assertForbidden();
    }

    // ── Vue : glisser-déposer, textes, icône ───────────────────────────────────

    public function test_la_vue_porte_le_glisser_deposer_les_textes_d_aide_et_l_icone(): void
    {
        $vue = (string) file_get_contents(resource_path('views/livewire/parametres/donnees-entreprise.blade.php'));

        foreach ([
            'Glisser-déposer ou cliquer pour choisir un logo', 'Glisser-déposer ou cliquer pour choisir un favicon',
            'PNG carré, fond transparent recommandé, max 2 Mo', 'ICO ou PNG 32x32px, max 500 Ko',
            'add_photo_alternate', 'x-on:dragover.prevent', 'x-on:drop.prevent', 'x-on:dragleave.prevent', 'Supprimer',
        ] as $attendu) {
            $this->assertStringContainsString($attendu, $vue, $attendu);
        }

        $this->assertStringNotContainsString('Alpine.start', $vue);
        $this->assertStringNotContainsString('addEventListener', $vue);
        $this->assertStringNotContainsString('accept="image/*"', $vue, 'le sélecteur doit annoncer ICO, que `image/*` ne couvre pas');
    }
}
