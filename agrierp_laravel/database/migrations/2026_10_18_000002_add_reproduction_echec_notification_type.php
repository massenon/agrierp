<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 15.49 — type de notification des échecs de reproduction (« Alertes Réforme / Pertes »).
 *
 * L'énumération est ÉTENDUE, jamais réécrite (même règle que la migration du 20/08/2026). Les gravités ne
 * changent pas : ce sont les écritures fautives (`warning`, `error`) qui ont été corrigées dans le code.
 */
return new class extends Migration
{
    private const AVANT = [
        'stock_low', 'high_mortality', 'payment_due',
        'fiscal_year_reminder', 'prophylaxis_due', 'system',
        'sale_under_withdrawal',
    ];

    private const APRES = [
        'stock_low', 'high_mortality', 'payment_due',
        'fiscal_year_reminder', 'prophylaxis_due', 'system',
        'sale_under_withdrawal', 'reproduction_echec',
    ];

    public function up(): void
    {
        Schema::table('notifications', function (Blueprint $table) {
            $table->enum('type', self::APRES)->change();
        });
    }

    public function down(): void
    {
        \App\Models\Notification::where('type', 'reproduction_echec')->delete();

        Schema::table('notifications', function (Blueprint $table) {
            $table->enum('type', self::AVANT)->change();
        });
    }
};
