<?php

namespace Tests\Feature;

use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * CAISSE-1 (DV-32) : à l'activation, le type d'appareil est choisi — « entreprise » (défaut recommandé, PIN de 4 à 6 chiffres) ou « personnel » (PIN de 6 chiffres,
 * tout effacé à la déconnexion). Le choix et ses règles vivent dans le navigateur (chiffré avec l'appairage, rien en clair, rien sur le serveur) : ces tests gardent
 * la PAGE WEB (les chaînes d'abord) et l'absence de tout secret ou réglage serveur ; les règles du PIN et l'effacement sont prouvés par `tests/Js/appareil-type.test.mjs`.
 */
class ModeHorsLigneTypeAppareilTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolesAndPermissionsSeeder::class);
    }

    private function compte(string $role): User
    {
        $u = User::create(['name' => ucfirst($role), 'username' => $role, 'email' => $role.'@fermeolouwachegoun.com', 'password' => bcrypt('LogiAgriERP@2026'), 'is_active' => true]);
        $u->assignRole($role);

        return $u;
    }

    public function test_la_page_propose_les_deux_types_d_appareil_avec_leurs_regles(): void
    {
        foreach (['caissier', 'animalier', 'admin'] as $role) {
            $page = $this->actingAs($this->compte($role))->get('/mode-hors-ligne');
            $page->assertOk()
                ->assertSee('id="hl-type-entreprise"', false)->assertSee('id="hl-type-personnel"', false)
                ->assertSee('Type d\'appareil', false)->assertSee('Appareil de l\'entreprise', false)->assertSee('(recommandé)', false)
                ->assertSee('PIN de 4 à 6 chiffres', false)
                ->assertSee('Appareil personnel', false)->assertSee('PIN de 6 chiffres obligatoire', false)
                ->assertSee('TOUTES les données hors ligne', false)
                ->assertSee('Imprimer le reçu provisoire', false)->assertSee('Facture n° attribué à la synchronisation.', false);
            auth()->logout();
            User::where('username', $role)->delete();
        }
    }

    public function test_aucun_secret_ni_reglage_serveur_pour_le_type_d_appareil(): void
    {
        $vue = file_get_contents(resource_path('views/livewire/profil/mode-hors-ligne.blade.php'));
        $this->assertStringNotContainsString('wire:model', $vue);
        $this->assertStringNotContainsString('localStorage', $vue);
        $composant = file_get_contents(app_path('Livewire/Profil/ModeHorsLigne.php'));
        $this->assertStringNotContainsString('type_appareil', $composant, 'le type d\'appareil n\'est jamais écrit côté serveur');
        $this->assertStringNotContainsString('typeAppareil', $composant);
    }
}
