<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ÉCART DOCUMENTÉ (ticket 6.2) : `stock_movements` (§24) ne prévoit pas de
 * motif. Le formulaire réel "Saisir un ajustement d'inventaire"
 * (`gestion-stocks.html`, onglet Ajustement/Correction) capture un motif
 * précis (Casse, Vol, Mortalité non déclarée, Naissance non répertoriée,
 * etc.) — perdre cette information dans le journal des mouvements aurait
 * rendu la traçabilité de l'écart inexploitable. Colonne nullable :
 * seuls les mouvements issus d'un ajustement manuel la renseignent.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('stock_movements', function (Blueprint $table) {
            $table->string('reason', 255)->nullable()->after('reference_id');
        });
    }

    public function down(): void
    {
        Schema::table('stock_movements', function (Blueprint $table) {
            $table->dropColumn('reason');
        });
    }
};
