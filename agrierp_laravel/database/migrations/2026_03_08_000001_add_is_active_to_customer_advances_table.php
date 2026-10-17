<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket "reconstruction historique-avances.html" — `is_active` absente
 * de `customer_advances` alors que l'archivage logique (jamais un DELETE
 * physique) est la règle appliquée à chaque autre entité métier de ce
 * projet. Ajoutée pour rester cohérent, pas pour introduire une
 * exception.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('customer_advances', function (Blueprint $table) {
            $table->boolean('is_active')->default(true)->after('advance_date');
        });
    }

    public function down(): void
    {
        Schema::table('customer_advances', function (Blueprint $table) {
            $table->dropColumn('is_active');
        });
    }
};
