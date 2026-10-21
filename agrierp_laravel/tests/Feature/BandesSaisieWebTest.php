<?php

namespace Tests\Feature;

use App\Actions\SaisieBandeAction;
use App\Actions\TransferBetweenLotsAction;
use App\Livewire\Elevage\GestionBandes;
use App\Models\AuditLog;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Validation\ValidationException;
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

    public function test_archiver_une_bande_videe_est_logique_avec_confirmation_et_un_second_archivage_ne_fait_rien(): void
    {
        // BS-Q3 : seule une bande sans effectif vivant s'archive.
        $this->pondeuses->update(['current_quantity' => 0]);

        $composant = Livewire::test(GestionBandes::class);
        $this->assertStringContainsString('archive-bande-'.$this->pondeuses->id, $composant->html(), 'confirmation x-modal-confirm-delete');

        $composant->call('archiveLot', $this->pondeuses->id)
            ->assertDispatched('toast', message: 'Bande archivée avec succès.', type: 'warning');

        $lot = $this->pondeuses->fresh();
        $this->assertFalse((bool) $lot->is_active);
        $this->assertSame('actif', $lot->status, "l'archivage ne touche pas le statut");
        $this->assertSame(200, (int) $lot->initial_quantity, 'la ligne est gardée, jamais supprimée');

        $composant->call('archiveLot', $this->pondeuses->id);
        $this->assertSame(1, AuditLog::where('action', 'livestock_lot.archived')->count(), 'second archivage : aucune seconde trace');
    }

    public function test_archiver_une_bande_qui_a_un_effectif_vivant_est_refuse_avec_un_message_clair_et_rien_n_est_ecrit(): void
    {
        $message = 'Cette bande compte encore 200 sujets vivants : archivez-la après avoir sorti ou transféré les sujets restants.';

        Livewire::test(GestionBandes::class)
            ->call('archiveLot', $this->pondeuses->id)
            ->assertDispatched('toast', message: $message, type: 'error');

        $this->assertTrue((bool) $this->pondeuses->fresh()->is_active, 'la bande reste en cours');
        $this->assertSame(0, AuditLog::where('action', 'livestock_lot.archived')->count());

        // Un seul sujet : le singulier.
        $this->pondeuses->update(['current_quantity' => 1]);
        Livewire::test(GestionBandes::class)
            ->call('archiveLot', $this->pondeuses->id)
            ->assertDispatched('toast', message: 'Cette bande compte encore 1 sujet vivant : archivez-la après avoir sorti ou transféré les sujets restants.', type: 'error');
    }

    public function test_le_point_de_passage_refuse_l_archivage_d_une_bande_vivante_sous_le_champ_bande(): void
    {
        try {
            app(SaisieBandeAction::class)->archiver($this->pondeuses->id);
            $this->fail('Une bande de 200 sujets ne doit pas s\'archiver.');
        } catch (ValidationException $e) {
            $this->assertSame(
                ['bande' => ['Cette bande compte encore 200 sujets vivants : archivez-la après avoir sorti ou transféré les sujets restants.']],
                $e->errors(),
            );
        }
    }

    public function test_une_bande_se_vide_par_un_transfert_puis_s_archive_le_client_n_est_jamais_bloque(): void
    {
        $autre = LivestockLot::create([
            'code' => 'PON-2026-02', 'species_id' => $this->especeId(), 'stage' => 'ponte', 'initial_quantity' => 10, 'current_quantity' => 10,
            'created_date' => '2026-06-01', 'status' => 'actif', 'is_active' => true,
        ]);

        app(TransferBetweenLotsAction::class)->execute([
            'source_lot_id' => $this->pondeuses->id, 'target_lot_id' => $autre->id,
            'transfer_date' => '2026-10-21', 'quantity' => 200, 'categorie' => null, 'constitution' => false, 'motif' => 'Vidage',
        ], $this->admin);

        $this->assertSame([0, 210], [(int) $this->pondeuses->fresh()->current_quantity, (int) $autre->fresh()->current_quantity]);

        Livewire::test(GestionBandes::class)
            ->call('archiveLot', $this->pondeuses->id)
            ->assertDispatched('toast', message: 'Bande archivée avec succès.', type: 'warning');
        $this->assertFalse((bool) $this->pondeuses->fresh()->is_active);
    }

    public function test_une_bande_se_vide_par_la_fiche_sorties_et_morts_puis_s_archive(): void
    {
        $this->pondeuses->update(['current_quantity' => 0]);
        LivestockDailyEntry::create([
            'lot_id' => $this->pondeuses->id, 'entry_date' => '2026-10-20', 'achat' => 0, 'ne' => 0, 'mort' => 5, 'vente' => 195, 'don' => 0, 'effectif_final' => 0,
        ]);

        Livewire::test(GestionBandes::class)->call('archiveLot', $this->pondeuses->id)
            ->assertDispatched('toast', message: 'Bande archivée avec succès.', type: 'warning');
        $this->assertFalse((bool) $this->pondeuses->fresh()->is_active, 'une bande vidée par ses fiches, même avec fiches, s\'archive');
    }

    // ── BS-Q4 : l'effectif d'une bande qui a des fiches se corrige par la fiche ─────────────────────────────────────

    private function ficheDeLaBande(): LivestockDailyEntry
    {
        return LivestockDailyEntry::create([
            'lot_id' => $this->pondeuses->id, 'entry_date' => '2026-10-20', 'achat' => 0, 'ne' => 0, 'mort' => 2, 'vente' => 0, 'don' => 0, 'effectif_final' => 198,
        ]);
    }

    public function test_une_bande_sans_fiche_garde_l_edition_libre_de_l_effectif(): void
    {
        $composant = Livewire::test(GestionBandes::class)->call('editLot', $this->pondeuses->id);

        $this->assertFalse($composant->get('effectifVerrouille'));
        $this->assertStringNotContainsString('data-effectif-verrouille', $composant->html());
    }

    public function test_une_bande_qui_a_des_fiches_grise_l_effectif_avec_une_info_bulle_explicative(): void
    {
        $this->ficheDeLaBande();

        $html = Livewire::test(GestionBandes::class)->call('editLot', $this->pondeuses->id)->html();

        $this->assertSame(1, preg_match('/<input[^>]*data-effectif-verrouille[^>]*>/s', $html, $m), "le champ « Effectif Actuel » est marqué verrouillé");
        $this->assertStringContainsString('disabled', $m[0]);
        $this->assertStringContainsString("title=\"Cette bande a des fiches journalières : son effectif se corrige depuis la fiche (la bande suit automatiquement).\"", $m[0]);
    }

    public function test_le_serveur_refuse_aussi_une_correction_d_effectif_sur_une_bande_a_fiches_mais_pas_le_stade(): void
    {
        $this->ficheDeLaBande();
        $message = "L'effectif de cette bande est tenu par ses fiches journalières : corrigez-le depuis la fiche, la bande suit automatiquement.";

        Livewire::test(GestionBandes::class)
            ->call('editLot', $this->pondeuses->id)
            ->set('quantity', 150)
            ->set('stage', 'engraissement')
            ->call('updateLot')
            ->assertDispatched('toast', message: $message, type: 'error');

        $lot = $this->pondeuses->fresh();
        $this->assertSame([200, 'ponte'], [(int) $lot->current_quantity, $lot->stage], 'rien n\'est écrit : ni effectif ni stade');

        // L'effectif reste celui de la bande (champ grisé) : le stade et le statut se modifient librement.
        Livewire::test(GestionBandes::class)
            ->call('editLot', $this->pondeuses->id)
            ->set('stage', 'engraissement')->set('status', 'cloture')
            ->call('updateLot')
            ->assertDispatched('toast', message: 'Bande modifiée avec succès.', type: 'success');
        $lot = $this->pondeuses->fresh();
        $this->assertSame([200, 'engraissement', 'cloture'], [(int) $lot->current_quantity, $lot->stage, $lot->status]);
    }

    public function test_le_point_de_passage_refuse_la_correction_d_effectif_d_une_bande_a_fiches_sous_le_champ_quantity(): void
    {
        $this->ficheDeLaBande();

        try {
            app(SaisieBandeAction::class)->modifier($this->pondeuses->id, ['stage' => 'ponte', 'status' => 'actif', 'current_quantity' => 150]);
            $this->fail('La correction doit être refusée.');
        } catch (ValidationException $e) {
            $this->assertSame(['quantity'], array_keys($e->errors()));
        }

        // Une valeur identique à l'effectif de la bande n'est pas une correction.
        app(SaisieBandeAction::class)->modifier($this->pondeuses->id, ['stage' => 'croissance', 'status' => 'actif', 'current_quantity' => 200]);
        $this->assertSame('croissance', $this->pondeuses->fresh()->stage);
    }

    // ── BS-Q6 : non-régression — une bande datée dans un exercice clos reste refusée ───────────────────────────────

    public function test_non_regression_la_date_du_dernier_jour_d_un_exercice_clos_est_refusee_la_premiere_d_un_exercice_ouvert_acceptee(): void
    {
        $composant = Livewire::test(GestionBandes::class)
            ->set('species_id', $this->especeId())->set('code', 'LOT-VOL-1')->set('stage', 'croissance')
            ->set('created_date', '2025-12-31')->set('quantity', 5)->call('saveLot');
        $this->assertErreurSousLeChamp($composant, 'created_date', "L'exercice 2025 est clôturé : aucune saisie ne peut être datée du 31/12/2025.");

        Livewire::test(GestionBandes::class)
            ->set('species_id', $this->especeId())->set('code', 'LOT-VOL-2')->set('stage', 'croissance')
            ->set('created_date', '2026-01-01')->set('quantity', 5)->call('saveLot')->assertHasNoErrors();
        $this->assertSame(1, LivestockLot::where('code', 'LOT-VOL-2')->count());
    }

    // ── BS-Q7 : restaurer une bande archivée (web d'abord) ──────────────────────────────────────────────────────────

    private function archiverLaBande(): void
    {
        $this->pondeuses->update(['current_quantity' => 0, 'is_active' => false]);
    }

    public function test_le_filtre_des_archivees_liste_les_bandes_archivees_avec_un_bouton_restaurer(): void
    {
        $this->archiverLaBande();

        $enCours = Livewire::test(GestionBandes::class);
        $this->assertStringNotContainsString('PON-2026-01', $enCours->html());
        $this->assertStringContainsString('Bandes archivées', $enCours->html(), 'le filtre propose les archivées');

        $archivees = Livewire::test(GestionBandes::class)->set('affichage', 'archivees');
        $this->assertStringContainsString('PON-2026-01', $archivees->html());
        $this->assertStringContainsString('restoreLot', $archivees->html());
        $this->assertStringContainsString('Restaurer', $archivees->html());
        $this->assertStringNotContainsString('editLot', $archivees->html(), 'une bande archivée ne se modifie pas');
        $this->assertSame(0, $archivees->instance()->kpis['bandes_actives'], 'les indicateurs ne comptent jamais les archivées');
    }

    public function test_restaurer_remet_la_bande_en_cours_avec_audit_et_la_ligne_reapparait(): void
    {
        $this->archiverLaBande();

        Livewire::test(GestionBandes::class)->set('affichage', 'archivees')
            ->call('restoreLot', $this->pondeuses->id)
            ->assertDispatched('toast', message: 'Bande restaurée avec succès.', type: 'success');

        $this->assertTrue((bool) $this->pondeuses->fresh()->is_active);
        $this->assertSame(1, AuditLog::where('action', 'livestock_lot.restored')->count());
        $this->assertSame(1, Livewire::test(GestionBandes::class)->instance()->kpis['bandes_actives']);

        // Déjà en cours : aucun effet, aucune seconde trace.
        Livewire::test(GestionBandes::class)->call('restoreLot', $this->pondeuses->id);
        $this->assertSame(1, AuditLog::where('action', 'livestock_lot.restored')->count());
    }

    public function test_restaurer_est_refuse_si_le_code_est_deja_porte_par_une_bande_en_cours(): void
    {
        $this->archiverLaBande();
        // Même code, casse différente : la collation du serveur les confond (MySQL) ; ici on le prouve sans index unique.
        LivestockLot::create([
            'code' => 'pon-2026-01', 'species_id' => $this->especeId(), 'stage' => 'ponte', 'initial_quantity' => 5, 'current_quantity' => 5,
            'created_date' => '2026-10-01', 'status' => 'actif', 'is_active' => true,
        ]);

        Livewire::test(GestionBandes::class)->set('affichage', 'archivees')
            ->call('restoreLot', $this->pondeuses->id)
            ->assertDispatched('toast', message: 'Le code « PON-2026-01 » est déjà utilisé par une bande en cours : cette bande ne peut pas être restaurée.', type: 'error');

        $this->assertFalse((bool) $this->pondeuses->fresh()->is_active);
        $this->assertSame(0, AuditLog::where('action', 'livestock_lot.restored')->count());
    }

    public function test_restaurer_exige_manage_elevage(): void
    {
        $this->archiverLaBande();
        $caissier = User::create([
            'name' => 'Caisse', 'username' => 'caisse-bs2', 'email' => 'caisse-bs2@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $caissier->assignRole('caissier');
        $this->actingAs($caissier);

        Livewire::test(GestionBandes::class)->call('restoreLot', $this->pondeuses->id)->assertForbidden();
        $this->assertFalse((bool) $this->pondeuses->fresh()->is_active);
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

        $action->modifier($lot->id, ['stage' => 'ponte', 'status' => 'cloture', 'current_quantity' => 0]);
        $action->archiver($lot->id);
        $this->assertFalse((bool) $lot->fresh()->is_active);

        $this->assertSame(SaisieBandeAction::RESTAUREE_MAINTENANT, $action->restaurer($lot->id));
        $this->assertTrue((bool) $lot->fresh()->is_active);
    }
}
