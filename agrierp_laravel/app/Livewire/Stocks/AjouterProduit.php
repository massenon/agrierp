<?php

namespace App\Livewire\Stocks;

use App\Models\LivestockSpecies;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Services\ProductCatalogService;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Ticket 2.4 (Sprint 2) — ajouter-produit.html → formulaire, Mode de
 * Tarification restreint à Fourchette/Sur Devis uniquement.
 *
 * ⚠️ RÉCONCILIATION DOCUMENTÉE (constat avant codage, Document 00 §2.2) :
 * `ajouter-produit.html`, tel quel dans le prototype, est un gabarit CRUD
 * générique (identique dans sa structure à d'autres écrans "Nom/Catégorie/
 * Prix unitaire/Description") qui ne comporte AUCUNE logique de mode de
 * tarification — un simple champ "Prix unitaire (FCFA)" unique. Ceci
 * contredit directement (a) l'instruction explicite du ticket 2.4
 * lui-même ("Mode de Tarification restreint à Fourchette/Sur Devis
 * uniquement") et (b) la modale "Nouveau Produit" de `catalogue-view.html`
 * (déjà lue au ticket 2.3), qui elle expose correctement Fourchette/Sur
 * devis + Prix Min/Max. Les deux instances du même formulaire dans le
 * prototype sont donc mutuellement incohérentes — celle de
 * `catalogue-view.html` est correcte et alignée sur le schéma réel
 * (`products.pricing_mode`), celle-ci ne l'est pas. Implémenté selon la
 * règle métier explicite (Document 00 §5.3) et la modale correcte, jamais
 * un champ "Prix unitaire" simple ni "prix au kg" (même la donnée de démo
 * "Lapin vivant (kg)" de ce fichier contredit cette règle — non reproduite).
 *
 * ⚠️ NON-DUPLICATION DE LA LISTE PRODUITS (piège déjà rencontré, signalé
 * au ticket 2.3) : `ajouter-produit.html` intègre aussi son propre tableau
 * de produits existants (KPI + recherche + colonnes Produit/Catégorie/
 * Prix/Statut). Reconstruire une DEUXIÈME liste de produits ici — en plus
 * de celle déjà livrée au ticket 2.3 (`CatalogueProduits`) — recréerait
 * précisément le piège que le ticket 2.3 demandait d'éviter (deux écrans,
 * deux sources dérivées indépendamment). Ce composant se limite donc au
 * FORMULAIRE (création et édition, conforme à son propre nom de ticket
 * "formulaire") ; la liste/le KPI restent uniquement sur l'écran Catalogue.
 *
 * `unit` reste un champ libre de comptage ("u", "sac", "plateau"...) —
 * jamais une unité de poids (Document 00 §5.3 : "toujours une unité de
 * pièce/comptage", cf. docblock de la migration `products`).
 */
#[Layout('layouts.app')]
class AjouterProduit extends Component
{
    public ?string $productId = null;

    public string $name = '';

    public string $description = '';

    public string $category_id = '';

    public string $species_id = '';

    public string $unit = 'u';

    public string $pricing_mode = 'fourchette';

    public ?float $price_min = null;

    public ?float $price_max = null;

    public float $tva_rate = 0;

    public float $stock_qty = 0;

    public float $alert_threshold = 0;

    public function mount(?string $product = null): void
    {
        if ($product) {
            $existing = Product::findOrFail($product);
            $this->productId = $existing->id;
            $this->name = $existing->name;
            $this->description = (string) $existing->description;
            $this->category_id = $existing->category_id;
            $this->species_id = (string) $existing->species_id;
            $this->unit = $existing->unit;
            $this->pricing_mode = $existing->pricing_mode;
            $this->price_min = $existing->price_min;
            $this->price_max = $existing->price_max;
            $this->tva_rate = (float) $existing->tva_rate;
            $this->stock_qty = (float) $existing->stock_qty;
            $this->alert_threshold = (float) $existing->alert_threshold;
        }
    }

    public function getCategoriesProperty()
    {
        return ProductCategory::where('is_active', true)->orderBy('label')->get();
    }

    public function getSpeciesOptionsProperty()
    {
        return LivestockSpecies::enabled()->orderBy('label')->get();
    }

    public function save(): void
    {
        $this->authorize('manage-stocks');

        // ⚠️ TICKET 15.15 — RÈGLES, PAYLOAD ET AUDIT VIVENT DANS
        // `ProductCatalogService`, partagé avec l'API du poste : un produit ne doit
        // pas passer d'un côté et être refusé de l'autre.
        $service = app(ProductCatalogService::class);

        $this->validate($service->regles($this->pricing_mode, true), $service->messages());

        $valeurs = [
            'name' => $this->name,
            'description' => $this->description,
            'category_id' => $this->category_id,
            'species_id' => $this->species_id,
            'unit' => $this->unit,
            'pricing_mode' => $this->pricing_mode,
            'price_min' => $this->price_min,
            'price_max' => $this->price_max,
            'tva_rate' => $this->tva_rate,
            'stock_qty' => $this->stock_qty,
            'alert_threshold' => $this->alert_threshold,
        ];

        if ($this->productId) {
            // ⚠️ La page web laisse modifier la quantité en édition (comportement
            // d'origine, conservé) ; l'API du poste, elle, ne le permet pas.
            $service->modifier(Product::findOrFail($this->productId), $valeurs, true);
            $message = 'Produit modifié avec succès.';
        } else {
            $service->creer($valeurs);
            $message = 'Produit créé avec succès.';
        }

        session()->flash('toast', ['message' => $message, 'type' => 'success']);
        $this->redirect('/catalogue-produits', navigate: false);
    }

    public function render()
    {
        return view('livewire.stocks.ajouter-produit', [
            'title' => 'Stocks & Produits > '.($this->productId ? 'Modifier le Produit' : 'Ajouter un Produit'),
        ]);
    }
}
