<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Reportée au ticket 4.7 (dépendait de `suppliers`/`purchases`, alors
 * inexistantes) — débloquée ici, reprise à l'identique de
 * `FULL_MIGRATIONS_DATABASE.md` §12 (dernière table du groupe
 * `create_receivables_payables_tables` restée en attente).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('payables', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('supplier_id')->constrained('suppliers')->restrictOnDelete();
            $table->foreignUuid('purchase_id')->nullable()->constrained('purchases')->nullOnDelete();
            $table->decimal('amount', 14, 2);
            $table->decimal('amount_paid', 14, 2)->default(0);
            $table->date('due_date')->nullable();
            $table->enum('status', ['en_cours', 'soldee', 'en_retard'])->default('en_cours');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('payables');
    }
};
