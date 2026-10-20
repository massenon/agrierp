<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket CFG-1 (décision D-CFG-1 du 19/10/2026) — ADRESSE D'EXPÉDITION DES E-MAILS, distincte de l'e-mail de contact.
 *
 * ⚠️ Jusqu'ici, « Adresse d'Expédition » (Intégrations) et « Email de Contact » (Données de l'Entreprise) écrivaient
 * la MÊME colonne `email` depuis deux écrans : changer l'expéditeur changeait l'adresse imprimée sur les documents.
 * L'onglet « Email (SMTP) » a désormais sa colonne ; vide, l'e-mail de contact sert d'expéditeur, comme avant.
 *
 * ⚠️ Colonne du SERVEUR seulement : elle ne descend pas au poste (le tirage ne sert que l'identité et les taux,
 * ticket 14.84) ; la table Drift `company_settings` n'a donc pas à la porter, comme `smtp_host`.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('company_settings', function (Blueprint $table) {
            $table->string('smtp_from_address')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('company_settings', function (Blueprint $table) {
            $table->dropColumn('smtp_from_address');
        });
    }
};
