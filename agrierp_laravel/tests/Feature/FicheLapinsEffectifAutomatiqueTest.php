<?php

namespace Tests\Feature;

use App\Actions\RecordSaleOnFicheElevageAction;
use App\Livewire\Elevage\FicheLapins;
use App\Models\FeedRationStandard;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Notification;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Services\ProtocoleDuJourService;
use App\Services\EffectifParCategorieService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Features\SupportTesting\Testable;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.41 — FICHE WEB LAPINS : EFFECTIF AUTOMATIQUE PAR CATÉGORIE.
 *
 * 🔁 17/10/2026 : glossaire Reproducteur / Jeune / Sous-mères ; départ déduit du stade de la bande.
 * Emplacements génériques (14.11 / 14.12) : `sevre` = Sous-mères (ex-« Lapereau » / « Jeune » 30 g) ;
 * `jeune` = Jeune (ex-« Lapin de Chair », 60 g). Date figée au 14/10/2026.
 *
 * ⚠️ Les valeurs attendues sont des LITTÉRAUX calculés à la main (plan du 14/10/2026), jamais produits
 * par le service. Départ R10/J20/C30 (total 60), rations 120/30/60 :
 *   J1 (achat 2, nés 5, mort Jeune 1)                       → 10/26/30  total 66  provende 3 780 g
 *   J2 (vente 4, morts R1 + C2, don Jeune 1)                → 9/25/24   total 58  provende 3 270 g
 *   J3 (vente 30, mort Jeune 2)                             → 9/23/0    total 26  somme 32  1 770 g
 */
class FicheLapinsEffectifAutomatiqueTest extends TestCase
{
    use RefreshDatabase;

    private const J1 = '2026-10-05';

    private const J2 = '2026-10-06';

    private const J3 = '2026-10-07';

    private LivestockSpecies $espece;

    private LivestockLot $lot;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow('2026-10-14 12:00:00');

        $this->espece = LivestockSpecies::create(['code' => 'cuniculture', 'label' => 'Lapins', 'is_enabled' => true]);
        $this->lot = $this->bande('LOT-LAP-A', 60);

        FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Reproducteur', 'ration_g_per_day' => 120]);
        // Glossaire du 17/10/2026 : Sous-mères 30 g/j (emplacement `sevre`), Jeune 60 g/j (emplacement `jeune`).
        FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Sous-mères', 'ration_g_per_day' => 30]);
        FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Jeune', 'ration_g_per_day' => 60]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function bande(string $code, int $initial): LivestockLot
    {
        return LivestockLot::create([
            'code' => $code, 'species_id' => $this->espece->id, 'stage' => 'croissance',
            'initial_quantity' => $initial, 'current_quantity' => $initial,
            'created_date' => '2026-09-01', 'status' => 'actif', 'is_active' => true,
        ]);
    }

    /** Fiche posée à la main (effectif_final fourni par le test, jamais par le service). */
    private function fiche(LivestockLot $lot, string $jour, array $valeurs = []): LivestockDailyEntry
    {
        return LivestockDailyEntry::create(array_merge([
            'lot_id' => $lot->id, 'entry_date' => $jour,
            'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0, 'effectif_final' => 0,
        ], $valeurs));
    }

    private function ouvrir(string $jour): Testable
    {
        return Livewire::test(FicheLapins::class)->set('selectedDate', $jour);
    }

    private function departer(Testable $c, int $r = 10, int $j = 20, int $ch = 30): Testable
    {
        return $c->set('departRepro', $r)->set('departSevre', $j)->set('departJeune', $ch);
    }

    /** Valeur affichée (attribut value) d'un champ d'effectif de catégorie. */
    private function affiche(Testable $c, string $id): ?string
    {
        $this->assertSame(1, preg_match('/<input\b[^>]*\bid="'.preg_quote($id, '/').'"[^>]*>/', $c->html(), $m), "champ #{$id} introuvable");
        $this->assertSame(1, preg_match('/\bvalue="([^"]*)"/', $m[0], $v), "champ #{$id} sans value");

        return $v[1];
    }

    /** Texte visible de la page (balises retirées, entités décodées, espaces fusionnés). */
    private function texte(Testable $c): string
    {
        return preg_replace('/\s+/u', ' ', html_entity_decode(strip_tags($c->html()), ENT_QUOTES | ENT_HTML5));
    }

    private function voit(Testable $c, string $attendu): void
    {
        $this->assertStringContainsString($attendu, $this->texte($c));
    }

    private function nevoitPas(Testable $c, string $attendu): void
    {
        $this->assertStringNotContainsString($attendu, $this->texte($c));
    }

    private function tag(Testable $c, string $id): string
    {
        preg_match('/<input\b[^>]*\bid="'.preg_quote($id, '/').'"[^>]*>/', $c->html(), $m);

        return $m[0] ?? '';
    }

    /** @return array{string, string, string} effectifs affichés Reproducteur / Jeune / Lapin de Chair */
    private function ecran(Testable $c): array
    {
        return [$this->affiche($c, 'cat-eff-repro'), $this->affiche($c, 'cat-eff-lapereau'), $this->affiche($c, 'cat-eff-chair')];
    }

    private function cellule(Testable $c, string $id): string
    {
        $this->assertSame(1, preg_match('/<td\b[^>]*\bid="'.preg_quote($id, '/').'"[^>]*>\s*([^<]*?)\s*<\/td>/', $c->html(), $m), "cellule #{$id} introuvable");

        return html_entity_decode($m[1]);
    }

    private function entree(string $jour, ?LivestockLot $lot = null): LivestockDailyEntry
    {
        return LivestockDailyEntry::where('lot_id', ($lot ?? $this->lot)->id)->whereDate('entry_date', $jour)->firstOrFail();
    }

    private function jeuxComplet(): void
    {
        // J1 : départ + achat 2, nés 5, mort Jeune 1.
        $c = $this->departer($this->ouvrir(self::J1))
            ->set('achat', 2)->set('ne', 5)->set('mortLapereau', 1)->call('saveDay');
        // J2 : vente 4 enregistrée au POS, puis morts R1 + C2 et don Jeune 1.
        app(RecordSaleOnFicheElevageAction::class)->execute([['lot_id' => $this->lot->id, 'qty' => 4]], self::J2);
        $this->ouvrir(self::J2)->set('mortRepro', 1)->set('mortChair', 2)->set('donLapereau', 1)->call('saveDay');
        // J3 : vente 30, mort Jeune 2.
        app(RecordSaleOnFicheElevageAction::class)->execute([['lot_id' => $this->lot->id, 'qty' => 30]], self::J3);
        $this->ouvrir(self::J3)->set('mortLapereau', 2)->call('saveDay');
    }

    // ===================================================================== (1) champs calculés

    public function test_les_trois_champs_d_effectif_de_categorie_sont_disabled_et_les_champs_saisis_restent_actifs(): void
    {
        $c = $this->departer($this->ouvrir(self::J1));

        foreach (['cat-eff-repro', 'cat-eff-lapereau', 'cat-eff-chair'] as $id) {
            $this->assertMatchesRegularExpression('/\bdisabled\b/', $this->tag($c, $id), "#{$id} doit être disabled");
        }

        $html = $c->html();
        foreach (['achat', 'ne', 'mortRepro', 'mortChair', 'mortLapereau', 'donRepro', 'donChair', 'donLapereau', 'passage', 'effectifM', 'effectifF', 'effectifSevres', 'effectifSmeres'] as $champ) {
            $this->assertSame(1, preg_match('/<input\b[^>]*wire:model(?:\.live)?="'.$champ.'"[^>]*>/', $html, $m), "champ saisi {$champ} introuvable");
            $this->assertDoesNotMatchRegularExpression('/\bdisabled\b|\breadonly\b/', $m[0], "{$champ} doit rester actif");
        }
        // Les anciens champs de saisie manuelle n'existent plus.
        $this->assertStringNotContainsString('wire:model.live="catEffRepro"', $html);
        $this->assertStringNotContainsString('wire:model.live="catEffSevre"', $html);
        $this->assertStringNotContainsString('wire:model.live="catEffJeune"', $html);
    }

    /**
     * Mise à jour EN DIRECT : chaque champ saisi déplace uniquement les catégories qu'il touche.
     * Départ R10/J20/C30 sur une bande de 60 ; les attendus sont calculés à la main.
     *
     * @dataProvider mouvementsEnDirect
     */
    public function test_chaque_mouvement_met_a_jour_les_categories_en_direct(string $champ, int $valeur, array $attendu): void
    {
        $c = $this->departer($this->ouvrir(self::J1))->set($champ, $valeur);

        $this->assertSame($attendu, $this->ecran($c), "après {$champ} = {$valeur}");
    }

    /** @return array<string, array{string, int, array{string, string, string}}> */
    public static function mouvementsEnDirect(): array
    {
        return [
            'achat → Jeune' => ['achat', 3, ['10', '23', '30']],
            'nés → Jeune' => ['ne', 4, ['10', '24', '30']],
            'mort Reproducteur' => ['mortRepro', 2, ['8', '20', '30']],
            'mort Lapereau = Jeune (D2)' => ['mortLapereau', 2, ['10', '18', '30']],
            'mort Lapin de chair' => ['mortChair', 5, ['10', '20', '25']],
            'don Reproducteur' => ['donRepro', 1, ['9', '20', '30']],
            'don Lapereau = Jeune (D2)' => ['donLapereau', 3, ['10', '17', '30']],
            'don Lapin de Chair' => ['donChair', 4, ['10', '20', '26']],
            'passage de stade Jeune → Chair' => ['passage', 5, ['10', '15', '35']],
        ];
    }

    public function test_la_vente_du_pos_deduit_le_lapin_de_chair_en_direct(): void
    {
        $this->fiche($this->lot, self::J1, ['vente' => 6, 'effectif_final' => 54]);

        $c = $this->departer($this->ouvrir(self::J1));

        $this->assertSame(['10', '20', '24'], $this->ecran($c));
    }

    public function test_les_champs_recalcules_suivent_les_modifications_successives_sans_rechargement(): void
    {
        $c = $this->departer($this->ouvrir(self::J1))->set('mortRepro', 1);
        $this->assertSame(['9', '20', '30'], $this->ecran($c));

        $c->set('mortRepro', 0)->set('achat', 5);
        $this->assertSame(['10', '25', '30'], $this->ecran($c));

        $c->set('passage', 5);
        $this->assertSame(['10', '20', '35'], $this->ecran($c));
    }

    // ===================================================================== (3) bande sans chaîne

    /**
     * 🔁 17/10/2026 — RATIONNEMENT AUTOMATIQUE. Bande sans chaîne, stade « croissance » (= Sous-mères) de 60 :
     * le départ est DÉDUIT du stade (0 / 60 / 0) et tout se calcule sans saisie. Provende : 60 × 30 = 1 800 g.
     */
    public function test_bande_sans_chaine_le_depart_est_deduit_du_stade_et_le_rationnement_est_calcule(): void
    {
        $c = $this->ouvrir(self::J1);

        $this->assertSame(['0', '60', '0'], $this->ecran($c));
        $this->assertSame('0 g', $this->cellule($c, 'cat-prov-repro-g'));
        $this->assertSame('1800 g', $this->cellule($c, 'cat-prov-lapereau-g'));
        $this->assertSame('0 g', $this->cellule($c, 'cat-prov-chair-g'));
        $this->assertSame('1800 g (1.8 Kg)', $this->cellule($c, 'day-total-provende-g'));

        // Seule une bande dont le stade ne relève d'aucune catégorie (« ponte », héritée) reste inconnue : « — », jamais 0.
        $this->lot->update(['stage' => 'ponte']);
        $c = $this->ouvrir(self::J1);
        $this->assertSame(['—', '—', '—'], $this->ecran($c));
        $this->assertSame('—', $this->cellule($c, 'day-total-provende-g'));
    }

    public function test_aucun_pourcentage_de_demonstration_du_premier_jour(): void
    {
        // La maquette répartit le premier jour à 15 % / 35 % / reste. Le départ déduit met TOUT l'effectif dans la
        // catégorie du stade de la bande : jamais une répartition inventée.
        $this->lot->update(['initial_quantity' => 100, 'current_quantity' => 100]);

        $c = $this->ouvrir(self::J1);

        $this->assertSame(['0', '100', '0'], $this->ecran($c));
        $this->assertSame(0, $c->instance()->categoriesJour['repro']);
        $this->assertStringNotContainsString('0.15', file_get_contents(app_path('Livewire/Elevage/FicheLapins.php')));
        $this->assertStringNotContainsString('0.35', file_get_contents(app_path('Livewire/Elevage/FicheLapins.php')));
    }

    public function test_bande_sans_chaine_le_depart_deduit_est_pre_rempli_et_corrigeable(): void
    {
        $c = $this->ouvrir(self::J1);

        foreach (['depart-repro' => 'departRepro', 'depart-sevre' => 'departSevre', 'depart-jeune' => 'departJeune'] as $id => $modele) {
            $tag = $this->tag($c, $id);
            $this->assertNotSame('', $tag, "champ #{$id}");
            $this->assertStringContainsString('wire:model.live="'.$modele.'"', $tag);
            $this->assertDoesNotMatchRegularExpression('/\bdisabled\b|\breadonly\b/', $tag, 'corrigeable pour une bande mixte');
        }
        $c->assertSet('departRepro', 0)->assertSet('departSevre', 60)->assertSet('departJeune', 0);
        $this->voit($c, 'déduit du stade de la bande');
        $this->voit($c, "l'effectif total au début du jour (60)");
    }

    public function test_un_depart_valide_donne_un_apercu_en_direct_avant_l_enregistrement(): void
    {
        $c = $this->departer($this->ouvrir(self::J1));

        $this->assertSame(['10', '20', '30'], $this->ecran($c));
        $this->assertSame('1200 g', $this->cellule($c, 'cat-prov-repro-g'));
        $this->assertSame('600 g', $this->cellule($c, 'cat-prov-lapereau-g'));
        $this->assertSame('1800 g', $this->cellule($c, 'cat-prov-chair-g'));
        $this->assertSame(0, LivestockDailyEntry::count(), 'aperçu : rien n\'est écrit');
    }

    public function test_un_depart_dont_la_somme_differe_du_total_est_refuse_avec_le_motif_visible(): void
    {
        $c = $this->departer($this->ouvrir(self::J1), 10, 20, 31);

        $this->assertSame(['—', '—', '—'], $this->ecran($c));
        $this->voit($c, 'La somme des catégories de départ (61) ne correspond pas à l\'effectif total au début du jour de départ (60).');

        $c->call('saveDay');
        $this->assertSame(0, LivestockDailyEntry::count(), 'un départ incohérent ne s\'enregistre pas');
    }

    public function test_un_depart_incomplet_est_refuse_a_l_enregistrement(): void
    {
        $c = $this->ouvrir(self::J1)->set('departRepro', 10)->set('departSevre', 50)->set('departJeune', null)->call('saveDay');

        $this->voit($c, 'Effectif de départ incomplet');
        $this->assertSame(0, LivestockDailyEntry::count());
    }

    /**
     * 🔁 17/10/2026 — sans rien saisir dans le départ, la première fiche ENREGISTRE le départ déduit du stade et
     * démarre la chaîne. Achat 2 (les achats de lapins entrent en Sous-mères, D11) : 0 / 62 / 0, total 62,
     * provende 62 × 30 = 1 860 g = 1,86 kg.
     */
    public function test_sans_saisie_la_premiere_fiche_enregistre_le_depart_deduit_du_stade(): void
    {
        $this->ouvrir(self::J1)->set('achat', 2)->call('saveDay');

        $f = $this->entree(self::J1);
        $this->assertSame(62, (int) $f->effectif_final);
        $this->assertSame([0, 60, 0], [(int) $f->cat_depart_repro, (int) $f->cat_depart_sevre, (int) $f->cat_depart_jeune]);
        $this->assertSame([0, 62, 0], [(int) $f->cat_eff_repro, (int) $f->cat_eff_sevre, (int) $f->cat_eff_jeune]);
        $this->assertSame(1.86, round((float) $f->feed_qty_kg, 2));
        $this->assertTrue(app(EffectifParCategorieService::class)->aUneChaine($this->lot->id));
    }

    // ===================================================================== (3) verrouillage du départ

    public function test_le_depart_est_enregistre_une_fois_puis_verrouille(): void
    {
        $this->departer($this->ouvrir(self::J1))->set('achat', 2)->call('saveDay');

        $f = $this->entree(self::J1);
        $this->assertSame([10, 20, 30], [(int) $f->cat_depart_repro, (int) $f->cat_depart_sevre, (int) $f->cat_depart_jeune]);

        // Le jour même, rouvert : les trois champs sont visibles, verrouillés, avec les valeurs stockées.
        $c = $this->ouvrir(self::J1);
        foreach (['depart-repro' => '10', 'depart-sevre' => '20', 'depart-jeune' => '30'] as $id => $valeur) {
            $this->assertMatchesRegularExpression('/\bdisabled\b/', $this->tag($c, $id), "#{$id} verrouillé");
            $this->assertSame($valeur, $this->affiche($c, $id));
        }

        // Un autre jour : tenter de redéfinir le départ ne change rien en base.
        $this->departer($this->ouvrir(self::J2), 1, 1, 58)->call('saveDay');
        $f2 = $this->entree(self::J2);
        $this->assertNull($f2->cat_depart_repro);
        $this->assertSame([10, 20, 30], [(int) $this->entree(self::J1)->cat_depart_repro, (int) $this->entree(self::J1)->cat_depart_sevre, (int) $this->entree(self::J1)->cat_depart_jeune]);
    }

    public function test_apres_enregistrement_les_categories_sont_ecrites_par_la_chaine(): void
    {
        $this->departer($this->ouvrir(self::J1))->set('achat', 2)->set('ne', 5)->set('mortLapereau', 1)->call('saveDay');

        $f = $this->entree(self::J1);
        $this->assertSame([10, 26, 30], [(int) $f->cat_eff_repro, (int) $f->cat_eff_sevre, (int) $f->cat_eff_jeune]);
        $this->assertSame(66, (int) $f->effectif_final);
        $this->assertSame(7, (int) $f->achat + (int) $f->ne);
        $this->assertSame(66, (int) $this->lot->fresh()->current_quantity);
    }

    // ===================================================================== (2) persistance et rechargement

    public function test_les_mouvements_par_categorie_sont_persistes_dans_les_bonnes_colonnes(): void
    {
        $this->departer($this->ouvrir(self::J1))
            ->set('mortRepro', 1)->set('mortLapereau', 2)->set('mortChair', 3)
            ->set('donRepro', 4)->set('donLapereau', 5)->set('donChair', 6)
            ->set('passage', 7)->call('saveDay');

        $f = $this->entree(self::J1);
        $this->assertSame([1, 2, 3], [(int) $f->mort_repro, (int) $f->mort_sevre, (int) $f->mort_jeune], 'morts : Reproducteur / Lapereau=Jeune / Chair');
        $this->assertSame([4, 5, 6], [(int) $f->don_repro, (int) $f->don_sevre, (int) $f->don_jeune], 'dons');
        $this->assertSame(7, (int) $f->passage_sevre_jeune);
        $this->assertSame(6, (int) $f->mort);
        $this->assertSame(15, (int) $f->don);
    }

    /** Défaut (a) : un jour existant rechargé remet les compteurs de morts et de dons. */
    public function test_un_jour_existant_recharge_les_compteurs_de_morts_dons_et_passage(): void
    {
        $this->departer($this->ouvrir(self::J1))
            ->set('mortRepro', 1)->set('mortLapereau', 2)->set('mortChair', 3)
            ->set('donRepro', 4)->set('donLapereau', 5)->set('donChair', 6)
            ->set('passage', 7)->set('achat', 9)->set('ne', 8)->call('saveDay');

        Livewire::test(FicheLapins::class)
            ->call('loadDay', self::J1)
            ->assertSet('mortRepro', 1)->assertSet('mortLapereau', 2)->assertSet('mortChair', 3)
            ->assertSet('donRepro', 4)->assertSet('donLapereau', 5)->assertSet('donChair', 6)
            ->assertSet('passage', 7)->assertSet('achat', 9)->assertSet('ne', 8);
    }

    public function test_reenregistrer_un_jour_recharge_ne_reecrit_pas_les_morts_et_dons_avec_des_valeurs_perimees(): void
    {
        $this->departer($this->ouvrir(self::J1))->set('mortRepro', 1)->set('mortChair', 2)->set('donLapereau', 3)->call('saveDay');

        $c = Livewire::test(FicheLapins::class)->call('loadDay', self::J1);
        // Autre jour, autres valeurs, puis retour : aucun compteur périmé ne doit survivre.
        $c->call('loadDay', self::J2)->assertSet('mortRepro', 0)->assertSet('mortChair', 0)->assertSet('donLapereau', 0);
        $c->call('loadDay', self::J1)->call('saveDay');

        $f = $this->entree(self::J1);
        $this->assertSame(3, (int) $f->mort);
        $this->assertSame(3, (int) $f->don);
        $this->assertSame([1, 0, 2], [(int) $f->mort_repro, (int) $f->mort_sevre, (int) $f->mort_jeune]);
    }

    public function test_une_fiche_ancienne_non_ventilee_ne_voit_pas_ses_morts_effaces_en_silence(): void
    {
        $this->fiche($this->lot, self::J1, ['mort' => 3, 'don' => 2, 'effectif_final' => 55]);

        $c = Livewire::test(FicheLapins::class)->call('loadDay', self::J1);
        $this->voit($c, 'non ventilé');
        $c->call('saveDay');
        $this->assertSame(3, (int) $this->entree(self::J1)->mort, 'refus : les morts ne sont pas remis à zéro');
        $this->assertSame(2, (int) $this->entree(self::J1)->don);
        $this->assertNull($this->entree(self::J1)->mort_repro);

        $c->set('mortRepro', 1)->set('mortChair', 2)->set('donLapereau', 2)->call('saveDay');
        $f = $this->entree(self::J1);
        $this->assertSame([1, 0, 2], [(int) $f->mort_repro, (int) $f->mort_sevre, (int) $f->mort_jeune]);
        $this->assertSame(3, (int) $f->mort);
    }

    /** Défaut (b) : changer la date appelle loadDay. */
    public function test_changer_la_date_charge_le_jour_choisi(): void
    {
        $this->fiche($this->lot, self::J2, ['achat' => 7, 'ne' => 3, 'mort' => 2, 'mort_repro' => 1, 'mort_sevre' => 1, 'mort_jeune' => 0,
            'don_repro' => 0, 'don_sevre' => 0, 'don_jeune' => 0, 'effectif_final' => 68]);

        $c = Livewire::test(FicheLapins::class)->set('selectedDate', self::J2);

        $c->assertSet('achat', 7)->assertSet('ne', 3)->assertSet('mortRepro', 1)->assertSet('mortLapereau', 1);

        $c->set('selectedDate', self::J1)->assertSet('achat', 0)->assertSet('mortRepro', 0);
    }

    public function test_un_jour_d_un_autre_mois_se_charge_aussi(): void
    {
        $this->fiche($this->lot, '2026-09-20', ['achat' => 4, 'effectif_final' => 64]);

        Livewire::test(FicheLapins::class)->set('selectedDate', '2026-09-20')->assertSet('achat', 4);
    }

    public function test_une_date_vide_ou_invalide_est_ignoree_sans_erreur(): void
    {
        Livewire::test(FicheLapins::class)->set('selectedDate', '')->assertOk();
        Livewire::test(FicheLapins::class)->set('selectedDate', 'pas-une-date')->assertOk();
    }

    public function test_a_l_ouverture_le_jour_courant_deja_saisi_est_charge(): void
    {
        $this->fiche($this->lot, '2026-10-14', ['achat' => 6, 'effectif_final' => 66]);

        Livewire::test(FicheLapins::class)->assertSet('achat', 6);
    }

    // ===================================================================== (2) défaut (c) : LA bande de la fiche

    public function test_la_veille_porte_sur_la_bande_de_la_fiche_et_non_sur_toutes_les_bandes(): void
    {
        $autre = $this->bande('LOT-LAP-B', 500);
        $this->fiche($autre, self::J1, ['achat' => 0, 'effectif_final' => 480]);   // plus récente que la fiche de A
        $this->fiche($this->lot, '2026-10-02', ['effectif_final' => 58]);

        $c = Livewire::test(FicheLapins::class)->set('bandeId', $this->lot->id)->set('selectedDate', self::J2);

        $this->assertSame(58, $c->instance()->previousEffectif, 'la veille de A est la fiche de A (58), pas celle de B (480)');

        $c->set('bandeId', $autre->id);
        $this->assertSame(480, $c->instance()->previousEffectif);
    }

    public function test_l_enregistrement_et_le_chargement_portent_sur_la_bande_choisie(): void
    {
        $autre = $this->bande('LOT-LAP-B', 500);
        $this->fiche($this->lot, self::J1, ['achat' => 11, 'effectif_final' => 71]);

        $c = Livewire::test(FicheLapins::class)->set('bandeId', $autre->id)->set('selectedDate', self::J1);
        $c->assertSet('achat', 0);                  // la fiche de A n'est pas celle de B
        $c->set('achat', 4)->call('saveDay');

        $this->assertSame(504, (int) $this->entree(self::J1, $autre)->effectif_final);
        $this->assertSame(71, (int) $this->entree(self::J1, $this->lot)->effectif_final, 'la bande A n\'est pas touchée');
        $this->assertSame(504, (int) $autre->fresh()->current_quantity);
        $this->assertSame(60, (int) $this->lot->fresh()->current_quantity);
    }

    public function test_le_tableau_mensuel_et_la_vente_du_jour_suivent_la_bande_choisie(): void
    {
        $autre = $this->bande('LOT-LAP-B', 500);
        $this->fiche($this->lot, self::J1, ['vente' => 3, 'effectif_final' => 57]);
        $this->fiche($autre, self::J1, ['vente' => 9, 'effectif_final' => 491]);

        $c = Livewire::test(FicheLapins::class)->set('bandeId', $autre->id)->set('selectedDate', self::J1);

        $this->assertSame(9, $c->instance()->venteDuJour);
        $this->assertSame(491, (int) $c->instance()->monthlyEntries->get(self::J1)->effectif_final);
    }

    public function test_le_depart_et_la_chaine_sont_propres_a_chaque_bande(): void
    {
        $autre = $this->bande('LOT-LAP-B', 500);
        $this->departer($this->ouvrir(self::J1))->call('saveDay');          // chaîne sur A (10 / 20 / 30)

        $c = Livewire::test(FicheLapins::class)->set('bandeId', $autre->id)->set('selectedDate', self::J1);
        $this->assertSame(['0', '500', '0'], $this->ecran($c), 'B : départ déduit de SON stade, jamais celui de A');
        $this->assertDoesNotMatchRegularExpression('/\bdisabled\b/', $this->tag($c, 'depart-repro'), 'B n\'a pas encore de départ verrouillé');
    }

    // ===================================================================== D6, D8, D9, D12, départ refusé

    /**
     * 🔁 17/10/2026 — D6 : les effectifs saisis à la main restent signalés et ne sont jamais repris ; le départ
     * est déduit du stade de la bande (et non plus « à saisir »). Les fiches anciennes ne sont pas touchées.
     */
    public function test_d6_les_saisies_anciennes_ne_sont_pas_reprises_et_le_depart_est_deduit_du_stade(): void
    {
        $this->fiche($this->lot, '2026-10-03', ['effectif_final' => 60, 'cat_eff_repro' => 5, 'cat_eff_sevre' => 6, 'cat_eff_jeune' => 7]);

        $c = $this->ouvrir(self::J1);

        $this->voit($c, 'saisis à la main');
        $this->voit($c, '03/10/2026');
        $this->voit($c, 'Reproducteur 5, Jeune 7, Sous-mères 6');
        $this->assertSame(['0', '60', '0'], $this->ecran($c), 'départ déduit du stade, jamais les saisies anciennes');

        $c->set('achat', 1)->call('saveDay');
        $this->assertNull($this->entree('2026-10-03')->cat_depart_repro);
        $this->assertSame([0, 60, 0], [(int) $this->entree(self::J1)->cat_depart_repro, (int) $this->entree(self::J1)->cat_depart_sevre, (int) $this->entree(self::J1)->cat_depart_jeune]);
        $this->assertSame(5, (int) $this->entree('2026-10-03')->cat_eff_repro, 'les saisies anciennes ne sont pas touchées');
    }

    /**
     * 🔁 17/10/2026 (« faut-il corriger les bandes déjà saisies ? OUI ») — réenregistrer une fiche sans chaîne pose
     * le départ déduit du stade (0 / 60 / 0) et la chaîne RECALCULE ses catégories : 5 / 6 / 7 (somme 18 pour 60
     * sujets) devient 0 / 60 / 0.
     */
    public function test_une_bande_deja_saisie_reenregistree_est_corrigee_par_la_chaine(): void
    {
        $this->fiche($this->lot, self::J1, ['effectif_final' => 60, 'cat_eff_repro' => 5, 'cat_eff_sevre' => 6, 'cat_eff_jeune' => 7,
            'mort_repro' => 0, 'mort_sevre' => 0, 'mort_jeune' => 0, 'don_repro' => 0, 'don_sevre' => 0, 'don_jeune' => 0]);

        Livewire::test(FicheLapins::class)->call('loadDay', self::J1)->set('achat', 0)->call('saveDay');

        $f = $this->entree(self::J1);
        $this->assertSame([0, 60, 0], [(int) $f->cat_eff_repro, (int) $f->cat_eff_sevre, (int) $f->cat_eff_jeune]);
        $this->assertSame(60, (int) $f->effectif_final);
    }

    public function test_d8_somme_differente_du_total_donne_un_avertissement_date_sans_bloquer(): void
    {
        $this->jeuxComplet();

        $c = $this->ouvrir(self::J3);

        $this->assertSame(['9', '23', '0'], $this->ecran($c));
        $this->voit($c, 'Avertissement');
        $this->voit($c, '07/10/2026');
        $this->voit($c, 'somme des catégories (32)');
        $this->voit($c, 'effectif total (26)');
        // Pas de blocage : la fiche est bien enregistrée.
        $this->assertSame(26, (int) $this->entree(self::J3)->effectif_final);
    }

    public function test_pas_d_avertissement_de_somme_quand_les_categories_correspondent_au_total(): void
    {
        $c = $this->departer($this->ouvrir(self::J1))->set('achat', 2);

        $this->nevoitPas($c, 'somme des catégories (');
    }

    public function test_d9_des_morts_superieurs_a_la_veille_donnent_un_plancher_et_un_avertissement(): void
    {
        $c = $this->departer($this->ouvrir(self::J1))->set('mortRepro', 40)->set('mortChair', 30);

        $this->voit($c, 'supérieurs à l\'effectif de la veille');
        $this->assertSame(0, $c->instance()->effectifFinalCalc);

        $c->call('saveDay');
        $f = $this->entree(self::J1);
        $this->assertSame(70, (int) $f->mort, 'la saisie reste tracée');
        $this->assertSame(0, (int) $f->effectif_final, 'plancher à 0');
        $this->assertSame(0, (int) $f->cat_eff_repro);
        $this->assertSame(0, (int) $f->cat_eff_jeune);
    }

    public function test_pas_d_avertissement_d9_quand_les_morts_ne_depassent_pas_la_veille(): void
    {
        $c = $this->departer($this->ouvrir(self::J1))->set('mortRepro', 5);

        $this->nevoitPas($c, 'supérieurs à l\'effectif de la veille');
    }

    public function test_d12_un_jour_anterieur_au_depart_affiche_des_tirets(): void
    {
        $this->departer($this->ouvrir(self::J2))->call('saveDay');

        $c = $this->ouvrir(self::J1);

        $this->assertSame(['—', '—', '—'], $this->ecran($c));
        $this->voit($c, 'antérieur à l\'effectif de départ fixé le 06/10/2026');
        $this->assertSame('10', $this->affiche($c, 'depart-repro'), 'départ stocké visible et verrouillé');
        $this->assertMatchesRegularExpression('/\bdisabled\b/', $this->tag($c, 'depart-repro'));
    }

    public function test_un_depart_stocke_incoherent_affiche_le_motif_et_aucune_categorie(): void
    {
        $this->fiche($this->lot, self::J1, ['effectif_final' => 60, 'cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 31]);

        $c = $this->ouvrir(self::J2);

        $this->assertSame(['—', '—', '—'], $this->ecran($c));
        $this->voit($c, 'La somme des catégories de départ (61) ne correspond pas à l\'effectif total au début du jour de départ (60).');
    }

    public function test_d3_un_passage_superieur_a_la_categorie_source_est_refuse(): void
    {
        $c = $this->departer($this->ouvrir(self::J1))->set('passage', 21);

        $this->voit($c, 'Passage de stade refusé');
        $c->call('saveDay');
        $this->assertSame(0, LivestockDailyEntry::count(), 'D3 : un passage impossible ne s\'enregistre pas');

        $c->set('passage', 20)->call('saveDay');
        $f = $this->entree(self::J1);
        $this->assertSame([10, 0, 50], [(int) $f->cat_eff_repro, (int) $f->cat_eff_sevre, (int) $f->cat_eff_jeune]);
        $this->assertSame(60, (int) $f->effectif_final, 'le passage est un transfert : total inchangé');
    }

    // ===================================================================== (4) cascade rétroactive

    public function test_corriger_un_jour_passe_recalcule_les_jours_suivants_et_la_bande(): void
    {
        $this->jeuxComplet();
        $this->assertSame(26, (int) $this->lot->fresh()->current_quantity);

        // J1 : un mort Reproducteur de plus → R 9 puis 8 puis 8 ; total −1 sur chaque jour suivant.
        $this->ouvrir(self::J1)->set('mortRepro', 1)->call('saveDay');

        $this->assertSame(8, (int) $this->entree(self::J2)->cat_eff_repro);
        $this->assertSame(8, (int) $this->entree(self::J3)->cat_eff_repro);
        $this->assertSame(57, (int) $this->entree(self::J2)->effectif_final);
        $this->assertSame(25, (int) $this->entree(self::J3)->effectif_final);
        $this->assertSame(25, (int) $this->lot->fresh()->current_quantity);
    }

    // ===================================================================== (5) rationnement par catégorie

    public function test_le_rationnement_prend_les_effectifs_des_categories_et_garde_la_cle_stable(): void
    {
        // Libellés anciens du barème : la clé stable les rapproche toujours.
        FeedRationStandard::query()->delete();
        FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Lapine Mère / Reproducteur', 'ration_g_per_day' => 150]);
        FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Lapin Sevré', 'ration_g_per_day' => 40]);
        FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Jeune Lapin (engraissement)', 'ration_g_per_day' => 70]);

        $calcul = $this->departer($this->ouvrir(self::J1))->instance()->provendeCalculation;

        $this->assertSame(10, $calcul['repro']['effectif']);
        $this->assertSame(20, $calcul['sous_meres']['effectif']);
        $this->assertSame(30, $calcul['chair']['effectif']);
        $this->assertSame(10 * 150, $calcul['repro']['total_g']);
        $this->assertSame(20 * 40, $calcul['sous_meres']['total_g']);
        $this->assertSame(30 * 70, $calcul['chair']['total_g']);
        $this->assertSame(1500 + 800 + 2100, $calcul['total_g']);
    }

    public function test_sans_effectif_de_categorie_connu_la_provende_est_un_tiret_et_l_autonomie_n_est_pas_calculee(): void
    {
        // Seul cas encore inconnu : bande héritée au stade « ponte », qui ne relève d'aucune catégorie de lapins.
        $this->lot->update(['stage' => 'ponte']);

        $calcul = $this->ouvrir(self::J1)->instance()->provendeCalculation;

        $this->assertNull($calcul['repro']['effectif']);
        $this->assertNull($calcul['repro']['total_g']);
        $this->assertNull($calcul['total_g']);
        $this->assertNull($calcul['total_kg']);
        $this->assertSame(120, $calcul['repro']['ration'], 'la ration normative reste affichée');
    }

    public function test_une_categorie_inconnue_rend_le_total_inconnu_sans_le_prendre_pour_zero(): void
    {
        // Fiche ancienne : mouvement ventilé inconnu (null) sur la chaîne → catégorie « Jeune » inconnue.
        $this->fiche($this->lot, self::J1, ['effectif_final' => 60, 'cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30]);
        $this->fiche($this->lot, self::J2, ['effectif_final' => 60]);   // mouvements ventilés null = inconnus

        $c = $this->ouvrir(self::J3);

        $cat = $c->instance()->categoriesJour;
        $this->assertNull($cat['sevre'], 'inconnu propagé');
        $this->assertSame('—', $this->affiche($c, 'cat-eff-lapereau'));
        $this->assertNull($c->instance()->provendeCalculation['total_g']);
    }

    // ===================================================================== (6) libellés

    /** 🔁 Décision client du 17/10/2026 : glossaire Reproducteur / Jeune / Sous-mères partout. */
    public function test_le_glossaire_reproducteur_jeune_sous_meres_est_applique(): void
    {
        $html = html_entity_decode(strip_tags($this->ouvrir(self::J1)->html()));

        foreach (['Morts par catégorie', 'Dons par catégorie', 'Reproducteur', 'Jeune', 'Sous-mères', 'Achats du jour', 'Nés (Mise bas)', 'Effectif Final du Jour (Calculé dynamique)', 'Taux de Mortalité du Jour (%)', 'TOTAL PROVENDE SERVIE DU JOUR (CUMUL EN GRAMMES)'] as $libelle) {
            $this->assertStringContainsString($libelle, $html, $libelle);
        }
        foreach (['Lapin de chair', 'Lapin de Chair', 'Lapereau', 'Sevré'] as $ancien) {
            $this->assertStringNotContainsString($ancien, $html, "ancien libellé « {$ancien} »");
        }

        $source = file_get_contents(base_path('resources/views/livewire/elevage/fiche-lapins.blade.php'));
        $this->assertStringContainsString('17/10/2026', $source, 'la décision du glossaire est documentée dans la vue');
    }

    /** 🔁 17/10/2026 — le passage de stade est le SEVRAGE du jour (Sous-mères → Jeune), gardé et nommé comme tel. */
    public function test_le_passage_de_stade_est_le_sevrage_sous_meres_vers_jeune(): void
    {
        $html = html_entity_decode(strip_tags($this->ouvrir(self::J1)->html()));

        $this->assertStringContainsString('Sevrage du jour (Sous-mères → Jeune)', $html);
        $this->assertStringNotContainsString('Passage de stade', $html);
    }

    // ===================================================================== (8) le jeu complet, à l'écran ET en base

    public function test_le_jeu_calcule_a_la_main_a_l_ecran_et_en_base(): void
    {
        // ---- J1
        $c = $this->departer($this->ouvrir(self::J1))->set('achat', 2)->set('ne', 5)->set('mortLapereau', 1);
        $this->assertSame(['10', '26', '30'], $this->ecran($c));
        $this->assertSame('1200 g', $this->cellule($c, 'cat-prov-repro-g'));
        $this->assertSame('780 g', $this->cellule($c, 'cat-prov-lapereau-g'));
        $this->assertSame('1800 g', $this->cellule($c, 'cat-prov-chair-g'));
        $this->assertSame('3780 g (3.78 Kg)', $this->cellule($c, 'day-total-provende-g'));
        $c->call('saveDay');
        $f = $this->entree(self::J1);
        $this->assertSame([10, 26, 30, 66], [(int) $f->cat_eff_repro, (int) $f->cat_eff_sevre, (int) $f->cat_eff_jeune, (int) $f->effectif_final]);
        $this->assertSame(3.78, round((float) $f->feed_qty_kg, 2));

        // ---- J2
        app(RecordSaleOnFicheElevageAction::class)->execute([['lot_id' => $this->lot->id, 'qty' => 4]], self::J2);
        $c = $this->ouvrir(self::J2)->set('mortRepro', 1)->set('mortChair', 2)->set('donLapereau', 1);
        $this->assertSame(['9', '25', '24'], $this->ecran($c));
        $this->assertSame('3270 g (3.27 Kg)', $this->cellule($c, 'day-total-provende-g'));
        $c->call('saveDay');
        $f = $this->entree(self::J2);
        $this->assertSame([9, 25, 24, 58], [(int) $f->cat_eff_repro, (int) $f->cat_eff_sevre, (int) $f->cat_eff_jeune, (int) $f->effectif_final]);
        $this->assertSame(4, (int) $f->vente, 'la vente du POS n\'est pas écrasée');
        $this->assertSame(3.27, round((float) $f->feed_qty_kg, 2));

        // ---- J3
        app(RecordSaleOnFicheElevageAction::class)->execute([['lot_id' => $this->lot->id, 'qty' => 30]], self::J3);
        $c = $this->ouvrir(self::J3)->set('mortLapereau', 2);
        $this->assertSame(['9', '23', '0'], $this->ecran($c));
        $this->assertSame('1770 g (1.77 Kg)', $this->cellule($c, 'day-total-provende-g'));
        $this->assertSame(26, $c->instance()->effectifFinalCalc);
        $c->call('saveDay');
        $f = $this->entree(self::J3);
        $this->assertSame([9, 23, 0, 26], [(int) $f->cat_eff_repro, (int) $f->cat_eff_sevre, (int) $f->cat_eff_jeune, (int) $f->effectif_final]);
        $this->assertSame(32, 9 + 23 + 0, 'somme des catégories (plancher du Lapin de Chair)');
        $this->assertSame(1.77, round((float) $f->feed_qty_kg, 2));
        $this->assertSame(26, (int) $this->lot->fresh()->current_quantity);

        // ---- Rechargement : l'écran de chaque jour relit exactement la base.
        $this->assertSame(['10', '26', '30'], $this->ecran($this->ouvrir(self::J1)));
        $this->assertSame(['9', '25', '24'], $this->ecran($this->ouvrir(self::J2)));
        $this->assertSame(['9', '23', '0'], $this->ecran($this->ouvrir(self::J3)));
    }

    // ===================================================================== service : état de la chaîne pour un jour

    public function test_etat_pour_jour_du_service(): void
    {
        $svc = app(EffectifParCategorieService::class);
        $lot = $this->lot->load('species');

        $this->assertSame('sans_chaine', $svc->etatPourJour($lot, self::J1)['mode']);

        $this->fiche($lot, self::J2, ['effectif_final' => 60, 'cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30,
            'cat_eff_repro' => 10, 'cat_eff_sevre' => 20, 'cat_eff_jeune' => 30]);
        $this->fiche($lot, self::J3, ['effectif_final' => 58, 'cat_eff_repro' => 9, 'cat_eff_sevre' => 19, 'cat_eff_jeune' => 30]);

        $this->assertSame('avant_depart', $svc->etatPourJour($lot, self::J1)['mode']);
        $this->assertSame(self::J2, $svc->etatPourJour($lot, self::J1)['depart_date']);

        $jourDepart = $svc->etatPourJour($lot, self::J2);
        $this->assertSame('chaine', $jourDepart['mode']);
        $this->assertSame(['repro' => 10, 'sevre' => 20, 'jeune' => 30], $jourDepart['veille'], 'le jour du départ, la veille EST le départ (D4)');

        $apres = $svc->etatPourJour($lot, '2026-10-08');
        $this->assertSame('chaine', $apres['mode']);
        $this->assertSame(['repro' => 9, 'sevre' => 19, 'jeune' => 30], $apres['veille'], 'dernière fiche antérieure');

        $milieu = $svc->etatPourJour($lot, self::J3);
        $this->assertSame(['repro' => 10, 'sevre' => 20, 'jeune' => 30], $milieu['veille'], 'STRICTEMENT antérieure : la fiche du jour est exclue');

        $this->fiche($lot, '2026-10-01', ['effectif_final' => 60]);
        $this->assertSame('chaine', $svc->etatPourJour($lot, self::J3)['mode']);
        $this->assertNull($svc->etatPourJour($lot, self::J3)['refus']);
    }

    public function test_etat_pour_jour_refuse_un_depart_stocke_incoherent_en_tenant_compte_de_la_fiche_precedente(): void
    {
        $svc = app(EffectifParCategorieService::class);
        $lot = $this->lot->load('species');
        $this->fiche($lot, '2026-10-01', ['effectif_final' => 70]);
        // Total au début du jour de départ = 70 (fiche précédente), pas 60 (effectif initial).
        $this->fiche($lot, self::J1, ['effectif_final' => 70, 'cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 40]);

        $this->assertSame('chaine', $svc->etatPourJour($lot, self::J2)['mode']);

        LivestockDailyEntry::whereDate('entry_date', self::J1)->update(['cat_depart_jeune' => 30]);
        $etat = $svc->etatPourJour($lot, self::J2);
        $this->assertSame('refus', $etat['mode']);
        $this->assertStringContainsString('(60) ne correspond pas', $etat['refus']);
        $this->assertNull($etat['veille']);
    }

    // ===================================================================== renforts (mutations survivantes)

    public function test_changer_de_bande_recharge_le_jour_de_la_nouvelle_bande(): void
    {
        $autre = $this->bande('LOT-LAP-B', 500);
        $this->fiche($this->lot, self::J1, ['achat' => 11, 'effectif_final' => 71]);

        $c = Livewire::test(FicheLapins::class)->set('bandeId', $this->lot->id)->set('selectedDate', self::J1)->assertSet('achat', 11);
        $c->set('bandeId', $autre->id)->assertSet('achat', 0);
        $c->set('bandeId', $this->lot->id)->assertSet('achat', 11);
    }

    public function test_d9_pas_d_avertissement_quand_les_morts_egalent_exactement_la_veille(): void
    {
        $c = $this->departer($this->ouvrir(self::J1))->set('mortRepro', 10)->set('mortLapereau', 20)->set('mortChair', 30);

        $this->nevoitPas($c, 'supérieurs à l\'effectif de la veille');
        $this->assertSame(0, $c->instance()->effectifFinalCalc);
    }

    public function test_le_depart_saisi_ne_survit_pas_a_un_changement_de_jour(): void
    {
        $c = $this->departer($this->ouvrir(self::J1))->call('loadDay', self::J2);

        // Le départ corrigé à la main (10 / 20 / 30) est oublié : on retrouve le départ déduit du stade.
        $c->assertSet('departRepro', 0)->assertSet('departSevre', 60)->assertSet('departJeune', 0);
    }

    /** Livewire garde les propriétés calculées en cache pour la requête : l'écran rendu APRÈS l'enregistrement doit refléter l'état écrit. */
    public function test_apres_l_enregistrement_l_ecran_de_la_meme_requete_reflete_la_base(): void
    {
        $c = $this->departer($this->ouvrir(self::J1))->set('achat', 2);
        $this->assertDoesNotMatchRegularExpression('/\bdisabled\b/', $this->tag($c, 'depart-repro'));

        $c->call('saveDay');

        $this->assertMatchesRegularExpression('/\bdisabled\b/', $this->tag($c, 'depart-repro'), 'départ verrouillé au retour de la sauvegarde');
        $this->assertSame(['10', '22', '30'], $this->ecran($c));
        $this->assertStringContainsString('05/10', $this->texte($c));
        $this->assertSame(62, (int) $c->instance()->monthlyEntries->get(self::J1)->effectif_final);
    }

    // ===================================================================== autonomie alimentaire et prophylaxie

    private function provende(float $stockKg): Product
    {
        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);

        return Product::create([
            'sku' => 'ALI-LAP-1', 'name' => 'Provende lapins', 'category_id' => $categorie->id, 'species_id' => $this->espece->id,
            'unit' => 'kg', 'pricing_mode' => 'fourchette', 'price_min' => 300, 'price_max' => 400,
            'tva_rate' => 0, 'stock_qty' => $stockKg, 'is_active' => true,
        ]);
    }

    public function test_l_autonomie_n_est_pas_calculee_quand_la_consommation_est_inconnue(): void
    {
        $this->provende(100);
        $this->lot->update(['stage' => 'ponte']);           // stade sans catégorie : consommation inconnue

        $c = $this->ouvrir(self::J1);
        $autonomie = $c->instance()->feedAutonomy;

        $this->assertTrue($autonomie['inconnu']);
        $this->assertNull($autonomie['autonomie_jours'], 'jamais « 99 jours » sur une consommation inconnue');
        $this->assertFalse($autonomie['critique']);
        $this->voit($c, 'Autonomie alimentaire : — (Provende lapins');

        $c->call('saveDay');
        $this->assertSame(0, Notification::count(), 'aucune alerte sur un 0 inventé');
    }

    public function test_l_autonomie_est_calculee_sur_la_provende_des_categories_calculees(): void
    {
        $this->provende(100);

        // Départ 10/20/30 : 1 200 + 600 + 1 800 = 3 600 g/j = 3,6 kg/j → 100 / 3,6 = 27,8 jours.
        $c = $this->departer($this->ouvrir(self::J1));
        $autonomie = $c->instance()->feedAutonomy;
        $this->assertArrayNotHasKey('inconnu', $autonomie);
        $this->assertSame(27.8, $autonomie['autonomie_jours']);
        $this->assertFalse($autonomie['critique']);

        // Stock de 9 kg : 9 / 3,6 = 2,5 jours → critique, et l'alerte remonte à l'enregistrement.
        Product::query()->update(['stock_qty' => 9]);
        $this->assertTrue($this->departer($this->ouvrir(self::J1))->instance()->feedAutonomy['critique']);
        $this->departer($this->ouvrir(self::J1))->call('saveDay');
        $this->assertSame(1, Notification::count());
    }

    public function test_la_prophylaxie_porte_sur_la_bande_de_la_fiche(): void
    {
        $autre = $this->bande('LOT-LAP-B', 500);
        $autre->update(['created_date' => '2026-10-10']);          // A : mise en lot le 01/09 ; B : le 10/10
        $service = app(ProtocoleDuJourService::class);
        $jour = Carbon::parse(self::J2);

        $c = Livewire::test(FicheLapins::class)->set('selectedDate', self::J2);
        $this->assertSame($service->jourDeCycle($this->lot, $jour), $c->instance()->protocoleDuJour->jourDeCycle);

        $c->set('bandeId', $autre->id);
        $this->assertSame($service->jourDeCycle($autre->fresh(), $jour), $c->instance()->protocoleDuJour->jourDeCycle);
        $this->assertNotSame($service->jourDeCycle($this->lot, $jour), $service->jourDeCycle($autre->fresh(), $jour));
    }
}
