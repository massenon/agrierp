<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ATT-1 — Numéro de séquence annuel pour l'attestation de formation :
 * le numéro officiel « N°04/2026/FEO/DG » est auto-incrémenté par année
 * à chaque génération.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('attestation_templates', function (Blueprint $table) {
            $table->unsignedInteger('numero_sequence')->default(0)->after('show_stamp');
        });
    }

    public function down(): void
    {
        Schema::table('attestation_templates', function (Blueprint $table) {
            $table->dropColumn('numero_sequence');
        });
    }
};
