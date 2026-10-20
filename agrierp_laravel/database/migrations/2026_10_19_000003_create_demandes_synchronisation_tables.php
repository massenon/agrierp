<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket S-T6 — DEMANDE DE SYNCHRONISATION ADRESSÉE AUX POSTES PAR LE SERVEUR (méthode TATACORA, § 3 de
 * `docs/COMPARAISON_METHODE_TATACORA.md`).
 *
 * Le serveur ne peut pas joindre un poste (pas d'adresse entrante, liaison intermittente) : il DÉPOSE une demande, et
 * chaque poste connecté la lit toutes les 30 s (`GET /api/sync/demande`). Une demande vise un poste (`poste` = nom du
 * jeton Sanctum, c'est-à-dire l'identifiant du poste) ou tous (`poste` nul). « Servie » se note PAR POSTE dans la
 * table fille : une demande adressée à tous reste due aux postes qui ne l'ont pas encore lue.
 *
 * Tables propres au SERVEUR : jamais tirées ni poussées.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('demandes_synchronisation')) {
            Schema::create('demandes_synchronisation', function (Blueprint $table) {
                $table->uuid('id')->primary();
                // Nul : tous les postes.
                $table->string('poste', 255)->nullable();
                $table->timestamp('demandee_le')->useCurrent();
                $table->foreignUuid('demandee_par')->nullable()->constrained('users')->nullOnDelete();

                $table->index('demandee_le');
            });
        }

        if (! Schema::hasTable('demandes_synchronisation_servies')) {
            Schema::create('demandes_synchronisation_servies', function (Blueprint $table) {
                $table->uuid('id')->primary();
                $table->foreignUuid('demande_id')->constrained('demandes_synchronisation')->cascadeOnDelete();
                $table->string('poste', 255);
                $table->timestamp('servie_le')->useCurrent();

                // Une demande n'est servie qu'une fois à un poste donné, même si deux lectures se croisent.
                $table->unique(['demande_id', 'poste']);
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('demandes_synchronisation_servies');
        Schema::dropIfExists('demandes_synchronisation');
    }
};
