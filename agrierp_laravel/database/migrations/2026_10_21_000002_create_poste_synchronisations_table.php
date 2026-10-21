<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket SW-1 (correction du client du 21/10/2026) — CE QUE LE SERVEUR SAIT DU CURSEUR DE CHAQUE POSTE, ET LE DRAPEAU
 * « RESYNCHRONISATION DEMANDÉE ».
 *
 * Le curseur de tirage (`since`) n'existait que sur le poste : le serveur ne pouvait donc pas dire quels postes n'ont
 * pas encore reçu ce qui s'est fait au web (le portable sert au web parce que le poste de bureau est en panne ; réparé,
 * le poste de bureau doit récupérer tout ce qui a été saisi). Une ligne par poste (`poste` = nom du jeton Sanctum) :
 *
 *  - `curseur_tirage` : le `server_time` rendu à la dernière page du dernier tirage — le `since` que le poste utilisera ;
 *  - `dernier_tirage_le` : l'instant de ce tirage ;
 *  - `resync_demandee_le` : drapeau posé par l'administrateur (« Renvoyer vers ce poste »). Il reste levé jusqu'à
 *    l'acquittement du poste, contrairement à la demande de synchronisation (S-T6) qui expire au bout d'une heure : un
 *    poste réparé une semaine plus tard doit encore le lire ;
 *  - `resync_demandee_par` : l'administrateur ; `resync_acquittee_le` : l'acquittement du poste.
 *
 * Table propre au SERVEUR : jamais tirée ni poussée. Migration sûre : ne touche à aucune table existante, et ne
 * recrée rien si elle existe déjà.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('poste_synchronisations')) {
            return;
        }

        Schema::create('poste_synchronisations', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('poste', 255)->unique();
            $table->timestamp('curseur_tirage')->nullable();
            $table->timestamp('dernier_tirage_le')->nullable();
            $table->timestamp('resync_demandee_le')->nullable();
            $table->foreignUuid('resync_demandee_par')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('resync_acquittee_le')->nullable();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('poste_synchronisations');
    }
};
