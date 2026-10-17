<?php

namespace Tests\Feature;

use App\Livewire\Elevage\BilanTechnicoEconomique;
use App\Livewire\Elevage\DashboardElevage;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.48 — « Bilan Technico-Économique » devient « Rentabilité » sur l'onglet du Dashboard Élevage et
 * dans son titre (décision client du 17/10/2026). Écart assumé au prototype, porté à l'identique sur le poste.
 */
class LibelleRentabiliteTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $compte = User::create([
            'name' => 'Animalier', 'username' => 'animalier', 'email' => 'animalier@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $compte->assignRole('animalier');
        $this->actingAs($compte);
    }

    public function test_l_onglet_du_dashboard_elevage_s_appelle_rentabilite(): void
    {
        Livewire::test(DashboardElevage::class)
            ->assertSee('Rentabilité')
            ->assertDontSee('Bilan Technico-Économique');
    }

    public function test_le_titre_de_l_onglet_s_appelle_rentabilite(): void
    {
        Livewire::test(BilanTechnicoEconomique::class)
            ->assertSee('Rentabilité de Lot')
            ->assertDontSee('Bilan Technico-Économique');
    }
}
