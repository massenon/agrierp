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

    /**
     * Décision BS-Q11 (21/10/2026) — LA correspondance libellée du statut d'un sujet : la valeur technique (`reforme`,
     * `vendu`, `mort`) reste celle de la base et de l'envoi du poste, seul l'affichage est accentué (« Réformé »).
     * Registre, filtres, fiche du sujet, historique et PDF passent tous par ici ; le poste la reprend à l'identique
     * (`ReproducteursRepository.libelleStatut`).
     *
     * @var array<string, string>
     */
    public const LIBELLES_STATUT = ['actif' => 'Actif', 'reforme' => 'Réformé', 'vendu' => 'Vendu', 'mort' => 'Mort'];

    /** Le libellé d'un statut ; une valeur inconnue garde `ucfirst` (jamais de statut avalé). */
    public static function libelleStatut(string $statut): string
    {
        return self::LIBELLES_STATUT[$statut] ?? ucfirst($statut);
    }

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

    public function getStatusLabelAttribute(): string
    {
        return self::libelleStatut((string) $this->status);
    }

    public function isPresent(): bool
    {
        return $this->status === 'actif';
    }
}
