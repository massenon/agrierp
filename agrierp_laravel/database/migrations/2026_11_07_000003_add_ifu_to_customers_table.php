<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * MECEF-3 (choix de la facture) — l'IFU du client, facultatif : une entreprise cliente en a un (13 chiffres), un client
 * particulier non. Il préremplit la fenêtre « Facture normalisée » de la caisse ; la fiche du client peut changer sans
 * toucher aux factures déjà normalisées (celles-ci gardent l'IFU saisi à la vente : `sales.client_ifu`).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('customers', function (Blueprint $table) {
            $table->string('ifu', 13)->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('customers', function (Blueprint $table) {
            $table->dropColumn('ifu');
        });
    }
};
