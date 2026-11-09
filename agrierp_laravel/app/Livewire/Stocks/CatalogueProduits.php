<?php

namespace App\Livewire\Stocks;

use App\Models\Product;
use App\Models\ProductCategory;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 2.3 (Sprint 2) — catalogue-produits.html (+ enfant catalogue-view.html)
 * → Livewire\Stocks\CatalogueProduits
 *
 * ⚠️ VIGILANCE EXPLICITE DEMANDÉE PAR LE TICKET : "vérifier qu'aucun autre
 * écran ne recrée sa propre source de données produit" (piège déjà
 * rencontré sur ce projet — catalogue vs POS ayant dérivé indépendamment).
 * CE composant interroge directement `App\Models\Product` /
 * `App\Models\ProductCategory` (créés au ticket 2.2) — un seul point de
 * vérité. Tout écran futur listant des produits (POS Sprint 4, Gestion
 * Stocks Sprint 6...) DOIT réutiliser ces mêmes modèles, jamais une requête
 * ou une transformation de données dupliquée localement.
 *
 * ÉCART D'ARCHITECTURE DOCUMENTÉ : le prototype charge `catalogue-view.html`
 * et `seuils-alerte.html` dans deux <iframe> (mécanisme propre à un
 * prototype HTML statique multi-fichiers). Conformément à Document 02 §4
 * ("composition par imbrication de composants, jamais par iframe"), les
 * deux onglets deviennent des sections d'un seul composant Livewire,
 * commutées via `<x-tab-page>` (Sprint 0).
 *
 * PÉRIMÈTRE DE CE TICKET : seul l'onglet "Voir le Catalogue" est
 * fonctionnel. "Seuils d'Alerte" (édition des seuils par produit) est un
 * écran distinct (`seuils-alerte.html`, Sprint 6 — Stocks) : affiché en
 * bandeau d'attente, pas construit ici (un ticket = une session).
 *
 * Les boutons "Nouveau Produit" / "Modifier" renvoient vers les futures
 * routes du ticket 2.4 (`ajouter-produit.html` → formulaire plein-page).
 * Le prototype ouvrait une modale inline sur cette même page pour l'ajout
 * — remplacé par une navigation vers un écran dédié pour respecter le
 * découpage de tickets déjà acté (2.3 table/liste, 2.4 formulaire) plutôt
 * que dupliquer une partie du formulaire ici en avance sur son propre
 * ticket. "Archiver" reste dans le périmètre de CE ticket (action
 * autonome, cf. Document 01 FR-01 : toujours archivage logique).
 */
#[Layout('layouts.app')]
class CatalogueProduits extends Component
{
    #[Url]
    public string $tab = 'catalogue';

    #[Url]
    public string $search = '';

    #[Url]
    public string $category = '';

    public function getCategoriesProperty()
    {
        return ProductCategory::where('is_active', true)->orderBy('label')->get();
    }

    public function getProductsProperty()
    {
        return Product::with(['category', 'species'])
            ->where('is_active', true)
            ->when($this->search, fn ($q) => $q->where(fn ($q2) => $q2
                ->where('name', 'like', '%'.$this->search.'%')
                ->orWhere('sku', 'like', '%'.$this->search.'%')))
            ->when($this->category, fn ($q) => $q->whereHas('category', fn ($q2) => $q2->where('label', $this->category)))
            ->orderBy('name')
            ->get();
    }

    public function archive(string $id): void
    {
        $this->authorize('manage-stocks');

        // Ticket ST-1 — `ProductCatalogService::archiver`, partagé avec l'envoi du poste.
        $product = app(\App\Services\ProductCatalogService::class)->archiver(Product::findOrFail($id));

        $this->dispatch('toast', message: "{$product->name} archivé avec succès.", type: 'warning');
    }

    public function render()
    {
        return view('livewire.stocks.catalogue-produits', ['title' => 'Stocks & Produits > Catalogue Produits']);
    }
}
