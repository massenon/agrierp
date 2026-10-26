<?php

namespace App\Actions;

use App\Models\AuditLog;
use App\Models\CompanySetting;
use App\Models\ElevageNumberingSetting;
use App\Models\FeedRationStandard;
use App\Models\FeedType;
use App\Models\ProphylaxisScheduleStandard;
use App\Support\MotifsRefusPush;
use Illuminate\Validation\ValidationException;

/**
 * Ticket H9b (décision D-H9 du 19/10/2026 : « Paramètres Élevage modifiables au poste et au web ») — barèmes
 * d'élevage reçus du poste.
 *
 * ⚠️ MÊMES RÈGLES QUE `App\Livewire\Elevage\ParametresElevage` : mêmes validations, mêmes journaux d'audit, et
 * SUPPRESSION = ARCHIVAGE (`is_active = false`, ticket 14.55 : un barème effacé faisait disparaître la provende
 * calculée de toute une catégorie). Dernier écrivain gagne : la dernière modification REÇUE s'applique, comme les
 * fiches journalières.
 *
 * Formats attendus (listes, comme toute clé d'envoi) :
 * - `feed_ration_standards` / `prophylaxis_schedule_standards` / `feed_types` : lignes avec leur `id` (UUID du
 *   poste à la création), leurs champs et `is_active` ;
 * - `elevage_numbering` : une ligne avec les 9 formats ;
 * - `company_settings` : une ligne `{rappel_soins_jours}` — SEUL champ de l'entreprise modifiable par ce canal.
 */
class RecordParametresElevageFromDeviceAction
{
    public const TABLES = [
        'feed_ration_standards', 'prophylaxis_schedule_standards', 'feed_types', 'elevage_numbering', 'company_settings',
    ];

    /** @return array{accepted: array<int, mixed>, rejected: array<int, array{id: mixed, reason: string}>} */
    public function execute(string $table, array $lignes): array
    {
        $accepted = [];
        $rejected = [];

        foreach ($lignes as $ligne) {
            $id = is_array($ligne) ? ($ligne['id'] ?? null) : null;
            try {
                if (! is_array($ligne)) {
                    throw ValidationException::withMessages(['id' => 'Ligne illisible.']);
                }
                $accepted[] = match ($table) {
                    'feed_ration_standards' => $this->ration($ligne),
                    'prophylaxis_schedule_standards' => $this->prophylaxie($ligne),
                    'feed_types' => $this->provende($ligne),
                    'elevage_numbering' => $this->numerotation($ligne),
                    'company_settings' => $this->rappelSoins($ligne),
                };
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::motif($e)];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }

    private function valider(array $ligne, array $regles): array
    {
        return validator($ligne, $regles, MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();
    }

    private function ration(array $ligne): string
    {
        $v = $this->valider($ligne, [
            'id' => ['required', 'uuid'],
            'species_code' => ['required', 'in:aviculture,cuniculture,porciculture'],
            'stage_label' => ['required', 'string', 'max:100'],
            'ration_g_per_day' => ['required', 'integer', 'min:1'],
            'is_active' => ['sometimes', 'boolean'],
        ]);
        $this->enregistrer(new FeedRationStandard, $v, ['species_code', 'stage_label', 'ration_g_per_day'],
            'feed_ration_standard.saved', 'feed_ration_standard.archived');

        return $v['id'];
    }

    private function prophylaxie(array $ligne): string
    {
        $v = $this->valider($ligne, [
            'id' => ['required', 'uuid'],
            'species_code' => ['required', 'in:aviculture,cuniculture,porciculture'],
            'period_label' => ['required', 'string', 'max:100'],
            'treatment' => ['required', 'string', 'max:150'],
            'product_recommended' => ['required', 'string', 'max:150'],
            'dosage' => ['required', 'string', 'max:150'],
            'withdrawal_days' => ['required', 'integer', 'min:0'],
            'is_active' => ['sometimes', 'boolean'],
        ]);
        $this->enregistrer(new ProphylaxisScheduleStandard, $v,
            ['species_code', 'period_label', 'treatment', 'product_recommended', 'dosage', 'withdrawal_days'],
            'prophylaxis_schedule.saved', 'prophylaxis_schedule.archived');

        return $v['id'];
    }

    private function provende(array $ligne): string
    {
        $v = $this->valider($ligne, [
            'id' => ['required', 'uuid'],
            'name' => ['required', 'string', 'max:150'],
            'species_id' => ['required', 'exists:livestock_species,id'],
            'standard_bag_weight_kg' => ['required', 'numeric', 'min:0.01'],
            'price_per_kg' => ['required', 'numeric', 'min:0'],
            'is_active' => ['sometimes', 'boolean'],
        ]);
        $this->enregistrer(new FeedType, $v, ['name', 'species_id', 'standard_bag_weight_kg', 'price_per_kg'],
            'feed_type.saved', 'feed_type.archived');

        return $v['id'];
    }

    /**
     * Création avec l'UUID du poste, ou modification ; `is_active = false` ARCHIVE (jamais de suppression).
     *
     * @param  array<int, string>  $champs
     */
    private function enregistrer($modele, array $v, array $champs, string $actionSave, string $actionArchive): void
    {
        $existant = $modele::query()->find($v['id']);
        $actif = (bool) ($v['is_active'] ?? true);
        $valeurs = array_intersect_key($v, array_flip($champs)) + ['is_active' => $actif];

        // Ticket ARC-Q2 — un renvoi (accusé perdu) d'une ligne DÉJÀ archivée n'écrit pas un second audit d'archivage :
        // l'auteur de la Corbeille reste celui qui a archivé.
        $dejaArchive = $existant !== null && ! $existant->is_active;

        if ($existant === null) {
            $modele->id = $v['id'];
            $modele->fill($valeurs)->save();
            $cible = $modele;
        } else {
            $existant->update($valeurs);
            $cible = $existant;
        }

        if ($actif || ! $dejaArchive) {
            AuditLog::record($actif ? $actionSave : $actionArchive, 'elevage', null, $cible);
        }
    }

    private function numerotation(array $ligne): string
    {
        $v = $this->valider($ligne, [
            'bande_format' => ['required', 'string', 'max:50'],
            'lapine_prefix' => ['required', 'string', 'max:10'],
            'male_prefix' => ['required', 'string', 'max:10'],
            'truie_prefix' => ['required', 'string', 'max:10'],
            'verrat_prefix' => ['required', 'string', 'max:10'],
            'portee_prefix' => ['required', 'string', 'max:10'],
            'volaille_prefix' => ['required', 'string', 'max:20'],
            'parc_prefix' => ['required', 'string', 'max:20'],
            'escargot_prefix' => ['required', 'string', 'max:20'],
        ]);
        ElevageNumberingSetting::current()->update($v);
        AuditLog::record('elevage_numbering.updated', 'elevage');

        return 'elevage_numbering';
    }

    private function rappelSoins(array $ligne): string
    {
        $v = $this->valider($ligne, ['rappel_soins_jours' => ['required', 'integer', 'min:0', 'max:30']]);
        CompanySetting::current()->update(['rappel_soins_jours' => $v['rappel_soins_jours']]);
        AuditLog::record('rappel_soins.updated', 'elevage');

        return 'company_settings';
    }
}
