<?php

use App\Services\Elevage\ReleveTerrainService;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket RELEVES-1 (08/11/2026) — ONGLET « RELEVÉS DE TERRAIN » de Paramètres Élevage : UNE table,
 * `field_survey_entries` (règles d'incubation, relevés de lots, règle du délai fournisseur de provende, référentiel
 * du technicien des poissons-chats). Une ligne = un type + un libellé + des valeurs (`data`, JSON) + un STATUT
 * (`a_valider` | `valide`).
 *
 * ⚠️ Les valeurs par défaut sont les PROPOSITIONS de l'assistant (DV-17, DV-18, DV-19) : elles naissent « À valider ».
 * Le semis est fait ICI (base existante) ET par `ReleveTerrainSeeder` (base neuve) par la MÊME méthode, idempotente :
 * identifiants déterministes, une ligne déjà présente (même archivée, même modifiée) n'est JAMAIS réécrite.
 * Clé primaire UUID (le poste écrit hors ligne). Pas de clé étrangère sur `validated_by` : l'archivage d'un compte ne
 * doit jamais bloquer ni effacer la trace de la validation.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('field_survey_entries', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('type', 40);
            $table->string('label', 150);
            $table->string('species_code', 40)->nullable();
            $table->json('data')->nullable();
            $table->string('status', 12)->default('a_valider');
            $table->uuid('validated_by')->nullable();
            $table->dateTime('validated_at')->nullable();
            $table->string('device_id', 100)->nullable();
            $table->string('sync_status', 20)->default('synced');
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->index(['type', 'is_active']);
        });

        ReleveTerrainService::semerParDefaut();
    }

    public function down(): void
    {
        Schema::dropIfExists('field_survey_entries');
    }
};
