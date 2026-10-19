<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Carbon\Carbon;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Database\Eloquent\Model;

class Sale extends Model
{
    use HasUuids;

    protected $fillable = [
        'customer_id', 'payment_mode', 'subtotal', 'discount', 'total',
        'cash_received', 'change_due', 'delivery_mode', 'delivery_fee',
        'delivery_address', 'delivery_contact',
        // 🔴→✅ TICKET 14.7 — `mecef_status` était ABSENT de `$fillable` alors que
        // `mecef_qr_ref`, sa colonne jumelle, y figurait. L'affectation de masse
        // le supprimait donc silencieusement : le `$sale->update([...])` de
        // `PosInterface::validateSale()` (ticket 7.1) n'écrivait jamais le statut,
        // qui restait figé sur son défaut `en_attente` quel que soit le résultat
        // réel de la transmission. Vérifié sur le MySQL réel du projet : le QR
        // était bien persisté, le statut jamais.
        // Conséquences : les KPI « Transmises / Erreurs » de Facturation
        // affichaient 0 en permanence, et la Déclaration TVA — qui ne retient que
        // les factures réellement transmises (exigence M14) — serait restée
        // définitivement VIDE. Aucune erreur levée nulle part : juste un champ
        // qui ne s'écrivait pas.
        'status', 'mecef_qr_ref', 'mecef_status', 'accounting_entry_id',
        // 🔴→✅ TICKET 14.71 — DATE REELLE DE LA VENTE, distincte de
        // `created_at` qui est la date d'ENREGISTREMENT. Les deux ne
        // divergent que pour une vente encaissee hors ligne et remontee
        // plus tard — c'est exactement le cas ou la difference compte.
        'sold_at',
    ];

    protected function casts(): array
    {
        return [
            'subtotal' => 'decimal:2',
            'discount' => 'decimal:2',
            'total' => 'decimal:2',
            'cash_received' => 'decimal:2',
            'change_due' => 'decimal:2',
            'delivery_fee' => 'decimal:2',
            'sold_at' => 'datetime',
        ];
    }

    /**
     * TICKET 15.31 - LA DATE EFFECTIVE D'UNE VENTE, UN SEUL POINT DE VERITE.
     *
     * `created_at` est la date d'ENREGISTREMENT, `sold_at` celle de la vente
     * (ticket 14.71). Elles divergent des qu'une vente est saisie apres coup
     * (poste hors ligne, vente anterieure du ticket 15.30) - et alors tout
     * rapport qui lit `created_at` met la vente dans le mauvais mois, sans
     * lever la moindre erreur : seuls les chiffres sont faux. L'ecriture
     * comptable, la remanence et le mouvement de stock lisaient deja
     * `sold_at ?? created_at` ; le chiffre d'affaires, la TVA, l'historique
     * et les rapports, non.
     *
     * Repli sur `created_at` pour l'historique et les postes qui n'envoient pas
     * `sold_at` : une vente sans `sold_at` est datee EXACTEMENT comme avant.
     * Ces scopes et cet accesseur sont la seule expression de cette regle -
     * ne jamais la recopier dans une requete.
     */
    public const DATE_EFFECTIVE_SQL = 'COALESCE(sales.sold_at, sales.created_at)';

    /** Date effective en objet : `sold_at ?? created_at`. */
    protected function dateEffective(): Attribute
    {
        return Attribute::get(fn (): ?Carbon => $this->sold_at ?? $this->created_at);
    }

    /** Ventes dont la date effective tombe dans [$du, $au], bornes incluses, journees entieres. */
    public function scopeSoldBetween(Builder $query, string|\DateTimeInterface $du, string|\DateTimeInterface $au): Builder
    {
        return $query
            ->whereRaw('DATE('.self::DATE_EFFECTIVE_SQL.') >= ?', [Carbon::parse($du)->toDateString()])
            ->whereRaw('DATE('.self::DATE_EFFECTIVE_SQL.') <= ?', [Carbon::parse($au)->toDateString()]);
    }

    /**
     * Ticket H5 — ventes NON ANNULÉES. 🔴 Le tableau de bord comptait les ventes annulées (`status = 'annulee'`) dans
     * le chiffre d'affaires, la courbe, les ventes porcines et le Top 5 : une vente annulée gonflait la recette.
     */
    public function scopeNonAnnulees(Builder $query): Builder
    {
        return $query->where(fn ($q) => $q->whereNull('status')->orWhere('status', '!=', 'annulee'));
    }

    /** Ventes dont la date effective est posterieure ou egale a l'instant donne. */
    public function scopeSoldSince(Builder $query, \DateTimeInterface $depuis): Builder
    {
        return $query->whereRaw(self::DATE_EFFECTIVE_SQL.' >= ?', [Carbon::instance($depuis)->format('Y-m-d H:i:s')]);
    }

    /** Ventes dont la date effective est comprise entre deux instants, bornes incluses. */
    public function scopeSoldBetweenInstants(Builder $query, \DateTimeInterface $du, \DateTimeInterface $au): Builder
    {
        return $query->whereRaw(self::DATE_EFFECTIVE_SQL.' BETWEEN ? AND ?', [
            Carbon::instance($du)->format('Y-m-d H:i:s'), Carbon::instance($au)->format('Y-m-d H:i:s'),
        ]);
    }

    /** Tri chronologique sur la date effective (decroissant par defaut : la plus recente d'abord). */
    public function scopeOrderByEffectiveDate(Builder $query, string $sens = 'desc'): Builder
    {
        return $query->orderByRaw(self::DATE_EFFECTIVE_SQL.' '.(strtolower($sens) === 'asc' ? 'asc' : 'desc'));
    }

    public function customer()
    {
        return $this->belongsTo(Customer::class, 'customer_id');
    }

    public function lines()
    {
        return $this->hasMany(SaleLine::class, 'sale_id');
    }

    public function receivable()
    {
        return $this->hasOne(Receivable::class, 'sale_id');
    }
}
