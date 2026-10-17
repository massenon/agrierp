<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 15.27 — élargit `chart_of_accounts.label` de 150 à 255.
 *
 * Deux libellés du CSV officiel du client (comptes 54 : 204 caractères, 603 : 242) dépassent 150. Les tronquer
 * altérerait une donnée de référence en silence ; on élargit donc la colonne. Aucune donnée existante n'est modifiée.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('chart_of_accounts', function (Blueprint $table) {
            $table->string('label', 255)->change();
        });
    }

    public function down(): void
    {
        // Pas de retour à 150 : il tronquerait (ou ferait échouer) les libellés longs déjà importés.
    }
};
