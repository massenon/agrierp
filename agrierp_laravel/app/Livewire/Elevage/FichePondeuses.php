<?php

namespace App\Livewire\Elevage;

use App\Livewire\Elevage\Concerns\AvecTransfertsDuJour;
use App\Actions\RecordEggProductionStockAction;
use App\Actions\SyncLotProductionStockAction;
use App\Actions\RecordSaleOnFicheElevageAction;
use App\Livewire\Elevage\Concerns\AvecProphylaxieDuJour;
use App\Livewire\Elevage\Concerns\AvecSoinsDuMois;
use App\Models\AuditLog;
use App\Models\LivestockDailyEntry;
use App\Models\FeedRationStandard;
use App\Actions\RaiseFeedAutonomyAlertAction;
use App\Services\AutonomieAlimentaireService;
use App\Services\EffectifParCategorieService;
use App\Support\StadePondeuse;
use Carbon\Carbon;
use App\Models\LivestockLot;
use App\Models\Product;
use App\Models\StockMovement;
use App\Services\EggStockLedgerService;
use App\Support\OrdreDesVerrous;
use Illuminate\Support\Facades\DB;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Ticket 3.6 (Sprint 3) — fiche-volailles-pondeuses.html → Livewire\Elevage\FichePondeuses
 * Variante B (RESPECT_TABLEAU_MENSUEL_DES_31_JOURS...md) : structure
 * Cheptel/Ponte/Stock — PAS de colonne Poids Général (divergence actée,
 * jamais à uniformiser avec la Variante A).
 *
 * ⚠️ MÉCANISME RÉEL D'INCRÉMENTATION DE STOCK : le prototype indique
 * explicitement "Incrémentation Automatique du Stock : +N Plateaux au
 * Stock Produits" — confirmant que le stock d'œufs est porté par
 * `products.stock_qty` (le produit "Œufs de table (plateau)", SKU
 * AVI-002, déjà seedé au ticket 2.3), pas par une table dédiée. Chaque
 * jour enregistré incrémente réellement ce produit du nombre de plateaux
 * nets générés (Commercialisables ÷ 30) — un seul point de vérité pour le
 * stock, partagé avec le Catalogue (ticket 2.3) et le futur POS
 * (Sprint 4).
 *
 * ⚠️ LIMITE DOCUMENTÉE — RECONSTRUCTION HISTORIQUE DU STOCK : `products`
 * ne porte qu'un solde courant (`stock_qty`), pas un grand livre de
 * mouvements (`stock_movements` arrive au Sprint 6). Le formulaire du
 * jour calcule donc SRH/TS/Stock Final en direct à partir du solde
 * courant réel du produit (exact, à l'instant présent), mais le tableau
 * mensuel ne peut pas reconstruire fidèlement le stock historique
 * jour par jour pour les jours passés — ces colonnes y affichent "—"
 * pour les jours autres que le jour actif, plutôt qu'un chiffre reconstitué
 * qui pourrait être trompeur. OR/OF/Commercialisables/Taux Ponte restent
 * en revanche 100% historiques et réels (stockés par jour).
 *
 * 🔁 TICKET VOL-2 (décision client du 05/11/2026) — EFFECTIF PAR STADE CALCULÉ, comme les volailles reproductrices (VOL-1), les
 * lapins et les porcs. QUATRE stades, aux libellés EXACTS du barème de l'aviculture : Poussin ponte, Poussin en croissance,
 * Poulette, Pondeuse. PP, PC, PL, PO ; v = veille ; p1, p2, p3 = passages PP → PC, PC → PL, PL → PO :
 *   PP = max(0, PPv + éclosions − vente_PP − mort_PP − don_PP − p1)
 *   PC = max(0, PCv − vente_PC − mort_PC − don_PC + p1 − p2)
 *   PL = max(0, PLv + achat − vente_PL − mort_PL − don_PL + p2 − p3)     (les ACHATS vont à Poulette)
 *   PO = max(0, POv − vente_PO − mort_PO − don_PO + p3)
 * Calcul : `EffectifParCategorieService::calculerJour(VOLAILLES_PONTE, …)` — aucune formule recopiée ici. Emplacements
 * génériques : `repro` = Pondeuse, `jeune` = Poulette, `sevre` = Poussin en croissance, `quatre` (colonnes `*_4`) = Poussin ponte.
 * ⚠️ AUCUN stade « inconnu » : le DÉPART de la bande (effectif de chaque stade au début du jour de départ, somme = effectif
 * total) est exigé avant toute journée ; sans lui la fiche affiche la demande de départ et refuse d'enregistrer. Les ventes
 * (`vente_*`) viennent de la caisse, rangées dans le stade du PRODUIT vendu. Les ŒUFS (récolte, casse, stock) sont inchangés.
 */
#[Layout('layouts.app')]
class FichePondeuses extends Component
{
    use \App\Livewire\Elevage\Concerns\AvecMoisDeFiche;   // Ticket EX8 (EF12) : mois passés, lecture seule
    use AvecTransfertsDuJour;
    use AvecProphylaxieDuJour;
    use AvecSoinsDuMois;

    public string $selectedDate;

    public int $achat = 0;

    public int $ne = 0;

    // Ticket VOL-2 — morts et dons PAR STADE (libellés du barème). Emplacements : Pondeuse = `repro`, Poulette = `jeune`,
    // Poussin en croissance = `sevre`, Poussin ponte = `quatre` (`*_4`).
    public int $mortPondeuse = 0;

    public int $mortPoulette = 0;

    public int $mortPoussinCroissance = 0;

    public int $mortPoussinPonte = 0;

    public int $donPondeuse = 0;

    public int $donPoulette = 0;

    public int $donPoussinCroissance = 0;

    public int $donPoussinPonte = 0;

    /** Ticket VOL-2 — passages de stade du jour (des FAITS saisis, jamais des effectifs) : 1 = Poussin ponte → Poussin en croissance. */
    public int $passage1 = 0;

    /** 2 = Poussin en croissance → Poulette. */
    public int $passage2 = 0;

    /** 3 = Poulette → Pondeuse. */
    public int $passage3 = 0;

    /** Ticket VOL-2 — EFFECTIF DE DÉPART par stade (début du jour de départ), saisi UNE fois par bande puis verrouillé. */
    public ?int $departPondeuse = null;

    public ?int $departPoulette = null;

    public ?int $departPoussinCroissance = null;

    public ?int $departPoussinPonte = null;

    /**
     * Ticket 15.56 — dons déjà enregistrés pour le jour rechargé (même règle que `mortEnregistre`) : la répartition
     * n'est pas stockée, seul le total l'est ; il est gardé tant qu'aucune répartition n'est ressaisie.
     */
    public ?int $donEnregistre = null;

    /** Ticket 15.57 — poids TOTAL pesé (g) ; la base stocke la moyenne par sujet, comme les autres fiches. */
    public ?int $peseeTotal = null;

    public int $oeufsRecoltes = 0;

    public int $oeufsCasses = 0;

    public string $observations = '';

    /**
     * Ticket 15.47 (A11) — LA bande de la fiche, comme Lapins et Porcs (15.41). `null` = la première bande par
     * code. Avant : `saveDay()` écrivait toujours sur la PREMIÈRE bande (ordre des UUID, imprévisible) et le
     * tableau mensuel mêlait toutes les bandes, deux fiches du même jour s'y écrasant.
     */
    public ?string $bandeId = null;

    /**
     * Ticket 15.47 — morts déjà enregistrés pour le jour rechargé. Une fiche d'AVANT VOL-2 n'a pas de
     * répartition par stade (seul le total `mort` l'est) : sans ce total, ré-enregistrer le jour remettait
     * ses morts à zéro. Il est gardé tant qu'aucune répartition n'est ressaisie.
     */
    public ?int $mortEnregistre = null;

    public function mount(): void
    {
        $this->selectedDate = now()->format('Y-m-d');
        $this->loadDay($this->selectedDate);
    }

    public function updatedSelectedDate(): void
    {
        $this->loadDay($this->selectedDate);
    }

    public function updatedBandeId(): void
    {
        $this->loadDay($this->selectedDate);
    }

    public function getBandeProperty(): ?LivestockLot
    {
        $lots = $this->lots;

        return ($this->bandeId !== null ? $lots->firstWhere('id', $this->bandeId) : null) ?? $lots->first();
    }

    protected function bandeDeLaFiche()
    {
        return $this->bande;
    }

    /** Morts du jour : la répartition saisie, sinon le total déjà enregistré. */
    private function mortDuJour(): int
    {
        $saisis = $this->mortPondeuse + $this->mortPoulette + $this->mortPoussinCroissance + $this->mortPoussinPonte;

        return $saisis > 0 ? $saisis : (int) ($this->mortEnregistre ?? 0);
    }

    /**
     * Ticket 15.56 — dons du jour : la répartition saisie, sinon le total déjà enregistré. Un don fait QUITTER le
     * sujet de l'exploitation : il réduit l'effectif et sort du stock du produit de la bande
     * (`SyncLotProductionStockAction`, ticket 14.37).
     */
    private function donDuJour(): int
    {
        $saisis = $this->donPondeuse + $this->donPoulette + $this->donPoussinCroissance + $this->donPoussinPonte;

        return $saisis > 0 ? $saisis : (int) ($this->donEnregistre ?? 0);
    }

    private function speciesCode(): string
    {
        return 'aviculture';
    }

    public function getLotsProperty()
    {
        return LivestockLot::whereHas('species', fn ($q) => $q->where('code', $this->speciesCode()))
            ->where('stage', 'ponte')
            ->where('status', 'actif')
            ->where('is_active', true)
            ->orderBy('code')
            ->get();
    }

    public function getEggProductProperty(): ?Product
    {
        return app(EggStockLedgerService::class)->eggProduct();
    }

    public function getKpisProperty(): array
    {
        $lotIds = $this->lots->pluck('id');
        $monthEntries = LivestockDailyEntry::whereIn('lot_id', $lotIds)
            ->whereBetween('entry_date', [$this->debutMoisFiche(), $this->finMoisFiche()])   // EX8 : le mois affiché
            ->get();

        $totalMorts = $monthEntries->sum('mort');
        $totalEffectifDepart = $monthEntries->sum(fn ($e) => $e->previousEffectif());
        $effectifTotal = (int) $this->lots->sum('current_quantity');
        $totalOr = $monthEntries->sum('ponte_total');
        $joursAvecEffectif = $monthEntries->count();
        $tauxPonteMoyen = $effectifTotal > 0 && $joursAvecEffectif > 0
            ? round(($totalOr / $joursAvecEffectif) / $effectifTotal * 100, 1)
            : 0.0;

        return [
            'effectif' => $effectifTotal,
            'taux_ponte_moyen' => $tauxPonteMoyen,
            'stock_plateaux' => $this->eggProduct ? (int) floor($this->eggProduct->stock_qty) : null,
            'taux_mortalite_mois' => $totalEffectifDepart > 0 ? round(($totalMorts / $totalEffectifDepart) * 100, 1) : 0.0,
        ];
    }

    /** Bandes du tableau mensuel (AvecSoinsDuMois). */
    protected function lotsDuTableauMensuel(): array
    {
        return [$this->bande?->id];
    }

    /** Fiches du mois de LA bande de la fiche (ticket 15.47 : une bande par tableau, plus d'écrasement). */
    public function getMonthlyEntriesProperty()
    {
        $bande = $this->bande;

        if (! $bande) {
            return collect();
        }

        // Ticket audit fidélité : eager-load treatmentProduct — colonne
        // "Traitements & Rappels" du prototype, trouvée manquante du
        // tableau mensuel (même écart que fiche-lapins.html).
        return LivestockDailyEntry::where('lot_id', $bande->id)
            ->whereBetween('entry_date', [$this->debutMoisFiche(), $this->finMoisFiche()])   // EX8 : le mois affiché
            ->with('treatmentProduct')
            ->orderBy('entry_date')
            ->get()
            ->keyBy(fn ($e) => $e->entry_date->format('Y-m-d'));
    }

    /**
     * 🔴→✅ TROUVÉ MANQUANT PAR BALAYAGE STRUCTUREL SYSTÉMATIQUE : le
     * bouton "Exporter PDF" du prototype était absent — même schéma déjà
     * trouvé sur de nombreux écrans. Réutilise le gabarit PARTAGÉ
     * `exports.fiche-elevage` (colonnes universelles de
     * `livestock_daily_entries`) — un seul gabarit pour les 5 fiches,
     * jamais 5 gabarits quasi-identiques à maintenir séparément.
     */
    public function exportFichePdf()
    {
        $this->authorize('view-elevage');

        $entries = $this->monthlyEntries->values();

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.fiche-elevage',
            ['entries' => $entries],
            'Fiche Pondeuses — Suivi Mensuel',
            $this->moisDuPdf()   // EX8 : le mois affiché
        );

        return response()->streamDownload(fn () => print($pdf->output()), $this->fichierDuPdf());
    }


    /** Veille de LA bande : dernière fiche antérieure, sinon son effectif initial (point unique `previousEffectif`). */
    public function getPreviousEffectifProperty(): int
    {
        $bande = $this->bande;

        if (! $bande) {
            return 0;
        }

        $sonde = new LivestockDailyEntry(['lot_id' => $bande->id, 'entry_date' => $this->selectedDate]);
        $sonde->setRelation('lot', $bande);

        return $sonde->previousEffectif();
    }

    /**
     * Ticket 14.4 — LIEN VENTE -> FICHE ELEVAGE, cote fiche.
     *
     * Le champ "Ventes" de la fiche journaliere etait etiquete comme
     * alimente par le POS mais valait `0` EN DUR — dans le calcul
     * d'effectif final affiche a l'ecran comme dans `saveDay()`, qui le
     * reecrivait donc a zero a chaque enregistrement de la journee par
     * l'animalier. Toute vente enregistree au POS etait silencieusement
     * annulee des la sauvegarde suivante.
     *
     * Lit desormais la valeur reellement persistee par
     * `PosInterface::recordFicheVente()` — un seul point de verite, jamais
     * une seconde source de comptage cote fiche.
     */
    public function getVenteDuJourProperty(): int
    {
        $lot = $this->bande;

        if (! $lot) {
            return 0;
        }

        return (int) (LivestockDailyEntry::where('lot_id', $lot->id)
            ->where('entry_date', $this->selectedDate)
            ->value('vente') ?? 0);
    }

    public function getEffectifFinalCalcProperty(): int
    {
        $mort = $this->mortDuJour();

        return LivestockDailyEntry::computeEffectifFinal($this->previousEffectif, $this->achat, $this->ne, $mort, $this->venteDuJour, $this->donDuJour(), $this->transfertsDuJour['transfert_entree'], $this->transfertsDuJour['transfert_sortie']);
    }

    public function getMortalityRateCalcProperty(): float
    {
        $mort = $this->mortDuJour();

        return $this->previousEffectif > 0 ? round(($mort / $this->previousEffectif) * 100, 1) : 0.0;
    }

    public function getCommercialisablesProperty(): int
    {
        return max(0, $this->oeufsRecoltes - $this->oeufsCasses);
    }

    public function getTauxPonteCalcProperty(): float
    {
        return $this->previousEffectif > 0 ? round(($this->oeufsRecoltes / $this->previousEffectif) * 100, 1) : 0.0;
    }

    public function getPlateauxProperty(): array
    {
        return app(EggStockLedgerService::class)->enPlateaux($this->commercialisables);
    }

    /**
     * 🔴→✅ TICKET 14.13 — DEUX DÉFAUTS RÉELS CORRIGÉS.
     *
     * 1. **SRH lisait le stock de MAINTENANT** (`eggProduct->stock_qty`), pas
     *    le solde réel de la veille de la date consultée. Ouvrir la fiche
     *    d'un jour passé affichait donc le stock du jour présent — un « Stock
     *    Reporté Hier » qui ne reportait rien. Reconstruit depuis l'historique
     *    réel de `stock_movements`, même principe que `AdjustStockAction` :
     *    recalcul depuis la vérité, jamais un solde en cache.
     * 2. **OS (Sortie vente) était figée à 0**, avec le commentaire « Sprint 4
     *    (POS), pas encore de source réelle » — or le POS existe depuis le
     *    Sprint 4 et décrémente réellement le stock d'œufs. Les ventes du jour
     *    étaient donc silencieusement ignorées et le Stock Final surestimait
     *    systématiquement le stock réel.
     *
     * Le mouvement de production du jour est daté de `selectedDate` : il est
     * exclu du SRH (borné strictement avant cette date) et compté une seule
     * fois via `plateaux` — pas de double comptage, que la journée ait déjà
     * été enregistrée ou non.
     */
    public function getStockTodayProperty(): array
    {
        // ⚠️ TICKET 14.46 — CE CALCUL A ÉTÉ EXTRAIT DANS
        // `EggStockLedgerService`. Le rapport Synthèse Élevage en avait besoin
        // à son tour et sa limite prétendait qu'aucun grand livre d'œufs
        // n'existait : il existait, enfermé ici. Recopier aurait laissé deux
        // soldes d'œufs diverger d'un écran à l'autre.
        return app(EggStockLedgerService::class)->ligne($this->selectedDate, $this->commercialisables);
    }

    public function loadDay(string $date): void
    {
        $this->traitementsCoches = [];   // une case cochée ne survit pas à un changement de jour
        $this->selectedDate = $date;
        // 🔴→✅ Ticket U11 — la fiche du jour CHOISI, même hors du mois en cours. `monthlyEntries` ne porte que le
        // mois courant : choisir le 28 du mois précédent vidait le formulaire alors que la fiche existait, et
        // « Enregistrer ce Jour » l'écrasait avec des zéros (achats, nés, œufs). Le poste charge la fiche de
        // n'importe quel jour (`FicheJournaliereRepository::chargerJour`) : même règle.
        $entry = $this->monthlyEntries->get($date)
            ?? ($this->bande
                ? LivestockDailyEntry::where('lot_id', $this->bande->id)->whereDate('entry_date', $date)->first()
                : null);

        $this->reset(['mortPondeuse', 'mortPoulette', 'mortPoussinCroissance', 'mortPoussinPonte', 'mortEnregistre',
            'donPondeuse', 'donPoulette', 'donPoussinCroissance', 'donPoussinPonte', 'donEnregistre',
            'passage1', 'passage2', 'passage3', 'departPondeuse', 'departPoulette', 'departPoussinCroissance', 'departPoussinPonte']);

        if ($entry) {
            $this->achat = $entry->achat;
            $this->ne = $entry->ne;
            // Ticket VOL-2 : la ventilation STOCKÉE recharge le jour. Une fiche d'AVANT le ticket (colonnes à null) garde son
            // total : il doit être ventilé avant d'enregistrer.
            if (! in_array(null, [$entry->mort_repro, $entry->mort_sevre, $entry->mort_jeune, $entry->mort_4], true)) {
                $this->mortPondeuse = (int) $entry->mort_repro;
                $this->mortPoussinCroissance = (int) $entry->mort_sevre;
                $this->mortPoulette = (int) $entry->mort_jeune;
                $this->mortPoussinPonte = (int) $entry->mort_4;
            } else {
                $this->mortEnregistre = (int) $entry->mort > 0 ? (int) $entry->mort : null;
            }
            if (! in_array(null, [$entry->don_repro, $entry->don_sevre, $entry->don_jeune, $entry->don_4], true)) {
                $this->donPondeuse = (int) $entry->don_repro;
                $this->donPoussinCroissance = (int) $entry->don_sevre;
                $this->donPoulette = (int) $entry->don_jeune;
                $this->donPoussinPonte = (int) $entry->don_4;
            } else {
                $this->donEnregistre = (int) ($entry->don ?? 0) > 0 ? (int) $entry->don : null;
            }
            $this->passage1 = (int) ($entry->passage_4_sevre ?? 0);
            $this->passage2 = (int) ($entry->passage_sevre_jeune ?? 0);
            $this->passage3 = (int) ($entry->passage_jeune_repro ?? 0);
            $this->oeufsRecoltes = $entry->ponte_total ?? 0;
            $this->oeufsCasses = $entry->ponte_casses ?? 0;
            $effectifFiche = (int) ($entry->effectif_final ?? 0);
            $this->peseeTotal = $entry->weight_sample_avg_g && $effectifFiche > 0
                ? (int) round($entry->weight_sample_avg_g * $effectifFiche)
                : null;
        } else {
            $this->reset(['achat', 'ne', 'oeufsRecoltes', 'oeufsCasses', 'peseeTotal']);
        }
    }

    /** Ticket VOL-2 — date au format AAAA-MM-JJ et réelle (un champ date vidé ne casse pas la fiche). */
    private function dateValide(?string $date): bool
    {
        if ($date === null || ! preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) {
            return false;
        }

        try {
            return Carbon::createFromFormat('Y-m-d', $date)->format('Y-m-d') === $date;
        } catch (\Throwable) {
            return false;
        }
    }

    /**
     * Livewire garde chaque propriété calculée en cache pour toute la requête : après une écriture, l'écran rendu dans la
     * MÊME requête afficherait l'état d'avant (départ encore saisissable, tableau mensuel sans le jour).
     */
    private function purgerCalculs(): void
    {
        unset($this->lots, $this->bande, $this->categoriesJour, $this->previousEffectif, $this->venteDuJour,
            $this->ventesDuJour, $this->effectifFinalCalc, $this->rationnement, $this->feedAutonomy, $this->monthlyEntries, $this->kpis);
    }

    /** Ticket VOL-2 — les ventes du jour, par stade (colonnes `vente_*` posées par la caisse), 0 sans fiche. */
    public function getVentesDuJourProperty(): array
    {
        $bande = $this->bande;
        $fiche = $bande && $this->dateValide($this->selectedDate)
            ? LivestockDailyEntry::where('lot_id', $bande->id)->whereDate('entry_date', $this->selectedDate)->first()
            : null;

        return [
            'repro' => (int) ($fiche?->vente_repro ?? 0),
            'sevre' => (int) ($fiche?->vente_sevre ?? 0),
            'jeune' => (int) ($fiche?->vente_jeune ?? 0),
            'quatre' => (int) ($fiche?->vente_4 ?? 0),
            // Vente d'AVANT le ticket : le total existe, sa répartition par stade non (voir saveDay).
            'non_ventilee' => $fiche !== null && (int) $fiche->vente > 0 && $fiche->vente_repro === null,
        ];
    }

    /** Départ saisi, par emplacement générique. */
    private function departSaisi(): array
    {
        return [
            'repro' => $this->departPondeuse, 'sevre' => $this->departPoussinCroissance,
            'jeune' => $this->departPoulette, 'quatre' => $this->departPoussinPonte,
        ];
    }

    /**
     * Ticket VOL-2 — EFFECTIFS PAR STADE : CALCULÉS, jamais saisis (voir le docblock de la classe). Retourne `mode`
     * (`depart_requis` | `avant_depart` | `refus` | `chaine`), les quatre effectifs (`null` UNIQUEMENT tant que le départ
     * n'est pas valide : la vue affiche alors la demande de départ, jamais « — »), le résultat du service, le motif de refus
     * du départ stocké ou saisi, le refus de passage et les avertissements.
     *
     * @return array<string, mixed>
     */
    public function getCategoriesJourProperty(): array
    {
        $sortie = [
            'mode' => 'depart_requis', 'repro' => null, 'sevre' => null, 'jeune' => null, 'quatre' => null, 'resultat' => null,
            'motif' => null, 'refus_passage' => null, 'avertissements' => [], 'depart_requis' => true,
            'depart_date' => null, 'depart' => null, 'proposition' => null,
        ];

        $bande = $this->bande;
        if (! $bande || ! $this->dateValide($this->selectedDate)) {
            return $sortie;
        }

        $service = app(EffectifParCategorieService::class);
        $etat = $service->etatPourJour($bande->loadMissing('species'), $this->selectedDate);
        $sortie['depart_date'] = $etat['depart_date'];
        $sortie['depart'] = $etat['depart'];
        $sortie['motif'] = $etat['refus'];
        $veille = $etat['veille'];

        if ($etat['mode'] === 'sans_chaine') {
            // Aucune chaîne : le départ est demandé. Proposition d'après le stade de la bande (jamais appliquée seule).
            $sortie['mode'] = 'depart_requis';
            $sortie['proposition'] = EffectifParCategorieService::departDepuisStade($bande, $this->previousEffectif);
            $saisi = $this->departSaisi();

            if (in_array(null, $saisi, true)) {
                if (count(array_filter($saisi, fn ($v) => $v !== null)) > 0) {
                    $sortie['motif'] = EffectifParCategorieService::verifierDepart($saisi, $this->previousEffectif);
                }

                return $sortie;
            }

            $sortie['motif'] = EffectifParCategorieService::verifierDepart($saisi, $this->previousEffectif);
            if ($sortie['motif'] !== null) {
                return $sortie;
            }
            $veille = $saisi;     // aperçu : le départ saisi est l'effectif au DÉBUT du jour (D4)
        } else {
            $sortie['mode'] = $etat['mode'];
            $sortie['depart_requis'] = false;
        }

        if ($veille === null) {
            return $sortie;       // avant le départ ou départ stocké refusé
        }

        $ventes = $this->ventesDuJour;
        $resultat = EffectifParCategorieService::calculerJour(EffectifParCategorieService::VOLAILLES_PONTE, $veille, [
            'achat' => $this->achat, 'ne' => $this->ne,
            'vente_repro' => $ventes['repro'], 'vente_sevre' => $ventes['sevre'], 'vente_jeune' => $ventes['jeune'], 'vente_4' => $ventes['quatre'],
            'mort_repro' => $this->mortPondeuse, 'mort_sevre' => $this->mortPoussinCroissance, 'mort_jeune' => $this->mortPoulette, 'mort_4' => $this->mortPoussinPonte,
            'don_repro' => $this->donPondeuse, 'don_sevre' => $this->donPoussinCroissance, 'don_jeune' => $this->donPoulette, 'don_4' => $this->donPoussinPonte,
            'passage_4_sevre' => $this->passage1, 'passage' => $this->passage2, 'passage_jeune_repro' => $this->passage3,
        ] + $this->transfertsDuJour, $this->effectifFinalCalc);

        $sortie['resultat'] = $resultat;
        $sortie['repro'] = $resultat->repro;
        $sortie['sevre'] = $resultat->sevre;
        $sortie['jeune'] = $resultat->jeune;
        $sortie['quatre'] = $resultat->quatre;
        $sortie['refus_passage'] = $resultat->refus;

        // D8 : avertissement DATÉ, jamais un blocage (le plancher à 0 de chaque stade suffit à le produire).
        if ($resultat->sommeDifferente === true) {
            $sortie['avertissements'][] = 'Avertissement — fiche du '.Carbon::parse($this->selectedDate)->format('d/m/Y')
                .' : la somme des stades ('.$resultat->somme().') diffère de l\'effectif total ('.$this->effectifFinalCalc
                .'). Un effectif de stade ne descend jamais sous 0 : vérifiez les ventes, morts et dons saisis.';
        }

        return $sortie;
    }

    /** D9 : des morts supérieurs à l'effectif de la veille ne bloquent pas (plancher à 0) — l'écran le dit. */
    public function getAvertissementMortsProperty(): ?string
    {
        $morts = $this->mortDuJour();

        return $morts > $this->previousEffectif
            ? "Morts du jour ({$morts}) supérieurs à l'effectif de la veille ({$this->previousEffectif}) : l'effectif est ramené à 0, vérifiez la saisie."
            : null;
    }

    /** Ticket VOL-2 — reprend la proposition de départ déduite du stade de la bande (action explicite de l'éleveur). */
    public function appliquerPropositionDepart(): void
    {
        $proposition = $this->categoriesJour['proposition'];

        if ($proposition === null) {
            $this->dispatch('toast', message: 'Aucune proposition pour le stade de cette bande : saisissez le départ de chaque stade.', type: 'warning');

            return;
        }

        $this->departPondeuse = $proposition['repro'];
        $this->departPoussinCroissance = $proposition['sevre'];
        $this->departPoulette = $proposition['jeune'];
        $this->departPoussinPonte = $proposition['quatre'];
    }

    public function saveDay(): void
    {
        $this->authorize('manage-elevage');
        $lot = $this->bande;

        if (! $lot) {
            $this->dispatch('toast', message: "Aucune bande active au stade Ponte. Créez d'abord une bande.", type: 'error');

            return;
        }

        // 🔴→✅ Ticket EX5 (EF5, décision Q3 du 20/10/2026) — une fiche datée dans un exercice CLOS est refusée : le stock
        // consommé de cet exercice est figé avec son inventaire. Même motif R4 qu'à l'envoi d'un poste.
        if ($refusExercice = app(\App\Services\AccountingEntryService::class)->refusExerciceClos($this->selectedDate)) {
            $this->dispatch('toast', message: $refusExercice, type: 'error');

            return;
        }

        if (! $this->dateValide($this->selectedDate)) {
            $this->dispatch('toast', message: 'Date invalide : choisissez un jour.', type: 'error');

            return;
        }

        // --- Ticket VOL-2 : contrôles AVANT toute écriture ------------------------------------------------------
        $cat = $this->categoriesJour;

        // Un jour antérieur au départ n'est pas saisissable (jamais d'effectif inconnu affiché).
        if ($cat['mode'] === 'avant_depart') {
            $this->dispatch('toast', message: 'Jour antérieur à l\'effectif de départ fixé le '.Carbon::parse($cat['depart_date'])->format('d/m/Y').' : il n\'est pas saisissable.', type: 'error');

            return;
        }

        // Départ stocké incohérent (D4) : la chaîne est refusée.
        if ($cat['mode'] === 'refus') {
            $this->dispatch('toast', message: $cat['motif'], type: 'error');

            return;
        }

        // Bande sans départ : il doit être saisi, complet et cohérent, AVANT d'enregistrer la journée.
        $departAEcrire = false;
        if ($cat['mode'] === 'depart_requis') {
            $departSaisi = $this->departSaisi();
            $refusDepart = count(array_filter($departSaisi, fn ($v) => $v !== null)) === 0
                ? 'Saisissez d\'abord l\'effectif de départ de la bande par stade (Poussin ponte, Poussin en croissance, Poulette, Pondeuse) : la journée ne peut pas être enregistrée sans lui.'
                : EffectifParCategorieService::verifierDepart($departSaisi, $this->previousEffectif);
            if ($refusDepart !== null) {
                $this->dispatch('toast', message: $refusDepart, type: 'error');

                return;
            }
            $departAEcrire = true;
        }

        // D3 : un passage de stade supérieur à son stade source ne s'enregistre pas.
        if ($cat['refus_passage'] !== null) {
            $this->dispatch('toast', message: $cat['refus_passage'], type: 'error');

            return;
        }

        $mort = $this->mortPondeuse + $this->mortPoulette + $this->mortPoussinCroissance + $this->mortPoussinPonte;
        $don = $this->donPondeuse + $this->donPoulette + $this->donPoussinCroissance + $this->donPoussinPonte;

        // Fiche d'AVANT le ticket (morts / dons / ventes non ventilés) : on ne devine pas le stade, on le dit.
        if (($this->mortEnregistre !== null && $mort === 0) || ($this->donEnregistre !== null && $don === 0)) {
            $this->dispatch('toast', message: 'Cette fiche porte des morts ou des dons non ventilés par stade : ventilez-les (Poussin ponte / Poussin en croissance / Poulette / Pondeuse) avant d\'enregistrer.', type: 'error');

            return;
        }
        if ($this->ventesDuJour['non_ventilee']) {
            $this->dispatch('toast', message: 'Cette journée porte des ventes d\'avant la mise en place des stades, non ventilées : elle ne peut pas être ré-enregistrée. Saisissez le départ de la bande un autre jour.', type: 'error');

            return;
        }

        $ventes = $this->ventesDuJour;
        $effectifFinal = $this->effectifFinalCalc;

        // Ticket 15.56 — état AVANT enregistrement : naissances, morts et dons ne sortent du stock du produit de la
        // bande que par ÉCART (`SyncLotProductionStockAction`), comme sur les quatre autres fiches.
        $ficheAvant = LivestockDailyEntry::where('lot_id', $lot->id)->whereDate('entry_date', $this->selectedDate)->first();
        $etatAvant = $ficheAvant
            ? ['ne' => (int) $ficheAvant->ne, 'mort' => (int) $ficheAvant->mort, 'don' => (int) ($ficheAvant->don ?? 0)]
            : [];

        $dailyEntry = DB::transaction(function () use ($effectifFinal, $etatAvant, $lot, $mort, $don, $ventes, $departAEcrire) {
            // 🔴→✅ Ticket U14 — UNE TRANSACTION, ET LE STOCK AVANT LA FICHE (`OrdreDesVerrous`), comme les fiches Porcs et
            // Lapins, la caisse et l'envoi des postes. Ces écritures (fiche, production au stock, cascade) partaient une par
            // une : une erreur au milieu laissait la fiche sans son mouvement de stock.
            OrdreDesVerrous::stock(OrdreDesVerrous::produitsDesFiches([$lot->id]));

            $dailyEntry = LivestockDailyEntry::updateOrCreate(
                ['lot_id' => $lot->id, 'entry_date' => $this->selectedDate],
                [
                    'achat' => $this->achat,
                    'ne' => $this->ne,
                    'mort' => $mort,
                    'vente' => $this->venteDuJour,
                    'don' => $don,
                    'effectif_final' => $effectifFinal,
                    'ponte_total' => $this->oeufsRecoltes,
                    'ponte_casses' => $this->oeufsCasses,
                    // Ticket VOL-2 — MOUVEMENTS PAR STADE persistés (ils rechargent le jour et alimentent la chaîne). Les
                    // ventes viennent de la caisse (lues, jamais saisies ici) : `vente` = leur somme.
                    'mort_repro' => $this->mortPondeuse, 'mort_sevre' => $this->mortPoussinCroissance, 'mort_jeune' => $this->mortPoulette, 'mort_4' => $this->mortPoussinPonte,
                    'don_repro' => $this->donPondeuse, 'don_sevre' => $this->donPoussinCroissance, 'don_jeune' => $this->donPoulette, 'don_4' => $this->donPoussinPonte,
                    'vente_repro' => $ventes['repro'], 'vente_sevre' => $ventes['sevre'], 'vente_jeune' => $ventes['jeune'], 'vente_4' => $ventes['quatre'],
                    'passage_4_sevre' => $this->passage1, 'passage_sevre_jeune' => $this->passage2, 'passage_jeune_repro' => $this->passage3,
                    // Ticket 15.57 — moyenne par sujet (g), comme les fiches Reproducteurs et Escargots.
                    'weight_sample_avg_g' => $this->peseeTotal && $effectifFinal > 0
                        ? (int) round($this->peseeTotal / $effectifFinal)
                        : null,
                ]
            );

            // Le DÉPART n'est écrit qu'UNE fois (verrouillé ensuite) ; les `cat_eff_*` ne sont jamais écrits ici : la chaîne
            // (cascade ci-dessous) les dérive.
            if ($departAEcrire) {
                $dailyEntry->fill([
                    'cat_depart_repro' => $this->departPondeuse,
                    'cat_depart_sevre' => $this->departPoussinCroissance,
                    'cat_depart_jeune' => $this->departPoulette,
                    'cat_depart_4' => $this->departPoussinPonte,
                ])->save();
            }

            // 🔴→✅ CORRECTIF « EFFECTIF TOTAL VIVANT » — la bande prenait l'effectif du jour ÉDITÉ.
            // Saisir ou corriger une fiche antérieure à la dernière remplaçait `current_quantity` par
            // l'effectif de CE jour (KPI « Effectif Total Vivant » faux sur Gestion des Bandes, Gestion
            // Élevage, Tableau de bord), sans recalculer les fiches suivantes. Même point d'entrée que
            // les fiches Porcs/Lapins (ticket 15.42), la vente antidatée et le push : jours suivants
            // recalculés, bande = DERNIÈRE fiche.
            app(RecordSaleOnFicheElevageAction::class)->recalculerEnCascade($lot->id, $this->selectedDate);

            // ⚠️ Ajustement de stock appliqué uniquement à la création de la fiche
            // du jour, jamais à sa modification — bug préexistant découvert
            // pendant le rétro-câblage (ticket 6.1) : incrémenter le stock à
            // chaque sauvegarde, y compris une simple correction du même jour,
            // aurait compté les œufs plusieurs fois. Modifier une fiche déjà
            // enregistrée ne réajuste donc pas le stock — limitation connue,
            // à traiter par un recalcul différentiel si un besoin réel émerge.
            // ⚠️ TICKET 14.59 — RÈGLE EXTRAITE DANS
            // `RecordEggProductionStockAction`. Elle vivait ici, donc la
            // synchronisation ne pouvait pas l'atteindre : une ponte saisie hors
            // ligne arrivait au serveur sans entrer un seul œuf au stock.
            // (VOL-2 : les ŒUFS ne changent pas.)
            if ($dailyEntry->wasRecentlyCreated) {
                app(RecordEggProductionStockAction::class)->execute($dailyEntry);
            }

            // Ticket 15.56 — la bande rattachée à un produit voit ses naissances, morts et DONS répercutés au stock.
            app(SyncLotProductionStockAction::class)->execute($dailyEntry, $etatAvant);

            return $dailyEntry;
        });

        $this->purgerCalculs();

        // L'alerte d'autonomie alimentaire remonte à la cloche (ticket 14.40), sur la provende des QUATRE stades.
        $provende = $this->feedAutonomy;
        if (($provende['available'] ?? false) && ! empty($provende['product']) && empty($provende['inconnu'])) {
            app(RaiseFeedAutonomyAlertAction::class)->execute($provende['product'], (float) $this->rationnement['total_kg']);
        }

        AuditLog::record('livestock_daily_entry.saved', 'elevage');
        $this->dispatch('toast', message: 'Jour enregistré avec succès.', type: 'success');
    }

    /**
     * Ticket VOL-2 — RATIONNEMENT PAR STADE : effectif calculé de chaque stade × la ration de sa ligne du barème de
     * l'aviculture (clés stables `StadePondeuse`), même tableau que le poste. Tant que le départ n'est pas valide, les
     * effectifs sont indisponibles (`null`) et le total aussi — la vue ne montre alors que la demande de départ.
     */
    public function getRationnementProperty(): array
    {
        $cat = $this->categoriesJour;

        return StadePondeuse::tableau(
            FeedRationStandard::where('species_code', 'aviculture')->get(),
            ['repro' => $cat['repro'], 'sevre' => $cat['sevre'], 'jeune' => $cat['jeune'], 'quatre' => $cat['quatre']],
        );
    }

    /** Autonomie alimentaire de la filière sur la provende du jour (SOMME des quatre stades). */
    public function getFeedAutonomyProperty(): ?array
    {
        $service = app(AutonomieAlimentaireService::class);

        return $service->evaluer($service->produitProvende('aviculture'), $this->rationnement['total_kg']);
    }

    public function render()
    {
        return view('livewire.elevage.fiche-pondeuses', ['title' => 'Élevage > Fiches Pondeuses']);
    }
}
