<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 14.37 (Sprint 14) — la bande sait enfin CE QU'ELLE PRODUIT.
 *
 * 🔴 GAP REVELE PAR LA SIMULATION (ticket 14.31) : une naissance augmentait
 * l'effectif de la bande, mais AUCUN flux ne faisait entrer le sujet en stock
 * vendable. Une ferme qui eleve ses propres animaux ne pouvait donc jamais les
 * vendre au-dela de son inventaire d'ouverture. Le prototype montre pourtant la
 * ligne attendue dans son journal des mouvements :
 *     « Lapereau sevre | Entree | Naissance | +6 »
 *
 * ⚠️ POURQUOI UN LIEN SUR LA BANDE, ET NON UNE CONVENTION PAR ESPECE. Une
 * espece correspond a PLUSIEURS produits (aviculture : poulet vif, oeufs,
 * poussin, abattu, fume, braise) et deux bandes de meme espece n'ont pas la
 * meme destination — c'est exactement le cas de cette exploitation, ou
 * AVI-2026-01 pond des oeufs pendant qu'AVI-2026-02 produit du poulet vif.
 * Aucune regle deduite de l'espece ne peut exprimer cela ; le lien doit etre
 * porte par la bande.
 *
 * NULLABLE : une bande sans produit rattache ne genere simplement aucun
 * mouvement de stock — l'exploitation reste libre de ne pas s'en servir, et
 * les bandes existantes ne sont pas invalidees.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('livestock_lots', function (Blueprint $table) {
            $table->foreignUuid('product_id')->nullable()->after('species_id')
                ->constrained('products')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('livestock_lots', function (Blueprint $table) {
            $table->dropForeign(['product_id']);
            $table->dropColumn('product_id');
        });
    }
};
