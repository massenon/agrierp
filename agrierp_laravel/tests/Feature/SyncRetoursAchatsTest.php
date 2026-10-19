<?php

namespace Tests\Feature;

use App\Livewire\Achats\ListeAchats;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Purchase;
use App\Models\PurchaseLine;
use App\Models\PurchaseReturn;
use App\Models\Supplier;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Ticket U8 — LES LIGNES DE RETOUR FOURNISSEUR DESCENDENT AU POSTE, AVEC LEUR ACHAT.
 *
 * La carte « Écarts / Retours » de la liste des achats compte des LIGNES de retour (`PurchaseReturn::count()`) ;
 * le poste, qui ne recevait pas `purchase_returns`, comptait des achats retournés — deux chiffres pour la même
 * ferme. Ce que ces tests verrouillent :
 *  - le tirage sert les lignes de retour des achats servis, avec les colonnes que le poste absorbe ;
 *  - AU MÊME CURSEUR que leur achat : un achat modifié renvoie TOUTES ses lignes de retour, une ligne de retour
 *    modifiée seule fait redescendre son achat (avec ses lignes d'achat et de retour) ;
 *  - AUCUNE FUITE : jamais une ligne de retour d'un achat non servi ;
 *  - un retour d'avant le ticket 15.20 (sans `return_date`) descend daté de son enregistrement.
 */
class SyncRetoursAchatsTest extends TestCase
{
    use RefreshDatabase;

    private User $utilisateur;

    private Supplier $fournisseur;

    private Product $provende;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $this->utilisateur = User::create([
            'name' => 'Administrateur', 'username' => 'admin',
            'email' => 'dg@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->utilisateur->assignRole('admin');

        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);
        $this->provende = Product::create([
            'sku' => 'ALI-PONTE', 'name' => 'Provende ponte', 'category_id' => $categorie->id, 'unit' => 'sac',
            'pricing_mode' => 'fourchette', 'price_min' => 8000, 'price_max' => 8000,
            'stock_qty' => 10, 'is_active' => true,
        ]);
        $this->fournisseur = Supplier::create([
            'name' => 'Provenderie du Plateau', 'category' => 'Aliments', 'is_active' => true,
        ]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    /** Achat de [qté, prix] par ligne ; retourné (une ligne de retour par ligne d'achat) si [retourne]. */
    private function achat(array $lignes, bool $retourne = false): Purchase
    {
        $achat = Purchase::create([
            'supplier_id' => $this->fournisseur->id, 'payment_mode' => 'especes',
            'total' => array_sum(array_map(fn ($l) => $l[0] * $l[1], $lignes)),
            'purchase_date' => now()->format('Y-m-d'),
        ]);
        $lot = (string) Str::uuid();
        foreach ($lignes as [$qte, $prix]) {
            $ligne = PurchaseLine::create([
                'purchase_id' => $achat->id, 'product_id' => $this->provende->id, 'qty' => $qte, 'unit_price' => $prix,
            ]);
            if ($retourne) {
                PurchaseReturn::create([
                    'purchase_id' => $achat->id, 'product_id' => $this->provende->id, 'qty' => $qte,
                    'reason' => 'Sacs éventrés', 'return_batch_id' => $lot, 'purchase_line_id' => $ligne->id,
                    'return_date' => now()->format('Y-m-d'), 'device_id' => 'poste-1',
                ]);
            }
        }
        if ($retourne) {
            $achat->forceFill(['returned_at' => now()])->save();
        }

        return $achat;
    }

    private function tirer(?string $depuis = null)
    {
        return $this->actingAs($this->utilisateur, 'sanctum')
            ->getJson('/api/sync/pull'.($depuis ? '?since='.urlencode($depuis) : ''))
            ->assertOk();
    }

    private function sansFuite($reponse): void
    {
        $achats = collect($reponse->json('purchases'))->pluck('id');
        foreach ($reponse->json('purchase_returns') as $retour) {
            $this->assertTrue($achats->contains($retour['purchase_id']), 'ligne de retour servie sans son achat');
        }
    }

    public function test_le_tirage_complet_sert_toutes_les_lignes_de_retour_comme_la_carte_du_web(): void
    {
        $retourne = $this->achat([[10, 8000], [5, 8200]], retourne: true);
        $this->achat([[4, 8000]]);

        $reponse = $this->tirer();

        $retours = collect($reponse->json('purchase_returns'));
        $this->assertCount(2, $retours);
        // La carte du web compte ces mêmes lignes.
        $this->assertSame(PurchaseReturn::count(), $retours->count());
        $this->assertSame(2, (new ListeAchats())->kpis['ecarts_retours']);

        $ligne = $retours->firstWhere('qty', 5);
        $this->assertSame($retourne->id, $ligne['purchase_id']);
        $this->assertSame('Sacs éventrés', $ligne['reason']);
        $this->assertSame(now()->format('Y-m-d'), $ligne['return_date']);
        $this->assertSame($this->provende->id, $ligne['product_id']);
        $this->assertNotEmpty($ligne['id']);
        $this->assertNotEmpty($ligne['return_batch_id']);
        $this->assertNotEmpty($ligne['purchase_line_id']);
        $this->sansFuite($reponse);
    }

    public function test_le_tirage_incremental_ne_sert_que_les_retours_des_achats_servis(): void
    {
        Carbon::setTestNow('2026-10-19 08:00:00');
        $ancien = $this->achat([[4, 8000]], retourne: true);
        $depuis = '2026-10-19T09:00:00+00:00';

        Carbon::setTestNow('2026-10-19 10:00:00');
        $nouveau = $this->achat([[2, 8100], [1, 8000]], retourne: true);

        $reponse = $this->tirer($depuis);

        $this->assertEquals([$nouveau->id], collect($reponse->json('purchases'))->pluck('id')->all());
        $this->assertEquals(
            [$nouveau->id, $nouveau->id],
            collect($reponse->json('purchase_returns'))->pluck('purchase_id')->all(),
        );
        $this->assertNotContains($ancien->id, collect($reponse->json('purchase_returns'))->pluck('purchase_id'));
        $this->sansFuite($reponse);
    }

    public function test_une_ligne_de_retour_modifiee_seule_fait_redescendre_son_achat_complet(): void
    {
        Carbon::setTestNow('2026-10-19 08:00:00');
        $achat = $this->achat([[4, 8000], [6, 7900]], retourne: true);
        $depuis = '2026-10-19T09:00:00+00:00';

        Carbon::setTestNow('2026-10-19 10:00:00');
        PurchaseReturn::where('purchase_id', $achat->id)->first()->touch();

        $reponse = $this->tirer($depuis);

        $this->assertEquals([$achat->id], collect($reponse->json('purchases'))->pluck('id')->all());
        $this->assertCount(2, collect($reponse->json('purchase_returns'))->where('purchase_id', $achat->id));
        $this->assertCount(2, collect($reponse->json('purchase_lines'))->where('purchase_id', $achat->id));
        $this->sansFuite($reponse);
    }

    public function test_un_retour_d_avant_le_ticket_15_20_descend_date_de_son_enregistrement(): void
    {
        Carbon::setTestNow('2026-09-03 11:00:00');
        $achat = $this->achat([[3, 8000]]);
        PurchaseReturn::create([
            'purchase_id' => $achat->id, 'product_id' => $this->provende->id, 'qty' => 3, 'reason' => null,
        ]);

        $ligne = collect($this->tirer()->json('purchase_returns'))->sole();

        $this->assertSame('2026-09-03', $ligne['return_date']);
        $this->assertNull($ligne['reason']);
        $this->assertNull($ligne['return_batch_id']);
    }

    public function test_sans_rien_de_nouveau_aucun_retour_ne_descend(): void
    {
        Carbon::setTestNow('2026-10-19 08:00:00');
        $this->achat([[4, 8000]], retourne: true);

        $this->assertSame([], $this->tirer('2026-10-19T09:00:00+00:00')->json('purchase_returns'));
    }
}
