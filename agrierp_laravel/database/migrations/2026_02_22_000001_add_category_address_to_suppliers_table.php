<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ÉCART DOCUMENTÉ (ticket 5.6) : `suppliers` (§5) ne documente que
 * name/phone/email/is_active. Le formulaire réel "Nouveau Fournisseur"
 * (`ajouter-fournisseur.html`) exige une Catégorie (liste fermée :
 * Aliments / Produits vétérinaires / Intrants agricoles / Matériel /
 * Autre) et une Adresse optionnelle — colonnes ajoutées en conséquence.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('suppliers', function (Blueprint $table) {
            $table->string('category', 50)->nullable()->after('name');
            $table->string('address', 255)->nullable()->after('email');
        });
    }

    public function down(): void
    {
        Schema::table('suppliers', function (Blueprint $table) {
            $table->dropColumn(['category', 'address']);
        });
    }
};
