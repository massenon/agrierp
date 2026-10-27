<?php

namespace Tests\Feature;

use App\Livewire\Achats\BonsCommande;
use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\Payable;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Purchase;
use App\Models\PurchaseOrder;
use App\Models\Role;
use App\Models\Supplier;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket AC-1 — LES BONS DE COMMANDE SE SAISISSENT ET SE RÉCEPTIONNENT AU POSTE.
 *
 * Saisie : `SaisieBonCommandeAction`, partagée avec `BonsCommande::generateBc`. Réception : un ACHAT du poste qui porte
 * `purchase_order_id` passe par `ReceptionBonCommandeService`, partagé avec `BonsCommande::confirmReceiveOrder` — les
 * lignes sont celles du BON, jamais celles du poste, et un bon ne se reçoit qu'une fois.
 */
class SyncBonsCommandeTest extends TestCase
{
    use RefreshDatabase;

    private User $acheteur;

    private User $lecteur;

    private Supplier $fournisseur;

    private Product $aliment;

    protected function setUp(): void
    {
        parent::setUp();

        Permission::findOrCreate('manage-achats', 'web');
        Permission::findOrCreate('view-achats', 'web');
        Role::findOrCreate('acheteur', 'web')->givePermissionTo(['manage-achats', 'view-achats']);
        Role::findOrCreate('lecteur', 'web')->givePermissionTo('view-achats');
        $this->acheteur = $this->utilisateur('acheteur');
        $this->lecteur = $this->utilisateur('lecteur');

        $this->fournisseur = Supplier::create(['name' => 'Provenderie du Plateau', 'category' => 'Aliments', 'is_active' => true]);
        $this->aliment = Product::create([
            'sku' => 'ALI-PONTE-25', 'name' => 'Aliment ponte 25kg',
            'category_id' => ProductCategory::create(['label' => 'Aliments', 'is_active' => true])->id,
            'unit' => 'sac', 'pricing_mode' => 'fourchette', 'price_min' => 5900, 'price_max' => 5900,
            'tva_rate' => 18, 'stock_qty' => 5, 'is_active' => true,
        ]);
        FiscalYear::create([
            'year' => (int) now()->format('Y'),
            'start_date' => now()->startOfYear()->toDateString(),
            'end_date' => now()->endOfYear()->toDateString(),
            'status' => 'ouvert',
        ]);
        foreach ([['601', 'Achats', 6], ['401', 'Fournisseurs', 4], ['445', 'TVA récupérable', 4], ['531', 'Caisse', 5]] as [$code, $libelle, $classe]) {
            ChartOfAccount::firstOrCreate(['code' => $code], ['label' => $libelle, 'class' => $classe, 'is_active' => true]);
        }
    }

    private function utilisateur(string $role): User
    {
        $u = User::create([
            'name' => ucfirst($role), 'username' => $role, 'email' => $role.'@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    /** @return array<string, mixed> */
    private function bon(array $remplace = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'supplier_id' => $this->fournisseur->id,
            'expected_delivery_date' => now()->addDays(5)->toDateString(),
            'lines' => [['id' => (string) Str::uuid(), 'product_id' => $this->aliment->id, 'qty' => 10, 'estimated_unit_price' => 6000]],
        ], $remplace);
    }

    private function envoyer(User $u, string $cle, array $lignes)
    {
        return $this->actingAs($u, 'sanctum')->postJson('/api/sync/push', ['device_id' => 'poste-test', $cle => $lignes]);
    }

    public function test_un_bon_du_poste_est_cree_envoye_avec_ses_lignes_et_rejoue_sans_doublon(): void
    {
        $bon = $this->bon();

        $this->envoyer($this->acheteur, 'purchase_orders', [$bon])->assertOk()->assertJsonPath('purchase_orders.accepted.0', $bon['id']);
        $this->envoyer($this->acheteur, 'purchase_orders', [$bon])->assertOk()->assertJsonPath('purchase_orders.accepted.0', $bon['id']);

        $this->assertSame(1, PurchaseOrder::count());
        $cree = PurchaseOrder::with('lines')->findOrFail($bon['id']);
        $this->assertSame('envoye', $cree->status);
        $this->assertSame($this->fournisseur->id, $cree->supplier_id);
        $this->assertSame(now()->addDays(5)->toDateString(), $cree->expected_delivery_date->toDateString());
        $this->assertCount(1, $cree->lines);
        $this->assertSame($bon['lines'][0]['id'], $cree->lines->first()->id);
        $this->assertSame(60000.0, (float) $cree->lines->sum(fn ($l) => $l->qty * $l->estimated_unit_price));
    }

    public function test_un_bon_sans_droit_ou_incomplet_est_refuse_avec_son_motif(): void
    {
        $refus = $this->envoyer($this->lecteur, 'purchase_orders', [$this->bon()])->assertOk();
        $this->assertStringContainsString('votre rôle ne permet pas', mb_strtolower($refus->json('purchase_orders.rejected.0.reason')));

        $sansLigne = $this->bon(['lines' => []]);
        $reponse = $this->envoyer($this->acheteur, 'purchase_orders', [$sansLigne])->assertOk();
        $this->assertStringContainsString('lignes', $reponse->json('purchase_orders.rejected.0.reason'));

        $inconnu = $this->bon(['supplier_id' => (string) Str::uuid()]);
        $reponse = $this->envoyer($this->acheteur, 'purchase_orders', [$inconnu])->assertOk();
        $this->assertNotEmpty($reponse->json('purchase_orders.rejected.0.reason'));

        $this->assertSame(0, PurchaseOrder::count());
    }

    public function test_la_reception_du_poste_recoit_le_bon_avec_ses_lignes_dette_entiere_et_ecriture(): void
    {
        $bon = $this->bon();
        $this->envoyer($this->acheteur, 'purchase_orders', [$bon]);
        $achat = [
            'id' => (string) Str::uuid(), 'supplier_id' => $this->fournisseur->id, 'purchase_order_id' => $bon['id'],
            'payment_mode' => 'credit', 'amount_paid' => 0, 'purchase_date' => now()->toDateString(),
            // Un poste qui enverrait d'autres lignes n'est PAS obéi : le bon est le maître.
            'lines' => [['product_id' => $this->aliment->id, 'qty' => 99, 'unit_price' => 1]],
        ];

        $this->envoyer($this->acheteur, 'purchases', [$achat])->assertOk()->assertJsonPath('purchases.accepted.0', $achat['id']);

        $this->assertSame('recu', PurchaseOrder::findOrFail($bon['id'])->status);
        $recu = Purchase::with('lines')->findOrFail($achat['id']);
        $this->assertSame($bon['id'], $recu->purchase_order_id);
        $this->assertSame(60000.0, (float) $recu->total);
        $this->assertSame(10.0, (float) $recu->lines->first()->qty);
        $this->assertSame(15.0, (float) $this->aliment->fresh()->stock_qty, '5 en stock + 10 reçus');
        $this->assertSame(60000.0, (float) Payable::where('purchase_id', $achat['id'])->sum('amount'));
        $this->assertNotNull($recu->accounting_entry_id, 'l\'écriture D 601 + 445 / C 401 est passée');
        $this->assertSame(1, AccountingEntry::count());
    }

    public function test_un_bon_deja_recu_rejette_la_seconde_reception_sans_rien_rejouer(): void
    {
        $bon = $this->bon();
        $this->envoyer($this->acheteur, 'purchase_orders', [$bon]);
        $achat = fn () => [
            'id' => (string) Str::uuid(), 'supplier_id' => $this->fournisseur->id, 'purchase_order_id' => $bon['id'],
            'payment_mode' => 'credit', 'purchase_date' => now()->toDateString(),
            'lines' => [['product_id' => $this->aliment->id, 'qty' => 10, 'unit_price' => 6000]],
        ];
        $this->envoyer($this->acheteur, 'purchases', [$achat()])->assertOk();

        $reponse = $this->envoyer($this->acheteur, 'purchases', [$achat()])->assertOk();

        $this->assertSame('Ce bon de commande est déjà reçu : une seule réception est possible.', $reponse->json('purchases.rejected.0.reason'));
        $this->assertSame(1, Purchase::count());
        $this->assertSame(15.0, (float) $this->aliment->fresh()->stock_qty);
    }

    public function test_le_web_et_le_poste_partagent_les_memes_points_de_passage(): void
    {
        $this->actingAs($this->acheteur);
        Livewire::test(BonsCommande::class)
            ->set('supplierId', $this->fournisseur->id)
            ->set('lineProductId', $this->aliment->id)
            ->set('lineQty', 4)
            ->set('linePrice', 6000)
            ->call('addLine')
            ->call('generateBc');

        $bon = PurchaseOrder::with('lines')->firstOrFail();
        $this->assertSame('envoye', $bon->status);
        $this->assertSame(4.0, (float) $bon->lines->first()->qty);

        Livewire::test(BonsCommande::class)->set('receivingOrderId', $bon->id)->call('confirmReceiveOrder');
        $this->assertSame('recu', $bon->fresh()->status);
        $this->assertSame(9.0, (float) $this->aliment->fresh()->stock_qty);
    }

    public function test_le_tirage_sert_les_lignes_du_bon(): void
    {
        $bon = $this->bon();
        $this->envoyer($this->acheteur, 'purchase_orders', [$bon]);

        $reponse = $this->actingAs($this->acheteur, 'sanctum')->getJson('/api/sync/pull?device_id=poste-test')->assertOk();

        $servi = collect($reponse->json('purchase_orders'))->firstWhere('id', $bon['id']);
        $this->assertSame(60000.0, (float) $servi['estimated_total']);
        $this->assertSame($bon['lines'][0]['id'], $servi['lines'][0]['id']);
        $this->assertSame(10.0, (float) $servi['lines'][0]['qty']);
        $this->assertSame(6000.0, (float) $servi['lines'][0]['estimated_unit_price']);
    }

    /**
     * Ticket AC-2 — les boutons « + » de l'achat : le fournisseur créé à la volée porte « Autre » (le serveur exige une
     * catégorie à l'envoi), le produit une tarification à zéro à compléter au Catalogue ; tous deux sont sélectionnés.
     */
    public function test_les_creations_a_la_volee_de_l_achat_posent_une_categorie_et_selectionnent_la_fiche(): void
    {
        $this->actingAs($this->acheteur);
        $categorie = ProductCategory::firstOrFail();

        $page = Livewire::test(\App\Livewire\Achats\EnregistrerAchat::class)
            ->set('newSupplierName', 'Nouveau Fournisseur SARL')
            ->set('newSupplierPhone', '+229 97 00 00 00')
            ->call('saveNewSupplier')
            ->set('newProductName', 'Maïs concassé')
            ->set('newProductCategoryId', $categorie->id)
            ->set('newProductUnit', 'sac')
            ->call('saveNewProduct');

        $fournisseur = Supplier::where('name', 'Nouveau Fournisseur SARL')->firstOrFail();
        $this->assertSame('Autre', $fournisseur->category);
        $this->assertSame($fournisseur->id, $page->get('supplierId'));
        $produit = Product::where('name', 'Maïs concassé')->firstOrFail();
        $this->assertSame('sac', $produit->unit);
        $this->assertSame(0.0, (float) $produit->price_min);
        $this->assertSame($produit->id, $page->get('lineProductId'));
    }
}
