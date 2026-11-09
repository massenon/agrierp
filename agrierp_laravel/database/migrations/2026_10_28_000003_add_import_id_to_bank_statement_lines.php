<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket CP-5 — un relevé importé depuis un poste porte l'UUID de son import : rejouer l'envoi (réponse perdue) ne doit pas
 * dupliquer ses lignes. `null` pour un relevé importé au web.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('bank_statement_lines', function (Blueprint $table) {
            $table->uuid('import_id')->nullable()->after('account_id')->index();
        });
    }

    public function down(): void
    {
        Schema::table('bank_statement_lines', function (Blueprint $table) {
            $table->dropColumn('import_id');
        });
    }
};
