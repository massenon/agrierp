<?php

namespace App\Livewire\Elevage;

use App\Livewire\Elevage\Concerns\AvecTransfertsDuJour;
use App\Actions\RecordEggProductionStockAction;
use App\Actions\RecordSaleOnFicheElevageAction;
use App\Livewire\Elevage\Concerns\AvecProphylaxieDuJour;
use App\Livewire\Elevage\Concerns\AvecSoinsDuMois;
use App\Models\AuditLog;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\Product;
use App\Models\StockMovement;
use App\Services\EggStockLedgerService;
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
 */
#[Layout('layouts.app')]
class FichePondeuses extends Component
{
    use AvecTransfertsDuJour;
    use AvecProphylaxieDuJour;
    use AvecSoinsDuMois;

    public string $selectedDate;

    public int $achat = 0;

    public int $ne = 0;

    public int $mortRepro = 0;

    public int $mortPoulette = 0;

    public int $mortPoussin = 0;

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
     * Ticket 15.47 — morts déjà enregistrés pour le jour rechargé. La répartition Reproducteurs / Poulettes /
     * Poussins n'est pas stockée (seul le total `mort` l'est) : sans ce total, ré-enregistrer le jour remettait
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
        $saisis = $this->mortRepro + $this->mortPoulette + $this->mortPoussin;

        return $saisis > 0 ? $saisis : (int) ($this->mortEnregistre ?? 0);
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
            ->whereBetween('entry_date', [now()->startOfMonth(), now()->endOfMonth()])
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
            ->whereBetween('entry_date', [now()->startOfMonth(), now()->endOfMonth()])
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
            now()->translatedFormat('F Y')
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'fiche-'.now()->format('Y-m').'.pdf');
    }

    public function getDaysInMonthProperty(): array
    {
        return range(1, now()->daysInMonth);
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

        return LivestockDailyEntry::computeEffectifFinal($this->previousEffectif, $this->achat, $this->ne, $mort, $this->venteDuJour, 0, $this->transfertsDuJour['transfert_entree'], $this->transfertsDuJour['transfert_sortie']);
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
        $entry = $this->monthlyEntries->get($date);

        $this->reset(['mortRepro', 'mortPoulette', 'mortPoussin', 'mortEnregistre']);

        if ($entry) {
            $this->achat = $entry->achat;
            $this->ne = $entry->ne;
            $this->mortEnregistre = (int) $entry->mort > 0 ? (int) $entry->mort : null;
            $this->oeufsRecoltes = $entry->ponte_total ?? 0;
            $this->oeufsCasses = $entry->ponte_casses ?? 0;
        } else {
            $this->reset(['achat', 'ne', 'oeufsRecoltes', 'oeufsCasses']);
        }
    }

    public function saveDay(): void
    {
        $this->authorize('manage-elevage');
        $lot = $this->bande;

        if (! $lot) {
            $this->dispatch('toast', message: "Aucune bande active au stade Ponte. Créez d'abord une bande.", type: 'error');

            return;
        }

        $mort = $this->mortDuJour();
        $effectifFinal = $this->effectifFinalCalc;

        $dailyEntry = LivestockDailyEntry::updateOrCreate(
            ['lot_id' => $lot->id, 'entry_date' => $this->selectedDate],
            [
                'achat' => $this->achat,
                'ne' => $this->ne,
                'mort' => $mort,
                'vente' => $this->venteDuJour,
                'don' => 0,
                'effectif_final' => $effectifFinal,
                'ponte_total' => $this->oeufsRecoltes,
                'ponte_casses' => $this->oeufsCasses,
            ]
        );

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
        if ($dailyEntry->wasRecentlyCreated) {
            app(RecordEggProductionStockAction::class)->execute($dailyEntry);
        }

        AuditLog::record('livestock_daily_entry.saved', 'elevage');
        $this->dispatch('toast', message: 'Jour enregistré avec succès.', type: 'success');
    }

    public function render()
    {
        return view('livewire.elevage.fiche-pondeuses', ['title' => 'Élevage > Fiches Pondeuses']);
    }
}
