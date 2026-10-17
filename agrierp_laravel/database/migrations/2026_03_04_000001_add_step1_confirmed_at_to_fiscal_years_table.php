<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ÉCART DOCUMENTÉ (ticket 10.6) : le prototype traite l'étape 1
 * ("Travaux d'Inventaire & Régularisation → Marquer comme terminé")
 * comme un simple toast sans état persistant. Une confirmation qui ne
 * survit pas au rechargement de la page n'a pas de sens réel dans un
 * assistant de clôture — colonne ajoutée pour que cette confirmation
 * soit réellement mémorisée, pas juste une animation.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('fiscal_years', function (Blueprint $table) {
            $table->timestamp('step1_confirmed_at')->nullable()->after('status');
        });
    }

    public function down(): void
    {
        Schema::table('fiscal_years', function (Blueprint $table) {
            $table->dropColumn('step1_confirmed_at');
        });
    }
};
