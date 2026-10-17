<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * `pricing_mode` : exactement 2 valeurs — `fourchette` (price_min/price_max)
 * ou `quote` (sur devis, cages sur mesure uniquement). Jamais "prix fixe"
 * ni "prix au kg" (Document 00 §5.3). La contrainte applicative
 * (quote ⇒ price_min/max null ; fourchette ⇒ les deux renseignés,
 * price_max >= price_min) est validée côté Livewire au ticket 2.4, pas ici
 * — ce modèle expose uniquement des accessors de lecture, un seul point de
 * vérité pour l'affichage (réutilisé par le catalogue et, plus tard, le
 * POS Sprint 4).
 */
class Product extends Model
{
    use HasUuids;

    protected $fillable = [
        'sku', 'name', 'description', 'category_id', 'unit', 'pricing_mode',
        'price_min', 'price_max', 'tva_rate', 'stock_qty',
        'alert_threshold', 'species_id', 'is_active',
    ];

    protected function casts(): array
    {
        return [
            'price_min' => 'decimal:2',
            'price_max' => 'decimal:2',
            'tva_rate' => 'decimal:2',
            'stock_qty' => 'decimal:2',
            'alert_threshold' => 'decimal:2',
            'is_active' => 'boolean',
        ];
    }

    /**
     * Ticket 14.40 — stock d'aliment converti EN KILOS.
     *
     * 🔴 RÉGRESSION INTRODUITE AU TICKET 14.36 ET CORRIGÉE ICI. Les aliments
     * sont comptés en SACS de 25 kg depuis que le catalogue a adopté l'unité du
     * prototype. Or l'autonomie alimentaire divise un stock par une
     * consommation exprimée en g/jour/sujet, donc en KILOS : lire `stock_qty`
     * tel quel revenait à comparer des sacs à des kilos, et donnait une
     * autonomie **25 fois trop faible** — 6,47 sacs lus comme 6,47 kg, soit une
     * alerte de rupture permanente sur un stock de six mois.
     *
     * Le défaut est de ceux qui ne lèvent aucune erreur : seul le chiffre était
     * faux, et il était faux dans le sens le plus crédible — une alerte, pas un
     * silence.
     *
     * Poids du sac repris de `feed_types.standard_bag_weight_kg` (25 kg pour
     * les 5 aliments du référentiel), jamais d'une constante inventée.
     */
    public function stockEnKg(): float
    {
        $quantite = (float) $this->stock_qty;

        if ($this->unit !== 'sac') {
            return $quantite;
        }

        $poidsSac = (float) (\DB::table('feed_types')->value('standard_bag_weight_kg') ?: 25);

        return round($quantite * $poidsSac, 2);
    }

    public function category()
    {
        return $this->belongsTo(ProductCategory::class, 'category_id');
    }

    /**
     * PMP réel (coût unitaire moyen pondéré) — Σ(qty×unit_price) / Σqty
     * depuis l'historique des achats. Extrait au ticket 12.7 depuis
     * `GestionStocks::computePmp()` (ticket 6.2) — un seul point de
     * vérité pour ce calcul, réutilisé par GestionStocks ET StocksSynth,
     * jamais une seconde implémentation qui pourrait diverger. Retourne
     * `null` si le produit n'a jamais été acheté (jamais une estimation
     * inventée).
     */
    public function computePmp(): ?float
    {
        $lines = \App\Models\PurchaseLine::where('product_id', $this->id)->get();
        $totalQty = (float) $lines->sum('qty');

        if ($totalQty <= 0) {
            return null;
        }

        $totalCost = (float) $lines->sum(fn ($l) => $l->qty * $l->unit_price);

        return round($totalCost / $totalQty, 2);
    }

    /**
     * Ticket 14.30 (Sprint 14) — STOCK NÉGATIF : point de vérité unique.
     *
     * `products.stock_qty` peut descendre sous zéro : la colonne est un
     * `decimal(12,2)` sans contrainte, `AdjustStockAction` décrémente sans
     * plancher, et le POS ne consultait pas le stock du tout avant ce ticket.
     * Un stock négatif n'est pas une fraude : c'est le signe d'une ENTRÉE NON
     * SAISIE (production ou achat non encore enregistré), régularisable par
     * l'ajustement manuel de `GestionStocks`.
     *
     * ⚠️ MAIS UN ACTIF NE PEUT PAS ÊTRE NÉGATIF. Valoriser −7 unités à leur PMP
     * produisait une valeur de stock négative, qui venait en DÉDUCTION de la
     * valeur totale au Bilan (Note 3) comme des tableaux de synthèse : un
     * produit en anomalie faisait mécaniquement baisser la valorisation des
     * autres. Le plancher est donc posé ici, une seule fois, plutôt que
     * réécrit dans les trois écrans qui valorisent — même raison que
     * l'extraction de `computePmp()` au ticket 12.7.
     *
     * Décision à faire valider par le Cabinet FAGUEZ avant recette : aucun
     * document du projet ne tranche la vente en rupture de stock.
     */
    public function quantiteValorisable(): float
    {
        return max(0.0, (float) $this->stock_qty);
    }

    /** Un stock négatif signale une entrée non saisie, jamais une quantité réelle. */
    public function stockEstNegatif(): bool
    {
        return (float) $this->stock_qty < 0;
    }

    /** Manquant à régulariser, en valeur absolue (0 si le stock est sain). */
    public function quantiteManquante(): float
    {
        return $this->stockEstNegatif() ? abs((float) $this->stock_qty) : 0.0;
    }

    /**
     * Valeur de stock au PMP, plancher compris.
     *
     * `null` — et non zéro — pour un produit sans historique d'achat (sujets
     * nés à la ferme, œufs) : l'absence de PMP calculable doit rester
     * distincte d'une valeur nulle, sous peine de faire passer un produit non
     * valorisable pour un produit sans valeur.
     */
    public function valeurStock(): ?float
    {
        $pmp = $this->computePmp();

        return $pmp === null ? null : round($this->quantiteValorisable() * $pmp, 2);
    }

    public function species()
    {
        return $this->belongsTo(LivestockSpecies::class, 'species_id');
    }

    public function getPriceDisplayAttribute(): string
    {
        if ($this->pricing_mode === 'quote') {
            return 'Sur devis';
        }

        return number_format((float) $this->price_min, 0, ',', ' ').' - '.number_format((float) $this->price_max, 0, ',', ' ').' FCFA';
    }

    public function getIsStockLowAttribute(): bool
    {
        return $this->stock_qty <= $this->alert_threshold;
    }

    /**
     * Génère un SKU au même format que les données de référence déjà
     * seedées (CUN-001, AVI-001...) : préfixe de 3 lettres dérivé de la
     * catégorie + séquence incrémentale à 3 chiffres. Ni `ajouter-produit.html`
     * ni `catalogue-view.html` (les deux versions du formulaire "Nouveau
     * Produit" du prototype) n'exposent de champ SKU manuel — génération
     * serveur, un seul point de vérité (ticket 2.4).
     */
    public static function generateSku(string $categoryLabel): string
    {
        $prefix = mb_strtoupper(mb_substr(preg_replace('/[^a-zA-Z]/', '', $categoryLabel), 0, 3));
        $prefix = $prefix ?: 'PRD';

        $lastNumber = static::where('sku', 'like', $prefix.'-%')
            ->selectRaw("MAX(CAST(SUBSTRING(sku, LENGTH(?) + 2) AS UNSIGNED)) as max_num", [$prefix])
            ->value('max_num');

        return $prefix.'-'.str_pad((int) $lastNumber + 1, 3, '0', STR_PAD_LEFT);
    }
}
