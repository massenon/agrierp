<?php

namespace App\Livewire\Achats;

use App\Exceptions\ClosedFiscalYearException;
use App\Exceptions\NoOpenFiscalYearException;
use App\Models\Payable;
use App\Models\Purchase;
use App\Models\PurchaseReturn;
use App\Models\Supplier;
use App\Models\TreasuryAccount;
use App\Services\PurchaseReturnService;
use App\Services\SupplierRefundService;
use App\Support\ExerciceChoisi;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Validation\ValidationException;
use Livewire\Component;
use Livewire\WithPagination;

/**
 * Ticket 5.4 (Sprint 5) — liste-achats.html → Livewire\Achats\ListeAchats
 * "Grand livre d'achats et d'approvisionnements de marchandises."
 *
 * "Statut" (Payé entièrement / Dette fournisseur) dérivé de la présence
 * d'une `Payable` non soldée — même principe que `HistoriqueVentes`
 * (ticket 4.4/4.7), un seul point de vérité partagé.
 *
 * ⚠️ "RETOUR FOURNISSEUR" = ANNULATION COMPLÈTE DE L'ACHAT, fidèle au
 * texte réel de la modale du prototype ("vous êtes sur le point
 * d'annuler l'achat [réf]... décrémentera automatiquement les stocks") —
 * PAS un retour partiel d'une seule ligne (D6).
 *
 * 🔴→✅ TICKET 15.20 — LE RETOUR ET LE REMBOURSEMENT PASSENT PAR DEUX SERVICES, partagés avec
 * `/api/sync/push` (`PurchaseReturnService`, `SupplierRefundService`). Avant : le retour ne
 * touchait ni la dette, ni le journal, et pouvait être rejoué (double décrément, stock négatif) ;
 * le remboursement créditait la trésorerie SANS écriture ni fournisseur (les deux livres
 * divergeaient). Désormais : le retour contre-passe l'écriture d'achat, annule la part non payée
 * de la dette, fait de la part déjà payée une créance sur le fournisseur (409), refuse un second
 * retour et un stock qui deviendrait négatif ; le remboursement est plafonné à cette créance et
 * entre en trésorerie AVEC son écriture. Toute action exige `manage-achats` (D11).
 *
 * 🔴→✅ TROUVÉ PAR COMPARAISON STRUCTURELLE RIGOUREUSE : le bouton
 * "Exporter PDF" était totalement absent — construit réellement
 * (`exportAchatsPdf()`, réutilise `PdfExportService`). "Importer" du
 * prototype reste volontairement non ajouté (même raisonnement que
 * `GestionStocks`/`Devis`).
 */
class ListeAchats extends Component
{
    use WithPagination;

    use \App\Livewire\Concerns\BornesCalendrierExercice;

    public string $search = '';

    public string $statusFilter = '';

    public string $dateFilter = '';

    public ?string $viewingPurchaseId = null;

    public ?string $returningPurchaseId = null;

    public string $returnReason = '';

    public string $refundSupplierId = '';

    public ?float $refundAmount = null;

    public string $refundDate = '';

    public string $refundTreasuryAccountId = '';

    public function mount(): void
    {
        $this->refundDate = now()->format('Y-m-d');
        $this->refundTreasuryAccountId = (string) (TreasuryAccount::where('is_active', true)->first()?->id ?? '');
    }

    public function getKpisProperty(): array
    {
        $purchases = Purchase::all();
        $payables = Payable::where('status', '!=', 'soldee')->get();

        return [
            'depenses_totales' => (float) $purchases->sum('total'),
            'achats_regles' => Purchase::whereDoesntHave('payable', fn ($q) => $q->where('status', '!=', 'soldee'))->count(),
            'dettes_en_cours' => (float) $payables->sum('balance'),
            'ecarts_retours' => PurchaseReturn::count(),
        ];
    }

    /**
     * Ticket EX7 (EF9) — les achats de l'exercice AFFICHÉ (filtres compris), sans plafond : la source de la liste
     * paginée ET de l'export PDF (jamais la seule page affichée).
     */
    public function achatsDeLExercice()
    {
        [$debut, $fin] = ExerciceChoisi::bornes();

        return Purchase::with(['supplier', 'lines.product.category', 'payable'])
            ->whereDate('purchase_date', '>=', $debut)
            ->whereDate('purchase_date', '<=', $fin)
            ->when($this->search, fn ($q) => $q->where(fn ($q2) => $q2->where('id', 'like', '%'.$this->search.'%')
                ->orWhereHas('supplier', fn ($q3) => $q3->where('name', 'like', '%'.$this->search.'%'))))
            ->when($this->dateFilter, fn ($q) => $q->whereDate('purchase_date', $this->dateFilter))
            ->orderByDesc('purchase_date')
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->get()
            ->map(function ($purchase) {
                $solde = $purchase->payable && $purchase->payable->status !== 'soldee' ? $purchase->payable->balance : 0;
                $purchase->setAttribute('is_dette', $solde > 0);
                $purchase->setAttribute('categorie', $purchase->lines->first()?->product?->category?->label ?? '—');

                return $purchase;
            })
            ->when($this->statusFilter === 'paye', fn ($rows) => $rows->where('is_dette', false))
            ->when($this->statusFilter === 'dette', fn ($rows) => $rows->where('is_dette', true))
            ->values();
    }

    /**
     * Ticket EX7 (EF9) — la page affichée (25 achats). Le statut « payé / dette » se lit sur la dette liée après la
     * requête : la page se découpe donc dans la liste filtrée, jamais avant le filtre.
     */
    public function getPurchasesProperty(): LengthAwarePaginator
    {
        $tous = $this->achatsDeLExercice();
        $page = max(1, min((int) $this->getPage('pageAchats'), (int) ceil(max(1, $tous->count()) / ExerciceChoisi::PAR_PAGE)));

        return new LengthAwarePaginator($tous->forPage($page, ExerciceChoisi::PAR_PAGE)->values(), $tous->count(), ExerciceChoisi::PAR_PAGE, $page, ['pageName' => 'pageAchats']);
    }

    /** Un filtre change : retour à la première page ; la date filtrée reste dans l'exercice affiché. */
    public function updating(string $propriete): void
    {
        if (in_array($propriete, ['search', 'statusFilter', 'dateFilter'], true)) {
            $this->resetPage('pageAchats');
        }
    }

    public function updatedDateFilter(): void
    {
        if ($this->dateFilter !== '') {
            $this->dateFilter = ExerciceChoisi::borner($this->dateFilter);
        }
    }

    /**
     * 🔴→✅ TROUVÉ MANQUANT PAR COMPARAISON STRUCTURELLE RIGOUREUSE : le
     * bouton "Exporter PDF" était totalement absent, alors que le
     * prototype le montre entre le filtre de date et "Ajouter
     * Remboursement". Réutilise `PdfExportService` (même pattern que
     * `Devis::exportDevisPdf()`) — pas de permission `export-achats`
     * dédiée dans le seeder (module Achats n'a que `view-achats`/
     * `manage-achats`), `view-achats` réutilisée plutôt qu'une
     * permission inventée.
     */
    public function exportAchatsPdf()
    {
        $this->authorize('view-achats');

        $purchases = $this->achatsDeLExercice();

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.liste-achats',
            ['purchases' => $purchases],
            "Liste d'Achats",
            'État au '.now()->format('d/m/Y')
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'achats-'.now()->format('Y-m-d').'.pdf');
    }

    public function getViewingPurchaseProperty(): ?Purchase
    {
        return $this->viewingPurchaseId ? Purchase::with(['supplier', 'lines.product', 'payable'])->find($this->viewingPurchaseId) : null;
    }

    public function getSuppliersProperty()
    {
        return Supplier::where('is_active', true)->orderBy('name')->get();
    }

    public function getTreasuryAccountsProperty()
    {
        return TreasuryAccount::where('is_active', true)->orderBy('label')->get();
    }

    public function view(string $id): void
    {
        $this->viewingPurchaseId = $id;
    }

    public function closeDrawer(): void
    {
        $this->viewingPurchaseId = null;
    }

    public function openReturnModal(string $id): void
    {
        $this->authorize('manage-achats');

        $this->returningPurchaseId = $id;
        $this->returnReason = '';
        $this->dispatch('open-modal', name: 'modal-return-purchase');
    }

    public function confirmReturnPurchase(): void
    {
        $this->authorize('manage-achats');

        $this->validate(['returnReason' => ['required', 'string']]);

        try {
            app(PurchaseReturnService::class)->annuler($this->returningPurchaseId, $this->returnReason);
        } catch (ValidationException $e) {
            // Refus métier (déjà retourné, stock insuffisant, achat sans écriture…) : le motif est affiché, rien n'a bougé.
            $this->addError('returnReason', collect($e->errors())->flatten()->implode(' '));

            return;
        } catch (NoOpenFiscalYearException|ClosedFiscalYearException $e) {
            $this->addError('returnReason', $e->getMessage());

            return;
        }

        $this->dispatch('close-modal', name: 'modal-return-purchase');
        $this->dispatch('toast', message: 'Retour fournisseur enregistré — stocks décrémentés, écriture contre-passée.', type: 'warning');
    }

    public function openRefundModal(): void
    {
        $this->authorize('manage-achats');

        $this->reset(['refundSupplierId', 'refundAmount']);
        $this->refundDate = now()->format('Y-m-d');
        $this->dispatch('open-modal', name: 'modal-ajouter-remboursement');
    }

    public function submitRefund(): void
    {
        $this->authorize('manage-achats');

        $this->validate([
            'refundSupplierId' => ['required', 'exists:suppliers,id'],
            'refundAmount' => ['required', 'numeric', 'min:1'],
            'refundDate' => ['required', 'date'],
            'refundTreasuryAccountId' => ['required', 'exists:treasury_accounts,id'],
        ]);

        try {
            $encaisse = app(SupplierRefundService::class)->rembourser(
                $this->refundSupplierId,
                (float) $this->refundAmount,
                $this->refundTreasuryAccountId,
                $this->refundDate,
            );
        } catch (ValidationException $e) {
            $this->addError('refundAmount', collect($e->errors())->flatten()->implode(' '));

            return;
        } catch (NoOpenFiscalYearException|ClosedFiscalYearException $e) {
            $this->addError('refundAmount', $e->getMessage());

            return;
        }

        $this->dispatch('close-modal', name: 'modal-ajouter-remboursement');

        $plafonne = $encaisse + 0.005 < (float) $this->refundAmount;
        $this->dispatch(
            'toast',
            message: $plafonne
                ? 'Remboursement plafonné à la créance ouverte : '.number_format($encaisse, 0, ',', ' ').' FCFA enregistrés.'
                : 'Remboursement enregistré avec succès.',
            type: $plafonne ? 'warning' : 'success',
        );
    }

    public function render()
    {
        return view('livewire.achats.liste-achats');
    }
}
