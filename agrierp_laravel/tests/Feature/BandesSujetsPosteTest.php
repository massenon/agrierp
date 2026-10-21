<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\LivestockTransfer;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Tickets BS1 et BS2 — ENVOI DU POSTE : bandes (création, modification, archivage) et entrées de sujets (fiches).
 *
 * Mêmes règles et mêmes droits que le web (`SaisieBandeAction` / `SaisieSujetAction`). Le poste n'écrase jamais ce qu'il
 * n'a pas le droit de décider : l'effectif d'une bande n'est écrit que sur correction explicite (`effectif_corrige`),
 * sinon il appartient à la cascade des fiches. Valeurs attendues écrites à la main.
 *
 * Décor : `PreparationExercices` (exercice 2025 clos, 2026 ouvert, bande PON-2026-01 de 200 têtes au 01/06/2026).
 */
class BandesSujetsPosteTest extends TestCase
{
    use PreparationExercices;
    use RefreshDatabase;

    private const LOT = 'bbbb1111-0000-4000-8000-000000000001';

    private const LOT_2 = 'bbbb1111-0000-4000-8000-000000000002';

    private const FICHE = 'ffff1111-0000-4000-8000-000000000001';

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

    /** Une bande telle que le poste l'envoie (colonnes de la table, UUID créé au poste). */
    private function bande(array $remplacements = []): array
    {
        return array_merge([
            'id' => self::LOT, 'code' => 'LOT-VOL-9', 'species_id' => $this->pondeuses->species_id,
            'stage' => 'croissance', 'created_date' => '2026-10-20', 'initial_quantity' => 40,
            'acquisition_cost' => 135000, 'product_id' => null, 'status' => 'actif', 'is_active' => true,
            'device_id' => 'poste-bureau',
        ], $remplacements);
    }

    private function pousserBandes(array ...$bandes)
    {
        return $this->envoyer(['livestock_lots' => $bandes]);
    }

    private function jeton(string $role): void
    {
        $utilisateur = User::create([
            'name' => $role, 'username' => $role.'-bs', 'email' => $role.'-bs@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $utilisateur->assignRole($role);
        // `actingAs` du décor (l'administrateur du web) primerait sur le jeton : on le retire, le poste parle seul.
        $this->app['auth']->forgetGuards();
        $this->jeton = $this->postJson('/api/auth/login', [
            'identifiant' => $role.'-bs', 'password' => 'AgriERP@2026', 'device_name' => 'poste-'.$role,
        ])->assertOk()->json('token');
    }

    // ── BS1 : bandes ───────────────────────────────────────────────────────────────────────────────────────────────

    public function test_une_bande_creee_au_poste_est_acceptee_avec_son_uuid_et_son_effectif(): void
    {
        $reponse = $this->pousserBandes($this->bande())->assertOk();

        $reponse->assertJsonPath('livestock_lots.accepted', [self::LOT])->assertJsonPath('livestock_lots.rejected', []);
        $lot = LivestockLot::findOrFail(self::LOT);
        $this->assertSame(['LOT-VOL-9', 'croissance', 40, 40, 'actif', true], [
            $lot->code, $lot->stage, (int) $lot->initial_quantity, (int) $lot->current_quantity, $lot->status, (bool) $lot->is_active,
        ]);
        $this->assertSame('2026-10-20', $lot->created_date->format('Y-m-d'));
        $this->assertSame(1, AuditLog::where('action', 'livestock_lot.created')->count());
    }

    public function test_le_renvoi_d_une_bande_connue_est_acquitte_sans_rien_reecrire(): void
    {
        $this->pousserBandes($this->bande())->assertOk();
        $avant = LivestockLot::findOrFail(self::LOT)->updated_at;
        Carbon::setTestNow('2026-10-21 11:00:00');

        $this->pousserBandes($this->bande())->assertJsonPath('livestock_lots.accepted', [self::LOT]);

        $this->assertSame(1, LivestockLot::where('code', 'LOT-VOL-9')->count());
        $this->assertSame(1, AuditLog::where('action', 'livestock_lot.created')->count());
        $this->assertSame(0, AuditLog::where('action', 'livestock_lot.updated')->count());
        $this->assertTrue($avant->equalTo(LivestockLot::findOrFail(self::LOT)->updated_at), 'aucune écriture au renvoi');
    }

    public function test_modifier_le_stade_et_le_statut_ne_touche_pas_a_l_effectif_sans_correction_explicite(): void
    {
        $this->pousserBandes($this->bande())->assertOk();
        // Le serveur a reçu entre-temps des fiches : l'effectif de la bande est devenu 52.
        LivestockLot::whereKey(self::LOT)->update(['current_quantity' => 52]);

        $this->pousserBandes($this->bande(['stage' => 'ponte', 'status' => 'cloture']))
            ->assertJsonPath('livestock_lots.accepted', [self::LOT]);

        $lot = LivestockLot::findOrFail(self::LOT);
        $this->assertSame(['ponte', 'cloture', 52, 40], [$lot->stage, $lot->status, (int) $lot->current_quantity, (int) $lot->initial_quantity]);
        $this->assertSame(1, AuditLog::where('action', 'livestock_lot.updated')->count());
    }

    public function test_la_correction_explicite_de_l_effectif_est_ecrite_comme_au_web(): void
    {
        $this->pousserBandes($this->bande())->assertOk();

        $this->pousserBandes($this->bande(['effectif_corrige' => 33]))->assertJsonPath('livestock_lots.accepted', [self::LOT]);

        $this->assertSame(33, (int) LivestockLot::findOrFail(self::LOT)->current_quantity);
    }

    public function test_une_bande_creee_puis_corrigee_et_cloturee_avant_tout_envoi_arrive_dans_son_dernier_etat(): void
    {
        $this->pousserBandes($this->bande(['status' => 'cloture', 'effectif_corrige' => 31]))
            ->assertJsonPath('livestock_lots.accepted', [self::LOT]);

        $lot = LivestockLot::findOrFail(self::LOT);
        $this->assertSame([40, 31, 'cloture'], [(int) $lot->initial_quantity, (int) $lot->current_quantity, $lot->status]);
    }

    public function test_archiver_une_bande_est_logique_idempotent_et_la_bande_n_est_plus_modifiable(): void
    {
        $this->pousserBandes($this->bande())->assertOk();

        $this->pousserBandes($this->bande(['is_active' => false]))->assertJsonPath('livestock_lots.accepted', [self::LOT]);
        $lot = LivestockLot::findOrFail(self::LOT);
        $this->assertSame([false, 'actif', 40], [(bool) $lot->is_active, $lot->status, (int) $lot->current_quantity]);

        $this->pousserBandes($this->bande(['is_active' => false]))->assertJsonPath('livestock_lots.accepted', [self::LOT]);
        $this->assertSame(1, AuditLog::where('action', 'livestock_lot.archived')->count(), 'second envoi : aucune seconde trace');

        $this->pousserBandes($this->bande(['stage' => 'ponte', 'is_active' => true]))
            ->assertJsonPath('livestock_lots.accepted', [])
            ->assertJsonPath('livestock_lots.rejected.0.reason', 'Cette bande est archivée : elle ne peut plus être modifiée.');
        $this->assertSame('croissance', LivestockLot::findOrFail(self::LOT)->stage);
    }

    public function test_une_bande_creee_puis_archivee_avant_tout_envoi_est_creee_archivee(): void
    {
        $this->pousserBandes($this->bande(['is_active' => false]))->assertJsonPath('livestock_lots.accepted', [self::LOT]);

        $this->assertFalse((bool) LivestockLot::findOrFail(self::LOT)->is_active);
    }

    public function test_les_rejets_sont_motives_en_francais_et_n_ecrivent_rien(): void
    {
        $doublon = $this->bande(['id' => self::LOT_2, 'code' => 'PON-2026-01']);
        $clos = $this->bande(['id' => 'bbbb1111-0000-4000-8000-000000000003', 'code' => 'LOT-CLOS', 'created_date' => '2025-12-20']);
        $zero = $this->bande(['id' => 'bbbb1111-0000-4000-8000-000000000004', 'code' => 'LOT-ZERO', 'initial_quantity' => 0]);
        $stade = $this->bande(['id' => 'bbbb1111-0000-4000-8000-000000000005', 'code' => 'LOT-STADE', 'stage' => 'abattage']);
        $espece = $this->bande(['id' => 'bbbb1111-0000-4000-8000-000000000006', 'code' => 'LOT-ESP', 'species_id' => 'bbbb1111-0000-4000-8000-0000000000ff']);

        $reponse = $this->pousserBandes($doublon, $clos, $zero, $stade, $espece)->assertOk();

        $reponse->assertJsonPath('livestock_lots.accepted', []);
        $motifs = collect($reponse->json('livestock_lots.rejected'))->pluck('reason', 'id');
        $this->assertSame('La valeur du champ code existe déjà.', $motifs[self::LOT_2]);
        $this->assertSame("L'exercice 2025 est clôturé : aucune saisie ne peut être datée du 20/12/2025.", $motifs['bbbb1111-0000-4000-8000-000000000003']);
        $this->assertSame("Le champ effectif initial est inférieur au minimum autorisé (1).", $motifs['bbbb1111-0000-4000-8000-000000000004']);
        $this->assertSame("La valeur du champ stade n'est pas autorisée.", $motifs['bbbb1111-0000-4000-8000-000000000005']);
        $this->assertSame('La valeur du champ espèce ne correspond à aucun enregistrement connu du serveur.', $motifs['bbbb1111-0000-4000-8000-000000000006']);
        $this->assertSame(1, LivestockLot::count(), 'seule la bande du décor existe');
    }

    public function test_le_code_d_une_bande_connue_ne_change_jamais(): void
    {
        $this->pousserBandes($this->bande())->assertOk();

        $this->pousserBandes($this->bande(['code' => 'LOT-AUTRE']))
            ->assertJsonPath('livestock_lots.rejected.0.reason', "Le code d'une bande ne se modifie jamais après sa création.");

        $this->assertSame('LOT-VOL-9', LivestockLot::findOrFail(self::LOT)->code);
    }

    public function test_un_compte_sans_manage_elevage_est_refuse_bande_par_bande(): void
    {
        $this->jeton('caissier');

        $reponse = $this->pousserBandes($this->bande())->assertOk();

        $reponse->assertJsonPath('livestock_lots.accepted', []);
        $reponse->assertJsonPath('livestock_lots.rejected.0.id', self::LOT);
        $reponse->assertJsonPath('livestock_lots.rejected.0.reason', 'Refusé : votre rôle ne permet pas de créer, modifier ou archiver une bande. Connectez-vous au poste avec un compte autorisé.');
        $this->assertSame(0, LivestockLot::where('id', self::LOT)->count());
    }

    public function test_l_animalier_envoie_ses_bandes(): void
    {
        $this->jeton('animalier');

        $this->pousserBandes($this->bande())->assertJsonPath('livestock_lots.accepted', [self::LOT]);
    }

    public function test_la_bande_et_sa_fiche_du_meme_envoi_sont_acceptees_dans_l_ordre(): void
    {
        $paquet = [
            'livestock_lots' => [$this->bande()],
            'livestock_daily_entries' => [[
                'id' => self::FICHE, 'lot_id' => self::LOT, 'entry_date' => '2026-10-20',
                'achat' => 0, 'ne' => 6, 'mort' => 0, 'vente' => 0, 'don' => 0, 'effectif_final' => 46,
            ]],
        ];

        $reponse = $this->envoyer($paquet)->assertOk();

        $reponse->assertJsonPath('livestock_lots.accepted', [self::LOT])->assertJsonPath('livestock_daily_entries.accepted', [self::FICHE]);
        $this->assertSame(46, (int) LivestockLot::findOrFail(self::LOT)->current_quantity, 'la cascade du serveur suit la fiche');
    }

    public function test_la_constitution_d_une_bande_part_comme_un_transfert_et_sort_les_sujets_de_la_bande_mere(): void
    {
        $paquet = [
            'livestock_lots' => [$this->bande(['initial_quantity' => 20])],
            'livestock_transfers' => [[
                'id' => 'cccc1111-0000-4000-8000-000000000001', 'source_lot_id' => $this->pondeuses->id, 'target_lot_id' => self::LOT,
                'transfer_date' => '2026-10-20', 'quantity' => 20, 'categorie' => null, 'constitution' => true,
                'motif' => 'Constitution de la bande LOT-VOL-9', 'is_active' => true,
            ]],
        ];

        $reponse = $this->envoyer($paquet)->assertOk();

        $reponse->assertJsonPath('livestock_lots.accepted', [self::LOT])->assertJsonPath('livestock_transfers.accepted', ['cccc1111-0000-4000-8000-000000000001']);
        $this->assertSame(180, (int) $this->pondeuses->fresh()->current_quantity, '200 - 20 sortis de la bande mère');
        $this->assertSame(20, (int) LivestockLot::findOrFail(self::LOT)->current_quantity, 'aucune entrée dans la bande constituée');
        $this->assertSame(self::LOT, LivestockTransfer::findOrFail('cccc1111-0000-4000-8000-000000000001')->target_lot_id);
    }

    // ── BS2 : entrées de sujets (fiches du jour) ───────────────────────────────────────────────────────────────────

    private function fiche(array $remplacements = []): array
    {
        return array_merge([
            'id' => self::FICHE, 'lot_id' => $this->pondeuses->id, 'entry_date' => '2026-10-10',
            'achat' => 0, 'ne' => 10, 'mort' => 0, 'vente' => 0, 'don' => 0, 'effectif_final' => 210,
        ], $remplacements);
    }

    private function pousserFiche(array $remplacements = [])
    {
        return $this->envoyer(['livestock_daily_entries' => [$this->fiche($remplacements)]]);
    }

    public function test_une_entree_de_sujets_creee_au_poste_alimente_la_fiche_et_la_bande(): void
    {
        $this->pousserFiche()->assertJsonPath('livestock_daily_entries.accepted', [self::FICHE]);

        $fiche = LivestockDailyEntry::findOrFail(self::FICHE);
        $this->assertSame([10, 210], [(int) $fiche->ne, (int) $fiche->effectif_final]);
        $this->assertSame(210, (int) $this->pondeuses->fresh()->current_quantity);
    }

    public function test_modifier_une_entree_au_poste_recalcule_les_jours_suivants_et_la_bande(): void
    {
        $this->pousserFiche()->assertOk();
        $this->envoyer(['livestock_daily_entries' => [$this->fiche([
            'id' => 'ffff1111-0000-4000-8000-000000000002', 'entry_date' => '2026-10-15', 'ne' => 0, 'achat' => 5, 'effectif_final' => 215,
        ])]])->assertOk();
        $this->assertSame(215, (int) $this->pondeuses->fresh()->current_quantity);

        // 10 naissances ramenées à 4 : 204 le 10/10, 209 le 15/10 ; la bande suit la DERNIÈRE fiche.
        $this->pousserFiche(['ne' => 4, 'effectif_final' => 204])->assertJsonPath('livestock_daily_entries.accepted', [self::FICHE]);

        $this->assertSame([204, 209, 209], [
            (int) LivestockDailyEntry::findOrFail(self::FICHE)->effectif_final,
            (int) LivestockDailyEntry::findOrFail('ffff1111-0000-4000-8000-000000000002')->effectif_final,
            (int) $this->pondeuses->fresh()->current_quantity,
        ]);
    }

    public function test_archiver_une_entree_au_poste_remet_sa_colonne_a_zero_et_la_cascade_suit(): void
    {
        $this->pousserFiche()->assertOk();

        $this->pousserFiche(['ne' => 0, 'effectif_final' => 200])->assertJsonPath('livestock_daily_entries.accepted', [self::FICHE]);

        $fiche = LivestockDailyEntry::findOrFail(self::FICHE);
        $this->assertSame([0, 200, 200], [(int) $fiche->ne, (int) $fiche->effectif_final, (int) $this->pondeuses->fresh()->current_quantity]);
    }

    public function test_une_entree_envoyee_deux_fois_ne_compte_qu_une_fois(): void
    {
        $this->pousserFiche()->assertOk();
        $this->pousserFiche()->assertJsonPath('livestock_daily_entries.accepted', [self::FICHE]);

        $this->assertSame(1, LivestockDailyEntry::count());
        $this->assertSame(210, (int) $this->pondeuses->fresh()->current_quantity);
    }

    public function test_une_entree_datee_dans_un_exercice_clos_est_refusee_avec_le_motif_du_serveur(): void
    {
        $reponse = $this->pousserFiche(['entry_date' => '2025-12-20'])->assertOk();

        $reponse->assertJsonPath('livestock_daily_entries.accepted', []);
        $this->assertSame(
            "L'exercice 2025 est clôturé : aucune saisie ne peut être datée du 20/12/2025.",
            $reponse->json('livestock_daily_entries.rejected.0.reason'),
        );
        $this->assertSame(0, LivestockDailyEntry::count());
    }

    public function test_un_compte_sans_manage_elevage_n_ecrit_aucune_entree_de_sujets(): void
    {
        $this->jeton('comptable');

        $reponse = $this->pousserFiche()->assertOk();

        $reponse->assertJsonPath('livestock_daily_entries.accepted', []);
        $this->assertSame(0, LivestockDailyEntry::count());
        $this->assertSame(200, (int) $this->pondeuses->fresh()->current_quantity);
    }

    public function test_les_especes_du_decor_existent(): void
    {
        $this->assertSame(1, LivestockSpecies::count());
    }
}
