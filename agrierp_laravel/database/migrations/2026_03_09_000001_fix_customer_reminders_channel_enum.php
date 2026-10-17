<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * 🔴→✅ BUG PRÉ-EXISTANT TROUVÉ EN CONSTRUISANT `exportCourrierPdf()` :
 * `customer_reminders.channel` était `enum('whatsapp', 'email', 'appel')`
 * — mais `RelancesClients::sendSmsReminder()` (ticket 4.7, déjà en
 * production dans ce projet) journalise avec `channel = 'sms'`, une
 * valeur ABSENTE de cet enum. Toute relance SMS réellement envoyée
 * aurait donc échoué à l'écriture en base (violation de contrainte
 * enum), silencieusement pour l'utilisateur final (le SMS lui-même
 * partirait, seule la traçabilité échouerait). 'appel' n'est utilisé
 * nulle part dans le code réel — retiré, remplacé par 'sms' et
 * 'courrier' (ce dernier nécessaire pour ce ticket).
 */
return new class extends Migration
{
    public function up(): void
    {
        if (DB::getDriverName() === 'mysql') {
            DB::statement("ALTER TABLE customer_reminders MODIFY channel ENUM('whatsapp', 'email', 'sms', 'courrier') NOT NULL");

            return;
        }

        // SQLite (et autres) : pas d'ALTER COLUMN natif pour un enum
        // (stocké comme CHECK constraint) — recréation de la colonne en
        // simple chaîne, la validation applicative (déjà en place via les
        // seules valeurs réellement écrites par le code) suffit hors MySQL.
        Schema::table('customer_reminders', function ($table) {
            $table->string('channel_new', 20)->nullable()->after('channel');
        });
        DB::table('customer_reminders')->update(['channel_new' => DB::raw('channel')]);
        Schema::table('customer_reminders', function ($table) {
            $table->dropColumn('channel');
        });
        Schema::table('customer_reminders', function ($table) {
            $table->renameColumn('channel_new', 'channel');
        });
    }

    public function down(): void
    {
        if (DB::getDriverName() === 'mysql') {
            DB::statement("ALTER TABLE customer_reminders MODIFY channel ENUM('whatsapp', 'email', 'appel') NOT NULL");
        }
    }
};
