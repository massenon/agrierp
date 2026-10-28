<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket CP-4 — JOURNAL DES DEMANDES DE CLÔTURE REJOUÉES (idempotence par l'UUID de la demande du poste).
 *
 * Une clôture est destructive et se juge au serveur : le poste n'écrit que sa DEMANDE. Une fois jouée, son UUID est
 * consigné ici ; si le poste la renvoie (acquittement perdu), elle est reconnue et acquittée SANS être rejouée — sinon une
 * clôture renvoyée après une réouverture faite entre-temps par l'administrateur reclôturerait l'exercice.
 * Seules les demandes ACCEPTÉES sont consignées : une demande refusée reste rejouable (le poste la relance ou l'abandonne).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('fiscal_closure_requests', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('kind', 40);
            $table->json('payload')->nullable();
            $table->uuid('user_id')->nullable();
            $table->timestamp('handled_at');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('fiscal_closure_requests');
    }
};
