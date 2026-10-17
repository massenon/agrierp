<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Ticket 14.26 (Sprint 14) — immobilisation amortissable.
 *
 * Amortissement LINÉAIRE, seule méthode citée par la Note 1 des États
 * Financiers : « les immobilisations sont amorties selon la méthode
 * linéaire ». L'annuité porte sur la base amortissable
 * (valeur d'acquisition − valeur résiduelle), jamais sur la valeur brute :
 * amortir jusqu'à zéro un bien qui conserve une valeur de revente
 * surestimerait la charge et sous-estimerait l'actif.
 *
 * ⚠️ PRORATA TEMPORIS MENSUEL, pas annuel : un bien acquis en novembre ne
 * porte pas une annuité pleine au 31 décembre. Le calcul au mois près est la
 * granularité que permettent les dates réellement saisies — un prorata au
 * jour près donnerait une fausse précision sur une durée exprimée en années.
 */
class FixedAsset extends Model
{
    use HasUuids;

    protected $fillable = [
        'code', 'label', 'account_code', 'acquisition_date', 'acquisition_value',
        'residual_value', 'duration_years', 'method',
        'is_capitalized', 'acquisition_entry_id',
        'status', 'disposal_date', 'disposal_reason', 'is_active',
    ];

    protected function casts(): array
    {
        return [
            'acquisition_date' => 'date:Y-m-d',
            'disposal_date' => 'date:Y-m-d',
            'acquisition_value' => 'decimal:2',
            'residual_value' => 'decimal:2',
            'is_active' => 'boolean',
            'is_capitalized' => 'boolean',
        ];
    }

    public function scopeActive($query)
    {
        return $query->where('is_active', true);
    }

    public function scopeInService($query)
    {
        return $query->where('status', 'en_service');
    }

    /**
     * Biens réellement entrés en comptabilité — les seuls que la dotation peut
     * amortir au grand livre. Une reprise d'antériorité alimente la Note 2 mais
     * n'a jamais été portée à l'actif : l'amortir créerait une charge sans
     * l'actif correspondant, et l'Actif Immobilisé deviendrait négatif.
     */
    public function scopeCapitalized($query)
    {
        return $query->where('is_capitalized', true);
    }

    /** Base réellement amortissable. */
    public function baseAmortissable(): float
    {
        return round(max(0, (float) $this->acquisition_value - (float) $this->residual_value), 2);
    }

    /** Annuité linéaire pleine. */
    public function annuite(): float
    {
        if ($this->duration_years <= 0) {
            return 0.0;
        }

        return round($this->baseAmortissable() / $this->duration_years, 2);
    }

    /**
     * Amortissement cumulé à une date donnée, au prorata des mois écoulés,
     * plafonné à la base amortissable — un bien totalement amorti ne continue
     * jamais de se déprécier.
     */
    public function cumulAmortissement(?string $date = null): float
    {
        $arrete = $date ? \Carbon\Carbon::parse($date) : now();

        if ($this->acquisition_date === null || $arrete->lt($this->acquisition_date)) {
            return 0.0;
        }

        // Une immobilisation cédée cesse de s'amortir à sa date de sortie.
        if ($this->disposal_date && $arrete->gt($this->disposal_date)) {
            $arrete = $this->disposal_date;
        }

        $mois = $this->acquisition_date->diffInMonths($arrete);

        return round(min($this->annuite() * ($mois / 12), $this->baseAmortissable()), 2);
    }

    /** Valeur nette comptable à une date donnée. */
    public function valeurNette(?string $date = null): float
    {
        return round((float) $this->acquisition_value - $this->cumulAmortissement($date), 2);
    }

    /** Le bien est-il intégralement amorti ? */
    public function estTotalementAmorti(?string $date = null): bool
    {
        return $this->cumulAmortissement($date) >= $this->baseAmortissable() - 0.01;
    }

    public function compte()
    {
        return ChartOfAccount::where('code', $this->account_code)->first();
    }
}
