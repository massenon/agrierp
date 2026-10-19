<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket U9 — `stock_movements` est servie au tirage du poste, au curseur `updated_at` (`SyncController::pull`).
 * La table n'avait qu'un index (`product_id`, `movement_date`) : chaque tirage incrémental la parcourait en entier.
 * Elle croît d'une ligne par ligne de vente, ligne d'achat, ponte et ajustement ; l'index garde le tirage
 * incrémental proportionnel à ce qui a changé. Aucune donnée n'est modifiée, et le schéma du poste n'est pas touché
 * (un index n'est pas une colonne synchronisée).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('stock_movements', function (Blueprint $table) {
            $table->index('updated_at');
        });
    }

    public function down(): void
    {
        Schema::table('stock_movements', function (Blueprint $table) {
            $table->dropIndex(['updated_at']);
        });
    }
};
