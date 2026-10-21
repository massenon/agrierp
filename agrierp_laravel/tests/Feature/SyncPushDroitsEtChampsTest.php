<?php

namespace Tests\Feature;

use App\Models\Expense;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Sale;
use App\Models\SaleLine;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Models\VeterinaryRecord;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket S1 — SÉCURITÉ DE L'ENVOI DU POSTE (`POST /api/sync/push`).
 *
 * 🔴 Avant ce ticket :
 * 1. huit tables (fiches, reproduction, soins, dépenses, achats, pointages, ventes, ajustements de stock)
 *    étaient acceptées de N'IMPORTE QUEL jeton, quel que soit le rôle ;
 * 2. une vente était remplie avec TOUS ses champs envoyés (`mecef_status`, `accounting_entry_id`…), et une
 *    ligne pouvait se rattacher à une autre vente par son `sale_id` ;
 * 3. une fiche et un soin écrivaient des colonnes jamais validées.
 */
class SyncPushDroitsEtChampsTest extends TestCase
{
    use RefreshDatabase;

    private Product $produit;

    private LivestockLot $bande;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);

        $categorie = new ProductCategory();
        $categorie->id = '11111111-1111-4111-8111-111111111111';
        $categorie->label = 'Aliments';
        $categorie->is_active = true;
        $categorie->save();

        $this->produit = Product::create([
            'sku' => 'ALI-001', 'name' => 'Provende ponte',
            'category_id' => $categorie->id, 'unit' => 'sac',
            'pricing_mode' => 'fourchette', 'tva_rate' => 0,
            'stock_qty' => 50, 'is_active' => true,
        ]);

        $espece = LivestockSpecies::firstOrCreate(['code' => 'avicole'], ['label' => 'Avicole', 'is_active' => true]);

        $this->bande = LivestockLot::create([
            'code' => 'PON-001', 'species_id' => $espece->id, 'stage' => 'ponte',
            'initial_quantity' => 100, 'current_quantity' => 100,
            'created_date' => now()->subDays(10)->toDateString(), 'status' => 'actif', 'is_active' => true,
        ]);
    }

    private function compte(string $role): User
    {
        $u = User::create([
            'name' => ucfirst($role), 'username' => $role,
            'email' => $role.'@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    private function fiche(array $remplacements = []): array
    {
        return array_merge([
            'id' => '33333333-3333-4333-8333-333333333333',
            'lot_id' => $this->bande->id,
            'entry_date' => now()->toDateString(),
            'achat' => 0, 'ne' => 0, 'mort' => 2, 'vente' => 0,
        ], $remplacements);
    }

    private function vente(array $remplacements = []): array
    {
        return array_merge([
            'id' => '99999999-9999-4999-8999-999999999999',
            'payment_mode' => 'especes',
            'subtotal' => 18000, 'discount' => 0, 'total' => 18000,
            'lines' => [[
                'product_id' => $this->produit->id,
                'qty' => 1, 'unit_price' => 18000, 'manual_total_amount' => 18000,
            ]],
        ], $remplacements);
    }

    public function test_un_caissier_ne_peut_pas_enregistrer_une_depense_par_le_poste(): void
    {
        $caisse = TreasuryAccount::create([
            'label' => 'Caisse Physique', 'account_code' => '531',
            'type' => 'caisse', 'balance' => 500000, 'is_active' => true,
        ]);

        $reponse = $this->actingAs($this->compte('caissier'), 'sanctum')->postJson('/api/sync/push', [
            'expenses' => [[
                'id' => '22222222-2222-4222-8222-222222222222',
                'expense_date' => now()->toDateString(),
                'label' => 'Gasoil groupe', 'category' => '605 - Énergie',
                'amount' => 12000, 'treasury_account_id' => $caisse->id,
            ]],
        ]);

        $reponse->assertOk();
        $reponse->assertJsonPath('expenses.accepted', []);
        $reponse->assertJsonPath('expenses.rejected.0.id', '22222222-2222-4222-8222-222222222222');
        $this->assertStringContainsString('votre rôle ne permet pas', $reponse->json('expenses.rejected.0.reason'));
        $this->assertSame(0, Expense::count());
        $this->assertEquals(500000, (float) $caisse->fresh()->balance);
    }

    public function test_un_caissier_ne_peut_pas_ajuster_le_stock_et_le_refus_porte_la_reference_client(): void
    {
        $reponse = $this->actingAs($this->compte('caissier'), 'sanctum')->postJson('/api/sync/push', [
            'stock_adjustments' => [[
                'client_ref' => 'ajust-1', 'product_id' => $this->produit->id,
                'type' => 'entree', 'quantity' => 10,
                'reference_type' => 'inventaire', 'reason' => 'Écart inventaire',
            ]],
        ]);

        $reponse->assertOk();
        $reponse->assertJsonPath('stock_adjustments.rejected.0.client_ref', 'ajust-1');
        $this->assertStringContainsString('ajuster le stock', $reponse->json('stock_adjustments.rejected.0.reason'));
        $this->assertEquals(50, (float) $this->produit->fresh()->stock_qty);
    }

    public function test_un_comptable_ne_peut_pas_saisir_une_fiche_d_elevage(): void
    {
        $reponse = $this->actingAs($this->compte('comptable'), 'sanctum')->postJson('/api/sync/push', [
            'livestock_daily_entries' => [$this->fiche()],
        ]);

        $reponse->assertOk();
        $reponse->assertJsonPath('livestock_daily_entries.accepted', []);
        $this->assertSame(0, LivestockDailyEntry::count());
    }

    public function test_un_animalier_saisit_sa_fiche_d_elevage(): void
    {
        $reponse = $this->actingAs($this->compte('animalier'), 'sanctum')->postJson('/api/sync/push', [
            'livestock_daily_entries' => [$this->fiche()],
        ]);

        $reponse->assertJsonPath('livestock_daily_entries.accepted', ['33333333-3333-4333-8333-333333333333']);
        $this->assertSame(98, LivestockDailyEntry::first()->effectif_final);
    }

    /** F0.90 : la fiche réduite à son identité accompagne les ventes du caissier ; elle ne modifie rien. */
    public function test_la_fiche_d_identite_du_caissier_n_est_pas_refusee_pour_son_role(): void
    {
        $existante = LivestockDailyEntry::create([
            'lot_id' => $this->bande->id, 'entry_date' => now()->toDateString(),
            'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'effectif_final' => 100,
        ]);

        $reponse = $this->actingAs($this->compte('caissier'), 'sanctum')->postJson('/api/sync/push', [
            'livestock_daily_entries' => [[
                'id' => $existante->id, 'lot_id' => $this->bande->id,
                'entry_date' => now()->toDateString(),
            ]],
        ]);

        $reponse->assertJsonPath('livestock_daily_entries.rejected', []);
        $reponse->assertJsonPath('livestock_daily_entries.accepted', [$existante->id]);
    }

    /**
     * Le poste inscrit la vente de la caisse dans la fiche du jour et la renvoie : c'est le travail du caissier.
     *
     * Ticket S-T9 : sur une fiche que le serveur connaît déjà, c'est la VENTE envoyée avec elle qui inscrit ses sujets
     * (la vente de la fiche du poste n'est plus reprise : deux comptoirs l'écrasaient l'un l'autre). Une fiche créée par
     * l'envoi garde la vente qu'elle porte.
     */
    public function test_le_caissier_inscrit_sa_vente_dans_la_fiche_du_jour(): void
    {
        $existante = LivestockDailyEntry::create([
            'lot_id' => $this->bande->id, 'entry_date' => now()->toDateString(),
            'achat' => 0, 'ne' => 0, 'mort' => 1, 'vente' => 0, 'effectif_final' => 99,
        ]);

        $reponse = $this->actingAs($this->compte('caissier'), 'sanctum')->postJson('/api/sync/push', [
            'livestock_daily_entries' => [
                $this->fiche(['id' => $existante->id, 'mort' => 1, 'vente' => 4]),
                $this->fiche([
                    'id' => '66666666-6666-4666-8666-666666666666',
                    'entry_date' => now()->subDay()->toDateString(), 'mort' => 0, 'vente' => 2,
                ]),
            ],
            'sales' => [$this->vente(['lines' => [[
                'product_id' => $this->produit->id, 'lot_id' => $this->bande->id,
                'qty' => 4, 'unit_price' => 4500, 'manual_total_amount' => 18000,
            ]]])],
        ]);

        $reponse->assertJsonPath('livestock_daily_entries.rejected', []);
        $this->assertSame(4, $existante->fresh()->vente);
        $this->assertSame(2, LivestockDailyEntry::find('66666666-6666-4666-8666-666666666666')->vente);
    }

    /** Des morts inscrits par l'animalier sur le même poste ne partent pas sous le compte du caissier. */
    public function test_le_caissier_ne_peut_pas_envoyer_une_saisie_d_elevage(): void
    {
        $existante = LivestockDailyEntry::create([
            'lot_id' => $this->bande->id, 'entry_date' => now()->toDateString(),
            'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'effectif_final' => 100,
        ]);

        $reponse = $this->actingAs($this->compte('caissier'), 'sanctum')->postJson('/api/sync/push', [
            'livestock_daily_entries' => [
                $this->fiche(['id' => $existante->id, 'mort' => 3, 'vente' => 1]),
                $this->fiche(['id' => '66666666-6666-4666-8666-666666666666', 'entry_date' => now()->subDay()->toDateString(), 'ne' => 5]),
            ],
        ]);

        $reponse->assertJsonPath('livestock_daily_entries.accepted', []);
        $this->assertStringContainsString('un compte animalier', $reponse->json('livestock_daily_entries.rejected.0.reason'));
        $this->assertSame(0, $existante->fresh()->mort);
        $this->assertNull(LivestockDailyEntry::find('66666666-6666-4666-8666-666666666666'));
    }

    public function test_un_animalier_ne_peut_pas_enregistrer_une_vente(): void
    {
        $reponse = $this->actingAs($this->compte('animalier'), 'sanctum')->postJson('/api/sync/push', [
            'sales' => [$this->vente()],
        ]);

        $reponse->assertJsonPath('sales.accepted', []);
        $this->assertSame(0, Sale::count());
    }

    public function test_les_champs_reserves_au_serveur_d_une_vente_ne_sont_pas_repris_du_poste(): void
    {
        $autre = new Sale();
        $autre->id = '88888888-8888-4888-8888-888888888888';
        $autre->fill(['payment_mode' => 'especes', 'subtotal' => 1000, 'discount' => 0, 'total' => 1000]);
        $autre->save();

        $vente = $this->vente([
            'mecef_status' => 'transmise',
            'mecef_qr_ref' => 'FAUX-QR',
            'accounting_entry_id' => '77777777-7777-4777-8777-777777777777',
        ]);
        $vente['lines'][0]['sale_id'] = $autre->id;
        $vente['lines'][0]['is_manual_price'] = true;

        $this->actingAs($this->compte('caissier'), 'sanctum')
            ->postJson('/api/sync/push', ['sales' => [$vente]])
            ->assertJsonPath('sales.accepted', ['99999999-9999-4999-8999-999999999999']);

        $enregistree = Sale::find('99999999-9999-4999-8999-999999999999');
        $this->assertNotSame('FAUX-QR', $enregistree->mecef_qr_ref);
        $this->assertNotSame('77777777-7777-4777-8777-777777777777', $enregistree->accounting_entry_id);

        // La ligne appartient à SA vente, jamais à celle désignée par le poste.
        $this->assertSame(1, SaleLine::where('sale_id', $enregistree->id)->count());
        $this->assertSame(0, SaleLine::where('sale_id', $autre->id)->count());
    }

    public function test_un_mode_de_paiement_inconnu_est_refuse_avec_un_motif(): void
    {
        $reponse = $this->actingAs($this->compte('caissier'), 'sanctum')->postJson('/api/sync/push', [
            'sales' => [$this->vente(['payment_mode' => 'bitcoin'])],
        ]);

        $reponse->assertOk();
        $reponse->assertJsonPath('sales.accepted', []);
        $this->assertNotEmpty($reponse->json('sales.rejected.0.reason'));
    }

    public function test_une_fiche_avec_un_produit_inconnu_est_refusee_sans_erreur_500(): void
    {
        $reponse = $this->actingAs($this->compte('animalier'), 'sanctum')->postJson('/api/sync/push', [
            'livestock_daily_entries' => [$this->fiche([
                'feed_product_id' => '00000000-0000-4000-8000-000000000000',
            ])],
        ]);

        $reponse->assertOk();
        $reponse->assertJsonPath('livestock_daily_entries.accepted', []);
        $this->assertSame(0, LivestockDailyEntry::count());
    }

    public function test_une_fiche_avec_un_effectif_negatif_est_refusee(): void
    {
        $reponse = $this->actingAs($this->compte('animalier'), 'sanctum')->postJson('/api/sync/push', [
            'livestock_daily_entries' => [$this->fiche(['effectif_m' => -5])],
        ]);

        $reponse->assertJsonPath('livestock_daily_entries.accepted', []);
    }

    /**
     * Ticket U3 (décision client D-U3 du 19/10/2026) — l'archivage d'un soin est désormais ACCEPTÉ du poste (S1 l'ignorait) :
     * un soin saisi puis archivé hors ligne arrive archivé. Une gravité hors liste reste refusée.
     */
    public function test_un_soin_reprend_l_archivage_mais_pas_une_gravite_hors_liste(): void
    {
        $compte = $this->compte('animalier');

        $this->actingAs($compte, 'sanctum')->postJson('/api/sync/push', [
            'veterinary_records' => [[
                'id' => '44444444-4444-4444-8444-444444444444',
                'lot_id' => $this->bande->id, 'action_type' => 'Vaccin',
                'record_date' => now()->toDateString(), 'is_active' => false,
            ]],
        ])->assertJsonPath('veterinary_records.accepted', ['44444444-4444-4444-8444-444444444444']);

        $this->assertFalse((bool) VeterinaryRecord::find('44444444-4444-4444-8444-444444444444')->is_active);

        $this->actingAs($compte, 'sanctum')->postJson('/api/sync/push', [
            'veterinary_records' => [[
                'id' => '55555555-5555-4555-8555-555555555555',
                'lot_id' => $this->bande->id, 'action_type' => 'Vaccin',
                'record_date' => now()->toDateString(), 'gravite' => 'apocalyptique',
            ]],
        ])->assertJsonPath('veterinary_records.accepted', []);
    }

    public function test_les_routes_de_synchronisation_sont_limitees_en_debit(): void
    {
        $compte = $this->compte('animalier');

        for ($i = 0; $i < 30; $i++) {
            $this->actingAs($compte, 'sanctum')->postJson('/api/sync/push', [])->assertOk();
        }

        $this->actingAs($compte, 'sanctum')->postJson('/api/sync/push', [])->assertStatus(429);
    }
}
