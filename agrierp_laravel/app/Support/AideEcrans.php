<?php

namespace App\Support;

use App\Models\ModuleConfig;

/**
 * Ticket AIDE-1 — LECTURE DES TEXTES D'AIDE (`lang/fr/aide_ecrans.php`, source unique web + poste).
 *
 * Le bouton flottant d'aide n'existe QUE si le module « Assistant de démarrage » est allumé (Paramètres > Modules Actifs,
 * éteint par défaut) : `actif()` est le seul endroit qui le décide pour le layout.
 */
class AideEcrans
{
    /** Le module est-il allumé ? (la même ligne `modules_config` que l'assistant de démarrage). */
    public static function actif(): bool
    {
        return ModuleConfig::isEnabled(ModuleConfig::ASSISTANT_DEMARRAGE);
    }

    /**
     * L'aide d'une route. [$chemin] est le chemin de la ROUTE tel que Laravel le déclare, paramètres compris
     * (`/clients/{customer}/profil`), précédé d'un `/`. Une route absente du fichier reçoit l'aide générique
     * (`defaut`) : le panneau n'est jamais vide.
     *
     * @return array{titre: string, puces: array<int, string>, generique: bool}
     */
    public static function pour(string $chemin): array
    {
        $ecrans = trans('aide_ecrans.ecrans');
        $aide = is_array($ecrans) ? ($ecrans[$chemin] ?? null) : null;

        if (is_array($aide) && isset($aide['titre'], $aide['puces'])) {
            return ['titre' => $aide['titre'], 'puces' => array_values($aide['puces']), 'generique' => false];
        }

        $defaut = trans('aide_ecrans.defaut');

        return ['titre' => $defaut['titre'], 'puces' => array_values($defaut['puces']), 'generique' => true];
    }

    /** Chemin de la route courante, dans la forme des clés du fichier (`/dashboard`, `/sujets/{animal}`). */
    public static function cheminCourant(): string
    {
        $uri = request()->route()?->uri() ?? request()->path();

        return '/'.ltrim($uri, '/');
    }

    /** @return array<string, string> libellés du panneau */
    public static function panneau(): array
    {
        return trans('aide_ecrans.panneau');
    }

    /** @return array<string, mixed> la visite guidée : libellés et 4 étapes */
    public static function visite(): array
    {
        return trans('aide_ecrans.visite');
    }
}
