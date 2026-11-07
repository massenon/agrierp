<?php

namespace App\Services\Mecef;

use App\Models\CompanySetting;
use App\Support\MecefMode;

/**
 * MECEF-1 — LE RÉGLAGE DE LA FACTURATION NORMALISÉE, UN SEUL POINT DE LECTURE.
 *
 * Le mode vit en base (`company_settings.mecef_mode`). Tant qu'il est NUL (jamais réglé), `config/mecef.php`
 * (`MECEF_ACTIF`) décide : faux = désactivé (défaut), vrai = `simule` (passerelle de démonstration, développement et
 * tests). « Actif » est DÉRIVÉ : tout mode sauf `desactive`.
 *
 * ⚠️ Le jeton JWT n'est lu qu'ici et par `EmecefGateway` ; il ne quitte JAMAIS le serveur (ni tirage du poste, ni réponse
 * d'API, ni audit).
 */
class MecefReglage
{
    public function mode(): string
    {
        $mode = CompanySetting::query()->value('mecef_mode');

        if (in_array($mode, MecefMode::REGLABLES, true)) {
            return $mode;
        }

        return config('mecef.actif') ? MecefMode::SIMULE : MecefMode::DESACTIVE;
    }

    public function actif(): bool
    {
        return $this->mode() !== MecefMode::DESACTIVE;
    }

    public function jetonConfigure(): bool
    {
        return (string) CompanySetting::query()->first()?->mecef_jeton_encrypted !== '';
    }

    /** @return array{ifu: string, url: string, jeton: string, operateur_id: string, operateur_nom: string} */
    public function emecef(): array
    {
        $r = CompanySetting::query()->first();

        return [
            'ifu' => (string) $r?->ifu,
            'url' => rtrim((string) ($r?->mecef_api_url ?: MecefMode::URL_PAR_DEFAUT), '/'),
            'jeton' => (string) $r?->mecef_jeton_encrypted,
            'operateur_id' => (string) ($r?->mecef_operateur_id ?: '1'),
            'operateur_nom' => (string) ($r?->mecef_operateur_nom ?: 'Caissier'),
        ];
    }
}
