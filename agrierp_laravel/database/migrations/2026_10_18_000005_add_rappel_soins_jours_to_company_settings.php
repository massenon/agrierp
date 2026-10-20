<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Règle R-SOINS-01 — délai du rappel des soins planifiés, RÉGLÉ PAR L'EXPLOITANT (Paramètres Élevage > Prophylaxie).
 * 3 jours par défaut : la valeur employée depuis le ticket 15.49, désormais modifiable au lieu d'être une constante.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('company_settings', function (Blueprint $table) {
            $table->unsignedTinyInteger('rappel_soins_jours')->default(3);
        });
    }

    public function down(): void
    {
        Schema::table('company_settings', function (Blueprint $table) {
            $table->dropColumn('rappel_soins_jours');
        });
    }
};
