<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Formules universelles (FORMULE_FICHE_ELEVAGE.md, vérifiées contre le JS
 * réel du prototype) — un seul point de vérité, réutilisé par toutes les
 * fiches espèces (tickets 3.5 à 3.9) plutôt que recalculées localement
 * dans chaque composant Livewire :
 *   Taux de Mortalité (%) = (Morts du Jour / Effectif J-1) x 100
 *   Effectif Final = Effectif(J-1) + Achats + Nés - (Morts + Ventes + Dons)
 */
class LivestockDailyEntry extends Model
{
    use HasUuids;

    protected $fillable = [
        'lot_id', 'entry_date', 'achat', 'ne', 'mort', 'vente', 'don',
        'effectif_final', 'effectif_m', 'effectif_f', 'effectif_sevres', 'effectif_smeres',
        // Ticket 14.11 — effectifs par categorie de rationnement, enfin persistes.
        'cat_eff_repro', 'cat_eff_sevre', 'cat_eff_jeune', 'cat_eff_4',
        // Ticket 15.39 — mouvements PAR CATÉGORIE et départ de chaîne (null = non ventilé/inconnu,
        // jamais 0). `cat_eff_*` en sont DÉRIVÉS par EffectifParCategorieService.
        'mort_repro', 'mort_sevre', 'mort_jeune', 'don_repro', 'don_sevre', 'don_jeune',
        'passage_sevre_jeune', 'cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune',
        'feed_qty_kg', 'feed_product_id', 'weight_sample_avg_g',
        'ponte_total', 'ponte_casses', 'treatment_product_id', 'treatment_dose',
        'symptomes', 'vente_sexe', 'vente_montant',
    ];

    protected function casts(): array
    {
        return [
            // 🔴→✅ TICKET 14.4 — `'date'` (sans format) sérialise vers
            // `Y-m-d H:i:s`, alors que la colonne est un DATE et que toutes
            // les recherches du projet comparent une chaîne `Y-m-d` :
            // `updateOrCreate(['lot_id' => …, 'entry_date' => $this->selectedDate])`
            // dans les 5 fiches, `firstOrCreate()` du POS (ticket 14.4).
            // MySQL masquait l'écart en coerçant la comparaison ; sur tout
            // autre pilote la ligne existante n'est pas retrouvée et l'INSERT
            // viole l'index unique `(lot_id, entry_date)` — reproduit
            // réellement en test. `date:Y-m-d` aligne la sérialisation sur le
            // type de colonne et sur la façon dont l'application interroge
            // déjà cette date.
            'entry_date' => 'date:Y-m-d',
            'feed_qty_kg' => 'decimal:2',
            'vente_montant' => 'decimal:2',
        ];
    }

    public function lot()
    {
        return $this->belongsTo(LivestockLot::class, 'lot_id');
    }

    public function feedProduct()
    {
        return $this->belongsTo(Product::class, 'feed_product_id');
    }

    public function treatmentProduct()
    {
        return $this->belongsTo(Product::class, 'treatment_product_id');
    }

    /**
     * Effectif de la veille (J-1) pour ce lot — nécessaire au calcul du
     * taux de mortalité. Retombe sur `livestock_lots.initial_quantity` si
     * aucune entrée antérieure n'existe (première fiche journalière du lot).
     */
    public function previousEffectif(): int
    {
        // 🔴→✅ TICKET 14.4 — DEUX DÉFAUTS RÉELS CORRIGÉS ICI.
        //
        // 1. `where('entry_date', '<', $this->entry_date)` passait un Carbon,
        //    sérialisé en `Y-m-d H:i:s`, comparé à des dates stockées en
        //    `Y-m-d` : l'écriture se trouvait ELLE-MÊME comme « jour
        //    précédent » ('2026-08-16' < '2026-08-16 00:00:00'), et repartait
        //    donc de son propre effectif au lieu de celui de la veille.
        //    `whereDate()` compare des dates, jamais des chaînes datetime.
        // 2. Exclusion explicite de l'enregistrement courant (`whereKeyNot`) —
        //    ceinture et bretelles : « le jour précédent » ne peut en aucun
        //    cas être le jour courant, quelle que soit la représentation de
        //    la date côté pilote.
        //
        // Effet réel constaté en test : deux ventes le même jour donnaient un
        // effectif final négatif (-8 au lieu de 35), la seconde repartant du
        // résultat déjà décrémenté de la première.
        $date = $this->entry_date instanceof \DateTimeInterface
            ? $this->entry_date->format('Y-m-d')
            : $this->entry_date;

        $previous = static::where('lot_id', $this->lot_id)
            ->when($this->getKey(), fn ($q) => $q->whereKeyNot($this->getKey()))
            ->whereDate('entry_date', '<', $date)
            ->orderByDesc('entry_date')
            ->first();

        return $previous?->effectif_final ?? $this->lot?->initial_quantity ?? 0;
    }

    public function getMortalityRateAttribute(): float
    {
        $previous = $this->previousEffectif();

        if ($previous <= 0) {
            return 0.0;
        }

        return round(($this->mort / $previous) * 100, 2);
    }

    /**
     * Calcule effectif_final selon la formule exacte — utilisé par les
     * Actions de sauvegarde des fiches (tickets 3.5+), jamais recalculé
     * autrement localement.
     */
    /**
     * Effectif final du jour.
     *
     * 🔴→✅ TICKET 14.63 — BORNE A ZERO RETABLIE. Les CINQ maquettes calculent
     * `Math.max(0, ...)` ; le serveur, lui, ne bornait pas. Saisir 50 morts sur
     * une bande de 40 stockait donc **-10** sur le web, la ou la maquette ET le
     * poste Flutter affichent 0 : deux surfaces, deux resultats, pour la meme
     * saisie.
     *
     * ⚠️ UN EFFECTIF NEGATIF N'EXISTE PAS, et il ne leve aucune erreur : il se
     * propage silencieusement dans l'effectif de depart du lendemain, dans les
     * taux de mortalite et dans la provende servie.
     *
     * ⚠️ LA SAISIE FAUTIVE RESTE TRACABLE : `mort` conserve la valeur saisie
     * (50), seul l'effectif est borne. Rien n'est efface, la borne evite
     * seulement qu'un impossible se propage.
     */
    public static function computeEffectifFinal(int $previousEffectif, int $achat, int $ne, int $mort, int $vente, int $don = 0): int
    {
        return max(0, $previousEffectif + $achat + $ne - ($mort + $vente + $don));
    }
}
