<?php

namespace App\Models;

use App\Services\FinancialReportService;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Ticket EX9 — Archive figée de l'exercice à la clôture (Q6).
 *
 * Immuable : pas de `updated_at`, pas de soft delete.
 * Conservée 10 ans — jamais purgée par la réinitialisation.
 */
class FiscalYearArchive extends Model
{
    use HasUuids;

    public $timestamps = false;

    protected $fillable = [
        'fiscal_year_id',
        'cloture_at',
        'bilan',
        'compte_resultat',
        'balance',
        'created_at',
    ];

    protected function casts(): array
    {
        return [
            'cloture_at' => 'datetime',
            'created_at' => 'datetime',
            'bilan' => 'array',
            'compte_resultat' => 'array',
            'balance' => 'array',
        ];
    }

    public function fiscalYear()
    {
        return $this->belongsTo(FiscalYear::class);
    }

    /**
     * Crée l'archive figée d'un exercice à sa clôture.
     * Doit être appelé à l'intérieur de la transaction de clôture.
     */
    public static function creerDepuisExercice(FiscalYear $year): self
    {
        $service = app(FinancialReportService::class);
        $asOf = $year->end_date->format('Y-m-d');
        $debut = $year->start_date->format('Y-m-d');

        return static::create([
            'fiscal_year_id' => $year->id,
            'cloture_at' => now(),
            'bilan' => $service->bilan($asOf),
            'compte_resultat' => $service->compteResultat($asOf),
            'balance' => $service->balanceGenerale($debut, $asOf),
            'created_at' => now(),
        ]);
    }
}
