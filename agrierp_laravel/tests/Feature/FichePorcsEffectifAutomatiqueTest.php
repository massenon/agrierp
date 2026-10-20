<?php

namespace Tests\Feature;

use App\Actions\RecordSaleOnFicheElevageAction;
use App\Livewire\Elevage\FichePorcs;
use App\Models\FeedRationStandard;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Notification;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Services\EffectifParCategorieService;
use App\Services\ProtocoleDuJourService;
use App\Support\EffectifCategoriesJour;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Features\SupportTesting\Testable;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

/**
 * Ticket 15.42 — FICHE WEB PORCS : EFFECTIF AUTOMATIQUE PAR CATÉGORIE (miroir de 15.41, lapins).
 *
 * Emplacements génériques (14.12 / 15.39) : `repro` = Reproducteur ; `sevre` = Porcelet ; `jeune` = Porc Marchand
 * (maquette) / « Jeune porc » (barème, D15 : donnée du barème NON renommée). Date figée au 14/10/2026.
 *
 * ⚠️ Les valeurs attendues sont des LITTÉRAUX calculés à la main (plan du 14/10/2026 + consigne du ticket), jamais
 * produits par le service. Départ R10 / P24 / M86 (total 120), rations 2 000 / 300 / 600 g/j :
 *   J1 (achat 3, nés 9, mort Porcelet 2)            → 13/31/86  total 130  provende 26 000 + 9 300 + 51 600 = 86 900 g
 *   J2 (vente 5, mort R1, don Marchand 1)           → 12/31/80  total 123  81 300 g
 *   J3 (vente 2, mort Marchand 3, don Porcelet 1)   → 12/30/75  total 117  78 000 g
 *   J4 (mort Porcelet 40) : plancher                → 12/0/75   total 77   somme 87 ≠ 77
 */
class FichePorcsEffectifAutomatiqueTest extends TestCase
{
    use RefreshDatabase;

    private const J1 = '2026-10-05';

    private const J2 = '2026-10-06';

    private const J3 = '2026-10-07';

    private const J4 = '2026-10-08';

    private LivestockSpecies $espece;

    private LivestockLot $lot;

    protected function setUp(): void
    {
        parent::setUp();

        // Ticket S2 : l'enregistrement exige désormais `authorize()` ; l'écran est utilisé par un compte animalier.
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $compte = \App\Models\User::create([
            'name' => 'Animalier', 'username' => 'animalier-test',
            'email' => 'animalier-test@olouwachegoun.bj', 'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $compte->assignRole('animalier');
        $this->actingAs($compte);
        Carbon::setTestNow('2026-10-14 12:00:00');

        $this->espece = LivestockSpecies::create(['code' => 'porciculture', 'label' => 'Porcs', 'is_enabled' => true]);
        $this->lot = $this->bande('LOT-POR-A', 120);

        FeedRationStandard::create(['species_code' => 'porciculture', 'stage_label' => 'Porcelet', 'ration_g_per_day' => 300]);
        FeedRationStandard::create(['species_code' => 'porciculture', 'stage_label' => 'Jeune porc', 'ration_g_per_day' => 600]);
        FeedRationStandard::create(['species_code' => 'porciculture', 'stage_label' => 'Porc reproducteur', 'ration_g_per_day' => 2000]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function bande(string $code, int $initial): LivestockLot
    {
        return LivestockLot::create([
            'code' => $code, 'species_id' => $this->espece->id, 'stage' => 'engraissement',
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
        return Livewire::test(FichePorcs::class)->set('selectedDate', $jour);
    }

    private function departer(Testable $c, int $r = 10, int $p = 24, int $m = 86): Testable
    {
        return $c->set('departRepro', $r)->set('departSevre', $p)->set('departJeune', $m);
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

    /** @return array{string, string, string} effectifs affichés Reproducteur / Porcelet / Porc Marchand */
    private function ecran(Testable $c): array
    {
        return [$this->affiche($c, 'cat-eff-repro'), $this->affiche($c, 'cat-eff-porcelet'), $this->affiche($c, 'cat-eff-jeune')];
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

    private function vendre(int $qte, string $jour): void
    {
        app(RecordSaleOnFicheElevageAction::class)->execute([['lot_id' => $this->lot->id, 'qty' => $qte]], $jour);
    }

    /** Les quatre jours du jeu de la consigne, enregistrés par la fiche (départ au J1). */
    private function jeuComplet(): void
    {
        $this->departer($this->ouvrir(self::J1))
            ->set('achat', 3)->set('ne', 9)->set('mortPorcelet', 2)->call('saveDay');
        $this->vendre(5, self::J2);
        $this->ouvrir(self::J2)->set('mortRepro', 1)->set('donMarchand', 1)->call('saveDay');
        $this->vendre(2, self::J3);
        $this->ouvrir(self::J3)->set('mortMarchand', 3)->set('donPorcelet', 1)->call('saveDay');
    }

    // ===================================================================== (1) champs calculés

    public function test_les_trois_champs_d_effectif_de_categorie_sont_disabled_et_les_champs_saisis_restent_actifs(): void
    {
        $c = $this->departer($this->ouvrir(self::J1));

        foreach (['cat-eff-repro', 'cat-eff-porcelet', 'cat-eff-jeune'] as $id) {
            $this->assertMatchesRegularExpression('/\bdisabled\b/', $this->tag($c, $id), "#{$id} doit être disabled");
        }

        $html = $c->html();
        foreach (['achat', 'ne', 'mortRepro', 'mortMarchand', 'mortPorcelet', 'donRepro', 'donMarchand', 'donPorcelet', 'passage', 'effectifVerrats', 'effectifTruies', 'effectifPorcelets', 'effectifEngraissement'] as $champ) {
            $this->assertSame(1, preg_match('/<input\b[^>]*wire:model(?:\.live)?="'.$champ.'"[^>]*>/', $html, $m), "champ saisi {$champ} introuvable");
            $this->assertDoesNotMatchRegularExpression('/\bdisabled\b|\breadonly\b/', $m[0], "{$champ} doit rester actif");
        }
        // Les anciens champs de saisie manuelle n'existent plus.
        $this->assertStringNotContainsString('wire:model.live="catEffRepro"', $html);
        $this->assertStringNotContainsString('wire:model.live="catEffPorcelet"', $html);
        $this->assertStringNotContainsString('wire:model.live="catEffJeune"', $html);
    }

    /**
     * Mise à jour EN DIRECT : chaque champ saisi déplace uniquement les catégories qu'il touche.
     * Départ R10 / P24 / M86 sur une bande de 120 ; les attendus sont calculés à la main.
     *
     * @param  array{string, string, string}  $attendu
     */
    #[DataProvider('mouvementsEnDirect')]
    public function test_chaque_mouvement_met_a_jour_les_categories_en_direct(string $champ, int $valeur, array $attendu): void
    {
        $c = $this->departer($this->ouvrir(self::J1))->set($champ, $valeur);

        $this->assertSame($attendu, $this->ecran($c), "après {$champ} = {$valeur}");
    }

    /** @return array<string, array{string, int, array{string, string, string}}> */
    public static function mouvementsEnDirect(): array
    {
        return [
            'achat → Reproducteur (D11)' => ['achat', 3, ['13', '24', '86']],
            'nés → Porcelet' => ['ne', 4, ['10', '28', '86']],
            'mort Reproducteur' => ['mortRepro', 2, ['8', '24', '86']],
            'mort Porcelet' => ['mortPorcelet', 2, ['10', '22', '86']],
            'mort Porc Marchand' => ['mortMarchand', 5, ['10', '24', '81']],
            'don Reproducteur' => ['donRepro', 1, ['9', '24', '86']],
            'don Porcelet' => ['donPorcelet', 3, ['10', '21', '86']],
            'don Porc Marchand' => ['donMarchand', 4, ['10', '24', '82']],
            'passage de stade Porcelet → Marchand' => ['passage', 5, ['10', '19', '91']],
        ];
    }

    public function test_la_vente_du_pos_deduit_le_porc_marchand_en_direct(): void
    {
        $this->fiche($this->lot, self::J1, ['vente' => 6, 'effectif_final' => 114]);

        $c = $this->departer($this->ouvrir(self::J1));

        $this->assertSame(['10', '24', '80'], $this->ecran($c));
    }

    public function test_les_champs_recalcules_suivent_les_modifications_successives_sans_rechargement(): void
    {
        $c = $this->departer($this->ouvrir(self::J1))->set('mortRepro', 1);
        $this->assertSame(['9', '24', '86'], $this->ecran($c));

        $c->set('mortRepro', 0)->set('achat', 5);
        $this->assertSame(['15', '24', '86'], $this->ecran($c));

        $c->set('passage', 4);
        $this->assertSame(['15', '20', '90'], $this->ecran($c));
    }

    /** Recalcul indépendant (formules du plan réécrites ici, sans le service) sur 25 combinaisons déterministes. */
    public function test_l_ecran_egale_une_recomputation_independante_sur_25_combinaisons(): void
    {
        $graine = 7;
        $tirer = function (int $max) use (&$graine): int {
            $graine = ($graine * 1103515245 + 12345) % 2147483648;

            return $graine % ($max + 1);
        };
        $c = $this->departer($this->ouvrir(self::J1));

        for ($i = 0; $i < 25; $i++) {
            $m = ['achat' => $tirer(8), 'ne' => $tirer(12), 'mortRepro' => $tirer(14), 'mortPorcelet' => $tirer(30), 'mortMarchand' => $tirer(30),
                'donRepro' => $tirer(3), 'donPorcelet' => $tirer(10), 'donMarchand' => $tirer(10), 'passage' => $tirer(20)];

            // Source du passage : le Porcelet APRÈS ses autres mouvements du jour ; un passage plus grand serait refusé (test D3).
            $porceletAvant = 24 + $m['ne'] - $m['mortPorcelet'] - $m['donPorcelet'];
            $m['passage'] = min($m['passage'], max(0, $porceletAvant));

            foreach ($m as $champ => $valeur) {
                $c->set($champ, $valeur);
            }

            $attendu = [
                (string) max(0, 10 + $m['achat'] - $m['mortRepro'] - $m['donRepro']),
                (string) max(0, $porceletAvant - $m['passage']),
                (string) max(0, 86 - $m['mortMarchand'] - $m['donMarchand'] + $m['passage']),
            ];

            $this->assertSame($attendu, $this->ecran($c), 'combinaison '.$i.' '.json_encode($m));

            $ration = [2000, 300, 600];
            $g = (int) $attendu[0] * $ration[0] + (int) $attendu[1] * $ration[1] + (int) $attendu[2] * $ration[2];
            $this->assertSame($g.' g ('.round($g / 1000, 2).' Kg)', $this->cellule($c, 'day-total-provende-g'), 'provende combinaison '.$i);
        }
    }

    public function test_le_calcul_vient_du_service_et_pas_d_une_formule_de_la_fiche(): void
    {
        $c = $this->departer($this->ouvrir(self::J1))->set('achat', 3);

        $this->assertInstanceOf(EffectifCategoriesJour::class, $c->instance()->categoriesJour['resultat']);

        $source = file_get_contents(app_path('Livewire/Elevage/FichePorcs.php'));
        $this->assertStringContainsString('EffectifParCategorieService::calculerJour(EffectifParCategorieService::PORCS', $source);
        $this->assertStringNotContainsString('0.20', $source, 'plus de pourcentage de démonstration');
        $this->assertStringNotContainsString('0.72', $source, 'plus de pourcentage de démonstration');
    }

    // ===================================================================== (3) bande sans chaîne

    /**
     * 🔁 17/10/2026 — RATIONNEMENT AUTOMATIQUE. Bande sans chaîne, stade « engraissement » (= Porc Marchand) de 120 :
     * départ DÉDUIT du stade (0 / 0 / 120) ; provende 120 × 600 = 72 000 g sans aucune saisie.
     */
    public function test_bande_sans_chaine_le_depart_est_deduit_du_stade_et_le_rationnement_est_calcule(): void
    {
        $c = $this->ouvrir(self::J1);

        $this->assertSame(['0', '0', '120'], $this->ecran($c));
        $this->assertSame('0 g', $this->cellule($c, 'cat-prov-repro-g'));
        $this->assertSame('0 g', $this->cellule($c, 'cat-prov-porcelet-g'));
        $this->assertSame('72000 g', $this->cellule($c, 'cat-prov-jeune-g'));
        $this->assertSame('72000 g (72 Kg)', $this->cellule($c, 'day-total-provende-g'));

        // Seule une bande dont le stade ne relève d'aucune catégorie (« ponte », héritée) reste inconnue : « — », jamais 0.
        $this->lot->update(['stage' => 'ponte']);
        $this->assertSame(['—', '—', '—'], $this->ecran($this->ouvrir(self::J1)));
    }

    public function test_aucun_pourcentage_de_demonstration_du_premier_jour(): void
    {
        // La maquette répartit le premier jour à 20 % / 72 % / reste. Le départ déduit met TOUT l'effectif dans la
        // catégorie du stade de la bande : jamais une répartition inventée.
        $this->lot->update(['initial_quantity' => 100, 'current_quantity' => 100]);

        $c = $this->ouvrir(self::J1);

        $this->assertSame(['0', '0', '100'], $this->ecran($c));
        $this->assertSame(0, $c->instance()->categoriesJour['repro']);
        $this->assertSame(0, $c->instance()->categoriesJour['sevre']);
        $this->assertSame(100, $c->instance()->categoriesJour['jeune']);
    }

    public function test_bande_sans_chaine_le_formulaire_propose_l_effectif_de_depart_en_trois_champs(): void
    {
        $c = $this->ouvrir(self::J1);

        foreach (['depart-repro' => 'departRepro', 'depart-sevre' => 'departSevre', 'depart-jeune' => 'departJeune'] as $id => $modele) {
            $tag = $this->tag($c, $id);
            $this->assertNotSame('', $tag, "champ #{$id}");
            $this->assertStringContainsString('wire:model.live="'.$modele.'"', $tag);
            $this->assertDoesNotMatchRegularExpression('/\bdisabled\b|\breadonly\b/', $tag);
        }
        $this->voit($c, 'Effectif de départ');
        $this->voit($c, "l'effectif total au début du jour (120)");
        $c->assertSet('departRepro', 0)->assertSet('departSevre', 0)->assertSet('departJeune', 120);
    }

    public function test_un_depart_valide_donne_un_apercu_en_direct_avant_l_enregistrement(): void
    {
        $c = $this->departer($this->ouvrir(self::J1));

        $this->assertSame(['10', '24', '86'], $this->ecran($c));
        $this->assertSame('20000 g', $this->cellule($c, 'cat-prov-repro-g'));
        $this->assertSame('7200 g', $this->cellule($c, 'cat-prov-porcelet-g'));
        $this->assertSame('51600 g', $this->cellule($c, 'cat-prov-jeune-g'));
        $this->assertSame(0, LivestockDailyEntry::count(), 'aperçu : rien n\'est écrit');
    }

    public function test_un_depart_dont_la_somme_differe_du_total_est_refuse_avec_le_motif_visible(): void
    {
        $c = $this->departer($this->ouvrir(self::J1), 10, 24, 87);

        $this->assertSame(['—', '—', '—'], $this->ecran($c));
        $this->voit($c, 'La somme des catégories de départ (121) ne correspond pas à l\'effectif total au début du jour de départ (120).');

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
     * 🔁 17/10/2026 — sans saisie, la première fiche ENREGISTRE le départ déduit du stade (0 / 0 / 120) et démarre
     * la chaîne. Achat 2 (les achats de porcs vont aux Reproducteurs, D11) : 2 / 0 / 120, total 122 ; provende
     * 2 × 2 000 + 120 × 600 = 76 000 g = 76 kg.
     */
    public function test_sans_saisie_la_premiere_fiche_enregistre_le_depart_deduit_du_stade(): void
    {
        $this->ouvrir(self::J1)->set('achat', 2)->call('saveDay');

        $f = $this->entree(self::J1);
        $this->assertSame(122, (int) $f->effectif_final);
        $this->assertSame([0, 0, 120], [(int) $f->cat_depart_repro, (int) $f->cat_depart_sevre, (int) $f->cat_depart_jeune]);
        $this->assertSame([2, 0, 120], [(int) $f->cat_eff_repro, (int) $f->cat_eff_sevre, (int) $f->cat_eff_jeune]);
        $this->assertSame(76.0, round((float) $f->feed_qty_kg, 2));
        $this->assertTrue(app(EffectifParCategorieService::class)->aUneChaine($this->lot->id));
    }

    // ===================================================================== (3) verrouillage du départ

    public function test_le_depart_est_enregistre_une_fois_puis_verrouille(): void
    {
        $this->departer($this->ouvrir(self::J1))->set('achat', 2)->call('saveDay');

        $f = $this->entree(self::J1);
        $this->assertSame([10, 24, 86], [(int) $f->cat_depart_repro, (int) $f->cat_depart_sevre, (int) $f->cat_depart_jeune]);

        // Le jour même, rouvert : les trois champs sont visibles, verrouillés, avec les valeurs stockées.
        $c = $this->ouvrir(self::J1);
        foreach (['depart-repro' => '10', 'depart-sevre' => '24', 'depart-jeune' => '86'] as $id => $valeur) {
            $this->assertMatchesRegularExpression('/\bdisabled\b/', $this->tag($c, $id), "#{$id} verrouillé");
            $this->assertSame($valeur, $this->affiche($c, $id));
        }

        // Un autre jour : tenter de redéfinir le départ ne change rien en base.
        $this->departer($this->ouvrir(self::J2), 1, 1, 120)->call('saveDay');
        $this->assertNull($this->entree(self::J2)->cat_depart_repro);
        $f1 = $this->entree(self::J1);
        $this->assertSame([10, 24, 86], [(int) $f1->cat_depart_repro, (int) $f1->cat_depart_sevre, (int) $f1->cat_depart_jeune]);
    }

    public function test_apres_enregistrement_les_categories_sont_ecrites_par_la_chaine(): void
    {
        $this->departer($this->ouvrir(self::J1))->set('achat', 3)->set('ne', 9)->set('mortPorcelet', 2)->call('saveDay');

        $f = $this->entree(self::J1);
        $this->assertSame([13, 31, 86], [(int) $f->cat_eff_repro, (int) $f->cat_eff_sevre, (int) $f->cat_eff_jeune]);
        $this->assertSame(130, (int) $f->effectif_final);
        $this->assertSame(130, (int) $this->lot->fresh()->current_quantity);
    }

    // ===================================================================== (2) persistance et rechargement

    public function test_les_mouvements_par_categorie_sont_persistes_dans_les_bonnes_colonnes(): void
    {
        $this->departer($this->ouvrir(self::J1))
            ->set('mortRepro', 1)->set('mortPorcelet', 2)->set('mortMarchand', 3)
            ->set('donRepro', 4)->set('donPorcelet', 5)->set('donMarchand', 6)
            ->set('passage', 7)->call('saveDay');

        $f = $this->entree(self::J1);
        $this->assertSame([1, 2, 3], [(int) $f->mort_repro, (int) $f->mort_sevre, (int) $f->mort_jeune], 'morts : Reproducteur / Porcelet / Marchand');
        $this->assertSame([4, 5, 6], [(int) $f->don_repro, (int) $f->don_sevre, (int) $f->don_jeune], 'dons');
        $this->assertSame(7, (int) $f->passage_sevre_jeune);
        $this->assertSame(6, (int) $f->mort);
        $this->assertSame(15, (int) $f->don);
    }

    /** Défaut (a) : un jour existant rechargé remet les compteurs de morts et de dons. */
    public function test_un_jour_existant_recharge_les_compteurs_de_morts_dons_et_passage(): void
    {
        $this->departer($this->ouvrir(self::J1))
            ->set('mortRepro', 1)->set('mortPorcelet', 2)->set('mortMarchand', 3)
            ->set('donRepro', 4)->set('donPorcelet', 5)->set('donMarchand', 6)
            ->set('passage', 7)->set('achat', 9)->set('ne', 8)->call('saveDay');

        Livewire::test(FichePorcs::class)
            ->call('loadDay', self::J1)
            ->assertSet('mortRepro', 1)->assertSet('mortPorcelet', 2)->assertSet('mortMarchand', 3)
            ->assertSet('donRepro', 4)->assertSet('donPorcelet', 5)->assertSet('donMarchand', 6)
            ->assertSet('passage', 7)->assertSet('achat', 9)->assertSet('ne', 8);
    }

    public function test_reenregistrer_un_jour_recharge_ne_reecrit_pas_les_morts_et_dons_avec_des_valeurs_perimees(): void
    {
        $this->departer($this->ouvrir(self::J1))->set('mortRepro', 1)->set('mortMarchand', 2)->set('donPorcelet', 3)->call('saveDay');

        $c = Livewire::test(FichePorcs::class)->call('loadDay', self::J1);
        $c->call('loadDay', self::J2)->assertSet('mortRepro', 0)->assertSet('mortMarchand', 0)->assertSet('donPorcelet', 0);
        $c->call('loadDay', self::J1)->call('saveDay');

        $f = $this->entree(self::J1);
        $this->assertSame(3, (int) $f->mort);
        $this->assertSame(3, (int) $f->don);
        $this->assertSame([1, 0, 2], [(int) $f->mort_repro, (int) $f->mort_sevre, (int) $f->mort_jeune]);
    }

    public function test_une_fiche_ancienne_non_ventilee_ne_voit_pas_ses_morts_efface_en_silence(): void
    {
        $this->fiche($this->lot, self::J1, ['mort' => 3, 'don' => 2, 'effectif_final' => 115]);

        $c = Livewire::test(FichePorcs::class)->call('loadDay', self::J1);
        $this->voit($c, 'non ventilé');
        $c->call('saveDay');
        $this->assertSame(3, (int) $this->entree(self::J1)->mort, 'refus : les morts ne sont pas remis à zéro');
        $this->assertSame(2, (int) $this->entree(self::J1)->don);
        $this->assertNull($this->entree(self::J1)->mort_repro);

        $c->set('mortRepro', 1)->set('mortMarchand', 2)->set('donPorcelet', 2)->call('saveDay');
        $f = $this->entree(self::J1);
        $this->assertSame([1, 0, 2], [(int) $f->mort_repro, (int) $f->mort_sevre, (int) $f->mort_jeune]);
        $this->assertSame(3, (int) $f->mort);
    }

    /** Défaut (b) : changer la date appelle loadDay. */
    public function test_changer_la_date_charge_le_jour_choisi(): void
    {
        $this->fiche($this->lot, self::J2, ['achat' => 7, 'ne' => 3, 'mort' => 2, 'mort_repro' => 1, 'mort_sevre' => 1, 'mort_jeune' => 0,
            'don_repro' => 0, 'don_sevre' => 0, 'don_jeune' => 0, 'effectif_final' => 128]);

        $c = Livewire::test(FichePorcs::class)->set('selectedDate', self::J2);

        $c->assertSet('achat', 7)->assertSet('ne', 3)->assertSet('mortRepro', 1)->assertSet('mortPorcelet', 1);

        $c->set('selectedDate', self::J1)->assertSet('achat', 0)->assertSet('mortRepro', 0);
    }

    public function test_un_jour_d_un_autre_mois_se_charge_aussi(): void
    {
        $this->fiche($this->lot, '2026-09-20', ['achat' => 4, 'effectif_final' => 124]);

        Livewire::test(FichePorcs::class)->set('selectedDate', '2026-09-20')->assertSet('achat', 4);
    }

    public function test_une_date_vide_ou_invalide_est_ignoree_sans_erreur(): void
    {
        Livewire::test(FichePorcs::class)->set('selectedDate', '')->assertOk();
        Livewire::test(FichePorcs::class)->set('selectedDate', 'pas-une-date')->assertOk();
    }

    public function test_a_l_ouverture_le_jour_courant_deja_saisi_est_charge(): void
    {
        $this->fiche($this->lot, '2026-10-14', ['achat' => 6, 'effectif_final' => 126]);

        Livewire::test(FichePorcs::class)->assertSet('achat', 6);
    }

    public function test_sans_bande_active_la_fiche_s_affiche_et_l_enregistrement_est_refuse_sans_erreur(): void
    {
        $this->lot->update(['is_active' => false]);

        $c = Livewire::test(FichePorcs::class)->assertOk();
        $c->call('saveDay')->assertOk();
        $this->assertSame(0, LivestockDailyEntry::count());
    }

    // ===================================================================== (2) défaut (c) : LA bande de la fiche

    public function test_la_veille_porte_sur_la_bande_de_la_fiche_et_non_sur_toutes_les_bandes(): void
    {
        $autre = $this->bande('LOT-POR-B', 500);
        $this->fiche($autre, self::J1, ['achat' => 0, 'effectif_final' => 480]);   // plus récente que la fiche de A
        $this->fiche($this->lot, '2026-10-02', ['effectif_final' => 118]);

        $c = Livewire::test(FichePorcs::class)->set('bandeId', $this->lot->id)->set('selectedDate', self::J2);

        $this->assertSame(118, $c->instance()->previousEffectif, 'la veille de A est la fiche de A (118), pas celle de B (480)');

        $c->set('bandeId', $autre->id);
        $this->assertSame(480, $c->instance()->previousEffectif);
    }

    public function test_l_enregistrement_et_le_chargement_portent_sur_la_bande_choisie(): void
    {
        $autre = $this->bande('LOT-POR-B', 500);
        $this->fiche($this->lot, self::J1, ['achat' => 11, 'effectif_final' => 131]);

        $c = Livewire::test(FichePorcs::class)->set('bandeId', $autre->id)->set('selectedDate', self::J1);
        $c->assertSet('achat', 0);                  // la fiche de A n'est pas celle de B
        $c->set('achat', 4)->call('saveDay');

        $this->assertSame(504, (int) $this->entree(self::J1, $autre)->effectif_final);
        $this->assertSame(131, (int) $this->entree(self::J1, $this->lot)->effectif_final, 'la bande A n\'est pas touchée');
        $this->assertSame(504, (int) $autre->fresh()->current_quantity);
        $this->assertSame(120, (int) $this->lot->fresh()->current_quantity, 'la bande A n\'est pas touchée non plus');
    }

    public function test_le_tableau_mensuel_et_la_vente_du_jour_suivent_la_bande_choisie(): void
    {
        $autre = $this->bande('LOT-POR-B', 500);
        $this->fiche($this->lot, self::J1, ['vente' => 3, 'effectif_final' => 117]);
        $this->fiche($autre, self::J1, ['vente' => 9, 'effectif_final' => 491]);

        $c = Livewire::test(FichePorcs::class)->set('bandeId', $autre->id)->set('selectedDate', self::J1);

        $this->assertSame(9, $c->instance()->venteDuJour);
        $this->assertSame(491, (int) $c->instance()->monthlyEntries->get(self::J1)->effectif_final);

        // Le tableau mensuel est celui d'UNE bande : une fiche de l'autre bande à un autre jour n'y figure pas.
        $this->fiche($autre, self::J2, ['effectif_final' => 490]);
        $deA = Livewire::test(FichePorcs::class)->set('bandeId', $this->lot->id);
        $this->assertSame([self::J1], $deA->instance()->monthlyEntries->keys()->all());
        $deB = Livewire::test(FichePorcs::class)->set('bandeId', $autre->id);
        $this->assertSame([self::J1, self::J2], $deB->instance()->monthlyEntries->keys()->all());
        $this->assertSame(117, (int) $deA->instance()->monthlyEntries->get(self::J1)->effectif_final);
    }

    public function test_le_depart_et_la_chaine_sont_propres_a_chaque_bande(): void
    {
        $autre = $this->bande('LOT-POR-B', 500);
        $this->departer($this->ouvrir(self::J1))->call('saveDay');          // chaîne sur A

        $c = Livewire::test(FichePorcs::class)->set('bandeId', $autre->id)->set('selectedDate', self::J1);
        $this->assertSame(['0', '0', '500'], $this->ecran($c), 'B : départ déduit de SON stade, jamais celui de A');
        $this->assertDoesNotMatchRegularExpression('/\bdisabled\b/', $this->tag($c, 'depart-repro'), 'B n\'a pas encore de départ verrouillé');
    }

    public function test_changer_de_bande_recharge_le_jour_de_la_nouvelle_bande(): void
    {
        $autre = $this->bande('LOT-POR-B', 500);
        $this->fiche($this->lot, self::J1, ['achat' => 11, 'effectif_final' => 131]);

        $c = Livewire::test(FichePorcs::class)->set('bandeId', $this->lot->id)->set('selectedDate', self::J1)->assertSet('achat', 11);
        $c->set('bandeId', $autre->id)->assertSet('achat', 0);
        $c->set('bandeId', $this->lot->id)->assertSet('achat', 11);
    }

    public function test_le_selecteur_de_bande_n_apparait_qu_avec_plusieurs_bandes(): void
    {
        $this->assertStringNotContainsString('id="bande-fiche"', Livewire::test(FichePorcs::class)->html());

        $this->bande('LOT-POR-B', 500);
        $this->assertStringContainsString('id="bande-fiche"', Livewire::test(FichePorcs::class)->html());
    }

    // ===================================================================== D6, D8, D9, D12, départ refusé

    /** 🔁 17/10/2026 — D6 : les saisies anciennes restent signalées, jamais reprises ; le départ est déduit du stade. */
    public function test_d6_les_saisies_anciennes_ne_sont_pas_reprises_et_le_depart_est_deduit_du_stade(): void
    {
        $this->fiche($this->lot, '2026-10-03', ['effectif_final' => 120, 'cat_eff_repro' => 5, 'cat_eff_sevre' => 6, 'cat_eff_jeune' => 109]);

        $c = $this->ouvrir(self::J1);

        $this->voit($c, 'saisis à la main');
        $this->voit($c, '03/10/2026');
        $this->assertSame(['0', '0', '120'], $this->ecran($c), 'départ déduit du stade, jamais les saisies anciennes');

        $c->set('achat', 1)->call('saveDay');
        $this->assertNull($this->entree('2026-10-03')->cat_depart_repro);
        $this->assertSame([0, 0, 120], [(int) $this->entree(self::J1)->cat_depart_repro, (int) $this->entree(self::J1)->cat_depart_sevre, (int) $this->entree(self::J1)->cat_depart_jeune]);
        $this->assertSame(5, (int) $this->entree('2026-10-03')->cat_eff_repro, 'les saisies anciennes ne sont pas touchées');
    }

    /** 🔁 17/10/2026 — une bande déjà saisie, réenregistrée, est CORRIGÉE par la chaîne : 5 / 6 / 109 devient 0 / 0 / 120. */
    public function test_une_bande_deja_saisie_reenregistree_est_corrigee_par_la_chaine(): void
    {
        $this->fiche($this->lot, self::J1, ['effectif_final' => 120, 'cat_eff_repro' => 5, 'cat_eff_sevre' => 6, 'cat_eff_jeune' => 109,
            'mort_repro' => 0, 'mort_sevre' => 0, 'mort_jeune' => 0, 'don_repro' => 0, 'don_sevre' => 0, 'don_jeune' => 0]);

        Livewire::test(FichePorcs::class)->call('loadDay', self::J1)->set('achat', 0)->call('saveDay');

        $f = $this->entree(self::J1);
        $this->assertSame([0, 0, 120], [(int) $f->cat_eff_repro, (int) $f->cat_eff_sevre, (int) $f->cat_eff_jeune]);
    }

    public function test_d8_somme_differente_du_total_donne_un_avertissement_date_sans_bloquer(): void
    {
        $this->jeuComplet();
        $this->ouvrir(self::J4)->set('mortPorcelet', 40)->call('saveDay');

        $c = $this->ouvrir(self::J4);

        $this->assertSame(['12', '0', '75'], $this->ecran($c));
        $this->voit($c, 'Avertissement');
        $this->voit($c, '08/10/2026');
        $this->voit($c, 'somme des catégories (87)');
        $this->voit($c, 'effectif total (77)');
        // Pas de blocage : la fiche est bien enregistrée.
        $this->assertSame(77, (int) $this->entree(self::J4)->effectif_final);
    }

    public function test_pas_d_avertissement_de_somme_quand_les_categories_correspondent_au_total(): void
    {
        $c = $this->departer($this->ouvrir(self::J1))->set('achat', 2);

        $this->nevoitPas($c, 'somme des catégories (');
    }

    public function test_d9_des_morts_superieurs_a_la_veille_donnent_un_plancher_et_un_avertissement(): void
    {
        $c = $this->departer($this->ouvrir(self::J1))->set('mortRepro', 40)->set('mortMarchand', 90);

        $this->voit($c, 'supérieurs à l\'effectif de la veille');
        $this->assertSame(0, $c->instance()->effectifFinalCalc);

        $c->call('saveDay');
        $f = $this->entree(self::J1);
        $this->assertSame(130, (int) $f->mort, 'la saisie reste tracée');
        $this->assertSame(0, (int) $f->effectif_final, 'plancher à 0');
        $this->assertSame(0, (int) $f->cat_eff_repro);
        $this->assertSame(0, (int) $f->cat_eff_jeune);
        $this->assertSame(24, (int) $f->cat_eff_sevre);
    }

    public function test_pas_d_avertissement_d9_quand_les_morts_ne_depassent_pas_la_veille(): void
    {
        $c = $this->departer($this->ouvrir(self::J1))->set('mortRepro', 5);

        $this->nevoitPas($c, 'supérieurs à l\'effectif de la veille');
    }

    public function test_d9_pas_d_avertissement_quand_les_morts_egalent_exactement_la_veille(): void
    {
        $c = $this->departer($this->ouvrir(self::J1))->set('mortRepro', 10)->set('mortPorcelet', 24)->set('mortMarchand', 86);

        $this->nevoitPas($c, 'supérieurs à l\'effectif de la veille');
        $this->assertSame(0, $c->instance()->effectifFinalCalc);
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
        $this->fiche($this->lot, self::J1, ['effectif_final' => 120, 'cat_depart_repro' => 10, 'cat_depart_sevre' => 24, 'cat_depart_jeune' => 87]);

        $c = $this->ouvrir(self::J2);

        $this->assertSame(['—', '—', '—'], $this->ecran($c));
        $this->voit($c, 'La somme des catégories de départ (121) ne correspond pas à l\'effectif total au début du jour de départ (120).');
    }

    public function test_d3_un_passage_superieur_a_la_categorie_source_est_refuse(): void
    {
        $c = $this->departer($this->ouvrir(self::J1))->set('passage', 25);

        $this->voit($c, 'Passage de stade refusé');
        $c->call('saveDay');
        $this->assertSame(0, LivestockDailyEntry::count(), 'D3 : un passage impossible ne s\'enregistre pas');

        $c->set('passage', 24)->call('saveDay');
        $f = $this->entree(self::J1);
        $this->assertSame([10, 0, 110], [(int) $f->cat_eff_repro, (int) $f->cat_eff_sevre, (int) $f->cat_eff_jeune]);
        $this->assertSame(120, (int) $f->effectif_final, 'le passage est un transfert : total inchangé');
    }

    /** La source est contrôlée APRÈS ses autres mouvements du jour (nés, morts, dons Porcelet). */
    public function test_d3_la_source_est_celle_apres_les_autres_mouvements_du_jour(): void
    {
        $c = $this->departer($this->ouvrir(self::J1))->set('ne', 6)->set('passage', 30);
        $this->nevoitPas($c, 'Passage de stade refusé');
        $this->assertSame(['10', '0', '116'], $this->ecran($c));

        $c->set('passage', 31);
        $this->voit($c, 'Passage de stade refusé');

        // Source = 24 + 6 nés − 4 morts − 2 dons = 24 : 25 est refusé, 24 accepté.
        $c->set('passage', 0)->set('mortPorcelet', 4)->set('donPorcelet', 2)->set('passage', 25);
        $this->voit($c, 'Passage de stade refusé');
        $c->set('passage', 24);
        $this->nevoitPas($c, 'Passage de stade refusé');
        $this->assertSame(['10', '0', '110'], $this->ecran($c));
    }

    // ===================================================================== (4) cascade rétroactive

    public function test_corriger_un_jour_passe_recalcule_les_jours_suivants_et_la_bande(): void
    {
        $this->jeuComplet();
        $this->assertSame(117, (int) $this->lot->fresh()->current_quantity);

        // J1 : un mort Reproducteur de plus → R 12 puis 11 puis 11 ; total −1 sur chaque jour suivant.
        $this->ouvrir(self::J1)->set('mortRepro', 1)->call('saveDay');

        $this->assertSame(11, (int) $this->entree(self::J2)->cat_eff_repro);
        $this->assertSame(11, (int) $this->entree(self::J3)->cat_eff_repro);
        $this->assertSame(122, (int) $this->entree(self::J2)->effectif_final);
        $this->assertSame(116, (int) $this->entree(self::J3)->effectif_final);
        $this->assertSame(116, (int) $this->lot->fresh()->current_quantity);
    }

    // ===================================================================== (5) rationnement par catégorie

    public function test_le_rationnement_prend_les_effectifs_des_categories_et_les_rations_du_bareme(): void
    {
        FeedRationStandard::query()->delete();
        FeedRationStandard::create(['species_code' => 'porciculture', 'stage_label' => 'Porcelet', 'ration_g_per_day' => 350]);
        FeedRationStandard::create(['species_code' => 'porciculture', 'stage_label' => 'Jeune porc', 'ration_g_per_day' => 700]);
        FeedRationStandard::create(['species_code' => 'porciculture', 'stage_label' => 'Porc reproducteur', 'ration_g_per_day' => 2500]);

        $calcul = $this->departer($this->ouvrir(self::J1))->instance()->provendeCalculation;

        $this->assertSame(10, $calcul['repro']['effectif']);
        $this->assertSame(24, $calcul['porcelet']['effectif']);
        $this->assertSame(86, $calcul['jeune']['effectif']);
        $this->assertSame(10 * 2500, $calcul['repro']['total_g']);
        $this->assertSame(24 * 350, $calcul['porcelet']['total_g']);
        $this->assertSame(86 * 700, $calcul['jeune']['total_g']);
        $this->assertSame(25000 + 8400 + 60200, $calcul['total_g']);
    }

    public function test_sans_effectif_de_categorie_connu_la_provende_est_un_tiret_et_l_autonomie_n_est_pas_calculee(): void
    {
        // Seul cas encore inconnu : bande héritée au stade « ponte », qui ne relève d'aucune catégorie de porcs.
        $this->lot->update(['stage' => 'ponte']);

        $calcul = $this->ouvrir(self::J1)->instance()->provendeCalculation;

        $this->assertNull($calcul['repro']['effectif']);
        $this->assertNull($calcul['repro']['total_g']);
        $this->assertNull($calcul['total_g']);
        $this->assertNull($calcul['total_kg']);
        $this->assertSame(2000, $calcul['repro']['ration'], 'la ration normative reste affichée');
        $this->assertSame(300, $calcul['porcelet']['ration']);
        $this->assertSame(600, $calcul['jeune']['ration']);
    }

    public function test_une_categorie_inconnue_rend_le_total_inconnu_sans_le_prendre_pour_zero(): void
    {
        $this->fiche($this->lot, self::J1, ['effectif_final' => 120, 'cat_depart_repro' => 10, 'cat_depart_sevre' => 24, 'cat_depart_jeune' => 86]);
        $this->fiche($this->lot, self::J2, ['effectif_final' => 120]);   // mouvements ventilés null = inconnus

        $c = $this->ouvrir(self::J3);

        $cat = $c->instance()->categoriesJour;
        $this->assertNull($cat['sevre'], 'inconnu propagé');
        $this->assertSame('—', $this->affiche($c, 'cat-eff-porcelet'));
        $this->assertNull($c->instance()->provendeCalculation['total_g']);
    }

    // ===================================================================== (6) libellés

    public function test_les_libelles_de_la_maquette_sont_respectes(): void
    {
        $html = html_entity_decode(strip_tags($this->ouvrir(self::J1)->html()));

        foreach (['Morts par catégorie', 'Dons par catégorie', 'Achats du jour', 'Nés (Mise bas porcelets)', 'Effectif Final du Jour (Calculé dynamique)', 'Taux de Mortalité du Jour (%)', 'TOTAL PROVENDE SERVIE DU JOUR (CUMUL EN GRAMMES)'] as $libelle) {
            $this->assertStringContainsString($libelle, $html, $libelle);
        }

        // Tableau de rationnement : lignes « Porcelet » / « Porc Marchand » / « Reproducteur » (maquette), dans cet ordre.
        $tableau = preg_replace('/\s+/u', ' ', strip_tags($this->tableauRation($this->ouvrir(self::J1))));
        $this->assertNotSame('', $tableau);
        $p = mb_strpos($tableau, 'Porcelet');
        $m = mb_strpos($tableau, 'Porc Marchand');
        $r = mb_strpos($tableau, 'Reproducteur');
        $this->assertNotFalse($p);
        $this->assertNotFalse($m);
        $this->assertNotFalse($r);
        $this->assertTrue($p < $m && $m < $r, 'ordre de la maquette : Porcelet, Porc Marchand, Reproducteur');
        $this->assertStringNotContainsString('Jeune porc', $html, 'D15 : le libellé du barème n\'est pas affiché à la place de celui de la maquette');
    }

    private function tableauRation(Testable $c): string
    {
        preg_match('/<table[^>]*>(?:(?!<\/table>).)*Ration Normative.*?<\/table>/s', $c->html(), $m);

        return $m[0] ?? '';
    }

    public function test_d15_le_libelle_du_bareme_n_est_pas_renomme(): void
    {
        $graine = file_get_contents(database_path('seeders/FeedRationStandardsSeeder.php'));
        $this->assertStringContainsString("'stage_label' => 'Jeune porc'", $graine, 'D15 : donnée du barème conservée (« Jeune porc »)');
        $vue = file_get_contents(resource_path('views/livewire/elevage/fiche-porcs.blade.php'));
        $this->assertStringContainsString('D15', $vue, 'l\'écart « Porc Marchand » / « Jeune porc » est signalé dans la vue');
    }

    public function test_le_passage_de_stade_est_un_champ_saisi_hors_maquette_et_dit_comme_tel(): void
    {
        $html = html_entity_decode(strip_tags($this->ouvrir(self::J1)->html()));

        $this->assertStringContainsString('Passage de stade', $html);
        $this->assertStringContainsString('Porcelet → Porc Marchand', $html);
        $this->assertStringContainsString('hors maquette', $html);
    }

    // ===================================================================== (8) le jeu complet, à l'écran ET en base

    public function test_le_jeu_calcule_a_la_main_a_l_ecran_et_en_base(): void
    {
        // ---- J1
        $c = $this->departer($this->ouvrir(self::J1))->set('achat', 3)->set('ne', 9)->set('mortPorcelet', 2);
        $this->assertSame(['13', '31', '86'], $this->ecran($c));
        $this->assertSame('26000 g', $this->cellule($c, 'cat-prov-repro-g'));
        $this->assertSame('9300 g', $this->cellule($c, 'cat-prov-porcelet-g'));
        $this->assertSame('51600 g', $this->cellule($c, 'cat-prov-jeune-g'));
        $this->assertSame('86900 g (86.9 Kg)', $this->cellule($c, 'day-total-provende-g'));
        $this->assertSame(130, $c->instance()->effectifFinalCalc);
        $c->call('saveDay');
        $f = $this->entree(self::J1);
        $this->assertSame([13, 31, 86, 130], [(int) $f->cat_eff_repro, (int) $f->cat_eff_sevre, (int) $f->cat_eff_jeune, (int) $f->effectif_final]);
        $this->assertSame(86.9, round((float) $f->feed_qty_kg, 2));

        // ---- J2
        $this->vendre(5, self::J2);
        $c = $this->ouvrir(self::J2)->set('mortRepro', 1)->set('donMarchand', 1);
        $this->assertSame(['12', '31', '80'], $this->ecran($c));
        $this->assertSame('81300 g (81.3 Kg)', $this->cellule($c, 'day-total-provende-g'));
        $c->call('saveDay');
        $f = $this->entree(self::J2);
        $this->assertSame([12, 31, 80, 123], [(int) $f->cat_eff_repro, (int) $f->cat_eff_sevre, (int) $f->cat_eff_jeune, (int) $f->effectif_final]);
        $this->assertSame(5, (int) $f->vente, 'la vente du POS n\'est pas écrasée');
        $this->assertSame(81.3, round((float) $f->feed_qty_kg, 2));

        // ---- J3
        $this->vendre(2, self::J3);
        $c = $this->ouvrir(self::J3)->set('mortMarchand', 3)->set('donPorcelet', 1);
        $this->assertSame(['12', '30', '75'], $this->ecran($c));
        $this->assertSame('78000 g (78 Kg)', $this->cellule($c, 'day-total-provende-g'));
        $c->call('saveDay');
        $f = $this->entree(self::J3);
        $this->assertSame([12, 30, 75, 117], [(int) $f->cat_eff_repro, (int) $f->cat_eff_sevre, (int) $f->cat_eff_jeune, (int) $f->effectif_final]);
        $this->assertSame(78.0, round((float) $f->feed_qty_kg, 2));

        // ---- J4 : plancher (mort Porcelet 40 > 30)
        $c = $this->ouvrir(self::J4)->set('mortPorcelet', 40);
        $this->assertSame(['12', '0', '75'], $this->ecran($c));
        $this->assertSame(77, $c->instance()->effectifFinalCalc);
        $c->call('saveDay');
        $f = $this->entree(self::J4);
        $this->assertSame([12, 0, 75, 77], [(int) $f->cat_eff_repro, (int) $f->cat_eff_sevre, (int) $f->cat_eff_jeune, (int) $f->effectif_final]);
        $this->assertSame(87, 12 + 0 + 75, 'somme des catégories (plancher du Porcelet)');
        $this->assertSame(40, (int) $f->mort, 'la saisie reste tracée');
        $this->assertSame(77, (int) $this->lot->fresh()->current_quantity);

        // ---- Rechargement : l'écran de chaque jour relit exactement la base.
        $this->assertSame(['13', '31', '86'], $this->ecran($this->ouvrir(self::J1)));
        $this->assertSame(['12', '31', '80'], $this->ecran($this->ouvrir(self::J2)));
        $this->assertSame(['12', '30', '75'], $this->ecran($this->ouvrir(self::J3)));
        $this->assertSame(['12', '0', '75'], $this->ecran($this->ouvrir(self::J4)));
    }

    // ===================================================================== renforts

    /** Livewire garde les propriétés calculées en cache pour la requête : l'écran rendu APRÈS l'enregistrement doit refléter l'état écrit. */
    public function test_apres_l_enregistrement_l_ecran_de_la_meme_requete_reflete_la_base(): void
    {
        $c = $this->departer($this->ouvrir(self::J1))->set('achat', 2);
        $this->assertDoesNotMatchRegularExpression('/\bdisabled\b/', $this->tag($c, 'depart-repro'));

        $c->call('saveDay');

        $this->assertMatchesRegularExpression('/\bdisabled\b/', $this->tag($c, 'depart-repro'), 'départ verrouillé au retour de la sauvegarde');
        $this->assertSame(['12', '24', '86'], $this->ecran($c));
        $this->assertStringContainsString('05/10', $this->texte($c));
        $this->assertSame(122, (int) $c->instance()->monthlyEntries->get(self::J1)->effectif_final);
    }

    public function test_le_depart_saisi_ne_survit_pas_a_un_changement_de_jour(): void
    {
        $c = $this->departer($this->ouvrir(self::J1))->call('loadDay', self::J2);

        // Le départ corrigé à la main est oublié : on retrouve le départ déduit du stade.
        $c->assertSet('departRepro', 0)->assertSet('departSevre', 0)->assertSet('departJeune', 120);
    }

    public function test_etat_pour_jour_du_service_sur_les_porcs(): void
    {
        $svc = app(EffectifParCategorieService::class);
        $lot = $this->lot->load('species');

        $this->assertSame('sans_chaine', $svc->etatPourJour($lot, self::J1)['mode']);

        $this->departer($this->ouvrir(self::J2))->call('saveDay');

        $this->assertSame('avant_depart', $svc->etatPourJour($lot, self::J1)['mode']);
        $this->assertSame(['repro' => 10, 'sevre' => 24, 'jeune' => 86], $svc->etatPourJour($lot, self::J2)['veille']);
    }

    // ===================================================================== autonomie alimentaire

    private function provende(float $stockKg): Product
    {
        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);

        return Product::create([
            'sku' => 'ALI-POR-1', 'name' => 'Provende porcs', 'category_id' => $categorie->id, 'species_id' => $this->espece->id,
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
        $this->voit($c, 'Autonomie alimentaire : — (Provende porcs');

        $c->call('saveDay');
        $this->assertSame(0, Notification::count(), 'aucune alerte sur un 0 inventé');
    }

    public function test_l_autonomie_est_calculee_sur_la_provende_des_categories_calculees(): void
    {
        $this->provende(788);

        // Départ 10/24/86 : 20 000 + 7 200 + 51 600 = 78 800 g/j = 78,8 kg/j → 788 / 78,8 = 10,0 jours.
        $c = $this->departer($this->ouvrir(self::J1));
        $autonomie = $c->instance()->feedAutonomy;
        $this->assertArrayNotHasKey('inconnu', $autonomie);
        $this->assertSame(10.0, $autonomie['autonomie_jours']);
        $this->assertFalse($autonomie['critique']);

        // Stock de 210 kg (maquette) : 210 / 78,8 = 2,7 jours → critique, et l'alerte remonte à l'enregistrement.
        Product::query()->update(['stock_qty' => 210]);
        $this->assertTrue($this->departer($this->ouvrir(self::J1))->instance()->feedAutonomy['critique']);
        $this->departer($this->ouvrir(self::J1))->call('saveDay');
        $this->assertSame(1, Notification::count());
    }

    // ===================================================================== prophylaxie (15.35) inchangée

    public function test_la_prophylaxie_porte_sur_la_bande_de_la_fiche(): void
    {
        $autre = $this->bande('LOT-POR-B', 500);
        $autre->update(['created_date' => '2026-10-10']);          // A : mise en lot le 01/09 ; B : le 10/10
        $service = app(ProtocoleDuJourService::class);
        $jour = Carbon::parse(self::J2);

        $c = Livewire::test(FichePorcs::class)->set('selectedDate', self::J2);
        $this->assertSame($service->jourDeCycle($this->lot, $jour), $c->instance()->protocoleDuJour->jourDeCycle);

        $c->set('bandeId', $autre->id);
        $this->assertSame($service->jourDeCycle($autre->fresh(), $jour), $c->instance()->protocoleDuJour->jourDeCycle);
        $this->assertNotSame($service->jourDeCycle($this->lot, $jour), $service->jourDeCycle($autre->fresh(), $jour));
    }
}
