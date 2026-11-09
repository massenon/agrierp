<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket VOL-1 (04/11/2026) — VENTES PAR CATÉGORIE de la fiche « Volailles Reproducteurs ».
 *
 * Décision du client : l'effectif des volailles reproductrices est CALCULÉ par catégorie, comme pour les lapins et les
 * porcs (tickets 15.39 à 15.42). Contrairement aux lapins (où la vente sort toujours de la catégorie « Jeune »), la
 * vente des volailles sort de la catégorie DU PRODUIT vendu : trois colonnes de vente ventilée.
 *
 * Emplacements génériques, ceux des autres mouvements par catégorie (mort_*, don_*, cat_eff_*, cat_depart_*) :
 *   repro = Reproducteur ; sevre = Poussin ; jeune = Jeune (la catégorie « Poulet » d'avant le ticket).
 * `vente` reste la SOMME des trois (compatibilité : effectif total, rapports, poste ancien).
 *
 * NULLABLES, SANS défaut : `null` = non ventilé (fiche d'avant le ticket, ou autre espèce). Idempotente, `down()` n'enlève
 * que ces colonnes.
 */
return new class extends Migration
{
    private const COLONNES = ['vente_repro', 'vente_sevre', 'vente_jeune'];

    public function up(): void
    {
        $manquantes = array_values(array_filter(self::COLONNES, fn ($c) => ! Schema::hasColumn('livestock_daily_entries', $c)));

        if ($manquantes === []) {
            return;
        }

        Schema::table('livestock_daily_entries', function (Blueprint $table) use ($manquantes) {
            foreach ($manquantes as $colonne) {
                $table->unsignedInteger($colonne)->nullable();
            }
        });
    }

    public function down(): void
    {
        $presentes = array_values(array_filter(self::COLONNES, fn ($c) => Schema::hasColumn('livestock_daily_entries', $c)));

        if ($presentes === []) {
            return;
        }

        Schema::table('livestock_daily_entries', function (Blueprint $table) use ($presentes) {
            $table->dropColumn($presentes);
        });
    }
};
