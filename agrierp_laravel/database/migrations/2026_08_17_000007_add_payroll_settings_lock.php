<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 14.39 (Sprint 14) — VERROUILLAGE DES PARAMETRES DE PAIE.
 *
 * Le bareme ITS et les taux de charges sont semes avec des valeurs par defaut
 * qui doivent etre validees. La PREMIERE edition reste donc ouverte au
 * comptable : c'est elle qui entre le bareme reellement valide par le client.
 *
 * ⚠️ TOUTE EDITION ULTERIEURE EST RESERVEE A L'ADMINISTRATEUR. Un bareme
 * fiscal et des taux de cotisation determinent le net verse a chaque salarie et
 * les montants declares aux organismes : une fois arretes, ils ne se modifient
 * plus au fil de l'eau. La trace de qui a fige le parametrage, et quand, est
 * conservee — sans elle, un ecart de paie serait impossible a expliquer.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('company_settings', function (Blueprint $table) {
            $table->timestamp('payroll_settings_edited_at')->nullable()->after('cnss_employer_risk_rate');
            $table->uuid('payroll_settings_edited_by')->nullable()->after('payroll_settings_edited_at');
        });
    }

    public function down(): void
    {
        Schema::table('company_settings', function (Blueprint $table) {
            $table->dropColumn(['payroll_settings_edited_at', 'payroll_settings_edited_by']);
        });
    }
};
