<?php

use App\Support\CategorieVolaille;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Ticket VOL-1 (04/11/2026) — LIGNES DE RATIONNEMENT « Reproducteur », « Jeune », « Poussin » de l'aviculture.
 *
 * La fiche « Volailles Reproducteurs » calcule désormais son rationnement par catégorie (effectif calculé × ration de
 * la ligne). Le barème de l'aviculture n'avait que les stades des pondeuses : on y AJOUTE trois lignes, sans toucher aux
 * lignes existantes ni aux libellés des Pondeuses.
 *
 * ⚠️ RATIONS PROVISOIRES, À CONFIRMER AVEC LE CLIENT : Reproducteur 130 g/j, Jeune 80 g/j, Poussin 30 g/j. Elles sont
 * modifiables dans Paramètres Élevage. Une ligne déjà présente (même libellé normalisé) n'est JAMAIS réécrite : la
 * migration est idempotente et ne remet pas à zéro une ration que le client aurait déjà ajustée.
 */
return new class extends Migration
{
    public function up(): void
    {
        $existants = DB::table('feed_ration_standards')->where('species_code', 'aviculture')->pluck('stage_label')
            ->map(fn ($l) => CategorieVolaille::cleDuLibelle($l))->filter()->all();

        foreach (CategorieVolaille::CLES as $cle) {
            if (in_array($cle, $existants, true)) {
                continue;
            }

            DB::table('feed_ration_standards')->insert([
                'id' => (string) Str::uuid(),
                'species_code' => 'aviculture',
                'stage_label' => CategorieVolaille::libelle($cle),
                'ration_g_per_day' => CategorieVolaille::RATIONS_PROVISOIRES[$cle],
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }
    }

    public function down(): void
    {
        foreach (CategorieVolaille::CLES as $cle) {
            DB::table('feed_ration_standards')->where('species_code', 'aviculture')
                ->where('stage_label', CategorieVolaille::libelle($cle))
                ->where('ration_g_per_day', CategorieVolaille::RATIONS_PROVISOIRES[$cle])
                ->delete();
        }
    }
};
