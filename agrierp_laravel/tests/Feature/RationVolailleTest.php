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
 * Ticket 15.57 — RATIONNEMENT ET PESÉE DES FICHES AVICOLES : sections du poste désormais présentes au web, même règle
 * (`RationVolaille`). Barème de l'aviculture semé : Pondeuse 110 g, Poulette 80 g, Poussins 30 et 60 g ; aucune ligne
 * « reproducteur ». Chiffres calculés à la main sur une bande de 60.
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
            'name' => 'Animalier', 'username' => 'elevage', 'email' => 'elevage@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
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

    public function test_pondeuses_l_effectif_va_a_la_ligne_pondeuse_seulement(): void
    {
        $this->bande('ponte');

        $tableau = Livewire::test(FichePondeuses::class)
            ->assertSee('Rationnement &amp; Provende Servie par Stade (en Grammes g/j)', false)
            ->assertSee('6600 g (6.6 Kg)')
            ->instance()->rationnement;

        $parLigne = collect($tableau['lignes'])->pluck('effectif', 'libelle')->all();
        $this->assertSame(60, $parLigne['Pondeuse (6 à 18 mois)']);
        $this->assertSame(0, $parLigne['Poulette (4 à 5.5 mois)']);
        $this->assertSame(60 * 110.0, $tableau['total_g']);
    }

    public function test_reproducteurs_sans_ligne_du_bareme_affichent_un_tiret_jamais_0_g(): void
    {
        $this->bande('reproduction');

        $tableau = Livewire::test(FicheReproducteurs::class)
            ->assertSee('Aucune ligne du barème ne correspond des reproducteurs')
            ->instance()->rationnement;

        $this->assertFalse($tableau['rattachee']);
        $this->assertNull($tableau['total_g']);
        $this->assertSame([null], array_values(array_unique(array_column($tableau['lignes'], 'effectif'))));
    }

    public function test_reproducteurs_avec_une_ligne_reproducteur_au_bareme(): void
    {
        $this->bande('reproduction');
        DB::table('feed_ration_standards')->insert([
            'id' => (string) Str::uuid(), 'species_code' => 'aviculture', 'stage_label' => 'Reproducteur', 'ration_g_per_day' => 150,
        ]);

        $tableau = Livewire::test(FicheReproducteurs::class)->instance()->rationnement;

        $this->assertSame(60 * 150.0, $tableau['total_g']);
        $this->assertSame(9.0, $tableau['total_kg']);
    }

    public function test_pondeuses_la_pesee_enregistre_la_moyenne_par_sujet(): void
    {
        $lot = $this->bande('ponte');

        Livewire::test(FichePondeuses::class)->set('peseeTotal', 1800)->assertSee('30 g')->call('saveDay');

        // 1 800 g ÷ 60 sujets = 30 g.
        $this->assertSame(30, (int) LivestockDailyEntry::where('lot_id', $lot->id)->sole()->weight_sample_avg_g);
        Livewire::test(FichePondeuses::class)->call('loadDay', now()->toDateString())->assertSet('peseeTotal', 1800);
    }
}
