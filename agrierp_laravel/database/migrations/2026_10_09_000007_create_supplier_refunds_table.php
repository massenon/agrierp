<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 15.20 — remboursements fournisseurs (argent qui REVIENT du fournisseur après un retour).
 *
 * ⚠️ CETTE TABLE EXISTE D'ABORD POUR L'IDEMPOTENCE, comme `supplier_payments` (15.16) : un poste qui n'a pas reçu
 * l'accusé renvoie le même remboursement, et sans trace du premier envoi le serveur encaisserait DEUX FOIS et
 * passerait DEUX écritures. L'`id` est celui du poste, conservé tel quel. Elle sert aussi de livre des créances :
 * créance ouverte d'un fournisseur = Σ `purchases.supplier_credit` − Σ `supplier_refunds.applied_amount`.
 *
 *  - `amount`         : ce que le poste ou l'utilisateur a DEMANDÉ.
 *  - `applied_amount` : ce qui a RÉELLEMENT été encaissé (plafonné à la créance ouverte), jamais supérieur à `amount`.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('supplier_refunds', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('supplier_id')->constrained('suppliers')->restrictOnDelete();
            $table->foreignUuid('treasury_account_id')->constrained('treasury_accounts')->restrictOnDelete();
            $table->decimal('amount', 14, 2);
            $table->decimal('applied_amount', 14, 2);
            $table->date('refund_date');
            $table->string('device_id', 64)->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('supplier_refunds');
    }
};
