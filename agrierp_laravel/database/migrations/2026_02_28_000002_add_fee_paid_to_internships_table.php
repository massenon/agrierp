<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ÉCART DOCUMENTÉ (ticket 8.2, Registre Stagiaires) : `internships` (§18)
 * ne porte que `monthly_fee` (montant), pas de statut de règlement. Le
 * registre réel affiche un badge Payé/En attente à côté du montant — colonne
 * ajoutée en conséquence.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('internships', function (Blueprint $table) {
            $table->boolean('fee_paid')->default(false)->after('monthly_fee');
        });
    }

    public function down(): void
    {
        Schema::table('internships', function (Blueprint $table) {
            $table->dropColumn('fee_paid');
        });
    }
};
