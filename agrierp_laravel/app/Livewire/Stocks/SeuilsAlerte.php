<?php

namespace App\Livewire\Stocks;

use App\Models\AuditLog;
use App\Models\Product;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 6.2 (Sprint 6) — seuils-alerte.html → Livewire\Stocks\SeuilsAlerte
 * "Configuration des seuils critiques déclenchant les alertes de
 * réapprovisionnement."
 *
 * ⚠️ ÉCRAN STANDALONE, PAS UN ONGLET DU HUB : contrairement à ce que le
 * regroupement du ticket laisse penser, `gestion-stocks.html` (ticket
 * 6.2 principal) n'a que 3 onglets internes réels — Tableau &
 * Valorisation, Journal des Mouvements, Ajustement/Correction — aucun
 * onglet "Seuils". `seuils-alerte.html` est un fichier séparé, à sa
 * propre route, jamais fusionné artificiellement dans le hub pour
 * coller au regroupement du plan.
 *
 * Édite directement `products.alert_threshold` (champ déjà existant
 * depuis le ticket 2.4) — un seul point de vérité, jamais une copie de
 * cette valeur. "Statut" (Normal/Critique) dérivé de la comparaison
 * stock_qty vs alert_threshold, même règle que le badge "Urgence" de
 * `GestionStocks` (ticket 6.2 principal) — jamais une seconde règle
 * inventée pour la même donnée.
 */
#[Layout('layouts.app')]
class SeuilsAlerte extends Component
{
    #[Url]
    public string $search = '';

    #[Url]
    public string $statusFilter = '';

    public ?string $editingProductId = null;

    public ?int $threshold = null;

    public function getKpisProperty(): array
    {
        $products = Product::where('is_active', true)->get();

        return [
            'produits_sous_seuil' => $products->filter(fn ($p) => $p->alert_threshold > 0 && $p->stock_qty <= $p->alert_threshold)->count(),
            'seuils_configures' => $products->where('alert_threshold', '>', 0)->count(),
        ];
    }

    public function getProductsProperty()
    {
        return Product::where('is_active', true)
            ->when($this->search, fn ($q) => $q->where('name', 'like', '%'.$this->search.'%'))
            ->orderBy('name')
            ->get()
            ->map(function ($product) {
                $product->setAttribute('is_critique', $product->alert_threshold > 0 && $product->stock_qty <= $product->alert_threshold);

                return $product;
            })
            ->when($this->statusFilter === 'Critique', fn ($rows) => $rows->filter(fn ($p) => $p->is_critique))
            ->when($this->statusFilter === 'Normal', fn ($rows) => $rows->filter(fn ($p) => ! $p->is_critique));
    }

    public function editThreshold(string $id): void
    {
        $product = Product::findOrFail($id);
        $this->editingProductId = $product->id;
        $this->threshold = $product->alert_threshold;
        $this->dispatch('open-modal', name: 'modal-edit-seuil');
    }

    public function saveThreshold(): void
    {
        $this->authorize('manage-stocks');

        $this->validate(['threshold' => ['required', 'integer', 'min:0']]);

        Product::findOrFail($this->editingProductId)->update(['alert_threshold' => $this->threshold]);

        AuditLog::record('product.threshold_updated', 'stocks');
        $this->dispatch('close-modal', name: 'modal-edit-seuil');
        $this->dispatch('toast', message: 'Seuil configuré avec succès.', type: 'success');
    }

    public function render()
    {
        return view('livewire.stocks.seuils-alerte', ['title' => 'Stocks > Seuils d\'Alerte']);
    }
}
