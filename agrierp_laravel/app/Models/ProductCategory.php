<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Validation\ValidationException;

class ProductCategory extends Model
{
    use HasUuids;

    protected $fillable = ['label', 'is_active'];

    protected function casts(): array
    {
        return ['is_active' => 'boolean'];
    }

    /**
     * Ticket UNI — deux catégories de même libellé (« Aliments » et « aliments ») font deux entrées identiques dans
     * tous les filtres et rapports. Le libellé est unique parmi TOUTES les catégories (actives ou non), casse, accents
     * et espaces ignorés. Une catégorie garde son propre libellé à la modification ; les doublons déjà en base ne sont
     * ni touchés ni supprimés (commande `agrierp:doublons`).
     */
    protected static function booted(): void
    {
        static::saving(function (self $categorie) {
            if (! $categorie->isDirty('label')) {
                return;
            }
            if (\App\Rules\UniqueNormalise::estPris('product_categories', 'label', $categorie->label, $categorie->exists ? $categorie->id : null)) {
                throw ValidationException::withMessages([
                    'label' => 'Une catégorie de produits porte déjà le libellé « '.trim((string) $categorie->label).' » : choisissez un autre libellé.',
                ]);
            }
        });
    }

    public function products()
    {
        return $this->hasMany(Product::class, 'category_id');
    }
}
