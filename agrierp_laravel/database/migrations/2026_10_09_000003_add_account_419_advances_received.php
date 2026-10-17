<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Ticket 15.19 (décision D1) — OUVRIR LE COMPTE 419 « AVANCES ET ACOMPTES REÇUS ».
 *
 * ⚠️ MIGRATION DE RATTRAPAGE, en plus de la semence. `ChartOfAccountsSeeder` est idempotent mais
 * ne se rejoue pas tout seul : sur une base DÉJÀ semée (la production), sans cette migration le
 * compte 419 n'existerait pas, `RecordSettlementAccountingEntryAction` ne trouverait pas sa
 * contrepartie, et toute avance serait refusée. Le même constat avait été fait au ticket 14.26
 * pour les comptes de classe 2.
 *
 * ⚠️ PROPOSITION À FAIRE VALIDER PAR LE CABINET FAGUEZ : le choix du compte 419 et le libellé.
 * Le compte 409 (fournisseurs débiteurs) n'est PAS ouvert ici : rien ne s'en sert avant le
 * ticket sur les retours fournisseur.
 *
 * Idempotente : si un compte 419 existe déjà (saisi à la main), il est laissé tel quel.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (DB::table('chart_of_accounts')->where('code', '419')->exists()) {
            return;
        }

        DB::table('chart_of_accounts')->insert([
            'id' => (string) Str::uuid(),
            'code' => '419',
            'label' => 'Avances et acomptes reçus',
            'class' => 4,
            'is_active' => true,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    public function down(): void
    {
        // Jamais de suppression d'un compte qui peut porter des écritures : on ne le retire que
        // s'il est vierge.
        $compte = DB::table('chart_of_accounts')->where('code', '419')->first();

        if ($compte && ! DB::table('accounting_entry_lines')->where('account_id', $compte->id)->exists()) {
            DB::table('chart_of_accounts')->where('id', $compte->id)->delete();
        }
    }
};
