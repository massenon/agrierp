<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Ticket 15.36 — glossaire de la fiche lapins : renomme DEUX libellés du barème.
 *
 *   « Lapin Sevré »                → « Jeune »
 *   « Jeune Lapin (engraissement) » → « Lapin de Chair »
 *
 * Décision client validée le 14/10/2026. La ration (`ration_g_per_day`) n'est
 * JAMAIS touchée : seul le libellé change.
 *
 * ⚠️ IDEMPOTENTE et PRUDENTE : on ne renomme que si le libellé exact existe
 * pour la cuniculture ET que la cible n'existe pas déjà (sinon on créerait un
 * doublon ; l'exploitant tranchera dans « Paramètres élevage »). La base de
 * production n'a pas été vérifiée : elle peut porter l'ancien libellé, le
 * nouveau, ou un libellé édité à la main — ce dernier est laissé tel quel.
 * Le rapprochement des rations ne dépend de toute façon PAS de cette
 * migration : `App\Support\CategorieRationLapin` reconnaît l'ancien ET le
 * nouveau libellé (clé stable).
 *
 * ⚠️ `updated_at` est avancé : le poste Desktop tire le référentiel complet à
 * chaque pull (aucun filtre `since`), il verra donc le nouveau libellé au
 * prochain tirage. Aucune colonne ni forme de réponse ne change.
 */
return new class extends Migration
{
    private const RENOMMAGES = [
        'Lapin Sevré' => 'Jeune',
        'Jeune Lapin (engraissement)' => 'Lapin de Chair',
    ];

    public function up(): void
    {
        foreach (self::RENOMMAGES as $ancien => $nouveau) {
            $this->renommer($ancien, $nouveau);
        }
    }

    public function down(): void
    {
        foreach (self::RENOMMAGES as $ancien => $nouveau) {
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
