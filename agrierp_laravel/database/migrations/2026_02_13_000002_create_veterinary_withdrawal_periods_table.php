<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Mécanique réelle de la rémanence vétérinaire (message de lancement du
 * projet, règle URGENTE) : chaque soin enregistré avec un délai de
 * rémanence > 0 (ticket 3.11, `SoinsVaccinsHub::saveSoin()`) crée une
 * ligne ici. Le blocage réel à la vente (Sprint 4, POS) interrogera cette
 * table par `lot_id` + `end_date >= aujourd'hui` — index déjà prévu à
 * cet effet ("requetee a chaque vente POS", commentaire du document source).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('veterinary_withdrawal_periods', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('lot_id')->constrained('livestock_lots')->restrictOnDelete();
            $table->string('product_used', 150);
            $table->date('start_date');
            $table->unsignedSmallInteger('withdrawal_days');
            $table->date('end_date');
            $table->foreignUuid('triggered_by_daily_entry_id')->nullable();
            $table->timestamps();
            $table->index(['lot_id', 'end_date']);

            // 🔴→✅ BUG MYSQL RÉEL TROUVÉ AU PREMIER `migrate:fresh` LOCAL :
            // le nom de contrainte auto-généré par Laravel
            // (`veterinary_withdrawal_periods_triggered_by_daily_entry_id_foreign`)
            // fait 65 caractères — 1 de plus que la limite MySQL de 64
            // pour un identifiant. Nom explicite raccourci en remplacement.
            $table->foreign('triggered_by_daily_entry_id', 'vwp_triggered_by_entry_foreign')
                ->references('id')->on('livestock_daily_entries')
                ->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('veterinary_withdrawal_periods');
    }
};
