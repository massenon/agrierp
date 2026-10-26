<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ATT-1 — Civilité du stagiaire (M. / Mme) : conditionne l'accord grammatical
 * dans l'attestation officielle de formation (« s'est distingué » / « s'est distinguée »).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('internships', function (Blueprint $table) {
            $table->string('civilite', 5)->default('M.')->after('birth_place');
        });
    }

    public function down(): void
    {
        Schema::table('internships', function (Blueprint $table) {
            $table->dropColumn('civilite');
        });
    }
};
