<?php

namespace App\Livewire\Comptabilite;

use App\Models\AccountingEntryLine;
use App\Models\CostCenter;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 10.7 (Sprint 10) — comptabilite-analytique.html →
 * Livewire\Comptabilite\ComptabiliteAnalytique
 * "Marges réelles par espèce/bande — croisement des charges (Classe 6)
 * et produits (Classe 7)."
 *
 * Même discipline architecturale que le Bilan (ticket 10.5) : calculé
 * EXCLUSIVEMENT depuis le grand livre (`accounting_entry_lines.cost_center_id`,
 * FK complétée au ticket 10.1), jamais en recalculant depuis des ventes
 * ou achats en direct — la comptabilité analytique est par définition un
 * découpage du grand livre par centre de coût, pas une source parallèle.
 *
 * ⚠️ MÊME CONSÉQUENCE HONNÊTE QUE LE BILAN : tant que le rétro-câblage
 * des modules métier (POS, Achats...) vers le grand livre reste différé
 * (ticket 10.2), et tant que ces modules n'assignent pas encore de
 * `cost_center_id` à leurs lignes générées, ce rapport affichera peu ou
 * pas de données réelles au-delà des écritures manuelles du Journal
 * Comptable (ticket 10.4) qui auraient explicitement renseigné un centre
 * de coût. Chaque montant affiché reste réel et vérifiable, la
 * couverture s'élargira avec le rétro-câblage.
 *
 * 5 centres de coûts de type "filière" seedés dans ce ticket
 * (`CostCentersSeeder`) — Cuniculture, Aviculture, Porciculture reliées
 * aux vraies espèces déjà seedées ; Maraîchage et Transformation sans
 * espèce associée (filières non liées à l'élevage).
 */
#[Layout('layouts.app')]
class ComptabiliteAnalytique extends Component
{
    #[Url]
    public string $startDate = '';

    #[Url]
    public string $endDate = '';

    #[Url]
    public string $filiereFilter = '';

    public function mount(): void
    {
        $this->startDate = now()->startOfMonth()->format('Y-m-d');
        $this->endDate = now()->endOfMonth()->format('Y-m-d');
    }

    public function getFilieresProperty()
    {
        return CostCenter::where('type', 'filiere')->where('is_active', true)->orderBy('label')->get();
    }

    /** Chiffre d'affaires (classe 7) et charges directes (classe 6) par filière — un seul point de calcul. */
    public function getRowsProperty()
    {
        return $this->filieres->map(function ($filiere) {
            $lines = AccountingEntryLine::query()
                ->join('accounting_entries', 'accounting_entries.id', '=', 'accounting_entry_lines.entry_id')
                ->where('accounting_entries.is_active', true)
                ->whereDate('accounting_entries.entry_date', '>=', $this->startDate)
                ->whereDate('accounting_entries.entry_date', '<=', $this->endDate)
                ->join('chart_of_accounts', 'chart_of_accounts.id', '=', 'accounting_entry_lines.account_id')
                ->where('accounting_entry_lines.cost_center_id', $filiere->id)
                ->whereIn('chart_of_accounts.class', [6, 7])
                ->selectRaw('chart_of_accounts.code, chart_of_accounts.label, chart_of_accounts.class, SUM(accounting_entry_lines.debit) as total_debit, SUM(accounting_entry_lines.credit) as total_credit')
                ->groupBy('chart_of_accounts.code', 'chart_of_accounts.label', 'chart_of_accounts.class')
                ->get();

            $ca = (float) $lines->where('class', 7)->sum(fn ($l) => $l->total_credit - $l->total_debit);
            $charges = (float) $lines->where('class', 6)->sum(fn ($l) => $l->total_debit - $l->total_credit);
            $marge = round($ca - $charges, 2);
            $taux = $ca > 0 ? round(($marge / $ca) * 100, 1) : null;

            $topCharges = $lines->where('class', 6)
                ->sortByDesc(fn ($l) => $l->total_debit - $l->total_credit)
                ->take(3)
                ->map(fn ($l) => ['code' => $l->code, 'label' => $l->label, 'amount' => round((float) $l->total_debit - (float) $l->total_credit, 2)])
                ->values();

            return [
                'filiere' => $filiere,
                'ca' => $ca,
                'charges' => $charges,
                'marge' => $marge,
                'taux' => $taux,
                'top_charges' => $topCharges,
            ];
        })->when($this->filiereFilter, fn ($rows) => $rows->filter(fn ($r) => $r['filiere']->label === $this->filiereFilter));
    }

    public function getKpisProperty(): array
    {
        $rows = $this->rows;
        $ca = $rows->sum('ca');
        $charges = $rows->sum('charges');
        $marge = round($ca - $charges, 2);

        return [
            'ca' => $ca,
            'charges' => $charges,
            'marge' => $marge,
            'taux' => $ca > 0 ? round(($marge / $ca) * 100, 1) : null,
        ];
    }

    public function getSelectedTopChargesProperty()
    {
        if (! $this->filiereFilter) {
            return null;
        }

        return $this->rows->first()['top_charges'] ?? collect();
    }

    /**
     * 🔴→✅ TROUVÉ MANQUANT PAR VÉRIFICATION NIVEAU 2 : bouton "Exporter
     * PDF" totalement absent — réutilise `getRowsProperty()` déjà réel,
     * même schéma d'export établi ailleurs dans ce projet.
     */
    public function exportComptaAnalytiquePdf()
    {
        $this->authorize('view-comptabilite');

        $rows = $this->rows;

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.comptabilite-analytique',
            ['rows' => $rows, 'kpis' => $this->kpis, 'startDate' => $this->startDate, 'endDate' => $this->endDate],
            'Comptabilité Analytique',
            'Du '.\Carbon\Carbon::parse($this->startDate)->format('d/m/Y').' au '.\Carbon\Carbon::parse($this->endDate)->format('d/m/Y')
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'comptabilite-analytique-'.now()->format('Y-m-d').'.pdf');
    }

    public function render()
    {
        return view('livewire.comptabilite.comptabilite-analytique', ['title' => 'Comptabilité > Analytique']);
    }
}
