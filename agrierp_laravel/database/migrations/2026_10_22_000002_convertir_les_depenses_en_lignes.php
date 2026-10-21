<?php

use App\Services\ConversionDepensesEnLignes;
use Illuminate\Database\Migrations\Migration;

/**
 * Ticket DEP1 — CHAQUE ANCIENNE DÉPENSE DEVIENT 1 EN-TÊTE + 1 LIGNE, sans en perdre aucune (EF11). Voir
 * `ConversionDepensesEnLignes` : compte de charge déduit de l'ancienne catégorie (la même règle que la comptabilisation
 * d'origine), 628 « Autres charges » à défaut, journalisé ; les pièces comptables déjà passées ne sont JAMAIS touchées.
 * Idempotente : une dépense qui a déjà ses lignes n'est pas reconvertie.
 */
return new class extends Migration
{
    public function up(): void
    {
        ConversionDepensesEnLignes::convertir();
    }

    public function down(): void
    {
        // Rien à défaire : les lignes se suppriment avec la table (migration précédente).
    }
};
