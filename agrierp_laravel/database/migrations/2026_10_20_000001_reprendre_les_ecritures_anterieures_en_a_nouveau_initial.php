<?php

use App\Services\AnouveauInitialService;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket EX1 (question Q7) — migration de DONNÉES, idempotente : les écritures datées avant le premier exercice
 * (reprises d'avant le logiciel) deviennent un à-nouveau initial `ran` au premier jour du premier exercice
 * (`AnouveauInitialService`). Sans elles, rien n'est écrit. Relancée, elle n'écrit que l'écart restant (aucun en
 * pratique). Aucun schéma n'est touché : rien à défaire au `down()` (l'écriture, comptable, ne s'efface pas).
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('accounting_entries') || ! Schema::hasTable('fiscal_years')) {
            return;
        }

        app(AnouveauInitialService::class)->regulariser();
    }

    public function down(): void
    {
        // Rien : une écriture comptable ne se supprime pas (elle se contre-passe au Journal).
    }
};
