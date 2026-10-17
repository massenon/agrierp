<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 14.8 (Sprint 14) — Rapprochement Bancaire.
 *
 * Le prototype simule l'import d'un relevé (`onchange` → toast, aucune
 * donnée traitée). Un rapprochement réel exige de PERSISTER les lignes du
 * relevé : sans elles, il n'y a rien à confronter au Grand Livre et l'écran
 * ne serait qu'une maquette — exactement ce que la politique « zéro
 * placeholder » interdit.
 *
 * `matched_entry_line_id` sans contrainte de clé étrangère, même convention
 * que `sales.accounting_entry_id` (ticket 2026_02_16) : le lettrage est une
 * information de rapprochement, pas une dépendance structurelle — supprimer
 * une écriture ne doit pas cascader sur l'historique du relevé.
 *
 * ⚠️ TABLE NON SYNCHRONISABLE, DÉLIBÉRÉMENT : pas de `device_id` ni de
 * `sync_status` (convention des tables terrain). Un relevé bancaire est
 * importé depuis la banque sur le poste comptable, jamais saisi hors-ligne
 * sur le terrain — lui ajouter des métadonnées de synchronisation
 * suggérerait un flux qui n'existe pas.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('bank_statement_lines', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('account_id')->constrained('chart_of_accounts')->restrictOnDelete();
            $table->date('statement_date');
            $table->string('label', 255);
            // Montant SIGNÉ : positif = crédit reçu en banque, négatif = débit.
            $table->decimal('amount', 14, 2);
            $table->boolean('is_reconciled')->default(false);
            $table->uuid('matched_entry_line_id')->nullable();
            $table->timestamps();

            $table->index(['account_id', 'statement_date']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('bank_statement_lines');
    }
};
