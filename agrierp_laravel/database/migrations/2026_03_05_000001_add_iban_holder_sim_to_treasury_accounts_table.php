<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ÉCART DOCUMENTÉ (Modes de Paiement, Sprint 11) : `treasury_accounts`
 * (ticket 2.6) ne prévoit que `rib` (pas `iban`, pourtant une donnée
 * bancaire réellement distincte — RIB et IBAN coexistent dans les deux
 * vrais formulaires du prototype), pas de titulaire nommé (`holder_name`,
 * "Titulaire du Compte"/"Titulaire de la Ligne"), pas de numéro de série
 * SIM (`sim_serial`, ligne Mobile Money uniquement).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('treasury_accounts', function (Blueprint $table) {
            $table->string('iban', 40)->nullable()->after('rib');
            $table->string('holder_name', 150)->nullable()->after('bank_name');
            $table->string('sim_serial', 30)->nullable()->after('phone_number');
        });
    }

    public function down(): void
    {
        Schema::table('treasury_accounts', function (Blueprint $table) {
            $table->dropColumn(['iban', 'holder_name', 'sim_serial']);
        });
    }
};
