<?php

namespace Tests\Feature;

use App\Actions\RecordSaleOnFicheElevageAction;
use App\Actions\TransferBetweenLotsAction;
use App\Livewire\Elevage\FicheLapins;
use App\Livewire\Elevage\GestionBandes;
use App\Livewire\Elevage\TransfertsBandes;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\LivestockTransfer;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Validation\ValidationException;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.46 — TRANSFERTS ENTRE BANDES ET CORRECTION DU DOUBLE COMPTAGE (A2).
 *
 * Valeurs calculées À LA MAIN dans chaque test (jamais relues du service qu'on vérifie).
 */
class TransfertsEntreBandesTest extends TestCase
{
    use RefreshDatabase;

    private LivestockSpecies $lapins;

    private User $animalier;

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow('2026-10-14 12:00:00');
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $this->animalier = User::create([
            'name' => 'Animalier', 'username' => 'animalier', 'email' => 'animalier@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->animalier->assignRole('animalier');
        $this->actingAs($this->animalier);

        $this->lapins = LivestockSpecies::create(['code' => 'cuniculture', 'label' => 'Lapins', 'is_enabled' => true]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function bande(string $code, int $initial, string $stade, string $creation, ?LivestockSpecies $espece = null): LivestockLot
    {
        return LivestockLot::create([
            'code' => $code, 'species_id' => ($espece ?? $this->lapins)->id, 'stage' => $stade,
            'initial_quantity' => $initial, 'current_quantity' => $initial,
            'created_date' => $creation, 'status' => 'actif', 'is_active' => true,
        ]);
    }

    /** Fiche posée puis passée par la cascade unique, comme le ferait une fiche journalière. */
    private function fiche(LivestockLot $lot, string $jour, array $valeurs = []): LivestockDailyEntry
    {
        $fiche = LivestockDailyEntry::create(array_merge([
            'lot_id' => $lot->id, 'entry_date' => $jour,
            'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0, 'effectif_final' => 0,
            'mort_repro' => 0, 'mort_sevre' => 0, 'mort_jeune' => 0,
            'don_repro' => 0, 'don_sevre' => 0, 'don_jeune' => 0, 'passage_sevre_jeune' => 0,
        ], $valeurs));
        $fiche->effectif_final = $fiche->effectifFinalDepuis($fiche->previousEffectif());
        $fiche->save();
        app(RecordSaleOnFicheElevageAction::class)->recalculerEnCascade($lot->id, $jour);

        return $fiche->fresh();
    }

    private function transferer(array $donnees): LivestockTransfer
    {
        return app(TransferBetweenLotsAction::class)->execute($donnees, $this->animalier);
    }

    /**
     * ⚠️⚠️ LE DÉFAUT D'ORIGINE (A2) : 8 lapereaux nés dans la bande mère (10 reproducteurs) puis une bande créée
     * pour eux avec 8 sujets. Avant : « Effectif Total Vivant » = 18 + 8 = 26 pour 18 animaux réels.
     */
    public function test_rattacher_une_portee_a_sa_bande_mere_supprime_le_double_comptage(): void
    {
        $mere = $this->bande('LAP-MERE', 10, 'reproduction', '2026-09-01');
        $this->fiche($mere, '2026-09-01', ['cat_depart_repro' => 10, 'cat_depart_sevre' => 0, 'cat_depart_jeune' => 0, 'ne' => 8]);
        $portee = $this->bande('LAP-PORTEE', 8, 'croissance', '2026-09-10');

        $this->assertSame(26, (int) LivestockLot::vivantes()->sum('current_quantity'), 'double comptage avant correction');

        $this->transferer([
            'source_lot_id' => $mere->id, 'target_lot_id' => $portee->id, 'transfer_date' => '2026-09-10',
            'quantity' => 8, 'categorie' => 'sevre', 'constitution' => true,
        ]);

        $this->assertSame(10, (int) $mere->fresh()->current_quantity);
        $this->assertSame(8, (int) $portee->fresh()->current_quantity, "l'effectif initial de la portée la comptait déjà");
        $this->assertSame(18, (int) LivestockLot::vivantes()->sum('current_quantity'));
        $this->assertSame($mere->id, $portee->fresh()->lot_source_id);

        $jour = LivestockDailyEntry::where('lot_id', $mere->id)->whereDate('entry_date', '2026-09-10')->first();
        $this->assertSame(8, (int) $jour->transfert_sortie);
        $this->assertSame(8, (int) $jour->transfert_sortie_sevre);
        $this->assertSame([10, 0, 0], [(int) $jour->cat_eff_repro, (int) $jour->cat_eff_sevre, (int) $jour->cat_eff_jeune]);
        $this->assertSame(0, LivestockDailyEntry::where('lot_id', $portee->id)->count(), 'aucune entrée inscrite dans la portée');
    }

    public function test_un_transfert_ordinaire_sort_de_la_source_entre_dans_la_cible_et_suit_la_cascade(): void
    {
        $a = $this->bande('LAP-A', 20, 'croissance', '2026-09-01');
        $b = $this->bande('LAP-B', 5, 'croissance', '2026-09-01');
        $this->fiche($a, '2026-09-01', ['cat_depart_repro' => 0, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 0]);
        $this->fiche($b, '2026-09-01', ['cat_depart_repro' => 0, 'cat_depart_sevre' => 5, 'cat_depart_jeune' => 0]);
        $this->fiche($b, '2026-09-08', ['mort' => 1, 'mort_sevre' => 1]);

        $t = $this->transferer([
            'source_lot_id' => $a->id, 'target_lot_id' => $b->id, 'transfer_date' => '2026-09-05',
            'quantity' => 6, 'categorie' => 'sevre',
        ]);

        // A : 20 − 6 = 14. B : 5 + 6 = 11 le 05/09, puis 11 − 1 mort = 10 le 08/09.
        $this->assertSame(14, (int) $a->fresh()->current_quantity);
        $this->assertSame(10, (int) $b->fresh()->current_quantity);
        $b08 = LivestockDailyEntry::where('lot_id', $b->id)->whereDate('entry_date', '2026-09-08')->first();
        $this->assertSame([10, 10], [(int) $b08->effectif_final, (int) $b08->cat_eff_sevre]);

        app(TransferBetweenLotsAction::class)->annuler($t);

        // Annulé : tout revient comme avant le transfert, le transfert reste tracé.
        $this->assertSame(20, (int) $a->fresh()->current_quantity);
        $this->assertSame(4, (int) $b->fresh()->current_quantity);
        $this->assertFalse((bool) $t->fresh()->is_active);
    }

    public function test_un_transfert_superieur_a_l_effectif_de_la_source_est_refuse(): void
    {
        $a = $this->bande('LAP-A', 20, 'croissance', '2026-09-01');
        $b = $this->bande('LAP-B', 5, 'croissance', '2026-09-01');
        $this->fiche($a, '2026-09-01', ['cat_depart_repro' => 0, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 0]);
        // Le 10/09, A n'a plus que 12 sujets : 7 transférés le 05/09 la rendraient négative ce jour-là.
        $this->fiche($a, '2026-09-10', ['mort' => 8, 'mort_sevre' => 8]);

        try {
            $this->transferer([
                'source_lot_id' => $a->id, 'target_lot_id' => $b->id, 'transfer_date' => '2026-09-05',
                'quantity' => 13, 'categorie' => 'sevre',
            ]);
            $this->fail('Le transfert aurait dû être refusé.');
        } catch (ValidationException $e) {
            $this->assertStringContainsString('ne compte que 12 sujet(s) le 10/09/2026', $e->errors()['transfert'][0]);
        }

        $this->assertSame(0, LivestockTransfer::count());
        $this->assertSame(12, (int) $a->fresh()->current_quantity);
    }

    public function test_la_categorie_transferee_doit_exister_dans_la_source(): void
    {
        $a = $this->bande('LAP-A', 20, 'croissance', '2026-09-01');
        $b = $this->bande('LAP-B', 5, 'engraissement', '2026-09-01');
        $this->fiche($a, '2026-09-01', ['cat_depart_repro' => 0, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 0]);

        $this->expectException(ValidationException::class);
        $this->transferer([
            'source_lot_id' => $a->id, 'target_lot_id' => $b->id, 'transfer_date' => '2026-09-05',
            'quantity' => 3, 'categorie' => 'jeune',
        ]);
    }

    public function test_especes_differentes_date_future_et_categorie_manquante_sont_refusees(): void
    {
        $porcs = LivestockSpecies::create(['code' => 'porciculture', 'label' => 'Porcs', 'is_enabled' => true]);
        $a = $this->bande('LAP-A', 20, 'croissance', '2026-09-01');
        $b = $this->bande('LAP-B', 5, 'croissance', '2026-09-01');
        $porc = $this->bande('PORC-A', 5, 'croissance', '2026-09-01', $porcs);

        foreach ([
            ['target_lot_id' => $porc->id, 'transfer_date' => '2026-09-05', 'categorie' => 'sevre'],
            ['target_lot_id' => $b->id, 'transfer_date' => '2026-10-20', 'categorie' => 'sevre'],
            ['target_lot_id' => $b->id, 'transfer_date' => '2026-09-05', 'categorie' => null],
            ['target_lot_id' => $b->id, 'transfer_date' => '2026-08-20', 'categorie' => 'sevre'],
        ] as $cas) {
            try {
                $this->transferer(['source_lot_id' => $a->id, 'quantity' => 2] + $cas);
                $this->fail('Refus attendu : '.json_encode($cas));
            } catch (ValidationException) {
            }
        }

        $this->assertSame(0, LivestockTransfer::count());
    }

    /** Ressaisir la fiche d'un jour de transfert ne fait pas disparaître le transfert de l'effectif. */
    public function test_reenregistrer_la_fiche_du_jour_garde_le_transfert(): void
    {
        $a = $this->bande('LAP-A', 20, 'croissance', '2026-09-01');
        $b = $this->bande('LAP-B', 5, 'croissance', '2026-09-01');
        $this->fiche($a, '2026-09-01', ['cat_depart_repro' => 0, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 0]);
        $this->transferer([
            'source_lot_id' => $a->id, 'target_lot_id' => $b->id, 'transfer_date' => '2026-09-05',
            'quantity' => 6, 'categorie' => 'sevre',
        ]);

        Livewire::test(FicheLapins::class)
            ->set('bandeId', $b->id)
            ->set('selectedDate', '2026-09-05')
            ->assertSee('Transferts entre bandes ce jour')
            ->call('saveDay')
            ->assertHasNoErrors();

        $this->assertSame(11, (int) $b->fresh()->current_quantity);
        $this->assertSame(11, (int) LivestockDailyEntry::where('lot_id', $b->id)->whereDate('entry_date', '2026-09-05')->value('effectif_final'));
    }

    public function test_l_ecran_enregistre_un_transfert_et_affiche_son_refus_en_clair(): void
    {
        $a = $this->bande('LAP-A', 20, 'croissance', '2026-09-01');
        $b = $this->bande('LAP-B', 5, 'croissance', '2026-09-01');
        $this->fiche($a, '2026-09-01', ['cat_depart_repro' => 0, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 0]);

        Livewire::test(TransfertsBandes::class)
            ->call('nouveauTransfert')
            ->set('source_lot_id', $a->id)
            ->set('target_lot_id', $b->id)
            ->set('transfer_date', '2026-09-05')
            ->set('quantity', 50)
            ->set('categorie', 'sevre')
            ->call('enregistrer')
            ->assertHasErrors('transfert')
            ->set('quantity', 4)
            ->call('enregistrer')
            ->assertHasNoErrors();

        $this->assertSame(16, (int) $a->fresh()->current_quantity);
        $this->assertSame(9, (int) $b->fresh()->current_quantity);
    }

    public function test_l_ecran_liste_les_bandes_a_rattacher_et_les_rattache(): void
    {
        $mere = $this->bande('LAP-MERE', 10, 'reproduction', '2026-09-01');
        $this->fiche($mere, '2026-09-01', ['cat_depart_repro' => 10, 'cat_depart_sevre' => 0, 'cat_depart_jeune' => 0, 'ne' => 8]);
        $portee = $this->bande('LAP-PORTEE', 8, 'croissance', '2026-09-10');

        $ecran = Livewire::test(TransfertsBandes::class);
        $this->assertTrue($ecran->instance()->bandesARattacher->contains('id', $portee->id));
        $this->assertFalse($ecran->instance()->bandesARattacher->contains('id', $mere->id), 'la plus ancienne bande ne peut être issue d\'aucune autre');

        $ecran->call('rattacher', $portee->id)
            ->assertSet('quantity', 8)
            ->assertSet('transfer_date', '2026-09-10')
            ->assertSet('categorie', 'sevre')
            ->set('source_lot_id', $mere->id)
            ->assertSet('target_lot_id', $portee->id)
            ->call('enregistrer')
            ->assertHasNoErrors();

        $this->assertSame(18, (int) LivestockLot::vivantes()->sum('current_quantity'));
    }

    public function test_creer_une_bande_avec_sa_bande_d_origine_n_ajoute_aucun_sujet_au_total(): void
    {
        $mere = $this->bande('LAP-MERE', 10, 'reproduction', '2026-09-01');
        $this->fiche($mere, '2026-09-01', ['cat_depart_repro' => 10, 'cat_depart_sevre' => 0, 'cat_depart_jeune' => 0, 'ne' => 8]);

        Livewire::test(GestionBandes::class)
            ->call('newLot')
            ->set('species_id', $this->lapins->id)
            ->set('code', 'LAP-PORTEE')
            ->set('stage', 'croissance')
            ->set('created_date', '2026-09-10')
            ->set('quantity', 8)
            ->set('lot_origine_id', $mere->id)
            ->call('saveLot')
            ->assertHasNoErrors();

        $this->assertSame(18, (int) LivestockLot::vivantes()->sum('current_quantity'));
        $this->assertSame($mere->id, LivestockLot::where('code', 'LAP-PORTEE')->value('lot_source_id'));
    }

    public function test_une_constitution_impossible_ne_cree_pas_la_bande(): void
    {
        $mere = $this->bande('LAP-MERE', 10, 'reproduction', '2026-09-01');
        $this->fiche($mere, '2026-09-01', ['cat_depart_repro' => 10, 'cat_depart_sevre' => 0, 'cat_depart_jeune' => 0]);

        Livewire::test(GestionBandes::class)
            ->call('newLot')
            ->set('species_id', $this->lapins->id)
            ->set('code', 'LAP-PORTEE')
            ->set('stage', 'croissance')
            ->set('created_date', '2026-09-10')
            ->set('quantity', 8)
            ->set('lot_origine_id', $mere->id)
            ->call('saveLot')
            ->assertHasErrors('lot_origine_id');

        $this->assertNull(LivestockLot::where('code', 'LAP-PORTEE')->first(), 'aucun Sous-mères dans la bande mère : refus, bande non créée');
    }

    public function test_le_poste_pousse_un_transfert_le_serveur_le_rejoue_une_seule_fois_puis_l_annule(): void
    {
        $a = $this->bande('LAP-A', 20, 'croissance', '2026-09-01');
        $b = $this->bande('LAP-B', 5, 'croissance', '2026-09-01');
        $this->fiche($a, '2026-09-01', ['cat_depart_repro' => 0, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 0]);
        $transfert = [
            'id' => '77777777-7777-4777-8777-777777777777', 'source_lot_id' => $a->id, 'target_lot_id' => $b->id,
            'transfer_date' => '2026-09-05', 'quantity' => 6, 'categorie' => 'sevre', 'is_active' => true,
        ];

        foreach ([1, 2] as $envoi) {
            $this->actingAs($this->animalier, 'sanctum')
                ->postJson('/api/sync/push', ['livestock_transfers' => [$transfert]])
                ->assertJsonPath('livestock_transfers.accepted', [$transfert['id']]);
        }
        $this->assertSame(14, (int) $a->fresh()->current_quantity, 'rejoué une seule fois malgré le renvoi');

        $this->actingAs($this->animalier, 'sanctum')->getJson('/api/sync/pull')
            ->assertJsonPath('livestock_transfers.0.id', $transfert['id']);

        $this->actingAs($this->animalier, 'sanctum')
            ->postJson('/api/sync/push', ['livestock_transfers' => [['is_active' => false] + $transfert]])
            ->assertJsonPath('livestock_transfers.accepted', [$transfert['id']]);
        $this->assertSame(20, (int) $a->fresh()->current_quantity);
    }

    public function test_le_poste_ne_peut_pas_ecrire_les_colonnes_de_transfert_d_une_fiche(): void
    {
        $a = $this->bande('LAP-A', 20, 'croissance', '2026-09-01');

        $this->actingAs($this->animalier, 'sanctum')->postJson('/api/sync/push', [
            'livestock_daily_entries' => [[
                'id' => '88888888-8888-4888-8888-888888888888', 'lot_id' => $a->id, 'entry_date' => '2026-09-02',
                'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'transfert_entree' => 50,
            ]],
        ])->assertJsonPath('livestock_daily_entries.accepted', ['88888888-8888-4888-8888-888888888888']);

        $fiche = LivestockDailyEntry::find('88888888-8888-4888-8888-888888888888');
        $this->assertSame(0, (int) $fiche->transfert_entree);
        $this->assertSame(20, (int) $fiche->effectif_final);
    }
}
