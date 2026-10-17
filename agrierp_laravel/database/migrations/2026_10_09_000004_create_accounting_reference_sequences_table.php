<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 15.20a — numérotation des écritures : un compteur par journal et par exercice.
 *
 * `AccountingEntry::generateReference()` relisait les 4 derniers caractères de la dernière
 * référence ; dès qu'une référence se terminait par un libellé, le numéro suivant valait
 * toujours 0001. Le numéro est désormais attribué DANS la transaction d'enregistrement de
 * l'écriture, depuis cette table, sous verrou : annulée avec elle, jamais de trou ; lue sous
 * verrou, jamais de doublon.
 *
 * Aucune ligne n'est semée ici : le compteur d'un exercice est amorcé au premier usage, depuis
 * le plus grand numéro déjà présent dans les références (voir AccountingEntry::attribuerNumero).
 * Aucune écriture existante n'est renumérotée.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('accounting_reference_sequences', function (Blueprint $table) {
            $table->string('journal', 10);
            $table->foreignUuid('fiscal_year_id')->constrained('fiscal_years');
            $table->unsignedInteger('last_number')->default(0);
            $table->primary(['journal', 'fiscal_year_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('accounting_reference_sequences');
    }
};
