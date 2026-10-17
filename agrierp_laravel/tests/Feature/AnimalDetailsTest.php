<?php

namespace Tests\Feature;

use App\Livewire\Elevage\AnimalDetails;
use App\Models\Animal;
use App\Models\LivestockLot;
use App\Models\LivestockReproductionEvent;
use App\Models\LivestockSpecies;
use App\Models\VeterinaryRecord;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.16 (Sprint 14) — Fiche Sujet (suivi individuel des reproducteurs).
 *
 * Deux points sont verrouillés ici :
 *  1. le rattachement des événements de reproduction se fait sur les
 *     références DÉJÀ saisies (`mother_ref`/`sire_ref`), sans migration ni
 *     perte des événements antérieurs ;
 *  2. les onglets sans source réelle affichent un motif explicite, jamais un
 *     contenu plausible inventé.
 */
class AnimalDetailsTest extends TestCase
{
    use RefreshDatabase;

    private Animal $sujet;

    private LivestockLot $lot;

    protected function setUp(): void
    {
        parent::setUp();

        $species = LivestockSpecies::create(['code' => 'cuniculture', 'label' => 'Lapins', 'is_enabled' => true]);

        $this->lot = LivestockLot::create([
            'code' => 'LOT-CUNI-2026-011',
            'species_id' => $species->id,
            'stage' => 'reproduction',
            'initial_quantity' => 20,
            'current_quantity' => 20,
            'created_date' => '2026-02-01',
            'status' => 'actif',
            'is_active' => true,
        ]);

        $this->sujet = Animal::create([
            'identifier' => 'LAP-2026-0143',
            'species_id' => $species->id,
            'lot_id' => $this->lot->id,
            'category' => 'reproducteur',
            'sex' => 'F',
            'breed' => 'Néo-Zélandais Blanc',
            'birth_date' => '2026-02-12',
            'entry_date' => '2026-02-15',
            'origin' => 'Naissance interne (Lot LOT-CUNI-2026-002)',
            'cage' => 'C5',
            'status' => 'actif',
        ]);
    }

    public function test_the_general_tab_shows_the_real_identification(): void
    {
        Livewire::test(AnimalDetails::class, ['animal' => $this->sujet])
            ->assertOk()
            ->assertSee('LAP-2026-0143')
            ->assertSee('Néo-Zélandais Blanc')
            ->assertSee('Femelle')
            ->assertSee('C5')
            ->assertSee('LOT-CUNI-2026-011');
    }

    /**
     * LE POINT CLÉ DU RATTACHEMENT : les événements existants portent des
     * références en texte libre. Aucune migration ne les a touchés, et ils
     * doivent malgré tout ressortir sur la fiche du sujet.
     */
    public function test_reproduction_events_are_matched_on_existing_refs(): void
    {
        // Événement où le sujet est la MÈRE
        LivestockReproductionEvent::create([
            'lot_id' => $this->lot->id,
            'mother_ref' => 'LAP-2026-0143',
            'sire_ref' => 'LAP-2026-0090',
            'saillie_date' => '2026-06-01',
            'mise_bas_date_actual' => '2026-07-01',
            'nes_vivants' => 8,
            'nes_morts' => 1,
            'status' => 'termine',
        ]);

        // Événement où le sujet est le GÉNITEUR
        LivestockReproductionEvent::create([
            'lot_id' => $this->lot->id,
            'mother_ref' => 'LAP-2026-0200',
            'sire_ref' => 'LAP-2026-0143',
            'saillie_date' => '2026-05-01',
            'status' => 'en_cours',
        ]);

        // Événement d'un AUTRE sujet — ne doit pas apparaître
        LivestockReproductionEvent::create([
            'lot_id' => $this->lot->id,
            'mother_ref' => 'LAP-2026-0777',
            'sire_ref' => 'LAP-2026-0888',
            'saillie_date' => '2026-06-15',
            'status' => 'en_cours',
        ]);

        $component = Livewire::test(AnimalDetails::class, ['animal' => $this->sujet]);

        $this->assertCount(2, $component->instance()->reproductionEvents);

        $component->call('switchTab', 'reproduction')
            ->assertSee('Mère')
            ->assertSee('Géniteur')
            ->assertSee('8');
    }

    /**
     * Les soins sont administrés PAR BANDE : la fiche doit le dire
     * explicitement plutôt que de les présenter comme individuels.
     */
    public function test_care_is_shown_as_belonging_to_the_batch(): void
    {
        VeterinaryRecord::create([
            'lot_id' => $this->lot->id,
            'action_type' => 'Vaccination',
            'product_used' => 'Vaccin VHD',
            'dose' => '1 ml',
            'record_date' => '2026-06-10',
            'is_active' => true,
        ]);

        Livewire::test(AnimalDetails::class, ['animal' => $this->sujet])
            ->call('switchTab', 'vaccins')
            ->assertSee('Vaccin VHD')
            ->assertSee('par bande');
    }

    /**
     * LA RÈGLE À NE PAS ENFREINDRE : un onglet sans source réelle doit
     * expliquer POURQUOI il est vide, jamais afficher un contenu plausible.
     */
    public function test_tabs_without_a_real_source_state_the_reason(): void
    {
        $component = Livewire::test(AnimalDetails::class, ['animal' => $this->sujet]);

        $component->call('switchTab', 'alimentation')
            ->assertSee('Aucune donnée réelle pour cet onglet')
            ->assertSee('PAR BANDE');

        $component->call('switchTab', 'production')
            ->assertSee('Aucune donnée réelle pour cet onglet')
            ->assertSee('par bande dans la fiche journalière');

        $component->call('switchTab', 'documents')
            ->assertSee('Aucune donnée réelle pour cet onglet');
    }

    public function test_movements_only_list_what_was_really_recorded(): void
    {
        $component = Livewire::test(AnimalDetails::class, ['animal' => $this->sujet]);

        // Un sujet encore présent n'a qu'un mouvement : son entrée.
        $this->assertCount(1, $component->instance()->movements);

        $this->sujet->update([
            'status' => 'reforme',
            'exit_date' => '2026-08-01',
            'exit_reason' => 'Réforme pour âge',
        ]);

        $component = Livewire::test(AnimalDetails::class, ['animal' => $this->sujet->fresh()]);

        $this->assertCount(2, $component->instance()->movements);
        $component->call('switchTab', 'mouvements')->assertSee('Réforme pour âge');
    }

    public function test_the_history_merges_all_dated_events_most_recent_first(): void
    {
        LivestockReproductionEvent::create([
            'lot_id' => $this->lot->id,
            'mother_ref' => 'LAP-2026-0143',
            'saillie_date' => '2026-06-01',
            'status' => 'en_cours',
        ]);

        VeterinaryRecord::create([
            'lot_id' => $this->lot->id,
            'action_type' => 'Vaccination',
            'record_date' => '2026-07-10',
            'is_active' => true,
        ]);

        $history = Livewire::test(AnimalDetails::class, ['animal' => $this->sujet])
            ->instance()->history;

        $this->assertCount(3, $history);   // entrée + saillie + soin
        $this->assertEquals('2026-07-10', $history[0]['date'], 'Le plus récent doit venir en premier.');
        $this->assertEquals('2026-02-15', $history[2]['date']);
    }

    public function test_an_unknown_tab_falls_back_to_general(): void
    {
        Livewire::test(AnimalDetails::class, ['animal' => $this->sujet])
            ->call('switchTab', 'inexistant')
            ->assertSet('tab', 'general');
    }

    /** Le scope reproducteurs isole bien les sujets suivis individuellement. */
    public function test_the_breeders_scope_only_returns_individually_tracked_subjects(): void
    {
        Animal::create([
            'identifier' => 'LAP-2026-0500',
            'species_id' => $this->sujet->species_id,
            'category' => 'engraissement',      // hors périmètre du suivi individuel
            'sex' => 'M',
            'entry_date' => '2026-07-01',
        ]);

        $this->assertEquals(2, Animal::count());
        $this->assertEquals(1, Animal::breeders()->count());
        $this->assertEquals('LAP-2026-0143', Animal::breeders()->first()->identifier);
    }
}
