<?php

namespace Tests\Feature;

use Tests\TestCase;

/**
 * Ticket 15.7 — LE MAÏS DE LA MARQUE SUR FOND CLAIR.
 *
 * ⚠️⚠️ CE QUE CE CONTRÔLE PROTÈGE. #FFD55F sur blanc donne 1,41:1 là où WCAG AA
 * exige 4,5:1. Le « ERP » de « AgriERP » était illisible sur la page de
 * connexion, et l'étiquette de catégorie de la recherche globale — 10 px, gras,
 * sur panneau blanc — l'était davantage encore : celle-là n'est même pas un
 * logo, c'est du texte d'interface, et l'audit ne l'avait pas vue parce que le
 * panneau était fermé pendant la mesure.
 *
 * La couleur claire reste la règle sur fond sombre (10,6:1 sur `brand-forest`).
 * Ce test garde la séparation : elle se perd en une seule copie de ligne.
 */
class ContrasteMarqueTest extends TestCase
{
    /** Surfaces claires : le maïs foncé, jamais le maïs clair. */
    private const SUR_FOND_CLAIR = [
        'resources/views/livewire/auth/login.blade.php',
        // Sprint VW : l'écran de verrouillage reprend la page de connexion (même logo sur fond blanc).
        'resources/views/components/verrou-session.blade.php',
        'resources/views/livewire/shared/global-search.blade.php',
    ];

    private function luminance(string $hex): float
    {
        $hex = ltrim($hex, '#');
        $canaux = [];

        foreach ([0, 2, 4] as $decalage) {
            $valeur = hexdec(substr($hex, $decalage, 2)) / 255;
            $canaux[] = $valeur <= 0.03928
                ? $valeur / 12.92
                : (($valeur + 0.055) / 1.055) ** 2.4;
        }

        return 0.2126 * $canaux[0] + 0.7152 * $canaux[1] + 0.0722 * $canaux[2];
    }

    private function rapport(string $a, string $b): float
    {
        $la = $this->luminance($a);
        $lb = $this->luminance($b);

        return (max($la, $lb) + 0.05) / (min($la, $lb) + 0.05);
    }

    /**
     * ⚠️ LE SEUIL EST CALCULÉ, PAS RECOPIÉ. Quelqu'un qui éclaircirait le token
     * « pour se rapprocher du jaune de la marque » repasserait sous 4,5:1 sans
     * qu'aucun test ne bouge, si celui-ci se contentait de comparer une chaîne.
     */
    public function test_the_ink_maize_passes_wcag_aa_on_white(): void
    {
        $config = file_get_contents(base_path('tailwind.config.js'));

        $this->assertMatchesRegularExpression(
            "/'brand-maize-ink':\s*'(#[0-9A-Fa-f]{6})'/",
            $config,
            'Le token brand-maize-ink a disparu de tailwind.config.js.'
        );

        preg_match("/'brand-maize-ink':\s*'(#[0-9A-Fa-f]{6})'/", $config, $trouve);

        $this->assertGreaterThanOrEqual(
            4.5,
            $this->rapport($trouve[1], '#FFFFFF'),
            $trouve[1].' sur blanc ne passe plus le seuil WCAG AA de 4,5:1.'
        );
    }

    /** Sur fond sombre, la couleur validée par le client ne bouge pas. */
    public function test_the_bright_maize_stays_readable_on_the_dark_brand_background(): void
    {
        $this->assertGreaterThanOrEqual(4.5, $this->rapport('#FFD55F', '#052e16'));
    }

    public function test_no_light_surface_view_uses_the_bright_maize(): void
    {
        $fautives = [];

        foreach (self::SUR_FOND_CLAIR as $vue) {
            $contenu = file_get_contents(base_path($vue));

            // ⚠️ LE PANNEAU `<aside>` EST L'EXCEPTION LÉGITIME : la page de
            // connexion y pose le logo sur une photo assombrie, où le maïs
            // clair donne son meilleur rendu. On l'écarte avant de contrôler
            // le reste de la page, qui est blanc.
            $surFondClair = preg_replace('/<aside\b.*?<\/aside>/s', '', $contenu);

            // `brand-maize` suivi d'autre chose que `-ink`.
            if (preg_match('/brand-maize(?!-ink)/', $surFondClair)) {
                $fautives[] = $vue;
            }
        }

        $this->assertSame(
            [],
            $fautives,
            'Ces vues sont posées sur fond clair et emploient le maïs clair '
            .'(1,41:1) : utilisez `brand-maize-ink`.'
        );
    }
}
