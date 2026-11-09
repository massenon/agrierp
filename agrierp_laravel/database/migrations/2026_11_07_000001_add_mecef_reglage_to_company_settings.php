<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * MECEF-1 — réglage du mode de facturation normalisée. `mecef_mode` NULL = jamais réglé : le commutateur général
 * `config/mecef.php` décide (défaut désactivé). Le jeton JWT est un SECRET (cast `encrypted`, jamais servi au poste).
 * L'IFU utilisé est celui des « Informations Légales & Fiscales » (`ifu`), une seule saisie.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('company_settings', function (Blueprint $table) {
            $table->string('mecef_mode', 20)->nullable();
            $table->string('mecef_api_url', 255)->nullable();
            $table->text('mecef_jeton_encrypted')->nullable();
            $table->string('mecef_operateur_id', 50)->nullable();
            $table->string('mecef_operateur_nom', 100)->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('company_settings', function (Blueprint $table) {
            $table->dropColumn(['mecef_mode', 'mecef_api_url', 'mecef_jeton_encrypted', 'mecef_operateur_id', 'mecef_operateur_nom']);
        });
    }
};
