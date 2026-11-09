<?php

namespace App\Livewire\Achats;

use App\Actions\SaisieBonCommandeAction;
use App\Exceptions\AchatNonComptabilisableException;
use App\Exceptions\ClosedFiscalYearException;
use App\Exceptions\NoOpenFiscalYearException;
use App\Models\AuditLog;
use App\Models\Product;
use App\Models\Purchase;
use App\Models\PurchaseOrder;
use App\Models\PurchaseOrderLine;
use App\Models\Supplier;
use App\Services\PdfExportService;
use App\Services\ReceptionBonCommandeService;
use Illuminate\Support\Facades\DB;
use Livewire\Component;

/**
 * Ticket 5.5 (Sprint 5) — bons-commande.html → Livewire\Achats\BonsCommande
 * "Planification des approvisionnements de la ferme."
 *
 * PDF OFFICIEL RÉEL — premier usage effectif de `PdfExportService`
 * (existant depuis le Sprint 0 mais jamais câblé jusqu'ici) : en-tête
 * institutionnel exact, orientation portrait (nouveau paramètre ajouté à
 * ce service ce ticket, rétrocompatible).
 *
 * ⚠️ "VALIDER LA RÉCEPTION" — lecture attentive du texte réel de la
 * modale du prototype : "générera automatiquement une facture d'achat
 * formelle et incrémentera vos stocks". Implémenté fidèlement :
 *   1. `PurchaseOrder.status` → 'recu'.
 *   2. Une vraie `Purchase` créée (`purchase_order_id` renseigné), une
 *      `PurchaseLine` par ligne du bon (prix estimé devenant le prix
 *      réel — aucun autre prix n'est capturé à la réception).
 *   3. `products.stock_qty` incrémenté pour chaque ligne.
 *   4. Aucun règlement n'est capturé dans cette modale (contrairement à
 *      `EnregistrerAchat`, ticket 5.2) — la facture générée est donc
 *      traitée comme intégralement due : `payment_mode = credit` et une
 *      `Payable` réelle créée pour le montant total, cohérent avec
 *      l'absence de tout champ de paiement dans le prototype à cette
 *      étape.
 *   5. TICKET 15.21 — points 2 à 4 sont désormais exécutés par
 *      `RecordPurchaseAction` (celle de l'achat direct), qui AJOUTE l'écriture
 *      (Débit 601 + 445 / Crédit 401) : jusque-là la réception ne comptabilisait
 *      rien. Les achats déjà reçus avant ce ticket ne sont PAS régularisés
 *      (décision cabinet) : voir `comptabilite:achats-sans-ecriture`.
 */
class BonsCommande extends Component
{
    public string $supplierId = '';

    public string $expectedDeliveryDate = '';

    public array $cart = [];

    public string $lineProductId = '';

    public int $lineQty = 1;

    public ?float $linePrice = null;

    public ?string $receivingOrderId = null;

    public function getSuppliersProperty()
    {
        return Supplier::where('is_active', true)->orderBy('name')->get();
    }

    public function getProductsProperty()
    {
        return Product::where('is_active', true)->orderBy('name')->get();
    }

    public function getTotalProperty(): float
    {
        return collect($this->cart)->sum(fn ($l) => $l['qty'] * $l['unit_price']);
    }

    public function getOrdersProperty()
    {
        return PurchaseOrder::with(['supplier', 'lines'])->orderByDesc('created_at')->get();
    }

    public function updatedLineProductId(): void
    {
        $product = Product::find($this->lineProductId);
        $this->linePrice = $product ? (float) ($product->price_min ?? 0) : null;
    }

    public function addLine(): void
    {
        $this->validate([
            'lineProductId' => ['required', 'exists:products,id'],
            'lineQty' => ['required', 'integer', 'min:1'],
            'linePrice' => ['required', 'numeric', 'min:0'],
        ]);

        $product = Product::findOrFail($this->lineProductId);

        $this->cart[] = [
            'product_id' => $product->id,
            'name' => $product->name,
            'unit' => $product->unit,
            'qty' => $this->lineQty,
            'unit_price' => $this->linePrice,
        ];

        $this->reset(['lineProductId', 'linePrice']);
        $this->lineQty = 1;
    }

    public function removeLine(int $index): void
    {
        unset($this->cart[$index]);
        $this->cart = array_values($this->cart);
    }

    public function generateBc(): void
    {
        $this->authorize('manage-achats');

        if (empty($this->cart)) {
            $this->dispatch('toast', message: "Ajoutez au moins un article au bon de commande.", type: 'error');

            return;
        }

        $this->validate([
            'supplierId' => ['required', 'exists:suppliers,id'],
            'expectedDeliveryDate' => ['nullable', 'date'],
        ]);

        // Ticket AC-1 — `SaisieBonCommandeAction`, partagée avec le push du poste.
        app(SaisieBonCommandeAction::class)->execute(
            $this->supplierId,
            $this->expectedDeliveryDate ?: null,
            array_map(fn ($l) => [
                'product_id' => $l['product_id'],
                'qty' => $l['qty'],
                'estimated_unit_price' => $l['unit_price'],
            ], $this->cart),
        );

        $this->dispatch('toast', message: 'Bon de commande généré avec succès.', type: 'success');
        $this->reset(['cart', 'supplierId', 'expectedDeliveryDate']);
    }

    public function openReceiveModal(string $id): void
    {
        $this->receivingOrderId = $id;
        $this->dispatch('open-modal', name: 'modal-receive-order');
    }

    public function confirmReceiveOrder(): void
    {
        $this->authorize('manage-achats');

        // ⚠️ TICKET 15.21 — LA RÉCEPTION PASSE PAR `RecordPurchaseAction`, comme l'achat direct (14.24 / 14.78).
        // Avant, cette méthode créait elle-même l'achat, ses lignes, le stock et la dette SANS AUCUNE écriture :
        // dette sans contrepartie en 401, charge 601 jamais constatée (règle n°1 du projet violée). Une seule
        // comptabilisation des achats : l'écriture est datée du jour de la RÉCEPTION (`purchase_date` = aujourd'hui),
        // et tout (achat, lignes, stock, dette, écriture, statut du bon) tient dans UNE transaction — un exercice
        // clos/absent ou un compte manquant annule l'ensemble, sans résidu.
        // Ticket AC-1 — `ReceptionBonCommandeService`, partagé avec le push des achats du poste : une seule réception.
        try {
            $recu = app(ReceptionBonCommandeService::class)->recevoir($this->receivingOrderId) !== null;
        } catch (NoOpenFiscalYearException|ClosedFiscalYearException|AchatNonComptabilisableException $e) {
            $this->dispatch('toast', message: 'Réception refusée : '.$e->getMessage(), type: 'error');

            return;
        }

        if (! $recu) {
            $this->dispatch('close-modal', name: 'modal-receive-order');

            return;
        }

        $this->dispatch('close-modal', name: 'modal-receive-order');
        $this->dispatch('toast', message: "Réception validée — facture d'achat générée, stocks mis à jour.", type: 'success');
    }

    public function exportPdf(string $id)
    {
        $order = PurchaseOrder::with(['supplier', 'lines.product'])->findOrFail($id);
        $total = $order->lines->sum(fn ($l) => $l->qty * $l->estimated_unit_price);
        $statusLabels = ['brouillon' => 'Brouillon', 'envoye' => 'Envoyé / En cours', 'recu' => 'Reçu / Validé', 'annule' => 'Annulé'];

        AuditLog::record('purchase_order.pdf_exported', 'achats');

        $pdf = app(PdfExportService::class)->render(
            view: 'exports.bon-commande',
            data: ['purchaseOrder' => $order, 'total' => $total, 'statusLabel' => $statusLabels[$order->status] ?? $order->status],
            title: 'Bon de Commande — '.strtoupper(substr($order->id, 0, 8)),
            period: $order->created_at->format('d/m/Y'),
            orientation: 'portrait',
        );

        return response()->streamDownload(
            fn () => print($pdf->output()),
            'bon-commande-'.strtoupper(substr($order->id, 0, 8)).'.pdf'
        );
    }

    public function render()
    {
        return view('livewire.achats.bons-commande');
    }
}
