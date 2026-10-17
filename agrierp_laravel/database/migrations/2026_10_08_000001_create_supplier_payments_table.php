<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 15.16 — règlements fournisseurs reçus des postes.
 *
 * ⚠️ CETTE TABLE EXISTE POUR L'IDEMPOTENCE, pas pour l'historique : un poste qui n'a
 * pas reçu l'accusé renvoie le même règlement, et sans trace du premier envoi le
 * serveur décaisserait DEUX FOIS la trésorerie et passerait DEUX écritures. L'`id`
 * est celui du poste, conservé tel quel.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('supplier_payments', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('supplier_id')->constrained('suppliers')->restrictOnDelete();
            $table->foreignUuid('treasury_account_id')->constrained('treasury_accounts')->restrictOnDelete();
            $table->decimal('amount', 14, 2);
            // Part réellement imputée aux dettes : jamais supérieure à `amount`.
            $table->decimal('applied_amount', 14, 2);
            $table->date('payment_date');
            $table->string('device_id', 64)->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('supplier_payments');
    }
};
