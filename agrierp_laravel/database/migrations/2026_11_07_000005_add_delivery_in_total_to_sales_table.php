<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Frais de livraison INCLUS dans la vente (décision du client, 07/11/2026).
 *
 * Avant : `sales.delivery_fee` était HORS `sales.total` (donc hors écriture comptable, hors encaissement, hors facture DGI).
 * Maintenant : une livraison « facturée » entre dans `sales.total`. Pour ne rien changer aux ventes DÉJÀ enregistrées, le
 * traitement est porté par un drapeau EXPLICITE : `delivery_in_total = true` seulement pour les NOUVELLES ventes ; `false`
 * (défaut, ventes existantes) = frais hors total, comme avant. Le drapeau est figé avec la vente.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('sales', function (Blueprint $table) {
            $table->boolean('delivery_in_total')->default(false);
        });
    }

    public function down(): void
    {
        Schema::table('sales', function (Blueprint $table) {
            $table->dropColumn('delivery_in_total');
        });
    }
};
