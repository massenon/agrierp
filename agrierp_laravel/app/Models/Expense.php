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
     * Ticket DEP1 — N'EST PLUS UNE SAISIE : la catégorie texte est remplacée par le compte de charge de chaque ligne.
     * Conservée pour les POSTES ANCIENS (ils la lisent au tirage et l'envoient à plat) : table de correspondance
     * catégorie → compte, et liste servie sous `expense_categories`. À retirer quand tous les postes sont migrés.
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
        // Ticket DEP1 — l'en-tête d'une dépense à plusieurs lignes.
        'payment_mode', 'cost_center_id', 'supplier_id', 'beneficiary', 'created_by',
        // Ticket DEP7 — non payée comptant : crédite le 401 du fournisseur et ouvre une dette (aucune trésorerie).
        'on_credit',
    ];

    /**
     * Ticket DEP1 — mode de paiement = TYPE du compte de trésorerie (le projet n'a pas d'autre notion : écran
     * Paramètres › Modes de Paiement). Clé = `treasury_accounts.type`, valeur = libellé affiché (web et poste).
     *
     * @var array<string, string>
     */
    public const MODES_DE_PAIEMENT = [
        'caisse' => 'Espèces',
        'banque' => 'Banque',
        'mobile_money' => 'Mobile Money',
    ];

    /**
     * Ticket DEP7 (DEP-Q3) — le CHOIX de règlement, proposé quand un fournisseur est choisi : clé = valeur du champ
     * (`on_credit` faux / vrai), valeur = libellé affiché (web et poste, mot pour mot).
     *
     * @var array<string, string>
     */
    public const REGLEMENTS = [
        'comptant' => 'Payée comptant',
        'credit' => 'À crédit (dette fournisseur)',
    ];

    /**
     * Ticket DEP7 — le règlement tel que le détail déplié le dit (web et poste, mot pour mot) : « Payée comptant »,
     * « À crédit — en attente » (dette ouverte), « À crédit — réglée » (dette soldée).
     */
    public static function libelleReglement(bool $aCredit, ?string $statut): string
    {
        if (! $aCredit) {
            return 'Payée comptant';
        }

        return $statut === 'payee' ? 'À crédit — réglée' : 'À crédit — en attente';
    }

    /**
     * Ticket DEP1 — le LIBELLÉ-RÉSUMÉ de l'en-tête (`expenses.label`, lu par les rapports et le Tableau de bord) : le
     * libellé de la ligne seule, sinon « premier libellé (+N autres) ». Une seule règle, web et poste.
     *
     * @param  array<int, string>  $libelles
     */
    public static function resume(array $libelles): string
    {
        $libelles = array_values($libelles);
        $reste = count($libelles) - 1;

        return $reste <= 0 ? ($libelles[0] ?? '') : $libelles[0].' (+'.$reste.' '.($reste === 1 ? 'autre' : 'autres').')';
    }

    protected function casts(): array
    {
        return [
            'expense_date' => 'date',
            'amount' => 'decimal:2',
            'is_active' => 'boolean',
            'on_credit' => 'boolean',
        ];
    }

    public function lines()
    {
        return $this->hasMany(ExpenseLine::class)->orderBy('position')->orderBy('id');
    }

    public function costCenter()
    {
        return $this->belongsTo(CostCenter::class, 'cost_center_id');
    }

    public function supplier()
    {
        return $this->belongsTo(Supplier::class, 'supplier_id');
    }

    public function creator()
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    /** La pièce comptable liée : sa référence est RELUE d'ici, jamais recopiée dans la dépense. */
    public function accountingEntry()
    {
        return $this->belongsTo(AccountingEntry::class, 'accounting_entry_id');
    }

    public function treasuryAccount()
    {
        return $this->belongsTo(TreasuryAccount::class, 'treasury_account_id');
    }
}
