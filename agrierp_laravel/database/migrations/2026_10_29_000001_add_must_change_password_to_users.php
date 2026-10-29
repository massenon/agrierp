<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket MDP-1 — CHANGEMENT DE MOT DE PASSE OBLIGATOIRE À LA PREMIÈRE CONNEXION.
 *
 * Décision du client : plus de réinitialisation par e-mail ; un administrateur choisit un mot de passe TEMPORAIRE
 * (`SaisieUtilisateurAction::reinitialiserMotDePasse`) et le compte est marqué ici. Tant que la colonne est vraie, le
 * web (middleware `ChangementMotDePasseObligatoire`) et l'API du poste (`ChangementMotDePasseObligatoireApi`) refusent
 * tout sauf le changement de mot de passe ; le changement réussi la remet à faux.
 *
 * ⚠️ MIGRATION SÛRE SUR UNE BASE PEUPLÉE : `NOT NULL` avec défaut faux, les comptes existants ne sont pas touchés.
 * Hors `$fillable` (jamais posée par un formulaire). Descend au poste (colonne `utilisateurs.must_change_password`,
 * affichage de la liste), le mot de passe, lui, jamais.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->boolean('must_change_password')->default(false);
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('must_change_password');
        });
    }
};
