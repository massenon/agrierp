<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ⚠️ RÈGLE URGENTE (Document 01 §6.7, message de lancement du projet) :
 * `sale_lines.manual_total_amount` est LA source de vérité du montant
 * d'une ligne de vente — `unit_price` n'est dérivé QUE pour l'affichage
 * (`unit_price = manual_total_amount / qty`, jamais l'inverse). Toute
 * vente, hors devis technique, passe par une confirmation de montant
 * global éditable — jamais une multiplication automatique prix × quantité
 * qui déciderait seule du total.
 *
 * `accounting_entry_id` (sales) et `cost_center_id` (sale_lines) restent
 * nullable sans contrainte FK, comme `livestock_lots.cost_center_id`
 * (ticket 3.1) — Sprint 10.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('sales', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('customer_id')->nullable()->constrained('customers')->nullOnDelete();
            $table->enum('payment_mode', ['especes', 'mobile_money', 'virement', 'credit', 'avance']);
            $table->decimal('subtotal', 14, 2);
            $table->decimal('discount', 14, 2)->default(0);
            $table->decimal('total', 14, 2);
            $table->decimal('cash_received', 14, 2)->nullable();
            $table->decimal('change_due', 14, 2)->nullable();
            $table->enum('delivery_mode', ['gratuite', 'client', 'incluse', 'facturee'])->nullable();
            $table->decimal('delivery_fee', 14, 2)->default(0);
            $table->enum('status', ['validee', 'annulee'])->default('validee');
            $table->string('mecef_qr_ref', 100)->nullable();
            $table->uuid('accounting_entry_id')->nullable();
            $table->timestamps();
        });

        Schema::create('sale_lines', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('sale_id')->constrained('sales')->cascadeOnDelete();
            $table->foreignUuid('product_id')->constrained('products')->restrictOnDelete();
            $table->decimal('qty', 10, 2);
            $table->decimal('unit_price', 14, 2);
            $table->decimal('manual_total_amount', 14, 2);
            $table->boolean('is_manual_price')->default(true);
            $table->uuid('cost_center_id')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('sale_lines');
        Schema::dropIfExists('sales');
    }
};
