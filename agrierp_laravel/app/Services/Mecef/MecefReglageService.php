<?php

namespace App\Services\Mecef;

use App\Models\AuditLog;
use App\Models\CompanySetting;
use App\Models\User;
use App\Support\MecefMode;
use Illuminate\Validation\ValidationException;

/**
 * LE RÉGLAGE DE LA FACTURATION NORMALISÉE — point de passage unique de ses colonnes (mode, adresse, opérateur, JETON, IFU).
 *
 * Appelé par le formulaire « Facturation normalisée (e-MECeF) » de Paramètres ET, pour les clés `mecef*`, par
 * `EntrepriseService` (la demande `entreprise` du poste, qui ne porte jamais le jeton).
 *
 * ⚠️ Le jeton JWT est un SECRET : chiffré par le cast du modèle, jamais relu à l'écran, jamais servi au poste, JAMAIS journalisé
 * (l'audit dit qu'un réglage a changé, jamais ce qu'il contient). Vide = conservé ; « Effacer » le retire explicitement.
 */
class MecefReglageService
{
    public const MOTIF_IFU = "L'IFU doit comporter 13 chiffres pour la facturation e-MECeF.";

    /** @return array<string, array<int, mixed>> */
    public function regles(): array
    {
        return [
            'mecefMode' => ['required', 'in:'.implode(',', MecefMode::REGLABLES)],
            'mecefApiUrl' => ['nullable', 'url', 'max:255'],
            'mecefOperateurId' => ['nullable', 'string', 'max:50'],
            'mecefOperateurNom' => ['nullable', 'string', 'max:100'],
            'mecefJeton' => ['nullable', 'string', 'max:4000'],
            'ifu' => ['nullable', 'string', 'regex:/^[0-9]+$/', 'max:50'],
        ];
    }

    /** @var array<string, string> */
    public const MESSAGES = [
        'mecefMode.in' => 'Le mode de facturation normalisée doit être : désactivé, e-MECeF ou boîtier.',
        'mecefMode.required' => 'Choisissez le mode de facturation normalisée.',
        'mecefApiUrl.url' => "L'adresse de l'API e-MECeF doit être une adresse web complète (https://…).",
        'ifu.regex' => "L'IFU doit contenir uniquement des chiffres.",
    ];

    /**
     * e-MECeF exige l'IFU de l'entreprise à 13 chiffres : refusé AVANT d'écrire quoi que ce soit.
     *
     * @throws ValidationException
     */
    public function verifierIfu(?string $mode, string $ifu): void
    {
        if ($mode === MecefMode::EMECEF && ! preg_match('/^\d{13}$/', $ifu)) {
            throw ValidationException::withMessages(['ifu' => self::MOTIF_IFU]);
        }
    }

    /**
     * Enregistre le réglage du formulaire : mode, adresse, opérateur, IFU et, SEULEMENT s'il est saisi, le jeton.
     *
     * @param  array{mecefMode: string, mecefApiUrl?: ?string, mecefOperateurId?: ?string, mecefOperateurNom?: ?string, mecefJeton?: ?string, ifu?: ?string}  $v
     *
     * @throws ValidationException
     */
    public function enregistrer(array $v, ?User $auteur = null): void
    {
        $this->verifierIfu($v['mecefMode'], trim((string) ($v['ifu'] ?? '')));

        $settings = CompanySetting::current();
        $avant = $settings->only(['mecef_mode', 'mecef_api_url', 'ifu']);

        $colonnes = $this->colonnes($v);
        if (array_key_exists('ifu', $v)) {
            $colonnes['ifu'] = trim((string) $v['ifu']);
        }

        $settings->update($colonnes);

        if (isset($colonnes['ifu']) && $colonnes['ifu'] !== (string) $avant['ifu']) {
            AuditLog::record('company_settings.updated', 'parametres');
        }

        // Journal SANS valeur : on sait que le réglage a changé, jamais ce que contient le jeton.
        if ($this->aChange($avant, $settings, $v)) {
            AuditLog::record('company_settings.mecef_updated', 'parametres');
        }
    }

    /** « Effacer » : retire le jeton (rien ne part plus à la DGI tant qu'un autre n'est pas saisi). */
    public function effacerJeton(): void
    {
        $settings = CompanySetting::current();

        if ((string) $settings->mecef_jeton_encrypted === '') {
            return;
        }

        $settings->update(['mecef_jeton_encrypted' => null]);
        AuditLog::record('company_settings.mecef_updated', 'parametres');
    }

    /** @return array<string, mixed> les seules colonnes MeCeF présentes dans la demande (absentes : réglage conservé) */
    public function colonnes(array $v): array
    {
        $colonnes = [];

        foreach (['mecefMode' => 'mecef_mode', 'mecefApiUrl' => 'mecef_api_url', 'mecefOperateurId' => 'mecef_operateur_id', 'mecefOperateurNom' => 'mecef_operateur_nom'] as $cle => $colonne) {
            if (array_key_exists($cle, $v)) {
                $colonnes[$colonne] = ($v[$cle] ?? null) === '' ? null : ($v[$cle] ?? null);
            }
        }

        if (is_string($v['mecefJeton'] ?? null) && trim($v['mecefJeton']) !== '') {
            $colonnes['mecef_jeton_encrypted'] = trim($v['mecefJeton']);
        }

        return $colonnes;
    }

    /** @param array<string, mixed> $avant `mecef_mode` et `mecef_api_url` d'avant l'écriture */
    public function aChange(array $avant, CompanySetting $apres, array $v): bool
    {
        return trim((string) ($v['mecefJeton'] ?? '')) !== ''
            || $apres->mecef_mode !== $avant['mecef_mode']
            || $apres->mecef_api_url !== $avant['mecef_api_url'];
    }
}
