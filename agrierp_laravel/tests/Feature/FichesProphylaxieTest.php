<?php

namespace Tests\Feature;

use App\Livewire\Elevage\FicheLapins;
use App\Livewire\Elevage\FichePorcs;
use App\Models\LivestockLot;
use App\Models\LivestockReproductionEvent;
use App\Models\LivestockSpecies;
use App\Models\Permission;
use App\Models\ProphylaxisScheduleStandard;
use App\Models\Role;
use App\Models\User;
use App\Models\VeterinaryRecord;
use App\Models\VeterinaryWithdrawalPeriod;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.35 — LE MOTEUR DE PROPHYLAXIE EST CÂBLÉ SUR LES FICHES LAPINS ET PORCS.
 *
 * Le ticket 3.11 (soins, rémanence, blocage de vente) est fait depuis
 * longtemps ; les fiches affichaient pourtant « Prévu : Sprint 3, ticket 3.11 »
 * — un marqueur PÉRIMÉ, jamais rouvert. Décision client du 14/10/2026 :
 * « terminer le marqueur » = brancher le moteur, le marqueur disparaît de fait.
 *
 * Barème de test à trois entrées (jours calculés à la main), maintenant figé
 * au 14/10/2026 :
 *   - Anti-stress     : J2 à J4, sans rémanence ;
 *   - Anti-coccidien  : J5, rémanence 5 jours (produit nommé) ;
 *   - Déparasitage    : « Le 1er du mois », bornes nulles.
 * Bande de référence mise en lot le 10/10 : le 14/10 est son J5.
 */
class FichesProphylaxieTest extends TestCase
{
    use RefreshDatabase;

    private LivestockSpecies $lapins;

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow('2026-10-14 09:00:00');

        foreach (['view-elevage', 'manage-elevage'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $animalier = Role::findOrCreate('animalier', 'web');
        $animalier->givePermissionTo(['view-elevage', 'manage-elevage']);

        $this->actingAs($this->utilisateur('animalier.prophylaxie@fermeolouwachegoun.com', $animalier));

        $this->lapins = LivestockSpecies::create(['code' => 'cuniculture', 'label' => 'Lapins', 'is_enabled' => true]);

        $this->standard('cuniculture', 'Anti-stress', 2, 4, 0, 'Vitalyte', "1C / 10L d'eau");
        $this->standard('cuniculture', 'Anti-coccidien', 5, 5, 5, 'Antcox', "1C / 20L d'eau");
        $this->standard('cuniculture', 'Déparasitage', null, null, 7, 'Levalap', "1C / 5L d'eau", 'Le 1er du mois');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function utilisateur(string $email, Role $role): User
    {
        $user = User::create(['name' => 'Animalier', 'email' => $email, 'password' => bcrypt('AgriERP@2026')]);
        $user->assignRole($role);

        return $user;
    }

    private function standard(string $espece, string $traitement, ?int $debut, ?int $fin, int $remanence, string $produit, string $dosage, ?string $libelle = null): ProphylaxisScheduleStandard
    {
        return ProphylaxisScheduleStandard::create([
            'species_code' => $espece,
            'period_label' => $libelle ?? "J{$debut}",
            'cycle_day_start' => $debut,
            'cycle_day_end' => $fin,
            'treatment' => $traitement,
            'product_recommended' => $produit,
            'dosage' => $dosage,
            'withdrawal_days' => $remanence,
            'is_active' => true,
        ]);
    }

    private function bande(LivestockSpecies $espece, string $code, string $stade, string $miseEnLot): LivestockLot
    {
        return LivestockLot::create([
            'code' => $code,
            'species_id' => $espece->id,
            'stage' => $stade,
            'initial_quantity' => 20,
            'current_quantity' => 20,
            'created_date' => $miseEnLot,
            'status' => 'actif',
            'is_active' => true,
        ]);
    }

    private function idDe(string $traitement): string
    {
        return ProphylaxisScheduleStandard::where('treatment', $traitement)->value('id');
    }

    // ─────────────────────────── Affichage ───────────────────────────

    public function test_la_fiche_lapins_affiche_le_protocole_du_jour_et_plus_le_marqueur(): void
    {
        $this->bande($this->lapins, 'LOT-LAP-1', 'croissance', '2026-10-10');

        Livewire::test(FicheLapins::class)
            ->assertSee('Anti-coccidien')
            ->assertSee('Antcox')
            ->assertSee("1C / 20L d'eau")
            ->assertSee('Rémanence 5j')
            ->assertSee('1 Prévu(s)')
            ->assertSee('Indice Rouge : 1 soin(s) en attente')
            ->assertSee("Valider l'Administration de tous ces Traitements Aujourd'hui", false)
            ->assertSee('bloque la vente de cette bande')
            ->assertDontSee('Anti-stress')
            ->assertDontSee('Le moteur automatique de prophylaxie')
            ->assertDontSee('ticket 3.11')
            ->assertDontSee('veterinary_calendar_events');
    }

    public function test_la_fiche_porcs_affiche_le_protocole_du_jour_et_plus_le_marqueur(): void
    {
        $porcs = LivestockSpecies::create(['code' => 'porciculture', 'label' => 'Porcs', 'is_enabled' => true]);
        $this->standard('porciculture', 'Traitement Vermifuge', 4, 4, 14, 'Ivermectine', '1ml / 33kg');
        $this->bande($porcs, 'LOT-POR-1', 'engraissement', '2026-10-11'); // J4

        Livewire::test(FichePorcs::class)
            ->assertSee('Traitement Vermifuge')
            ->assertSee('Rémanence 14j')
            ->assertSee('1 Prévu(s)')
            ->assertDontSee('Le moteur automatique de prophylaxie')
            ->assertDontSee('ticket 3.11');
    }

    /** « Libre » : un jour sans traitement n'est PAS un jour indéterminé. */
    public function test_un_jour_sans_traitement_affiche_libre(): void
    {
        $this->bande($this->lapins, 'LOT-LAP-1', 'croissance', '2026-10-01'); // J14

        Livewire::test(FicheLapins::class)
            ->assertSee('Libre')
            ->assertDontSee("Valider l'Administration de tous ces Traitements Aujourd'hui", false)
            ->assertSee('Aucun traitement récurrent programmé pour ce jour')
            ->assertDontSee('Indéterminé');
    }

    /** Comme au poste (F0.12) : l'inconnue est DITE, elle n'est pas présentée comme « Libre ». */
    public function test_une_bande_en_reproduction_sans_saillie_est_indeterminee(): void
    {
        $this->bande($this->lapins, 'LOT-LAP-R', 'reproduction', '2026-10-10');

        Livewire::test(FicheLapins::class)
            ->assertSee('Indéterminé')
            ->assertSee('saillie')
            ->assertDontSee('Libre')
            ->assertDontSee('Anti-coccidien');
    }

    public function test_une_bande_en_reproduction_se_compte_depuis_la_derniere_saillie(): void
    {
        $bande = $this->bande($this->lapins, 'LOT-LAP-R', 'reproduction', '2026-01-01');
        LivestockReproductionEvent::create(['lot_id' => $bande->id, 'mother_ref' => 'F-01', 'saillie_date' => '2026-10-12', 'status' => 'en_cours']);

        // Saillie le 12/10 : le 14/10 est le J3 -> Anti-stress (et non le J287 de la mise en lot).
        Livewire::test(FicheLapins::class)
            ->assertSee('Anti-stress')
            ->assertDontSee('Indéterminé');
    }

    public function test_les_entrees_calendaires_sont_annoncees_comme_non_evaluees(): void
    {
        $this->bande($this->lapins, 'LOT-LAP-1', 'croissance', '2026-10-10');

        Livewire::test(FicheLapins::class)
            ->assertSee('1 entrée(s) du protocole sans jour de cycle')
            ->assertSee('ne sont pas évaluées ici')
            ->assertDontSee('Déparasitage');
    }

    /** Aucune pastille « Rémanence 0j » : seule une vraie rémanence est affichée. */
    public function test_un_traitement_sans_delai_n_affiche_pas_de_pastille_de_remanence(): void
    {
        $this->bande($this->lapins, 'LOT-LAP-1', 'croissance', '2026-10-12'); // J3 : Anti-stress, 0 jour

        Livewire::test(FicheLapins::class)
            ->assertSee('Anti-stress')
            ->assertSee('Vitalyte')
            ->assertDontSee('Rémanence');
    }

    // ─────────────────────────── Validation ───────────────────────────

    public function test_la_validation_ecrit_le_soin_et_sa_remanence_et_bloque_la_bande(): void
    {
        $bande = $this->bande($this->lapins, 'LOT-LAP-1', 'croissance', '2026-10-10');

        // Rien n'existe tant que l'animalier n'a pas validé : l'affichage n'écrit rien.
        $composant = Livewire::test(FicheLapins::class);
        $this->assertSame(0, VeterinaryRecord::count());
        $this->assertSame(0, VeterinaryWithdrawalPeriod::count());

        $composant->set('observations', 'RAS')
            ->set('traitementsCoches', [$this->idDe('Anti-coccidien')])
            ->call('validerTraitements')
            ->assertSee('Validé / Effectué')
            ->assertSee('Indice Rouge : 0 soin(s) en attente')
            ->assertDontSee("Valider l'Administration de tous ces Traitements Aujourd'hui", false);

        $soin = VeterinaryRecord::sole();
        $this->assertSame($bande->id, $soin->lot_id);
        $this->assertSame('Anti-coccidien', $soin->action_type);
        $this->assertSame('Antcox', $soin->product_used);
        $this->assertSame("1C / 20L d'eau", $soin->dose);
        $this->assertSame('RAS', $soin->symptomes);
        $this->assertSame('2026-10-14', $soin->record_date->toDateString());

        $periode = VeterinaryWithdrawalPeriod::sole();
        $this->assertSame($bande->id, $periode->lot_id);
        $this->assertSame('Antcox', $periode->product_used);
        $this->assertSame(5, (int) $periode->withdrawal_days);
        $this->assertSame('2026-10-14', $periode->start_date->toDateString());
        $this->assertSame('2026-10-19', $periode->end_date->toDateString(), '14/10 + 5 jours.');
        $this->assertTrue(VeterinaryWithdrawalPeriod::isLotBlocked($bande->id));
    }

    public function test_un_traitement_sans_remanence_ecrit_le_soin_sans_bloquer_la_bande(): void
    {
        $bande = $this->bande($this->lapins, 'LOT-LAP-1', 'croissance', '2026-10-12'); // J3 : Anti-stress, 0 jour

        Livewire::test(FicheLapins::class)
            ->set('traitementsCoches', [$this->idDe('Anti-stress')])
            ->call('validerTraitements');

        $this->assertSame(1, VeterinaryRecord::count());
        $this->assertSame(0, VeterinaryWithdrawalPeriod::count());
        $this->assertFalse(VeterinaryWithdrawalPeriod::isLotBlocked($bande->id));
    }

    /** IDEMPOTENCE : valider deux fois = un seul soin, une seule période. */
    public function test_valider_deux_fois_ne_cree_qu_un_soin(): void
    {
        $this->bande($this->lapins, 'LOT-LAP-1', 'croissance', '2026-10-10');

        $composant = Livewire::test(FicheLapins::class)
            ->set('traitementsCoches', [$this->idDe('Anti-coccidien')])
            ->call('validerTraitements');

        // Même cochage rejoué (double clic, onglet périmé) : rien de plus.
        $composant->set('traitementsCoches', [$this->idDe('Anti-coccidien')])
            ->call('validerTraitements');

        $this->assertSame(1, VeterinaryRecord::count());
        $this->assertSame(1, VeterinaryWithdrawalPeriod::count());

        // Une seconde session de la même page, ouverte avant la première validation.
        Livewire::test(FicheLapins::class)
            ->set('traitementsCoches', [$this->idDe('Anti-coccidien')])
            ->call('validerTraitements');

        $this->assertSame(1, VeterinaryRecord::count());
        $this->assertSame(1, VeterinaryWithdrawalPeriod::count());
    }

    public function test_sans_cochage_rien_n_est_ecrit(): void
    {
        $this->bande($this->lapins, 'LOT-LAP-1', 'croissance', '2026-10-10');

        Livewire::test(FicheLapins::class)->call('validerTraitements');

        $this->assertSame(0, VeterinaryRecord::count());
        $this->assertSame(0, VeterinaryWithdrawalPeriod::count());
    }

    /** Seuls les traitements DUS ce jour-là se valident : un identifiant forgé ne passe pas. */
    public function test_un_traitement_hors_protocole_du_jour_ne_se_valide_pas(): void
    {
        $this->bande($this->lapins, 'LOT-LAP-1', 'croissance', '2026-10-10'); // J5

        Livewire::test(FicheLapins::class)
            ->set('traitementsCoches', [$this->idDe('Anti-stress'), $this->idDe('Déparasitage'), 'identifiant-inconnu'])
            ->call('validerTraitements');

        $this->assertSame(0, VeterinaryRecord::count());
        $this->assertSame(0, VeterinaryWithdrawalPeriod::count());
    }

    public function test_une_bande_indeterminee_ne_se_valide_pas(): void
    {
        $this->bande($this->lapins, 'LOT-LAP-R', 'reproduction', '2026-10-10');

        Livewire::test(FicheLapins::class)
            ->set('traitementsCoches', [$this->idDe('Anti-coccidien')])
            ->call('validerTraitements');

        $this->assertSame(0, VeterinaryRecord::count());
    }

    /** Rapprochement : un soin d'un AUTRE jour ou d'une AUTRE bande ne vaut pas validation. */
    public function test_un_soin_d_un_autre_jour_ou_d_une_autre_bande_ne_vaut_pas_validation(): void
    {
        $bande = $this->bande($this->lapins, 'LOT-LAP-1', 'croissance', '2026-10-10');
        $porcs = LivestockSpecies::create(['code' => 'porciculture', 'label' => 'Porcs', 'is_enabled' => true]);
        $autre = $this->bande($porcs, 'LOT-POR-1', 'engraissement', '2026-10-10');

        // Même libellé, mais la veille pour la bande consultée...
        VeterinaryRecord::create(['lot_id' => $bande->id, 'action_type' => 'Anti-coccidien', 'record_date' => '2026-10-13', 'is_active' => true]);
        // ... et le bon jour, mais pour une autre bande.
        VeterinaryRecord::create(['lot_id' => $autre->id, 'action_type' => 'Anti-coccidien', 'record_date' => '2026-10-14', 'is_active' => true]);

        Livewire::test(FicheLapins::class)
            ->assertSee('1 Prévu(s)')
            ->assertDontSee('Validé / Effectué');
    }

    public function test_un_soin_archive_ne_vaut_pas_validation(): void
    {
        $bande = $this->bande($this->lapins, 'LOT-LAP-1', 'croissance', '2026-10-10');
        VeterinaryRecord::create(['lot_id' => $bande->id, 'action_type' => 'Anti-coccidien', 'record_date' => '2026-10-14', 'is_active' => false]);

        Livewire::test(FicheLapins::class)->assertSee('1 Prévu(s)');
    }

    public function test_un_soin_existant_du_jour_marque_le_traitement_comme_valide(): void
    {
        $bande = $this->bande($this->lapins, 'LOT-LAP-1', 'croissance', '2026-10-10');
        VeterinaryRecord::create(['lot_id' => $bande->id, 'action_type' => 'Anti-coccidien', 'record_date' => '2026-10-14', 'is_active' => true]);

        Livewire::test(FicheLapins::class)
            ->assertSee('Validé / Effectué')
            ->assertSee('Indice Rouge : 0 soin(s) en attente');
    }

    /** La validation vise le jour AFFICHÉ de la fiche, pas « aujourd'hui » : rattrapage d'un oubli. */
    public function test_la_validation_d_un_jour_passe_est_datee_de_ce_jour(): void
    {
        $bande = $this->bande($this->lapins, 'LOT-LAP-1', 'croissance', '2026-10-10');

        Livewire::test(FicheLapins::class)
            ->set('selectedDate', '2026-10-12') // J3 -> Anti-stress
            ->set('traitementsCoches', [$this->idDe('Anti-stress')])
            ->call('validerTraitements');

        $soin = VeterinaryRecord::sole();
        $this->assertSame('Anti-stress', $soin->action_type);
        $this->assertSame('2026-10-12', $soin->record_date->toDateString());
        $this->assertSame($bande->id, $soin->lot_id);
    }

    public function test_un_jour_futur_ne_se_valide_pas(): void
    {
        $this->bande($this->lapins, 'LOT-LAP-1', 'croissance', '2026-10-10');

        Livewire::test(FicheLapins::class)
            ->set('selectedDate', '2026-10-15') // J6 : rien n'est dû, le cochage forgé est ignoré
            ->set('traitementsCoches', [$this->idDe('Anti-coccidien')])
            ->call('validerTraitements');

        $this->assertSame(0, VeterinaryRecord::count());

        // Un jour futur DUE : bande mise en lot le 11/10, J5 = 15/10.
        LivestockLot::query()->update(['created_date' => '2026-10-11']);
        Livewire::test(FicheLapins::class)
            ->set('selectedDate', '2026-10-15')
            ->set('traitementsCoches', [$this->idDe('Anti-coccidien')])
            ->call('validerTraitements');

        $this->assertSame(0, VeterinaryRecord::count(), 'Un traitement n\'est pas administré à l\'avance.');
    }

    public function test_changer_de_jour_vide_le_cochage(): void
    {
        $this->bande($this->lapins, 'LOT-LAP-1', 'croissance', '2026-10-10');

        Livewire::test(FicheLapins::class)
            ->set('traitementsCoches', [$this->idDe('Anti-coccidien')])
            ->call('loadDay', '2026-10-13')
            ->assertSet('traitementsCoches', [])
            ->set('traitementsCoches', [$this->idDe('Anti-stress')])
            ->set('selectedDate', '2026-10-12')
            ->assertSet('traitementsCoches', []);
    }

    public function test_un_utilisateur_sans_manage_elevage_ne_valide_pas(): void
    {
        $this->bande($this->lapins, 'LOT-LAP-1', 'croissance', '2026-10-10');

        Permission::findOrCreate('view-ventes', 'web');
        $lecteur = Role::findOrCreate('lecteur-elevage', 'web');
        $lecteur->givePermissionTo('view-elevage');
        $this->actingAs($this->utilisateur('lecteur.prophylaxie@fermeolouwachegoun.com', $lecteur));

        Livewire::test(FicheLapins::class)
            ->set('traitementsCoches', [$this->idDe('Anti-coccidien')])
            ->call('validerTraitements')
            ->assertForbidden();

        $this->assertSame(0, VeterinaryRecord::count());
    }

    public function test_la_validation_sur_les_porcs_ecrit_soin_et_remanence(): void
    {
        $porcs = LivestockSpecies::create(['code' => 'porciculture', 'label' => 'Porcs', 'is_enabled' => true]);
        $this->standard('porciculture', 'Traitement Vermifuge', 4, 4, 14, 'Ivermectine', '1ml / 33kg');
        $bande = $this->bande($porcs, 'LOT-POR-1', 'engraissement', '2026-10-11'); // J4

        Livewire::test(FichePorcs::class)
            ->set('traitementsCoches', [$this->idDe('Traitement Vermifuge')])
            ->call('validerTraitements')
            ->assertSee('Validé / Effectué');

        $this->assertSame(1, VeterinaryRecord::where('lot_id', $bande->id)->count());
        $periode = VeterinaryWithdrawalPeriod::sole();
        $this->assertSame('2026-10-28', $periode->end_date->toDateString(), '14/10 + 14 jours.');
        $this->assertTrue(VeterinaryWithdrawalPeriod::isLotBlocked($bande->id));
    }

    // ───────────────────── Marqueurs des fiches non câblées ─────────────────────

    /**
     * 🔁 17/10/2026 — Pondeuses et Reproducteurs sont RACCORDÉES au protocole du jour (même moteur que Lapins et
     * Porcs) : plus de marqueur « à planifier » pour la prophylaxie. Escargots garde ses marqueurs (hygrométrie,
     * rationnement) : leur suite reste dite, sans échéance inventée.
     */
    public function test_les_marqueurs_restants_ne_pretendent_plus_attendre_le_ticket_3_11(): void
    {
        foreach (['fiche-pondeuses', 'fiche-reproducteurs'] as $vue) {
            $source = file_get_contents(resource_path("views/livewire/elevage/{$vue}.blade.php"));

            $this->assertStringNotContainsString('Sprint 3, ticket 3.11', $source, "{$vue} : marqueur périmé.");
            $this->assertStringContainsString('<x-prophylaxie-du-jour', $source, "{$vue} : la prophylaxie du jour est raccordée.");
            $this->assertStringNotContainsString("son raccordement à cette fiche n'est pas fait", $source);
        }

        $escargots = file_get_contents(resource_path('views/livewire/elevage/fiche-escargots.blade.php'));
        $this->assertStringNotContainsString('Sprint 3, ticket 3.11', $escargots);
        $this->assertStringContainsString('à planifier', $escargots, 'fiche-escargots : la suite doit être dite, sans échéance inventée.');

        foreach (['fiche-lapins', 'fiche-porcs'] as $vue) {
            $source = file_get_contents(resource_path("views/livewire/elevage/{$vue}.blade.php"));
            $this->assertStringNotContainsString('moteur automatique de prophylaxie', $source);
            $this->assertStringNotContainsString('ticket 3.11', $source);
        }
    }

    public function test_les_docblocks_ne_disent_plus_que_la_table_n_est_pas_construite(): void
    {
        foreach (['FicheLapins', 'FichePorcs'] as $classe) {
            $source = file_get_contents(app_path("Livewire/Elevage/{$classe}.php"));
            $this->assertStringNotContainsString('pas encore construite', $source, $classe);
        }
    }
}
