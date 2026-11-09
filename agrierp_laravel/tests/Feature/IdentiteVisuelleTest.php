<?php

namespace Tests\Feature;

use App\Models\CompanySetting;
use App\Models\User;
use App\Services\PdfExportService;
use App\Support\IdentiteVisuelle;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/**
 * Ticket CONF-1 — LE LOGO ET LE FAVICON CHOISIS SONT RÉELLEMENT UTILISÉS (point de passage unique `IdentiteVisuelle`).
 *
 * Avant : les deux layouts pointaient `assets/images/logo_favicon.webp` sous le type `image/png` (faux) et l'en-tête des PDF
 * le logo fixe ; `company_settings.logo_path` / `favicon_path` ne servaient qu'à l'écran de réglage.
 */
class IdentiteVisuelleTest extends TestCase
{
    use RefreshDatabase;

    private const PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('public');
    }

    private function ico(): string
    {
        // En-tête ICO (1 image 1x1) + entrée d'annuaire + 4 octets de données : suffisant pour l'en-tête binaire.
        return "\x00\x00\x01\x00\x01\x00"."\x01\x01\x00\x00\x01\x00\x20\x00\x04\x00\x00\x00\x16\x00\x00\x00"."\x00\x00\x00\x00";
    }

    private function ranger(string $genre, string $nom, string $octets): void
    {
        Storage::disk('public')->put('company/'.$nom, $octets);
        CompanySetting::current()->update([$genre.'_path' => 'company/'.$nom]);
    }

    public function test_sans_fichier_choisi_le_repli_d_installation_sert_et_son_type_est_juste(): void
    {
        $this->assertNull(IdentiteVisuelle::logoUrl());
        $this->assertStringEndsWith('assets/images/favicon.ico', IdentiteVisuelle::faviconUrl());
        $this->assertSame('image/x-icon', IdentiteVisuelle::faviconType());
        $this->assertSame(public_path('assets/images/logo_ferme_ecole_officiel.png'), IdentiteVisuelle::logoCheminPdf());
    }

    public function test_le_logo_choisi_est_servi_avec_son_cache_busting(): void
    {
        $this->ranger('logo', 'abc.png', base64_decode(self::PNG));

        $url = IdentiteVisuelle::logoUrl();

        $this->assertStringContainsString('storage/company/abc.png?v=', $url);
        $this->assertMatchesRegularExpression('/\?v=\d+$/', $url);
    }

    public function test_le_type_du_favicon_est_deduit_du_fichier_jamais_ecrit_en_dur(): void
    {
        $this->ranger('favicon', 'f.ico', $this->ico());
        $this->assertSame('image/vnd.microsoft.icon', IdentiteVisuelle::faviconType());

        $this->ranger('favicon', 'f.png', base64_decode(self::PNG));
        $this->assertSame('image/png', IdentiteVisuelle::faviconType());

        // Un fichier dont l'extension MENT : le contenu décide.
        $this->ranger('favicon', 'menteur.png', $this->ico());
        $this->assertSame('image/vnd.microsoft.icon', IdentiteVisuelle::faviconType());
    }

    public function test_un_chemin_dont_le_fichier_a_disparu_vaut_aucun(): void
    {
        CompanySetting::current()->update(['logo_path' => 'company/disparu.png', 'favicon_path' => 'company/disparu.ico']);

        $this->assertNull(IdentiteVisuelle::logoUrl());
        $this->assertStringEndsWith('assets/images/favicon.ico', IdentiteVisuelle::faviconUrl());
    }

    public function test_le_layout_declare_l_icone_choisie_avec_le_bon_type(): void
    {
        $this->ranger('favicon', 'f.ico', $this->ico());

        $html = $this->get('/login')->assertOk()->getContent();

        $this->assertMatchesRegularExpression('#<link rel="icon" type="image/vnd\.microsoft\.icon" href="[^"]*storage/company/f\.ico\?v=\d+">#', $html);
        $this->assertStringNotContainsString('logo_favicon.webp', $html);
    }

    public function test_le_layout_sans_icone_choisie_garde_le_repli_avec_son_vrai_type(): void
    {
        $html = $this->get('/login')->assertOk()->getContent();

        $this->assertStringContainsString('<link rel="icon" type="image/x-icon" href="'.asset('assets/images/favicon.ico').'">', $html);
    }

    public function test_les_icones_par_defaut_sont_celles_de_la_ferme_et_de_vrais_fichiers(): void
    {
        $ico = (string) file_get_contents(public_path('assets/images/favicon.ico'));
        $this->assertSame('image/vnd.microsoft.icon', IdentiteVisuelle::typeMime($ico));
        $this->assertSame(4, unpack('v', substr($ico, 4, 2))[1], 'ICO de 4 tailles : 16, 32, 48, 64');
        $png = (string) file_get_contents(public_path('assets/images/favicon-32.png'));
        $this->assertSame('image/png', IdentiteVisuelle::typeMime($png));
        $this->assertSame([32, 32], array_slice(getimagesizefromstring($png), 0, 2));
        // Le logo de repli des documents est une image que DomPDF dessine.
        $logo = (string) file_get_contents(IdentiteVisuelle::logoCheminPdf());
        $this->assertContains(IdentiteVisuelle::typeMime($logo), ['image/png', 'image/jpeg']);
    }

    /** CONF-2 (décision du client du 08/11/2026) : LE TRACTEUR NE CHANGE JAMAIS — le logo choisi ne sert qu'aux documents et à l'onglet. */
    public function test_la_connexion_garde_l_icone_tracteur_meme_avec_un_logo_choisi(): void
    {
        $this->ranger('logo', 'abc.png', base64_decode(self::PNG));

        $this->get('/login')->assertOk()
            ->assertSee('agriculture', false)
            ->assertDontSee('data-logo-entreprise', false)
            ->assertDontSee('storage/company/abc.png', false);
    }

    public function test_la_barre_laterale_garde_l_icone_tracteur_meme_avec_un_logo_choisi(): void
    {
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $admin = User::create(['name' => 'Admin', 'username' => 'adm', 'email' => 'adm@x.bj', 'password' => bcrypt('x'), 'is_active' => true]);
        $admin->assignRole('admin');
        $this->ranger('logo', 'abc.png', base64_decode(self::PNG));

        $this->actingAs($admin)->get('/dashboard')->assertOk()
            ->assertSee('style="font-size:26px;">agriculture</span>', false)
            ->assertDontSee('storage/company/abc.png', false);
    }

    public function test_les_sources_du_tracteur_ne_lisent_jamais_le_logo_choisi(): void
    {
        foreach (['layouts/app.blade.php', 'livewire/auth/login.blade.php', 'components/verrou-session.blade.php'] as $vue) {
            $src = (string) file_get_contents(resource_path('views/'.$vue));
            $this->assertStringContainsString('>agriculture</span>', $src, $vue);
            $this->assertStringNotContainsString('IdentiteVisuelle::logo', $src, $vue);
            $this->assertStringNotContainsString('logo-entreprise', $src, $vue);
        }
        $this->assertFileDoesNotExist(resource_path('views/components/logo-entreprise.blade.php'));
    }

    public function test_le_pdf_emploie_le_logo_choisi_png_et_garde_le_repli_pour_un_format_que_dompdf_ne_dessine_pas(): void
    {
        $this->ranger('logo', 'abc.png', base64_decode(self::PNG));
        $this->assertSame(Storage::disk('public')->path('company/abc.png'), IdentiteVisuelle::logoCheminPdf());

        // Un logo webp sert au web ; le PDF garde le logo d'installation.
        $this->ranger('logo', 'abc.webp', 'RIFF'."\x00\x00\x00\x00".'WEBPVP8 ');
        $this->assertSame(public_path('assets/images/logo_ferme_ecole_officiel.png'), IdentiteVisuelle::logoCheminPdf());
    }

    public function test_l_en_tete_des_pdf_serveur_recoit_le_chemin_du_logo_choisi(): void
    {
        $this->ranger('logo', 'abc.png', base64_decode(self::PNG));
        $recu = null;
        \Barryvdh\DomPDF\Facade\Pdf::shouldReceive('loadView')->once()->andReturnUsing(function ($vue, $donnees) use (&$recu) {
            $recu = $donnees['companyLogo'];

            return \Mockery::mock(\Barryvdh\DomPDF\PDF::class)->shouldReceive('setPaper')->andReturnSelf()->getMock();
        });

        app(PdfExportService::class)->render('exports.facture-vente', [], 'Facture', 'Période');

        $this->assertSame(Storage::disk('public')->path('company/abc.png'), $recu);
    }

    public function test_l_attestation_garde_son_logo_mesure_sur_le_modele_du_client(): void
    {
        $source = (string) file_get_contents(app_path('Services/AttestationService.php'));

        $this->assertStringContainsString("resource_path('attestation/images/logo-ferme.png')", $source);
        $this->assertStringNotContainsString('IdentiteVisuelle', $source);
    }
}
