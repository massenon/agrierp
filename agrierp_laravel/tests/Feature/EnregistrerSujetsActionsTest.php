<?php

namespace Tests\Feature;

use App\Actions\SaisieSujetAction;
use App\Livewire\Elevage\EnregistrerSujets;
use App\Models\AuditLog;
use App\Models\LivestockDailyEntry;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket BS2 (web d'abord, article 5) — « Enregistrer des Sujets » : Nouveau, Modifier, Archiver une entrée du journal.
 *
 * Une ligne du journal = UNE ORIGINE d'une fiche du jour (Naissance → `ne`, Achat → `achat`, Don → `don`). Modifier ou
 * archiver passe par la cascade unique `recalculerEnCascade` (A1) : les jours suivants et la bande suivent.
 *
 * Décor : `PreparationExercices` — bande PON-2026-01, 200 têtes au 01/06/2026, exercice 2025 clos. Les effectifs
 * attendus sont écrits à la main (200 + entrées − sorties).
 */
class EnregistrerSujetsActionsTest extends TestCase
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

    private function ajouter(string $origine, int $quantite, string $jour)
    {
        return Livewire::test(EnregistrerSujets::class)
            ->set('species_id', $this->pondeuses->species_id)
            ->set('lot_id', $this->pondeuses->id)
            ->set('origine', $origine)
            ->set('quantite', $quantite)
            ->set('entry_date', $jour)
            ->call('saveEntry');
    }

    private function fiche(string $jour): ?LivestockDailyEntry
    {
        return LivestockDailyEntry::where('lot_id', $this->pondeuses->id)->whereDate('entry_date', $jour)->first();
    }

    private function effectif(string $jour): ?int
    {
        return $this->fiche($jour)?->effectif_final;
    }

    private function bande(): int
    {
        return (int) $this->pondeuses->fresh()->current_quantity;
    }

    /** 10 naissances le 10/10 (210), 5 achats le 15/10 (215). */
    private function decorJournal(): void
    {
        $this->ajouter('Naissance', 10, '2026-10-10')->assertHasNoErrors();
        $this->ajouter('Achat', 5, '2026-10-15')->assertHasNoErrors();
        $this->assertSame([210, 215, 215], [$this->effectif('2026-10-10'), $this->effectif('2026-10-15'), $this->bande()]);
    }

    private function modifier(string $dateAncienne, string $origineAncienne, string $origine, int $quantite, string $jour)
    {
        $fiche = $this->fiche($dateAncienne);

        return Livewire::test(EnregistrerSujets::class)
            ->call('editEntry', $fiche->id, $origineAncienne)
            ->set('origine', $origine)
            ->set('quantite', $quantite)
            ->set('entry_date', $jour)
            ->call('updateEntry');
    }

    public function test_modifier_la_quantite_recalcule_la_fiche_les_jours_suivants_et_la_bande(): void
    {
        $this->decorJournal();

        $this->modifier('2026-10-10', 'Naissance', 'Naissance', 4, '2026-10-10')
            ->assertHasNoErrors()
            ->assertDispatched('toast', message: 'Modification enregistrée avec succès.', type: 'success');

        // 200 + 4 = 204 ; 204 + 5 = 209.
        $this->assertSame([4, 204, 209, 209], [(int) $this->fiche('2026-10-10')->ne, $this->effectif('2026-10-10'), $this->effectif('2026-10-15'), $this->bande()]);
        $this->assertSame(1, AuditLog::where('action', 'livestock_entry.updated')->count());
    }

    public function test_modifier_l_origine_deplace_la_quantite_de_colonne(): void
    {
        $this->decorJournal();

        $this->modifier('2026-10-10', 'Naissance', 'Achat', 10, '2026-10-10')->assertHasNoErrors();

        $fiche = $this->fiche('2026-10-10');
        $this->assertSame([0, 10, 210, 215], [(int) $fiche->ne, (int) $fiche->achat, $this->effectif('2026-10-10'), $this->bande()]);
    }

    public function test_modifier_la_date_retire_l_entree_du_premier_jour_et_la_pose_sur_le_second(): void
    {
        $this->decorJournal();

        $this->modifier('2026-10-10', 'Naissance', 'Naissance', 10, '2026-10-20')->assertHasNoErrors();

        // 10/10 : plus rien (200) ; 15/10 : 205 ; 20/10 : 215 ; la bande suit la DERNIÈRE fiche.
        $this->assertSame([0, 200, 205, 215, 215], [
            (int) $this->fiche('2026-10-10')->ne, $this->effectif('2026-10-10'), $this->effectif('2026-10-15'),
            $this->effectif('2026-10-20'), $this->bande(),
        ]);
    }

    public function test_archiver_remet_la_colonne_a_zero_cascade_et_le_journal_ne_la_montre_plus(): void
    {
        $this->decorJournal();
        $fiche = $this->fiche('2026-10-15');

        Livewire::test(EnregistrerSujets::class)
            ->call('archiveEntry', $fiche->id, 'Achat')
            ->assertHasNoErrors()
            ->assertDispatched('toast', message: 'Entrée archivée avec succès.', type: 'warning');

        $this->assertSame([0, 210, 210], [(int) $this->fiche('2026-10-15')->achat, $this->effectif('2026-10-15'), $this->bande()]);
        $this->assertSame(1, AuditLog::where('action', 'livestock_entry.archived')->count());
        $this->assertNotNull($this->fiche('2026-10-15'), 'la fiche du jour est gardée, jamais supprimée');
    }

    public function test_une_fiche_avec_naissance_et_achat_donne_deux_lignes_chacune_avec_ses_actions(): void
    {
        $this->ajouter('Naissance', 3, '2026-10-12')->assertHasNoErrors();
        $this->ajouter('Achat', 2, '2026-10-12')->assertHasNoErrors();

        $composant = Livewire::test(EnregistrerSujets::class);
        $fiche = $this->fiche('2026-10-12');

        $this->assertCount(2, $composant->instance()->entries);
        $this->assertStringContainsString("editEntry('{$fiche->id}', 'Naissance')", $composant->html());
        $this->assertStringContainsString("editEntry('{$fiche->id}', 'Achat')", $composant->html());
        $this->assertStringContainsString("archive-sujet-{$fiche->id}-Achat", $composant->html(), 'confirmation x-modal-confirm-delete');
    }

    public function test_un_effectif_qui_deviendrait_negatif_un_jour_suivant_refuse_la_modification_et_l_archivage(): void
    {
        $this->decorJournal();
        // 12/10 : vente de 205 sujets → 210 - 205 = 5 ; 15/10 : 5 + 5 achetés = 10.
        $this->fiche('2026-10-15'); // (déjà là)
        $vente = LivestockDailyEntry::create([
            'lot_id' => $this->pondeuses->id, 'entry_date' => '2026-10-12', 'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 205, 'don' => 0, 'effectif_final' => 5,
        ]);
        app(\App\Actions\RecordSaleOnFicheElevageAction::class)->recalculerEnCascade($this->pondeuses->id, '2026-10-10');
        $this->assertSame([5, 10, 10], [$this->effectif('2026-10-12'), $this->effectif('2026-10-15'), $this->bande()]);

        // Archiver les 10 naissances : 200 - 205 = -5 le 12/10.
        $archivage = Livewire::test(EnregistrerSujets::class)->call('archiveEntry', $this->fiche('2026-10-10')->id, 'Naissance');
        $this->assertSame("Saisie refusée : l'effectif de la bande PON-2026-01 deviendrait négatif le 12/10/2026 (-5).", $archivage->errors()->first('quantite'));

        $modification = $this->modifier('2026-10-10', 'Naissance', 'Naissance', 4, '2026-10-10');
        $this->assertSame("Saisie refusée : l'effectif de la bande PON-2026-01 deviendrait négatif le 12/10/2026 (-1).", $modification->errors()->first('quantite'));

        $this->assertSame([10, 210, 5, 10, 10], [
            (int) $this->fiche('2026-10-10')->ne, $this->effectif('2026-10-10'), $this->effectif('2026-10-12'), $this->effectif('2026-10-15'), $this->bande(),
        ], 'rien n\'a été écrit');
        $this->assertSame(0, AuditLog::whereIn('action', ['livestock_entry.updated', 'livestock_entry.archived'])->count());
        unset($vente);
    }

    public function test_une_date_dans_un_exercice_clos_est_refusee_pour_les_trois_gestes_avec_le_motif_du_serveur(): void
    {
        $clos = "L'exercice 2025 est clôturé : aucune saisie ne peut être datée du 20/12/2025.";

        $this->assertErreurSousLeChamp($this->ajouter('Achat', 5, '2025-12-20'), 'entry_date', $clos);
        $this->assertSame(0, LivestockDailyEntry::count());

        // Une entrée d'un exercice clos (posée directement : le décor), ni modifiable ni archivable.
        $ancienne = LivestockDailyEntry::create([
            'lot_id' => $this->pondeuses->id, 'entry_date' => '2025-12-20', 'achat' => 7, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0, 'effectif_final' => 207,
        ]);

        $archivage = Livewire::test(EnregistrerSujets::class)->call('archiveEntry', $ancienne->id, 'Achat');
        $this->assertSame($clos, $archivage->errors()->first('entry_date'));

        $modification = Livewire::test(EnregistrerSujets::class)
            ->call('editEntry', $ancienne->id, 'Achat')
            ->set('quantite', 3)
            ->call('updateEntry');
        $this->assertSame($clos, $modification->errors()->first('entry_date'));

        $this->assertSame(7, (int) $ancienne->fresh()->achat);
    }

    public function test_une_entree_deja_archivee_ou_modifiee_est_signalee_et_n_ecrit_rien(): void
    {
        $this->decorJournal();
        $id = $this->fiche('2026-10-15')->id;

        Livewire::test(EnregistrerSujets::class)->call('archiveEntry', $id, 'Achat');
        $seconde = Livewire::test(EnregistrerSujets::class)->call('archiveEntry', $id, 'Achat')
            ->assertDispatched('toast', message: "Cette entrée n'existe plus : elle a déjà été modifiée ou archivée.", type: 'error');

        $this->assertSame(1, AuditLog::where('action', 'livestock_entry.archived')->count());
        unset($seconde);
    }

    public function test_les_droits_manage_elevage_et_archive_elevage_sont_exiges_a_chaque_geste(): void
    {
        $this->decorJournal();
        $fiche = $this->fiche('2026-10-10');

        $caissier = User::create([
            'name' => 'Caisse', 'username' => 'caisse-bs2', 'email' => 'caisse-bs2@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $caissier->assignRole('caissier');
        $this->actingAs($caissier);
        foreach (['newEntry', 'saveEntry', 'updateEntry'] as $methode) {
            Livewire::test(EnregistrerSujets::class)->call($methode)->assertForbidden();
        }
        Livewire::test(EnregistrerSujets::class)->call('editEntry', $fiche->id, 'Naissance')->assertForbidden();
        Livewire::test(EnregistrerSujets::class)->call('archiveEntry', $fiche->id, 'Naissance')->assertForbidden();

        // Un compte qui saisit sans pouvoir archiver : modifier oui, archiver non.
        $saisisseur = User::create([
            'name' => 'Saisie', 'username' => 'saisie-bs2', 'email' => 'saisie-bs2@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $saisisseur->givePermissionTo(['view-elevage', 'manage-elevage']);
        $this->actingAs($saisisseur);
        Livewire::test(EnregistrerSujets::class)->call('editEntry', $fiche->id, 'Naissance')->assertOk();
        Livewire::test(EnregistrerSujets::class)->call('archiveEntry', $fiche->id, 'Naissance')->assertForbidden();
        $this->assertSame(10, (int) $fiche->fresh()->ne);
    }

    public function test_les_boutons_du_blade_suivent_les_droits(): void
    {
        $this->decorJournal();

        $html = Livewire::test(EnregistrerSujets::class)->html();
        $this->assertStringContainsString('title="Modifier"', $html);
        $this->assertStringContainsString('title="Archiver"', $html);
        $this->assertStringContainsString('Modifier le Sujet', $html);

        $lecteur = User::create([
            'name' => 'Lecteur', 'username' => 'lecteur-bs2', 'email' => 'lecteur-bs2@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $lecteur->givePermissionTo('view-elevage');
        $this->actingAs($lecteur);
        $html = Livewire::test(EnregistrerSujets::class)->html();
        $this->assertStringNotContainsString('title="Modifier"', $html);
        $this->assertStringNotContainsString('wire:click="newEntry"', $html);
        $this->assertStringContainsString('Lecture seule', $html);
    }

    public function test_le_point_de_passage_unique_existe(): void
    {
        $this->assertTrue(class_exists(SaisieSujetAction::class));
    }
}
