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

    /** Un jeton est-il disponible ? (saisi à l'écran OU défini dans `.env` : le seul fait que l'on connaît du secret) */
    public function jetonConfigure(): bool
    {
        return $this->jetonEnregistre() !== '' || $this->jetonDeConfiguration() !== '';
    }

    /** CONF-1 — le jeton en service vient de `.env` (aucun jeton saisi à l'écran) : l'écran le dit sans jamais l'afficher. */
    public function jetonDepuisConfiguration(): bool
    {
        return $this->jetonEnregistre() === '' && $this->jetonDeConfiguration() !== '';
    }

    /**
     * CONF-1 — délais et vérification SSL des appels e-MECeF (`SGMEF_HTTP_TIMEOUT`, `SGMEF_CONNECT_TIMEOUT`, `SGMEF_VERIFY_SSL`).
     *
     * @return array{delai: int, delai_connexion: int, verifier_ssl: bool}
     */
    public function reseau(): array
    {
        return [
            'delai' => max(1, (int) config('mecef.sgmef.http_timeout', 30)),
            'delai_connexion' => max(1, (int) config('mecef.sgmef.connect_timeout', 10)),
            'verifier_ssl' => (bool) config('mecef.sgmef.verify_ssl', true),
        ];
    }

    /**
     * Priorité : réglage saisi à l'écran (base) > `.env` (`SGMEF_*`) > valeur par défaut du logiciel.
     *
     * @return array{ifu: string, url: string, jeton: string, operateur_id: string, operateur_nom: string}
     */
    public function emecef(): array
    {
        $r = CompanySetting::query()->first();

        return [
            'ifu' => (string) ($r?->ifu ?: $this->repli('default_ifu')),
            'url' => rtrim((string) ($r?->mecef_api_url ?: $this->repli('api_url') ?: MecefMode::URL_PAR_DEFAUT), '/'),
            'jeton' => $this->jetonEnregistre() !== '' ? $this->jetonEnregistre() : $this->jetonDeConfiguration(),
            'operateur_id' => (string) ($r?->mecef_operateur_id ?: $this->repli('default_operator_id') ?: '1'),
            'operateur_nom' => (string) ($r?->mecef_operateur_nom ?: $this->repli('default_operator_name') ?: 'Caissier'),
        ];
    }

    private function jetonEnregistre(): string
    {
        return (string) CompanySetting::query()->first()?->mecef_jeton_encrypted;
    }

    private function jetonDeConfiguration(): string
    {
        return $this->repli('token');
    }

    private function repli(string $cle): string
    {
        return trim((string) config('mecef.sgmef.'.$cle));
    }
}
