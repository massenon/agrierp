<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 14.55 (Sprint 14) — L'ABSENCE DE STAGIAIRE DEVIENT ARCHIVABLE.
 *
 * Seconde des tables encore supprimees physiquement sans colonne d'archivage.
 *
 * ⚠️ UNE ABSENCE SUPPRIMEE EST UNE TRACE EFFACEE. Le registre des stagiaires
 * sert a delivrer des attestations : effacer une absence modifie
 * retroactivement ce que l'ecole atteste, sans que rien ne le montre. Archiver
 * conserve la trace et la rend restaurable.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('internship_absences', function (Blueprint $table) {
            $table->boolean('is_active')->default(true);
        });
    }

    public function down(): void
    {
        Schema::table('internship_absences', function (Blueprint $table) {
            $table->dropColumn('is_active');
        });
    }
};
