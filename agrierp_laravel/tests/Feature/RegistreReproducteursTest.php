<?php

namespace Tests\Feature;

use App\Livewire\Elevage\RegistreReproducteurs;
use App\Models\Animal;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.17 (Sprint 14) — Registre des Reproducteurs.
 *
 * La règle la plus lourde de conséquences est verrouillée en premier :
 * enregistrer un reproducteur ne doit JAMAIS incrémenter l'effectif de la
 * bande. Un double comptage entre suivi par bande et suivi individuel serait
 * silencieux et fausserait tous les effectifs.
 */
class RegistreReproducteursTest extends TestCase
{
    use RefreshDatabase;

    private LivestockSpecies $species;

    private LivestockLot $lot;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-elevage', 'manage-elevage'] as $name) {
            Permission::findOrCreate($name, 'web');
        }
        $role = Role::findOrCreate('animalier', 'web');
        $role->givePermissionTo(['view-elevage', 'manage-elevage']);

        $user = User::create([
            'name' => 'Animalier Test',
            'email' => 'elevage.test@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'),
        ]);
        $user->assignRole($role);
        $this->actingAs($user);

        $this->species = LivestockSpecies::create(['code' => 'cuniculture', 'label' => 'Lapins', 'is_enabled' => true]);

        $this->lot = LivestockLot::create([
            'code' => 'LOT-CUNI-2026-011',
            'species_id' => $this->species->id,
            'stage' => 'reproduction',
            'initial_quantity' => 20,
            'current_quantity' => 20,
            'created_date' => '2026-02-01',
            'status' => 'actif',
            'is_active' => true,
        ]);
    }

    private function formulaire(): array
    {
        return [
            'identifier' => 'LAP-2026-0143',
            'species_id' => $this->species->id,
            'lot_id' => $this->lot->id,
            'sex' => 'F',
            'breed' => 'Néo-Zélandais Blanc',
            'birth_date' => '2026-02-12',
            'entry_date' => '2026-02-15',
            'origin' => 'Naissance interne',
            'cage' => 'C5',
        ];
    }

    /**
     * LA RÈGLE CRITIQUE : identifier un sujet n'est pas le faire entrer.
     * L'effectif de la bande ne doit pas bouger d'une unité.
     */
    public function test_registering_a_breeder_never_increases_the_batch_headcount(): void
    {
        $avant = $this->lot->current_quantity;

        $component = Livewire::test(RegistreReproducteurs::class);
        foreach ($this->formulaire() as $champ => $valeur) {
            $component->set($champ, $valeur);
        }
        $component->call('saveAnimal')->assertHasNoErrors();

        $this->assertEquals(1, Animal::count());
        $this->assertEquals(
            $avant,
            $this->lot->fresh()->current_quantity,
            "Identifier un sujet deja compte ne doit jamais gonfler l'effectif de la bande."
        );
    }

    /** L'identifiant est la clé de rattachement des événements : jamais de doublon. */
    public function test_the_identifier_must_be_unique(): void
    {
        Animal::create([
            'identifier' => 'LAP-2026-0143',
            'species_id' => $this->species->id,
            'category' => 'reproducteur',
            'sex' => 'F',
            'entry_date' => '2026-02-15',
        ]);

        $component = Livewire::test(RegistreReproducteurs::class);
        foreach ($this->formulaire() as $champ => $valeur) {
            $component->set($champ, $valeur);
        }
        $component->call('saveAnimal')->assertHasErrors('identifier');

        $this->assertEquals(1, Animal::count());
    }

    /** Une naissance postérieure à l'entrée est incohérente et doit être refusée. */
    public function test_a_birth_date_after_the_entry_date_is_rejected(): void
    {
        $component = Livewire::test(RegistreReproducteurs::class);
        foreach ($this->formulaire() as $champ => $valeur) {
            $component->set($champ, $valeur);
        }

        $component->set('birth_date', '2026-03-01')     // après l'entrée du 15/02
            ->call('saveAnimal')
            ->assertHasErrors('birth_date');

        $this->assertEquals(0, Animal::count());
    }

    /** Sortie : archivage LOGIQUE, la fiche et l'historique restent consultables. */
    public function test_an_exit_is_a_logical_archive_not_a_deletion(): void
    {
        $animal = Animal::create([
            'identifier' => 'LAP-2026-0143',
            'species_id' => $this->species->id,
            'lot_id' => $this->lot->id,
            'category' => 'reproducteur',
            'sex' => 'F',
            'entry_date' => '2026-02-15',
        ]);

        $effectifAvant = $this->lot->current_quantity;

        Livewire::test(RegistreReproducteurs::class)
            ->call('openExit', $animal->id)
            ->set('exitStatus', 'reforme')
            ->set('exit_date', '2026-08-01')
            ->set('exit_reason', 'Réforme pour âge')
            ->call('confirmExit')
            ->assertHasNoErrors();

        $animal->refresh();

        $this->assertEquals('reforme', $animal->status);
        $this->assertEquals('Réforme pour âge', $animal->exit_reason);
        $this->assertFalse($animal->isPresent());
        // Le sujet existe toujours — jamais de suppression physique.
        $this->assertEquals(1, Animal::count());
        // Et l'effectif de la bande reste celui de la fiche journalière.
        $this->assertEquals($effectifAvant, $this->lot->fresh()->current_quantity);
    }

    public function test_an_exit_cannot_predate_the_entry(): void
    {
        $animal = Animal::create([
            'identifier' => 'LAP-2026-0143',
            'species_id' => $this->species->id,
            'category' => 'reproducteur',
            'sex' => 'F',
            'entry_date' => '2026-02-15',
        ]);

        Livewire::test(RegistreReproducteurs::class)
            ->call('openExit', $animal->id)
            ->set('exit_date', '2026-01-01')
            ->call('confirmExit')
            ->assertHasErrors('exit_date');

        $this->assertEquals('actif', $animal->fresh()->status);
    }

    public function test_the_list_filters_by_search_species_and_status(): void
    {
        Animal::create(['identifier' => 'LAP-A', 'species_id' => $this->species->id, 'category' => 'reproducteur', 'sex' => 'F', 'breed' => 'Néo-Zélandais', 'entry_date' => '2026-02-15']);
        Animal::create(['identifier' => 'LAP-B', 'species_id' => $this->species->id, 'category' => 'reproducteur', 'sex' => 'M', 'breed' => 'Californien', 'entry_date' => '2026-02-15', 'status' => 'reforme']);

        $component = Livewire::test(RegistreReproducteurs::class);

        $this->assertCount(2, $component->instance()->animals);

        $component->set('search', 'Californien');
        $this->assertCount(1, $component->instance()->animals);

        $component->set('search', '')->set('statusFilter', 'actif');
        $this->assertCount(1, $component->instance()->animals);
        $this->assertEquals('LAP-A', $component->instance()->animals->first()->identifier);
    }

    /** Un rôle en lecture seule ne peut pas enregistrer de sujet. */
    public function test_a_read_only_role_cannot_register(): void
    {
        $role = Role::findOrCreate('lecture', 'web');
        $role->givePermissionTo(['view-elevage']);      // sans manage-elevage

        $user = User::create([
            'name' => 'Lecture',
            'email' => 'lecture@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'),
        ]);
        $user->assignRole($role);
        $this->actingAs($user);

        Livewire::test(RegistreReproducteurs::class)
            ->call('newAnimal')
            ->assertForbidden();
    }
}
