<?php

namespace Tests\Feature;

use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.61 (Sprint 14) — 85 % D'ÉCLOSION SANS UN SEUL ŒUF COUVÉ.
 *
 * ⚠️⚠️ LE DÉFAUT CORRIGÉ. La maquette distingue **deux replis** et un seul
 * avait été recopié : `computeTauxEclosionLive()` retombe sur **0.0 %** pour le
 * taux DU JOUR ; seul le KPI MENSUEL affiche « 85.0 », valeur de démonstration.
 *
 * Le taux du jour annonçait donc **85 %** tant qu'aucun œuf n'était mis en
 * incubation — un chiffre inventé, présenté comme calculé, sur l'indicateur qui
 * décide de la conduite du couvoir.
 */
class FicheReproducteursEclosionTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-elevage', 'manage-elevage'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('admin', 'web')->givePermissionTo(['view-elevage', 'manage-elevage']);

        $admin = User::create([
            'name' => 'Directeur', 'username' => 'admin',
            'email' => 'dg@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $admin->assignRole('admin');
        $this->actingAs($admin);

        $espece = LivestockSpecies::firstOrCreate(
            ['code' => 'aviculture'],
            ['label' => 'Aviculture', 'is_active' => true],
        );

        LivestockLot::create([
            'code' => 'AVI-REP-01',
            'species_id' => $espece->id,
            'stage' => 'reproduction',
            'initial_quantity' => 60,
            'current_quantity' => 60,
            'created_date' => now()->toDateString(),
            'status' => 'actif',
            'is_active' => true,
        ]);
    }

    /**
     * ⚠️ SANS ŒUF COUVÉ, LE TAUX EST 0, PAS 85. Un taux inventé se lit comme
     * un couvoir qui fonctionne.
     */
    public function test_without_incubated_eggs_the_rate_is_zero_not_eighty_five(): void
    {
        Livewire::test(\App\Livewire\Elevage\FicheReproducteurs::class)
            ->set('oeufsCouves', 0)
            ->set('poussinsNes', 0)
            ->assertSet('eclosionRateCalc', 0.0);
    }

    /** Le calcul réel : 34 poussins nés de 40 œufs couvés = 85 %. */
    public function test_the_rate_is_hatched_over_incubated(): void
    {
        Livewire::test(\App\Livewire\Elevage\FicheReproducteurs::class)
            ->set('oeufsCouves', 40)
            ->set('poussinsNes', 34)
            ->assertSet('eclosionRateCalc', 85.0);
    }

    /**
     * ⚠️ Une couvée entièrement perdue affiche bien 0 % — indiscernable, avant
     * ce ticket, du cas « rien n'a été couvé », qui affichait 85 %.
     */
    public function test_a_fully_lost_batch_shows_zero(): void
    {
        Livewire::test(\App\Livewire\Elevage\FicheReproducteurs::class)
            ->set('oeufsCouves', 40)
            ->set('poussinsNes', 0)
            ->assertSet('eclosionRateCalc', 0.0);
    }
}
