<?php

namespace App\Livewire\Parametres;

use App\Models\AuditLog;
use App\Models\CompanySetting;
use Livewire\Component;
use Livewire\WithFileUploads;

/**
 * Suite du Sprint 11 — parametres.html → Livewire\Parametres\DonneesEntreprise
 * "Identité légale, fiscale et configuration technique de la Ferme École
 * OLOUWACHEGOUN." Chargé comme onglet "Données de l'Entreprise" du hub
 * Paramètres (résolvait par avance la question du ticket 11.2 — voir
 * `ParametresHub`).
 *
 * `company_settings` existait déjà en intégralité depuis la correction du
 * ticket 4.7 (SMTP + SMS pour les canaux de relance) — cet écran est le
 * PREMIER à exposer réellement ses champs d'identité (raison sociale,
 * promoteur, adresse, IFU, RCCM, logo, favicon), jamais une seconde table
 * ni une copie de ces mêmes champs.
 *
 * Logo/Favicon : upload réel (`WithFileUploads`), même traitement que
 * partout ailleurs dans ce projet (ticket 1.6, 5.2, 5.8...).
 *
 * Ticket CFG-1 (19/10/2026) — LE BLOC « Configuration Email (SMTP) » A QUITTÉ
 * CET ÉCRAN pour l'onglet « Email (SMTP) » du hub (`EmailSmtp`), avec son
 * « Envoyer un e-mail de test » : la même configuration se saisissait ici ET
 * dans `/parametres-integrations`, avec deux jeux de valeurs. Le bloc renvoie
 * désormais vers l'onglet ; l'enregistrement de cet écran ne touche plus aucun
 * champ SMTP.
 */
class DonneesEntreprise extends Component
{
    use WithFileUploads;

    public string $companyName = '';

    public string $promoterName = '';

    public string $address = '';

    public string $phone = '';

    public string $email = '';

    public string $ifu = '';

    public string $rccm = '';

    // --- Régime de TVA et paie béninoise (ticket 14.38) ------------------
    public bool $tvaEnabled = true;

    public $vpsRate = 4;

    public $cnssEmployeeRate = 3.6;

    public $cnssEmployerPensionRate = 6.4;

    public $cnssEmployerFamilyRate = 9;

    public $cnssEmployerRiskRate = 2;

    public $logoFile = null;

    public $faviconFile = null;

    public function mount(): void
    {
        $settings = CompanySetting::current();

        $this->companyName = $settings->company_name;
        $this->promoterName = (string) $settings->promoter_name;
        $this->address = (string) $settings->address;
        $this->phone = (string) $settings->phone;
        $this->email = (string) $settings->email;
        $this->ifu = (string) $settings->ifu;
        $this->rccm = (string) $settings->rccm;

        // Ticket 14.38 — régime de TVA et taux de paie béninoise.
        $this->tvaEnabled = (bool) ($settings->tva_enabled ?? true);
        $this->vpsRate = (float) ($settings->vps_rate ?? 4);
        $this->cnssEmployeeRate = (float) ($settings->cnss_employee_rate ?? 3.6);
        $this->cnssEmployerPensionRate = (float) ($settings->cnss_employer_pension_rate ?? 6.4);
        $this->cnssEmployerFamilyRate = (float) ($settings->cnss_employer_family_rate ?? 9);
        $this->cnssEmployerRiskRate = (float) ($settings->cnss_employer_risk_rate ?? 2);
    }

    public function getSettingsProperty(): CompanySetting
    {
        return CompanySetting::current();
    }

    public function save(): void
    {
        $this->authorize('manage-parametres');

        $this->validate([
            'companyName' => ['required', 'string', 'max:150'],
            'ifu' => ['required', 'string', 'regex:/^[0-9]+$/', 'max:50'],
            'email' => ['nullable', 'email'],
            'logoFile' => ['nullable', 'image', 'max:2048'],
            'faviconFile' => ['nullable', 'image', 'max:500'],
            // ⚠️ Bornes issues du droit béninois : VPS 2 % (enseignement privé)
            // ou 4 % (autres) ; risques professionnels 1 à 4 % selon le niveau
            // de risque de l'entreprise. Les laisser libres inviterait à saisir
            // un taux hors barème sans que rien ne le signale.
            'vpsRate' => ['required', 'numeric', 'min:0', 'max:10'],
            'cnssEmployeeRate' => ['required', 'numeric', 'min:0', 'max:20'],
            'cnssEmployerPensionRate' => ['required', 'numeric', 'min:0', 'max:20'],
            'cnssEmployerFamilyRate' => ['required', 'numeric', 'min:0', 'max:20'],
            'cnssEmployerRiskRate' => ['required', 'numeric', 'min:1', 'max:4'],
        ], [
            'ifu.regex' => "L'IFU doit contenir uniquement des chiffres.",
        ]);

        $settings = CompanySetting::current();

        // ⚠️ TICKET 14.39 — VERROU SUR LES TAUX DE PAIE. La première
        // configuration est ouverte (elle entre les valeurs validées par le
        // client) ; toute modification ultérieure exige le rôle
        // administrateur. Les taux déterminent le net versé à chaque salarié et
        // les montants déclarés aux organismes.
        $tauxModifies = $settings->payrollSettingsLocked() && (
            (float) $settings->vps_rate !== (float) $this->vpsRate
            || (float) $settings->cnss_employee_rate !== (float) $this->cnssEmployeeRate
            || (float) $settings->cnss_employer_pension_rate !== (float) $this->cnssEmployerPensionRate
            || (float) $settings->cnss_employer_family_rate !== (float) $this->cnssEmployerFamilyRate
            || (float) $settings->cnss_employer_risk_rate !== (float) $this->cnssEmployerRiskRate
        );

        if ($tauxModifies && ! $settings->payrollSettingsEditableBy(auth()->user())) {
            $this->addError('vpsRate', "Les taux de charges sociales ont été arrêtés le "
                .$settings->payroll_settings_edited_at?->format('d/m/Y à H:i')
                .". Seul un administrateur peut les modifier.");

            return;
        }

        $payload = [
            'company_name' => $this->companyName,
            'promoter_name' => $this->promoterName ?: null,
            'address' => $this->address ?: null,
            'phone' => $this->phone ?: null,
            'email' => $this->email ?: null,
            'ifu' => $this->ifu,
            'rccm' => $this->rccm ?: null,
            'tva_enabled' => $this->tvaEnabled,
            'vps_rate' => $this->vpsRate,
            'cnss_employee_rate' => $this->cnssEmployeeRate,
            'cnss_employer_pension_rate' => $this->cnssEmployerPensionRate,
            'cnss_employer_family_rate' => $this->cnssEmployerFamilyRate,
            'cnss_employer_risk_rate' => $this->cnssEmployerRiskRate,
        ];

        if ($this->logoFile) {
            $payload['logo_path'] = $this->logoFile->store('company', 'public');
        }

        if ($this->faviconFile) {
            $payload['favicon_path'] = $this->faviconFile->store('company', 'public');
        }

        $settings->update($payload);

        // Première saisie des taux : le paramétrage est désormais arrêté.
        if ($tauxModifies || ! $settings->payrollSettingsLocked()) {
            $settings->fresh()->markPayrollSettingsEdited(auth()->user());
        }

        AuditLog::record('company_settings.updated', 'parametres');
        $this->reset(['logoFile', 'faviconFile']);
        $this->dispatch('toast', message: 'Modifications enregistrées avec succès.', type: 'success');
    }

    public function render()
    {
        return view('livewire.parametres.donnees-entreprise');
    }
}
