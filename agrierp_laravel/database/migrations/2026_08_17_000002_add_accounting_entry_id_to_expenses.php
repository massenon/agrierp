<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 14.33 (Sprint 14) — rattachement comptable des DEPENSES.
 *
 * Meme colonne, meme role et meme garde anti-doublon que sur `sales` (14.23),
 * `purchases` (14.24), `payslips` (14.25), `fixed_assets` (14.26) et
 * `credit_notes` (14.27).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('expenses', function (Blueprint $table) {
            $table->uuid('accounting_entry_id')->nullable()->after('status');
        });
    }

    public function down(): void
    {
        Schema::table('expenses', function (Blueprint $table) {
            $table->dropColumn('accounting_entry_id');
        });
    }
};
