<?php

namespace Tests\Feature;

use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\Payable;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Purchase;
use App\Models\PurchaseOrder;
use App\Models\PurchaseOrderLine;
use App\Models\StockMovement;
use App\Models\Supplier;
use App\Models\TreasuryAccount;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 14.78 (Sprint 14) — LE DOMAINE ACHAT ENTRE DANS LE CONTRAT DE SYNCHRO.
 *
 * ⚠️⚠️ CE QUE CES TESTS PROTÈGENT. Un achat porte **cinq effets**, pas un : la
 * pièce et ses lignes, l'ENTRÉE en stock (recalcul du PMP), le DÉCAISSEMENT de
 * la part réglée, la DETTE fournisseur si le règlement est partiel, et
 * l'ÉCRITURE SYSCOHADA. Enregistrer la pièce sans ses effets produirait le
 * défaut déjà corrigé pour les ventes hors ligne (14.52), la ponte (14.59) et
 * les dépenses (14.62) — un enregistrement qui existe et ne pèse sur rien,
 * découvert des semaines plus tard au rapprochement.
 */
class SyncAchatsTest extends TestCase
{
    use RefreshDatabase;

    private User $utilisateur;

    private Supplier $fournisseur;

    private Product $produit;

    private TreasuryAccount $caisse;

    protected function setUp(): void
    {
        parent::setUp();

        $this->utilisateur = User::create([
            'name' => 'Caissier', 'username' => 'caisse',
            'email' => 'caisse@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);

        // Ticket S1 : l'envoi du poste exige désormais le rôle qui écrit chaque table.

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);

        $this->utilisateur->assignRole('admin');

        $this->fournisseur = Supplier::create([
            'name' => 'Provenderie du Plateau', 'category' => 'Aliments',
            'phone' => '+22997000000', 'is_active' => true,
        ]);

        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);

        $this->produit = Product::create([
            'sku' => 'ALI-PONTE-25', 'name' => 'Aliment ponte 25kg',
            'category_id' => $categorie->id, 'unit' => 'sac',
            'pricing_mode' => 'fourchette', 'price_min' => 8000, 'price_max' => 8000,
            'stock_qty' => 10, 'is_active' => true,
        ]);

        $this->caisse = TreasuryAccount::create([
            'label' => 'Caisse Physique', 'account_code' => '531',
            'type' => 'caisse', 'balance' => 500000, 'is_active' => true,
        ]);

        FiscalYear::create([
            'year' => (int) now()->format('Y'),
            'start_date' => now()->startOfYear()->toDateString(),
            'end_date' => now()->endOfYear()->toDateString(),
            'status' => 'ouvert',
        ]);

        foreach ([['601', "Achats d'aliments", 6], ['401', 'Fournisseurs', 4], ['531', 'Caisse', 5]] as [$code, $libelle, $classe]) {
            ChartOfAccount::firstOrCreate(['code' => $code], [
                'label' => $libelle, 'class' => $classe, 'is_active' => true,
            ]);
        }
    }

    /** @return array<string, mixed> */
    private function achat(array $remplacements = []): array
    {
        return array_merge([
            'id' => '77777777-7777-4777-8777-777777777777',
            'supplier_id' => $this->fournisseur->id,
            'payment_mode' => 'especes',
            'treasury_account_id' => $this->caisse->id,
            'amount_paid' => 100000,
            'purchase_date' => now()->toDateString(),
            'lines' => [
                ['product_id' => $this->produit->id, 'qty' => 20, 'unit_price' => 5000],
            ],
        ], $remplacements);
    }

    private function pousser(array $achats): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($this->utilisateur, 'sanctum')
            ->postJson('/api/sync/push', ['purchases' => $achats]);
    }

    private function tirer(): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($this->utilisateur, 'sanctum')->getJson('/api/sync/pull');
    }

    /** ⚠️⚠️ LE TEST QUI COMPTE : l'achat arrive avec ses CINQ effets. */
    public function test_a_pushed_purchase_carries_its_five_effects(): void
    {
        $reponse = $this->pousser([$this->achat()]);

        $reponse->assertOk()->assertJsonPath('purchases.accepted.0', '77777777-7777-4777-8777-777777777777');

        $achat = Purchase::find('77777777-7777-4777-8777-777777777777');

        // 1. la pièce et sa ligne
        $this->assertNotNull($achat);
        $this->assertSame('100000.00', $achat->total);
        $this->assertCount(1, $achat->lines);

        // 2. l'entrée en stock, par le seul point d'entrée réel
        $this->assertSame(30.0, (float) $this->produit->fresh()->stock_qty);
        $this->assertTrue(StockMovement::where('reference_id', $achat->id)->exists());

        // 3. le décaissement
        $this->assertSame(400000.0, (float) $this->caisse->fresh()->balance);

        // 4. aucune dette : l'achat est réglé entièrement
        $this->assertSame(0, Payable::count());

        // 5. l'écriture SYSCOHADA, équilibrée
        $ecriture = AccountingEntry::find($achat->accounting_entry_id);
        $this->assertNotNull($ecriture);
        $this->assertSame(
            (float) $ecriture->lines->sum('debit'),
            (float) $ecriture->lines->sum('credit'),
        );
    }

    /**
     * ⚠️⚠️ RÈGLEMENT PARTIEL : la dette porte le TOTAL et la part réglée, jamais
     * le seul reste dû — la balance âgée a besoin des deux.
     */
    public function test_a_partly_paid_purchase_opens_a_supplier_debt(): void
    {
        $this->pousser([$this->achat(['amount_paid' => 40000])])->assertOk();

        $dette = Payable::first();

        $this->assertNotNull($dette);
        $this->assertSame('100000.00', $dette->amount);
        $this->assertSame('40000.00', $dette->amount_paid);
        $this->assertSame(460000.0, (float) $this->caisse->fresh()->balance);
    }

    /**
     * ⚠️⚠️ IDEMPOTENCE — LE DÉFAUT LE PLUS COÛTEUX. Un envoi rejoué ne doit
     * entrer la marchandise qu'une fois et ne décaisser qu'une fois.
     */
    public function test_a_replayed_purchase_changes_nothing(): void
    {
        $this->pousser([$this->achat()])->assertOk();
        $reponse = $this->pousser([$this->achat()])->assertOk();

        $reponse->assertJsonPath('purchases.accepted.0', '77777777-7777-4777-8777-777777777777');
        $this->assertSame(1, Purchase::count());
        $this->assertSame(30.0, (float) $this->produit->fresh()->stock_qty);
        $this->assertSame(400000.0, (float) $this->caisse->fresh()->balance);
    }

    /** ⚠️ On ne règle jamais plus que le total : pas de dette négative. */
    public function test_paying_more_than_the_total_is_capped(): void
    {
        $this->pousser([$this->achat(['amount_paid' => 999999])])->assertOk();

        $this->assertSame(400000.0, (float) $this->caisse->fresh()->balance);
        $this->assertSame(0, Payable::count());
    }

    /** Un achat sans ligne n'a pas de sens : il est rejeté AVEC son motif. */
    public function test_a_purchase_without_lines_is_refused(): void
    {
        $reponse = $this->pousser([$this->achat(['lines' => []])])->assertOk();

        $reponse->assertJsonCount(0, 'purchases.accepted');
        $reponse->assertJsonCount(1, 'purchases.rejected');
        $this->assertSame(0, Purchase::count());
    }

    /** Un fournisseur inconnu du serveur est refusé — jamais inventé. */
    public function test_an_unknown_supplier_is_refused(): void
    {
        $reponse = $this->pousser([
            $this->achat(['supplier_id' => '00000000-0000-4000-8000-000000000000']),
        ])->assertOk();

        $reponse->assertJsonCount(1, 'purchases.rejected');
        $this->assertSame(0, Purchase::count());
    }

    /**
     * ⚠️ UN REFUS N'EMPORTE PAS L'ENVOI ENTIER : l'achat valide du même lot
     * passe, l'autre est rejeté avec son motif.
     */
    public function test_one_refusal_does_not_carry_away_the_whole_push(): void
    {
        $reponse = $this->pousser([
            $this->achat(['id' => '88888888-8888-4888-8888-888888888888', 'lines' => []]),
            $this->achat(),
        ])->assertOk();

        $reponse->assertJsonCount(1, 'purchases.accepted');
        $reponse->assertJsonCount(1, 'purchases.rejected');
        $this->assertSame(1, Purchase::count());
    }

    /** ⚠️ La date vient du poste : une livraison de mardi reste à mardi. */
    public function test_the_purchase_keeps_the_day_it_was_recorded_on(): void
    {
        $this->pousser([$this->achat(['purchase_date' => now()->subDays(2)->toDateString()])])->assertOk();

        $this->assertSame(
            now()->subDays(2)->toDateString(),
            Purchase::first()->purchase_date->toDateString(),
        );
    }

    /** Une date future est refusée — une livraison ne s'anticipe pas. */
    public function test_a_purchase_dated_in_the_future_is_refused(): void
    {
        $reponse = $this->pousser([
            $this->achat(['purchase_date' => now()->addDay()->toDateString()]),
        ])->assertOk();

        $reponse->assertJsonCount(1, 'purchases.rejected');
    }

    /** 🔴→✅ Les fournisseurs descendent : sans eux, le poste n'achète rien. */
    public function test_the_suppliers_reach_the_device(): void
    {
        $this->tirer()
            ->assertOk()
            ->assertJsonCount(1, 'suppliers')
            ->assertJsonPath('suppliers.0.name', 'Provenderie du Plateau')
            ->assertJsonPath('suppliers.0.category', 'Aliments');
    }

    /**
     * ⚠️ LE STATUT SE CALCULE SUR LE SERVEUR. Le poste ne reçoit pas
     * `payables` : deux règles de statut donneraient deux listes différentes
     * pour la même ferme.
     */
    public function test_the_purchase_list_carries_its_debt_status(): void
    {
        $this->pousser([$this->achat(['amount_paid' => 40000])])->assertOk();

        $this->tirer()
            ->assertOk()
            ->assertJsonCount(1, 'purchases')
            ->assertJsonPath('purchases.0.has_debt', true)
            ->assertJsonPath('purchases.0.supplier_name', 'Provenderie du Plateau');
    }

    /**
     * ⚠️⚠️ LE MONTANT D'UN BON DE COMMANDE N'EST PAS STOCKÉ : il se somme sur
     * ses lignes, et la colonne s'appelle `estimated_unit_price`. Écrite
     * `unit_price` par habitude, la somme valait 0 pour un bon de 405 000 FCFA
     * — pas un tiret, un CHIFFRE FAUX que rien à l'écran n'aurait signalé.
     */
    public function test_the_purchase_order_carries_its_estimated_total(): void
    {
        $bon = PurchaseOrder::create([
            'supplier_id' => $this->fournisseur->id,
            'expected_delivery_date' => now()->addWeek()->toDateString(),
            'status' => 'envoye',
        ]);

        PurchaseOrderLine::create([
            'purchase_order_id' => $bon->id, 'product_id' => $this->produit->id,
            'qty' => 40, 'estimated_unit_price' => 6500,
        ]);
        PurchaseOrderLine::create([
            'purchase_order_id' => $bon->id, 'product_id' => $this->produit->id,
            'qty' => 20, 'estimated_unit_price' => 7250,
        ]);

        $this->tirer()
            ->assertOk()
            ->assertJsonCount(1, 'purchase_orders')
            ->assertJsonPath('purchase_orders.0.estimated_total', 405000)
            ->assertJsonPath('purchase_orders.0.status', 'envoye');
    }

    /**
     * 🔴→✅ TICKET 14.79 — LES DETTES FOURNISSEURS DESCENDENT.
     *
     * ⚠️ MÊME RÈGLE QUE LES CRÉANCES CLIENTS : seul ce qui RESTE DÛ est servi,
     * sans filtre `since`. Une dette échue il y a trois mois n'a plus bougé —
     * et c'est celle que le fournisseur va réclamer.
     */
    public function test_the_supplier_debt_reaches_the_device(): void
    {
        $this->pousser([$this->achat(['amount_paid' => 40000])])->assertOk();

        $this->tirer()
            ->assertOk()
            ->assertJsonCount(1, 'payables')
            ->assertJsonPath('payables.0.supplier_name', 'Provenderie du Plateau')
            ->assertJsonPath('payables.0.amount', '100000.00')
            ->assertJsonPath('payables.0.amount_paid', '40000.00');
    }

    /**
     * ⚠️⚠️ UNE DETTE SOLDÉE DISPARAÎT DU TIRAGE — et le poste, qui remplace sa
     * table à chaque fois, cesse de la porter à l'ardoise. Sans cela, la ferme
     * croirait devoir une somme déjà payée.
     */
    public function test_a_settled_debt_is_no_longer_served(): void
    {
        $this->pousser([$this->achat(['amount_paid' => 40000])])->assertOk();

        Payable::first()->update(['amount_paid' => 100000, 'status' => 'soldee']);

        $this->tirer()->assertOk()->assertJsonCount(0, 'payables');
    }

    /**
     * ⚠️⚠️ LES BONS DE COMMANDE RESTENT EN LECTURE SEULE : un envoi les concernant doit
     * être ignoré ET COMPTÉ — un rejet muet passerait pour un succès.
     *
     * ⚠️ TICKET 15.17 — LES FOURNISSEURS NE LE SONT PLUS : le poste peut créer, modifier
     * et archiver une fiche (voir `SyncFournisseurTest`). Mais seulement avec le droit
     * `manage-achats` : l'utilisateur de ce test n'a aucun rôle, son envoi est donc
     * REFUSÉ AVEC UN MOTIF (et non ignoré en silence), et la fiche n'est pas touchée.
     */
    public function test_orders_cannot_be_written_and_suppliers_need_the_right(): void
    {
        $reponse = $this->actingAs($this->utilisateur, 'sanctum')->postJson('/api/sync/push', [
            'suppliers' => [['id' => $this->fournisseur->id, 'name' => 'NOM FALSIFIÉ']],
            'purchase_orders' => [['id' => '99999999-9999-4999-8999-999999999999']],
        ]);

        $reponse->assertOk();
        $this->assertGreaterThanOrEqual(1, $reponse->json('referentiels_ignored'));
        $this->assertSame([], $reponse->json('suppliers.accepted'));
        $this->assertCount(1, $reponse->json('suppliers.rejected'));
        $this->assertSame('Provenderie du Plateau', $this->fournisseur->fresh()->name);
        $this->assertSame(0, PurchaseOrder::count());
    }
}
