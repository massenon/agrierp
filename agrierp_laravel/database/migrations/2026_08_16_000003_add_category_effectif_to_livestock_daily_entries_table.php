<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 14.11 (Sprint 14) — effectifs par CATÉGORIE de rationnement.
 *
 * 🔴→✅ BUG RÉEL CORRIGÉ : `catEffRepro`/`catEffSevre`/`catEffJeune` de
 * `FicheLapins` (et `FichePorcs`) alimentent le calcul de rationnement, mais
 * n'étaient NI chargés par `loadDay()` NI sauvegardés par `saveDay()` — aucune
 * colonne n'existait pour les recevoir. Conséquence : remis à zéro à chaque
 * changement de jour et à chaque rechargement, l'animalier devait ressaisir
 * les trois effectifs quotidiennement et toute continuité jour-après-jour
 * était perdue. Ces 4 colonnes leur donnent enfin un support réel.
 *
 * 4 colonnes et non 3 : les Pondeuses suivent 4 stades (ticket à venir), et
 * le même schéma générique sert les 5 fiches — exactement le principe déjà
 * retenu pour `effectif_m`/`effectif_f`/`effectif_sevres`/`effectif_smeres`.
 *
 * ⚠️ Nullable, sans valeur par défaut : `null` signifie « jamais saisi »,
 * distinct de `0` qui signifie « catégorie réellement vide ». La différence
 * compte pour `getCatEffReproComputedProperty()`, qui ne doit repartir d'un
 * historique que s'il en existe un.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('livestock_daily_entries', function (Blueprint $table) {
            $table->unsignedInteger('cat_eff_repro')->nullable()->after('effectif_smeres');
            $table->unsignedInteger('cat_eff_sevre')->nullable()->after('cat_eff_repro');
            $table->unsignedInteger('cat_eff_jeune')->nullable()->after('cat_eff_sevre');
            $table->unsignedInteger('cat_eff_4')->nullable()->after('cat_eff_jeune');
        });
    }

    public function down(): void
    {
        Schema::table('livestock_daily_entries', function (Blueprint $table) {
            $table->dropColumn(['cat_eff_repro', 'cat_eff_sevre', 'cat_eff_jeune', 'cat_eff_4']);
        });
    }
};
