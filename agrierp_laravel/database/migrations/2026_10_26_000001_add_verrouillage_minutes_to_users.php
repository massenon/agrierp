<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Sprint VW (VW1) — DURÉE D'INACTIVITÉ AVANT LE VERROUILLAGE AUTOMATIQUE, PAR UTILISATEUR.
 *
 * Décision du client (26/10/2026) : le verrou de session du poste (VL-1/VL-2) existe aussi sur le web. Le réglage est
 * tenu SUR LE SERVEUR (et non dans le navigateur) pour suivre la personne d'un navigateur à l'autre.
 *
 * ⚠️ MIGRATION SÛRE SUR UNE BASE PEUPLÉE : colonne `NOT NULL` AVEC valeur par défaut (5 minutes, celle du poste) ; les
 * comptes existants la reçoivent d'office, rien n'est réécrit. `0` signifie « Jamais ». Les valeurs admises
 * (0, 1, 5, 15, 30) sont validées à l'écriture (Mon Profil) et relues avec repli sur 5 (`User::delaiVerrouillage()`),
 * pas par une contrainte de base : le jeu de durées peut évoluer sans migration.
 *
 * ⚠️ NON SYNCHRONISÉE : `SyncController` ne donne pas cette colonne au poste (liste de colonnes explicite pour `users`),
 * qui a son propre réglage au coffre. Aucune migration Drift.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->unsignedSmallInteger('verrouillage_minutes')->default(5);
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('verrouillage_minutes');
        });
    }
};
