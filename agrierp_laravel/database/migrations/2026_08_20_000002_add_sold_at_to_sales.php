<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * 🔴🔴 TICKET 14.71 — LA DATE D'UNE VENTE HORS LIGNE N'EXISTAIT NULLE PART.
 *
 * `sales` ne portait AUCUNE date de vente : seulement `created_at`, posée par
 * Eloquent au moment de l'INSERT. Pour une vente saisie au comptoir, les deux
 * coïncident et rien ne se voit. Pour une vente encaissée **hors ligne** puis
 * remontée par `POST /api/sync/push`, la date enregistrée est celle du
 * **tirage**, pas celle de la vente.
 *
 * Le poste, lui, tient bien l'heure réelle (`sales.sold_at` en base Drift) —
 * il ne l'envoyait pas, et le serveur n'aurait pas su où la mettre.
 *
 * ⚠️ TROIS CONSÉQUENCES, TOUTES SILENCIEUSES :
 *   1. **Écriture SYSCOHADA datée du tirage.**
 *      `RecordSaleAccountingEntryAction` prend `$sale->created_at`. Une vente
 *      du 28/07 remontée le 02/08 tombe donc sur l'exercice comptable du mois
 *      d'août. Pour un comptable béninois, c'est un produit imputé à la
 *      mauvaise période — et la balance des deux mois est fausse.
 *   2. **Fiche d'élevage du mauvais jour.** `pushSales` appelait
 *      `RecordSaleOnFicheElevageAction::execute($lignes)` SANS date, donc
 *      `now()` : les têtes vendues étaient déduites de la fiche du jour du
 *      tirage. La fiche du jour réel de la vente restait, elle, incohérente.
 *   3. CA du tableau de bord et courbe « 6 derniers mois » datés du tirage.
 *
 * Colonne rendue nullable et **rétro-remplie depuis `created_at`** : pour tout
 * l'historique, la vente a bien eu lieu à sa création (aucune vente hors ligne
 * n'a encore été remontée sur cette base). Le code lit `sold_at ?? created_at`,
 * de sorte qu'une ligne ancienne se comporte exactement comme avant.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('sales', function (Blueprint $table) {
            $table->timestamp('sold_at')->nullable()->after('status');
        });

        // Rétro-remplissage : l'historique conserve exactement sa date.
        DB::table('sales')->whereNull('sold_at')->update([
            'sold_at' => DB::raw('created_at'),
        ]);
    }

    public function down(): void
    {
        Schema::table('sales', function (Blueprint $table) {
            $table->dropColumn('sold_at');
        });
    }
};
