<?php

namespace Tests\Feature;

use App\Livewire\Profil\MonProfil;
use App\Models\User;
use App\Services\VerrouSessionService;
use Illuminate\Support\Facades\Schema;
use Livewire\Livewire;

/**
 * Sprint VW (VW3) — la durée d'inactivité est un réglage PAR UTILISATEUR, tenu sur le serveur (il suit la personne
 * d'un navigateur à l'autre), avec les valeurs et le défaut du poste.
 */
class VerrouSessionReglageTest extends VerrouSessionBase
{
    public function test_les_durees_et_le_defaut_sont_ceux_du_poste(): void
    {
        $this->assertSame([0, 1, 5, 15, 30], VerrouSessionService::DUREES);
        $this->assertSame(5, VerrouSessionService::DUREE_PAR_DEFAUT);
        $this->assertSame(10, VerrouSessionService::ECHECS_MAX);
    }

    public function test_les_libelles_des_durees(): void
    {
        $this->assertSame('Jamais', VerrouSessionService::libelleDuree(0));
        $this->assertSame('1 minute', VerrouSessionService::libelleDuree(1));
        $this->assertSame('5 minutes', VerrouSessionService::libelleDuree(5));
        $this->assertSame('15 minutes', VerrouSessionService::libelleDuree(15));
        $this->assertSame('30 minutes', VerrouSessionService::libelleDuree(30));
    }

    public function test_la_colonne_existe_avec_le_defaut_de_5_minutes(): void
    {
        $this->assertTrue(Schema::hasColumn('users', 'verrouillage_minutes'));
        $this->assertSame(5, $this->utilisateur()->fresh()->verrouillage_minutes);
    }

    public function test_une_valeur_inconnue_en_base_retombe_sur_le_defaut(): void
    {
        $u = $this->utilisateur();
        $u->forceFill(['verrouillage_minutes' => 7])->save();

        $this->assertSame(5, $u->fresh()->delaiVerrouillage());

        $u->forceFill(['verrouillage_minutes' => 0])->save();
        $this->assertSame(0, $u->fresh()->delaiVerrouillage(), '0 = Jamais est une valeur valide');
    }

    public function test_mon_profil_affiche_le_reglage_de_l_utilisateur(): void
    {
        $u = $this->utilisateur();
        $u->forceFill(['verrouillage_minutes' => 15])->save();

        Livewire::actingAs($u)->test(MonProfil::class)
            ->assertSet('verrouillage_minutes', 15)
            ->assertSee('Verrouillage automatique')
            ->assertSee('Jamais')
            ->assertSee('1 minute')
            ->assertSee('30 minutes');
    }

    public function test_le_choix_est_enregistre_pour_cet_utilisateur_seulement(): void
    {
        $u = $this->utilisateur();
        $autre = User::create([
            'name' => 'Caissière POS', 'username' => 'caisse', 'email' => 'caisse@fermeolouwachegoun.com',
            'password' => 'AgriERP@2026', 'is_active' => true,
        ]);

        Livewire::actingAs($u)->test(MonProfil::class)
            ->set('verrouillage_minutes', 30)
            ->assertHasNoErrors()
            ->assertDispatched('verrou-delai-modifie', minutes: 30);

        $this->assertSame(30, $u->fresh()->verrouillage_minutes);
        $this->assertSame(5, $autre->fresh()->verrouillage_minutes);
    }

    public function test_jamais_est_un_choix_valide(): void
    {
        $u = $this->utilisateur();

        Livewire::actingAs($u)->test(MonProfil::class)->set('verrouillage_minutes', 0)->assertHasNoErrors();

        $this->assertSame(0, $u->fresh()->verrouillage_minutes);
    }

    public function test_une_valeur_hors_liste_est_refusee_et_non_enregistree(): void
    {
        $u = $this->utilisateur();

        Livewire::actingAs($u)->test(MonProfil::class)
            ->set('verrouillage_minutes', 7)
            ->assertHasErrors('verrouillage_minutes');

        $this->assertSame(5, $u->fresh()->verrouillage_minutes);
    }

    public function test_la_colonne_ne_descend_pas_au_poste(): void
    {
        // `/api/sync/pull` ne donne que `id, name, username, email, is_active` pour `users` : le réglage web reste web.
        $source = file_get_contents(base_path('app/Http/Controllers/Api/SyncController.php'));
        $this->assertStringNotContainsString('verrouillage_minutes', $source);
    }

    public function test_la_page_rend_la_duree_du_compte_au_gabarit(): void
    {
        $u = $this->utilisateur();
        $u->forceFill(['verrouillage_minutes' => 15])->save();

        $this->actingAs($u)->get('/mon-profil')->assertOk()->assertSee('data-verrou-minutes="15"', false);
    }
}
