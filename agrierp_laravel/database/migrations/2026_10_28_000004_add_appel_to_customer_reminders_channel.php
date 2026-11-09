<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Ticket AUT-3 — le canal « appel » (numéro composé depuis l'appareil, `tel:`) remplace le SMS pour les nouvelles relances.
 *
 * ⚠️ `sms` RESTE dans l'énumération MySQL : les relances déjà journalisées par SMS se lisent toujours. SQLite (et les autres)
 * stockent déjà ce canal en chaîne libre (migration du 2026-03-09).
 */
return new class extends Migration
{
    public function up(): void
    {
        if (DB::getDriverName() === 'mysql') {
            DB::statement("ALTER TABLE customer_reminders MODIFY channel ENUM('whatsapp', 'email', 'sms', 'appel', 'courrier') NOT NULL");
        }
    }

    public function down(): void
    {
        if (DB::getDriverName() === 'mysql') {
            DB::statement("ALTER TABLE customer_reminders MODIFY channel ENUM('whatsapp', 'email', 'sms', 'courrier') NOT NULL");
        }
    }
};
