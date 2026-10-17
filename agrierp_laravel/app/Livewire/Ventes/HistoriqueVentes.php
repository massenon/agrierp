<?php

namespace App\Livewire\Ventes;

use App\Actions\AdjustStockAction;
use App\Models\AuditLog;
use App\Models\Customer;
use App\Models\Product;
use App\Models\Receivable;
use App\Models\Sale;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 4.4 (Sprint 4) — historique-ventes.html → Livewire\Ventes\HistoriqueVentes
 * "Toutes les ventes enregistrées de l'entreprise." Un seul point de
 * vérité : interroge directement `sales`/`sale_lines`, alimentées
 * réellement par le POS (ticket 4.2) — aucune donnée dupliquée.
 *
 * ⚠️ CORRIGÉ AU TICKET 4.7 : ce composant dérivait initialement "Payée"
 * vs "En attente" directement depuis `sales.payment_mode = credit`, faute
 * de table de créances. `receivables` existe désormais (ticket 4.7) — le
 * statut et le solde dû interrogent maintenant cette table réelle, un
 * seul point de vérité partagé avec `ListeClients` et `RelancesClients`.
 *
 * Annulation réelle : `cancelSale()` repasse `status = annulee` ET
 * réintègre le stock des produits vendus — jamais un simple changement de
 * statut sans effet sur les données réelles qu'il a modifiées.
 *
 * Export PDF/Excel non repris ce ticket, signalé explicitement — le
 * PdfExportService existant (Sprint 0) sera câblé dans une session dédiée
 * plutôt qu'ajouté en fin de ticket déjà dense.
 */
class HistoriqueVentes extends Component
{
    #[Url]
    public string $search = '';

    #[Url]
    public string $statusFilter = '';

    #[Url]
    public string $modeFilter = '';

    #[Url]
    public string $customerFilter = '';

    public string $dateFrom;

    public string $dateTo;

    public ?string $viewingSaleId = null;

    public ?string $cancellingSaleId = null;

    public function mount(): void
    {
        $this->dateFrom = now()->startOfMonth()->format('Y-m-d');
        $this->dateTo = now()->format('Y-m-d');
    }

    public function getCustomersProperty()
    {
        return Customer::where('is_active', true)->orderBy('name')->get();
    }

    public function getSalesInRangeProperty()
    {
        return Sale::soldBetween($this->dateFrom, $this->dateTo)->get();
    }

    public function getKpisProperty(): array
    {
        $validSales = $this->salesInRange->where('status', 'validee');
        $count = $validSales->count();

        return [
            'ca' => (float) $validSales->sum('total'),
            'transactions' => $count,
            'panier_moyen' => $count > 0 ? round($validSales->sum('total') / $count) : 0,
            'encours_creances' => (float) Receivable::where('status', '!=', 'soldee')->sum('amount')
                - (float) Receivable::where('status', '!=', 'soldee')->sum('amount_paid'),
        ];
    }

    public function getSalesProperty()
    {
        return Sale::with(['customer', 'lines', 'receivable'])
            ->when($this->search, fn ($q) => $q->where(fn ($q2) => $q2->where('id', 'like', '%'.$this->search.'%')
                ->orWhereHas('customer', fn ($q3) => $q3->where('name', 'like', '%'.$this->search.'%'))))
            ->when($this->statusFilter === 'annulee', fn ($q) => $q->where('status', 'annulee'))
            ->when($this->statusFilter === 'payee', fn ($q) => $q->where('status', 'validee')->where('payment_mode', '!=', 'credit'))
            ->when($this->statusFilter === 'attente', fn ($q) => $q->where('status', 'validee')->where('payment_mode', 'credit'))
            ->when($this->modeFilter, fn ($q) => $q->where('payment_mode', $this->modeFilter))
            ->when($this->customerFilter, fn ($q) => $q->where('customer_id', $this->customerFilter))
            ->orderByEffectiveDate()
            ->limit(100)
            ->get();
    }

    public function getViewingSaleProperty(): ?Sale
    {
        return $this->viewingSaleId ? Sale::with(['customer', 'lines.product'])->find($this->viewingSaleId) : null;
    }

    public function view(string $id): void
    {
        $this->viewingSaleId = $id;
    }

    public function closeDrawer(): void
    {
        $this->viewingSaleId = null;
    }

    /**
     * 🔴→✅ TROUVÉ MANQUANT PAR VÉRIFICATION NIVEAU 2 : "Télécharger PDF"
     * dans le drawer de détail vente était totalement absent. Réutilise
     * `PdfExportService` — export PAR VENTE (ticket de caisse), pas un
     * export en masse.
     */
    public function exportSaleTicketPdf(string $saleId)
    {
        $this->authorize('export-ventes');

        $sale = \App\Models\Sale::with(['customer', 'lines.product'])->findOrFail($saleId);

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.sale-ticket',
            ['sale' => $sale],
            'Ticket de Vente',
            strtoupper(substr($sale->id, 0, 8))
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'vente-'.strtoupper(substr($sale->id, 0, 8)).'.pdf');
    }

    public function confirmCancel(string $id): void
    {
        $this->cancellingSaleId = $id;
        $this->dispatch('open-modal', name: 'modal-cancel-sale');
    }

    public function cancelSale(): void
    {
        $this->authorize('manage-ventes');
        $sale = Sale::with('lines')->findOrFail($this->cancellingSaleId);

        if ($sale->status === 'annulee') {
            return;
        }

        foreach ($sale->lines as $line) {
            $product = Product::find($line->product_id);
            if ($product) {
                app(AdjustStockAction::class)->execute($product, (float) $line->qty, 'sale', $sale->id);
            }
        }

        $sale->update(['status' => 'annulee']);

        AuditLog::record('sale.cancelled', 'ventes');
        $this->dispatch('close-modal', name: 'modal-cancel-sale');
        $this->dispatch('toast', message: 'Vente annulée — stock réintégré.', type: 'warning');
    }

    public function resetFilters(): void
    {
        $this->reset(['search', 'statusFilter', 'modeFilter', 'customerFilter']);
    }

    public function render()
    {
        return view('livewire.ventes.historique-ventes');
    }
}
