<?php

namespace App\Livewire\Achats;

use App\Models\Purchase;
use App\Models\Supplier;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 5.6 (Sprint 5) — fiches-fournisseurs.html → Livewire\Achats\FichesFournisseurs
 * "Fiches détaillées des fournisseurs et historique des transactions."
 *
 * Vue analytique réelle sur `suppliers` (même table que
 * `AjouterFournisseur`, jamais une copie) : Total Achats (Année) et
 * Dernière Commande calculés en direct depuis `purchases`.
 *
 * `profile-fournisseur.html` consolidé ici en tiroir de détail plutôt
 * qu'une page routée séparée — même traitement que le tiroir déjà utilisé
 * pour `HistoriqueVentes` (ticket 4.4) et `ListeAchats` (ticket 5.4),
 * évite une troisième vue quasi identique du même fournisseur.
 *
 * Édition/archivage renvoient vers l'onglet "Ajouter Fournisseur" (source
 * canonique unique) plutôt que de dupliquer un second modal d'édition sur
 * la même table.
 */
class FichesFournisseurs extends Component
{
    #[Url]
    public string $search = '';

    #[Url]
    public string $statusFilter = '';

    public ?string $viewingSupplierId = null;

    public function getKpisProperty(): array
    {
        return [
            'fournisseurs_actifs' => Supplier::where('is_active', true)->count(),
            'volume_achat_mois' => (float) Purchase::whereMonth('purchase_date', now()->month)->whereYear('purchase_date', now()->year)->sum('total'),
        ];
    }

    public function getSuppliersProperty()
    {
        return Supplier::query()
            ->when($this->search, fn ($q) => $q->where('name', 'like', '%'.$this->search.'%'))
            ->when($this->statusFilter === 'Actif', fn ($q) => $q->where('is_active', true))
            ->when($this->statusFilter === 'Inactif', fn ($q) => $q->where('is_active', false))
            ->orderBy('name')
            ->get()
            ->map(function ($supplier) {
                $purchases = Purchase::where('supplier_id', $supplier->id)->whereYear('purchase_date', now()->year)->get();
                $lastPurchase = Purchase::where('supplier_id', $supplier->id)->orderByDesc('purchase_date')->first();

                $supplier->setAttribute('total_achats_annee', (float) $purchases->sum('total'));
                $supplier->setAttribute('derniere_commande', $lastPurchase?->purchase_date);

                return $supplier;
            });
    }

    /**
     * 🔴→✅ TROUVÉ MANQUANT PAR COMPARAISON STRUCTURELLE RIGOUREUSE : le
     * bouton "Exporter PDF" était totalement absent — même schéma déjà
     * trouvé sur de nombreux écrans de ce projet.
     */
    public function exportFournisseursPdf()
    {
        $this->authorize('view-achats');

        $suppliers = $this->suppliers;

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.fiches-fournisseurs',
            ['suppliers' => $suppliers],
            'Fiches Fournisseurs',
            'État au '.now()->format('d/m/Y')
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'fournisseurs-'.now()->format('Y-m-d').'.pdf');
    }

    public function getViewingSupplierProperty(): ?Supplier
    {
        return $this->viewingSupplierId ? Supplier::find($this->viewingSupplierId) : null;
    }

    public function getViewingPurchasesProperty()
    {
        if (! $this->viewingSupplierId) {
            return collect();
        }

        return Purchase::with('lines')->where('supplier_id', $this->viewingSupplierId)->orderByDesc('purchase_date')->limit(15)->get();
    }

    public function view(string $id): void
    {
        $this->viewingSupplierId = $id;
    }

    public function closeDrawer(): void
    {
        $this->viewingSupplierId = null;
    }

    public function render()
    {
        return view('livewire.achats.fiches-fournisseurs');
    }
}
