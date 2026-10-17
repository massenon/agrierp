<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ⚠️ ÉCART RÉEL DÉCOUVERT (ticket 3.14) : le champ "Coût d'Acquisition
 * (FCFA)" existait déjà dans le formulaire de création de bande
 * (`GestionBandes`, ticket 3.3, fidèle au champ du modal de création de
 * bande du prototype) mais n'était ni stocké dans le schéma
 * (`livestock_lots`) ni réellement sauvegardé par `saveLot()` — un
 * formulaire qui semblait complet mais perdait silencieusement cette
 * valeur. Découvert seulement maintenant car
 * `bilan-technico-economique.html` (ce ticket) en a besoin pour la ligne
 * de coût "Acquisition initiale". Corrigé ici : colonne ajoutée +
 * `GestionBandes::saveLot()` mis à jour pour la persister réellement.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('livestock_lots', function (Blueprint $table) {
            $table->decimal('acquisition_cost', 14, 2)->nullable()->after('created_date');
        });
    }

    public function down(): void
    {
        Schema::table('livestock_lots', function (Blueprint $table) {
            $table->dropColumn('acquisition_cost');
        });
    }
};
