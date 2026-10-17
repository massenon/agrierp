<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 15.19 — imputations d'avances client (une ligne par imputation).
 *
 * ⚠️ CETTE TABLE EXISTE D'ABORD POUR L'IDEMPOTENCE, comme `supplier_payments` (15.16) : un
 * poste qui n'a pas reçu l'accusé renvoie la même imputation, et sans trace du premier envoi
 * le serveur imputerait DEUX FOIS (avance entamée deux fois, créance réduite deux fois, deux
 * écritures 419/411). L'`id` est celui du poste, conservé tel quel. Elle sert aussi d'historique :
 * `customer_advances.amount_used` n'est qu'un cumul.
 *
 *  - `amount`         : ce que l'utilisateur ou le poste a DEMANDÉ d'imputer.
 *  - `applied_amount` : ce qui a RÉELLEMENT été imputé (plafonné), jamais supérieur à `amount`.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('advance_imputations', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('customer_advance_id')->constrained('customer_advances')->restrictOnDelete();
            $table->foreignUuid('receivable_id')->constrained('receivables')->restrictOnDelete();
            $table->decimal('amount', 14, 2);
            $table->decimal('applied_amount', 14, 2);
            $table->date('imputation_date');
            $table->string('device_id', 64)->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('advance_imputations');
    }
};
