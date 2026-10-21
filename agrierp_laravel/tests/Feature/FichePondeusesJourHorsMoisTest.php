<?php

namespace Tests\Feature;

use App\Livewire\Elevage\FichePondeuses;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket U11 — FICHE PONDEUSES : UN JOUR D'UN MOIS PASSÉ SE RECHARGE, IL NE S'ÉCRASE PLUS.
 *
 * 🔴 `loadDay()` lisait la fiche dans `monthlyEntries` (mois COURANT seulement) : choisir une date du mois précédent
 * vidait le formulaire alors que la fiche existait, et « Enregistrer ce Jour » la réécrivait avec des zéros. Le
 * poste, lui, recharge la fiche de n'importe quel jour : les deux surfaces font désormais de même.
 */
class FichePondeusesJourHorsMoisTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow('2026-10-14 12:00:00');
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $compte = User::create([
            'name' => 'Animalier', 'username' => 'animalier', 'email' => 'animalier@fermeolouwachegoun.com',
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

    public function test_une_fiche_du_mois_precedent_se_recharge_et_n_est_pas_ecrasee(): void
    {
        $poules = LivestockSpecies::create(['code' => 'aviculture', 'label' => 'Volailles', 'is_enabled' => true]);
        $bande = LivestockLot::create([
            'code' => 'PON-A', 'species_id' => $poules->id, 'stage' => 'ponte', 'initial_quantity' => 200,
            'current_quantity' => 198, 'created_date' => '2026-09-01', 'status' => 'actif', 'is_active' => true,
        ]);
        LivestockDailyEntry::create([
            'lot_id' => $bande->id, 'entry_date' => '2026-09-28', 'achat' => 3, 'ne' => 1, 'mort' => 0, 'vente' => 0,
            'effectif_final' => 204, 'ponte_total' => 150, 'ponte_casses' => 6,
        ]);

        $fiche = Livewire::test(FichePondeuses::class)->set('selectedDate', '2026-09-28');

        $fiche->assertSet('achat', 3)->assertSet('ne', 1)->assertSet('oeufsRecoltes', 150)->assertSet('oeufsCasses', 6);

        $fiche->call('saveDay')->assertHasNoErrors();
        $enregistree = LivestockDailyEntry::where('lot_id', $bande->id)->whereDate('entry_date', '2026-09-28')->first();
        $this->assertSame([3, 1, 150, 6], [
            (int) $enregistree->achat, (int) $enregistree->ne, (int) $enregistree->ponte_total, (int) $enregistree->ponte_casses,
        ]);
    }
}
