<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * ÉCART DOCUMENTÉ (Feuille de Pointage, Sprint 8) : `attendance_records.status`
 * (§18) n'admet que `present/absent/conge/maladie` — le formulaire réel
 * de pointage propose Présent/Absent/Retard/Congé, "retard" n'existant
 * nulle part dans le schéma documenté. Enum étendu (maladie conservée,
 * documentée et potentiellement utile ailleurs, jamais supprimée sans
 * raison).
 *
 * 🔴→✅ TROUVÉ AU TICKET 14.1 : même incompatibilité SQLite que
 * `2026_02_20_000003_add_sms_to_customer_reminders_channel_enum` — voir le
 * docblock de cette migration-là pour le détail. Corrigé de la même façon,
 * les deux occurrences traitées ensemble plutôt qu'au fil des découvertes.
 */
return new class extends Migration
{
    public function up(): void
    {
        if ($this->isMysql()) {
            DB::statement("ALTER TABLE attendance_records MODIFY COLUMN status ENUM('present', 'absent', 'conge', 'maladie', 'retard') NOT NULL DEFAULT 'present'");

            return;
        }

        Schema::table('attendance_records', function (Blueprint $table) {
            $table->string('status')->default('present')->nullable(false)->change();
        });
    }

    public function down(): void
    {
        if ($this->isMysql()) {
            DB::statement("ALTER TABLE attendance_records MODIFY COLUMN status ENUM('present', 'absent', 'conge', 'maladie') NOT NULL DEFAULT 'present'");
        }
    }

    private function isMysql(): bool
    {
        return in_array(DB::connection()->getDriverName(), ['mysql', 'mariadb'], true);
    }
};
