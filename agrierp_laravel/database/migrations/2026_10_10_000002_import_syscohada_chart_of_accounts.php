<?php

use App\Services\ImporterPlanSyscohadaService;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Ticket 15.27 (phase A de l'item 9) — MIGRATION DE RATTRAPAGE : importe le plan SYSCOHADA révisé (insertion seule)
 * sur une base DÉJÀ SEMÉE.
 *
 * ⚠️ Sur une base NON SEMÉE (installation neuve, tests) elle ne fait RIEN, volontairement : importer avant les 36 comptes de
 * la ferme créerait 531 « chèques postaux » (sens du CSV) à la place de 531 « Caisse ». C'est `ChartOfAccountsSeeder`
 * qui importe, APRÈS ses 36 comptes.
 *
 * Idempotente. Ne modifie, ne désactive ni ne supprime aucun compte existant.
 */
return new class extends Migration
{
    public function up(): void
    {
        // ⚠️ « Table non vide » ne prouve rien : les migrations 15.19 et 15.20 posent 419 et 409 même sur une base
        // vide. On exige donc les quatre comptes d'ancrage de la ferme.
        $ancres = DB::table('chart_of_accounts')->whereIn('code', ['101', '531', '601', '701'])->count();

        if ($ancres < 4) {
            return;
        }

        app(ImporterPlanSyscohadaService::class)->importer();
    }

    public function down(): void
    {
        // Jamais de suppression de comptes qui peuvent porter des écritures.
    }
};
