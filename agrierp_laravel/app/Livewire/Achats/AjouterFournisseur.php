<?php

namespace App\Livewire\Achats;

use App\Models\Supplier;
use App\Services\SupplierCatalogService;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 5.6 (Sprint 5) — ajouter-fournisseur.html → Livewire\Achats\AjouterFournisseur
 * CRUD complet et canonique pour `suppliers` — un seul point de vérité
 * pour la création/modification, réutilisé par "Fiches Fournisseurs"
 * (même table, jamais une copie).
 */
class AjouterFournisseur extends Component
{
    #[Url]
    public string $search = '';

    #[Url]
    public string $statusFilter = '';

    public ?string $editingSupplierId = null;

    public string $name = '';

    public string $category = '';

    public string $phone = '';

    public string $address = '';

    public function getKpisProperty(): array
    {
        return [
            'fournisseurs_actifs' => Supplier::where('is_active', true)->count(),
            'nouveaux_mois' => Supplier::where('is_active', true)->whereMonth('created_at', now()->month)->whereYear('created_at', now()->year)->count(),
        ];
    }

    public function getSuppliersProperty()
    {
        return Supplier::query()
            ->when($this->search, fn ($q) => $q->where('name', 'like', '%'.$this->search.'%'))
            ->when($this->statusFilter === 'Actif', fn ($q) => $q->where('is_active', true))
            ->when($this->statusFilter === 'Inactif', fn ($q) => $q->where('is_active', false))
            ->orderBy('name')
            ->get();
    }

    public function newSupplier(): void
    {
        $this->reset(['editingSupplierId', 'name', 'category', 'phone', 'address']);
        $this->dispatch('open-modal', name: 'modal-create-fournisseur');
    }

    public function editSupplier(string $id): void
    {
        $supplier = Supplier::findOrFail($id);
        $this->editingSupplierId = $supplier->id;
        $this->name = $supplier->name;
        $this->category = (string) $supplier->category;
        $this->phone = (string) $supplier->phone;
        $this->address = (string) $supplier->address;
        $this->dispatch('open-modal', name: 'modal-create-fournisseur');
    }

    public function saveSupplier(): void
    {
        $this->authorize('manage-achats');

        // ⚠️ TICKET 15.17 — RÈGLES, PAYLOAD ET AUDIT VIVENT DANS
        // `SupplierCatalogService`, partagé avec `/sync/push` (le poste).
        $service = app(SupplierCatalogService::class);

        $this->validate(array_intersect_key($service->regles(), array_flip(['name', 'category', 'phone', 'address'])));

        $valeurs = [
            'name' => $this->name,
            'category' => $this->category,
            'phone' => $this->phone,
            'address' => $this->address,
        ];

        if ($this->editingSupplierId) {
            $service->modifier(Supplier::findOrFail($this->editingSupplierId), $valeurs);
            $message = 'Modification enregistrée avec succès.';
        } else {
            $service->creer($valeurs);
            $message = 'Enregistrement effectué avec succès.';
        }

        $this->dispatch('close-modal', name: 'modal-create-fournisseur');
        $this->dispatch('toast', message: $message, type: 'success');
    }

    public function archiveSupplier(string $id): void
    {
        $this->authorize('manage-achats');

        app(SupplierCatalogService::class)->archiver(Supplier::findOrFail($id));
        $this->dispatch('toast', message: 'Fournisseur archivé avec succès.', type: 'warning');
    }

    public function render()
    {
        return view('livewire.achats.ajouter-fournisseur');
    }
}
