<?php

namespace App\Livewire\Elevage;

use App\Actions\AdjustStockAction;
use App\Models\AuditLog;
use App\Models\LivestockLot;
use App\Models\Product;
use App\Models\Transformation;
use Illuminate\Support\Facades\Auth;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Ticket 3.12 (Sprint 3) — transformation.html → Livewire\Elevage\TransformationForm
 * "Convertit des sujets vivants en produits finis vendables au POS —
 * impact automatique sur le cheptel, le stock et la comptabilité."
 *
 * Impacts réellement appliqués :
 *   1. Élevage — Décrémentation : `livestock_lots.current_quantity` réduit
 *      du nombre de sujets abattus.
 *   2. Stock Produits Finis — Incrémentation : `products.stock_qty`
 *      augmenté de la quantité produite.
 *
 * ⚠️ ÉCRITURE COMPTABLE NON GÉNÉRÉE, SIGNALÉ EXPLICITEMENT : le prototype
 * annonce "Débit 313 Produits Transformés / Crédit 73 Variation de
 * Stocks", mais aucune table d'écritures (`journal_entries`/`journal_lines`,
 * Sprint 10) n'existe encore. `transformations.accounting_entry_id` reste
 * nullable sans contrainte FK (comme `livestock_lots.cost_center_id`,
 * ticket 3.1) — une migration `alter` l'ajoutera au Sprint 10, jamais une
 * écriture fictive générée en avance sur ses propres tables.
 *
 * La marge imputée au centre analytique (mention du prototype) dépend de
 * `cost_centers` (Sprint 10 également) — non implémentée pour la même
 * raison.
 */
#[Layout('layouts.app')]
class TransformationForm extends Component
{
    public string $lotId = '';

    public int $qtyAnimals = 1;

    public string $productId = '';

    public ?float $qtyProduced = null;

    public string $transformationDate = '';

    public function mount(): void
    {
        $this->transformationDate = now()->format('Y-m-d');
    }

    public function getLotsProperty()
    {
        return LivestockLot::with('species')
            ->where('status', 'actif')->where('is_active', true)
            ->where('current_quantity', '>', 0)
            ->get();
    }

    public function getSelectedLotProperty(): ?LivestockLot
    {
        return $this->lotId ? $this->lots->firstWhere('id', $this->lotId) : null;
    }

    public function getEligibleProductsProperty()
    {
        if (! $this->selectedLot) {
            return collect();
        }

        return Product::where('is_active', true)
            ->where(fn ($q) => $q->where('species_id', $this->selectedLot->species_id)->orWhereNull('species_id'))
            ->orderBy('name')
            ->get();
    }

    public function getKpisProperty(): array
    {
        $monthTransfos = Transformation::whereMonth('transformation_date', now()->month)->whereYear('transformation_date', now()->year);

        return [
            'transformations_mois' => (clone $monthTransfos)->count(),
            'sujets_transformes' => (int) (clone $monthTransfos)->sum('qty_animals'),
        ];
    }

    public function getHistoryProperty()
    {
        return Transformation::with(['lot', 'product'])->orderByDesc('transformation_date')->limit(20)->get();
    }

    public function updatedLotId(): void
    {
        $this->productId = '';
    }

    public function validateTransformation(): void
    {
        $this->authorize('manage-elevage');

        $this->validate([
            'lotId' => ['required', 'exists:livestock_lots,id'],
            'qtyAnimals' => ['required', 'integer', 'min:1'],
            'productId' => ['required', 'exists:products,id'],
            'qtyProduced' => ['required', 'numeric', 'min:0'],
            'transformationDate' => ['required', 'date'],
        ]);

        if ($this->selectedLot && $this->qtyAnimals > $this->selectedLot->current_quantity) {
            $this->addError('qtyAnimals', "La quantité ne peut pas dépasser l'effectif disponible du lot ({$this->selectedLot->current_quantity}).");

            return;
        }

        $lot = $this->selectedLot;
        $product = Product::findOrFail($this->productId);

        $transformation = Transformation::create([
            'lot_id' => $this->lotId,
            'product_id' => $this->productId,
            'qty_animals' => $this->qtyAnimals,
            'qty_produced' => $this->qtyProduced,
            'operator_id' => Auth::id(),
            'transformation_date' => $this->transformationDate,
        ]);

        // 1. Élevage — Décrémentation
        $lot->decrement('current_quantity', $this->qtyAnimals);

        // 2. Stock Produits Finis — Incrémentation
        app(AdjustStockAction::class)->execute($product, (float) $this->qtyProduced, 'transformation', $transformation->id);

        AuditLog::record('transformation.recorded', 'elevage');
        $this->dispatch('toast', message: "Transformation validée — {$this->qtyAnimals} sujet(s) transformé(s) en {$product->name}.", type: 'success');
        $this->reset(['lotId', 'qtyAnimals', 'productId', 'qtyProduced']);
        $this->qtyAnimals = 1;
        $this->transformationDate = now()->format('Y-m-d');

        // 🔴→✅ TICKET 14.3 — `selectedLot` (dérivé de `$this->lotId`) a été lu
        // plus haut pour le contrôle d'effectif disponible, donc mémoïsé.
        // `lotId` venant d'être réinitialisé, le rendu réaffichait la bande
        // source de la transformation déjà validée, avec son effectif
        // d'AVANT décrémentation — trompeur juste après l'opération.
        unset($this->selectedLot);
    }

    public function render()
    {
        return view('livewire.elevage.transformation-form', ['title' => 'Élevage > Transformation']);
    }
}
