<?php

namespace Database\Seeders\Demo;

use App\Actions\AdjustStockAction;
use App\Models\Animal;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockReproductionEvent;
use App\Models\VeterinaryCalendarEvent;
use App\Models\VeterinaryRecord;
use App\Models\VeterinaryWithdrawalPeriod;
use Carbon\CarbonImmutable;
use Illuminate\Database\Seeder;

/**
 * Ticket 14.31 (Sprint 14) — ÉLEVAGE : cinq mois de fiches journalières.
 *
 * ⚠️ L'ARITHMÉTIQUE DE CHEPTEL EST LA RAISON D'ÊTRE DE CE SEEDER. Chaque
 * journée applique la formule universelle du projet
 * (`FORMULE_FICHE_ELEVAGE.md`, reprise dans `LivestockDailyEntry`) :
 *
 *     Effectif Final = Effectif(J-1) + Achats + Nés − (Morts + Ventes + Dons)
 *
 * L'effectif de chaque jour est donc DÉRIVÉ du précédent, jamais tiré au sort.
 * Un jeu de démonstration où les effectifs sauteraient d'un jour à l'autre
 * invaliderait tout ce qui s'appuie dessus — taux de mortalité, courbes de
 * croissance, autonomie alimentaire, valorisation du cheptel — et donnerait
 * une fausse confiance dans des écrans qui, eux, calculent juste.
 *
 * ⚠️ LA PROVENDE CONSOMMÉE SORT RÉELLEMENT DU STOCK, via `AdjustStockAction`.
 * C'est ce qui relie les achats du seeder précédent aux fiches d'élevage :
 * sans cette sortie, le stock d'aliment ne baisserait jamais et l'alerte
 * d'autonomie alimentaire — fonctionnalité mise en avant par le prototype —
 * ne se déclencherait sur rien.
 *
 * ⚠️ RATIONS ISSUES DE `feed_ration_standards`, poids issus de
 * `growth_standards` : les g/jour et les GMQ ne sont pas inventés ici, ils
 * viennent du référentiel que les écrans d'analyse utilisent pour juger si un
 * lot est dans la norme. Inventer des chiffres aurait produit des lots
 * systématiquement hors norme, ou systématiquement parfaits.
 */
class DemoElevageSeeder extends Seeder
{
    public function __construct(private DemoContexte $ctx) {}

    /** @var array<int, array<string, mixed>> */
    private array $lots = [];

    public function run(): void
    {
        $this->creerLots();

        $entrees = 0;
        foreach ($this->lots as $config) {
            $entrees += $this->simulerLot($config);
        }

        $this->creerTransformations();
        $this->creerReproducteurs();
        $this->creerEvenementsReproduction();
        $this->creerCalendrierVeterinaire();

        $this->command?->info('  Élevage : '.LivestockLot::count().' bandes, '.$entrees.' fiches journalières, '
            .LivestockReproductionEvent::count().' événements de reproduction, '.Animal::count().' reproducteurs.');
    }

    // ------------------------------------------------------------- les bandes

    private function creerLots(): void
    {
        $definitions = [
            // code, espèce, stade, effectif, démarrage, aliment, produit vendu, GMQ cible
            // ⚠️ BANDES ÉCHELONNÉES À DESSEIN : chaque filière doit montrer À LA
            // FOIS un cycle terminé (bande écoulée puis clôturée, avec son
            // chiffre d'affaires) et une bande encore en cours au dernier jour.
            // Sans cela, l'écran des bandes serait soit vide, soit sans
            // historique — et la démonstration ne montrerait qu'une moitié du
            // métier.
            ['AVI-2026-01', 'aviculture', 'ponte', 200, 0, 'ALI-001', 'AVI-002', 'Pondeuses Isa Brown'],
            ['AVI-2026-02', 'aviculture', 'engraissement', 250, 6, 'ALI-002', 'AVI-001', 'Poulets goliath 1re bande'],
            ['AVI-2026-03', 'aviculture', 'engraissement', 250, 75, 'ALI-002', 'AVI-001', 'Poulets goliath 2e bande'],
            ['CUN-2026-01', 'cuniculture', 'reproduction', 60, 0, 'ALI-004', 'CUN-001', 'Lapins reproducteurs'],
            ['CUN-2026-02', 'cuniculture', 'engraissement', 90, 20, 'ALI-004', 'CUN-001', 'Lapins engraissement 1re bande'],
            ['CUN-2026-03', 'cuniculture', 'engraissement', 80, 62, 'ALI-004', 'CUN-001', 'Lapins engraissement 2e bande'],
            ['POR-2026-01', 'porciculture', 'engraissement', 24, 0, 'ALI-005', 'POR-001', 'Porcs charcutiers 1re bande'],
            ['POR-2026-02', 'porciculture', 'engraissement', 18, 105, 'ALI-005', 'POR-001', 'Porcs charcutiers 2e bande'],
        ];

        foreach ($definitions as [$code, $espece, $stade, $effectif, $decalage, $aliment, $produit, $libelle]) {
            $debut = $this->ctx->debut->addDays($decalage);

            if ($debut->gt($this->ctx->fin)) {
                continue;
            }

            $lot = LivestockLot::create([
                'code' => $code,
                'species_id' => $this->ctx->espece($espece)->id,
                'stage' => $stade,
                'initial_quantity' => $effectif,
                'current_quantity' => $effectif,
                // Ticket 14.37 : la bande sait ce qu'elle produit.
                'product_id' => $this->ctx->produit($produit)->id,
                'created_date' => $debut->format('Y-m-d'),
                'acquisition_cost' => $effectif * $this->coutUnitaire($espece),
                'status' => 'actif',
                'cost_center_id' => $this->ctx->centreDeCout(ucfirst($espece))?->id,
                'is_active' => true,
                'created_at' => $debut, 'updated_at' => $debut,
            ]);

            $this->lots[] = compact('lot', 'espece', 'stade', 'effectif', 'debut', 'aliment', 'produit', 'libelle');
        }
    }

    private function coutUnitaire(string $espece): int
    {
        return match ($espece) {
            'aviculture' => 520,
            'cuniculture' => 3_500,
            'porciculture' => 45_000,
            default => 1_000,
        };
    }

    // ------------------------------------------------- la simulation d'un lot

    /**
     * ⚠️ CHAQUE STADE A SA PROPRE DYNAMIQUE — c'est ce qui sépare une
     * simulation d'un tirage aléatoire. Une première version appliquait la
     * même loi de vente à tous les lots : les cheptels s'effondraient
     * (200 pondeuses tombées à 10, 90 lapins à 0 en cinq mois), une
     * exploitation qui n'existe pas.
     *
     *   - PONTE : on ne vend pas ses pondeuses, on vend leurs ŒUFS. Mortalité
     *     faible, quelques réformes ponctuelles ; l'effectif se maintient.
     *   - ENGRAISSEMENT : rien pendant la croissance, puis écoulement de la
     *     bande à partir de l'âge de vente. Une bande vidée est CLÔTURÉE —
     *     c'est le cycle réel d'un poulet de chair, pas un effectif qui fond.
     *   - REPRODUCTION : les naissances font croître le lot, les sevrés
     *     partent progressivement. L'effectif oscille autour de sa capacité.
     *
     * @param  array<string, mixed>  $config
     */
    private function simulerLot(array $config): int
    {
        $lot = $config['lot'];
        $stade = $config['stade'];
        $espece = $config['espece'];
        $effectif = (int) $config['effectif'];
        $capacite = $effectif;
        $aliment = $this->ctx->produit($config['aliment']);
        $rationG = $this->rationJournaliere($espece, $stade);
        $gmq = $this->gmqCible($espece, $stade);
        $poids = $this->poidsInitial($espece);

        // Âge de mise en vente, par espèce — cycles réels d'élevage.
        $ageVente = match ($espece) {
            'aviculture' => 55,      // poulet de chair
            'cuniculture' => 90,     // lapin d'engraissement
            'porciculture' => 150,   // porc charcutier
            default => 90,
        };

        $entrees = 0;
        $ponte = $stade === 'ponte';
        $jourCycle = 0;

        foreach ($this->ctx->jours($config['debut']) as $jour) {
            if ($effectif <= 0) {
                break;
            }

            $jourCycle++;

            // --- Mortalité quotidienne -------------------------------------
            //
            // ⚠️ ARRONDI PROBABILISTE, JAMAIS `max(1, …)`. Une première version
            // écrivait `max(1, round($effectif * $taux))` : sur un petit
            // effectif l'espérance arrondissait à 0, le `max(1, …)` la
            // remontait à 1, et CHAQUE tirage tuait donc une bête. Résultat
            // constaté : 39 % de mortalité chez les pondeuses et **la totalité
            // du troupeau porcin décimée** (23 morts sur 24). Le plancher
            // transformait une espérance de 0,02 mort/jour en 0,4 — vingt fois
            // trop, et d'autant plus faux que le lot est petit.
            //
            // Ici la partie entière de l'espérance est certaine, la partie
            // fractionnaire est tirée : l'espérance journalière est respectée
            // quel que soit l'effectif.
            // Taux propres à l'ESPÈCE autant qu'au stade : un porc charcutier
            // ne meurt pas au rythme d'un poulet de chair (≈ 2-3 % sur un
            // cycle contre 5-6 %), et le lapin est l'espèce la plus fragile
            // des trois. Un taux unique donnait 28 % de mortalité porcine.
            $tauxMort = match (true) {
                $stade === 'ponte' => 0.0003,
                $espece === 'porciculture' => 0.00018,
                $stade === 'reproduction' => 0.0005,
                $espece === 'cuniculture' => 0.0008,
                default => $jourCycle <= 21 ? 0.0015 : 0.0007,
            };

            $esperance = $effectif * $tauxMort;
            $morts = (int) floor($esperance);

            if ($this->ctx->chance((int) round(($esperance - $morts) * 100))) {
                $morts++;
            }

            // Épisode sanitaire : rare, PROPORTIONNEL au lot, et arrondi lui
            // aussi de façon probabiliste. Un plancher de 1 sujet restait
            // anodin sur 250 volailles mais pesait 4 % du troupeau à chaque
            // épisode sur 24 porcs — d'où 28 % de mortalité porcine cumulée.
            if ($this->ctx->chance(2)) {
                $ampleur = $effectif * 0.012;
                $morts += (int) floor($ampleur);

                if ($this->ctx->chance((int) round(($ampleur - floor($ampleur)) * 100))) {
                    $morts++;
                }
            }

            $morts = min($morts, max(0, $effectif - 1));

            // --- Naissances : reproduction uniquement ----------------------
            $nes = 0;
            if ($stade === 'reproduction' && $this->ctx->chance(14)) {
                $nes = $this->ctx->entre(4, 9);
            }

            // --- Ventes : selon le stade, jamais une loi unique ------------
            $vendus = 0;

            if ($stade === 'engraissement' && $jourCycle >= $ageVente) {
                // Écoulement de la bande : par lots, jusqu'à épuisement.
                if ($this->ctx->chance(45)) {
                    $vendus = min($this->ctx->entre(8, 25), $effectif - $morts);
                }
            } elseif ($stade === 'ponte') {
                // Réforme occasionnelle d'une pondeuse en fin de carrière.
                if ($this->ctx->chance(4)) {
                    $vendus = min($this->ctx->entre(1, 3), $effectif - $morts);
                }
            } elseif ($stade === 'reproduction') {
                // Les sevrés partent quand le lot dépasse sa capacité.
                if ($effectif > $capacite && $this->ctx->chance(30)) {
                    $vendus = min($this->ctx->entre(2, 6), $effectif - $capacite);
                }
            }

            // Don : un poulet ou un lapin offert (visite, fête, école) est
            // courant ; un porc à 95 000 FCFA ne se donne pas. Restreint aux
            // petites espèces — sans quoi la simulation offrait 4 porcs en
            // deux mois, soit 380 000 FCFA évaporés sans motif.
            $dons = ($espece !== 'porciculture' && $this->ctx->chance(1) && $effectif - $morts - $vendus > 5) ? 1 : 0;

            // ⚠️ LA FORMULE, appliquée telle quelle — l'effectif du jour
            // dérive du précédent, il n'est jamais tiré au sort.
            $effectifFinal = max(0, $effectif + 0 + $nes - ($morts + $vendus + $dons));

            // --- Provende : ration normative × effectif --------------------
            //
            // ⚠️ CONVERTIE EN SACS DE 25 KG, l'unité du produit au catalogue
            // (ticket 14.36). La ration reste exprimée en g/jour/sujet — c'est
            // le référentiel `feed_ration_standards` — mais le stock, lui, se
            // décrémente dans son unité réelle. Sortir des kilos d'un produit
            // compté en sacs aurait vidé le stock 25 fois trop vite.
            $feedKg = round(($rationG * $effectifFinal) / 1000, 2);
            $feedSacs = round($feedKg / 25, 3);

            // --- Poids moyen : progression au GMQ du référentiel -----------
            $poids += $gmq;

            $entree = LivestockDailyEntry::create([
                'lot_id' => $lot->id,
                'entry_date' => $jour->format('Y-m-d'),
                'achat' => 0,
                'ne' => $nes,
                'mort' => $morts,
                'vente' => $vendus,
                'don' => $dons,
                'effectif_final' => $effectifFinal,
                'cat_eff_repro' => $stade === 'reproduction' ? $effectifFinal : null,
                'cat_eff_jeune' => $stade === 'engraissement' ? $effectifFinal : null,
                'feed_qty_kg' => $feedKg,
                'feed_product_id' => $aliment->id,
                'weight_sample_avg_g' => $this->ctx->chance(20) ? (int) round($poids) : null,
                // Taux de ponte réaliste : 75 à 85 % en pleine production.
                'ponte_total' => $ponte ? max(0, (int) round($effectifFinal * 0.80) + $this->ctx->entre(-10, 6)) : null,
                'ponte_casses' => $ponte ? $this->ctx->entre(0, 4) : null,
                'vente_montant' => $vendus > 0 ? $vendus * $this->prixSujet($espece) : null,
                'created_at' => $jour, 'updated_at' => $jour,
            ]);

            // 🔴→✅ TICKET 14.37 — LA PRODUCTION PASSE PAR L'ACTION RÉELLE.
            //
            // Ce seeder convertissait lui-même les sorties de cheptel en
            // entrées de stock, faute de flux applicatif. L'Action
            // `SyncLotProductionStockAction` existe désormais : naissances au
            // crédit, mortalité et dons au débit, sur le produit rattaché à la
            // bande. Le seeder appelle le code réel plutôt que de le simuler.
            app(\App\Actions\SyncLotProductionStockAction::class)->execute($entree);

            // ⚠️ MISE EN VENTE des sujets écoulés : la vente d'une bande
            // d'engraissement sort du cheptel et entre en marchandise. Les
            // ventes sont exclues de l'Action ci-dessus (le POS les compte
            // déjà) ; ici, aucune vente POS n'a eu lieu, c'est le seeder qui
            // fait entrer la bande écoulée en stock.
            if ($vendus > 0 && isset($config['produit'])) {
                app(AdjustStockAction::class)->execute(
                    $this->ctx->produit($config['produit']), (float) $vendus,
                    'elevage', $lot->id, $jour->toDateTime(), 'Mise en vente '.$lot->code
                );
            }

            // ⚠️ LA PONTE DU JOUR ENTRE EN STOCK COMMERCIAL.
            //
            // Même gap que pour les sujets vifs, et plus visible encore : les
            // fiches enregistrent la ponte quotidienne, mais AUCUN flux ne fait
            // entrer ces œufs dans `products.stock_qty`. Sans cette conversion,
            // la ferme produisait 20 000 œufs sur la période sans jamais
            // pouvoir en vendre un seul au-delà de son stock d'ouverture — et
            // les ventes s'arrêtaient net deux mois avant la fin, faute de
            // marchandise. Un plateau = 30 œufs, les cassés déduits.
            if ($ponte && $entree->ponte_total > 0) {
                $plateaux = (int) floor(((int) $entree->ponte_total - (int) $entree->ponte_casses) / 30);

                if ($plateaux > 0) {
                    app(AdjustStockAction::class)->execute(
                        $this->ctx->produit('AVI-002'), (float) $plateaux,
                        'elevage', $lot->id, $jour->toDateTime(), 'Ponte '.$lot->code
                    );
                }
            }

            // ⚠️ SORTIE DE STOCK RÉELLE : c'est ce qui relie les achats de
            // provende aux fiches, et fait vivre l'alerte d'autonomie.
            if ($feedSacs > 0) {
                app(AdjustStockAction::class)->execute(
                    $aliment, -$feedSacs, 'elevage', $lot->id, $jour->toDateTime(),
                    'Rationnement '.$lot->code.' — '.$feedKg.' kg'
                );
            }

            $this->traitementsEventuels($lot, $jour, $entree->id, $morts, $effectifFinal);

            $effectif = $effectifFinal;
            $entrees++;
        }

        // Une bande entièrement écoulée est clôturée — c'est la fin normale
        // d'un cycle d'engraissement, pas une anomalie à laisser « active ».
        $lot->update([
            'current_quantity' => max(0, $effectif),
            'status' => $effectif > 0 ? 'actif' : 'cloture',
        ]);

        return $entrees;
    }

    /**
     * Traitement vétérinaire déclenché par une mortalité anormale — et le
     * délai de rémanence qui en découle.
     *
     * ⚠️ C'est ce délai qui rend démontrable le BLOCAGE DE VENTE d'un sujet
     * sous traitement (ticket 14.21) : sans période de rémanence active en
     * base, la protection sanitaire la plus visible du logiciel ne se voit
     * nulle part.
     */
    private function traitementsEventuels(LivestockLot $lot, CarbonImmutable $jour, string $entreeId, int $morts, int $effectif): void
    {
        if ($morts < 3 || ! $this->ctx->chance(60)) {
            return;
        }

        $produit = $this->ctx->parmi(['Oxytétracycline 20%', 'Amproliuim soluble', 'Vitamine AD3E', 'Ivermectine']);

        VeterinaryRecord::create([
            'lot_id' => $lot->id,
            'action_type' => 'traitement',
            'product_used' => $produit,
            'dose' => $this->ctx->entre(1, 3).' g/L pendant '.$this->ctx->entre(3, 5).' jours',
            'vet_name' => 'Dr AGBODJAN Firmin',
            'symptomes' => $this->ctx->parmi(['Diarrhée et prostration', 'Toux et jetage', 'Baisse de consommation', 'Plumes ébouriffées']),
            'gravite' => $this->ctx->parmi(['legere', 'moderee']),
            'cost' => $this->ctx->entre(3, 12) * 1_000,
            'record_date' => $jour->format('Y-m-d'),
            'daily_entry_id' => $entreeId,
            'is_active' => true,
            'created_at' => $jour, 'updated_at' => $jour,
        ]);

        $delai = $this->ctx->entre(7, 21);

        VeterinaryWithdrawalPeriod::create([
            'lot_id' => $lot->id,
            'product_used' => $produit,
            'start_date' => $jour->format('Y-m-d'),
            'withdrawal_days' => $delai,
            'end_date' => $jour->addDays($delai)->format('Y-m-d'),
            'triggered_by_daily_entry_id' => $entreeId,
            'created_at' => $jour, 'updated_at' => $jour,
        ]);
    }

    // ------------------------------------------------------- le référentiel

    private function rationJournaliere(string $espece, string $stade): int
    {
        $standard = \DB::table('feed_ration_standards')->where('species_code', $espece)->get();

        $recherche = match (true) {
            $stade === 'ponte' => 'Pondeuse',
            $stade === 'reproduction' => 'Reproducteur',
            default => null,
        };

        if ($recherche) {
            foreach ($standard as $s) {
                if (str_contains($s->stage_label, $recherche)) {
                    return (int) $s->ration_g_per_day;
                }
            }
        }

        // À défaut, la ration médiane de l'espèce plutôt qu'un chiffre inventé.
        $rations = $standard->pluck('ration_g_per_day')->sort()->values();

        return $rations->isEmpty() ? 60 : (int) $rations[(int) floor($rations->count() / 2)];
    }

    private function gmqCible(string $espece, string $stade): int
    {
        $standard = \DB::table('growth_standards')
            ->where('species_code', $espece)
            ->where('stage_label', $stade)
            ->first()
            ?? \DB::table('growth_standards')->where('species_code', $espece)->first();

        if (! $standard) {
            return 20;
        }

        // Milieu de fourchette : un lot de démonstration doit être dans la
        // norme, pas à sa borne.
        return (int) round(((int) $standard->gmq_min_g_per_day + (int) $standard->gmq_max_g_per_day) / 2);
    }

    private function poidsInitial(string $espece): int
    {
        return match ($espece) {
            'aviculture' => 45,
            'cuniculture' => 600,
            'porciculture' => 8_000,
            default => 100,
        };
    }

    private function prixSujet(string $espece): int
    {
        return match ($espece) {
            'aviculture' => 5_500,
            'cuniculture' => 8_000,
            'porciculture' => 95_000,
            default => 3_000,
        };
    }

    /**
     * TRANSFORMATION : des sujets vifs deviennent du poulet fumé ou braisé.
     *
     * ⚠️ SANS CE FLUX, LA DÉCLARATION TVA RESTE VIDE. Les seuls produits
     * taxables à 18 % sont les TRANSFORMÉS (le vif et l'œuf sont exonérés) ;
     * leur stock d'ouverture — 15 poulets fumés, 12 braisés — s'épuisait en
     * quelques semaines et plus aucune vente taxable n'avait lieu ensuite. La
     * TVA collectée du mois affichait donc 0 sur 0 pièce, sur une exigence
     * pourtant impérative du module M14 (CGI Bénin art. 162 bis).
     *
     * Le rendement retenu est 1 sujet vif → 1 produit transformé : la
     * transformation ne multiplie pas les unités, elle change leur nature.
     */
    private function creerTransformations(): void
    {
        $operateur = \App\Models\User::where('email', 'elevage@olouwachegoun.bj')->value('id')
            ?? \App\Models\User::value('id');

        $lots = LivestockLot::whereHas('species', fn ($q) => $q->where('code', 'aviculture'))
            ->where('stage', 'engraissement')
            ->orderBy('code')
            ->get();

        if ($lots->isEmpty() || ! $operateur) {
            return;
        }

        $vif = $this->ctx->produit('AVI-001');

        // ⚠️ FUMIER COMPOSTÉ : le seul produit taxable dont la ferme dispose en
        // PERMANENCE. Les transformés (fumé, braisé) dépendent du vif
        // disponible et s'épuisaient dès que la demande dépassait la
        // production, laissant la Déclaration TVA à zéro sur le mois en cours.
        // Le fumier, lui, est produit chaque jour par le cheptel — sa
        // production hebdomadaire garantit une base taxable continue, ce qui
        // est aussi la réalité d'une exploitation de cette taille.
        $compost = $this->ctx->produit('TRA-001');

        for ($jour = $this->ctx->debut->addDays(7); $jour->lte($this->ctx->fin); $jour = $jour->addDays(7)) {
            app(AdjustStockAction::class)->execute(
                $compost, (float) $this->ctx->entre(12, 28),
                'elevage', null, $jour->toDateTime(), 'Compostage hebdomadaire du fumier'
            );
        }

        for ($jour = $this->ctx->debut->addDays(45); $jour->lte($this->ctx->fin); $jour = $jour->addDays($this->ctx->entre(3, 6))) {
            $lot = $lots->first();
            $produit = $this->ctx->produit($this->ctx->parmi(['AVI-005', 'AVI-006']))->refresh();
            $sujets = $this->ctx->entre(6, 14);

            // On ne transforme que ce qui est réellement en stock de vif.
            if ((float) $vif->refresh()->stock_qty < $sujets) {
                continue;
            }

            \App\Models\Transformation::create([
                'lot_id' => $lot->id,
                'product_id' => $produit->id,
                'qty_animals' => $sujets,
                'qty_produced' => $sujets,
                'operator_id' => $operateur,
                'transformation_date' => $jour->format('Y-m-d'),
                'created_at' => $jour, 'updated_at' => $jour,
            ]);

            // Le vif sort du stock, le transformé y entre : deux mouvements
            // réels, jamais une simple écriture de quantité.
            app(AdjustStockAction::class)->execute(
                $vif, -$sujets, 'transformation', $lot->id, $jour->toDateTime(), 'Transformation en '.$produit->name
            );
            app(AdjustStockAction::class)->execute(
                $produit, $sujets, 'transformation', $lot->id, $jour->toDateTime(), 'Issu de '.$lot->code
            );
        }
    }

    // ------------------------------------------------- reproducteurs et suivi

    /** Registre des reproducteurs — sujets identifiés individuellement. */
    private function creerReproducteurs(): void
    {
        $lotCuni = LivestockLot::where('code', 'CUN-2026-01')->first();
        $lotAvi = LivestockLot::where('code', 'AVI-2026-01')->first();

        if ($lotCuni) {
            foreach (range(1, 12) as $i) {
                $sexe = $i <= 9 ? 'F' : 'M';

                Animal::create([
                    'identifier' => sprintf('LAP-R%03d', $i),
                    'species_id' => $lotCuni->species_id,
                    'lot_id' => $lotCuni->id,
                    'category' => 'reproducteur',
                    'sex' => $sexe,
                    'breed' => $this->ctx->parmi(['Néo-Zélandais', 'Californien', 'Fauve de Bourgogne']),
                    'birth_date' => $this->ctx->debut->subMonths($this->ctx->entre(6, 14))->format('Y-m-d'),
                    'entry_date' => $lotCuni->created_date->format('Y-m-d'),
                    'origin' => $this->ctx->parmi(['Élevage interne', 'Achat - Ferme de Pobè']),
                    'cage' => 'C'.$this->ctx->entre(1, 8).'-'.$this->ctx->entre(1, 4),
                    'status' => 'actif',
                    'is_active' => true,
                ]);
            }
        }

        if ($lotAvi) {
            foreach (range(1, 6) as $i) {
                Animal::create([
                    'identifier' => sprintf('COQ-%03d', $i),
                    'species_id' => $lotAvi->species_id,
                    'lot_id' => $lotAvi->id,
                    'category' => 'reproducteur',
                    'sex' => 'M',
                    'breed' => 'Goliath',
                    'birth_date' => $this->ctx->debut->subMonths($this->ctx->entre(8, 16))->format('Y-m-d'),
                    'entry_date' => $lotAvi->created_date->format('Y-m-d'),
                    'origin' => 'Couvoir Avicole de Kétou',
                    'cage' => 'Poulailler '.$this->ctx->parmi(['A', 'B']),
                    'status' => 'actif',
                    'is_active' => true,
                ]);
            }
        }
    }

    /**
     * Cycles de reproduction cunicole : saillie → palpation → mise bas →
     * sevrage, avec les délais réels de l'espèce (gestation 31 jours,
     * sevrage à 35 jours) plutôt que des dates arbitraires.
     */
    private function creerEvenementsReproduction(): void
    {
        $lot = LivestockLot::where('code', 'CUN-2026-01')->first();

        if (! $lot) {
            return;
        }

        $meres = Animal::where('lot_id', $lot->id)->where('sex', 'F')->orderBy('identifier')->pluck('identifier')->all();
        $males = Animal::where('lot_id', $lot->id)->where('sex', 'M')->orderBy('identifier')->pluck('identifier')->all();

        if (empty($meres) || empty($males)) {
            return;
        }

        for ($date = $this->ctx->debut->addDays(4); $date->lte($this->ctx->fin); $date = $date->addDays(9)) {
            $mere = $this->ctx->parmi($meres);
            $miseBas = $date->addDays(31);          // gestation réelle du lapin
            $sevrage = $miseBas->addDays(35);
            $passee = $miseBas->lte($this->ctx->fin);

            LivestockReproductionEvent::create([
                'lot_id' => $lot->id,
                'mother_ref' => $mere,
                'sire_ref' => $this->ctx->parmi($males),
                'saillie_date' => $date->format('Y-m-d'),
                'palpation_date' => $date->addDays(12)->format('Y-m-d'),
                'mise_bas_date_expected' => $miseBas->format('Y-m-d'),
                'mise_bas_date_actual' => $passee ? $miseBas->addDays($this->ctx->entre(-1, 2))->format('Y-m-d') : null,
                'sevrage_date_expected' => $sevrage->format('Y-m-d'),
                'nes_vivants' => $passee ? $this->ctx->entre(4, 9) : null,
                'nes_morts' => $passee ? $this->ctx->entre(0, 2) : null,
                'status' => $passee ? 'termine' : 'en_cours',
                'created_at' => $date, 'updated_at' => $date,
            ]);
        }
    }

    /** Calendrier prophylactique à venir — l'écran VMS ne doit pas être vide. */
    private function creerCalendrierVeterinaire(): void
    {
        foreach (LivestockLot::where('status', 'actif')->orderBy('code')->get() as $lot) {
            foreach ([7, 21, 45] as $decalage) {
                VeterinaryCalendarEvent::create([
                    'lot_id' => $lot->id,
                    'task_type' => $this->ctx->parmi(['vaccination', 'deparasitage', 'vitamines', 'desinfection']),
                    'scheduled_date' => $this->ctx->fin->addDays($decalage)->format('Y-m-d'),
                    'status' => 'planned',
                ]);
            }
        }
    }
}
