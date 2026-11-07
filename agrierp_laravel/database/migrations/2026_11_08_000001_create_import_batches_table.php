<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket IMPORT-1 — JOURNAL DE L'IMPORTATION EN MASSE (web).
 *
 * Une ligne par fichier présenté : module, version du modèle, nom et empreinte SHA-256 du fichier, auteur, compteurs et
 * statut (`apercu` tant que rien n'est écrit, `termine` après la confirmation, `annule`). Table du SERVEUR seulement :
 * elle ne se synchronise pas (le poste n'en tient pas de copie, voir `agrierp_flutter/CLAUDE.md`, IMPORT-1).
 *
 * `lignes` porte les valeurs lues et l'état de chaque ligne le temps de l'aperçu ; à la fin de l'import elle ne garde
 * que les valeurs des lignes REFUSÉES (pour le rapport à corriger) — jamais celles des fiches créées.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('import_batches', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('module', 30);
            $table->unsignedSmallInteger('version_modele');
            $table->string('nom_fichier', 255);
            $table->string('empreinte', 64);
            $table->string('statut', 12)->default('apercu');
            $table->unsignedInteger('lues')->default(0);
            $table->unsignedInteger('valides')->default(0);
            $table->unsignedInteger('ignorees')->default(0);
            $table->unsignedInteger('refusees')->default(0);
            $table->unsignedInteger('creees')->default(0);
            $table->string('avertissement', 500)->nullable();
            $table->longText('lignes')->nullable();
            $table->longText('rapport')->nullable();
            $table->timestamp('termine_le')->nullable();
            $table->timestamps();

            $table->index(['module', 'empreinte']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('import_batches');
    }
};
