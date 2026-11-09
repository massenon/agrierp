<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket VOL-2 (05/11/2026) — la catégorie d'un transfert entre bandes admet le QUATRIÈME emplacement (`quatre` = Poussin
 * ponte des volailles pondeuses), en plus de `repro`, `sevre` et `jeune`. Aucune ligne existante n'est modifiée.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('livestock_transfers')) {
            return;
        }

        Schema::table('livestock_transfers', function (Blueprint $table) {
            $table->enum('categorie', ['repro', 'sevre', 'jeune', 'quatre'])->nullable()->change();
        });
    }

    public function down(): void
    {
        if (! Schema::hasTable('livestock_transfers')) {
            return;
        }

        // Un transfert déjà rangé dans le quatrième emplacement ne tient plus dans l'ancienne liste : on le rend « sans catégorie ».
        \Illuminate\Support\Facades\DB::table('livestock_transfers')->where('categorie', 'quatre')->update(['categorie' => null]);

        Schema::table('livestock_transfers', function (Blueprint $table) {
            $table->enum('categorie', ['repro', 'sevre', 'jeune'])->nullable()->change();
        });
    }
};
