<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Ticket 1.7 (Sprint 1) — notifications.html → Livewire\Notifications\Index
 *
 * `type` (colonne technique, pilote les futurs déclencheurs automatiques —
 * StockLow, HighMortality... Document 02 §5) est distinct de la "Catégorie"
 * affichée dans l'UI (Élevage/Stocks/Finance/RH) : une seule catégorie
 * regroupe plusieurs `type` possibles. Mapping ci-dessous, un seul point de
 * vérité (AVOID_INSTRUCTIONS.md § Inconsistent Coding Patterns).
 */
class Notification extends Model
{
    use HasUuids;

    public $timestamps = false;

    /**
     * Ticket 15.20a — `created_at` est écrit par l'application, dans SON fuseau.
     *
     * Avant, la colonne était remplie par la base (`useCurrent()` = CURRENT_TIMESTAMP, en UTC) alors que
     * toutes les comparaisons (`whereDate('created_at', now())`) se font dans le fuseau de l'application
     * (Africa/Porto-Novo, UTC+1) : entre 00:00 et 01:00 heure du Bénin, la déduplication des alertes ne
     * reconnaissait plus sa propre ligne. Même convention que les colonnes écrites par Eloquent.
     */
    protected static function booted(): void
    {
        static::creating(function (self $notification) {
            $notification->created_at ??= now();
        });
    }

    protected $fillable = [
        'user_id',
        'target_role',
        'type',
        'severity',
        'title',
        'message',
        'icon',
        'link_url',
        'is_read',
        'read_at',
    ];

    protected function casts(): array
    {
        return [
            'is_read' => 'boolean',
            'read_at' => 'datetime',
            'created_at' => 'datetime',
        ];
    }

    private const CATEGORY_BY_TYPE = [
        'stock_low' => 'Stocks',
        'high_mortality' => 'Élevage',
        'prophylaxis_due' => 'Élevage',
        'payment_due' => 'Finance',
        'fiscal_year_reminder' => 'Finance',
        'system' => 'Système',
    ];

    private const SEVERITY_LABELS = [
        'critique' => 'Critique',
        'moyen' => 'Moyen',
        'info' => 'Info',
    ];

    public function getCategoryAttribute(): string
    {
        return self::CATEGORY_BY_TYPE[$this->type] ?? 'Système';
    }

    /**
     * Réutilisé par Livewire\Notifications\Index pour le filtre "Catégorie"
     * — dérivé du même mapping que getCategoryAttribute() (un seul point
     * de vérité), plutôt qu'une liste recréée localement dans le composant.
     */
    public static function typesForCategory(string $category): array
    {
        return array_keys(array_filter(
            self::CATEGORY_BY_TYPE,
            fn ($cat) => $cat === $category
        ));
    }

    public function getSeverityLabelAttribute(): string
    {
        return self::SEVERITY_LABELS[$this->severity] ?? 'Info';
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    /**
     * Notifications visibles par un utilisateur donné : adressées
     * directement à lui (user_id) OU diffusées à l'un de ses rôles
     * (target_role) — sémantique de diffusion Document 02 §5.
     */
    public function scopeVisibleTo(Builder $query, User $user): Builder
    {
        $roleNames = $user->roles->pluck('name');

        return $query->where(function (Builder $q) use ($user, $roleNames) {
            $q->where('user_id', $user->id);

            if ($roleNames->isNotEmpty()) {
                $q->orWhereIn('target_role', $roleNames);
            }
        });
    }
}
