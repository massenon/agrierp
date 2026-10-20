<?php

namespace App\Services;

use App\Actions\AdjustStockAction;
use App\Models\AuditLog;
use App\Models\Product;
use App\Models\ProductCategory;
use Illuminate\Support\Facades\DB;

/**
 * Ticket 15.15 — CRÉATION ET MODIFICATION D'UN PRODUIT : UNE SEULE FABRIQUE.
 *
 * Extrait de `Livewire\Stocks\AjouterProduit` (ticket 2.4) pour que la page web ET
 * `POST|PUT /api/products` (le poste Flutter) appliquent les MÊMES règles :
 * fourchette ⇒ les deux prix et `price_max ≥ price_min`, sur devis ⇒ aucun prix
 * (Document 03 §3.6), SKU engendré par catégorie, trace d'audit. Deux validations
 * qui divergent laisseraient un produit passer d'un côté et pas de l'autre.
 *
 * ⚠️ LA QUANTITÉ EN STOCK N'EST ÉCRITE QU'À LA CRÉATION (ticket S-T12 : par un mouvement « Stock initial »). La page web laisse aussi
 * modifier `stock_qty` en édition — ce qui change un solde SANS journaliser de
 * mouvement ni passer par l'action d'ajustement. L'API ne le permet pas : un
 * poste corrige un stock par un AJUSTEMENT, que le serveur rejoue en recalculant
 * depuis l'état réel (règle « jamais appliqué tel quel »). La page web, elle, est
 * inchangée — signalé au ticket, non tranché ici.
 */
class ProductCatalogService
{
    /**
     * @return array<string, array<int, string>>
     */
    public function regles(string $pricingMode, bool $avecStock): array
    {
        $regles = [
            'name' => ['required', 'string', 'max:150'],
            'description' => ['nullable', 'string', 'max:2000'],
            'category_id' => ['required', 'exists:product_categories,id'],
            'species_id' => ['nullable'],
            'unit' => ['required', 'string', 'max:20'],
            'pricing_mode' => ['required', 'in:fourchette,quote'],
            'tva_rate' => ['required', 'numeric', 'min:0', 'max:100'],
            'alert_threshold' => ['required', 'numeric', 'min:0'],
        ];

        if ($avecStock) {
            $regles['stock_qty'] = ['required', 'numeric', 'min:0'];
        }

        // Document 03 §3.6 : fourchette ⇒ les deux prix, max ≥ min ; quote ⇒ aucun.
        if ($pricingMode === 'fourchette') {
            $regles['price_min'] = ['required', 'numeric', 'min:0'];
            $regles['price_max'] = ['required', 'numeric', 'min:0', 'gte:price_min'];
        }

        return $regles;
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'price_max.gte' => 'Le prix maximum doit être supérieur ou égal au prix minimum.',
        ];
    }

    /**
     * @param  array<string, mixed>  $v  données validées
     * @return array<string, mixed>
     */
    public function payload(array $v, bool $avecStock): array
    {
        $fourchette = ($v['pricing_mode'] ?? null) === 'fourchette';

        $payload = [
            'name' => $v['name'],
            'description' => ($v['description'] ?? null) ?: null,
            'category_id' => $v['category_id'],
            'species_id' => ($v['species_id'] ?? null) ?: null,
            'unit' => $v['unit'],
            'pricing_mode' => $v['pricing_mode'],
            'price_min' => $fourchette ? ($v['price_min'] ?? null) : null,
            'price_max' => $fourchette ? ($v['price_max'] ?? null) : null,
            'tva_rate' => $v['tva_rate'],
            'alert_threshold' => $v['alert_threshold'],
        ];

        if ($avecStock) {
            $payload['stock_qty'] = $v['stock_qty'];
        }

        return $payload;
    }

    /**
     * @param  array<string, mixed>  $v
     * @param  string|null  $id  UUID généré par le poste : conservé tel quel
     */
    public function creer(array $v, ?string $id = null): Product
    {
        $categorie = ProductCategory::find($v['category_id'])?->label ?? 'PRD';

        $payload = $this->payload($v, true);
        $payload['sku'] = Product::generateSku($categorie);
        $payload['is_active'] = true;

        // 🔴→✅ TICKET S-T12 (trouvé par l'essai à plusieurs postes) — LE STOCK INITIAL PASSE PAR LE GRAND LIVRE. Il était
        // écrit dans `stock_qty` sans mouvement : le produit naissait avec un stock que `stock_movements` ignorait, et
        // tout ce qui reconstruit le stock depuis le grand livre (rotation, « Stock Final » des fiches, l'invariant
        // stock = grand livre de l'essai) se trompait de ce montant, au web comme au poste. Le produit est créé à 0,
        // puis le stock initial entre par `AdjustStockAction` (point unique, 6.1), en « Ajout Manuel » daté de la
        // création — comme l'onglet « Ajouter Stock », sans écriture comptable (ce n'est pas un écart d'inventaire).
        $initial = (float) ($payload['stock_qty'] ?? 0);
        $payload['stock_qty'] = 0;

        return DB::transaction(function () use ($payload, $id, $initial) {
            $produit = new Product();
            // ⚠️ `id` n'est pas remplissable : `create(['id' => …])` l'ignorerait EN
            // SILENCE et le serveur forgerait son propre UUID (piège des achats, 14.78).
            if ($id !== null) {
                $produit->id = $id;
            }
            $produit->fill($payload);
            $produit->save();

            if ($initial > 0) {
                app(AdjustStockAction::class)->execute($produit, $initial, 'manual_addition', null, null, 'Stock initial');
            }

            AuditLog::record('product.created', 'stocks');

            return $produit->fresh();
        });
    }

    /** @param array<string, mixed> $v */
    public function modifier(Product $produit, array $v, bool $avecStock): Product
    {
        $produit->update($this->payload($v, $avecStock));

        AuditLog::record('product.updated', 'stocks');

        return $produit->fresh();
    }
}
