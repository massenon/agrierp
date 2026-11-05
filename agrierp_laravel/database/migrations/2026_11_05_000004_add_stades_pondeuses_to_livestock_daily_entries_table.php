<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket VOL-2 (05/11/2026) — QUATRIÈME EMPLACEMENT ET PASSAGES SUPPLÉMENTAIRES de la fiche « Volailles Pondeuses ».
 *
 * Décision du client : l'effectif des pondeuses est CALCULÉ par stade, comme celui des reproductrices (VOL-1), des lapins
 * et des porcs. Quatre stades — Poussin ponte, Poussin en croissance, Poulette, Pondeuse — pour trois emplacements
 * génériques existants (`repro`, `sevre`, `jeune`) : il en faut un quatrième. `cat_eff_4` existait déjà (sans usage) ;
 * on AJOUTE (jamais de renommage : le contrat /api/sync/* ne casse aucun nom de clé) :
 *   - le quatrième emplacement = Poussin ponte : `mort_4`, `don_4`, `vente_4`, `cat_depart_4` ;
 *   - deux passages : `passage_4_sevre` (Poussin ponte → Poussin en croissance) et `passage_jeune_repro` (Poulette →
 *     Pondeuse). Poussin en croissance → Poulette reste `passage_sevre_jeune` ;
 *   - les transferts entre bandes du quatrième emplacement : `transfert_entree_4`, `transfert_sortie_4` (dérivés, à 0).
 * NULLABLES sans défaut (`null` = non ventilé : fiche d'avant le ticket, ou autre espèce), sauf les deux transferts,
 * dérivés comme les autres (NOT NULL à 0). Idempotente ; `down()` n'enlève que ces colonnes.
 */
return new class extends Migration
{
    private const NULLABLES = ['mort_4', 'don_4', 'vente_4', 'cat_depart_4', 'passage_4_sevre', 'passage_jeune_repro'];

    private const TRANSFERTS = ['transfert_entree_4', 'transfert_sortie_4'];

    public function up(): void
    {
        $manque = fn (array $colonnes) => array_values(array_filter($colonnes, fn ($c) => ! Schema::hasColumn('livestock_daily_entries', $c)));
        $nullables = $manque(self::NULLABLES);
        $transferts = $manque(self::TRANSFERTS);

        if ($nullables === [] && $transferts === []) {
            return;
        }

        Schema::table('livestock_daily_entries', function (Blueprint $table) use ($nullables, $transferts) {
            foreach ($nullables as $colonne) {
                $table->unsignedInteger($colonne)->nullable();
            }
            foreach ($transferts as $colonne) {
                $table->unsignedInteger($colonne)->default(0);
            }
        });
    }

    public function down(): void
    {
        $presentes = array_values(array_filter(
            array_merge(self::NULLABLES, self::TRANSFERTS),
            fn ($c) => Schema::hasColumn('livestock_daily_entries', $c),
        ));

        if ($presentes === []) {
            return;
        }

        Schema::table('livestock_daily_entries', function (Blueprint $table) use ($presentes) {
            $table->dropColumn($presentes);
        });
    }
};
