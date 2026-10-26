<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket DEV3 — UNE FACTURE NE PEUT ÊTRE LA FACTURE QUE D'UN SEUL DEVIS. `quotes.converted_sale_id` (nullable, posé
 * depuis le ticket 4.3 mais jamais écrit) porte le lien devis → facture ; l'index unique est la dernière ligne de
 * défense de l'idempotence de la conversion (la première est le verrou du devis dans `ConvertirDevisEnFactureAction`).
 * Plusieurs NULL cohabitent (un devis non converti n'a pas de lien) : MySQL, MariaDB et SQLite l'admettent.
 *
 * Aucune donnée n'existe à corriger : la colonne n'était écrite par aucun chemin avant le ticket DEV3.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('quotes', function (Blueprint $table) {
            $table->unique('converted_sale_id', 'quotes_converted_sale_id_unique');
        });
    }

    public function down(): void
    {
        Schema::table('quotes', function (Blueprint $table) {
            $table->dropUnique('quotes_converted_sale_id_unique');
        });
    }
};
