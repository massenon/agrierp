<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 14.27 (Sprint 14) — rattachement comptable des AVOIRS.
 *
 * Meme colonne, meme role et meme garde anti-doublon que sur `sales`
 * (14.23), `purchases` (14.24), `payslips` (14.25) et `fixed_assets`
 * (14.26) : un avoir deja comptabilise ne peut plus l'etre une seconde fois.
 *
 * Pas de contrainte de cle etrangere, par coherence avec les 4 tables
 * precedentes : l'ecriture est archivable logiquement (`is_active`) sans
 * bloquer l'avoir qui la reference.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('credit_notes', function (Blueprint $table) {
            $table->uuid('accounting_entry_id')->nullable()->after('status');
        });
    }

    public function down(): void
    {
        Schema::table('credit_notes', function (Blueprint $table) {
            $table->dropColumn('accounting_entry_id');
        });
    }
};
