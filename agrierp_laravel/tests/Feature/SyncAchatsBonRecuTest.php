<?php

namespace Tests\Feature;

use App\Models\Purchase;
use App\Models\Role;
use App\Models\Supplier;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * PWA-3 (délai fournisseur constaté) : le tirage des achats porte `purchase_order_id` (le bon que l'achat a reçu). Sans lui, un poste ou la PWA ne
 * peut pas relier un bon « reçu » au jour de sa réception (`ReleveTerrainService::delaisFournisseurs`).
 */
class SyncAchatsBonRecuTest extends TestCase
{
    use RefreshDatabase;

    public function test_le_tirage_des_achats_porte_le_bon_de_commande_recu(): void
    {
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $u = User::create(['name' => 'Admin', 'username' => 'adm', 'email' => 'adm@x.test', 'password' => bcrypt('x'), 'is_active' => true]);
        $u->assignRole('admin');
        $f = Supplier::create(['name' => 'Fournisseur', 'is_active' => true]);
        $bonId = (string) \Illuminate\Support\Str::uuid();
        \DB::table('purchase_orders')->insert(['id' => $bonId, 'supplier_id' => $f->id, 'status' => 'recu', 'created_at' => now(), 'updated_at' => now()]);
        $avecBon = new Purchase;
        $avecBon->forceFill(['supplier_id' => $f->id, 'purchase_order_id' => $bonId, 'payment_mode' => 'especes', 'total' => 100, 'purchase_date' => '2026-11-01'])->save();
        $sansBon = new Purchase;
        $sansBon->forceFill(['supplier_id' => $f->id, 'payment_mode' => 'especes', 'total' => 50, 'purchase_date' => '2026-11-02'])->save();

        $r = $this->actingAs($u, 'sanctum')->getJson('/api/sync/pull')->assertOk();
        $achats = collect($r->json('purchases'))->keyBy('id');
        $this->assertSame($bonId, $achats[$avecBon->id]['purchase_order_id']);
        $this->assertNull($achats[$sansBon->id]['purchase_order_id']);
        $this->assertArrayHasKey('purchase_order_id', $achats[$sansBon->id]);
    }
}
