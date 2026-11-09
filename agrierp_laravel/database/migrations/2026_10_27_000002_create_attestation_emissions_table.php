<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ATT-3 — ATTESTATIONS FABRIQUÉES AU POSTE : le serveur garde le NUMÉRO attribué à chaque émission.
 *
 * Le poste produit lui-même le PDF (hors ligne comprise) ; le serveur reste l'autorité du numéro
 * (`N°04/2026/FEO/DG`) et de la trace d'audit. La clé primaire est l'identifiant d'émission généré PAR LE POSTE (UUID) :
 * rejouer un envoi (réponse perdue, émission restée en file hors ligne) retrouve la même ligne, donc le même numéro,
 * et ne compte qu'une fois. Le numéro est FIGÉ ici, jamais recalculé : un rang déduit des dates changerait avec
 * l'arrivée tardive d'une émission faite hors ligne et donnerait deux fois le même numéro.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('attestation_emissions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->enum('type', ['employe', 'stagiaire']);
            $table->string('numero', 40);
            $table->dateTime('issued_at');
            $table->uuid('user_id')->nullable();
            $table->timestamps();

            $table->unique('numero');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('attestation_emissions');
    }
};
