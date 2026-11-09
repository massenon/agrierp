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
        // CONF-1 : jamais d'ouverture sans le droit (même garde que `EmailSmtp::mount`).
        abort_unless(\Illuminate\Support\Facades\Gate::allows('manage-parametres'), 403);

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

    /** CONF-1 : un fichier déposé est jugé tout de suite (même règle que l'enregistrement) ; refusé, il est retiré de la zone. */
    public function updatedLogoFile(): void
    {
        $this->jugerDepot('logo');
    }

    public function updatedFaviconFile(): void
    {
        $this->jugerDepot('favicon');
    }

    private function jugerDepot(string $genre): void
    {
        $propriete = $genre.'File';
        $this->resetErrorBag($propriete);

        if (! $this->{$propriete}) {
            return;
        }

        [, $erreur] = app(\App\Services\EntrepriseService::class)
            ->jugerFichier($genre, $this->{$propriete}->get(), $this->{$propriete}->getClientOriginalName());

        if ($erreur !== null) {
            $this->{$propriete} = null;
            $this->addError($propriete, $erreur);
        }
    }

    /** CONF-1 : « Supprimer » le logo ou le favicon (confirmation côté vue) ; l'ancien fichier part du disque. */
    public function supprimerFichier(string $genre): void
    {
        $this->authorize('manage-parametres');
        abort_unless(in_array($genre, ['logo', 'favicon'], true), 404);

        app(\App\Services\EntrepriseService::class)->supprimerFichier($genre);

        $this->reset([$genre.'File']);
        $this->dispatch('toast', message: $genre === 'logo' ? "Logo de l'entreprise supprimé." : "Icône du site supprimée.", type: 'success');
    }

    public function save(): void
    {
        $this->authorize('manage-parametres');

        $service = app(\App\Services\EntrepriseService::class);

        // Les règles `mecef*` ne s'appliquent qu'à la demande du poste et à l'onglet « Facturation normalisée (e-MECeF) » : pas ici.
        // Les fichiers n'ont plus la règle `image` de Laravel (elle refuse l'ICO) : `EntrepriseService::fichiersDepuis` les juge.
        $this->validate(array_filter($service->regles(), fn ($cle) => ! str_starts_with($cle, 'mecef'), ARRAY_FILTER_USE_KEY), \App\Services\EntrepriseService::MESSAGES);

        // CONF-1 : TOUT est jugé avant d'écrire quoi que ce soit (logo ET favicon), puis les fichiers sont rangés.
        $entrees = [];
        foreach (['logo' => $this->logoFile, 'favicon' => $this->faviconFile] as $genre => $fichier) {
            if ($fichier) {
                $entrees[$genre] = ['octets' => $fichier->get(), 'nom' => $fichier->getClientOriginalName()];
            }
        }

        try {
            $fichiers = $service->fichiersDepuis($entrees);
        } catch (\Illuminate\Validation\ValidationException $e) {
            foreach ($e->errors() as $champ => $messages) {
                $this->addError($champ, $messages[0]);
            }

            return;
        }

        try {
            $service->enregistrer([
                'companyName' => $this->companyName, 'promoterName' => $this->promoterName, 'address' => $this->address,
                'phone' => $this->phone, 'email' => $this->email, 'ifu' => $this->ifu, 'rccm' => $this->rccm,
                'tvaEnabled' => $this->tvaEnabled, 'vpsRate' => $this->vpsRate, 'cnssEmployeeRate' => $this->cnssEmployeeRate,
                'cnssEmployerPensionRate' => $this->cnssEmployerPensionRate, 'cnssEmployerFamilyRate' => $this->cnssEmployerFamilyRate,
                'cnssEmployerRiskRate' => $this->cnssEmployerRiskRate,
                // Le réglage MeCeF a son onglet (`FacturationEmecef`) : aucune clé `mecef*` ici, il reste tel quel.
            ], auth()->user(), $fichiers);
        } catch (\Illuminate\Validation\ValidationException $e) {
            // Le refus porte sur UN champ : l'IFU (e-MECeF) ou les taux de paie arrêtés.
            foreach ($e->errors() as $champ => $messages) {
                $this->addError($champ, $messages[0]);
            }

            return;
        }

        $this->reset(['logoFile', 'faviconFile']);
        $this->dispatch('toast', message: 'Modifications enregistrées avec succès.', type: 'success');
    }

    public function render()
    {
        return view('livewire.parametres.donnees-entreprise');
    }
}
