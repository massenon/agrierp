<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ÉCART DOCUMENTÉ : aucune table pour les modèles d'attestation
 * n'existe dans le schéma documenté. Table dédiée (2 lignes réelles,
 * type employé/stagiaire) plutôt qu'une extension de `company_settings`
 * (ticket 4.7) — ce sont des modèles de document, pas des paramètres
 * globaux de l'entreprise.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('attestation_templates', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->enum('type', ['employe', 'stagiaire'])->unique();
            $table->text('body_text');
            $table->string('format', 20)->default('A4 Paysage');
            $table->boolean('show_watermark')->default(true);
            $table->boolean('show_header')->default(true);
            $table->boolean('show_signature')->default(true);
            $table->boolean('show_stamp')->default(false);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('attestation_templates');
    }
};
