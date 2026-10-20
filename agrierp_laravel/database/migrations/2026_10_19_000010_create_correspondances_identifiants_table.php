<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket S-T5 (méthode TATACORA) — CORRESPONDANCES D'IDENTIFIANTS ENTRE UN POSTE ET LE SERVEUR.
 *
 * Quand un poste crée hors ligne un client, un fournisseur ou un produit qui existe déjà au serveur (même clé
 * naturelle, `FusionReferentielsService`), le serveur ne crée pas de seconde fiche : il note ici que l'identifiant du
 * poste (`id_poste`) désigne la fiche du serveur (`id_serveur`). Toute référence ultérieure à `id_poste` (vente, achat,
 * ligne, avance, règlement…) est traduite par cette table au moment de son traitement.
 *
 * Table propre au SERVEUR : jamais tirée ni poussée. ⚠️ Une ligne ne se modifie ni ne s'efface (sauf réinitialisation
 * des données) : un poste ancien peut renvoyer son identifiant des mois plus tard.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('correspondances_identifiants')) {
            return;
        }

        Schema::create('correspondances_identifiants', function (Blueprint $table) {
            $table->uuid('id')->primary();
            // `customers`, `suppliers` ou `products`.
            $table->string('table_referentiel', 50);
            $table->uuid('id_poste');
            $table->uuid('id_serveur');
            // Clé naturelle normalisée qui a décidé la fusion (lecture humaine, audit).
            $table->string('cle_naturelle', 255);
            // Nom du jeton du poste (S-T2), sinon le `device_id` envoyé.
            $table->string('poste', 255)->nullable();
            $table->foreignUuid('user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('fusionne_le')->useCurrent();

            $table->unique(['table_referentiel', 'id_poste']);
            $table->index(['table_referentiel', 'id_serveur']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('correspondances_identifiants');
    }
};
