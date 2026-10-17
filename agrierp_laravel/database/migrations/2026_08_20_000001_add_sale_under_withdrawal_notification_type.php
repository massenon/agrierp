<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 14.68 (Sprint 14) — UN TYPE DE NOTIFICATION POUR L'INCIDENT SANITAIRE.
 *
 * ⚠️ **POURQUOI UN TYPE DÉDIÉ PLUTÔT QUE `system`.** Une vente reçue sur une
 * bande sous délai d'attente est un **incident de santé publique** : il doit
 * pouvoir être filtré, compté et audité à part. Le ranger dans `system` le
 * noierait parmi les messages génériques — et une alerte qu'on ne peut pas
 * isoler est une alerte qu'on ne relit jamais.
 *
 * ⚠️ L'énumération est **étendue, jamais réécrite** : retirer un type existant
 * invaliderait les notifications déjà en base.
 */
return new class extends Migration
{
    private const AVANT = [
        'stock_low', 'high_mortality', 'payment_due',
        'fiscal_year_reminder', 'prophylaxis_due', 'system',
    ];

    private const APRES = [
        'stock_low', 'high_mortality', 'payment_due',
        'fiscal_year_reminder', 'prophylaxis_due', 'system',
        'sale_under_withdrawal',
    ];

    public function up(): void
    {
        Schema::table('notifications', function (Blueprint $table) {
            $table->enum('type', self::APRES)->change();
        });
    }

    public function down(): void
    {
        // ⚠️ Les notifications du nouveau type doivent partir AVANT le
        // rétrécissement, sinon la contrainte refuserait des lignes déjà
        // enregistrées et la migration inverse échouerait.
        \App\Models\Notification::where('type', 'sale_under_withdrawal')->delete();

        Schema::table('notifications', function (Blueprint $table) {
            $table->enum('type', self::AVANT)->change();
        });
    }
};
