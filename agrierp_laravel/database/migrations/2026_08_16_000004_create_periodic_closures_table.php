<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 14.14 (Sprint 14) — Clôture Périodique (verrouillage mensuel léger).
 *
 * Onglet marqué « (nouveau) » dans le prototype source lui-même, jamais
 * implémenté. Distinct de la clôture ANNUELLE (`fiscal_years`) : il
 * n'affecte pas le Report à Nouveau et reste réversible par un
 * Administrateur — d'où les colonnes de déclôture, qui tracent l'exception
 * plutôt que de la faire disparaître en remettant simplement la ligne à zéro.
 *
 * `period` au format `YYYY-MM`, unique : un mois ne peut être clôturé qu'une
 * fois. Une déclôture est enregistrée SUR la ligne existante (dates et
 * auteurs conservés), jamais par suppression — l'historique d'une action
 * exceptionnelle doit rester consultable.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('periodic_closures', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('period', 7)->unique();          // YYYY-MM
            $table->timestamp('closed_at');
            $table->uuid('closed_by')->nullable();
            $table->timestamp('reopened_at')->nullable();
            $table->uuid('reopened_by')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('periodic_closures');
    }
};
