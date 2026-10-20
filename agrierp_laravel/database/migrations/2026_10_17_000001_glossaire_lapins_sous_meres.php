<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Décision client du 17/10/2026 — glossaire des lapins : Reproducteur / Jeune / Sous-mères.
 *
 * Barème de la cuniculture : « Jeune » (30 g/j) devient « Sous-mères », PUIS « Lapin de Chair »
 * (60 g/j) devient « Jeune ». L'ORDRE est imposé : dans l'autre sens, « Jeune » existerait déjà et
 * le second renommage serait sauté (même garde que la migration 2026_10_14_000001). Les rations ne
 * changent pas ; seul `stage_label` change, la forme de `/api/sync/pull` est inchangée.
 */
return new class extends Migration
{
    private const RENOMMAGES = [
        'Jeune' => 'Sous-mères',
        'Lapin de Chair' => 'Jeune',
    ];

    public function up(): void
    {
        foreach (self::RENOMMAGES as $ancien => $nouveau) {
            $this->renommer($ancien, $nouveau);
        }
    }

    public function down(): void
    {
        foreach (array_reverse(self::RENOMMAGES, true) as $ancien => $nouveau) {
            $this->renommer($nouveau, $ancien);
        }
    }

    private function renommer(string $de, string $vers): void
    {
        $cible = DB::table('feed_ration_standards')
            ->where('species_code', 'cuniculture')->where('stage_label', $vers)->exists();

        if ($cible) {
            return;
        }

        DB::table('feed_ration_standards')
            ->where('species_code', 'cuniculture')->where('stage_label', $de)
            ->update(['stage_label' => $vers, 'updated_at' => now()]);
    }
};
