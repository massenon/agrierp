<?php

namespace App\Livewire\Ventes;

use App\Models\Customer;
use App\Models\Receivable;
use App\Models\Sale;
use App\Services\CustomerCatalogService;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 4.6 (Sprint 4) — liste-clients.html → Livewire\Ventes\ListeClients
 * "Répertoire des clients de la ferme et de leur situation commerciale."
 *
 * ⚠️ CORRIGÉ AU TICKET 4.7 : "Solde Dû" interrogeait initialement
 * `sales.payment_mode = credit` faute de table de créances dédiée.
 * `receivables` existe désormais — le solde interroge cette table réelle,
 * un seul point de vérité partagé avec `HistoriqueVentes` et
 * `RelancesClients`.
 *
 * "Statut" (Actif/Créance en retard/Inactif) dérivé : Créance en retard
 * si solde dû > 0, sinon Actif (aucune notion de dernière activité
 * "Inactif" n'est encore trackée — Sprint 8+, non inventée ici).
 */
class ListeClients extends Component
{
    #[Url]
    public string $search = '';

    #[Url]
    public string $statusFilter = '';

    #[Url]
    public string $cityFilter = '';

    public ?string $editingCustomerId = null;

    public string $name = '';

    public string $phone = '';

    public string $email = '';

    public string $city = '';

    /**
     * 🔴→✅ TROUVÉ TOTALEMENT ABSENT PAR VÉRIFICATION NIVEAU 2 (lecture
     * ligne par ligne) : la case à cocher "Tout sélectionner" et la barre
     * "Supprimer la sélection" du prototype n'existaient nulle part —
     * jamais un simple ajout visuel, mécanisme complet construit ici :
     * sélection réelle, action réelle. "Supprimer" = archivage logique
     * (`is_active = false`), JAMAIS un DELETE physique — même règle que
     * `archiveCustomer()` déjà en place, appliquée en masse plutôt
     * qu'inventée à part.
     */
    public array $selectedIds = [];

    public function toggleSelectAll(): void
    {
        $allIds = $this->customersWithBalance->pluck('customer.id')->toArray();

        $this->selectedIds = count($this->selectedIds) === count($allIds) ? [] : $allIds;
    }

    public function getKpisProperty(): array
    {
        $activeReceivables = Receivable::where('status', '!=', 'soldee')->get();

        return [
            'clients_actifs' => Customer::where('is_active', true)->count(),
            'nouveaux_mois' => Customer::where('is_active', true)->whereMonth('created_at', now()->month)->whereYear('created_at', now()->year)->count(),
            'solde_creances' => (float) $activeReceivables->sum('balance'),
        ];
    }

    public function getCustomersWithBalanceProperty()
    {
        $customers = Customer::where('is_active', true)
            ->when($this->search, fn ($q) => $q->where('name', 'like', '%'.$this->search.'%'))
            ->when($this->cityFilter, fn ($q) => $q->where('city', $this->cityFilter))
            ->orderBy('name')
            ->get();

        return $customers->map(function ($customer) {
            $sales = Sale::where('customer_id', $customer->id)->where('status', 'validee')->get();
            $solde = (float) Receivable::where('customer_id', $customer->id)->where('status', '!=', 'soldee')->get()->sum('balance');

            return [
                'customer' => $customer,
                'total_achats' => (float) $sales->sum('total'),
                'solde_du' => $solde,
                'statut' => $solde > 0 ? 'Créance en retard' : 'Actif',
            ];
        })->when($this->statusFilter, fn ($rows) => $rows->filter(fn ($r) => $r['statut'] === $this->statusFilter));
    }

    public function getCitiesProperty()
    {
        return Customer::where('is_active', true)->whereNotNull('city')->distinct()->pluck('city')->sort()->values();
    }

    public function newCustomer(): void
    {
        $this->reset(['editingCustomerId', 'name', 'phone', 'email', 'city']);
        $this->dispatch('open-modal', name: 'modal-create-client');
    }

    public function editCustomer(string $id): void
    {
        $customer = Customer::findOrFail($id);
        $this->editingCustomerId = $customer->id;
        $this->name = $customer->name;
        $this->phone = (string) $customer->phone;
        $this->email = (string) $customer->email;
        $this->city = (string) $customer->city;
        $this->dispatch('open-modal', name: 'modal-create-client');
    }

    public function saveCustomer(): void
    {
        // Ticket 15.18 : règles et écriture partagées avec `/sync/push` (le poste Flutter).
        $service = app(CustomerCatalogService::class);

        $this->validate(array_diff_key($service->regles(), ['is_active' => 1]));

        $valides = [
            'name' => $this->name,
            'phone' => $this->phone,
            'email' => $this->email,
            'city' => $this->city,
        ];

        if ($this->editingCustomerId) {
            $service->modifier(Customer::findOrFail($this->editingCustomerId), $valides);
            $message = 'Client modifié avec succès.';
        } else {
            $service->creer($valides);
            $message = 'Client créé avec succès.';
        }

        $this->dispatch('close-modal', name: 'modal-create-client');
        $this->dispatch('toast', message: $message, type: 'success');
    }

    public function archiveCustomer(string $id): void
    {
        app(CustomerCatalogService::class)->archiver(Customer::findOrFail($id));
        $this->dispatch('toast', message: 'Client archivé avec succès.', type: 'warning');
    }

    /**
     * Suppression en masse = archivage logique en masse, même règle que
     * `archiveCustomer()` — jamais un DELETE physique, même en masse.
     * Modale de confirmation affichant le NOMBRE réel de clients
     * concernés avant toute action (adaptation raisonnable de la règle
     * "modale nommant l'élément" pour une action multi-lignes — nommer
     * individuellement chacun des N clients sélectionnés serait
     * impraticable au-delà de quelques éléments).
     */
    public function bulkArchiveCustomers(): void
    {
        if (empty($this->selectedIds)) {
            return;
        }

        $count = app(CustomerCatalogService::class)->archiverPlusieurs($this->selectedIds);

        $this->selectedIds = [];
        $this->dispatch('close-modal', name: 'modal-bulk-archive-clients');
        $this->dispatch('toast', message: "{$count} client(s) archivé(s) avec succès.", type: 'warning');
    }

    public function openBulkArchiveModal(): void
    {
        if (empty($this->selectedIds)) {
            return;
        }

        $this->dispatch('open-modal', name: 'modal-bulk-archive-clients');
    }

    /**
     * 🔴→✅ TROUVÉ MANQUANT PAR VÉRIFICATION NIVEAU 2 : bouton "PDF"
     * totalement absent — même schéma déjà trouvé sur de nombreux
     * écrans de ce projet.
     */
    public function exportClientsPdf()
    {
        $this->authorize('export-ventes');

        $rows = $this->customersWithBalance;

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.liste-clients',
            ['rows' => $rows],
            'Liste des Clients',
            'État au '.now()->format('d/m/Y')
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'clients-'.now()->format('Y-m-d').'.pdf');
    }

    public function render()
    {
        return view('livewire.ventes.liste-clients');
    }
}
