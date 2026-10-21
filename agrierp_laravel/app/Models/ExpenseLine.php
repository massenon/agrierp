<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Ramsey\Uuid\Uuid;

/**
 * Ticket DEP1 — une ligne de dépense : un achat (libellé), son COMPTE DE CHARGE (classe 6 du plan) et son montant.
 */
class ExpenseLine extends Model
{
    use HasUuids;

    /**
     * Espace de noms de l'identifiant d'une ligne CONVERTIE depuis une ancienne dépense (UUID v5 de l'identifiant de la
     * dépense). Le serveur (migration, poste ancien) et le poste (palier Drift v56) calculent la MÊME valeur : la ligne
     * convertie ici et celle convertie là-bas sont la même ligne, jamais deux.
     */
    public const ESPACE_CONVERSION = 'c5a0e7a2-6f55-4a52-9e0e-3f1f2f6d0a11';

    protected $fillable = ['expense_id', 'position', 'label', 'charge_account_id', 'amount'];

    protected function casts(): array
    {
        return ['amount' => 'decimal:2', 'position' => 'integer'];
    }

    public function expense()
    {
        return $this->belongsTo(Expense::class);
    }

    public function chargeAccount()
    {
        return $this->belongsTo(ChartOfAccount::class, 'charge_account_id');
    }

    /** Identifiant de la ligne unique d'une dépense convertie (ou reçue à plat d'un ancien poste). */
    public static function idDeConversion(string $expenseId): string
    {
        return Uuid::uuid5(self::ESPACE_CONVERSION, $expenseId)->toString();
    }
}
