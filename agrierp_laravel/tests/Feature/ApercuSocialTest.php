<?php

namespace Tests\Feature;

use Tests\TestCase;

/**
 * Aperçu de partage du produit : l'image (1280×640) est servie par le site, et les pages portent les balises
 * `og:image` / `twitter:card` (réseaux sociaux, messageries). Même image que celle du poste.
 */
class ApercuSocialTest extends TestCase
{
    public function test_l_image_d_apercu_existe_en_1280_par_640(): void
    {
        $chemin = public_path('assets/images/social-preview.png');
        $this->assertFileExists($chemin);

        [$largeur, $hauteur, $type] = getimagesize($chemin);
        $this->assertSame([1280, 640, IMAGETYPE_PNG], [$largeur, $hauteur, $type]);
    }

    public function test_la_page_de_connexion_porte_les_balises_de_partage(): void
    {
        $page = $this->get('/login')->assertOk();

        $page->assertSee('property="og:image" content="'.url('assets/images/social-preview.png').'"', false);
        $page->assertSee('name="twitter:card" content="summary_large_image"', false);
        $page->assertSee('property="og:title" content="LogiAgriERP', false);
    }

    public function test_la_meme_image_est_livree_au_poste(): void
    {
        $poste = base_path('../agrierp_flutter/assets/images/social-preview.png');
        if (! is_file($poste)) {
            $this->markTestSkipped('poste absent de ce dépôt');
        }
        $this->assertSame(md5_file(public_path('assets/images/social-preview.png')), md5_file($poste));
    }
}
