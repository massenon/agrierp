<?php

namespace Tests\Feature;

use App\Actions\SaisieBandeAction;
use App\Livewire\Elevage\GestionBandes;
use App\Models\AuditLog;
use App\Models\LivestockLot;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket BS1 (web d'abord, article 5) — « Bandes & Sujets » : créer, modifier, archiver une bande, par UN point de
 * passage (`SaisieBandeAction`) que partagent l'écran web et l'envoi du poste.
 *
 * Valeurs attendues écrites à la main. Décor : `PreparationExercices` (exercices 2025 clos et 2026 ouvert, bande de
 * pondeuses PON-2026-01 de 200 têtes, espèce « aviculture »).
 */
class BandesSaisieWebTest extends TestCase
{
    use PreparationExercices;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        $this->preparerDecor('2026-10-21 09:00:00');
        $this->exercice(2025, 'cloture');
        $this->exercice(2026);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function especeId(): string
    {
        return $this->pondeuses->species_id;
    }

    public function test_creer_une_bande_pose_l_effectif_initial_et_courant_actif_et_trace_l_audit(): void
    {
        Livewire::test(GestionBandes::class)
            ->set('species_id', $this->especeId())
            ->set('code', 'LOT-VOL-9')
            ->set('stage', 'croissance')
            ->set('created_date', '2026-10-20')
            ->set('quantity', 40)
            ->set('acquisition_cost', 135000)
            ->call('saveLot')
            ->assertHasNoErrors()
            ->assertDispatched('toast', message: 'Bande créée avec succès.', type: 'success');

        $lot = LivestockLot::where('code', 'LOT-VOL-9')->firstOrFail();
        $this->assertSame([40, 40, 'actif', true, 'croissance'], [
            (int) $lot->initial_quantity, (int) $lot->current_quantity, $lot->status, (bool) $lot->is_active, $lot->stage,
        ]);
        $this->assertSame(1, AuditLog::where('action', 'livestock_lot.created')->count());
    }

    public function test_une_bande_datee_dans_un_exercice_clos_est_refusee_sous_la_date_et_rien_n_est_ecrit(): void
    {
        $composant = Livewire::test(GestionBandes::class)
            ->set('species_id', $this->especeId())
            ->set('code', 'LOT-VOL-8')
            ->set('stage', 'croissance')
            ->set('created_date', '2025-12-20')
            ->set('quantity', 10)
            ->call('saveLot');

        $this->assertErreurSousLeChamp($composant, 'created_date', "L'exercice 2025 est clôturé : aucune saisie ne peut être datée du 20/12/2025.");
        $this->assertSame(0, LivestockLot::where('code', 'LOT-VOL-8')->count());
        $this->assertSame(0, AuditLog::where('action', 'livestock_lot.created')->count());
    }

    public function test_le_blade_affiche_l_erreur_de_la_date_de_creation(): void
    {
        $html = Livewire::test(GestionBandes::class)
            ->set('species_id', $this->especeId())
            ->set('code', 'LOT-VOL-7')
            ->set('created_date', '2025-12-20')
            ->set('quantity', 10)
            ->call('saveLot')
            ->html();

        $this->assertStringContainsString('aucune saisie ne peut être datée du 20/12/2025', $html);
    }

    public function test_modifier_une_bande_change_le_stade_l_effectif_et_le_statut(): void
    {
        Livewire::test(GestionBandes::class)
            ->call('editLot', $this->pondeuses->id)
            ->set('stage', 'engraissement')
            ->set('quantity', 180)
            ->set('status', 'cloture')
            ->call('updateLot')
            ->assertHasNoErrors()
            ->assertDispatched('toast', message: 'Bande modifiée avec succès.', type: 'success');

        $lot = $this->pondeuses->fresh();
        $this->assertSame(['engraissement', 180, 'cloture'], [$lot->stage, (int) $lot->current_quantity, $lot->status]);
        $this->assertSame(200, (int) $lot->initial_quantity, "l'effectif initial ne change jamais");
        $this->assertSame('PON-2026-01', $lot->code, 'le code est immuable');
        $this->assertSame(1, AuditLog::where('action', 'livestock_lot.updated')->count());
    }

    public function test_archiver_une_bande_est_logique_avec_confirmation_et_un_second_archivage_ne_fait_rien(): void
    {
        $composant = Livewire::test(GestionBandes::class);
        $this->assertStringContainsString('archive-bande-'.$this->pondeuses->id, $composant->html(), 'confirmation x-modal-confirm-delete');

        $composant->call('archiveLot', $this->pondeuses->id)
            ->assertDispatched('toast', message: 'Bande archivée avec succès.', type: 'warning');

        $lot = $this->pondeuses->fresh();
        $this->assertFalse((bool) $lot->is_active);
        $this->assertSame('actif', $lot->status, "l'archivage ne touche pas le statut");
        $this->assertSame(200, (int) $lot->current_quantity, 'la ligne est gardée, jamais supprimée');

        $composant->call('archiveLot', $this->pondeuses->id);
        $this->assertSame(1, AuditLog::where('action', 'livestock_lot.archived')->count(), 'second archivage : aucune seconde trace');
    }

    public function test_une_bande_archivee_n_est_plus_listee_ni_comptee(): void
    {
        $this->pondeuses->update(['is_active' => false]);

        $composant = Livewire::test(GestionBandes::class);

        $this->assertStringNotContainsString('PON-2026-01', $composant->html());
        $this->assertSame(0, $composant->instance()->kpis['bandes_actives']);
    }

    public function test_sans_manage_elevage_aucune_action_n_est_permise(): void
    {
        $caissier = User::create([
            'name' => 'Caisse', 'username' => 'caisse-bs', 'email' => 'caisse-bs@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $caissier->assignRole('caissier');
        $this->actingAs($caissier);

        foreach (['newLot', 'saveLot', 'updateLot'] as $methode) {
            Livewire::test(GestionBandes::class)->call($methode)->assertForbidden();
        }
        Livewire::test(GestionBandes::class)->call('editLot', $this->pondeuses->id)->assertForbidden();
        Livewire::test(GestionBandes::class)->call('archiveLot', $this->pondeuses->id)->assertForbidden();

        $this->assertTrue((bool) $this->pondeuses->fresh()->is_active);
    }

    public function test_la_mortalite_d_une_bande_sans_effectif_initial_est_inconnue_jamais_zero(): void
    {
        LivestockLot::create([
            'code' => 'LOT-ZERO', 'species_id' => $this->especeId(), 'stage' => 'ponte', 'initial_quantity' => 0, 'current_quantity' => 0,
            'created_date' => '2026-10-01', 'status' => 'actif', 'is_active' => true,
        ]);
        $this->pondeuses->update(['initial_quantity' => 8, 'current_quantity' => 7]);

        $html = Livewire::test(GestionBandes::class)->html();

        $this->assertStringContainsString('12.5%', $html, '(8 − 7) / 8 = 12,5 %');
        $this->assertSame(1, preg_match('/LOT-ZERO.*?data-label="Mortalité"[^>]*>\s*—\s*</s', $html), 'effectif initial 0 : « — »');
    }

    public function test_enregistrer_des_sujets_est_atteignable_depuis_bandes_et_sujets(): void
    {
        $html = Livewire::test(GestionBandes::class)->html();

        $this->assertStringContainsString(route('elevage.enregistrer-sujets'), $html);
        $this->assertStringContainsString('Enregistrer des Sujets', $html);
    }

    public function test_le_point_de_passage_unique_existe_et_porte_les_trois_gestes(): void
    {
        $action = app(SaisieBandeAction::class);

        $lot = $action->creer([
            'code' => 'LOT-VOL-5', 'species_id' => $this->especeId(), 'stage' => 'ponte',
            'created_date' => '2026-10-01', 'quantity' => 12, 'acquisition_cost' => null, 'product_id' => null,
        ]);
        $this->assertSame([12, 12, 'actif'], [(int) $lot->initial_quantity, (int) $lot->current_quantity, $lot->status]);

        $action->modifier($lot->id, ['stage' => 'ponte', 'status' => 'cloture', 'current_quantity' => 11]);
        $this->assertSame([11, 'cloture'], [(int) $lot->fresh()->current_quantity, $lot->fresh()->status]);

        $action->archiver($lot->id);
        $this->assertFalse((bool) $lot->fresh()->is_active);
    }
}
