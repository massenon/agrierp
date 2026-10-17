<?php

namespace App\Models;

use Carbon\CarbonInterface;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class ArchivedDocument extends Model
{
    use HasUuids;

    protected $fillable = ['title', 'category', 'archived_date', 'expiry_date', 'is_active'];

    protected function casts(): array
    {
        return [
            'archived_date' => 'date',
            'expiry_date' => 'date',
            'is_active' => 'boolean',
        ];
    }

    /**
     * Seuil du statut « Bientôt expiré » : échéance dans 30 jours ou moins (maquette
     * `archivage-documents.html`, carte « Expirant sous 30j »). Le poste Flutter reprend le même.
     */
    public const SEUIL_BIENTOT_EXPIRE_JOURS = 30;

    /**
     * Statut dérivé de expiry_date — jamais un champ stocké séparément.
     * Règle unique : `statutPour()` (page, carte « Expirant sous 30j », filtre, badge).
     */
    public function getStatusAttribute(): string
    {
        return self::statutPour($this->expiry_date);
    }

    /**
     * ⚠️ Ticket 15.24 — RÈGLE UNIQUE DU STATUT, en JOURS CALENDAIRES.
     *
     * L'ancien code faisait `$echeance->diffInDays(now()) <= 30` : avec Carbon 3, `diffInDays` est
     * SIGNÉ (échéance future = négatif) et fractionnaire. Toute échéance à venir passait donc pour
     * « Bientôt expiré », même à +200 jours, et la carte « Expirant sous 30j » comptait tout.
     *
     * Ici : nombre de jours entiers entre AUJOURD'HUI et le jour d'échéance (heures ignorées).
     *  - sans échéance            → valide (jamais « expiré »)
     *  - échéance aujourd'hui ou avant (≤ 0 j) → expire (comme le web et la maquette : une pièce
     *    qui expire le jour J n'est plus valable ce jour-là)
     *  - 1 à 30 jours             → bientot_expire (30 inclus)
     *  - 31 jours et plus         → valide
     */
    public static function statutPour(?CarbonInterface $echeance): string
    {
        if ($echeance === null) {
            return 'valide';
        }

        $jours = (int) round(now()->startOfDay()->diffInDays($echeance->copy()->startOfDay(), false));

        if ($jours <= 0) {
            return 'expire';
        }

        return $jours <= self::SEUIL_BIENTOT_EXPIRE_JOURS ? 'bientot_expire' : 'valide';
    }
}
