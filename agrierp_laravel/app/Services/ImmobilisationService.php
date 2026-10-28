<?php

namespace App\Services;

use App\Actions\RecordAssetAcquisitionEntryAction;
use App\Actions\RecordDepreciationEntryAction;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\FixedAsset;
use App\Models\TreasuryAccount;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Ticket CP-3 — POINT DE PASSAGE UNIQUE DU REGISTRE DES IMMOBILISATIONS (enregistrer, modifier, sortir, passer la dotation).
 *
 * Appelé par `Comptabilite\Immobilisations` (le web) ET par l'envoi du poste (`SyncController::pushFixedAssets` et
 * `pushDepreciationRequests`, droit `manage-comptabilite`) : mêmes règles, mêmes messages, mêmes écritures.
 *
 * ⚠️ Aucune suppression : un bien sort par cession ou réforme. ⚠️ Un bien déjà comptabilisé ne change pas de valeur
 * d'acquisition ici. ⚠️ La dotation est recalculée par l'Action à partir du registre et du grand livre, jamais reprise d'un
 * montant envoyé.
 */
class ImmobilisationService
{
    public const NATURES_FERME = ['221', '241', '244'];

    public const MOTIF_VALEUR_FIGEE = "Ce bien est déjà comptabilisé : sa valeur d'acquisition ne peut plus être modifiée ici. Passez une écriture de correction au Journal Comptable.";

    /** Comptes de classe 2 hors amortissements (28x) proposés comme natures : ceux de la ferme + ceux déjà portés par un bien. */
    public function natures()
    {
        $utilisees = FixedAsset::query()->pluck('account_code')->filter()->unique()->all();

        return ChartOfAccount::where('class', 2)
            ->where('is_active', true)
            ->where('code', 'not like', '28%')
            ->whereIn('code', array_merge(self::NATURES_FERME, $utilisees))
            ->orderBy('code')
            ->get();
    }

    /**
     * Règles de saisie, sous les noms des propriétés de la page web.
     *
     * @return array<string, array<int, mixed>>
     */
    public function regles(?string $idModifie = null): array
    {
        return [
            'code' => ['required', 'string', 'max:50', Rule::unique('fixed_assets', 'code')->ignore($idModifie)],
            'label' => ['required', 'string', 'max:150'],
            'accountCode' => ['required', 'string', Rule::in($this->natures()->pluck('code')->all())],
            'acquisitionDate' => ['required', 'date', 'before_or_equal:today'],
            'acquisitionValue' => ['required', 'numeric', 'min:1'],
            'residualValue' => ['required', 'numeric', 'min:0', 'lt:acquisitionValue'],
            'durationYears' => ['required', 'integer', 'min:1', 'max:50'],
            'contrepartie' => ['nullable', 'string', Rule::in(array_merge([''], ['credit'], TreasuryAccount::where('is_active', true)->pluck('id')->all()))],
        ];
    }

    public const ATTRIBUTS = [
        'accountCode' => 'nature', 'acquisitionDate' => "date d'acquisition",
        'acquisitionValue' => "valeur d'acquisition", 'residualValue' => 'valeur résiduelle',
        'durationYears' => "durée d'amortissement",
    ];

    /**
     * Enregistre un bien et, sauf reprise d'antériorité (`contrepartie` vide), le capitalise.
     *
     * @param  array{code: string, label: string, accountCode: string, acquisitionDate: string, acquisitionValue: mixed, residualValue: mixed, durationYears: mixed, contrepartie?: ?string}  $v
     * @return array{bien: FixedAsset, message: string}
     */
    public function enregistrer(array $v, ?string $id = null): array
    {
        $bien = new FixedAsset();
        if ($id !== null) {
            $bien->id = $id;   // l'UUID du poste se pose HORS de `fill()` : il n'est pas remplissable
        }
        $bien->fill($this->colonnes($v) + ['status' => 'en_service', 'is_active' => true, 'is_capitalized' => false]);
        $bien->save();

        AuditLog::record('fixed_asset.created', 'comptabilite', null, $bien);

        $message = 'Immobilisation enregistrée.';
        $contrepartie = (string) ($v['contrepartie'] ?? '');

        if ($contrepartie !== '') {
            try {
                $ecriture = app(RecordAssetAcquisitionEntryAction::class)->execute($bien, $contrepartie === 'credit' ? null : $contrepartie);

                $message = $ecriture
                    ? "Immobilisation enregistrée et portée à l'actif (débit {$bien->account_code})."
                    : "Immobilisation enregistrée, mais son écriture d'acquisition n'a pas pu être générée — plan comptable incomplet.";
            } catch (\App\Exceptions\ClosedFiscalYearException|\App\Exceptions\NoOpenFiscalYearException $e) {
                // Le bien existe réellement : il reste au registre, hors comptabilité, et l'écran le dit.
                $message = 'Immobilisation enregistrée SANS écriture : '.$e->getMessage();
            }
        }

        return ['bien' => $bien->fresh(), 'message' => $message];
    }

    /** @throws ValidationException la valeur d'un bien comptabilisé ne se modifie pas ici */
    public function modifier(FixedAsset $bien, array $v): FixedAsset
    {
        if ($bien->is_capitalized && round((float) $v['acquisitionValue'], 2) !== round((float) $bien->acquisition_value, 2)) {
            throw ValidationException::withMessages(['acquisitionValue' => self::MOTIF_VALEUR_FIGEE]);
        }

        $bien->update($this->colonnes($v));

        AuditLog::record('fixed_asset.updated', 'comptabilite', null, $bien);

        return $bien;
    }

    /** @return array<string, array<int, mixed>> */
    public function reglesSortie(FixedAsset $bien): array
    {
        return [
            'cessionDate' => ['required', 'date', 'after_or_equal:'.$bien->acquisition_date->format('Y-m-d')],
            'cessionStatus' => ['required', 'in:cede,reforme'],
            'cessionReason' => ['required', 'string', 'max:150'],
        ];
    }

    public const MESSAGES_SORTIE = ['cessionDate.after_or_equal' => "La date de sortie ne peut pas précéder l'acquisition."];

    public const ATTRIBUTS_SORTIE = ['cessionDate' => 'date de sortie', 'cessionReason' => 'motif'];

    public function sortir(FixedAsset $bien, string $date, string $statut, string $motif): FixedAsset
    {
        $bien->update(['status' => $statut, 'disposal_date' => $date, 'disposal_reason' => $motif]);

        AuditLog::record('fixed_asset.disposed', 'comptabilite', null, $bien);

        return $bien;
    }

    /** Archivage d'une saisie erronée (`is_active`), jamais une suppression. */
    public function archiver(FixedAsset $bien): FixedAsset
    {
        if ($bien->is_active) {
            $bien->update(['is_active' => false]);
            AuditLog::record('fixed_asset.archived', 'comptabilite', null, $bien);
        }

        return $bien;
    }

    /**
     * Passe la dotation de la période : l'Action recalcule l'ÉCART contre le grand livre (idempotente).
     *
     * @return \App\Models\AccountingEntry|null null si rien à doter
     */
    public function passerDotation(string $dateArrete): ?\App\Models\AccountingEntry
    {
        return app(RecordDepreciationEntryAction::class)->execute($dateArrete);
    }

    private function colonnes(array $v): array
    {
        return [
            'code' => $v['code'],
            'label' => $v['label'],
            'account_code' => $v['accountCode'],
            'acquisition_date' => $v['acquisitionDate'],
            'acquisition_value' => $v['acquisitionValue'],
            'residual_value' => $v['residualValue'],
            'duration_years' => $v['durationYears'],
            'method' => 'lineaire',
        ];
    }
}
