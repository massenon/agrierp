<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ÉCART DOCUMENTÉ (ticket 5.8) : aucune table `expenses` n'existe dans le
 * schéma documenté. Conçue à partir des champs réels du formulaire
 * "Nouvelle Dépense" (`saisie-depenses.html`) : date, libellé, catégorie
 * SYSCOHADA (Classe 6, texte libre — la liste affichée n'est qu'un
 * échantillon indicatif, pas un référentiel fermé documenté ailleurs),
 * montant, compte de trésorerie débité, justificatif photo optionnel.
 *
 * Pas de champ Fixe/Variable dans le formulaire source malgré les KPI
 * "Charges Fixes"/"Charges Variables" affichés — voir le composant Livewire
 * pour la décision associée (KPI laissés en attente, aucune règle de
 * classification fiable trouvée dans le prototype).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('expenses', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->date('expense_date');
            $table->string('label', 255);
            $table->string('category', 100);
            $table->decimal('amount', 14, 2);
            $table->foreignUuid('treasury_account_id')->constrained('treasury_accounts')->restrictOnDelete();
            $table->string('receipt_path', 255)->nullable();
            $table->enum('status', ['payee', 'en_attente'])->default('payee');
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('expenses');
    }
};
