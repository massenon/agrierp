<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 9.1 (Sprint 9) — RÉSOUT LE GAP HISTORIQUE CRITIQUE identifié à
 * l'ultra-review de fin de session précédente : "The Administration
 * module class is referenced in routes and sidebar but was never built."
 * Le lien `/administration` existait dans la sidebar depuis le Sprint 0
 * sans jamais aboutir à une route réelle — corrigé dans ce ticket.
 *
 * ÉCART DOCUMENTÉ : aucune des 3 tables ci-dessous n'existe dans le
 * schéma documenté (`FULL_MIGRATIONS_DATABASE.md`) — conçues à partir
 * des champs réels des 3 écrans du hub Administration.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('mails', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('reference', 30)->unique();
            $table->enum('type', ['entrant', 'sortant']);
            $table->string('subject', 255);
            $table->string('party', 150);
            $table->date('mail_date');
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });

        Schema::create('archived_documents', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('title', 255);
            $table->string('category', 100);
            $table->date('archived_date');
            $table->date('expiry_date')->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });

        Schema::create('administrative_documents', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('title', 255);
            $table->string('type', 100);
            $table->string('beneficiary', 150);
            $table->date('doc_date');
            $table->enum('status', ['signe', 'en_attente'])->default('en_attente');
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('administrative_documents');
        Schema::dropIfExists('archived_documents');
        Schema::dropIfExists('mails');
    }
};
