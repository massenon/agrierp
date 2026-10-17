<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 14.44 (Sprint 14) — LA BANDE VENDUE, ENFIN CONSERVÉE SUR LA VENTE.
 *
 * `PosInterface::confirmWeightAdd()` EXIGE déjà la bande source pour tout
 * produit lié à une espèce (contrôle de rémanence vétérinaire) et
 * `recordFicheVente()` s'en sert pour décrémenter l'effectif du jour. Mais
 * cette information restait dans le panier, en mémoire : la ligne de vente
 * enregistrée ne la portait pas.
 *
 * Conséquence : le Bilan Technico-Économique ne pouvait chiffrer AUCUN revenu
 * par bande — non par absence de ventes, mais parce que le lien vente→bande
 * n'était nulle part persisté. Le rapprocher après coup aurait exigé une
 * heuristique (FIFO, répartition au prorata) ; l'information exacte existait
 * déjà au moment de la vente, il suffisait de l'écrire.
 *
 * ⚠️ NULLABLE PAR NATURE, ET SANS CONTRAINTE DE SUPPRESSION EN CASCADE : la
 * plupart des lignes de vente ne concernent aucune bande (provende, œufs,
 * intrants). Et une bande archivée ne doit jamais emporter l'historique
 * commercial avec elle — `nullOnDelete()`, jamais `cascadeOnDelete()`.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('sale_lines', function (Blueprint $table) {
            $table->foreignUuid('lot_id')->nullable()->after('product_id')
                ->constrained('livestock_lots')->nullOnDelete();
            $table->index('lot_id');
        });
    }

    public function down(): void
    {
        Schema::table('sale_lines', function (Blueprint $table) {
            $table->dropForeign(['lot_id']);
            $table->dropIndex(['lot_id']);
            $table->dropColumn('lot_id');
        });
    }
};
