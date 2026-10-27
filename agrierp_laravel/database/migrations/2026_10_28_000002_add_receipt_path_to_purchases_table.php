<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket AC-3 — le justificatif d'un ACHAT est rattaché à l'achat (comme celui d'une dépense : `expenses.receipt_path`).
 *
 * Avant ce ticket, `EnregistrerAchat` rangeait le fichier sur le disque sans le relier à rien : personne ne pouvait le
 * retrouver. Le chemin est relatif au disque `local` (privé) ; le fichier se lit par la route authentifiée des
 * justificatifs, jamais par une URL publique.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('purchases', function (Blueprint $table) {
            $table->string('receipt_path', 255)->nullable()->after('purchase_date');
        });
    }

    public function down(): void
    {
        Schema::table('purchases', function (Blueprint $table) {
            $table->dropColumn('receipt_path');
        });
    }
};
