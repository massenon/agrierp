<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ATT-1 — Données de naissance du stagiaire, nécessaires pour le corps de
 * l'attestation officielle de formation.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('internships', function (Blueprint $table) {
            $table->date('birth_date')->nullable()->after('end_date');
            $table->string('birth_place', 100)->nullable()->after('birth_date');
        });
    }

    public function down(): void
    {
        Schema::table('internships', function (Blueprint $table) {
            $table->dropColumn(['birth_date', 'birth_place']);
        });
    }
};
