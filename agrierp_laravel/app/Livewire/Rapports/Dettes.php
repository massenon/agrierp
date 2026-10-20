<?php

namespace App\Livewire\Rapports;

use App\Models\Payable;
use App\Services\PdfExportService;
use Illuminate\Support\Facades\Response;
use Livewire\Attributes\On;
use Livewire\Component;

/**
 * Ticket 12.5 (Sprint 12) — rapport-dettes.html →
 * Livewire\Rapports\Dettes
 * "Suivi des sommes dues aux fournisseurs."
 *
 * Symétrique exact de `Creances` (ticket 12.4) côté fournisseurs — même
 * décision de source : `payables` (`Payable`, ticket 5.7) déjà
 * pleinement peuplée, jamais le grand livre encore clairsemé.
 * "Montant Dû" = `Payable::getBalanceAttribute()`, déjà existant et déjà
 * réutilisé par `DettesFournisseursHub`/`SuiviDettes` (Sprint 5) — jamais
 * recalculé indépendamment ici.
 *
 * ⚠️ Écart volontaire avec `Creances` : ce prototype-ci affiche un champ
 * de recherche (`#search-rapport-dettes`) que `rapport-creances.html`
 * n'avait pas — fidélité pixel par écran individuel, pas une
 * uniformisation artificielle entre écrans siblings qui divergeraient
 * dans leur prototype source respectif.
 *
 * Période appliquée sur `due_date` (Échéance) — même logique que
 * `Creances`.
 */
class Dettes extends Component
{
    public string $startDate;

    public string $endDate;

    public string $search = '';

    public function mount(string $startDate, string $endDate): void
    {
        $this->startDate = $startDate;
        $this->endDate = $endDate;
    }

    public function getPayablesProperty()
    {
        return Payable::with('supplier')
            ->whereColumn('amount_paid', '<', 'amount')
            ->whereDate('due_date', '>=', $this->startDate)
            ->whereDate('due_date', '<=', $this->endDate)
            ->when($this->search, fn ($q) => $q->whereHas('supplier', fn ($q2) => $q2->where('name', 'like', '%'.$this->search.'%')))
            ->orderBy('due_date')
            // Ticket U12b — deux dettes de la même échéance : ordre déterminé (identifiant), repris par le poste.
            ->orderBy('id')
            ->get();
    }

    #[On('export-report')]
    public function exportReport(string $format, string $startDate, string $endDate)
    {
        $this->authorize('export-rapports');

        $this->startDate = $startDate;
        $this->endDate = $endDate;

        $payables = $this->payables;
        $period = \Carbon\Carbon::parse($startDate)->format('d/m/Y').' au '.\Carbon\Carbon::parse($endDate)->format('d/m/Y');

        if ($format === 'pdf') {
            $pdf = app(PdfExportService::class)->render(
                'exports.dettes',
                ['payables' => $payables],
                'État des Dettes Fournisseurs',
                $period
            );

            return response()->streamDownload(fn () => print($pdf->output()), 'dettes-'.now()->format('Y-m-d').'.pdf');
        }

        $csv = "Fournisseur,Montant Dû,Échéance\n";
        foreach ($payables as $p) {
            $csv .= '"'.($p->supplier?->name ?? '').'",'.$p->balance.','.$p->due_date->format('d/m/Y')."\n";
        }

        return Response::streamDownload(fn () => print($csv), 'dettes-'.now()->format('Y-m-d').'.csv', ['Content-Type' => 'text/csv']);
    }

    public function render()
    {
        return view('livewire.rapports.dettes');
    }
}
