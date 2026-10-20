<?php

namespace App\Livewire\Rapports;

use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Services\PdfExportService;
use Illuminate\Support\Facades\Response;
use Livewire\Attributes\On;
use App\Services\EggStockLedgerService;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 12.6 (Sprint 12) — rapport-elevage-synth.html →
 * Livewire\Rapports\ElevageSynth
 * "Restitution fidèle des registres manuscrits — recensement,
 * mouvements et suivi de ponte, alimentée automatiquement depuis les
 * fiches d'élevage." Le rapport le plus complexe des 6 onglets du hub
 * (3 tableaux croisés).
 *
 * Source unique et réelle : `LivestockDailyEntry` (fiches journalières
 * réelles, tickets 3.5+, formules déjà vérifiées et centralisées dans le
 * modèle lui-même — jamais recalculées différemment ici).
 *
 * ⚠️ ÉCART DE SCHÉMA HONNÊTEMENT SIGNALÉ (Tableau 1) : le prototype
 * détaille des catégories spécifiques à l'aviculture reproducteurs
 * (Mères Pondeuses/Couveuses/Éleveuses distinctes, Morts M/F/SM séparés,
 * Géniteurs, Effectif Malade) qu'aucune colonne dédiée de
 * `LivestockDailyEntry` (schéma universel toutes espèces) ne porte
 * individuellement. Plutôt qu'inventer des chiffres pour ces libellés
 * exacts, ce tableau affiche les colonnes RÉELLEMENT disponibles et
 * honnêtement les plus proches (`effectif_m`/`effectif_f`/`effectif_smeres`/
 * `effectif_sevres`/`mort`/`achat`/`ne`/`effectif_final`) avec leurs
 * propres libellés généraux, jamais une correspondance forcée qui
 * afficherait une vraie donnée sous un faux nom.
 *
 * 🔴→✅ TABLEAU 3 COMPLÉTÉ AU TICKET 14.46. La limite inscrite ici
 * affirmait qu'« un grand livre de stock d'œufs n'existe nulle part dans
 * ce projet ». C'était vrai à la rédaction, faux depuis le ticket 14.13 :
 * le grand livre existait, ENFERMÉ dans le composant `FichePondeuses`.
 * Extrait dans `EggStockLedgerService` (jamais recopié — deux soldes
 * d'œufs finiraient par diverger), il alimente maintenant les quatre
 * colonnes SRH / TS / OS / Stock Final avec les formules du prototype :
 *     Total Stock (TS) = (OR − OF) + SRH        Stock Final = TS − OS
 *
 * ⚠️ CES QUATRE COLONNES SONT DES SOLDES DE FERME, PAS DE BANDE. Le stock
 * d'œufs est tenu au niveau du PRODUIT : rien dans `stock_movements` ne
 * distingue l'œuf issu d'une bande de celui issu d'une autre. Deux bandes
 * pondeuses le même jour lisent donc le même SRH. C'est dit à l'écran —
 * répartir au prorata inventerait une traçabilité qui n'existe pas.
 *
 * Tableau 2 (Mouvements, Traitements & Ventes) : ENTIÈREMENT réel, aucun
 * écart — chaque colonne du prototype a une colonne correspondante
 * directe dans `LivestockDailyEntry`.
 *
 * 🔴→✅ TICKET 14.49 (AUDIT DE FIDÉLITÉ) — la première colonne du Tableau 3,
 * « Âge (Sem.) », avait été REMPLACÉE par « Jour » sans justification écrite.
 * Elle est pourtant calculable (date de création de la bande), et c'est la
 * colonne qui donne son sens à toutes les autres : la production d'une
 * pondeuse ne se lit qu'en regard de son âge. Rétablie, en position sticky
 * comme dans le prototype.
 *
 * ⚠️ La colonne « Lot » reste un AJOUT assumé au-delà du prototype, qui
 * n'affiche qu'une seule bande : ce rapport en couvre plusieurs, et sans elle
 * deux bandes deviendraient indiscernables sur une même journée. Le Tableau 3
 * compte donc 11 colonnes contre 10 au prototype — écart d'ajout, jamais de
 * perte.
 */
class ElevageSynth extends Component
{
    public string $startDate;

    public string $endDate;

    #[Url]
    public string $lotFilter = '';

    public string $activeTable = 't1';

    public function mount(string $startDate, string $endDate): void
    {
        $this->startDate = $startDate;
        $this->endDate = $endDate;
    }

    public function getLotsProperty()
    {
        return LivestockLot::where('is_active', true)->orderBy('code')->get();
    }

    /**
     * 🔴→✅ TICKET U11 — ORDRE DÉTERMINISTE. Deux fiches du même jour (deux bandes) sortaient dans l'ordre que le
     * moteur de base voulait bien leur donner : MySQL, SQLite et le poste pouvaient les présenter autrement, et la
     * fiche « la plus ancienne » de la mortalité hebdo (`sortBy('entry_date')->first()`) dépendait de ce hasard.
     * Second critère : l'identifiant (UUID), croissant — le même au poste (`RapportsRepository.ordreDesFiches`).
     */
    private function baseQuery()
    {
        return LivestockDailyEntry::with(['lot.species', 'treatmentProduct'])
            ->whereDate('entry_date', '>=', $this->startDate)
            ->whereDate('entry_date', '<=', $this->endDate)
            ->when($this->lotFilter, fn ($q) => $q->where('lot_id', $this->lotFilter))
            ->orderByDesc('entry_date')
            ->orderBy('id');
    }

    public function getEntriesProperty()
    {
        return $this->baseQuery()->get();
    }

    /**
     * Grand livre d'œufs par DATE affichée. Indexé par date : deux bandes
     * pondeuses le même jour partagent le même solde de ferme, et la
     * production commercialisable du jour est agrégée une seule fois.
     */
    public function getLedgerOeufsProperty(): array
    {
        $service = app(EggStockLedgerService::class);
        $ledger = [];

        $parDate = $this->entries
            ->where('ponte_total', '>', 0)
            ->groupBy(fn ($e) => $e->entry_date->format('Y-m-d'));

        foreach ($parDate as $date => $duJour) {
            $commercialisables = (int) $duJour->sum(fn ($e) => max(0, (int) $e->ponte_total - (int) $e->ponte_casses));
            $ledger[$date] = $service->ligne($date, $commercialisables);
        }

        return $ledger;
    }

    public function getKpisProperty(): array
    {
        $entries = $this->entries;

        $productionTotale = (int) $entries->sum('ponte_total');

        $pontePositive = $entries->filter(fn ($e) => $e->effectif_final > 0 && $e->ponte_total > 0);
        $tauxPonteMoyen = $pontePositive->isNotEmpty()
            ? round($pontePositive->avg(fn ($e) => ($e->ponte_total / $e->effectif_final) * 100), 1)
            : null;

        // Taux de Mortalité Hebdo = (Cumul Morts ÷ Effectif Début) × 100 —
        // même formule affichée sous le Tableau 1, effectif début pris sur
        // l'entrée la plus ancienne de la période sélectionnée.
        $totalMorts = (int) $entries->sum('mort');
        $earliestEntry = $entries->sortBy('entry_date')->first();
        $effectifDebut = $earliestEntry?->previousEffectif() ?? 0;
        $tauxMortaliteHebdo = $effectifDebut > 0 ? round(($totalMorts / $effectifDebut) * 100, 1) : null;

        $caVentes = (float) $entries->sum('vente_montant');

        return [
            'production_totale' => $productionTotale,
            'taux_ponte_moyen' => $tauxPonteMoyen,
            'taux_mortalite_hebdo' => $tauxMortaliteHebdo,
            'ca_ventes' => $caVentes,
        ];
    }

    #[On('export-report')]
    public function exportReport(string $format, string $startDate, string $endDate)
    {
        $this->authorize('export-rapports');

        $this->startDate = $startDate;
        $this->endDate = $endDate;

        $entries = $this->entries;
        $period = \Carbon\Carbon::parse($startDate)->format('d/m/Y').' au '.\Carbon\Carbon::parse($endDate)->format('d/m/Y');

        if ($format === 'pdf') {
            $pdf = app(PdfExportService::class)->render(
                'exports.elevage-synth',
                ['entries' => $entries],
                'Rapport Élevage — Synthèse Détaillée',
                $period
            );

            return response()->streamDownload(fn () => print($pdf->output()), 'rapport-elevage-'.now()->format('Y-m-d').'.pdf');
        }

        $csv = "Date,Lot,Effectif M,Effectif F,Sous Mères,Sevrés,Morts,Achats,Nés,Effectif Final,Vente Qté,Vente Montant,Ponte Totale,Ponte Cassés\n";
        foreach ($entries as $e) {
            $csv .= implode(',', [
                $e->entry_date->format('d/m/Y'),
                '"'.($e->lot?->code ?? '').'"',
                $e->effectif_m, $e->effectif_f, $e->effectif_smeres, $e->effectif_sevres,
                $e->mort, $e->achat, $e->ne, $e->effectif_final,
                $e->vente, $e->vente_montant, $e->ponte_total, $e->ponte_casses,
            ])."\n";
        }

        return Response::streamDownload(fn () => print($csv), 'rapport-elevage-'.now()->format('Y-m-d').'.csv', ['Content-Type' => 'text/csv']);
    }

    public function render()
    {
        return view('livewire.rapports.elevage-synth');
    }
}
