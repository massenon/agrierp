<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 14.38 (Sprint 14) — bareme progressif de l'IR-PTS / ITS (Benin).
 *
 * Impot sur les Traitements et Salaires : retenu a la source par l'employeur,
 * calcule par TRANCHES sur le revenu net imposable (apres deduction des
 * cotisations sociales salariales).
 *
 * ⚠️ TABLE PLUTOT QUE CONSTANTES EN DUR. Un bareme fiscal change par voie de
 * loi de finances : le figer dans le code obligerait a redeployer
 * l'application a chaque revision, et surtout rendrait invisible la version
 * reellement appliquee a un bulletin. Ici le comptable voit le bareme, et
 * peut le corriger sans developpeur.
 *
 * ⚠️ Le bareme seme doit etre VALIDE PAR LE CLIENT avant toute paie reelle :
 * ni le prototype ni le CDC ne le documentent.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('income_tax_brackets', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->decimal('from_amount', 14, 2);
            $table->decimal('to_amount', 14, 2)->nullable();   // null = tranche superieure
            $table->decimal('rate', 5, 2);
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->index('from_amount');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('income_tax_brackets');
    }
};
