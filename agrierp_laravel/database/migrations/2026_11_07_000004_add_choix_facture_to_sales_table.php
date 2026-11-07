<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Choix « Facture simple » / « Facture normalisée » fait à la vente.
 *
 *  - `facture_type` : `simple` (aucune transmission DGI, jamais) ou `normalisee` ;
 *  - `client_ifu` (13 chiffres, facultatif : vide = client sans IFU), `client_nom_facture` (obligatoire si normalisée) et
 *    `aib_taux` (`5%`, `1%` ou `N/A`) : l'identité fiscale de l'ACHETEUR telle que saisie à la vente, figée avec elle ;
 *  - `mecef_aib_montant` : le montant d'AIB CALCULÉ PAR LA DGI (réponse de création de la facture), jamais calculé ici.
 *
 * Données déjà là (avant ce choix) : une vente déjà normalisée (`mecef_status = transmise`) devient `normalisee` ; TOUTES les
 * autres deviennent `simple` — décision : une ancienne vente « à facturer » ne part pas à la DGI à l'insu du client.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('sales', function (Blueprint $table) {
            $table->string('facture_type', 12)->nullable();
            $table->string('client_ifu', 13)->nullable();
            $table->string('client_nom_facture', 150)->nullable();
            $table->string('aib_taux', 4)->nullable();
            $table->decimal('mecef_aib_montant', 14, 2)->nullable();
        });

        DB::table('sales')->where('mecef_status', 'transmise')->update(['facture_type' => 'normalisee']);
        DB::table('sales')->whereNull('facture_type')->update(['facture_type' => 'simple']);
    }

    public function down(): void
    {
        Schema::table('sales', function (Blueprint $table) {
            $table->dropColumn(['facture_type', 'client_ifu', 'client_nom_facture', 'aib_taux', 'mecef_aib_montant']);
        });
    }
};
