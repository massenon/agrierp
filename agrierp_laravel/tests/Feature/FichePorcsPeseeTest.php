<?php

namespace Tests\Feature;

use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.60 (Sprint 14) — ALLER-RETOUR DE LA PESÉE PORCINE.
 *
 * ⚠️⚠️ LE DÉFAUT CORRIGÉ. La fiche Porcs est la seule à peser en **Kg** ; la
 * colonne de stockage `weight_sample_avg_g` porte, elle, le poids **MOYEN par
 * sujet en grammes**. Le rechargement remettait cette moyenne — simplement
 * divisée par 1000 — dans le champ « Poids Général Pesé (Kg) », qui est un
 * TOTAL : 500 Kg pesés sur 100 porcs revenaient à **5 Kg**.
 *
 * Le défaut ne lève aucune erreur : il se voit seulement en rouvrant une fiche
 * déjà enregistrée, et fausse la pesée du jour suivant, que la maquette
 * pré-remplit depuis J-1.
 */
class FichePorcsPeseeTest extends TestCase
{
    use RefreshDatabase;

    private LivestockLot $bande;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-elevage', 'manage-elevage'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('admin', 'web')->givePermissionTo(['view-elevage', 'manage-elevage']);

        $admin = User::create([
            'name' => 'Directeur', 'username' => 'admin',
            'email' => 'dg@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $admin->assignRole('admin');
        $this->actingAs($admin);

        $espece = LivestockSpecies::firstOrCreate(
            ['code' => 'porciculture'],
            ['label' => 'Porciculture', 'is_active' => true],
        );

        $this->bande = LivestockLot::create([
            'code' => 'POR-2026-01',
            'species_id' => $espece->id,
            'stage' => 'engraissement',
            'initial_quantity' => 100,
            'current_quantity' => 100,
            'created_date' => now()->toDateString(),
            'status' => 'actif',
            'is_active' => true,
        ]);
    }

    /**
     * ⚠️ LE TOTAL PESÉ REVIENT COMME UN TOTAL. 500 Kg sur 100 porcs = 5 000 g
     * de moyenne ; rouvrir la fiche doit réafficher **500 Kg**, pas 5.
     */
    public function test_the_weighed_total_comes_back_as_a_total(): void
    {
        LivestockDailyEntry::create([
            'lot_id' => $this->bande->id,
            'entry_date' => now()->toDateString(),
            'effectif_final' => 100,
            // 500 Kg pesés sur 100 sujets → 5 000 g de moyenne.
            'weight_sample_avg_g' => 5000,
        ]);

        Livewire::test(\App\Livewire\Elevage\FichePorcs::class)
            ->call('loadDay', now()->toDateString())
            ->assertSet('peseeTotalKg', 500.0);
    }

    /**
     * L'aller-retour complet : ce qui est saisi doit être ce qui revient.
     * C'est la garantie qui manquait — la conversion existait dans les deux
     * sens, mais pas la même.
     */
    public function test_saving_then_reloading_preserves_the_weight(): void
    {
        Livewire::test(\App\Livewire\Elevage\FichePorcs::class)
            ->set('peseeTotalKg', 500.0)
            ->call('saveDay')
            ->call('loadDay', now()->toDateString())
            ->assertSet('peseeTotalKg', 500.0);
    }

    /**
     * ⚠️ Sans effectif, le total ne se reconstitue pas : `null` plutôt qu'une
     * division par zéro ou un zéro trompeur.
     */
    public function test_without_a_headcount_the_weight_stays_null(): void
    {
        LivestockDailyEntry::create([
            'lot_id' => $this->bande->id,
            'entry_date' => now()->toDateString(),
            'effectif_final' => 0,
            'weight_sample_avg_g' => 5000,
        ]);

        Livewire::test(\App\Livewire\Elevage\FichePorcs::class)
            ->call('loadDay', now()->toDateString())
            ->assertSet('peseeTotalKg', null);
    }
}
