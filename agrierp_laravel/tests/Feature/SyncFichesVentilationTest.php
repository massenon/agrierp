<?php

namespace Tests\Feature;

use App\Actions\RecordSaleOnFicheElevageAction;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\TreasuryAccount;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Ticket 15.40 — PUSH DES FICHES : VALIDATION DE LA VENTILATION PAR CATÉGORIE, COHÉRENCE, CASCADE.
 *
 * Suite du ticket 15.39 (service d'effectif par catégorie + 10 colonnes nullables). Date figée au 15/10/2026.
 *
 * Emplacements (14.11 / 14.12) : `repro` = Reproducteur ; `sevre` = Jeune (lapins) ; `jeune` = Lapin de Chair.
 * Bande de test : lapins, effectif initial 60, départ R10 / J20 / C30. Les effectifs attendus sont des LITTÉRAUX
 * calculés à la main, jamais produits par le service.
 */
class SyncFichesVentilationTest extends TestCase
{
    use RefreshDatabase;

    private User $utilisateur;

    private LivestockSpecies $cuniculture;

    private LivestockLot $bande;

    private int $compteur = 0;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow('2026-10-15 12:00:00');

        $this->utilisateur = User::create([
            'name' => 'Animalier', 'username' => 'elevage', 'email' => 'elevage@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);

        // Ticket S1 : l'envoi du poste exige désormais le rôle qui écrit chaque table.

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);

        $this->utilisateur->assignRole('admin');

        $this->cuniculture = LivestockSpecies::create(['label' => 'Cuniculture', 'code' => 'cuniculture', 'is_active' => true]);
        $this->bande = $this->creerBande($this->cuniculture, 'LAP-2026-01', 60);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    // ============================================================ outils

    private function creerBande(LivestockSpecies $espece, string $code, int $initial): LivestockLot
    {
        return LivestockLot::create([
            'code' => $code, 'species_id' => $espece->id, 'stage' => 'croissance',
            'initial_quantity' => $initial, 'current_quantity' => $initial,
            'created_date' => '2026-09-01', 'status' => 'actif', 'is_active' => true,
        ]);
    }

    private function uuid(int $n): string
    {
        return sprintf('%08d-0000-4000-8000-000000000000', $n);
    }

    /** Fiche à pousser (mouvements à 0 par défaut). */
    private function fiche(string $jour, array $en_plus = [], ?LivestockLot $bande = null, ?int $n = null): array
    {
        $n ??= ++$this->compteur;

        return array_merge([
            'id' => $this->uuid($n), 'lot_id' => ($bande ?? $this->bande)->id, 'entry_date' => $jour,
            'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0,
        ], $en_plus);
    }

    private function pousser(array $fiches, array $ventes = [])
    {
        $corps = ['livestock_daily_entries' => $fiches];
        if ($ventes !== []) {
            $corps['sales'] = $ventes;
        }

        return $this->actingAs($this->utilisateur, 'sanctum')->postJson('/api/sync/push', $corps);
    }

    /** Un départ saisi en base : 10 / 20 / 30 au début du 10/10/2026 (effectif initial 60). Hors push. */
    private function teteEnBase(?LivestockLot $bande = null, string $jour = '2026-10-10'): LivestockDailyEntry
    {
        $f = new LivestockDailyEntry([
            'lot_id' => ($bande ?? $this->bande)->id, 'entry_date' => $jour,
            'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0,
            'mort_repro' => 0, 'mort_sevre' => 0, 'mort_jeune' => 0,
            'don_repro' => 0, 'don_sevre' => 0, 'don_jeune' => 0, 'passage_sevre_jeune' => 0,
            'cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30,
            'cat_eff_repro' => 10, 'cat_eff_sevre' => 20, 'cat_eff_jeune' => 30,
        ]);
        $f->effectif_final = 60;
        $f->id = $this->uuid(9000);
        $f->save();

        return $f;
    }

    private function enBase(string $id): LivestockDailyEntry
    {
        return LivestockDailyEntry::findOrFail($id);
    }

    private function cats(string $id): array
    {
        $f = $this->enBase($id);

        return [$f->cat_eff_repro, $f->cat_eff_sevre, $f->cat_eff_jeune];
    }

    private function motif($reponse, int $i = 0): string
    {
        return (string) $reponse->json("livestock_daily_entries.rejected.$i.reason");
    }

    private const DIX_CLES = [
        'mort_repro', 'mort_sevre', 'mort_jeune', 'don_repro', 'don_sevre', 'don_jeune',
        'passage_sevre_jeune', 'cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune',
    ];

    // ============================================================ (1) VALIDATION DES 10 COLONNES

    public function test_une_valeur_negative_refuse_la_fiche_entiere_avec_un_motif_francais_sur_chacune_des_dix_cles(): void
    {
        foreach (self::DIX_CLES as $cle) {
            LivestockDailyEntry::query()->delete();
            $mauvaise = $this->fiche('2026-10-14', [$cle => -1], null, 1);
            $bonne = $this->fiche('2026-10-13', ['mort' => 0], null, 2);

            $reponse = $this->pousser([$mauvaise, $bonne])->assertOk();

            $this->assertSame([$this->uuid(2)], $reponse->json('livestock_daily_entries.accepted'), $cle);
            $this->assertSame($this->uuid(1), $reponse->json('livestock_daily_entries.rejected.0.id'), $cle);
            $motif = $this->motif($reponse);
            $this->assertStringContainsString('minimum', $motif, $cle);
            $this->assertDoesNotMatchRegularExpression('/\b(The|field|must|least|greater)\b/', $motif, $cle);
            $this->assertDoesNotMatchRegularExpression('/\b'.preg_quote($cle, '/').'\b/', $motif, "$cle : libellé français attendu, pas le nom technique");
            $this->assertNull(LivestockDailyEntry::find($this->uuid(1)), "$cle : la fiche refusée ne s'écrit pas");
        }
    }

    public function test_une_valeur_non_entiere_est_refusee_en_francais(): void
    {
        foreach (self::DIX_CLES as $cle) {
            foreach (['abc', 1.5] as $valeur) {
                LivestockDailyEntry::query()->delete();
                $reponse = $this->pousser([$this->fiche('2026-10-14', [$cle => $valeur], null, 1)])->assertOk();

                $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'), $cle.'='.json_encode($valeur));
                $this->assertStringContainsString('nombre entier', $this->motif($reponse), $cle);
            }
        }
    }

    public function test_les_dix_cles_acceptent_zero_et_un_null_vaut_cle_absente(): void
    {
        $f = $this->fiche('2026-10-14', array_fill_keys(self::DIX_CLES, null), null, 1);
        $reponse = $this->pousser([$f])->assertOk();

        $this->assertSame([$this->uuid(1)], $reponse->json('livestock_daily_entries.accepted'));
        foreach (self::DIX_CLES as $cle) {
            $this->assertNull($this->enBase($this->uuid(1))->{$cle}, "$cle : un null n'est pas écrit comme un zéro");
        }
    }

    public function test_un_null_n_efface_pas_une_ventilation_deja_saisie(): void
    {
        $id = $this->uuid(1);
        $this->pousser([$this->fiche('2026-10-14', ['mort' => 3, 'mort_repro' => 1, 'mort_sevre' => 1, 'mort_jeune' => 1, 'passage_sevre_jeune' => 0], null, 1)])->assertOk();

        $this->pousser([$this->fiche('2026-10-14', ['mort' => 3, 'mort_repro' => null, 'mort_sevre' => null, 'mort_jeune' => null, 'passage_sevre_jeune' => null], null, 1)])->assertOk();

        $f = $this->enBase($id);
        $this->assertSame([1, 1, 1, 0], [$f->mort_repro, $f->mort_sevre, $f->mort_jeune, $f->passage_sevre_jeune]);
    }

    public function test_une_fiche_ventilee_valide_est_ecrite_telle_quelle(): void
    {
        $f = $this->fiche('2026-10-14', [
            'mort' => 6, 'mort_repro' => 1, 'mort_sevre' => 2, 'mort_jeune' => 3,
            'don' => 3, 'don_repro' => 0, 'don_sevre' => 1, 'don_jeune' => 2, 'passage_sevre_jeune' => 4,
        ], null, 1);
        $reponse = $this->pousser([$f])->assertOk();

        $this->assertSame([$this->uuid(1)], $reponse->json('livestock_daily_entries.accepted'));
        $e = $this->enBase($this->uuid(1));
        $this->assertSame([1, 2, 3, 0, 1, 2, 4], [$e->mort_repro, $e->mort_sevre, $e->mort_jeune, $e->don_repro, $e->don_sevre, $e->don_jeune, $e->passage_sevre_jeune]);
    }

    public function test_la_forme_de_la_reponse_est_inchangee(): void
    {
        $reponse = $this->pousser([$this->fiche('2026-10-14', ['mort_repro' => -1], null, 1)])->assertOk();

        // Ticket S-T9 : `merged` s'ajoute (fiche du poste réunie à celle que le serveur tient pour la même (bande, jour)).
        $this->assertSame(['accepted', 'rejected', 'merged'], array_keys($reponse->json('livestock_daily_entries')));
        $this->assertSame(['id', 'reason'], array_keys($reponse->json('livestock_daily_entries.rejected.0')));
    }

    // ============================================================ (2) cat_eff_* ET effectif_final : DÉRIVÉS

    public function test_sur_une_bande_a_chaine_cat_eff_et_effectif_final_du_client_ne_sont_pas_ecrits(): void
    {
        $this->teteEnBase();
        $f = $this->fiche('2026-10-11', [
            'mort' => 1, 'mort_repro' => 1, 'mort_sevre' => 0, 'mort_jeune' => 0,
            'cat_eff_repro' => 999, 'cat_eff_sevre' => 888, 'cat_eff_jeune' => 777, 'effectif_final' => 555,
        ], null, 1);
        $this->pousser([$f])->assertOk()->assertJsonPath('livestock_daily_entries.accepted.0', $this->uuid(1));

        // Départ 10/20/30 (total 60) ; le 11 : un reproducteur mort -> 9/20/30, total 59.
        $this->assertSame([9, 20, 30], $this->cats($this->uuid(1)));
        $this->assertSame(59, (int) $this->enBase($this->uuid(1))->effectif_final);
    }

    public function test_sur_une_bande_a_chaine_un_renvoi_avec_cat_eff_perimes_ne_les_reecrit_pas(): void
    {
        $this->teteEnBase();
        $this->pousser([$this->fiche('2026-10-11', ['mort' => 1, 'mort_repro' => 1, 'mort_sevre' => 0, 'mort_jeune' => 0], null, 1)])->assertOk();
        $avant = $this->cats($this->uuid(1));

        $this->pousser([$this->fiche('2026-10-11', [
            'mort' => 1, 'mort_repro' => 1, 'mort_sevre' => 0, 'mort_jeune' => 0,
            'cat_eff_repro' => 1, 'cat_eff_sevre' => 1, 'cat_eff_jeune' => 1,
        ], null, 1)])->assertOk();

        $this->assertSame($avant, $this->cats($this->uuid(1)));
        $this->assertSame([9, 20, 30], $this->cats($this->uuid(1)));
    }

    public function test_sans_chaine_les_cat_eff_du_client_restent_ecrits_comme_avant(): void
    {
        // Décision annoncée : sans chaîne, `cat_eff_*` est encore la SAISIE du poste actuel et du web (15.39).
        $f = $this->fiche('2026-10-14', ['cat_eff_repro' => 10, 'cat_eff_sevre' => 20, 'cat_eff_jeune' => 30], null, 1);
        $this->pousser([$f])->assertOk()->assertJsonPath('livestock_daily_entries.accepted.0', $this->uuid(1));

        $this->assertSame([10, 20, 30], $this->cats($this->uuid(1)));
    }

    public function test_effectif_final_du_client_reste_ignore_sans_chaine(): void
    {
        $this->pousser([$this->fiche('2026-10-14', ['mort' => 2, 'effectif_final' => 999], null, 1)])->assertOk();

        $this->assertSame(58, (int) $this->enBase($this->uuid(1))->effectif_final);
    }

    // ============================================================ (3) COHÉRENCE

    public function test_une_cle_de_ventilation_des_morts_exige_les_trois(): void
    {
        foreach ([['mort_repro' => 1], ['mort_repro' => 1, 'mort_sevre' => 0], ['mort_jeune' => 0]] as $cles) {
            LivestockDailyEntry::query()->delete();
            $reponse = $this->pousser([$this->fiche('2026-10-14', ['mort' => 1] + $cles, null, 1)])->assertOk();

            $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'), json_encode($cles));
            $motif = $this->motif($reponse);
            $this->assertStringContainsString('trois', $motif);
            $this->assertStringContainsString('morts', $motif);
            $this->assertNull(LivestockDailyEntry::find($this->uuid(1)));
        }
    }

    public function test_une_cle_de_ventilation_des_dons_exige_les_trois(): void
    {
        $reponse = $this->pousser([$this->fiche('2026-10-14', ['don' => 1, 'don_sevre' => 1], null, 1)])->assertOk();

        $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertStringContainsString('trois', $this->motif($reponse));
        $this->assertStringContainsString('dons', $this->motif($reponse));
    }

    public function test_mort_doit_egaler_la_somme_des_trois_mort_par_categorie(): void
    {
        foreach ([4, 2, 0] as $mort) {
            LivestockDailyEntry::query()->delete();
            $reponse = $this->pousser([$this->fiche('2026-10-14', ['mort' => $mort, 'mort_repro' => 1, 'mort_sevre' => 1, 'mort_jeune' => 1], null, 1)])->assertOk();

            $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'), "mort=$mort");
            $this->assertStringContainsString('3', $this->motif($reponse));
            $this->assertStringContainsString("($mort)", $this->motif($reponse));
        }
        LivestockDailyEntry::query()->delete();
        $ok = $this->pousser([$this->fiche('2026-10-14', ['mort' => 3, 'mort_repro' => 1, 'mort_sevre' => 1, 'mort_jeune' => 1], null, 1)])->assertOk();
        $this->assertSame([$this->uuid(1)], $ok->json('livestock_daily_entries.accepted'));
    }

    public function test_don_doit_egaler_la_somme_des_trois_don_par_categorie(): void
    {
        $reponse = $this->pousser([$this->fiche('2026-10-14', ['don' => 5, 'don_repro' => 1, 'don_sevre' => 1, 'don_jeune' => 1], null, 1)])->assertOk();
        $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertStringContainsString('dons', $this->motif($reponse));

        $ok = $this->pousser([$this->fiche('2026-10-14', ['don' => 3, 'don_repro' => 1, 'don_sevre' => 1, 'don_jeune' => 1], null, 1)])->assertOk();
        $this->assertSame([$this->uuid(1)], $ok->json('livestock_daily_entries.accepted'));
    }

    public function test_une_ventilation_sans_le_total_est_comparee_au_total_par_defaut_zero(): void
    {
        // Fiche neuve : `mort` absent vaut 0 (défaut de la base) ; la ventilation 1+0+0 ne l'égale pas.
        $f = ['id' => $this->uuid(1), 'lot_id' => $this->bande->id, 'entry_date' => '2026-10-14', 'mort_repro' => 1, 'mort_sevre' => 0, 'mort_jeune' => 0];
        $this->assertSame([], $this->pousser([$f])->json('livestock_daily_entries.accepted'));

        $f2 = ['id' => $this->uuid(2), 'lot_id' => $this->bande->id, 'entry_date' => '2026-10-14', 'mort_repro' => 0, 'mort_sevre' => 0, 'mort_jeune' => 0];
        $this->assertSame([$this->uuid(2)], $this->pousser([$f2])->json('livestock_daily_entries.accepted'));
    }

    public function test_un_total_modifie_sans_ressaisir_la_ventilation_deja_stockee_est_refuse(): void
    {
        $this->pousser([$this->fiche('2026-10-14', ['mort' => 3, 'mort_repro' => 1, 'mort_sevre' => 1, 'mort_jeune' => 1], null, 1)])->assertOk();

        $reponse = $this->pousser([$this->fiche('2026-10-14', ['mort' => 5], null, 1)])->assertOk();

        $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertSame(3, (int) $this->enBase($this->uuid(1))->mort, 'la fiche refusée ne touche pas à l\'existant');
    }

    public function test_une_fiche_incoherente_ne_bloque_pas_les_autres(): void
    {
        $mauvaise = $this->fiche('2026-10-14', ['mort' => 9, 'mort_repro' => 1, 'mort_sevre' => 0, 'mort_jeune' => 0], null, 1);
        $bonne = $this->fiche('2026-10-13', ['mort' => 1, 'mort_repro' => 1, 'mort_sevre' => 0, 'mort_jeune' => 0], null, 2);

        $reponse = $this->pousser([$mauvaise, $bonne])->assertOk();

        $this->assertSame([$this->uuid(2)], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertSame($this->uuid(1), $reponse->json('livestock_daily_entries.rejected.0.id'));
    }

    // ============================================================ (4) D7 : FICHE NON VENTILÉE SUR BANDE À CHAÎNE

    public function test_d7_morts_non_ventiles_sur_bande_a_chaine_sont_refuses_avec_un_motif_clair(): void
    {
        $this->teteEnBase();
        $reponse = $this->pousser([$this->fiche('2026-10-11', ['mort' => 2], null, 1)])->assertOk();

        $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'));
        $motif = $this->motif($reponse);
        $this->assertStringContainsString('ancien poste', $motif);
        $this->assertStringContainsString('mise à jour', $motif);
        $this->assertStringContainsString('morts', $motif);
        $this->assertNull(LivestockDailyEntry::find($this->uuid(1)));
    }

    public function test_d7_dons_non_ventiles_sur_bande_a_chaine_sont_refuses(): void
    {
        $this->teteEnBase();
        $reponse = $this->pousser([$this->fiche('2026-10-11', ['don' => 1], null, 1)])->assertOk();

        $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertStringContainsString('ancien poste', $this->motif($reponse));
        $this->assertStringContainsString('dons', $this->motif($reponse));
    }

    public function test_d7_ne_touche_pas_les_autres_fiches_de_l_envoi(): void
    {
        $this->teteEnBase();
        $reponse = $this->pousser([
            $this->fiche('2026-10-11', ['mort' => 2], null, 1),
            $this->fiche('2026-10-12', ['mort' => 1, 'mort_repro' => 0, 'mort_sevre' => 1, 'mort_jeune' => 0], null, 2),
        ])->assertOk();

        $this->assertSame([$this->uuid(2)], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertSame($this->uuid(1), $reponse->json('livestock_daily_entries.rejected.0.id'));
    }

    public function test_d7_une_fiche_sans_morts_ni_dons_est_acceptee_avec_ses_mouvements_connus_a_zero(): void
    {
        $this->teteEnBase();
        $this->pousser([$this->fiche('2026-10-11', ['achat' => 2, 'ne' => 5], null, 1)])
            ->assertOk()->assertJsonPath('livestock_daily_entries.accepted.0', $this->uuid(1));

        $e = $this->enBase($this->uuid(1));
        $this->assertSame([0, 0, 0, 0, 0, 0, 0], [$e->mort_repro, $e->mort_sevre, $e->mort_jeune, $e->don_repro, $e->don_sevre, $e->don_jeune, $e->passage_sevre_jeune]);
        // Départ 10/20/30 ; achat 2 + nés 5 vont au Jeune : 10/27/30, total 67 — pas de catégorie « inconnue ».
        $this->assertSame([10, 27, 30], $this->cats($this->uuid(1)));
        $this->assertSame(67, (int) $e->effectif_final);
    }

    public function test_d7_une_fiche_ventilee_sur_bande_a_chaine_calcule_ses_categories(): void
    {
        $this->teteEnBase();
        $this->pousser([$this->fiche('2026-10-11', [
            'vente' => 4, 'mort' => 3, 'mort_repro' => 1, 'mort_sevre' => 0, 'mort_jeune' => 2,
            'don' => 1, 'don_repro' => 0, 'don_sevre' => 1, 'don_jeune' => 0,
        ], null, 1)])->assertOk()->assertJsonPath('livestock_daily_entries.accepted.0', $this->uuid(1));

        // R = 10-1 = 9 ; J = 20-1 = 19 ; C = 30-4-2 = 24 ; total 60-4-3-1 = 52 (somme 52).
        $this->assertSame([9, 19, 24], $this->cats($this->uuid(1)));
        $this->assertSame(52, (int) $this->enBase($this->uuid(1))->effectif_final);
    }

    public function test_d7_une_fiche_anterieure_au_depart_n_est_pas_dans_la_chaine_et_reste_acceptee(): void
    {
        $this->teteEnBase(null, '2026-10-10');
        $reponse = $this->pousser([$this->fiche('2026-10-08', ['mort' => 2], null, 1)])->assertOk();

        $this->assertSame([$this->uuid(1)], $reponse->json('livestock_daily_entries.accepted'));
    }

    public function test_d7_la_fiche_qui_fixe_le_depart_doit_elle_aussi_etre_ventilee_si_elle_a_des_morts(): void
    {
        $reponse = $this->pousser([$this->fiche('2026-10-10', [
            'mort' => 2, 'cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30,
        ], null, 1)])->assertOk();

        $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertStringContainsString('ancien poste', $this->motif($reponse));
    }

    public function test_sans_chaine_les_fiches_non_ventilees_sont_acceptees_comme_avant(): void
    {
        $reponse = $this->pousser([
            $this->fiche('2026-10-12', ['mort' => 2, 'don' => 1, 'achat' => 1, 'ne' => 2], null, 1),
            $this->fiche('2026-10-13', ['mort' => 0, 'don' => 0], null, 2),
        ])->assertOk();

        $this->assertSame([$this->uuid(1), $this->uuid(2)], $reponse->json('livestock_daily_entries.accepted'));
        $e = $this->enBase($this->uuid(1));
        $this->assertNull($e->mort_repro, 'sans chaîne, aucune ventilation « zéro » n\'est inventée');
        $this->assertNull($e->cat_eff_repro);
        $this->assertSame(60 + 1 + 2 - 2 - 1, (int) $e->effectif_final);
    }

    public function test_sans_chaine_les_null_15_38_et_fiches_reduites_15_34_sont_inchanges(): void
    {
        $r = $this->pousser([$this->fiche('2026-10-12', ['mort' => null, 'vente' => null], null, 1)])->assertOk();
        $this->assertSame([$this->uuid(1)], $r->json('livestock_daily_entries.accepted'));

        $reduite = ['id' => $this->uuid(2), 'lot_id' => $this->bande->id, 'entry_date' => '2026-10-13'];
        $r = $this->pousser([$reduite])->assertOk();
        $this->assertSame([], $r->json('livestock_daily_entries.accepted'));
        $this->assertStringContainsString('Fiche refusée', $this->motif($r));
    }

    // ============================================================ (5) DÉPART (D4)

    public function test_depart_accepte_sur_la_fiche_de_depart_d_une_bande_sans_chaine(): void
    {
        $f = $this->fiche('2026-10-10', ['cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30], null, 1);
        $this->pousser([$f])->assertOk()->assertJsonPath('livestock_daily_entries.accepted.0', $this->uuid(1));

        $e = $this->enBase($this->uuid(1));
        $this->assertSame([10, 20, 30], [$e->cat_depart_repro, $e->cat_depart_sevre, $e->cat_depart_jeune]);
        $this->assertSame([10, 20, 30], $this->cats($this->uuid(1)), 'la chaîne est calculée dès l\'acceptation du départ');
    }

    public function test_depart_dont_la_somme_differe_du_total_de_depart_est_refuse(): void
    {
        $f = $this->fiche('2026-10-10', ['cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 31], null, 1);
        $reponse = $this->pousser([$f])->assertOk();

        $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertStringContainsString('61', $this->motif($reponse));
        $this->assertStringContainsString('60', $this->motif($reponse));
        $this->assertNull(LivestockDailyEntry::find($this->uuid(1)));
    }

    public function test_depart_incomplet_est_refuse(): void
    {
        $f = $this->fiche('2026-10-10', ['cat_depart_repro' => 10, 'cat_depart_sevre' => 50], null, 1);
        $reponse = $this->pousser([$f])->assertOk();

        $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertStringContainsString('incomplet', $this->motif($reponse));
    }

    public function test_le_total_de_depart_est_l_effectif_au_debut_du_jour_pas_apres_les_mouvements(): void
    {
        // Veille : 60 - 5 = 55 au début du 10/10. Un départ de 60 est donc refusé, un départ de 55 accepté.
        $this->pousser([$this->fiche('2026-10-09', ['mort' => 5], null, 1)])->assertOk();

        $refus = $this->pousser([$this->fiche('2026-10-10', ['cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30], null, 2)])->assertOk();
        $this->assertSame([], $refus->json('livestock_daily_entries.accepted'));

        $ok = $this->pousser([$this->fiche('2026-10-10', ['cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 25], null, 2)])->assertOk();
        $this->assertSame([$this->uuid(2)], $ok->json('livestock_daily_entries.accepted'));
    }

    public function test_les_mouvements_du_jour_s_appliquent_apres_le_depart(): void
    {
        $this->pousser([$this->fiche('2026-10-10', [
            'cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30,
            'mort' => 1, 'mort_repro' => 1, 'mort_sevre' => 0, 'mort_jeune' => 0,
        ], null, 1)])->assertOk()->assertJsonPath('livestock_daily_entries.accepted.0', $this->uuid(1));

        $this->assertSame([9, 20, 30], $this->cats($this->uuid(1)));
        $this->assertSame(59, (int) $this->enBase($this->uuid(1))->effectif_final);
    }

    public function test_depart_refuse_si_la_bande_a_deja_une_chaine_avec_la_date_du_depart(): void
    {
        $this->teteEnBase(null, '2026-10-10');
        $f = $this->fiche('2026-10-12', ['cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30], null, 1);
        $reponse = $this->pousser([$f])->assertOk();

        $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertStringContainsString('effectif de départ déjà fixé le 10/10/2026', $this->motif($reponse));
        $this->assertNull(LivestockDailyEntry::find($this->uuid(1)));
    }

    public function test_depart_deja_fixe_refuse_aussi_sur_une_fiche_anterieure_et_pour_des_valeurs_differentes(): void
    {
        $tete = $this->teteEnBase(null, '2026-10-10');

        $avant = $this->pousser([$this->fiche('2026-10-08', ['cat_depart_repro' => 60, 'cat_depart_sevre' => 0, 'cat_depart_jeune' => 0], null, 1)])->assertOk();
        $this->assertStringContainsString('déjà fixé le 10/10/2026', $this->motif($avant));

        $autre = $this->pousser([['id' => $tete->id, 'lot_id' => $this->bande->id, 'entry_date' => '2026-10-10', 'cat_depart_repro' => 20, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 20]])->assertOk();
        $this->assertSame([], $autre->json('livestock_daily_entries.accepted'));
        $this->assertStringContainsString('déjà fixé le 10/10/2026', $this->motif($autre));
        $this->assertSame(10, (int) $this->enBase($tete->id)->cat_depart_repro);
    }

    public function test_un_depart_incomplet_est_refuse_aussi_quand_la_chaine_existe_deja(): void
    {
        $this->teteEnBase();
        $reponse = $this->pousser([$this->fiche('2026-10-12', ['cat_depart_repro' => 5], null, 1)])->assertOk();

        $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertStringContainsString('déjà fixé', $this->motif($reponse));
    }

    public function test_renvoyer_a_l_identique_la_fiche_de_depart_est_accepte_et_idempotent(): void
    {
        $f = $this->fiche('2026-10-10', ['cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30], null, 1);
        $this->pousser([$f])->assertOk();
        $maj = $this->enBase($this->uuid(1))->updated_at->toDateTimeString();

        Carbon::setTestNow('2026-10-15 18:00:00');
        $reponse = $this->pousser([$f])->assertOk();

        $this->assertSame([$this->uuid(1)], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertSame($maj, $this->enBase($this->uuid(1))->updated_at->toDateTimeString());
    }

    public function test_depart_refuse_sur_une_espece_non_prise_en_charge(): void
    {
        $avi = LivestockSpecies::create(['label' => 'Aviculture', 'code' => 'aviculture', 'is_active' => true]);
        $poulets = $this->creerBande($avi, 'AVI-2026-01', 60);
        $f = $this->fiche('2026-10-10', ['cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30], $poulets, 1);
        $reponse = $this->pousser([$f])->assertOk();

        $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertStringContainsString('lapins et les porcs', $this->motif($reponse));
    }

    public function test_depart_des_porcs_est_accepte_et_calcule(): void
    {
        $porcine = LivestockSpecies::create(['label' => 'Porciculture', 'code' => 'porciculture', 'is_active' => true]);
        $porcs = $this->creerBande($porcine, 'POR-2026-01', 120);
        $this->pousser([$this->fiche('2026-10-10', [
            'cat_depart_repro' => 10, 'cat_depart_sevre' => 24, 'cat_depart_jeune' => 86,
            'achat' => 3, 'ne' => 9, 'mort' => 2, 'mort_repro' => 0, 'mort_sevre' => 2, 'mort_jeune' => 0,
        ], $porcs, 1)])->assertOk()->assertJsonPath('livestock_daily_entries.accepted.0', $this->uuid(1));

        // Plan du 14/10 : 13 / 31 / 86, total 130 (l'achat de porcs gonfle le Reproducteur, D11).
        $this->assertSame([13, 31, 86], $this->cats($this->uuid(1)));
        $this->assertSame(130, (int) $this->enBase($this->uuid(1))->effectif_final);
    }

    // ============================================================ (6) CASCADE

    public function test_une_fiche_poussee_sur_un_jour_anterieur_recalcule_les_fiches_suivantes_total_et_categories(): void
    {
        $this->teteEnBase(null, '2026-10-10');
        $this->pousser([$this->fiche('2026-10-12', ['vente' => 4, 'mort' => 2, 'mort_repro' => 0, 'mort_sevre' => 0, 'mort_jeune' => 2], null, 1)])->assertOk();
        // 12/10 : total 60-6 = 54 ; 10 / 20 / 24.
        $this->assertSame(54, (int) $this->enBase($this->uuid(1))->effectif_final);
        $this->assertSame([10, 20, 24], $this->cats($this->uuid(1)));

        // Saisie rétroactive du 11/10 : achat 2, nés 5 (-> Jeune).
        $this->pousser([$this->fiche('2026-10-11', ['achat' => 2, 'ne' => 5], null, 2)])->assertOk();

        $this->assertSame(67, (int) $this->enBase($this->uuid(2))->effectif_final);
        $this->assertSame([10, 27, 30], $this->cats($this->uuid(2)));
        $this->assertSame(61, (int) $this->enBase($this->uuid(1))->effectif_final, 'cascade sur le total : 67 - 6');
        $this->assertSame([10, 27, 24], $this->cats($this->uuid(1)), 'cascade sur les catégories');
        $this->assertSame(61, (int) $this->bande->fresh()->current_quantity, 'la bande suit la dernière fiche');
    }

    public function test_sans_chaine_la_cascade_du_total_et_de_la_bande_est_aussi_declenchee_15_31_refermee(): void
    {
        // CHANGEMENT DE COMPORTEMENT annoncé : avant 15.40, seule une vente déclenchait la cascade.
        $this->pousser([$this->fiche('2026-10-12', ['mort' => 6], null, 1)])->assertOk();
        $this->assertSame(54, (int) $this->enBase($this->uuid(1))->effectif_final);

        $this->pousser([$this->fiche('2026-10-11', ['achat' => 10], null, 2)])->assertOk();

        $this->assertSame(70, (int) $this->enBase($this->uuid(2))->effectif_final);
        $this->assertSame(64, (int) $this->enBase($this->uuid(1))->effectif_final, 'fiche suivante recalculée : 70 - 6');
        $this->assertSame(64, (int) $this->bande->fresh()->current_quantity);
    }

    public function test_une_seule_cascade_par_bande_en_fin_de_lot_triee_par_bande_et_jour(): void
    {
        $espece = LivestockSpecies::create(['label' => 'Porciculture', 'code' => 'porciculture', 'is_active' => true]);
        $autre = $this->creerBande($espece, 'POR-2026-01', 50);

        $appels = [];
        $this->app->bind(RecordSaleOnFicheElevageAction::class, function () use (&$appels) {
            return new class($appels) extends RecordSaleOnFicheElevageAction
            {
                public function __construct(private array &$appels) {}

                public function recalculerEnCascade(string $lotId, string $apresDate): void
                {
                    $this->appels[] = [$lotId, $apresDate];
                    parent::recalculerEnCascade($lotId, $apresDate);
                }
            };
        });

        $this->pousser([
            $this->fiche('2026-10-13', ['mort' => 1], null, 1),
            $this->fiche('2026-10-12', ['mort' => 1], $autre, 2),
            $this->fiche('2026-10-11', ['mort' => 1], null, 3),
            $this->fiche('2026-10-14', ['mort' => 1], $autre, 4),
            $this->fiche('2026-10-12', ['mort' => 1], null, 5),
        ])->assertOk();

        $this->assertCount(2, $appels, 'une cascade par bande, pas une par fiche');
        $parBande = [];
        foreach ($appels as [$lot, $date]) {
            $parBande[$lot] = $date;
        }
        $this->assertSame('2026-10-11', $parBande[$this->bande->id], 'cascade depuis le plus ancien jour poussé');
        $this->assertSame('2026-10-12', $parBande[$autre->id]);
        $this->assertSame(57, (int) $this->bande->fresh()->current_quantity);
        $this->assertSame(48, (int) $autre->fresh()->current_quantity);
    }

    public function test_aucune_cascade_pour_une_bande_dont_toutes_les_fiches_sont_refusees(): void
    {
        $appels = 0;
        $this->app->bind(RecordSaleOnFicheElevageAction::class, function () use (&$appels) {
            return new class($appels) extends RecordSaleOnFicheElevageAction
            {
                public function __construct(private int &$appels) {}

                public function recalculerEnCascade(string $lotId, string $apresDate): void
                {
                    $this->appels++;
                    parent::recalculerEnCascade($lotId, $apresDate);
                }
            };
        });

        $this->pousser([$this->fiche('2026-10-13', ['mort' => -1], null, 1)])->assertOk();

        $this->assertSame(0, $appels);
    }

    public function test_l_ordre_d_envoi_ne_change_ni_le_resultat_ni_l_ordre_de_la_reponse(): void
    {
        $this->teteEnBase(null, '2026-10-08');
        $a = $this->fiche('2026-10-09', ['mort' => 1, 'mort_repro' => 1, 'mort_sevre' => 0, 'mort_jeune' => 0], null, 1);
        $b = $this->fiche('2026-10-10', ['vente' => 5], null, 2);
        $c = $this->fiche('2026-10-11', ['achat' => 3], null, 3);

        $reponse = $this->pousser([$c, $a, $b])->assertOk();

        $this->assertSame([$this->uuid(3), $this->uuid(1), $this->uuid(2)], $reponse->json('livestock_daily_entries.accepted'), 'ordre de la réponse = ordre d\'envoi');
        $this->assertSame([59, 54, 57], [
            (int) $this->enBase($this->uuid(1))->effectif_final,
            (int) $this->enBase($this->uuid(2))->effectif_final,
            (int) $this->enBase($this->uuid(3))->effectif_final,
        ]);
        $this->assertSame([9, 20, 30], $this->cats($this->uuid(1)));
        $this->assertSame([9, 20, 25], $this->cats($this->uuid(2)));
        $this->assertSame([9, 23, 25], $this->cats($this->uuid(3)));
        $this->assertSame(57, (int) $this->bande->fresh()->current_quantity);
    }

    public function test_le_total_de_depart_tient_compte_d_une_fiche_precedente_du_meme_envoi_envoyee_apres(): void
    {
        // Envoi [10/10 départ, 09/10 morts 5] : au début du 10/10 l'effectif est 55 (et non 60).
        $depart = $this->fiche('2026-10-10', ['cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 25], null, 1);
        $veille = $this->fiche('2026-10-09', ['mort' => 5], null, 2);

        $reponse = $this->pousser([$depart, $veille])->assertOk();

        $this->assertSame([$this->uuid(1), $this->uuid(2)], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertSame([10, 20, 25], $this->cats($this->uuid(1)));
    }

    public function test_renvoi_identique_ne_change_aucun_updated_at(): void
    {
        $this->teteEnBase(null, '2026-10-10');
        $lot = [
            $this->fiche('2026-10-11', ['achat' => 2, 'ne' => 5], null, 1),
            $this->fiche('2026-10-12', ['vente' => 4, 'mort' => 2, 'mort_repro' => 0, 'mort_sevre' => 0, 'mort_jeune' => 2], null, 2),
        ];
        $this->pousser($lot)->assertOk();
        $photo = fn () => [
            DB::table('livestock_daily_entries')->orderBy('entry_date')->pluck('updated_at', 'id')->all(),
            DB::table('livestock_lots')->where('id', $this->bande->id)->value('updated_at'),
        ];
        $avant = $photo();

        Carbon::setTestNow('2026-10-15 20:00:00');
        $reponse = $this->pousser($lot)->assertOk();

        $this->assertCount(2, $reponse->json('livestock_daily_entries.accepted'));
        $this->assertSame($avant, $photo(), 'un renvoi identique ne réécrit rien');
    }

    public function test_une_fiche_poussee_avec_une_vente_du_meme_envoi_sur_bande_a_chaine_ne_double_pas(): void
    {
        $this->teteEnBase(null, '2026-10-10');
        foreach ([['411', 'Clients', 4], ['531', 'Caisse', 5], ['701', 'Ventes', 7], ['443', 'TVA collectée', 4]] as [$code, $libelle, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $libelle, 'class' => $classe, 'is_active' => true]);
        }
        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
        TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);
        $categorie = ProductCategory::create(['label' => 'Lapins', 'is_active' => true]);
        $produit = Product::create([
            'sku' => 'LAP-001', 'name' => 'Lapin de chair', 'category_id' => $categorie->id, 'species_id' => $this->cuniculture->id,
            'unit' => 'u', 'pricing_mode' => 'fourchette', 'price_min' => 3_000, 'price_max' => 4_000, 'tva_rate' => 0,
            'stock_qty' => 50, 'is_active' => true,
        ]);

        $fiche = $this->fiche('2026-10-13', ['vente' => 6], null, 1);
        $vente = [
            'id' => '11111111-1111-4111-8111-111111111111', 'payment_mode' => 'especes', 'sold_at' => '2026-10-13 09:00:00',
            'subtotal' => 21_000, 'discount' => 0, 'total' => 21_000, 'status' => 'validee',
            'lines' => [['product_id' => $produit->id, 'lot_id' => $this->bande->id, 'qty' => 6, 'unit_price' => 3_500, 'manual_total_amount' => 21_000]],
        ];
        $reponse = $this->pousser([$fiche], [$vente])->assertOk();

        $this->assertSame([$this->uuid(1)], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertContains($vente['id'], $reponse->json('sales.accepted'));
        $this->assertSame(6, (int) $this->enBase($this->uuid(1))->vente);
        $this->assertSame([10, 20, 24], $this->cats($this->uuid(1)));
        $this->assertSame(54, (int) $this->bande->fresh()->current_quantity);
    }

    // ============================================================ (7) porteUneColonneDeSaisie

    private function reduite(array $en_plus = [], int $n = 1): array
    {
        return array_merge(['id' => $this->uuid($n), 'lot_id' => $this->bande->id, 'entry_date' => '2026-10-13'], $en_plus);
    }

    public function test_cat_eff_ne_compte_pas_comme_saisie(): void
    {
        foreach ([['cat_eff_repro' => 5], ['cat_eff_sevre' => 0], ['cat_eff_jeune' => 3, 'effectif_final' => 9], ['cat_eff_repro' => 1, 'cat_eff_sevre' => 1, 'cat_eff_jeune' => 1]] as $en_plus) {
            LivestockDailyEntry::query()->delete();
            $reponse = $this->pousser([$this->reduite($en_plus)])->assertOk();

            $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'), json_encode($en_plus));
            $this->assertStringContainsString('Fiche refusée', $this->motif($reponse));
            $this->assertSame(0, LivestockDailyEntry::count());
        }
    }

    public function test_les_dix_cles_a_null_ne_comptent_pas_comme_saisie(): void
    {
        $reponse = $this->pousser([$this->reduite(array_fill_keys(self::DIX_CLES, null))])->assertOk();

        $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertSame(0, LivestockDailyEntry::count());
    }

    public function test_une_valeur_non_nulle_sur_une_cle_de_ventilation_compte_comme_saisie(): void
    {
        // Décision : une ventilation à zéro est une information réelle (« connu à zéro »), comme `mort = 0` (15.34).
        $zeros = ['mort_repro' => 0, 'mort_sevre' => 0, 'mort_jeune' => 0];
        $reponse = $this->pousser([$this->reduite($zeros)])->assertOk();
        $this->assertSame([$this->uuid(1)], $reponse->json('livestock_daily_entries.accepted'));

        LivestockDailyEntry::query()->delete();
        $reponse = $this->pousser([$this->reduite(['passage_sevre_jeune' => 0])])->assertOk();
        $this->assertSame([$this->uuid(1)], $reponse->json('livestock_daily_entries.accepted'));

        LivestockDailyEntry::query()->delete();
        $depart = ['cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30];
        $reponse = $this->pousser([$this->reduite($depart + ['entry_date' => '2026-10-10'])])->assertOk();
        $this->assertSame([$this->uuid(1)], $reponse->json('livestock_daily_entries.accepted'));
    }

    public function test_la_fiche_reduite_de_f0_90_n_est_pas_affectee(): void
    {
        // Inconnue : refusée (15.34), bande sans chaîne comme à chaîne.
        $inconnue = $this->pousser([$this->reduite()])->assertOk();
        $this->assertStringContainsString('Fiche refusée', $this->motif($inconnue));

        // Connue, sur bande à chaîne : acceptée, RIEN n'est écrit (pas même les « zéros connus »).
        $this->teteEnBase();
        $f = new LivestockDailyEntry(['lot_id' => $this->bande->id, 'entry_date' => '2026-10-13', 'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 3, 'don' => 0]);
        $f->id = $this->uuid(2);
        $f->effectif_final = 57;
        $f->save();
        $avant = LivestockDailyEntry::find($this->uuid(2))->only(['mort_repro', 'mort_sevre', 'mort_jeune', 'don_repro', 'passage_sevre_jeune', 'vente', 'updated_at']);

        $reponse = $this->pousser([$this->reduite([], 2)])->assertOk();

        $this->assertSame([$this->uuid(2)], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertEquals($avant, LivestockDailyEntry::find($this->uuid(2))->only(['mort_repro', 'mort_sevre', 'mort_jeune', 'don_repro', 'passage_sevre_jeune', 'vente', 'updated_at']));
        $apres = LivestockDailyEntry::find($this->uuid(2));
        $this->assertNull($apres->mort_repro, 'une fiche réduite ne pose aucun zéro connu');
        $this->assertNull($apres->passage_sevre_jeune);
    }

    public function test_fiche_reduite_connue_dont_les_morts_stockes_ne_sont_pas_ventiles_n_est_pas_refusee_par_d7(): void
    {
        $this->teteEnBase();
        $f = new LivestockDailyEntry(['lot_id' => $this->bande->id, 'entry_date' => '2026-10-13', 'achat' => 0, 'ne' => 0, 'mort' => 2, 'vente' => 0, 'don' => 0]);
        $f->id = $this->uuid(2);
        $f->effectif_final = 58;
        $f->save();

        $reponse = $this->pousser([$this->reduite([], 2)])->assertOk();

        $this->assertSame([$this->uuid(2)], $reponse->json('livestock_daily_entries.accepted'));
    }

    // ============================================================ (8) PASSAGE DE STADE (D3)

    public function test_passage_superieur_a_la_categorie_source_est_refuse_en_francais(): void
    {
        $this->teteEnBase();
        $reponse = $this->pousser([$this->fiche('2026-10-11', ['passage_sevre_jeune' => 21], null, 1)])->assertOk();

        $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'));
        $motif = $this->motif($reponse);
        $this->assertStringContainsString('Passage de stade refusé', $motif);
        $this->assertStringContainsString('21', $motif);
        $this->assertStringContainsString('20', $motif);
        $this->assertNull(LivestockDailyEntry::find($this->uuid(1)));
    }

    public function test_passage_egal_a_la_source_est_accepte_et_transfere_sans_changer_le_total(): void
    {
        $this->teteEnBase();
        $this->pousser([$this->fiche('2026-10-11', ['passage_sevre_jeune' => 20], null, 1)])
            ->assertOk()->assertJsonPath('livestock_daily_entries.accepted.0', $this->uuid(1));

        $this->assertSame([10, 0, 50], $this->cats($this->uuid(1)));
        $this->assertSame(60, (int) $this->enBase($this->uuid(1))->effectif_final);
    }

    public function test_la_source_est_celle_apres_les_autres_mouvements_du_jour(): void
    {
        // Lecture retenue par 15.39 : source = veille + achats/nés - morts - dons du jour.
        // 20 + 5 (nés) - 3 (morts) = 22 : passage 22 accepté, 23 refusé.
        $this->teteEnBase();
        $base = ['ne' => 5, 'mort' => 3, 'mort_repro' => 0, 'mort_sevre' => 3, 'mort_jeune' => 0];

        $ok = $this->pousser([$this->fiche('2026-10-11', $base + ['passage_sevre_jeune' => 22], null, 1)])->assertOk();
        $this->assertSame([$this->uuid(1)], $ok->json('livestock_daily_entries.accepted'));
        $this->assertSame([10, 0, 52], $this->cats($this->uuid(1)));

        $ko = $this->pousser([$this->fiche('2026-10-12', $base + ['passage_sevre_jeune' => 99], null, 2)])->assertOk();
        $this->assertSame([], $ko->json('livestock_daily_entries.accepted'));

        // Au 13/10 la veille est le 11/10 (10/0/52) : source = 0 - 3, ramenée à 0 ; tout passage est refusé.
        $ko2 = $this->pousser([$this->fiche('2026-10-13', ['mort' => 3, 'mort_repro' => 0, 'mort_sevre' => 3, 'mort_jeune' => 0, 'passage_sevre_jeune' => 1000], null, 3)])->assertOk();
        $this->assertSame([], $ko2->json('livestock_daily_entries.accepted'));
    }

    public function test_les_morts_du_jour_reduisent_la_source_du_passage(): void
    {
        $this->teteEnBase();
        $reponse = $this->pousser([$this->fiche('2026-10-11', [
            'mort' => 5, 'mort_repro' => 0, 'mort_sevre' => 5, 'mort_jeune' => 0, 'passage_sevre_jeune' => 16,
        ], null, 1)])->assertOk();

        // Source = 20 - 5 = 15 < 16.
        $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertStringContainsString('15', $this->motif($reponse));
    }

    public function test_un_depart_identique_a_celui_de_la_tete_sur_une_autre_fiche_est_refuse(): void
    {
        $this->teteEnBase(null, '2026-10-10');
        $reponse = $this->pousser([$this->fiche('2026-10-12', ['cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30], null, 1)])->assertOk();

        $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertNull($this->enBase($this->uuid(9000))->cat_depart_repro === null ? 1 : null);
        $this->assertNull(LivestockDailyEntry::find($this->uuid(1)));
    }

    public function test_une_fiche_existante_non_tete_ne_peut_pas_recevoir_un_depart_meme_identique(): void
    {
        $this->teteEnBase(null, '2026-10-10');
        $this->pousser([$this->fiche('2026-10-12', ['achat' => 1], null, 1)])->assertOk();

        $reponse = $this->pousser([$this->fiche('2026-10-12', ['achat' => 1, 'cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30], null, 1)])->assertOk();

        $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertNull($this->enBase($this->uuid(1))->cat_depart_repro);
    }

    public function test_la_veille_du_passage_est_celle_de_la_chaine_et_non_le_depart(): void
    {
        // 11/10 : tout le Jeune passe en Chair (20 -> 0). Le 12/10, plus rien à faire passer : un passage de 1 est refusé.
        $this->teteEnBase();
        $this->pousser([$this->fiche('2026-10-11', ['passage_sevre_jeune' => 20], null, 1)])->assertOk();

        $reponse = $this->pousser([$this->fiche('2026-10-12', ['passage_sevre_jeune' => 1], null, 2)])->assertOk();

        $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertStringContainsString("n'en compte que 0", $this->motif($reponse));
    }

    public function test_sans_chaine_le_passage_n_est_pas_controle(): void
    {
        $reponse = $this->pousser([$this->fiche('2026-10-11', ['passage_sevre_jeune' => 5000], null, 1)])->assertOk();

        $this->assertSame([$this->uuid(1)], $reponse->json('livestock_daily_entries.accepted'));
    }

    public function test_passage_refuse_ne_bloque_pas_les_autres_fiches(): void
    {
        $this->teteEnBase();
        $reponse = $this->pousser([
            $this->fiche('2026-10-11', ['passage_sevre_jeune' => 500], null, 1),
            $this->fiche('2026-10-12', ['passage_sevre_jeune' => 1], null, 2),
        ])->assertOk();

        $this->assertSame([$this->uuid(2)], $reponse->json('livestock_daily_entries.accepted'));
    }
}
