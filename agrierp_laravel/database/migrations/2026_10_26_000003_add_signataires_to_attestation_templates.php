<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ATT-1 — Trois blocs de signature configurables par modèle d'attestation :
 * Examinateur, Président du Jury, Directeur Général.
 * Les noms/titres restent modifiables à chaque génération (valeurs par défaut).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('attestation_templates', function (Blueprint $table) {
            $table->string('sig1_titre')->default('Le Directeur Général')->after('numero_sequence');
            $table->string('sig1_nom')->default('M. Olouchègoun')->after('sig1_titre');
            $table->string('sig2_titre')->default("L'Examinateur")->after('sig1_nom');
            $table->string('sig2_nom')->nullable()->after('sig2_titre');
            $table->string('sig3_titre')->default('Le Président du Jury')->after('sig2_nom');
            $table->string('sig3_nom')->nullable()->after('sig3_titre');
        });
    }

    public function down(): void
    {
        Schema::table('attestation_templates', function (Blueprint $table) {
            $table->dropColumn(['sig1_titre', 'sig1_nom', 'sig2_titre', 'sig2_nom', 'sig3_titre', 'sig3_nom']);
        });
    }
};
