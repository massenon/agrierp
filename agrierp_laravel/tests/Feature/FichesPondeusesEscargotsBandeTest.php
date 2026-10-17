<?php

namespace Tests\Feature;

use App\Livewire\Elevage\FicheEscargots;
use App\Livewire\Elevage\FichePondeuses;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\ModuleConfig;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.47 (A11) — FICHES PONDEUSES ET ESCARGOTS À PLUSIEURS BANDES.
 *
 * 🔴 Avant : `saveDay()` écrivait toujours sur la PREMIÈRE bande (ordre des UUID), la veille était celle de
 * toutes les bandes réunies, le tableau mensuel écrasait deux fiches du même jour, et ré-enregistrer un jour
 * remettait ses morts à zéro (leur répartition par catégorie n'est pas stockée).
 */
class FichesPondeusesEscargotsBandeTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow('2026-10-14 12:00:00');
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $compte = User::create([
            'name' => 'Animalier', 'username' => 'animalier', 'email' => 'animalier@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $compte->assignRole('animalier');
        $this->actingAs($compte);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function bande(LivestockSpecies $espece, string $code, int $effectif, string $stade): LivestockLot
    {
        return LivestockLot::create([
            'code' => $code, 'species_id' => $espece->id, 'stage' => $stade,
            'initial_quantity' => $effectif, 'current_quantity' => $effectif,
            'created_date' => '2026-09-01', 'status' => 'actif', 'is_active' => true,
        ]);
    }

    public function test_pondeuses_l_enregistrement_porte_sur_la_bande_choisie_et_sa_propre_veille(): void
    {
        $poules = LivestockSpecies::create(['code' => 'aviculture', 'label' => 'Volailles', 'is_enabled' => true]);
        $b = $this->bande($poules, 'PON-B', 50, 'ponte');
        $a = $this->bande($poules, 'PON-A', 200, 'ponte');

        Livewire::test(FichePondeuses::class)
            ->assertSet('bandeId', null)
            ->set('bandeId', $b->id)
            ->set('selectedDate', '2026-10-14')
            ->set('mortPoulette', 2)
            ->call('saveDay')
            ->assertHasNoErrors();

        // Veille de PON-B seule : 50 − 2 = 48 (et non 250 − 2 = 248, veille de toutes les bandes).
        $fiche = LivestockDailyEntry::where('lot_id', $b->id)->first();
        $this->assertNotNull($fiche);
        $this->assertSame(48, (int) $fiche->effectif_final);
        $this->assertSame(0, LivestockDailyEntry::where('lot_id', $a->id)->count());
        $this->assertSame(200, (int) $a->fresh()->current_quantity);
    }

    public function test_pondeuses_la_bande_par_defaut_est_la_premiere_par_code(): void
    {
        $poules = LivestockSpecies::create(['code' => 'aviculture', 'label' => 'Volailles', 'is_enabled' => true]);
        $this->bande($poules, 'PON-B', 50, 'ponte');
        $a = $this->bande($poules, 'PON-A', 200, 'ponte');

        $this->assertSame($a->id, Livewire::test(FichePondeuses::class)->instance()->bande->id);
    }

    public function test_pondeuses_reenregistrer_un_jour_garde_ses_morts(): void
    {
        $poules = LivestockSpecies::create(['code' => 'aviculture', 'label' => 'Volailles', 'is_enabled' => true]);
        $a = $this->bande($poules, 'PON-A', 200, 'ponte');
        LivestockDailyEntry::create([
            'lot_id' => $a->id, 'entry_date' => '2026-10-14',
            'achat' => 0, 'ne' => 0, 'mort' => 3, 'vente' => 0, 'don' => 0, 'effectif_final' => 197, 'ponte_total' => 150,
        ]);

        Livewire::test(FichePondeuses::class)
            ->assertSet('mortEnregistre', 3)
            ->assertSee('3 mort(s) déjà enregistré(s) ce jour')
            ->set('oeufsRecoltes', 160)
            ->call('saveDay');

        $fiche = LivestockDailyEntry::where('lot_id', $a->id)->first();
        $this->assertSame([3, 197, 160], [(int) $fiche->mort, (int) $fiche->effectif_final, (int) $fiche->ponte_total]);
    }

    public function test_escargots_l_enregistrement_porte_sur_la_bande_choisie_et_garde_ses_morts(): void
    {
        $escargots = LivestockSpecies::create(['code' => 'helico', 'label' => 'Escargots', 'is_enabled' => true]);
        ModuleConfig::create(['species_code' => 'helico', 'is_enabled' => true]);
        $a = $this->bande($escargots, 'ESC-A', 1000, 'engraissement');
        $b = $this->bande($escargots, 'ESC-B', 400, 'engraissement');
        LivestockDailyEntry::create([
            'lot_id' => $b->id, 'entry_date' => '2026-10-14',
            'achat' => 0, 'ne' => 0, 'mort' => 5, 'vente' => 0, 'don' => 0, 'effectif_final' => 395,
        ]);

        Livewire::test(FicheEscargots::class)
            ->set('bandeId', $b->id)
            ->assertSet('mortEnregistre', 5)
            ->set('naissainsNes', 10)
            ->call('saveDay')
            ->assertHasNoErrors();

        // ESC-B : 400 + 10 − 5 = 405 ; ESC-A intacte.
        $this->assertSame(405, (int) LivestockDailyEntry::where('lot_id', $b->id)->value('effectif_final'));
        $this->assertSame(0, LivestockDailyEntry::where('lot_id', $a->id)->count());
    }
}
