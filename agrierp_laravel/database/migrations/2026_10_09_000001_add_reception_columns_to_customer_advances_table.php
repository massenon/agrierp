<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 15.19 — une avance client ENTRE EN TRÉSORERIE (décision D2) et dit d'où elle vient.
 *
 * ⚠️ TOUTES NULLABLES, et ce n'est pas un oubli. Les avances saisies avant ce ticket n'ont
 * jamais touché ni un compte de trésorerie ni le grand livre : on ne sait pas dans quelle
 * caisse l'argent est entré, ni même s'il y est entré. Leur inventer un compte serait pire
 * que de les laisser sans. `treasury_account_id IS NULL` = avance NON COMPTABILISÉE (voir
 * `CustomerAdvance::estComptabilisee()`).
 *
 *  - `treasury_account_id` : le compte où l'argent est entré (même compte que l'écriture D 5xx).
 *  - `payment_mode`        : mode de paiement dit par le poste ou la page (libre côté base,
 *                            borné par le service).
 *  - `motif`               : « Motif / Commande réservée » de la maquette.
 *  - `device_id`           : poste d'origine, quand l'avance vient de `/api/sync/push`.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('customer_advances', function (Blueprint $table) {
            $table->foreignUuid('treasury_account_id')->nullable()->after('customer_id')
                ->constrained('treasury_accounts')->restrictOnDelete();
            $table->string('payment_mode', 20)->nullable()->after('advance_date');
            $table->string('motif', 255)->nullable()->after('payment_mode');
            $table->string('device_id', 64)->nullable()->after('motif');
        });
    }

    public function down(): void
    {
        Schema::table('customer_advances', function (Blueprint $table) {
            $table->dropConstrainedForeignId('treasury_account_id');
            $table->dropColumn(['payment_mode', 'motif', 'device_id']);
        });
    }
};
