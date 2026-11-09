<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * MECEF-1 — ce que la DGI renvoie d'une facture normalisée, gardé sur la vente (facture FV) et sur l'avoir (facture FA).
 *
 * `sales.mecef_status` passe d'un enum à un texte pour accueillir `expiree`. Les valeurs déjà stockées ne sont PAS
 * réécrites : `transmise` reste la clé de « Normalisée », `erreur` celle de « Refusée » (voir `App\Support\MecefEtat`).
 * `mecef_qr_ref` porte la donnée du QR renvoyée par la DGI (plus longue que l'ancienne référence : 255 caractères).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('sales', function (Blueprint $table) {
            $table->string('mecef_status', 20)->default('en_attente')->change();
            $table->string('mecef_qr_ref', 255)->nullable()->change();
        });

        Schema::table('sales', function (Blueprint $table) {
            $table->string('mecef_uid', 64)->nullable();
            $table->string('mecef_code', 100)->nullable();
            $table->string('mecef_nim', 50)->nullable();
            $table->string('mecef_compteurs', 50)->nullable();
            $table->dateTime('mecef_normalise_le')->nullable();
            $table->text('mecef_message')->nullable();
        });

        Schema::table('credit_notes', function (Blueprint $table) {
            // NULL = avoir sur une vente non normalisée : aucune transmission.
            $table->string('mecef_status', 20)->nullable();
            $table->string('mecef_uid', 64)->nullable();
            $table->string('mecef_qr_ref', 255)->nullable();
            $table->string('mecef_code', 100)->nullable();
            $table->string('mecef_nim', 50)->nullable();
            $table->string('mecef_compteurs', 50)->nullable();
            $table->dateTime('mecef_normalise_le')->nullable();
            $table->text('mecef_message')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('credit_notes', function (Blueprint $table) {
            $table->dropColumn(['mecef_status', 'mecef_uid', 'mecef_qr_ref', 'mecef_code', 'mecef_nim', 'mecef_compteurs', 'mecef_normalise_le', 'mecef_message']);
        });

        Schema::table('sales', function (Blueprint $table) {
            $table->dropColumn(['mecef_uid', 'mecef_code', 'mecef_nim', 'mecef_compteurs', 'mecef_normalise_le', 'mecef_message']);
        });
    }
};
