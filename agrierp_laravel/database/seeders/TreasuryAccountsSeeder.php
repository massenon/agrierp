<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Soldes cohérents avec dashboard.html du prototype : Trésorerie totale
 * 1 600 000 FCFA = Caisse 420 000 + Banque 1 180 000 (SEEDER_TEST.md §6).
 */
class TreasuryAccountsSeeder extends Seeder
{
    public function run(): void
    {
        $accounts = [
            ['type' => 'caisse', 'label' => 'Caisse Principale', 'account_code' => '531', 'balance' => 420000],
            ['type' => 'banque', 'label' => 'Compte Bancaire Principal', 'account_code' => '521101', 'balance' => 1180000],
            ['type' => 'mobile_money', 'label' => 'Mobile Money', 'account_code' => '521201', 'balance' => 0],
        ];

        foreach ($accounts as $a) {
            DB::table('treasury_accounts')->insert([
                'id' => (string) Str::uuid(),
                'type' => $a['type'],
                'label' => $a['label'],
                'account_code' => $a['account_code'],
                'balance' => $a['balance'],
                'is_active' => true,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }
    }
}
