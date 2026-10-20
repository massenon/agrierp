<?php

namespace App\Livewire\Shared;

use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\Customer;
use App\Models\Employee;
use App\Models\LivestockLot;
use App\Models\LivestockReproductionEvent;
use App\Models\Product;
use App\Models\PurchaseOrder;
use App\Models\Receivable;
use App\Models\Sale;
use App\Models\Supplier;
use App\Models\VeterinaryRecord;
use Illuminate\Support\Facades\Auth;
use Livewire\Component;

/**
 * Implémentation réelle de MOTEUR_DE_RECHERCHE_GLOBALE_ERP.md — jusqu'ici
 * un `<input disabled>` purement statique dans le layout (commentaire déjà
 * en place, ticket explicitement différé au Sprint 0 : "hors périmètre
 * Sprint 0... non câblé pour l'instant"). Ce composant le câble pour de
 * vrai.
 *
 * Monté UNE SEULE FOIS dans `layouts.app` (Document 05 §Composant), jamais
 * dupliqué par page — même principe que `NotificationBell`.
 *
 * ⚠️ RBAC — filtrage EN AMONT, jamais après coup (§4 de la spécification,
 * correction actée : 4 rôles distincts, pas de fusion comptable/admin) :
 * chaque bloc de requête par domaine est gardé par `Auth::user()->can(...)`
 * AVANT toute requête Eloquent — un domaine auquel l'utilisateur n'a pas
 * accès n'est jamais interrogé, encore moins renvoyé puis filtré. La
 * recherche ne doit jamais devenir une voie de contournement du RBAC.
 *
 * ⚠️ Simplification honnête par rapport au tableau RBAC illustratif de la
 * spécification (§4) : celui-ci décrit une granularité par TYPE DE DONNÉE
 * (ex. caissier voit "stock disponible" mais pas "coût d'achat
 * fournisseur"), plus fine que les permissions Spatie réellement seedées
 * dans ce projet (`view-elevage`, `view-ventes`, `view-achats`,
 * `view-stocks`, `view-comptabilite`, `view-rh`...). Le §5 de la
 * spécification elle-même prescrit un filtrage BLOC PAR DOMAINE ("un
 * domaine entier n'est même pas requêté") — implémenté ici avec la
 * permission la plus proche de chaque domaine, complétée par une
 * vérification supplémentaire à l'intérieur du domaine 4 et 5 (qui
 * couvrent chacun deux permissions distinctes dans le vrai schéma RBAC)
 * plutôt que d'inventer des permissions qui n'existent pas.
 *
 * Recherche via `WHERE ... LIKE`, pas de moteur externe (Meilisearch/
 * Algolia) — volume d'une ferme unique, conforme à la recommandation
 * explicite de la spécification §5.
 */
class GlobalSearch extends Component
{
    public string $query = '';

    public bool $showResults = false;

    public function updatedQuery(): void
    {
        $this->showResults = strlen(trim($this->query)) >= 2;
    }

    public function close(): void
    {
        $this->showResults = false;
    }

    /** Élevage & Zootechnie — brand-emerald. */
    private function searchElevage(): array
    {
        if (! Auth::user()->can('view-elevage')) {
            return [];
        }

        $lots = LivestockLot::where('code', 'like', "%{$this->query}%")
            ->with('species')->limit(5)->get()
            ->map(fn ($l) => [
                'label' => $l->code,
                'sublabel' => ($l->species?->label ?? '').' — '.$l->current_quantity.' sujets',
                'url' => route('elevage.bandes'),
                'icon' => 'pets',
            ]);

        $events = LivestockReproductionEvent::where('mother_ref', 'like', "%{$this->query}%")
            ->orWhere('sire_ref', 'like', "%{$this->query}%")
            ->limit(5)->get()
            ->map(fn ($e) => [
                'label' => 'Reproduction — '.$e->mother_ref,
                'sublabel' => 'Statut : '.$e->status,
                'url' => route('elevage.suivi-reproduction').'?event='.$e->id,
                'icon' => 'pets',
            ]);

        return $lots->concat($events)->take(5)->all();
    }

    /** Santé & Pharmacie — info-blue. */
    private function searchSante(): array
    {
        if (! Auth::user()->can('view-elevage')) {
            return [];
        }

        // 🔴→✅ Ticket U3 — les deux critères sont GROUPÉS : `A OR B AND actif` se lisait `A OR (B AND actif)`, et un soin
        // archivé trouvé par son produit remontait dans la recherche. Soins actifs seulement, comme au poste.
        return VeterinaryRecord::where(fn ($q) => $q->where('product_used', 'like', "%{$this->query}%")
            ->orWhere('vet_name', 'like', "%{$this->query}%"))
            ->where('is_active', true)
            ->limit(5)->get()
            ->map(fn ($v) => [
                'label' => $v->product_used ?? $v->action_type,
                'sublabel' => $v->record_date?->format('d/m/Y').' — '.($v->vet_name ?? ''),
                'url' => route('elevage.soins-vaccins'),
                'icon' => 'medication',
            ])->all();
    }

    /** Commercial & Ventes — brand-maize. */
    private function searchCommercial(): array
    {
        if (! Auth::user()->can('view-ventes')) {
            return [];
        }

        $customers = Customer::where('name', 'like', "%{$this->query}%")
            ->orWhere('phone', 'like', "%{$this->query}%")
            ->where('is_active', true)
            ->limit(5)->get()
            ->map(fn ($c) => [
                'label' => $c->name,
                'sublabel' => $c->phone ?? '',
                'url' => route('ventes.creances-hub', ['tab' => 'liste']),
                'icon' => 'person',
            ]);

        $sales = Sale::whereHas('customer', fn ($q) => $q->where('name', 'like', "%{$this->query}%"))
            ->orWhere('mecef_qr_ref', 'like', "%{$this->query}%")
            ->with('customer')
            ->limit(5)->get()
            ->map(fn ($s) => [
                'label' => 'Vente — '.($s->customer?->name ?? 'Client comptant'),
                'sublabel' => number_format($s->total, 0, ',', ' ').' FCFA',
                'url' => route('ventes.devis-hub', ['tab' => 'historique']),
                'icon' => 'point_of_sale',
            ]);

        return $customers->concat($sales)->take(5)->all();
    }

    /** Achats & Stocks — nécessite view-stocks OU view-achats pour entrer dans le domaine. */
    private function searchAchatsStocks(): array
    {
        $user = Auth::user();
        if (! $user->can('view-stocks') && ! $user->can('view-achats')) {
            return [];
        }

        $results = collect();

        if ($user->can('view-stocks')) {
            $results = $results->concat(
                Product::where('name', 'like', "%{$this->query}%")
                    ->orWhere('sku', 'like', "%{$this->query}%")
                    ->where('is_active', true)
                    ->limit(5)->get()
                    ->map(fn ($p) => [
                        'label' => $p->name,
                        'sublabel' => 'Stock : '.$p->stock_qty.' '.$p->unit.($p->stock_qty <= $p->alert_threshold ? ' — Alerte Critique' : ''),
                        'url' => route('stocks.gestion'),
                        'icon' => 'inventory_2',
                        'critical' => $p->stock_qty <= $p->alert_threshold,
                    ])
            );
        }

        if ($user->can('view-achats')) {
            $results = $results->concat(
                Supplier::where('name', 'like', "%{$this->query}%")
                    ->where('is_active', true)
                    ->limit(3)->get()
                    ->map(fn ($s) => [
                        'label' => $s->name,
                        'sublabel' => $s->category ?? '',
                        'url' => route('achats.fournisseurs-hub'),
                        'icon' => 'local_shipping',
                    ])
            );

            $results = $results->concat(
                PurchaseOrder::whereHas('supplier', fn ($q) => $q->where('name', 'like', "%{$this->query}%"))
                    ->with('supplier')
                    ->limit(2)->get()
                    ->map(fn ($po) => [
                        'label' => 'Bon de commande — '.($po->supplier?->name ?? ''),
                        'sublabel' => 'Statut : '.$po->status,
                        'url' => route('achats.commandes-hub'),
                        'icon' => 'local_shipping',
                    ])
            );
        }

        return $results->take(5)->all();
    }

    /** Comptabilité & Admin — nécessite view-comptabilite OU view-rh pour entrer dans le domaine. */
    private function searchComptabiliteAdmin(): array
    {
        $user = Auth::user();
        if (! $user->can('view-comptabilite') && ! $user->can('view-rh')) {
            return [];
        }

        $results = collect();

        if ($user->can('view-comptabilite')) {
            $results = $results->concat(
                ChartOfAccount::where('code', 'like', "%{$this->query}%")
                    ->orWhere('label', 'like', "%{$this->query}%")
                    ->where('is_active', true)
                    // Ticket 15.27 : avec 1 300+ comptes, 3 résultats SANS ordre seraient arbitraires (« Caisse » doit donner 531 d'abord) : codes courts (plus généraux) d'abord.
                    ->orderByRaw('LENGTH(code), code')
                    ->limit(3)->get()
                    ->map(fn ($a) => [
                        'label' => $a->code.' — '.$a->label,
                        'sublabel' => 'Classe '.$a->class,
                        'url' => route('comptabilite.plan'),
                        'icon' => 'menu_book',
                    ])
            );

            $results = $results->concat(
                AccountingEntry::where('reference', 'like', "%{$this->query}%")
                    ->where('is_active', true)
                    ->limit(2)->get()
                    ->map(fn ($e) => [
                        'label' => $e->reference ?? 'Écriture',
                        'sublabel' => $e->entry_date->format('d/m/Y'),
                        'url' => route('comptabilite.journal'),
                        'icon' => 'account_balance',
                    ])
            );
        }

        if ($user->can('view-rh')) {
            $results = $results->concat(
                Employee::where('first_name', 'like', "%{$this->query}%")
                    ->orWhere('last_name', 'like', "%{$this->query}%")
                    ->where('is_active', true)
                    ->limit(3)->get()
                    ->map(fn ($e) => [
                        'label' => $e->last_name.' '.$e->first_name,
                        'sublabel' => $e->position ?? '',
                        'url' => route('rh.personnel-stages-hub'),
                        'icon' => 'badge',
                    ])
            );
        }

        return $results->take(5)->all();
    }

    public function getResultsProperty(): array
    {
        if (strlen(trim($this->query)) < 2) {
            return [];
        }

        $domains = [
            ['key' => 'elevage', 'label' => 'Élevage & Cheptel', 'icon' => 'pets', 'color' => 'emerald', 'items' => $this->searchElevage()],
            ['key' => 'sante', 'label' => 'Vétérinaire & Soins', 'icon' => 'medication', 'color' => 'blue', 'items' => $this->searchSante()],
            ['key' => 'commercial', 'label' => 'Commercial & Caisse', 'icon' => 'point_of_sale', 'color' => 'maize', 'items' => $this->searchCommercial()],
            ['key' => 'achats_stocks', 'label' => 'Achats & Stocks', 'icon' => 'inventory_2', 'color' => 'maize', 'items' => $this->searchAchatsStocks()],
            ['key' => 'comptabilite_admin', 'label' => 'Comptabilité & Admin', 'icon' => 'account_balance', 'color' => 'blue', 'items' => $this->searchComptabiliteAdmin()],
        ];

        return array_values(array_filter($domains, fn ($d) => count($d['items']) > 0));
    }

    public function render()
    {
        return view('livewire.shared.global-search');
    }
}
