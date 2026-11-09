<?php

namespace Tests\Feature;

use App\Livewire\Elevage\FichePondeuses;
use App\Livewire\Elevage\FicheReproducteurs;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.57 → VOL-1 → VOL-2 — RATIONNEMENT ET PESÉE DES FICHES AVICOLES. Depuis VOL-2, les deux fiches calculent leur
 * rationnement PAR CATÉGORIE (Reproducteurs : Reproducteur / Jeune / Poussin) ou PAR STADE (Pondeuses : les quatre libellés du
 * barème) : effectif CALCULÉ × ration de la ligne (`CategorieVolaille::tableauReproducteurs`, `StadePondeuse::tableau`).
 * `App\Support\RationVolaille` (une seule ligne par sous-chaîne « pondeuse ») et le composant `x-ration-volaille` n'existent plus.
 * Barème de l'aviculture semé : Pondeuse 110 g, Poulette 80 g, Poussin en croissance 60 g, Poussin ponte 30 g. Chiffres calculés à
 * la main sur une bande de 60.
 */
class RationVolailleTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $this->seed(\Database\Seeders\FeedRationStandardsSeeder::class);
        $u = User::create([
            'name' => 'Animalier', 'username' => 'elevage', 'email' => 'elevage@fermeolouwachegoun.com',
            'password' => bcrypt('LogiAgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole('animalier');
        $this->actingAs($u);
    }

    private function bande(string $stade): LivestockLot
    {
        $esp = LivestockSpecies::firstOrCreate(['code' => 'aviculture'], ['label' => 'Aviculture', 'is_enabled' => true]);

        return LivestockLot::create([
            'code' => 'AVI-'.$stade, 'species_id' => $esp->id, 'stage' => $stade, 'initial_quantity' => 60,
            'current_quantity' => 60, 'created_date' => now()->subDays(5)->toDateString(), 'status' => 'actif', 'is_active' => true,
        ]);
    }

    /** Départ 10 / 10 / 10 / 30 sur 60 (Poussin ponte / Poussin en croissance / Poulette / Pondeuse). */
    public function test_pondeuses_rationnement_par_stade_calcule_a_la_main(): void
    {
        $this->bande('ponte');

        $tableau = Livewire::test(FichePondeuses::class)
            ->set('departPoussinPonte', 10)->set('departPoussinCroissance', 10)->set('departPoulette', 10)->set('departPondeuse', 30)
            ->assertSee('Rationnement &amp; Provende Servie par Stade (en Grammes g/j)', false)
            ->assertSee('5000 g (5 Kg)')
            ->instance()->rationnement;

        // 10 × 30 + 10 × 60 + 10 × 80 + 30 × 110 = 300 + 600 + 800 + 3 300 = 5 000 g.
        $this->assertSame([10, 10, 10, 30], array_column($tableau['lignes'], 'effectif'));
        $this->assertSame([300, 600, 800, 3300], array_column($tableau['lignes'], 'total_g'));
        $this->assertSame(5000, $tableau['total_g']);
        $this->assertSame(5.0, $tableau['total_kg']);
    }

    /**
     * Les lignes du barème des reproducteurs (Reproducteur 130, Jeune 80, Poussin 30 g/j : valeurs PROVISOIRES) ne figurent
     * jamais au tableau de la fiche Pondeuses, et réciproquement : les quatre libellés du barème, dans l'ordre de la chaîne.
     */
    public function test_pondeuses_ne_voient_pas_les_lignes_des_reproducteurs_et_inversement(): void
    {
        $this->bande('ponte');

        $libelles = collect(Livewire::test(FichePondeuses::class)->instance()->rationnement['lignes'])->pluck('libelle')->all();

        $this->assertSame(['Poussin ponte (0 à 2 mois)', 'Poussin en croissance (2 à 4 mois)', 'Poulette (4 à 5.5 mois)', 'Pondeuse (6 à 18 mois)'], $libelles);

        $repro = Livewire::test(FicheReproducteurs::class);
        $this->assertSame(['Reproducteur', 'Jeune', 'Poussin'], array_column($repro->instance()->rationnement['lignes'], 'libelle'));
    }

    public function test_pondeuses_sans_depart_aucun_total_jamais_0_g(): void
    {
        $this->bande('ponte');

        $tableau = Livewire::test(FichePondeuses::class)->instance()->rationnement;

        $this->assertNull($tableau['total_g']);
        $this->assertSame([null], array_values(array_unique(array_column($tableau['lignes'], 'effectif'))));
    }

    public function test_l_ancienne_regle_rationvolaille_n_existe_plus(): void
    {
        $this->assertFalse(class_exists(\App\Support\RationVolaille::class), 'plus aucun appel : la classe est retirée');
        $this->assertFileDoesNotExist(resource_path('views/components/ration-volaille.blade.php'));
    }

    /** VOL-1 — reproducteurs : effectif calculé de chaque catégorie × sa ration. Départ 30 / 20 / 10 sur 60. */
    public function test_reproducteurs_rationnement_par_categorie_calcule_a_la_main(): void
    {
        $this->bande('reproduction');

        $tableau = Livewire::test(FicheReproducteurs::class)
            ->set('departRepro', 30)->set('departJeune', 20)->set('departSevre', 10)
            ->assertSee('Rationnement &amp; Provende Servie par Catégorie (en Grammes g/j)', false)
            ->instance()->rationnement;

        // 30 × 130 + 20 × 80 + 10 × 30 = 3 900 + 1 600 + 300 = 5 800 g.
        $this->assertSame(['Reproducteur', 'Jeune', 'Poussin'], array_column($tableau['lignes'], 'libelle'));
        $this->assertSame([30, 20, 10], array_column($tableau['lignes'], 'effectif'));
        $this->assertSame([3900, 1600, 300], array_column($tableau['lignes'], 'total_g'));
        $this->assertSame(5800, $tableau['total_g']);
        $this->assertSame(5.8, $tableau['total_kg']);
    }

    public function test_reproducteurs_sans_depart_aucun_total_jamais_0_g(): void
    {
        $this->bande('reproduction');

        $tableau = Livewire::test(FicheReproducteurs::class)->instance()->rationnement;

        $this->assertNull($tableau['total_g']);
        $this->assertSame([null], array_values(array_unique(array_column($tableau['lignes'], 'effectif'))));
    }

    public function test_pondeuses_la_pesee_enregistre_la_moyenne_par_sujet(): void
    {
        $lot = $this->bande('ponte');

        $depart = fn ($c) => $c->set('departPondeuse', 60)->set('departPoulette', 0)->set('departPoussinCroissance', 0)->set('departPoussinPonte', 0);   // VOL-2
        $depart(Livewire::test(FichePondeuses::class))->set('peseeTotal', 1800)->assertSee('30 g')->call('saveDay');

        // 1 800 g ÷ 60 sujets = 30 g.
        $this->assertSame(30, (int) LivestockDailyEntry::where('lot_id', $lot->id)->sole()->weight_sample_avg_g);
        Livewire::test(FichePondeuses::class)->call('loadDay', now()->toDateString())->assertSet('peseeTotal', 1800);
    }
}
