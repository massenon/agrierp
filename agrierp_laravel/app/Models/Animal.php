<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Ticket 14.16 (Sprint 14) — sujet suivi INDIVIDUELLEMENT (reproducteurs).
 *
 * Coexiste délibérément avec le suivi par bande : un lot d'engraissement
 * reste une quantité (`livestock_lots.current_quantity`), un reproducteur
 * devient un enregistrement nominatif. Voir le docblock de la migration pour
 * la raison de ce périmètre.
 *
 * ⚠️ RATTACHEMENT SUR L'EXISTANT, SANS MIGRER LES DONNÉES DÉJÀ SAISIES :
 * `livestock_reproduction_events` porte depuis l'origine `mother_ref` et
 * `sire_ref` en texte libre. L'historique de reproduction d'un sujet est donc
 * retrouvé par correspondance sur `identifier`, jamais par une clé étrangère
 * ajoutée après coup qui aurait laissé orphelins tous les événements
 * antérieurs.
 */
class Animal extends Model
{
    use HasUuids;

    protected $fillable = [
        'identifier', 'species_id', 'lot_id', 'category', 'sex', 'breed',
        'birth_date', 'entry_date', 'origin', 'cage',
        'status', 'exit_date', 'exit_reason', 'is_active',
    ];

    protected function casts(): array
    {
        return [
            'birth_date' => 'date:Y-m-d',
            'entry_date' => 'date:Y-m-d',
            'exit_date' => 'date:Y-m-d',
            'is_active' => 'boolean',
        ];
    }

    public function species()
    {
        return $this->belongsTo(LivestockSpecies::class, 'species_id');
    }

    public function lot()
    {
        return $this->belongsTo(LivestockLot::class, 'lot_id');
    }

    public function scopeActive($query)
    {
        return $query->where('is_active', true);
    }

    /** Reproducteurs — seule catégorie réellement suivie sujet par sujet. */
    public function scopeBreeders($query)
    {
        return $query->where('category', 'reproducteur');
    }

    /**
     * Événements de reproduction du sujet — mère OU géniteur, retrouvés par
     * correspondance sur les références déjà saisies.
     */
    public function reproductionEvents()
    {
        return LivestockReproductionEvent::query()
            ->where(fn ($q) => $q->where('mother_ref', $this->identifier)
                ->orWhere('sire_ref', $this->identifier))
            ->orderByDesc('saillie_date');
    }

    /**
     * Soins et vaccins : `veterinary_records` est rattaché au LOT, jamais au
     * sujet — c'est le niveau auquel la prophylaxie est réellement
     * administrée sur cette ferme (traitement de bande). Les soins du lot du
     * sujet sont donc présentés comme tels, explicitement, plutôt que
     * réinventés au niveau individuel.
     */
    public function lotVeterinaryRecords()
    {
        return VeterinaryRecord::where('lot_id', $this->lot_id)
            ->where('is_active', true)
            ->orderByDesc('record_date');
    }

    public function getAgeInMonthsAttribute(): ?int
    {
        return $this->birth_date?->diffInMonths(now());
    }

    public function isPresent(): bool
    {
        return $this->status === 'actif';
    }
}
