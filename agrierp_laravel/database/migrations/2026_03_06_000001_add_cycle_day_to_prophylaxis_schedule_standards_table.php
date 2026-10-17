<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket "communication Flutter/cron jobs" — GAP TROUVÉ : `RAPPEL_DE_PROPHYLAXIE_DU_JOUR.md`
 * exige un `cycle_day` entier pour comparer au jour du cycle de chaque
 * bande, mais `prophylaxis_schedule_standards.period_label` (ticket 2.8)
 * n'est qu'un texte libre repris du prototype ("Le 5e jour", "J1",
 * "Le 2 au 4e jour"...) — jamais un entier exploitable directement.
 *
 * `cycle_day_start`/`cycle_day_end` (bornes incluses, souvent égales pour
 * un jour unique) ajoutés — NULLABLES, remplis pour les entrées
 * réellement relatives au cycle (rempli au niveau seeder), laissés NULL
 * pour les 2 entrées "Le 1er du mois" (calcul par jour calendaire, pas
 * par cycle depuis la mise en lot — base de calcul différente, non
 * couverte par ce mécanisme, documenté honnêtement plutôt que forcé).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('prophylaxis_schedule_standards', function (Blueprint $table) {
            $table->unsignedSmallInteger('cycle_day_start')->nullable()->after('period_label');
            $table->unsignedSmallInteger('cycle_day_end')->nullable()->after('cycle_day_start');
        });
    }

    public function down(): void
    {
        Schema::table('prophylaxis_schedule_standards', function (Blueprint $table) {
            $table->dropColumn(['cycle_day_start', 'cycle_day_end']);
        });
    }
};
