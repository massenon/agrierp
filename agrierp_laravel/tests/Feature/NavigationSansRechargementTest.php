<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\Blade;
use Tests\TestCase;

/**
 * Navigation sans rechargement (`wire:navigate`) et ergonomie mobile de la modale de synchronisation.
 *
 * Ces garde-fous lisent les vues : le comportement réel (aucun rechargement, aucune erreur JavaScript) a été vérifié dans un
 * vrai navigateur ; ce qui casserait en silence est un lien interne ajouté SANS `wire:navigate`, ou un écouteur global
 * du verrou posé sans être retiré (il se cumulerait à chaque page).
 */
class NavigationSansRechargementTest extends TestCase
{
    public function test_les_liens_du_menu_et_des_cartes_naviguent_sans_rechargement(): void
    {
        $this->assertStringContainsString('wire:navigate', Blade::render('<x-sidebar-link href="/dashboard" icon="dashboard" label="Tableau" />'));
        $this->assertStringContainsString('wire:navigate', Blade::render('<x-nav-card href="/dashboard" icon="dashboard" title="Tableau" />'));
    }

    public function test_aucun_lien_interne_de_la_mise_en_page_ne_recharge_la_page(): void
    {
        $mise = file_get_contents(resource_path('views/layouts/app.blade.php'));

        preg_match_all('/<a\s+(?!wire:navigate)[^>]*href="\/[a-z][^"]*"[^>]*>/', $mise, $liens);
        $this->assertSame([], $liens[0], 'liens internes sans wire:navigate dans layouts/app.blade.php');
    }

    public function test_les_ecouteurs_du_verrou_sont_retires_a_chaque_initialisation(): void
    {
        $js = file_get_contents(resource_path('js/verrou.js'));

        $this->assertStringContainsString('retirerEcouteurs();', $js);
        $debut = strpos($js, 'init() {');
        $init = substr($js, $debut, strpos($js, '_marquerActivite(forcer') - $debut);
        $this->assertStringNotContainsString('window.addEventListener', $init);
        $this->assertStringNotContainsString('document.addEventListener', $init);
        $this->assertStringContainsString('minuterieVerification = window.setInterval', $init, 'la minuterie est mémorisée pour être arrêtée');
    }

    public function test_la_modale_de_synchronisation_est_utilisable_au_doigt_et_sans_textes_d_aide(): void
    {
        $vue = file_get_contents(resource_path('views/livewire/shared/etat-synchronisation-postes.blade.php'));

        $this->assertStringNotContainsString('base de référence', $vue);
        $this->assertStringNotContainsString('a servi de base', $vue);
        $this->assertStringContainsString('flex-col-reverse sm:flex-row', $vue, 'pied en pile sur mobile');
        $this->assertStringContainsString('w-full sm:w-auto min-h-[44px]', $vue, 'boutons pleine largeur, cible de 44 px');
        $this->assertStringContainsString('w-11 h-11', $vue, 'croix de fermeture de 44 px');
    }

    public function test_la_cloche_ne_releve_pas_pendant_le_verrou_et_arrete_sa_minuterie(): void
    {
        $vue = file_get_contents(resource_path('views/livewire/shared/notification-bell.blade.php'));

        $this->assertStringNotContainsString('wire:poll', $vue, 'un wire:poll continuerait de frapper le serveur verrouillé (423)');
        $this->assertStringContainsString('window.agrierpVerrou?.verrouille', $vue);
        $this->assertStringContainsString('document.hidden', $vue);
        $this->assertStringContainsString('window.clearInterval(this.minuterie)', $vue);
    }
}
