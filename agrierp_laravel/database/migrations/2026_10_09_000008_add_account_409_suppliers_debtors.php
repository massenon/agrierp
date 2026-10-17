<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Ticket 15.20 (décision D1/D7) — OUVRIR LE COMPTE 409 « FOURNISSEURS DÉBITEURS ».
 *
 * ⚠️ MIGRATION DE RATTRAPAGE, en plus de la semence (même raison que le 419 au ticket 15.19) : sur une base DÉJÀ
 * semée, sans elle le compte 409 n'existerait pas et tout retour d'un achat déjà payé serait refusé.
 *
 * ⚠️ PROPOSITION À FAIRE VALIDER PAR LE CABINET FAGUEZ : le choix du compte 409 et son libellé.
 *
 * Idempotente : si un compte 409 existe déjà (saisi à la main), il est laissé tel quel.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (DB::table('chart_of_accounts')->where('code', '409')->exists()) {
            return;
        }

        DB::table('chart_of_accounts')->insert([
            'id' => (string) Str::uuid(),
            'code' => '409',
            'label' => 'Fournisseurs débiteurs',
            'class' => 4,
            'is_active' => true,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    public function down(): void
    {
        // Jamais de suppression d'un compte qui peut porter des écritures : on ne le retire que s'il est vierge.
        $compte = DB::table('chart_of_accounts')->where('code', '409')->first();

        if ($compte && ! DB::table('accounting_entry_lines')->where('account_id', $compte->id)->exists()) {
            DB::table('chart_of_accounts')->where('id', $compte->id)->delete();
        }
    }
};
