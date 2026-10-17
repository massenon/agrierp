<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 15.46 — TRANSFERT ENTRE BANDES (A2, décision client du 17/10/2026 : écran dédié, bandes déjà saisies
 * corrigées).
 *
 * 🔴 Aucun mouvement ne faisait passer des sujets d'une bande à l'autre. Les nés d'une portée, comptés dans la
 * bande mère (`ne`), étaient recomptés dans la nouvelle bande créée pour eux (`initial_quantity`) : « Effectif
 * Total Vivant » les comptait DEUX fois.
 *
 * - `livestock_transfers` est la SOURCE DE VÉRITÉ d'un transfert (UUID, archivage logique : un transfert est
 *   annulé, jamais supprimé). `constitution` = la bande cible a été créée avec ces sujets : son effectif initial
 *   les compte déjà, seule la sortie de la bande source est inscrite (c'est la correction des bandes existantes).
 * - Les colonnes `transfert_*` des fiches sont DÉRIVÉES de cette table (comme `effectif_final`) : jamais saisies,
 *   jamais reprises du poste. Totaux NOT NULL à 0 : une fiche sans transfert garde exactement son effectif.
 *   Ventilation par catégorie (repro / sevre / jeune) pour les bandes à chaîne (lapins, porcs).
 * - `livestock_lots.lot_source_id` : la bande d'origine d'une bande constituée à partir d'une autre.
 */
return new class extends Migration
{
    private const COLONNES_FICHE = [
        'transfert_entree', 'transfert_sortie',
        'transfert_entree_repro', 'transfert_entree_sevre', 'transfert_entree_jeune',
        'transfert_sortie_repro', 'transfert_sortie_sevre', 'transfert_sortie_jeune',
    ];

    public function up(): void
    {
        if (! Schema::hasTable('livestock_transfers')) {
            Schema::create('livestock_transfers', function (Blueprint $table) {
                $table->uuid('id')->primary();
                $table->foreignUuid('source_lot_id')->constrained('livestock_lots')->restrictOnDelete();
                $table->foreignUuid('target_lot_id')->constrained('livestock_lots')->restrictOnDelete();
                $table->date('transfer_date');
                $table->unsignedInteger('quantity');
                $table->enum('categorie', ['repro', 'sevre', 'jeune'])->nullable();
                $table->boolean('constitution')->default(false);
                $table->string('motif', 255)->nullable();
                $table->foreignUuid('user_id')->nullable()->constrained('users')->nullOnDelete();
                $table->string('device_id', 64)->nullable();
                $table->boolean('is_active')->default(true);
                $table->timestamps();

                $table->index(['source_lot_id', 'transfer_date']);
                $table->index(['target_lot_id', 'transfer_date']);
            });
        }

        $manquantes = array_values(array_filter(
            self::COLONNES_FICHE,
            fn ($c) => ! Schema::hasColumn('livestock_daily_entries', $c),
        ));
        if ($manquantes !== []) {
            Schema::table('livestock_daily_entries', function (Blueprint $table) use ($manquantes) {
                foreach ($manquantes as $colonne) {
                    $table->unsignedInteger($colonne)->default(0);
                }
            });
        }

        if (! Schema::hasColumn('livestock_lots', 'lot_source_id')) {
            Schema::table('livestock_lots', function (Blueprint $table) {
                $table->foreignUuid('lot_source_id')->nullable()->constrained('livestock_lots')->nullOnDelete();
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('livestock_lots', 'lot_source_id')) {
            Schema::table('livestock_lots', function (Blueprint $table) {
                $table->dropConstrainedForeignId('lot_source_id');
            });
        }

        $presentes = array_values(array_filter(
            self::COLONNES_FICHE,
            fn ($c) => Schema::hasColumn('livestock_daily_entries', $c),
        ));
        if ($presentes !== []) {
            Schema::table('livestock_daily_entries', function (Blueprint $table) use ($presentes) {
                $table->dropColumn($presentes);
            });
        }

        Schema::dropIfExists('livestock_transfers');
    }
};
