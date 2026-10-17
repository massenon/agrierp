<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 14.16 (Sprint 14) — suivi INDIVIDUEL des sujets, limité aux
 * reproducteurs (arbitrage client).
 *
 * Jusqu'ici tout le module Élevage suivait des BANDES avec des quantités
 * (`livestock_lots.current_quantity`) : aucune entité ne représentait un
 * sujet. `animal-details.html` en supposait pourtant une — c'est le gap
 * signalé au ticket 14.10 et tranché ici.
 *
 * ⚠️ PÉRIMÈTRE VOLONTAIREMENT RESTREINT : seuls les reproducteurs sont suivis
 * individuellement. C'est là que le suivi par sujet a une valeur réelle
 * (sélection, réforme, généalogie) ; l'imposer aux bandes d'engraissement
 * signifierait saisir des centaines de poulets de chair un par un. Les bandes
 * restent donc suivies en quantités — les deux modes coexistent
 * délibérément.
 *
 * `category` en STRING et non en ENUM, décision assumée : ce projet a déjà
 * payé deux fois l'extension d'un enum MySQL (`customer_reminders.channel`,
 * `attendance_records.status`, migrations en SQL brut incompatibles avec tout
 * autre pilote — voir ticket 14.2). Élargir plus tard le suivi individuel à
 * une autre catégorie ne doit pas exiger une migration en SQL natif.
 *
 * `identifier` unique : c'est la clé lisible portée par la boucle/le tatouage
 * du sujet, et celle que `livestock_reproduction_events.mother_ref` /
 * `sire_ref` utilisent DÉJÀ en texte libre — le rattachement se fait donc sur
 * l'existant, sans migrer ni casser les événements de reproduction déjà
 * saisis.
 *
 * Pas de `device_id`/`sync_status` : `livestock_lots` et
 * `livestock_daily_entries` n'en portent pas non plus. Rester cohérent avec
 * le module plutôt qu'introduire une convention isolée sur une seule table.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('animals', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('identifier', 50)->unique();     // ex. LAP-2026-0143
            $table->foreignUuid('species_id')->constrained('livestock_species')->restrictOnDelete();
            $table->foreignUuid('lot_id')->nullable()->constrained('livestock_lots')->nullOnDelete();
            $table->string('category', 30)->default('reproducteur');
            $table->enum('sex', ['M', 'F']);
            $table->string('breed', 100)->nullable();       // race
            $table->date('birth_date')->nullable();
            $table->date('entry_date');
            $table->string('origin', 150)->nullable();       // naissance interne, achat…
            $table->string('cage', 30)->nullable();
            // Archivage logique uniquement — jamais de suppression physique
            // d'un historique zootechnique (Document 00 §7).
            $table->string('status', 20)->default('actif'); // actif | reforme | vendu | mort
            $table->date('exit_date')->nullable();
            $table->string('exit_reason', 150)->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->index(['species_id', 'status']);
            $table->index('lot_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('animals');
    }
};
