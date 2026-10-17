<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ÉCART DOCUMENTÉ (ticket 8.2) : `employees` (§18) ne porte que
 * `is_active` (booléen d'archivage). Le registre réel affiche un statut
 * opérationnel à 3 valeurs (Actif/Congé/Suspendu) — un employé "en congé"
 * reste actif dans l'entreprise (`is_active = true`), c'est une notion
 * distincte de l'archivage. Colonne ajoutée pour ne pas confondre les
 * deux concepts (même principe que `sales.status` vs `mecef_status`,
 * ticket 7.1).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('employees', function (Blueprint $table) {
            $table->enum('status', ['actif', 'conge', 'suspendu'])->default('actif')->after('hire_date');
        });
    }

    public function down(): void
    {
        Schema::table('employees', function (Blueprint $table) {
            $table->dropColumn('status');
        });
    }
};
