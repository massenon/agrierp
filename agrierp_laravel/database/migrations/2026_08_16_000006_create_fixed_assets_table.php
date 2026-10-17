<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 14.26 (Sprint 14) — registre des IMMOBILISATIONS.
 *
 * Aucune table ne suivait les immobilisations : la classe 2 n'existait au plan
 * comptable qu'a travers `281 Amortissements`, sans le moindre bien en face.
 * C'est la limite que la Note 2 des Etats Financiers signalait explicitement
 * (ticket 14.6) — « le plan comptable ne trace les immobilisations qu'au
 * niveau agrege de la classe 2, sans ventilation par nature d'actif qui
 * necessiterait des sous-comptes dedies ». Ce registre la leve.
 *
 * `account_code` rattache chaque bien a son compte de classe 2 (221 Batiments,
 * 241 Cages, 244 Broyeurs et equipements) : la ventilation par nature devient
 * une donnee reelle et non une hypothese.
 *
 * `residual_value` et `duration_years` portent l'amortissement LINEAIRE, la
 * seule methode citee par la Note 1 des Etats Financiers (« les
 * immobilisations sont amorties selon la methode lineaire »). `method` reste
 * une chaine — jamais un enum, ce projet a deja paye deux fois l'extension
 * d'un enum MySQL (ticket 14.2).
 *
 * Cession/reforme par changement de STATUT et date de sortie : jamais de
 * suppression physique d'un bien amorti, dont l'historique comptable doit
 * rester consultable (Document 00 §7).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('fixed_assets', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('code', 50)->unique();
            $table->string('label', 150);
            $table->string('account_code', 20);              // 221 / 241 / 244
            $table->date('acquisition_date');
            $table->decimal('acquisition_value', 14, 2);
            $table->decimal('residual_value', 14, 2)->default(0);
            $table->unsignedSmallInteger('duration_years');
            $table->string('method', 20)->default('lineaire');
            $table->string('status', 20)->default('en_service'); // en_service | cede | reforme
            $table->date('disposal_date')->nullable();
            $table->string('disposal_reason', 150)->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->index(['account_code', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('fixed_assets');
    }
};
