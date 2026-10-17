<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ÉCART DOCUMENTÉ (ticket 7.1) : `sales` (ticket 4.1) porte déjà
 * `mecef_qr_ref`, mais aucun statut de TRANSMISSION distinct de
 * `status` (validee/annulee, qui concerne la vente elle-même, pas sa
 * remontée fiscale). L'écran réel `facturation.html` affiche 3 statuts
 * MeCeF (Transmise/En attente/Erreur MeCeF) — colonne ajoutée en
 * conséquence, jamais confondue avec `sales.status`.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('sales', function (Blueprint $table) {
            $table->enum('mecef_status', ['transmise', 'en_attente', 'erreur'])->default('en_attente')->after('mecef_qr_ref');
        });
    }

    public function down(): void
    {
        Schema::table('sales', function (Blueprint $table) {
            $table->dropColumn('mecef_status');
        });
    }
};
