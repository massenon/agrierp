<?php

namespace App\Actions;

use App\Models\LivestockSpecies;
use App\Models\ModuleConfig;
use App\Models\User;
use App\Support\MotifsRefusPush;
use Illuminate\Validation\ValidationException;

/**
 * Ticket MOD1 — Modules Actifs reçus du poste (même effet que `Livewire\Parametres\ModulesActifs::toggleModule()`).
 *
 * Une ligne par espèce : `{id, species_code, is_enabled}` (l'`id` envoyé est le code de l'espèce : la configuration
 * est une ligne UNIQUE par espèce, et c'est sous ce nom que le serveur acquitte ou refuse). ⚠️ La valeur est
 * EXPLICITE — jamais une bascule : un envoi rejoué ou arrivé en double ne rebascule pas le module. Dernier écrivain
 * gagne, comme les autres paramètres. Ne touche que `modules_config`, jamais la comptabilité.
 */
class RecordModulesConfigFromDeviceAction
{
    /** @return array{accepted: array<int, mixed>, rejected: array<int, array{id: mixed, reason: string}>} */
    public function execute(array $lignes, User $user): array
    {
        $accepted = [];
        $rejected = [];

        foreach ($lignes as $ligne) {
            $id = is_array($ligne) ? ($ligne['species_code'] ?? $ligne['id'] ?? null) : null;
            try {
                if (! is_array($ligne)) {
                    throw ValidationException::withMessages(['id' => 'Ligne illisible.']);
                }
                $v = validator($ligne, [
                    'species_code' => ['required', 'string', 'max:20'],
                    'is_enabled' => ['required', 'boolean'],
                ], MotifsRefusPush::messages(), MotifsRefusPush::attributs())->validate();

                if ($v['species_code'] !== ModuleConfig::ASSISTANT_DEMARRAGE && ! LivestockSpecies::query()->where('code', $v['species_code'])->exists()) {
                    throw ValidationException::withMessages(['species_code' => 'Espèce inconnue : '.$v['species_code'].'.']);
                }

                ModuleConfig::definir($v['species_code'], (bool) $v['is_enabled'], $user->id);
                $accepted[] = $v['species_code'];
            } catch (ValidationException $e) {
                $rejected[] = ['id' => $id, 'reason' => MotifsRefusPush::motif($e)];
            }
        }

        return ['accepted' => $accepted, 'rejected' => $rejected];
    }
}
