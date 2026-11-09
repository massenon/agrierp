<?php

namespace App\Services;

use App\Models\AuditLog;
use App\Models\CompanySetting;
use App\Models\User;
use App\Support\IdentiteVisuelle;
use App\Support\MecefMode;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
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
            // MECEF-1 — facturation normalisée. `sometimes` : un poste plus ancien n'envoie pas ces clés, le réglage reste tel quel.
            'mecefMode' => ['sometimes', 'in:'.implode(',', MecefMode::REGLABLES)],
            'mecefApiUrl' => ['sometimes', 'nullable', 'url', 'max:255'],
            'mecefOperateurId' => ['sometimes', 'nullable', 'string', 'max:50'],
            'mecefOperateurNom' => ['sometimes', 'nullable', 'string', 'max:100'],
            // Le jeton JWT est un SECRET : saisi au web seulement, vide = conservé.
            'mecefJeton' => ['sometimes', 'nullable', 'string', 'max:4000'],
        ];
    }

    /** Taille maximale décodée, en octets : celles de `DonneesEntreprise` (logo 2 048 Ko, favicon 500 Ko). */
    public const TAILLES_FICHIERS = ['logo' => 2048 * 1024, 'favicon' => 500 * 1024];

    /**
     * CONF-1 — formats admis : le LOGO en PNG, JPG ou WEBP ; le FAVICON en ICO ou PNG. Jugés sur le CONTENU (en-tête binaire),
     * jamais sur le seul nom du fichier : la règle `image` de Laravel refuse l'ICO, un nom `.png` peut cacher n'importe quoi.
     * Le SVG est refusé (il peut porter un script).
     */
    public const FORMATS = [
        'logo' => ['image/png' => 'png', 'image/jpeg' => 'jpg', 'image/webp' => 'webp'],
        'favicon' => ['image/vnd.microsoft.icon' => 'ico', 'image/png' => 'png'],
    ];

    /** Extensions de NOM acceptées (en plus de l'en-tête) quand le nom du fichier est connu (web ; le poste le juge à son bout). */
    public const EXTENSIONS_NOM = [
        'logo' => ['png', 'jpg', 'jpeg', 'webp'],
        'favicon' => ['ico', 'png'],
    ];

    /** Champ de formulaire (web) de chaque genre : les erreurs s'affichent sous le bon champ. */
    private const CHAMPS = ['logo' => 'logoFile', 'favicon' => 'faviconFile'];

    /** @return string message français du refus (le MÊME au web et au poste : `lang/fr/validation.php`, groupe `fichiers_entreprise`) */
    public static function messageFichier(string $genre, string $motif): string
    {
        return (string) __('validation.fichiers_entreprise.'.$genre.'.'.$motif);
    }

    /**
     * Ticket CONF-1 — juge UN fichier (octets + nom d'origine s'il est connu). Retourne l'extension à ranger, ou le message de refus.
     *
     * @return array{0: ?string, 1: ?string} [extension, message d'erreur]
     */
    public function jugerFichier(string $genre, string $octets, ?string $nomOrigine = null): array
    {
        $mime = IdentiteVisuelle::typeMime($octets);
        $extension = self::FORMATS[$genre][$mime] ?? null;

        if ($nomOrigine !== null && $nomOrigine !== '' && ! in_array(strtolower(pathinfo($nomOrigine, PATHINFO_EXTENSION)), self::EXTENSIONS_NOM[$genre], true)) {
            return [null, self::messageFichier($genre, 'format')];
        }

        // Un ICO n'est pas lisible par GD ; un PNG/JPEG/WEBP doit l'être (en-tête valide ne suffit pas à faire une image).
        if ($extension === null || ($mime !== 'image/vnd.microsoft.icon' && @getimagesizefromstring($octets) === false) || ($mime === 'image/vnd.microsoft.icon' && ! $this->icoCoherent($octets))) {
            return [null, self::messageFichier($genre, 'format')];
        }

        if (strlen($octets) > self::TAILLES_FICHIERS[$genre]) {
            return [null, self::messageFichier($genre, 'taille')];
        }

        return [$extension, null];
    }

    /** L'annuaire d'un ICO (6 octets d'en-tête + 16 par image) tient dans le fichier. */
    private function icoCoherent(string $octets): bool
    {
        $nombre = unpack('v', substr($octets, 4, 2))[1] ?? 0;

        return $nombre >= 1 && strlen($octets) >= 6 + 16 * $nombre;
    }

    /**
     * Ticket CONF-1 — TOUS les fichiers sont jugés AVANT d'en écrire un seul (un logo valide n'est plus rangé quand le favicon est refusé).
     *
     * @param array<string, array{octets: string, nom?: ?string}> $entrees par genre (`logo`, `favicon`)
     * @return array<string, string> colonnes `logo_path` / `favicon_path` rangées
     *
     * @throws ValidationException un message par fichier refusé, sous le champ du formulaire (`logoFile`, `faviconFile`)
     */
    public function fichiersDepuis(array $entrees): array
    {
        $extensions = [];
        $erreurs = [];

        foreach ($entrees as $genre => $entree) {
            [$extension, $erreur] = $this->jugerFichier($genre, $entree['octets'], $entree['nom'] ?? null);

            if ($erreur !== null) {
                $erreurs[self::CHAMPS[$genre]] = $erreur;
            } else {
                $extensions[$genre] = $extension;
            }
        }

        if ($erreurs !== []) {
            throw ValidationException::withMessages($erreurs);
        }

        $fichiers = [];
        foreach ($extensions as $genre => $extension) {
            $chemin = 'company/'.Str::uuid().'.'.$extension;
            Storage::disk('public')->put($chemin, $entrees[$genre]['octets']);
            $fichiers[$genre.'_path'] = $chemin;
        }

        return $fichiers;
    }

    /**
     * Ticket AUT-2 — logo et favicon ENVOYÉS PAR LE POSTE (`logoB64`, `faviconB64`), ou leur suppression (`logoSupprimer`,
     * `faviconSupprimer` : la colonne repasse à `null`, l'ancien fichier est effacé par `enregistrer`). Mêmes règles, mêmes
     * messages et même rangement que le web. Retourne les colonnes `logo_path` / `favicon_path` à passer à `enregistrer`.
     *
     * @param array<string, mixed> $p
     * @return array<string, ?string>
     *
     * @throws ValidationException fichier illisible, d'un format refusé ou trop gros — AVANT toute écriture
     */
    public function fichiersDepuisBase64(array $p): array
    {
        $entrees = [];

        foreach (['logo', 'favicon'] as $genre) {
            $b64 = $p[$genre.'B64'] ?? null;

            if (! is_string($b64) || $b64 === '') {
                continue;
            }

            $octets = base64_decode($b64, true);
            $entrees[$genre] = ['octets' => $octets === false ? '' : $octets];
        }

        $fichiers = $this->fichiersDepuis($entrees);

        foreach (['logo', 'favicon'] as $genre) {
            if (! isset($fichiers[$genre.'_path']) && filter_var($p[$genre.'Supprimer'] ?? false, FILTER_VALIDATE_BOOLEAN)) {
                $fichiers[$genre.'_path'] = null;
            }
        }

        return $fichiers;
    }

    /** Ticket CONF-1 — « Supprimer » le logo ou le favicon : la colonne repasse à `null`, le fichier est effacé du disque. */
    public function supprimerFichier(string $genre): void
    {
        abort_unless(isset(self::CHAMPS[$genre]), 404);

        $settings = CompanySetting::current();
        $ancien = $settings->{$genre.'_path'};

        $settings->update([$genre.'_path' => null]);
        $this->effacer($ancien);

        AuditLog::record('company_settings.fichier_supprime', 'parametres');
    }

    private function effacer(?string $chemin): void
    {
        if (is_string($chemin) && $chemin !== '' && str_starts_with($chemin, 'company/')) {
            Storage::disk('public')->delete($chemin);
        }
    }

    public const MESSAGES = [
        'ifu.regex' => "L'IFU doit contenir uniquement des chiffres.",
        'mecefMode.in' => 'Le mode de facturation normalisée doit être : désactivé, e-MECeF ou boîtier.',
        'mecefApiUrl.url' => "L'adresse de l'API e-MECeF doit être une adresse web complète (https://…).",
    ];

    /**
     * @param array{companyName: string, promoterName?: ?string, address?: ?string, phone?: ?string, email?: ?string, ifu: string, rccm?: ?string, tvaEnabled?: bool, vpsRate: mixed, cnssEmployeeRate: mixed, cnssEmployerPensionRate: mixed, cnssEmployerFamilyRate: mixed, cnssEmployerRiskRate: mixed} $v
     * @param array<string, ?string> $fichiers colonnes `logo_path` / `favicon_path` déjà rangées (`null` = fichier supprimé)
     *
     * @throws ValidationException taux arrêtés et auteur non administrateur
     */
    public function enregistrer(array $v, ?User $auteur, array $fichiers = []): void
    {
        $avant = CompanySetting::current()->only(['logo_path', 'favicon_path']);

        try {
            $this->ecrire($v, $auteur, $fichiers);
        } catch (\Throwable $e) {
            // Refus (IFU, taux arrêtés…) : les fichiers qui viennent d'être rangés pour cette demande ne restent pas sur le disque.
            foreach ($fichiers as $nouveau) {
                $this->effacer($nouveau);
            }

            throw $e;
        }

        // CONF-1 — un fichier remplacé ou supprimé ne s'accumule pas sur le disque : l'ANCIEN est effacé une fois la base à jour.
        foreach (['logo_path', 'favicon_path'] as $colonne) {
            if (array_key_exists($colonne, $fichiers) && $avant[$colonne] !== null && $avant[$colonne] !== $fichiers[$colonne]) {
                $this->effacer($avant[$colonne]);

                if ($fichiers[$colonne] === null) {
                    AuditLog::record('company_settings.fichier_supprime', 'parametres');
                }
            }
        }
    }

    /** @param array<string, ?string> $fichiers */
    private function ecrire(array $v, ?User $auteur, array $fichiers): void
    {
        $settings = CompanySetting::current();

        // MECEF-1 — e-MECeF exige l'IFU à 13 chiffres : refusé AVANT d'écrire quoi que ce soit (règle de `MecefReglageService`).
        app(\App\Services\Mecef\MecefReglageService::class)->verifierIfu($v['mecefMode'] ?? null, (string) $v['ifu']);

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

        $mecefAvant = $settings->only(['mecef_mode', 'mecef_api_url']);

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
        ] + $this->colonnesMecef($v) + $fichiers);

        if ($tauxModifies || ! $settings->payrollSettingsLocked()) {
            $settings->fresh()->markPayrollSettingsEdited($auteur);
        }

        AuditLog::record('company_settings.updated', 'parametres');

        // Journal SANS valeur : on sait que le réglage a changé, jamais ce que contient le jeton.
        if ($this->mecefAChange($mecefAvant, $settings, $v)) {
            AuditLog::record('company_settings.mecef_updated', 'parametres');
        }
    }

    /** @return array<string, mixed> les seules colonnes MeCeF présentes dans la demande (absentes : réglage conservé) */
    private function colonnesMecef(array $v): array
    {
        return app(\App\Services\Mecef\MecefReglageService::class)->colonnes($v);
    }

    /** @param array<string, mixed> $avant `mecef_mode` et `mecef_api_url` d'avant l'écriture */
    private function mecefAChange(array $avant, CompanySetting $apres, array $v): bool
    {
        return app(\App\Services\Mecef\MecefReglageService::class)->aChange($avant, $apres, $v);
    }
}
