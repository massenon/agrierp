<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ⚠️ MIGRATION SCINDÉE PAR RAPPORT AU DOCUMENT SOURCE (§12
 * `create_receivables_payables_tables`) : `payables` référence `suppliers`
 * et `purchases` (Sprint 5, pas encore créées) — reportée à ce sprint,
 * jamais créée en avance sur ses propres dépendances (même principe que
 * `livestock_lots.cost_center_id`, ticket 3.1). `credit_notes` déjà créée
 * et étendue au ticket 4.5, non reprise ici.
 *
 * ⚠️ CORRECTION RÉTROACTIVE NÉCESSAIRE : `receivables` est LA table
 * documentée pour le suivi des créances (montant, montant déjà réglé,
 * échéance, statut). Les tickets 4.4 et 4.6 avaient dérivé un "solde dû"
 * approximatif directement depuis `sales.payment_mode = credit` faute de
 * cette table. `PosInterface::validateSale()` (ticket 4.2) est corrigée
 * dans ce même ticket pour créer réellement une `Receivable` à chaque
 * vente à crédit, et les tickets 4.4/4.6 sont mis à jour pour interroger
 * `receivables` plutôt que de continuer l'approximation — un seul point
 * de vérité, corrigé dès que l'infrastructure correcte existe.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('receivables', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('customer_id')->constrained('customers')->restrictOnDelete();
            $table->foreignUuid('sale_id')->nullable()->constrained('sales')->nullOnDelete();
            $table->decimal('amount', 14, 2);
            $table->decimal('amount_paid', 14, 2)->default(0);
            $table->date('due_date')->nullable();
            $table->enum('status', ['en_cours', 'soldee', 'en_retard'])->default('en_cours');
            $table->timestamps();
        });

        Schema::create('customer_advances', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('customer_id')->constrained('customers')->restrictOnDelete();
            $table->decimal('amount', 14, 2);
            $table->decimal('amount_used', 14, 2)->default(0);
            $table->date('advance_date');
            $table->timestamps();
        });

        Schema::create('customer_reminders', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('customer_id')->constrained('customers')->restrictOnDelete();
            $table->foreignUuid('receivable_id')->constrained('receivables')->cascadeOnDelete();
            $table->enum('channel', ['whatsapp', 'email', 'appel']);
            $table->date('reminder_date');
            $table->text('message')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('customer_reminders');
        Schema::dropIfExists('customer_advances');
        Schema::dropIfExists('receivables');
    }
};
