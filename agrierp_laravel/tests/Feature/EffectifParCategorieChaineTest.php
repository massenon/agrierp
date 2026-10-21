<?php

namespace Tests\Feature;

use App\Actions\RecordSaleOnFicheElevageAction;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use App\Services\EffectifParCategorieService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

/**
 * Ticket 15.39 — SERVICE D'EFFECTIF PAR CATÉGORIE : SCHÉMA, CHAÎNE D'UNE BANDE, CASCADE DES VENTES,
 * RAPPORT À BLANC. Date figée au 14/10/2026. Aucune interface, aucun push.
 *
 * Emplacements (14.11 / 14.12) : `sevre` = Jeune (lapins) / Porcelet (porcs) ; `jeune` = Lapin de
 * Chair (lapins) / Marchand (porcs). Les effectifs attendus sont des LITTÉRAUX calculés à la main
 * (plan du 14/10/2026), jamais produits par le service ; les totaux des fiches de test sont
 * posés par un recalcul local (`poserTotaux`) qui n'appelle pas le service.
 */
class EffectifParCategorieChaineTest extends TestCase
{
    use RefreshDatabase;

    private LivestockSpecies $cuniculture;

    private LivestockSpecies $porciculture;

    private LivestockLot $lapins;

    private LivestockLot $porcs;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow('2026-10-14 12:00:00');

        $this->cuniculture = LivestockSpecies::create(['label' => 'Cuniculture', 'code' => 'cuniculture', 'is_active' => true]);
        $this->porciculture = LivestockSpecies::create(['label' => 'Porciculture', 'code' => 'porciculture', 'is_active' => true]);
        $this->lapins = $this->bande($this->cuniculture, 'LAP-2026-01', 60);
        $this->porcs = $this->bande($this->porciculture, 'POR-2026-01', 120);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function bande(LivestockSpecies $espece, string $code, int $initial): LivestockLot
    {
        return LivestockLot::create([
            'code' => $code, 'species_id' => $espece->id, 'stage' => 'croissance',
            'initial_quantity' => $initial, 'current_quantity' => $initial,
            'created_date' => '2026-09-01', 'status' => 'actif', 'is_active' => true,
        ]);
    }

    /** Fiche posée à la main ; l'effectif total est recalculé localement, jamais par le service. */
    private function fiche(LivestockLot $lot, string $jour, array $mouvements = []): LivestockDailyEntry
    {
        $f = new LivestockDailyEntry(array_merge(
            ['lot_id' => $lot->id, 'entry_date' => $jour, 'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0],
            $mouvements,
        ));
        $f->effectif_final = 0;
        $f->save();
        $this->poserTotaux($lot);

        return $f->fresh();
    }

    /** Recalcul indépendant des totaux de TOUTE la bande (dates croissantes). */
    private function poserTotaux(LivestockLot $lot): void
    {
        $courant = (int) $lot->initial_quantity;
        foreach (LivestockDailyEntry::where('lot_id', $lot->id)->orderBy('entry_date')->get() as $f) {
            $courant = max(0, $courant + $f->achat + $f->ne - $f->mort - $f->vente - (int) $f->don);
            DB::table('livestock_daily_entries')->where('id', $f->id)->update(['effectif_final' => $courant]);
        }
    }

    /** Mouvements ventilés (morts/dons par catégorie, passage) en cohérence avec les totaux `mort`/`don`. */
    private function mv(array $m): array
    {
        $base = [
            'achat' => 0, 'ne' => 0, 'vente' => 0,
            'mort_repro' => 0, 'mort_sevre' => 0, 'mort_jeune' => 0,
            'don_repro' => 0, 'don_sevre' => 0, 'don_jeune' => 0, 'passage_sevre_jeune' => 0,
        ];
        $m = array_merge($base, $m);
        $m['mort'] = $m['mort_repro'] + $m['mort_sevre'] + $m['mort_jeune'];
        $m['don'] = $m['don_repro'] + $m['don_sevre'] + $m['don_jeune'];

        return $m;
    }

    private function cats(LivestockLot $lot, string $jour): array
    {
        $f = LivestockDailyEntry::where('lot_id', $lot->id)->whereDate('entry_date', $jour)->firstOrFail();

        return [$f->cat_eff_repro, $f->cat_eff_sevre, $f->cat_eff_jeune];
    }

    private function total(LivestockLot $lot, string $jour): int
    {
        return (int) LivestockDailyEntry::where('lot_id', $lot->id)->whereDate('entry_date', $jour)->firstOrFail()->effectif_final;
    }

    private function service(): EffectifParCategorieService
    {
        return app(EffectifParCategorieService::class);
    }

    /** Jeu lapins du plan : départ R10/J20/C30 (somme 60 = effectif initial de la bande). */
    private function jeuLapins(): void
    {
        $this->fiche($this->lapins, '2026-10-01', $this->mv(['cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30, 'achat' => 2, 'ne' => 5, 'mort_sevre' => 1]));
        $this->fiche($this->lapins, '2026-10-02', $this->mv(['vente' => 4, 'mort_repro' => 1, 'mort_jeune' => 2, 'don_sevre' => 1]));
        $this->fiche($this->lapins, '2026-10-03', $this->mv(['vente' => 30, 'mort_sevre' => 2]));
    }

    private function jeuPorcs(): void
    {
        $this->fiche($this->porcs, '2026-10-01', $this->mv(['cat_depart_repro' => 10, 'cat_depart_sevre' => 24, 'cat_depart_jeune' => 86, 'achat' => 3, 'ne' => 9, 'mort_sevre' => 2]));
        $this->fiche($this->porcs, '2026-10-02', $this->mv(['vente' => 5, 'mort_repro' => 1, 'don_jeune' => 1]));
        $this->fiche($this->porcs, '2026-10-03', $this->mv(['vente' => 2, 'mort_jeune' => 3, 'don_sevre' => 1]));
        $this->fiche($this->porcs, '2026-10-04', $this->mv(['mort_sevre' => 40]));
    }

    // ================================================================== (1) SCHÉMA

    public function test_les_dix_colonnes_existent_nullables_sans_defaut(): void
    {
        $colonnes = ['mort_repro', 'mort_sevre', 'mort_jeune', 'don_repro', 'don_sevre', 'don_jeune',
            'passage_sevre_jeune', 'cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune'];
        $infos = collect(Schema::getColumns('livestock_daily_entries'))->keyBy('name');

        foreach ($colonnes as $c) {
            $this->assertTrue(Schema::hasColumn('livestock_daily_entries', $c), $c);
            $this->assertTrue($infos[$c]['nullable'], "{$c} doit être NULLABLE (null = inconnu, jamais 0)");
            $this->assertNull($infos[$c]['default'], "{$c} sans valeur par défaut");
            $this->assertStringContainsString('int', strtolower($infos[$c]['type_name'] ?? $infos[$c]['type']), $c);
        }
    }

    public function test_les_colonnes_sont_assignables_en_masse(): void
    {
        $f = $this->fiche($this->lapins, '2026-10-01', ['mort_repro' => 2, 'cat_depart_jeune' => 7]);

        $this->assertSame(2, $f->mort_repro);
        $this->assertSame(7, $f->cat_depart_jeune);
        $this->assertNull($f->mort_sevre, 'une colonne non saisie reste NULL, pas 0');
        $this->assertNull($f->passage_sevre_jeune);
    }

    public function test_la_migration_est_idempotente_et_son_down_inverse_l_up(): void
    {
        $fichier = collect(glob(database_path('migrations/*effectif_par_categorie*.php')))->first();
        $this->assertNotNull($fichier, 'migration introuvable');
        $migration = require $fichier;

        $migration->up(); // déjà appliquée : rejouer ne doit rien casser
        $this->assertTrue(Schema::hasColumn('livestock_daily_entries', 'mort_repro'));

        $migration->down();
        foreach (['mort_repro', 'mort_sevre', 'mort_jeune', 'don_repro', 'don_sevre', 'don_jeune', 'passage_sevre_jeune', 'cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune'] as $c) {
            $this->assertFalse(Schema::hasColumn('livestock_daily_entries', $c), "down() doit retirer {$c}");
        }
        foreach (['cat_eff_repro', 'cat_eff_sevre', 'cat_eff_jeune', 'cat_eff_4', 'don', 'mort'] as $c) {
            $this->assertTrue(Schema::hasColumn('livestock_daily_entries', $c), "down() ne doit pas toucher {$c}");
        }

        $migration->down(); // rejouable
        $migration->up();
        $migration->up();
        $this->assertTrue(Schema::hasColumn('livestock_daily_entries', 'cat_depart_sevre'));
    }

    // ================================================================== (3) CHAÎNE — LAPINS

    public function test_chaine_lapins_jeu_du_plan(): void
    {
        $this->jeuLapins();

        $rapport = $this->service()->recalculerChaine($this->lapins->id);

        $this->assertTrue($rapport['chaine']);
        $this->assertNull($rapport['refus']);
        $this->assertSame([10, 26, 30], $this->cats($this->lapins, '2026-10-01'));
        $this->assertSame(66, $this->total($this->lapins, '2026-10-01'));
        $this->assertSame([9, 25, 24], $this->cats($this->lapins, '2026-10-02'));
        $this->assertSame(58, $this->total($this->lapins, '2026-10-02'));
        $this->assertSame([9, 23, 0], $this->cats($this->lapins, '2026-10-03'));
        $this->assertSame(26, $this->total($this->lapins, '2026-10-03'));
        $this->assertSame(3, $rapport['modifiees']);
    }

    public function test_la_chaine_ne_touche_jamais_aux_mouvements_saisis(): void
    {
        $this->jeuLapins();
        $avant = DB::table('livestock_daily_entries')->orderBy('entry_date')->get()->map(fn ($l) => collect((array) $l)->except(['cat_eff_repro', 'cat_eff_sevre', 'cat_eff_jeune', 'updated_at'])->all())->all();

        $this->service()->recalculerChaine($this->lapins->id);

        $apres = DB::table('livestock_daily_entries')->orderBy('entry_date')->get()->map(fn ($l) => collect((array) $l)->except(['cat_eff_repro', 'cat_eff_sevre', 'cat_eff_jeune', 'updated_at'])->all())->all();
        $this->assertSame($avant, $apres);
    }

    public function test_retroactif_mort_chair_du_j2_corrige_a_zero(): void
    {
        $this->jeuLapins();
        $this->service()->recalculerChaine($this->lapins->id);

        // Correction rétroactive : au J2 les 2 morts de Chair étaient une erreur de saisie.
        $j2 = LivestockDailyEntry::whereDate('entry_date', '2026-10-02')->where('lot_id', $this->lapins->id)->first();
        $j2->update(['mort_jeune' => 0, 'mort' => 1]);
        $this->poserTotaux($this->lapins);

        $this->service()->recalculerChaine($this->lapins->id);

        $this->assertSame([10, 26, 30], $this->cats($this->lapins, '2026-10-01'), 'J1 inchangé');
        $this->assertSame([9, 25, 26], $this->cats($this->lapins, '2026-10-02'));
        $this->assertSame(60, $this->total($this->lapins, '2026-10-02'));
        $this->assertSame([9, 23, 0], $this->cats($this->lapins, '2026-10-03'));
        $this->assertSame(28, $this->total($this->lapins, '2026-10-03'));
    }

    public function test_jour_saute_est_franchi(): void
    {
        $this->fiche($this->lapins, '2026-10-01', $this->mv(['cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30, 'achat' => 2, 'ne' => 5, 'mort_sevre' => 1]));
        // Aucune fiche le 02 ni le 03 : la fiche du 04 repart de celle du 01.
        $this->fiche($this->lapins, '2026-10-04', $this->mv(['vente' => 4, 'mort_repro' => 1]));

        $this->service()->recalculerChaine($this->lapins->id);

        $this->assertSame([10, 26, 30], $this->cats($this->lapins, '2026-10-01'));
        $this->assertSame([9, 26, 26], $this->cats($this->lapins, '2026-10-04'));
        $this->assertSame(61, $this->total($this->lapins, '2026-10-04'));
    }

    public function test_les_fiches_anterieures_a_la_tete_de_chaine_ne_sont_pas_touchees(): void
    {
        $avant = $this->fiche($this->lapins, '2026-09-28', ['cat_eff_repro' => 5, 'cat_eff_sevre' => 5, 'cat_eff_jeune' => 5]);
        $this->fiche($this->lapins, '2026-10-01', $this->mv(['cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30]));
        // Départ : la somme (60) doit égaler l'effectif au début du 01 = fin du 28/09 = 60 (aucun mouvement).

        $this->service()->recalculerChaine($this->lapins->id);

        $this->assertSame([5, 5, 5], $this->cats($this->lapins, '2026-09-28'));
        $this->assertSame([10, 20, 30], $this->cats($this->lapins, '2026-10-01'));
        $this->assertTrue($avant->updated_at->equalTo(LivestockDailyEntry::find($avant->id)->updated_at));
    }

    public function test_depart_avec_somme_differente_du_total_refuse_la_chaine_sans_rien_ecrire(): void
    {
        $this->fiche($this->lapins, '2026-10-01', $this->mv(['cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 31, 'achat' => 1]));

        $rapport = $this->service()->recalculerChaine($this->lapins->id);

        $this->assertNotNull($rapport['refus']);
        $this->assertStringContainsString('61', $rapport['refus']);
        $this->assertSame(0, $rapport['modifiees']);
        $this->assertSame([null, null, null], $this->cats($this->lapins, '2026-10-01'));
    }

    public function test_une_bande_sans_depart_n_a_pas_de_chaine_et_rien_n_est_ecrit(): void
    {
        $this->fiche($this->lapins, '2026-10-01', $this->mv(['achat' => 2]));
        $this->fiche($this->lapins, '2026-10-02', $this->mv(['vente' => 1]));

        $rapport = $this->service()->recalculerChaine($this->lapins->id);

        $this->assertFalse($rapport['chaine']);
        $this->assertSame(0, $rapport['modifiees']);
        $this->assertSame([null, null, null], $this->cats($this->lapins, '2026-10-01'));
        $this->assertFalse($this->service()->aUneChaine($this->lapins->id));
    }

    public function test_un_depart_partiel_n_est_pas_une_chaine(): void
    {
        $this->fiche($this->lapins, '2026-10-01', $this->mv(['cat_depart_repro' => 10, 'cat_depart_sevre' => 20]));

        $this->assertFalse($this->service()->aUneChaine($this->lapins->id));
        $rapport = $this->service()->recalculerChaine($this->lapins->id);
        $this->assertFalse($rapport['chaine']);
        $this->assertSame([null, null, null], $this->cats($this->lapins, '2026-10-01'));
    }

    public function test_un_second_depart_dans_la_chaine_est_ignore_et_signale(): void
    {
        $this->jeuLapins();
        LivestockDailyEntry::whereDate('entry_date', '2026-10-02')->where('lot_id', $this->lapins->id)
            ->update(['cat_depart_repro' => 1, 'cat_depart_sevre' => 1, 'cat_depart_jeune' => 1]);

        $rapport = $this->service()->recalculerChaine($this->lapins->id);

        $this->assertNotEmpty($rapport['avertissements']);
        $this->assertSame([9, 25, 24], $this->cats($this->lapins, '2026-10-02'), 'le départ du J2 est ignoré (verrouillé, QC4)');
    }

    public function test_une_espece_non_prise_en_charge_n_a_pas_de_chaine(): void
    {
        $avi = LivestockSpecies::create(['label' => 'Aviculture', 'code' => 'aviculture', 'is_active' => true]);
        $lot = $this->bande($avi, 'AVI-2026-01', 60);
        $this->fiche($lot, '2026-10-01', $this->mv(['cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30]));

        $rapport = $this->service()->recalculerChaine($lot->id);

        $this->assertFalse($rapport['chaine']);
        $this->assertSame([null, null, null], $this->cats($lot, '2026-10-01'));
    }

    // ------------------------------------------------------------------ null = inconnu, propagé

    public function test_un_mouvement_inconnu_rend_la_categorie_inconnue_et_l_inconnu_se_propage(): void
    {
        $this->fiche($this->lapins, '2026-10-01', $this->mv(['cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30]));
        $this->fiche($this->lapins, '2026-10-02', array_merge($this->mv(['vente' => 4]), ['mort_sevre' => null]));
        $this->fiche($this->lapins, '2026-10-03', $this->mv(['vente' => 1]));

        $this->service()->recalculerChaine($this->lapins->id);

        $this->assertSame([10, 20, 30], $this->cats($this->lapins, '2026-10-01'));
        $this->assertSame([10, null, 26], $this->cats($this->lapins, '2026-10-02'));
        $this->assertSame([10, null, 25], $this->cats($this->lapins, '2026-10-03'), 'l\'inconnu du J2 reste inconnu au J3, jamais 0');
    }

    public function test_une_categorie_redevenue_connue_apres_correction_retrouve_sa_valeur(): void
    {
        $this->fiche($this->lapins, '2026-10-01', $this->mv(['cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30]));
        $j2 = $this->fiche($this->lapins, '2026-10-02', array_merge($this->mv([]), ['mort_sevre' => null]));
        $this->service()->recalculerChaine($this->lapins->id);
        $this->assertSame([10, null, 30], $this->cats($this->lapins, '2026-10-02'));

        $j2->update(['mort_sevre' => 3, 'mort' => 3]);
        $this->poserTotaux($this->lapins);
        $this->service()->recalculerChaine($this->lapins->id);

        $this->assertSame([10, 17, 30], $this->cats($this->lapins, '2026-10-02'));
    }

    // ------------------------------------------------------------------ passage de stade en chaîne

    public function test_passage_de_stade_en_chaine_lapins_transfert_jeune_vers_chair(): void
    {
        $this->fiche($this->lapins, '2026-10-01', $this->mv(['cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30, 'passage_sevre_jeune' => 8]));

        $this->service()->recalculerChaine($this->lapins->id);

        $this->assertSame([10, 12, 38], $this->cats($this->lapins, '2026-10-01'));
        $this->assertSame(60, $this->total($this->lapins, '2026-10-01'));
    }

    public function test_passage_superieur_a_la_source_en_chaine_est_signale_sans_creer_de_sujets(): void
    {
        $this->fiche($this->lapins, '2026-10-01', $this->mv(['cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30, 'passage_sevre_jeune' => 25]));

        $rapport = $this->service()->recalculerChaine($this->lapins->id);

        $this->assertNull($rapport['refus'], 'le refus de chaîne est réservé au départ (D4)');
        $this->assertNotEmpty($rapport['avertissements']);
        $this->assertSame([10, 0, 50], $this->cats($this->lapins, '2026-10-01'));
        $this->assertSame(25, (int) LivestockDailyEntry::first()->passage_sevre_jeune, 'le passage saisi n\'est pas réécrit');
    }

    // ================================================================== (3) CHAÎNE — PORCS

    public function test_chaine_porcs_jeu_du_plan_et_plancher_porcelet_au_j4(): void
    {
        $this->jeuPorcs();

        $this->service()->recalculerChaine($this->porcs->id);

        $this->assertSame([13, 31, 86], $this->cats($this->porcs, '2026-10-01'));
        $this->assertSame(130, $this->total($this->porcs, '2026-10-01'));
        $this->assertSame([12, 31, 80], $this->cats($this->porcs, '2026-10-02'));
        $this->assertSame(123, $this->total($this->porcs, '2026-10-02'));
        $this->assertSame([12, 30, 75], $this->cats($this->porcs, '2026-10-03'));
        $this->assertSame(117, $this->total($this->porcs, '2026-10-03'));
        $this->assertSame([12, 0, 75], $this->cats($this->porcs, '2026-10-04'));
        $this->assertSame(77, $this->total($this->porcs, '2026-10-04'));
    }

    public function test_les_deux_bandes_ont_des_chaines_independantes(): void
    {
        $this->jeuLapins();
        $this->jeuPorcs();

        $this->service()->recalculerChaine($this->porcs->id);

        $this->assertSame([null, null, null], $this->cats($this->lapins, '2026-10-01'), 'les lapins n\'ont pas été recalculés');
        $this->assertSame([13, 31, 86], $this->cats($this->porcs, '2026-10-01'));
    }

    // ================================================================== IDEMPOTENCE & TRANSACTION

    public function test_chaine_idempotente_une_fiche_deja_juste_n_est_pas_reecrite(): void
    {
        $this->jeuLapins();
        $this->service()->recalculerChaine($this->lapins->id);
        $avant = DB::table('livestock_daily_entries')->orderBy('entry_date')->get()->all();

        Carbon::setTestNow('2026-10-14 18:00:00'); // si une fiche était réécrite, updated_at bougerait
        DB::enableQueryLog();
        $rapport = $this->service()->recalculerChaine($this->lapins->id);
        $ecritures = collect(DB::getQueryLog())->filter(fn ($q) => preg_match('/^\s*(update|insert|delete)/i', $q['query']))->count();
        DB::disableQueryLog();

        $this->assertSame(0, $rapport['modifiees']);
        $this->assertSame(0, $ecritures, 'aucune écriture au second passage');
        $this->assertEquals($avant, DB::table('livestock_daily_entries')->orderBy('entry_date')->get()->all());
    }

    public function test_chaine_transactionnelle_un_echec_au_milieu_n_ecrit_rien(): void
    {
        $this->jeuLapins();
        $vues = 0;
        LivestockDailyEntry::saving(function () use (&$vues) {
            if (++$vues === 3) {
                throw new \RuntimeException('panne simulée à la troisième fiche');
            }
        });

        try {
            $this->service()->recalculerChaine($this->lapins->id);
            $this->fail('l\'exception devait remonter');
        } catch (\RuntimeException $e) {
            $this->assertStringContainsString('panne', $e->getMessage());
        }

        foreach (['2026-10-01', '2026-10-02', '2026-10-03'] as $jour) {
            $this->assertSame([null, null, null], $this->cats($this->lapins, $jour), "{$jour} doit être revenue en arrière");
        }
        $this->assertGreaterThanOrEqual(3, $vues);
    }

    // ================================================================== (4) VENTE ANTIDATÉE

    public function test_vente_antidatee_de_6_au_j1_recalcule_les_categories_en_cascade(): void
    {
        $this->jeuLapins();
        $this->service()->recalculerChaine($this->lapins->id);

        app(RecordSaleOnFicheElevageAction::class)->execute([['lot_id' => $this->lapins->id, 'qty' => 6]], '2026-10-01');

        $this->assertSame([10, 26, 24], $this->cats($this->lapins, '2026-10-01'));
        $this->assertSame(60, $this->total($this->lapins, '2026-10-01'));
        $this->assertSame([9, 25, 18], $this->cats($this->lapins, '2026-10-02'));
        $this->assertSame(52, $this->total($this->lapins, '2026-10-02'));
        $this->assertSame([9, 23, 0], $this->cats($this->lapins, '2026-10-03'));
        $this->assertSame(20, $this->total($this->lapins, '2026-10-03'));
        $this->assertSame(20, (int) $this->lapins->fresh()->current_quantity, 'la bande suit la dernière fiche (15.31)');
    }

    public function test_vente_porcs_est_imputee_au_marchand(): void
    {
        $this->jeuPorcs();
        $this->service()->recalculerChaine($this->porcs->id);

        app(RecordSaleOnFicheElevageAction::class)->execute([['lot_id' => $this->porcs->id, 'qty' => 10]], '2026-10-02');

        $this->assertSame([13, 31, 86], $this->cats($this->porcs, '2026-10-01'), 'J1 antérieur au jour de la vente');
        $this->assertSame([12, 31, 70], $this->cats($this->porcs, '2026-10-02'));
        $this->assertSame(113, $this->total($this->porcs, '2026-10-02'));
        $this->assertSame([12, 30, 65], $this->cats($this->porcs, '2026-10-03'));
        $this->assertSame([12, 0, 65], $this->cats($this->porcs, '2026-10-04'));
    }

    public function test_fiche_creee_par_la_vente_sur_une_bande_a_chaine_recoit_ses_categories(): void
    {
        $this->fiche($this->lapins, '2026-10-01', $this->mv(['cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30, 'achat' => 2, 'ne' => 5, 'mort_sevre' => 1]));
        $this->fiche($this->lapins, '2026-10-03', $this->mv(['vente' => 1]));
        $this->service()->recalculerChaine($this->lapins->id);

        // Aucune fiche le 02 : la vente en crée une.
        app(RecordSaleOnFicheElevageAction::class)->execute([['lot_id' => $this->lapins->id, 'qty' => 4]], '2026-10-02');

        $j2 = LivestockDailyEntry::where('lot_id', $this->lapins->id)->whereDate('entry_date', '2026-10-02')->first();
        $this->assertNotNull($j2);
        $this->assertSame(4, (int) $j2->vente);
        $this->assertSame([10, 26, 26], [$j2->cat_eff_repro, $j2->cat_eff_sevre, $j2->cat_eff_jeune]);
        $this->assertSame(0, $j2->mort_repro, 'mouvements du jour connus à 0 : ni morts ni dons ce jour-là');
        $this->assertSame(0, $j2->don_jeune);
        $this->assertSame(0, $j2->passage_sevre_jeune);
        $this->assertSame(62, $this->total($this->lapins, '2026-10-02'));
        $this->assertSame([10, 26, 25], $this->cats($this->lapins, '2026-10-03'));
        $this->assertSame(61, $this->total($this->lapins, '2026-10-03'));
    }

    public function test_sans_chaine_la_vente_garde_exactement_le_comportement_actuel(): void
    {
        $this->fiche($this->lapins, '2026-10-01', ['achat' => 0, 'mort' => 1]);

        app(RecordSaleOnFicheElevageAction::class)->execute([['lot_id' => $this->lapins->id, 'qty' => 3]], '2026-10-02');

        $j2 = LivestockDailyEntry::where('lot_id', $this->lapins->id)->whereDate('entry_date', '2026-10-02')->first();
        $this->assertSame(3, (int) $j2->vente);
        $this->assertSame(56, (int) $j2->effectif_final);
        foreach (['cat_eff_repro', 'cat_eff_sevre', 'cat_eff_jeune', 'mort_repro', 'mort_sevre', 'mort_jeune', 'don_repro', 'don_sevre', 'don_jeune', 'passage_sevre_jeune', 'cat_depart_repro'] as $c) {
            $this->assertNull($j2->$c, "{$c} doit rester NULL (bande non ventilée)");
        }
        $this->assertSame(56, (int) $this->lapins->fresh()->current_quantity);
    }

    public function test_une_vente_sans_chaine_ne_touche_pas_aux_cat_eff_saisis_a_la_main(): void
    {
        $this->fiche($this->lapins, '2026-10-01', ['cat_eff_repro' => 9, 'cat_eff_sevre' => 8, 'cat_eff_jeune' => 7]);
        $this->fiche($this->lapins, '2026-10-02', ['cat_eff_repro' => 6, 'cat_eff_sevre' => 5, 'cat_eff_jeune' => 4]);

        app(RecordSaleOnFicheElevageAction::class)->execute([['lot_id' => $this->lapins->id, 'qty' => 2]], '2026-10-01');

        $this->assertSame([9, 8, 7], $this->cats($this->lapins, '2026-10-01'));
        $this->assertSame([6, 5, 4], $this->cats($this->lapins, '2026-10-02'));
    }

    // ================================================================== (5) RAPPORT À BLANC

    public function test_rapport_a_blanc_liste_les_bandes_sans_rien_ecrire(): void
    {
        $this->jeuLapins();                                   // chaîne explicite
        $porcsSansHistorique = $this->porcs;                   // aucune fiche
        $vide = $this->bande($this->cuniculture, 'LAP-2026-02', 40); // lapins sans fiche
        $avi = LivestockSpecies::create(['label' => 'Aviculture', 'code' => 'aviculture', 'is_active' => true]);
        $this->bande($avi, 'AVI-2026-01', 10);                 // hors périmètre
        $implicite = $this->bande($this->cuniculture, 'LAP-2026-03', 50);
        $this->fiche($implicite, '2026-10-01', ['cat_eff_repro' => 5, 'cat_eff_sevre' => 20, 'cat_eff_jeune' => 25]);
        $this->fiche($implicite, '2026-10-02', ['vente' => 3]); // ancienne fiche : mouvements non ventilés
        $non = $this->bande($this->cuniculture, 'LAP-2026-04', 30);
        $this->fiche($non, '2026-10-01', ['cat_eff_repro' => 5]);   // 1 seule catégorie : pas une tête

        $avant = DB::table('livestock_daily_entries')->orderBy('id')->get()->all();
        DB::enableQueryLog();
        $rapport = $this->service()->rapportABlanc();
        $ecritures = collect(DB::getQueryLog())->filter(fn ($q) => preg_match('/^\s*(update|insert|delete|create|alter|drop)/i', $q['query']))->count();
        DB::disableQueryLog();

        $this->assertSame(0, $ecritures, 'lecture seule');
        $this->assertEquals($avant, DB::table('livestock_daily_entries')->orderBy('id')->get()->all());

        $parCode = collect($rapport['bandes'])->keyBy('code');
        $this->assertCount(5, $parCode, 'lapins et porcs seulement, aviculture exclue');
        $this->assertSame('lapins', $parCode['LAP-2026-01']['espece']);
        $this->assertSame('chaine', $parCode['LAP-2026-01']['statut']);
        $this->assertSame(3, $parCode['LAP-2026-01']['fiches']);
        $this->assertSame('2026-10-01', $parCode['LAP-2026-01']['tete']['date']);
        $this->assertSame(3, $parCode['LAP-2026-01']['a_modifier'], 'trois fiches encore sans catégories');

        $this->assertSame('sans_historique', $parCode['POR-2026-01']['statut']);
        $this->assertSame('sans_historique', $parCode['LAP-2026-02']['statut']);
        $this->assertSame(0, $parCode['LAP-2026-02']['fiches']);

        $this->assertSame('tete_implicite', $parCode['LAP-2026-03']['statut'], 'D6 : la dernière fiche aux 3 catégories non nulles');
        $this->assertSame('2026-10-01', $parCode['LAP-2026-03']['tete']['date']);
        $this->assertSame(['repro' => 5, 'sevre' => 20, 'jeune' => 25], $parCode['LAP-2026-03']['tete']['categories']);

        $this->assertSame('non_ventilee', $parCode['LAP-2026-04']['statut']);
        $this->assertNull($parCode['LAP-2026-04']['tete']);

        $this->assertSame(1, $rapport['resume']['chaine']);
        $this->assertSame(1, $rapport['resume']['tete_implicite']);
        $this->assertSame(2, $rapport['resume']['sans_historique']);
        $this->assertSame(1, $rapport['resume']['non_ventilee']);
    }

    public function test_tete_implicite_est_la_derniere_fiche_aux_trois_categories_non_nulles_et_n_est_pas_ecrite(): void
    {
        $this->fiche($this->lapins, '2026-10-01', ['cat_eff_repro' => 1, 'cat_eff_sevre' => 1, 'cat_eff_jeune' => 1]);
        $this->fiche($this->lapins, '2026-10-02', ['cat_eff_repro' => 5, 'cat_eff_sevre' => 20, 'cat_eff_jeune' => 35]);
        $this->fiche($this->lapins, '2026-10-03', ['cat_eff_repro' => 9, 'cat_eff_sevre' => null, 'cat_eff_jeune' => 9]);

        $tete = $this->service()->teteImplicite($this->lapins->id);

        $this->assertSame('2026-10-02', $tete['date']);
        $this->assertSame(['repro' => 5, 'sevre' => 20, 'jeune' => 35], $tete['categories']);
        $this->assertNull(LivestockDailyEntry::whereDate('entry_date', '2026-10-02')->first()->cat_depart_repro, 'jamais écrite');
        $this->assertFalse($this->service()->aUneChaine($this->lapins->id), 'une tête implicite n\'est pas une chaîne exploitable');
    }

    public function test_commande_artisan_de_rapport_est_en_lecture_seule(): void
    {
        $this->jeuLapins();
        $avant = DB::table('livestock_daily_entries')->orderBy('id')->get()->all();

        $code = Artisan::call('elevage:effectif-categories-rapport');
        $sortie = Artisan::output();

        $this->assertSame(0, $code);
        $this->assertStringContainsString('LAP-2026-01', $sortie);
        $this->assertStringContainsString('POR-2026-01', $sortie);
        $this->assertStringContainsString('sans_historique', $sortie);
        $this->assertEquals($avant, DB::table('livestock_daily_entries')->orderBy('id')->get()->all());
    }

    // ================================================================== CONTRAT /api/sync/pull

    public function test_le_tirage_sert_les_nouvelles_colonnes_a_null_pour_les_anciennes_fiches(): void
    {
        $this->fiche($this->lapins, '2026-10-01', ['achat' => 1]);
        $mdp = 'AgriERP@2026';
        Permission::findOrCreate('view-ventes', 'web');
        Role::findOrCreate('caissier', 'web')->givePermissionTo(['view-ventes']);
        User::create(['name' => 'C', 'username' => 'caisse', 'email' => 'caisse@fermeolouwachegoun.com', 'password' => bcrypt($mdp), 'is_active' => true])->assignRole('caissier');
        $token = $this->postJson('/api/auth/login', ['identifiant' => 'caisse', 'password' => $mdp, 'device_name' => 'poste-01'])->json('token');

        $fiches = $this->withToken($token)->getJson('/api/sync/pull')->assertOk()->json('livestock_daily_entries');

        $this->assertCount(1, $fiches);
        foreach (['mort_repro', 'mort_sevre', 'mort_jeune', 'don_repro', 'don_sevre', 'don_jeune', 'passage_sevre_jeune', 'cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune'] as $c) {
            $this->assertArrayHasKey($c, $fiches[0], $c);
            $this->assertNull($fiches[0][$c], "{$c} : null (inconnu), jamais 0");
        }
    }
}
