<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket VC-1 — encaissements de créances clients reçus des postes.
 *
 * ⚠️ CETTE TABLE EXISTE POUR L'IDEMPOTENCE (comme `supplier_payments`, 15.16) : un poste qui n'a pas reçu l'accusé
 * renvoie le même encaissement, et sans trace du premier envoi le serveur encaisserait DEUX FOIS (trésorerie, créance,
 * écriture). L'`id` est celui du poste, conservé tel quel. Un encaissement saisi au web n'y laisse pas de ligne.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('receivable_payments', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('customer_id')->constrained('customers')->restrictOnDelete();
            // Créance visée, nulle : règlement global du client (FIFO, comme la fiche client du web).
            $table->foreignUuid('receivable_id')->nullable()->constrained('receivables')->restrictOnDelete();
            $table->foreignUuid('treasury_account_id')->constrained('treasury_accounts')->restrictOnDelete();
            $table->decimal('amount', 14, 2);
            // Part réellement imputée aux créances : jamais supérieure à `amount`.
            $table->decimal('applied_amount', 14, 2);
            $table->date('payment_date');
            $table->string('device_id', 64)->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('receivable_payments');
    }
};
