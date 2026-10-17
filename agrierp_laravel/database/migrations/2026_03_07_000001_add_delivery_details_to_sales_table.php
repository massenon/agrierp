<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket "vérification structurelle rigoureuse — pos-interface.html" —
 * la modale "Livraison" du prototype (adresse + contact du transporteur)
 * n'avait jamais été construite. `delivery_mode`/`delivery_fee`
 * existaient déjà sur `sales`, mais `delivery_address`/`delivery_contact`
 * n'ont jamais eu de colonne — ajoutées ici pour compléter réellement la
 * fonctionnalité plutôt que de l'implémenter à moitié.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('sales', function (Blueprint $table) {
            $table->string('delivery_address')->nullable()->after('delivery_fee');
            $table->string('delivery_contact')->nullable()->after('delivery_address');
        });
    }

    public function down(): void
    {
        Schema::table('sales', function (Blueprint $table) {
            $table->dropColumn(['delivery_address', 'delivery_contact']);
        });
    }
};
