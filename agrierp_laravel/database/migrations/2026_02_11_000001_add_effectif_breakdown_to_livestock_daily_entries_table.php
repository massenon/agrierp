<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ÉCART DE SCHÉMA CONFIRMÉ (ticket 3.5) : `RESPECT_TABLEAU_MENSUEL_DES_31_
 * JOURS_DESKTOP_POUR_CHAQUE_FICHE_ELEVAGE.md` documente un groupe "Effectif
 * Final du Jour" à 5 sous-colonnes (M, F, Sevrés, S/Mères, Total) pour la
 * Variante A (Lapins/Porcs/Volailles Reproducteurs/Escargots) — confirmé
 * par lecture directe de `fiche-lapins.html` lignes 450-454. Le schéma
 * documenté (`FULL_MIGRATIONS_DATABASE.md` §7) ne porte qu'un seul champ
 * agrégé `effectif_final`. Colonnes de ventilation ajoutées en extension
 * mineure (nullables, n'affectent aucune donnée existante) plutôt que de
 * perdre cette fidélité réelle du tableau mensuel.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('livestock_daily_entries', function (Blueprint $table) {
            $table->unsignedInteger('effectif_m')->nullable()->after('effectif_final');
            $table->unsignedInteger('effectif_f')->nullable()->after('effectif_m');
            $table->unsignedInteger('effectif_sevres')->nullable()->after('effectif_f');
            $table->unsignedInteger('effectif_smeres')->nullable()->after('effectif_sevres');
        });
    }

    public function down(): void
    {
        Schema::table('livestock_daily_entries', function (Blueprint $table) {
            $table->dropColumn(['effectif_m', 'effectif_f', 'effectif_sevres', 'effectif_smeres']);
        });
    }
};
