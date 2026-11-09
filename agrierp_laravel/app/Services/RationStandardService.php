<?php

namespace App\Services;

use App\Models\AuditLog;
use App\Models\FeedRationStandard;

/**
 * Ticket IMPORT-4 — POINT DE PASSAGE UNIQUE de la CRÉATION d'une ration normative (Paramètres Élevage > Rationnement).
 *
 * Les règles vivaient en dur dans `Livewire\Elevage\ParametresElevage::saveRation`. Elles sont ici, lues par l'écran ET par
 * l'importation en masse : mêmes règles, mêmes messages, même trace d'audit (`feed_ration_standard.saved`).
 */
class RationStandardService
{
    /** Filières du formulaire « Ration » : code → libellé de la liste « Espèce » de l'écran. */
    public const ESPECES = [
        'aviculture' => 'Aviculture (Volailles)',
        'cuniculture' => 'Cuniculture (Lapins)',
        'porciculture' => 'Porciculture (Porcs)',
    ];

    /**
     * Règles de saisie sous les noms des colonnes de la table.
     *
     * @return array<string, array<int, string>>
     */
    public static function regles(): array
    {
        return [
            'species_code' => ['required', 'in:'.implode(',', array_keys(self::ESPECES))],
            'stage_label' => ['required', 'string', 'max:100'],
            'ration_g_per_day' => ['required', 'integer', 'min:1'],
        ];
    }

    /**
     * Les mêmes règles sous les noms des propriétés du formulaire de l'écran (`ration_species_code`…).
     *
     * @return array<string, array<int, string>>
     */
    public static function reglesDuFormulaire(): array
    {
        $regles = self::regles();

        return [
            'ration_species_code' => $regles['species_code'],
            'ration_stage_label' => $regles['stage_label'],
            'ration_grammes' => $regles['ration_g_per_day'],
        ];
    }

    /** @param array{species_code: string, stage_label: string, ration_g_per_day: int|string} $v */
    public function creer(array $v, ?string $id = null): FeedRationStandard
    {
        $ration = new FeedRationStandard();
        // `id` n'est pas remplissable : l'identifiant déterministe de l'importation se pose HORS de `fill()`.
        if ($id !== null) {
            $ration->id = $id;
        }
        $ration->fill([
            'species_code' => $v['species_code'],
            'stage_label' => trim((string) $v['stage_label']),
            'ration_g_per_day' => (int) $v['ration_g_per_day'],
            'is_active' => true,
        ]);
        $ration->save();

        AuditLog::record('feed_ration_standard.saved', 'elevage');

        return $ration;
    }
}
