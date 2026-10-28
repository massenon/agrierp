<?php

namespace App\Services;

use App\Models\AuditLog;
use App\Models\CompanySetting;
use App\Models\User;
use Illuminate\Validation\ValidationException;

/**
 * Ticket PA-3 — POINT DE PASSAGE UNIQUE DES « DONNÉES DE L'ENTREPRISE » (identité, IFU, RCCM, TVA, taux de paie).
 *
 * Appelé par `Parametres\DonneesEntreprise::save` ET par l'envoi du poste (type `entreprise` de `settings_requests`).
 * Les taux de paie sont VERROUILLÉS après la première configuration : toute modification ultérieure exige le rôle
 * administrateur (ticket 14.39). Logo et favicon se déposent par un fichier, hors de ce service (`enregistrerFichier`).
 */
class EntrepriseService
{
    /** @return array<string, array<int, mixed>> */
    public function regles(): array
    {
        return [
            'companyName' => ['required', 'string', 'max:150'],
            'ifu' => ['required', 'string', 'regex:/^[0-9]+$/', 'max:50'],
            'email' => ['nullable', 'email'],
            // Bornes issues du droit béninois : VPS 2 % ou 4 %, risques professionnels 1 à 4 %.
            'vpsRate' => ['required', 'numeric', 'min:0', 'max:10'],
            'cnssEmployeeRate' => ['required', 'numeric', 'min:0', 'max:20'],
            'cnssEmployerPensionRate' => ['required', 'numeric', 'min:0', 'max:20'],
            'cnssEmployerFamilyRate' => ['required', 'numeric', 'min:0', 'max:20'],
            'cnssEmployerRiskRate' => ['required', 'numeric', 'min:1', 'max:4'],
        ];
    }

    public const MESSAGES = ['ifu.regex' => "L'IFU doit contenir uniquement des chiffres."];

    /**
     * @param array{companyName: string, promoterName?: ?string, address?: ?string, phone?: ?string, email?: ?string, ifu: string, rccm?: ?string, tvaEnabled?: bool, vpsRate: mixed, cnssEmployeeRate: mixed, cnssEmployerPensionRate: mixed, cnssEmployerFamilyRate: mixed, cnssEmployerRiskRate: mixed} $v
     * @param array<string, string> $fichiers colonnes `logo_path` / `favicon_path` déjà rangées
     *
     * @throws ValidationException taux arrêtés et auteur non administrateur
     */
    public function enregistrer(array $v, ?User $auteur, array $fichiers = []): void
    {
        $settings = CompanySetting::current();

        $tauxModifies = $settings->payrollSettingsLocked() && (
            (float) $settings->vps_rate !== (float) $v['vpsRate']
            || (float) $settings->cnss_employee_rate !== (float) $v['cnssEmployeeRate']
            || (float) $settings->cnss_employer_pension_rate !== (float) $v['cnssEmployerPensionRate']
            || (float) $settings->cnss_employer_family_rate !== (float) $v['cnssEmployerFamilyRate']
            || (float) $settings->cnss_employer_risk_rate !== (float) $v['cnssEmployerRiskRate']
        );

        if ($tauxModifies && ! $settings->payrollSettingsEditableBy($auteur)) {
            throw ValidationException::withMessages(['vpsRate' => 'Les taux de charges sociales ont été arrêtés le '
                .$settings->payroll_settings_edited_at?->format('d/m/Y à H:i')
                .'. Seul un administrateur peut les modifier.']);
        }

        $settings->update([
            'company_name' => $v['companyName'],
            'promoter_name' => ($v['promoterName'] ?? null) ?: null,
            'address' => ($v['address'] ?? null) ?: null,
            'phone' => ($v['phone'] ?? null) ?: null,
            'email' => ($v['email'] ?? null) ?: null,
            'ifu' => $v['ifu'],
            'rccm' => ($v['rccm'] ?? null) ?: null,
            'tva_enabled' => (bool) ($v['tvaEnabled'] ?? true),
            'vps_rate' => $v['vpsRate'],
            'cnss_employee_rate' => $v['cnssEmployeeRate'],
            'cnss_employer_pension_rate' => $v['cnssEmployerPensionRate'],
            'cnss_employer_family_rate' => $v['cnssEmployerFamilyRate'],
            'cnss_employer_risk_rate' => $v['cnssEmployerRiskRate'],
        ] + $fichiers);

        if ($tauxModifies || ! $settings->payrollSettingsLocked()) {
            $settings->fresh()->markPayrollSettingsEdited($auteur);
        }

        AuditLog::record('company_settings.updated', 'parametres');
    }
}
