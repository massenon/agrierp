<?php

namespace Tests\Feature;

use App\Services\VerrouSessionService;

/**
 * Sprint VW (VW2) — garde-fous LUS dans le code source du navigateur : la minuterie et la surcouche sont dans le
 * gabarit de l'application (et nulle part ailleurs), les durées du JavaScript sont celles du serveur, le menu du
 * compte propose « Verrouiller ». Ce que ces tests verrouillent est invisible à `Livewire::test()` (zéro JavaScript).
 */
class VerrouSessionBladeTest extends VerrouSessionBase
{
    private function source(string $chemin): string
    {
        return file_get_contents(base_path($chemin));
    }

    public function test_le_gabarit_de_l_application_porte_la_surcouche_et_la_minuterie(): void
    {
        $app = $this->source('resources/views/layouts/app.blade.php');

        $this->assertStringContainsString('<x-verrou-session', $app);
        $this->assertStringContainsString("minutes=\"{{ auth()->user()->delaiVerrouillage() }}\"", $app);
    }

    public function test_ni_la_connexion_ni_les_pages_publiques_n_ont_de_minuterie(): void
    {
        $this->assertStringNotContainsString('x-verrou-session', $this->source('resources/views/layouts/guest.blade.php'));
        $this->assertStringNotContainsString('x-verrou-session', $this->source('resources/views/livewire/auth/login.blade.php'));

        $this->get('/login')->assertOk()->assertDontSee('data-verrou-minutes', false);
        $this->get('/welcome')->assertOk()->assertDontSee('data-verrou-minutes', false);
    }

    public function test_le_menu_du_compte_propose_verrouiller_avant_le_separateur_de_deconnexion(): void
    {
        $app = $this->source('resources/views/layouts/app.blade.php');
        $menu = substr($app, strpos($app, 'id="dd-profile"'));
        $menu = substr($menu, 0, strpos($menu, '</form>'));

        $this->assertMatchesRegularExpression(
            '#<span class="material-symbols-outlined text-\[16px\]">lock</span>Verrouiller</button>#',
            $menu,
        );
        $this->assertStringContainsString('dusk="verrouiller"', $menu);
        $this->assertLessThan(strpos($menu, 'Déconnexion'), strpos($menu, 'Verrouiller'));
        $this->assertGreaterThan(strpos($menu, 'Paramètres'), strpos($menu, 'Verrouiller'));
        // Avant le séparateur, comme au poste (« Verrouiller » est au-dessus du trait, « Déconnexion » en dessous).
        $this->assertLessThan(strpos($menu, '<div class="border-t border-outline-variant"></div>'), strpos($menu, 'Verrouiller'));
    }

    public function test_la_page_rendue_contient_le_menu_la_surcouche_et_les_textes_communs_au_poste(): void
    {
        $this->actingAs($this->utilisateur());

        $this->get('/mon-profil')->assertOk()
            ->assertSee('Verrouiller')
            ->assertSee('Application verrouillée')
            ->assertSee("NOM D'UTILISATEUR", false)
            ->assertSee('MOT DE PASSE')
            ->assertSee('DÉVERROUILLER')
            ->assertSee('Se déconnecter')
            ->assertSee('data-verrou-minutes="5"', false);
    }

    public function test_l_ecran_de_verrouillage_a_la_presentation_de_la_connexion(): void
    {
        $this->verrouille();

        $this->get(route('session.verrou'))->assertOk()
            ->assertSee('assets/images/image_login.png', false)
            ->assertSee('Ferme Olouwachegoun')
            ->assertSee('Application verrouillée')
            ->assertSee('Session de M. Olouchègoun. Saisissez votre mot de passe pour reprendre votre travail.')
            ->assertSee('value="admin"', false)
            ->assertSee('readonly', false)
            ->assertSee('DÉVERROUILLER');
    }

    public function test_l_ecran_de_verrouillage_redirige_si_la_session_n_est_pas_verrouillee(): void
    {
        $this->actingAs($this->utilisateur());

        $this->get(route('session.verrou'))->assertRedirect(route('dashboard.index'));
    }

    public function test_l_ecran_de_verrouillage_exige_une_connexion(): void
    {
        $this->get(route('session.verrou'))->assertRedirect(route('login'));
    }

    public function test_le_javascript_est_branche_et_traite_le_423_les_requetes_en_vol_et_les_onglets(): void
    {
        $app = $this->source('resources/js/app.js');
        $verrou = $this->source('resources/js/verrou.js');

        $this->assertStringContainsString("import './verrou'", $app);
        $this->assertStringContainsString('423', $verrou);
        $this->assertStringContainsString("Livewire.hook('request'", $verrou);
        $this->assertStringContainsString("route('session.verrouiller')", $this->source('resources/views/components/verrou-session.blade.php'));
        $this->assertStringContainsString("'/verrouiller'", $this->source('routes/web.php'));
        $this->assertStringContainsString('localStorage', $verrou);
        $this->assertStringContainsString("addEventListener('storage'", $verrou);
        foreach (['pointerdown', 'keydown', 'scroll', 'wheel', 'touchstart'] as $evenement) {
            $this->assertStringContainsString("'$evenement'", $verrou, $evenement);
        }
    }

    public function test_les_durees_du_javascript_sont_celles_du_serveur(): void
    {
        $js = $this->source('resources/js/verrou-logique.js');

        $this->assertSame(1, preg_match('/export const DUREES = \[([0-9, ]+)\]/', $js, $m));
        $this->assertSame(VerrouSessionService::DUREES, array_map('intval', explode(',', $m[1])));
        $this->assertSame(1, preg_match('/export const DUREE_PAR_DEFAUT = (\d+)/', $js, $d));
        $this->assertSame(VerrouSessionService::DUREE_PAR_DEFAUT, (int) $d[1]);
    }

    public function test_la_logique_javascript_passe_ses_tests_node(): void
    {
        $node = trim((string) shell_exec('command -v node 2>/dev/null'));
        if ($node === '') {
            $this->markTestSkipped('Node absent : tests/Js/*.test.mjs non exécutés.');
        }

        exec(escapeshellarg($node).' --test '.escapeshellarg(base_path('tests/Js/verrou-logique.test.mjs')).' '.escapeshellarg(base_path('tests/Js/verrou-composant.test.mjs')).' 2>&1', $sortie, $code);

        $this->assertSame(0, $code, implode("\n", $sortie));
    }
}
