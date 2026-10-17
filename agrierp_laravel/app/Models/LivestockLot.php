<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class LivestockLot extends Model
{
    use HasUuids;

    protected $fillable = [
        'code', 'species_id', 'stage', 'initial_quantity', 'current_quantity',
        'created_date', 'acquisition_cost', 'status', 'cost_center_id', 'is_active', 'product_id',
    ];

    protected function casts(): array
    {
        return [
            'created_date' => 'date',
            'is_active' => 'boolean',
        ];
    }

    /**
     * Produit vendable issu de cette bande (ticket 14.37).
     *
     * ⚠️ Rattachement DÉCIDÉ par l'exploitant, jamais déduit de l'espèce : une
     * espèce correspond à plusieurs produits, et deux bandes de même espèce
     * peuvent avoir des destinations différentes — pondeuses contre poulets de
     * chair, par exemple.
     */
    /**
     * 🔴→✅ CORRECTIF « ARCHIVAGE » — les bandes VIVANTES : en cours (`status = actif`) ET non archivées
     * (`is_active = true`).
     *
     * Archiver une bande (Gestion des Bandes, Corbeille) pose `is_active = false` sans toucher au statut :
     * les indicateurs qui ne filtraient que `status = actif` comptaient donc encore la bande archivée dans
     * « Effectif Total Vivant », les bandes actives, les alertes sanitaires… Toute statistique « actuelle »
     * passe par ce point unique.
     */
    public function scopeVivantes($query)
    {
        return $query->where('status', 'actif')->where('is_active', true);
    }

    /**
     * Libellés des stades par espèce (« Stade Initial » de la création de bande).
     *
     * ⚠️ La colonne `stage` garde ses quatre valeurs (enum) : seuls les LIBELLÉS changent. Décision client
     * du 17/10/2026, lapins : Reproducteur (`reproduction`), Jeune (`engraissement`), Sous-mères
     * (`croissance`) — les trois catégories de la fiche Lapins ; la ponte n'existe pas pour eux.
     *
     * @return array<string, string> valeur stockée => libellé affiché
     */
    public static function stadesPourEspece(?string $speciesCode): array
    {
        if ($speciesCode === 'cuniculture') {
            return ['reproduction' => 'Reproducteur', 'engraissement' => 'Jeune', 'croissance' => 'Sous-mères'];
        }

        return ['reproduction' => 'Reproduction', 'croissance' => 'Croissance', 'ponte' => 'Ponte', 'engraissement' => 'Engraissement'];
    }

    /** Libellé du stade de cette bande, selon son espèce. */
    public function libelleStade(): string
    {
        return self::stadesPourEspece($this->species?->code)[$this->stage] ?? ucfirst((string) $this->stage);
    }

    public function product()
    {
        return $this->belongsTo(Product::class, 'product_id');
    }

    public function species()
    {
        return $this->belongsTo(LivestockSpecies::class, 'species_id');
    }

    public function dailyEntries()
    {
        return $this->hasMany(LivestockDailyEntry::class, 'lot_id');
    }

    public function reproductionEvents()
    {
        return $this->hasMany(LivestockReproductionEvent::class, 'lot_id');
    }

    /**
     * Numérotation continue inter-bandes (ticket 3.3, Document 05) : un
     * code par défaut suggéré (pré-rempli mais toujours modifiable dans le
     * formulaire, fidèle au champ texte du prototype), qui continue la
     * séquence déjà utilisée pour l'espèce plutôt que de repartir de zéro
     * à chaque nouvelle bande. Dérivé des préfixes configurés au ticket
     * 2.8 (`elevage_numbering_settings`) — un seul point de vérité pour la
     * convention de nommage.
     */
    public static function suggestNextCode(string $speciesCode): string
    {
        $settings = ElevageNumberingSetting::current();

        $prefixMap = [
            'cuniculture' => 'LOT-LAP',
            'aviculture' => $settings->volaille_prefix,
            'porciculture' => 'LOT-POR',
            'helico' => $settings->escargot_prefix,
        ];

        $prefix = $prefixMap[$speciesCode] ?? 'LOT';

        // 🔴→✅ TICKET 14.37 — `SUBSTRING_INDEX` EST UNE FONCTION MYSQL, absente
        // de SQLite : cet écran était intestable et se serait effondré sur tout
        // autre moteur. Même défaut de portabilité que les deux migrations à
        // ENUM corrigées au ticket 14.1, et découvert de la même façon — en
        // exécutant réellement le code.
        //
        // Le suffixe est extrait CÔTÉ PHP. Le volume est celui d'un cheptel de
        // ferme (quelques dizaines de bandes), jamais un cas où déléguer au
        // SGBD changerait quoi que ce soit.
        $lastNumber = static::where('code', 'like', $prefix.'-%')
            ->pluck('code')
            ->map(fn ($code) => (int) preg_replace('/\D/', '', substr(strrchr($code, '-') ?: '', 1)))
            ->max();

        return $prefix.'-'.((int) $lastNumber + 1);
    }
}
