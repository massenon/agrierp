<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 15.39 (Sprint 0 Laravel) — MOUVEMENTS PAR CATÉGORIE ET DÉPART DE CHAÎNE.
 *
 * Plan « effectif automatique par catégorie » du 14/10/2026 (lapins et porcs) : le serveur
 * persiste les MOUVEMENTS par catégorie et un DÉPART unique, puis recalcule `cat_eff_*`
 * (déjà existants, ticket 14.11 : non recréés ici) comme valeur dérivée, à la façon de
 * `effectif_final`.
 *
 * Emplacements génériques, comme `cat_eff_*` (14.11 / 14.12) :
 *   repro = Reproducteur ; sevre = Jeune (lapins) / Porcelet (porcs) ;
 *   jeune = Lapin de Chair (lapins) / Marchand (porcs).
 * `passage_sevre_jeune` : UN seul champ de passage de stade (Jeune → Chair, Porcelet → Marchand),
 * un FAIT saisi et non un effectif (décision client QC3).
 *
 * ⚠️⚠️ NULLABLES, SANS VALEUR PAR DÉFAUT : `null` = « non ventilé / inconnu », JAMAIS lu comme 0.
 * Un 0 dirait « il ne s'est rien passé dans cette catégorie » ; une fiche saisie avant ce ticket
 * n'a simplement pas la ventilation. Idempotente (rejouable), `down()` n'enlève que ces colonnes.
 */
return new class extends Migration
{
    private const COLONNES = [
        'mort_repro', 'mort_sevre', 'mort_jeune',
        'don_repro', 'don_sevre', 'don_jeune',
        'passage_sevre_jeune',
        'cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune',
    ];

    public function up(): void
    {
        $manquantes = array_values(array_filter(self::COLONNES, fn ($c) => ! Schema::hasColumn('livestock_daily_entries', $c)));

        if ($manquantes === []) {
            return;
        }

        Schema::table('livestock_daily_entries', function (Blueprint $table) use ($manquantes) {
            foreach ($manquantes as $colonne) {
                $table->unsignedInteger($colonne)->nullable();
            }
        });
    }

    public function down(): void
    {
        $presentes = array_values(array_filter(self::COLONNES, fn ($c) => Schema::hasColumn('livestock_daily_entries', $c)));

        if ($presentes === []) {
            return;
        }

        Schema::table('livestock_daily_entries', function (Blueprint $table) use ($presentes) {
            $table->dropColumn($presentes);
        });
    }
};
