<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ÉCART DOCUMENTÉ (ticket 4.3) : aucune table `quotes` n'existe dans
 * `FULL_MIGRATIONS_DATABASE.md`. Conçue à partir de la lecture réelle du
 * formulaire "Nouveau Devis" (`devis.html`) : un devis y est une
 * description libre des prestations (`devis-articles`, texte libre — pas
 * une liste structurée de lignes produit comme `sale_lines`) + un montant
 * global unique + une TVA + une validité en jours. Cohérent avec la
 * nature technique des devis (cages sur mesure, prestations sur mesure)
 * — pas de table `quote_lines` créée, elle ne correspondrait à aucun
 * champ réel du formulaire source.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('quotes', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('quote_number', 30)->unique();
            $table->foreignUuid('customer_id')->nullable()->constrained('customers')->nullOnDelete();
            $table->text('articles_description');
            $table->decimal('amount', 14, 2);
            $table->decimal('tva_rate', 5, 2)->default(0);
            $table->unsignedSmallInteger('validity_days')->default(15);
            $table->date('quote_date');
            $table->text('note')->nullable();
            $table->enum('status', ['brouillon', 'envoye', 'accepte', 'refuse', 'facture'])->default('brouillon');
            $table->uuid('converted_sale_id')->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('quotes');
    }
};
