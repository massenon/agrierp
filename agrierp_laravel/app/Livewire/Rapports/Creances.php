<?php

namespace App\Livewire\Rapports;

use App\Models\Receivable;
use App\Services\PdfExportService;
use Illuminate\Support\Facades\Response;
use Livewire\Attributes\On;
use Livewire\Component;

/**
 * Ticket 12.4 (Sprint 12) — rapport-creances.html →
 * Livewire\Rapports\Creances
 * "Suivi des sommes dues par les clients."
 *
 * Décision de source cohérente avec le texte du prototype lui-même : son
 * info-bulle dit "généré à partir des données réelles" (formulation
 * générique, à la différence de "écritures comptables réelles" du
 * ticket 12.3 précédent) — pour des créances clients, la source réelle
 * et déjà pleinement peuplée est directement `receivables`
 * (`Receivable`, ticket 4.7), pas le grand livre encore clairsemé.
 *
 * "Montant Dû" = `Receivable::getBalanceAttribute()`, déjà existant et
 * déjà réutilisé par `CreancesClientsHub`/`RelancesClients` (Sprint 4) —
 * jamais recalculé indépendamment ici, un seul point de vérité pour ce
 * qu'est le solde restant dû d'une créance.
 *
 * Période appliquée sur `due_date` (Échéance) — le champ que le tableau
 * affiche et trie naturellement, cohérent avec la colonne "Échéance" du
 * prototype.
 */
class Creances extends Component
{
    public string $startDate;

    public string $endDate;

    public function mount(string $startDate, string $endDate): void
    {
        $this->startDate = $startDate;
        $this->endDate = $endDate;
    }

    public function getReceivablesProperty()
    {
        return Receivable::with('customer')
            ->whereColumn('amount_paid', '<', 'amount')
            ->whereDate('due_date', '>=', $this->startDate)
            ->whereDate('due_date', '<=', $this->endDate)
            ->orderBy('due_date')
            ->get();
    }

    #[On('export-report')]
    public function exportReport(string $format, string $startDate, string $endDate)
    {
        $this->authorize('export-rapports');

        $this->startDate = $startDate;
        $this->endDate = $endDate;

        $receivables = $this->receivables;
        $period = \Carbon\Carbon::parse($startDate)->format('d/m/Y').' au '.\Carbon\Carbon::parse($endDate)->format('d/m/Y');

        if ($format === 'pdf') {
            $pdf = app(PdfExportService::class)->render(
                'exports.creances',
                ['receivables' => $receivables],
                'État des Créances Clients',
                $period
            );

            return response()->streamDownload(fn () => print($pdf->output()), 'creances-'.now()->format('Y-m-d').'.pdf');
        }

        $csv = "Client,Montant Dû,Échéance\n";
        foreach ($receivables as $r) {
            $csv .= '"'.($r->customer?->name ?? '').'",'.$r->balance.','.$r->due_date->format('d/m/Y')."\n";
        }

        return Response::streamDownload(fn () => print($csv), 'creances-'.now()->format('Y-m-d').'.csv', ['Content-Type' => 'text/csv']);
    }

    public function render()
    {
        return view('livewire.rapports.creances');
    }
}
