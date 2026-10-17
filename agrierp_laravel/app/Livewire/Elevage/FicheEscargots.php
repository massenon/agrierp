<?php

namespace App\Livewire\Elevage;

use App\Actions\RecordSaleOnFicheElevageAction;
use App\Actions\SyncLotProductionStockAction;
use App\Livewire\Elevage\Concerns\AvecSoinsDuMois;
use App\Models\AuditLog;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\ModuleConfig;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Ticket 3.9 (Sprint 3) — fiche-escargots.html → Livewire\Elevage\FicheEscargots
 * Implémentation réelle complète, visibilité conditionnée à
 * `modules_config.helico` — DERNIÈRE FICHE ESPÈCE DU SPRINT 3.
 *
 * Vérification SERVEUR (Document 00 §2.4 : le masquage de menu n'est
 * qu'un confort d'affichage, la vraie autorisation est vérifiée à chaque
 * action) dans `mount()` — un accès direct à l'URL alors que le module est
 * désactivé est bloqué ici, pas seulement caché dans le hub (ticket 3.2).
 *
 * Workflow Ponte en Terre & Éclosion des Naissains — même mécanique que
 * `FicheReproducteurs` (ticket 3.7) : `ponte_total` = œufs pondus en terre,
 * `ne` = naissains nés. Taux d'Éclosion applicable ici (Aviculture
 * Reproducteurs ET Héliciculture uniquement, FORMULE_FICHE_ELEVAGE.md §3).
 *
 * Ventilation effectif (4 sous-colonnes du tableau mensuel réel :
 * Naissains/Engraiss./Bordés/Total, PAS M/F/Sevrés/S-Mères comme Lapins —
 * confirmé par lecture directe, lignes 460-463) réutilise
 * `effectif_m`→Naissains, `effectif_f`→Engraissement, `effectif_sevres`→
 * Bordés (reproducteurs), `effectif_smeres` non utilisé pour cette espèce
 * (pas de 4e catégorie dans le prototype réel).
 *
 * ⚠️ RATIONNEMENT NON IMPLÉMENTÉ, SIGNALÉ EXPLICITEMENT : le prototype
 * demande un "Rationnement Farine Calcique & Fourrage" propre aux
 * escargots, mais aucun barème n'a été fourni pour cette filière
 * (`feed_ration_standards`, ticket 2.7, ne couvre que cuniculture/
 * aviculture/porciculture — Héliciculture explicitement désactivée par
 * défaut, Document 00 §5.1). Plutôt que d'inventer un grammage non
 * documenté, cette section reste en bandeau d'attente.
 */
#[Layout('layouts.app')]
class FicheEscargots extends Component
{
    use AvecSoinsDuMois;

    public string $selectedDate;

    public int $achat = 0;

    public int $naissainsNes = 0;

    public int $oeufsTerre = 0;

    public int $mortBorde = 0;

    public int $mortEngraissement = 0;

    public int $mortNaissain = 0;

    public int $effectifNaissains = 0;

    public int $effectifEngraissement = 0;

    public int $effectifBordes = 0;

    public ?int $peseeTotal = null;

    public string $observations = '';

    public bool $moduleEnabled = false;

    public function mount(): void
    {
        $this->moduleEnabled = ModuleConfig::isEnabled('helico');
        $this->selectedDate = now()->format('Y-m-d');
    }

    public function getLotsProperty()
    {
        if (! $this->moduleEnabled) {
            return collect();
        }

        return LivestockLot::whereHas('species', fn ($q) => $q->where('code', 'helico'))
            ->where('status', 'actif')
            ->where('is_active', true)
            ->get();
    }

    public function getKpisProperty(): array
    {
        $lotIds = $this->lots->pluck('id');
        $monthEntries = LivestockDailyEntry::whereIn('lot_id', $lotIds)
            ->whereBetween('entry_date', [now()->startOfMonth(), now()->endOfMonth()])
            ->get();

        $totalOeufs = $monthEntries->sum('ponte_total');
        $totalNaissains = $monthEntries->sum('ne');
        $totalMorts = $monthEntries->sum('mort');
        $totalEffectifDepart = $monthEntries->sum(fn ($e) => $e->previousEffectif());

        return [
            'effectif_total' => (int) $this->lots->sum('current_quantity'),
            'naissains_mois' => (int) $totalNaissains,
            'taux_eclosion' => $totalOeufs > 0 ? round(($totalNaissains / $totalOeufs) * 100, 1) : 0.0,
            'taux_mortalite_mois' => $totalEffectifDepart > 0 ? round(($totalMorts / $totalEffectifDepart) * 100, 1) : 0.0,
        ];
    }

    /** Bandes du tableau mensuel (AvecSoinsDuMois). */
    protected function lotsDuTableauMensuel(): array
    {
        return $this->lots->pluck('id')->all();
    }

    public function getMonthlyEntriesProperty()
    {
        $lotIds = $this->lots->pluck('id');

        // Ticket audit fidélité : eager-load treatmentProduct — colonne
        // "Traitements & Prophylaxie" du prototype, trouvée manquante du
        // tableau mensuel (même écart que fiche-lapins.html), corrigée
        // dans la foulée pour les 3 fiches partageant ce même patron.
        return LivestockDailyEntry::whereIn('lot_id', $lotIds)
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
            'Fiche Escargots — Suivi Mensuel',
            now()->translatedFormat('F Y')
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'fiche-'.now()->format('Y-m').'.pdf');
    }

    public function getDaysInMonthProperty(): array
    {
        return range(1, now()->daysInMonth);
    }

    public function getPreviousEffectifProperty(): int
    {
        $entry = LivestockDailyEntry::whereIn('lot_id', $this->lots->pluck('id'))
            ->where('entry_date', '<', $this->selectedDate)
            ->orderByDesc('entry_date')
            ->first();

        return $entry?->effectif_final ?? (int) $this->lots->sum('initial_quantity');
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
        $lot = $this->lots->first();

        if (! $lot) {
            return 0;
        }

        return (int) (LivestockDailyEntry::where('lot_id', $lot->id)
            ->where('entry_date', $this->selectedDate)
            ->value('vente') ?? 0);
    }

    public function getEffectifFinalCalcProperty(): int
    {
        $mort = $this->mortBorde + $this->mortEngraissement + $this->mortNaissain;

        return LivestockDailyEntry::computeEffectifFinal($this->previousEffectif, $this->achat, $this->naissainsNes, $mort, $this->venteDuJour, 0);
    }

    public function getMortalityRateCalcProperty(): float
    {
        $mort = $this->mortBorde + $this->mortEngraissement + $this->mortNaissain;

        return $this->previousEffectif > 0 ? round(($mort / $this->previousEffectif) * 100, 1) : 0.0;
    }

    public function getEclosionRateCalcProperty(): float
    {
        return $this->oeufsTerre > 0 ? round(($this->naissainsNes / $this->oeufsTerre) * 100, 1) : 0.0;
    }

    public function loadDay(string $date): void
    {
        $this->selectedDate = $date;
        $entry = $this->monthlyEntries->get($date);

        if ($entry) {
            $this->achat = $entry->achat;
            $this->oeufsTerre = $entry->ponte_total ?? 0;
            $this->naissainsNes = $entry->ne;
            $this->effectifNaissains = $entry->effectif_m ?? 0;
            $this->effectifEngraissement = $entry->effectif_f ?? 0;
            $this->effectifBordes = $entry->effectif_sevres ?? 0;
            // Le TOTAL pese se reconstitue depuis la moyenne stockee.
            $effectifFiche = (int) ($entry->effectif_final ?? 0);
            $this->peseeTotal = $entry->weight_sample_avg_g && $effectifFiche > 0
                ? (int) round($entry->weight_sample_avg_g * $effectifFiche)
                : null;
        } else {
            $this->reset(['achat', 'oeufsTerre', 'naissainsNes', 'mortBorde', 'mortEngraissement', 'mortNaissain', 'effectifNaissains', 'effectifEngraissement', 'effectifBordes', 'peseeTotal']);
        }
    }

    public function saveDay(): void
    {
        $this->authorize('manage-elevage');
        $lot = $this->lots->first();

        if (! $lot) {
            $this->dispatch('toast', message: "Aucune bande active en héliciculture. Créez d'abord une bande.", type: 'error');

            return;
        }

        $mort = $this->mortBorde + $this->mortEngraissement + $this->mortNaissain;
        $effectifFinal = $this->effectifFinalCalc;        // 🔴→✅ TICKET 14.37 — état AVANT enregistrement, pour n'appliquer
        // au stock que l'ÉCART. Une fiche se corrige : appliquer les
        // valeurs telles quelles compterait la production autant de fois
        // que la journée est sauvegardée.
        $ficheAvant = LivestockDailyEntry::where('lot_id', $lot->id)
            ->whereDate('entry_date', $this->selectedDate)
            ->first();

        $etatAvant = $ficheAvant
            ? ['ne' => (int) $ficheAvant->ne, 'mort' => (int) $ficheAvant->mort, 'don' => (int) ($ficheAvant->don ?? 0)]
            : [];



        $entree = LivestockDailyEntry::updateOrCreate(
            ['lot_id' => $lot->id, 'entry_date' => $this->selectedDate],
            [
                'achat' => $this->achat,
                'ne' => $this->naissainsNes,
                'mort' => $mort,
                'vente' => $this->venteDuJour,
                'don' => 0,
                'effectif_final' => $effectifFinal,
                'ponte_total' => $this->oeufsTerre,
                'effectif_m' => $this->effectifNaissains,
                'effectif_f' => $this->effectifEngraissement,
                'effectif_sevres' => $this->effectifBordes,
                // 🔴→✅ TICKET 14.63 — LA COLONNE PORTE LE POIDS **MOYEN PAR
                // SUJET**, en grammes. Cette fiche y deposait le TOTAL pese :
                // `GrowthAnalysisService` en tire le GMQ en la traitant comme
                // une moyenne, si bien qu'une bande qui perd des animaux voyait
                // son « poids » BAISSER et son GMQ devenir negatif — un
                // indicateur de croissance qui lit un amaigrissement.
                //
                // ⚠️ ARRONDI, PAS TRONCATURE : la maquette calcule
                // `Math.round(poidsG / effectifFinal)`.
                'weight_sample_avg_g' => $this->peseeTotal && $effectifFinal > 0
                    ? (int) round($this->peseeTotal / $effectifFinal)
                    : null,
            ]
        );

        // La production du cheptel entre réellement en stock — naissances
        // portées au crédit, mortalité et dons au débit. Sans bande
        // rattachée à un produit, l'Action ne fait rien.
        app(SyncLotProductionStockAction::class)->execute($entree, $etatAvant);

        // 🔴→✅ CORRECTIF « EFFECTIF TOTAL VIVANT » — la bande prenait l'effectif du jour ÉDITÉ.
        // Saisir ou corriger une fiche antérieure à la dernière remplaçait `current_quantity` par
        // l'effectif de CE jour (KPI « Effectif Total Vivant » faux sur Gestion des Bandes, Gestion
        // Élevage, Tableau de bord), sans recalculer les fiches suivantes. Même point d'entrée que
        // les fiches Porcs/Lapins (ticket 15.42), la vente antidatée et le push : jours suivants
        // recalculés, bande = DERNIÈRE fiche.
        app(RecordSaleOnFicheElevageAction::class)->recalculerEnCascade($lot->id, $this->selectedDate);

        AuditLog::record('livestock_daily_entry.saved', 'elevage');
        $this->dispatch('toast', message: 'Jour enregistré avec succès.', type: 'success');
    }

    public function render()
    {
        return view('livewire.elevage.fiche-escargots', ['title' => 'Élevage > Fiches Escargots']);
    }
}
