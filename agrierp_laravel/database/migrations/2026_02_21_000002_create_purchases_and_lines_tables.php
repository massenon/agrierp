<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * `purchase_lines.unit_price` est un vrai prix unitaire (contrairement à
 * `sale_lines` où `manual_total_amount` fait foi) — un achat est facturé
 * par le fournisseur à un prix connu, la règle "vente à la pièce"
 * (Document 01 §6.7) ne s'applique qu'aux ventes, jamais aux achats.
 *
 * `purchases.accounting_entry_id` reste nullable sans contrainte FK,
 * comme `livestock_lots.cost_center_id` (ticket 3.1) — Sprint 10.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('purchase_orders', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('supplier_id')->constrained('suppliers')->restrictOnDelete();
            $table->date('expected_delivery_date')->nullable();
            $table->enum('status', ['brouillon', 'envoye', 'recu', 'annule'])->default('brouillon');
            $table->timestamps();
        });

        Schema::create('purchase_order_lines', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('purchase_order_id')->constrained('purchase_orders')->cascadeOnDelete();
            $table->foreignUuid('product_id')->constrained('products')->restrictOnDelete();
            $table->decimal('qty', 10, 2);
            $table->decimal('estimated_unit_price', 14, 2)->nullable();
            $table->timestamps();
        });

        Schema::create('purchases', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('supplier_id')->constrained('suppliers')->restrictOnDelete();
            $table->foreignUuid('purchase_order_id')->nullable()->constrained('purchase_orders')->nullOnDelete();
            $table->enum('payment_mode', ['especes', 'mobile_money', 'virement', 'credit']);
            $table->decimal('total', 14, 2);
            $table->uuid('accounting_entry_id')->nullable();
            $table->date('purchase_date');
            $table->timestamps();
        });

        Schema::create('purchase_lines', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('purchase_id')->constrained('purchases')->cascadeOnDelete();
            $table->foreignUuid('product_id')->constrained('products')->restrictOnDelete();
            $table->decimal('qty', 10, 2);
            $table->decimal('unit_price', 14, 2);
            $table->timestamps();
        });

        Schema::create('purchase_returns', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('purchase_id')->constrained('purchases')->restrictOnDelete();
            $table->foreignUuid('product_id')->constrained('products')->restrictOnDelete();
            $table->decimal('qty', 10, 2);
            $table->text('reason')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('purchase_returns');
        Schema::dropIfExists('purchase_lines');
        Schema::dropIfExists('purchases');
        Schema::dropIfExists('purchase_order_lines');
        Schema::dropIfExists('purchase_orders');
    }
};
