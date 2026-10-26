<?php

namespace Tests\Feature;

use App\Livewire\Profil\MonProfil;
use Livewire\Livewire;

/**
 * Sprint VW — côté Livewire : Mon Profil porte le réglage, et une action Livewire n'atteint jamais un composant
 * tant que la session est verrouillée (c'est le middleware, pas la surcouche, qui l'empêche).
 */
class VerrouSessionLivewireTest extends VerrouSessionBase
{
    public function test_mon_profil_montre_la_carte_verrouillage_automatique_sous_le_mot_de_passe(): void
    {
        $u = $this->utilisateur();

        $html = Livewire::actingAs($u)->test(MonProfil::class)->html();

        $this->assertStringContainsString('Verrouillage automatique', $html);
        $this->assertLessThan(strpos($html, 'Verrouillage automatique'), strpos($html, 'Modifier le Mot de Passe'));
        $this->assertStringContainsString("Après ce délai sans toucher à la souris ni au clavier, l'application se verrouille : ", html_entity_decode($html));
        // Les cinq choix, dans l'ordre.
        $this->assertMatchesRegularExpression('#Jamais.*1 minute.*5 minutes.*15 minutes.*30 minutes#s', $html);
    }

    public function test_un_envoi_livewire_reel_vers_mon_profil_est_refuse_verrouille(): void
    {
        $this->verrouille();

        // Même requête qu'enverrait le navigateur d'un onglet resté ouvert : refusée avant d'atteindre le composant.
        $this->postJson('/livewire/update', [
            'components' => [['snapshot' => '{}', 'updates' => ['verrouillage_minutes' => 0], 'calls' => []]],
        ], ['X-Livewire' => ''])->assertStatus(423);

        $this->assertSame(5, auth()->user()->fresh()->verrouillage_minutes);
    }
}
