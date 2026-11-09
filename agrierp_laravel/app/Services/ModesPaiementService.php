<?php

namespace App\Services;

use App\Actions\RecordTreasuryTransferAction;
use App\Models\AccountingEntry;
use App\Models\AuditLog;
use App\Models\TreasuryAccount;

/**
 * Ticket PA-4 — POINT DE PASSAGE UNIQUE DES « MODES DE PAIEMENT » (compte bancaire, ligne Mobile Money, virement interne).
 *
 * Appelé par `Parametres\ModesPaiement` (le web) ET par l'envoi du poste (type `mode_paiement` de `settings_requests`).
 * Idempotence : l'UUID du poste est la clé du compte créé et le `source_id` de l'écriture du virement ; rejouer ne crée rien.
 */
class ModesPaiementService
{
    public const REGLES_BANQUE = [
        'bankName' => ['required', 'string'],
        'rib' => ['required', 'string', 'max:100'],
        'iban' => ['required', 'string', 'max:40'],
    ];

    public const REGLES_MOMO = [
        'operatorName' => ['required', 'string'],
        'phoneNumber' => ['required', 'string', 'max:30'],
    ];

    /** @param array{bankName: string, holderName?: ?string, rib: string, iban: string, accountCode?: ?string} $v */
    public function creerBanque(array $v, ?string $id = null): TreasuryAccount
    {
        if ($id !== null && ($existant = TreasuryAccount::find($id))) {
            return $existant;
        }

        $compte = new TreasuryAccount();
        if ($id !== null) {
            $compte->id = $id;
        }
        $compte->fill([
            'type' => 'banque',
            'label' => $v['bankName'].(($v['accountCode'] ?? '') ? ' - '.$v['accountCode'] : ''),
            'account_code' => ($v['accountCode'] ?? '') ?: '521',
            'bank_name' => $v['bankName'],
            'holder_name' => ($v['holderName'] ?? null) ?: null,
            'rib' => $v['rib'],
            'iban' => $v['iban'],
            'balance' => 0,
            'is_active' => true,
        ]);
        $compte->save();

        AuditLog::record('treasury_account.bank_created', 'parametres');

        return $compte;
    }

    /** @param array{operatorName: string, phoneNumber: string, holderName?: ?string, simSerial?: ?string, accountCode?: ?string} $v */
    public function creerMomo(array $v, ?string $id = null): TreasuryAccount
    {
        if ($id !== null && ($existant = TreasuryAccount::find($id))) {
            return $existant;
        }

        $compte = new TreasuryAccount();
        if ($id !== null) {
            $compte->id = $id;
        }
        $compte->fill([
            'type' => 'mobile_money',
            'label' => $v['operatorName'].(($v['accountCode'] ?? '') ? ' - '.$v['accountCode'] : ''),
            'account_code' => ($v['accountCode'] ?? '') ?: '5212',
            'operator_name' => $v['operatorName'],
            'holder_name' => ($v['holderName'] ?? null) ?: null,
            'phone_number' => $v['phoneNumber'],
            'sim_serial' => ($v['simSerial'] ?? null) ?: null,
            'balance' => 0,
            'is_active' => true,
        ]);
        $compte->save();

        AuditLog::record('treasury_account.momo_created', 'parametres');

        return $compte;
    }

    /**
     * Virement interne. Rend l'écriture (null : plan comptable incomplet) ; lève `\InvalidArgumentException` (solde
     * insuffisant, comptes identiques) ou une exception d'exercice. Un rejeu (même [$sourceId]) ne vire rien.
     */
    public function virer(TreasuryAccount $source, TreasuryAccount $destination, float $montant, ?string $motif, ?string $sourceId = null): ?AccountingEntry
    {
        if ($sourceId !== null && AccountingEntry::where('source_type', 'treasury_transfer')->where('source_id', $sourceId)->exists()) {
            return AccountingEntry::where('source_type', 'treasury_transfer')->where('source_id', $sourceId)->first();
        }

        $ecriture = app(RecordTreasuryTransferAction::class)->execute($source, $destination, $montant, $motif, null, $sourceId);

        AuditLog::record('treasury.transfer', 'parametres');

        return $ecriture;
    }
}
