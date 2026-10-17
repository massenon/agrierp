<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 14.55 (Sprint 14) — LA RATION NORMATIVE DEVIENT ARCHIVABLE.
 *
 * `feed_ration_standards` etait la SEULE des quatre tables encore supprimees
 * physiquement a ne pas porter de colonne d'archivage. Or la regle du projet
 * est explicite : « suppression = archivage logique, jamais un DELETE ».
 *
 * ⚠️ CONSEQUENCE REELLE DE LA SUPPRESSION PHYSIQUE : une ration effacee
 * disparaissait aussi du poste Desktop a la synchronisation suivante — le
 * referentiel y est REMPLACE a chaque tirage. La provende servie cessait donc
 * d'etre calculee pour cette categorie, sans que rien ne l'explique, et la
 * valeur d'origine etait irrecuperable.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('feed_ration_standards', function (Blueprint $table) {
            $table->boolean('is_active')->default(true)->after('ration_g_per_day');
        });
    }

    public function down(): void
    {
        Schema::table('feed_ration_standards', function (Blueprint $table) {
            $table->dropColumn('is_active');
        });
    }
};
