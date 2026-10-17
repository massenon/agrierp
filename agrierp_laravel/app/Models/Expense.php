<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class Expense extends Model
{
    use HasUuids;

    /**
     * Comptes de charge proposes a la saisie d'une depense.
     *
     * ⚠️ TICKET 14.62 — SOURCE UNIQUE. Cette liste vivait **en dur dans la vue
     * Blade**, donc inatteignable depuis l'API : le poste Flutter aurait du la
     * recopier, et les deux listes auraient divergé au premier ajout — un
     * compte de charge disponible d'un cote, absent de l'autre, sans que rien
     * ne le signale.
     *
     * ⚠️ **DIVERGENCE AVEC LA MAQUETTE, SIGNALEE ET NON TRANCHEE** :
     * `saisie-depenses.html` n'offre que **quatre** comptes (601, 602, 621,
     * 624) ; la liste web en compte **neuf**. L'enrichissement n'a jamais ete
     * documente. Les neuf sont conserves — retirer cinq comptes deja
     * utilisables casserait des saisies existantes — mais l'ecart est porte au
     * journal pour arbitrage du client.
     *
     * @var array<int, string>
     */
    public const CATEGORIES = [
        '601 - Aliments',
        '602 - Produits vétérinaires',
        '604 - Fournitures et matériel',
        '605 - Énergie',
        '606 - Entretien',
        '614 - Transports',
        '621 - Salaires',
        '624 - Transports',
        '628 - Autres charges',
    ];

    protected $fillable = [
        'expense_date', 'label', 'category', 'amount', 'treasury_account_id',
        'receipt_path', 'status', 'is_active', 'accounting_entry_id',
    ];

    protected function casts(): array
    {
        return [
            'expense_date' => 'date',
            'amount' => 'decimal:2',
            'is_active' => 'boolean',
        ];
    }

    public function treasuryAccount()
    {
        return $this->belongsTo(TreasuryAccount::class, 'treasury_account_id');
    }
}
