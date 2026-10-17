<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 15.20b — index sur `accounting_entries.reference`.
 *
 * `AccountingEntry::attribuerNumero()` relit, à chaque attribution, les références du préfixe
 * `OD-AAAA-` situées après le compteur (plage + LIKE 'préfixe%'). Sans index, c'est un parcours
 * complet de la table à chaque écriture. Index NON unique : des doublons passés existent peut-être
 * en production (voir 15.20a), une contrainte d'unicité ferait échouer la migration.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('accounting_entries', function (Blueprint $table) {
            $table->index('reference', 'accounting_entries_reference_index');
        });
    }

    public function down(): void
    {
        Schema::table('accounting_entries', function (Blueprint $table) {
            $table->dropIndex('accounting_entries_reference_index');
        });
    }
};
