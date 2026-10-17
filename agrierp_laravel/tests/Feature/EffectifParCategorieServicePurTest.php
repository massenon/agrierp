<?php

namespace Tests\Feature;

use App\Services\EffectifParCategorieService as S;
use Tests\TestCase;

/**
 * Ticket 15.39 — FONCTIONS PURES du service d'effectif par catégorie (lapins et porcs).
 *
 * Aucune base : `calculerJour()` ne reçoit que des nombres. Les jeux de test sont ceux du
 * plan du 14/10/2026, CALCULÉS À LA MAIN ; la contre-vérification `attendu()` ci-dessous est
 * écrite AUTREMENT que le service (table de deltas signés par catégorie, puis plancher), pour
 * ne pas recopier sa formule.
 *
 * Correspondance des emplacements (14.11 / 14.12) : repro = Reproducteur ; sevre = Jeune
 * (lapins) / Porcelet (porcs) ; jeune = Lapin de Chair (lapins) / Marchand (porcs).
 */
class EffectifParCategorieServicePurTest extends TestCase
{
    private const MV0 = [
        'achat' => 0, 'ne' => 0, 'vente' => 0,
        'mort_repro' => 0, 'mort_sevre' => 0, 'mort_jeune' => 0,
        'don_repro' => 0, 'don_sevre' => 0, 'don_jeune' => 0,
        'passage' => 0,
    ];

    private function mv(array $m = []): array
    {
        return array_merge(self::MV0, $m);
    }

    private function etat(?int $r, ?int $s, ?int $j): array
    {
        return ['repro' => $r, 'sevre' => $s, 'jeune' => $j];
    }

    /**
     * Recalcul INDÉPENDANT : chaque catégorie = veille + somme de deltas signés, puis plancher.
     * Pas de passage ici (testé à part, avec sa règle de refus).
     */
    private function attendu(string $espece, array $v, array $m): array
    {
        $lapins = $espece === 'lapins';
        $deltas = [
            'repro' => [$lapins ? 0 : $m['achat'], -$m['mort_repro'], -$m['don_repro'], 0],
            'sevre' => [($lapins ? $m['achat'] : 0) + $m['ne'], -$m['mort_sevre'], -$m['don_sevre'], -$m['passage']],
            'jeune' => [-$m['vente'], -$m['mort_jeune'], -$m['don_jeune'], $m['passage']],
        ];
        $sortie = [];
        foreach ($deltas as $cat => $liste) {
            $sortie[$cat] = max(0, $v[$cat] + array_sum($liste));
        }

        return $sortie;
    }

    private function trio($r): array
    {
        return [$r->repro, $r->sevre, $r->jeune];
    }

    // ------------------------------------------------------------------ LAPINS (jeu du plan)

    public function test_lapins_j1_achat_ne_et_mort_jeune(): void
    {
        $r = S::calculerJour('lapins', $this->etat(10, 20, 30), $this->mv(['achat' => 2, 'ne' => 5, 'mort_sevre' => 1]), 66);

        $this->assertSame([10, 26, 30], $this->trio($r));
        $this->assertFalse($r->sommeDifferente);
        $this->assertNull($r->refus);
    }

    public function test_lapins_j2_vente_morts_et_don(): void
    {
        $r = S::calculerJour('lapins', $this->etat(10, 26, 30), $this->mv(['vente' => 4, 'mort_repro' => 1, 'mort_jeune' => 2, 'don_sevre' => 1]), 58);

        $this->assertSame([9, 25, 24], $this->trio($r));
        $this->assertFalse($r->sommeDifferente);
    }

    public function test_lapins_j3_plancher_et_somme_differente_du_total(): void
    {
        $r = S::calculerJour('lapins', $this->etat(9, 25, 24), $this->mv(['vente' => 30, 'mort_sevre' => 2]), 26);

        $this->assertSame([9, 23, 0], $this->trio($r));
        $this->assertSame(32, $r->repro + $r->sevre + $r->jeune);
        $this->assertTrue($r->sommeDifferente, 'somme 32 ≠ total 26 : avertissement D8');
        $this->assertNull($r->refus, 'un avertissement n\'est pas un refus');
    }

    public function test_lapins_achat_va_au_jeune_et_pas_au_reproducteur(): void
    {
        $r = S::calculerJour('lapins', $this->etat(10, 20, 30), $this->mv(['achat' => 7]), 67);

        $this->assertSame([10, 27, 30], $this->trio($r));
    }

    public function test_lapins_vente_imputee_a_la_chair_seulement(): void
    {
        $r = S::calculerJour('lapins', $this->etat(10, 20, 30), $this->mv(['vente' => 5]), 55);

        $this->assertSame([10, 20, 25], $this->trio($r));
    }

    // ------------------------------------------------------------------ PORCS (jeu du plan)

    public function test_porcs_jeu_du_plan_sur_trois_jours(): void
    {
        $j1 = S::calculerJour('porcs', $this->etat(10, 24, 86), $this->mv(['achat' => 3, 'ne' => 9, 'mort_sevre' => 2]), 130);
        $this->assertSame([13, 31, 86], $this->trio($j1));
        $this->assertFalse($j1->sommeDifferente);

        $j2 = S::calculerJour('porcs', $this->etat(13, 31, 86), $this->mv(['vente' => 5, 'mort_repro' => 1, 'don_jeune' => 1]), 123);
        $this->assertSame([12, 31, 80], $this->trio($j2));
        $this->assertFalse($j2->sommeDifferente);

        $j3 = S::calculerJour('porcs', $this->etat(12, 31, 80), $this->mv(['vente' => 2, 'mort_jeune' => 3, 'don_sevre' => 1]), 117);
        $this->assertSame([12, 30, 75], $this->trio($j3));
        $this->assertFalse($j3->sommeDifferente);
    }

    public function test_porcs_plancher_porcelet_a_40_au_j4(): void
    {
        $r = S::calculerJour('porcs', $this->etat(12, 30, 75), $this->mv(['mort_sevre' => 40]), 77);

        $this->assertSame([12, 0, 75], $this->trio($r));
        $this->assertTrue($r->sommeDifferente, '12 + 0 + 75 = 87 ≠ 77');
    }

    public function test_porcs_achat_va_au_reproducteur_et_ne_au_porcelet(): void
    {
        $r = S::calculerJour('porcs', $this->etat(10, 24, 86), $this->mv(['achat' => 4, 'ne' => 6]), 130);

        $this->assertSame([14, 30, 86], $this->trio($r));
    }

    public function test_porcs_vente_imputee_au_marchand(): void
    {
        $r = S::calculerJour('porcs', $this->etat(10, 24, 86), $this->mv(['vente' => 9]), 111);

        $this->assertSame([10, 24, 77], $this->trio($r));
    }

    /** Contre-vérification : 200 combinaisons déterministes, formule réécrite autrement. */
    public function test_parite_avec_le_recalcul_independant_sur_des_combinaisons(): void
    {
        mt_srand(1539);
        foreach (['lapins', 'porcs'] as $espece) {
            for ($i = 0; $i < 100; $i++) {
                $v = $this->etat(mt_rand(0, 40), mt_rand(0, 40), mt_rand(0, 40));
                $m = $this->mv([
                    'achat' => mt_rand(0, 9), 'ne' => mt_rand(0, 9), 'vente' => mt_rand(0, 60),
                    'mort_repro' => mt_rand(0, 12), 'mort_sevre' => mt_rand(0, 12), 'mort_jeune' => mt_rand(0, 12),
                    'don_repro' => mt_rand(0, 5), 'don_sevre' => mt_rand(0, 5), 'don_jeune' => mt_rand(0, 5),
                ]);
                $r = S::calculerJour($espece, $v, $m, 0);
                $this->assertSame(array_values($this->attendu($espece, $v, $m)), $this->trio($r), "{$espece} #{$i}");
            }
        }
    }

    // ------------------------------------------------------------------ PASSAGE DE STADE (D3)

    public function test_lapins_passage_est_un_transfert_jeune_vers_chair_total_inchange(): void
    {
        $r = S::calculerJour('lapins', $this->etat(5, 10, 3), $this->mv(['passage' => 4]), 18);

        $this->assertSame([5, 6, 7], $this->trio($r));
        $this->assertSame(18, $r->repro + $r->sevre + $r->jeune, 'un transfert ne change pas la somme');
        $this->assertFalse($r->sommeDifferente);
        $this->assertNull($r->refus);
    }

    public function test_porcs_passage_est_un_transfert_porcelet_vers_marchand(): void
    {
        $r = S::calculerJour('porcs', $this->etat(5, 10, 3), $this->mv(['passage' => 10]), 18);

        $this->assertSame([5, 0, 13], $this->trio($r));
        $this->assertNull($r->refus, 'passer toute la catégorie source est permis');
    }

    public function test_passage_apres_les_mouvements_du_jour_de_la_categorie_source(): void
    {
        // Source du jour avant passage : 10 + 2 (nés) - 3 (morts) = 9 ; passage 9 permis, 10 refusé.
        $ok = S::calculerJour('porcs', $this->etat(0, 10, 0), $this->mv(['ne' => 2, 'mort_sevre' => 3, 'passage' => 9]), 9);
        $this->assertSame([0, 0, 9], $this->trio($ok));
        $this->assertNull($ok->refus);

        $ko = S::calculerJour('porcs', $this->etat(0, 10, 0), $this->mv(['ne' => 2, 'mort_sevre' => 3, 'passage' => 10]), 9);
        $this->assertNotNull($ko->refus);
    }

    public function test_passage_superieur_a_la_source_est_refuse_avec_message_et_sans_creer_de_sujets(): void
    {
        $r = S::calculerJour('lapins', $this->etat(5, 10, 3), $this->mv(['passage' => 11]), 18);

        $this->assertNotNull($r->refus);
        $this->assertStringContainsString('passage', mb_strtolower($r->refus));
        // Valeurs de repli : le passage est ramené à la source, la somme reste 18 (aucun sujet inventé).
        $this->assertSame(18, $r->repro + $r->sevre + $r->jeune);
        $this->assertSame([5, 0, 13], $this->trio($r));
    }

    public function test_passage_sans_aucun_sujet_en_source_est_refuse(): void
    {
        $r = S::calculerJour('lapins', $this->etat(5, 0, 3), $this->mv(['passage' => 1]), 8);

        $this->assertNotNull($r->refus);
        $this->assertSame([5, 0, 3], $this->trio($r));
    }

    // ------------------------------------------------------------------ DÉPART (D4)

    public function test_depart_somme_egale_au_total_est_accepte(): void
    {
        $this->assertNull(S::verifierDepart($this->etat(10, 20, 30), 60));
    }

    public function test_depart_somme_differente_du_total_est_refuse(): void
    {
        $refus = S::verifierDepart($this->etat(10, 20, 30), 61);

        $this->assertNotNull($refus);
        $this->assertStringContainsString('60', $refus);
        $this->assertStringContainsString('61', $refus);
    }

    public function test_depart_somme_inferieure_au_total_est_aussi_refusee(): void
    {
        $refus = S::verifierDepart($this->etat(10, 20, 29), 60);

        $this->assertNotNull($refus);
        $this->assertStringContainsString('59', $refus);
    }

    public function test_depart_incomplet_est_refuse(): void
    {
        $this->assertNotNull(S::verifierDepart($this->etat(10, null, 30), 40));
    }

    public function test_depart_zero_partout_pour_une_bande_vide_est_valide(): void
    {
        $this->assertNull(S::verifierDepart($this->etat(0, 0, 0), 0));
    }

    // ------------------------------------------------------------------ NULL = INCONNU, JAMAIS 0

    public function test_veille_inconnue_donne_categorie_inconnue_et_les_autres_restent_calculees(): void
    {
        $r = S::calculerJour('lapins', $this->etat(10, null, 30), $this->mv(['vente' => 4]), 56);

        $this->assertSame(10, $r->repro);
        $this->assertNull($r->sevre);
        $this->assertSame(26, $r->jeune);
        $this->assertNull($r->sommeDifferente, 'une somme avec un inconnu n\'est pas comparable au total');
    }

    public function test_mouvement_inconnu_donne_la_categorie_concernee_inconnue_seulement(): void
    {
        $r = S::calculerJour('lapins', $this->etat(10, 20, 30), $this->mv(['mort_repro' => null]), 60);
        $this->assertNull($r->repro);
        $this->assertSame(20, $r->sevre);
        $this->assertSame(30, $r->jeune);

        $r = S::calculerJour('lapins', $this->etat(10, 20, 30), $this->mv(['don_jeune' => null]), 60);
        $this->assertSame(10, $r->repro);
        $this->assertSame(20, $r->sevre);
        $this->assertNull($r->jeune);

        $r = S::calculerJour('porcs', $this->etat(10, 20, 30), $this->mv(['mort_sevre' => null]), 60);
        $this->assertNull($r->sevre);
    }

    public function test_passage_inconnu_rend_inconnus_les_deux_categories_du_transfert(): void
    {
        $r = S::calculerJour('porcs', $this->etat(10, 20, 30), $this->mv(['passage' => null]), 60);

        $this->assertSame(10, $r->repro);
        $this->assertNull($r->sevre);
        $this->assertNull($r->jeune);
        $this->assertNull($r->refus);
    }

    public function test_achat_inconnu_ne_touche_que_la_categorie_qui_le_recoit(): void
    {
        $lap = S::calculerJour('lapins', $this->etat(10, 20, 30), $this->mv(['achat' => null]), 60);
        $this->assertSame(10, $lap->repro);
        $this->assertNull($lap->sevre);
        $this->assertSame(30, $lap->jeune);

        $por = S::calculerJour('porcs', $this->etat(10, 20, 30), $this->mv(['achat' => null]), 60);
        $this->assertNull($por->repro);
        $this->assertSame(20, $por->sevre);
    }

    public function test_total_inconnu_donne_somme_non_comparable(): void
    {
        $r = S::calculerJour('lapins', $this->etat(1, 2, 3), $this->mv(), null);

        $this->assertSame([1, 2, 3], $this->trio($r));
        $this->assertNull($r->sommeDifferente);
    }

    public function test_zero_connu_reste_zero_et_n_est_pas_confondu_avec_inconnu(): void
    {
        $r = S::calculerJour('lapins', $this->etat(0, 0, 0), $this->mv(), 0);

        $this->assertSame([0, 0, 0], $this->trio($r));
        $this->assertFalse($r->sommeDifferente);
    }

    public function test_espece_non_prise_en_charge_est_refusee(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        S::calculerJour('volailles', $this->etat(1, 1, 1), $this->mv(), 3);
    }

    public function test_les_colonnes_de_sortie_sont_celles_du_schema(): void
    {
        $r = S::calculerJour('lapins', $this->etat(10, 20, 30), $this->mv(), 60);

        $this->assertSame(['cat_eff_repro' => 10, 'cat_eff_sevre' => 20, 'cat_eff_jeune' => 30], $r->versColonnes());
    }
}
