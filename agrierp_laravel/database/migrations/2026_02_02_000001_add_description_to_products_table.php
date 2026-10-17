<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ÉCART DOCUMENTÉ (ticket 2.4) : `products.description` n'existe pas dans
 * `FULL_MIGRATIONS_DATABASE.md` §3, mais le formulaire source
 * (`ajouter-produit.html`) comporte un champ "Description" optionnel.
 * Colonne nullable ajoutée en extension mineure plutôt que d'ignorer un
 * champ réellement présent dans le prototype.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('products', function (Blueprint $table) {
            $table->text('description')->nullable()->after('name');
        });
    }

    public function down(): void
    {
        Schema::table('products', function (Blueprint $table) {
            $table->dropColumn('description');
        });
    }
};
