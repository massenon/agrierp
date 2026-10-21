<?php

namespace Tests\Feature;

use App\Http\Controllers\Api\SyncController;
use App\Livewire\Ventes\ListeClients;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\CorrespondanceIdentifiant;
use App\Models\Customer;
use App\Models\CustomerAdvance;
use App\Models\FiscalYear;
use App\Models\LivestockSpecies;
use App\Models\Payable;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Purchase;
use App\Models\PurchaseLine;
use App\Models\Receivable;
use App\Models\Sale;
use App\Models\SaleLine;
use App\Models\StockMovement;
use App\Models\Supplier;
use App\Models\SupplierPayment;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Services\FusionReferentielsService;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket S-T5 (méthode TATACORA) — « le même article saisi sur deux postes n'existe qu'une fois ; le poste apprend
 * l'identifiant du serveur ». Deux postes créent hors ligne le même client, fournisseur ou produit : UNE fiche au
 * serveur, la correspondance enregistrée, rendue en `merged`, et toute référence ultérieure à l'identifiant du second
 * poste traduite vers la fiche du serveur. Jamais de fusion sans correspondance certaine.
 */
class SyncFusionReferentielsTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    /** @var array<string, string> jeton en clair par nom de poste */
    private array $jetons = [];

    private ProductCategory $categorie;

    private TreasuryAccount $caisse;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seed(RolesAndPermissionsSeeder::class);

        $this->admin = User::create([
            'name' => 'Admin', 'username' => 'admin', 'email' => 'dg@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->admin->assignRole('admin');

        foreach (['POSTE-A', 'POSTE-B'] as $poste) {
            $this->jetons[$poste] = $this->admin->createToken($poste, ['*'], now()->addDays(90))->plainTextToken;
        }

        $this->categorie = ProductCategory::create(['label' => 'Aviculture', 'is_active' => true]);

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

        foreach ([
            ['411', 'Clients', 4], ['419', 'Avances et acomptes reçus', 4], ['401', 'Fournisseurs', 4],
            ['531', 'Caisse', 5], ['601', 'Achats de marchandises', 6], ['701', 'Ventes', 7],
        ] as [$code, $libelle, $classe]) {
            ChartOfAccount::firstOrCreate(['code' => $code], ['label' => $libelle, 'class' => $classe, 'is_active' => true]);
        }
    }

    /** Envoi d'un poste, avec SON jeton (S-T2 : `device_id` = nom du jeton). */
    private function pousser(string $poste, array $corps): TestResponse
    {
        $this->app['auth']->forgetGuards();

        return $this->withToken($this->jetons[$poste])
            ->postJson('/api/sync/push', array_merge(['device_id' => $poste], $corps))
            ->assertOk();
    }

    private function client(array $remplace = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'name' => 'AMOUSSOU Régis',
            'phone' => '+229 97 12 34 56',
            'email' => null,
            'city' => 'Ikpinlè',
            'is_active' => true,
        ], $remplace);
    }

    private function fournisseur(array $remplace = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'name' => 'Provenderie du Plateau',
            'category' => 'Aliments',
            'phone' => '+229 96 00 11 22',
            'is_active' => true,
        ], $remplace);
    }

    private function produit(array $remplace = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'sku' => 'LOC-'.Str::random(6),
            'name' => 'Poulet fermier',
            'category_id' => $this->categorie->id,
            'unit' => 'u',
            'pricing_mode' => 'fourchette',
            'price_min' => 3000,
            'price_max' => 4000,
            'tva_rate' => 0,
            'stock_qty' => 12,
            'alert_threshold' => 5,
        ], $remplace);
    }

    // ── Deux postes, une seule fiche ────────────────────────────────────────────────────────────────────────────────

    public function test_deux_postes_creent_le_meme_client_un_seul_au_serveur_et_la_correspondance_est_rendue(): void
    {
        $a = $this->client();
        // Même personne saisie autrement : casse, accents, espaces, téléphone au format international.
        $b = $this->client(['name' => '  amoussou   regis ', 'phone' => '0022997123456', 'city' => 'Pobè']);

        $this->pousser('POSTE-A', ['customers' => [$a]]);
        $r = $this->pousser('POSTE-B', ['customers' => [$b]]);

        $this->assertSame(1, Customer::count(), 'le même client ne doit exister qu\'une fois');
        $this->assertNotNull(Customer::find($a['id']));
        $this->assertNull(Customer::find($b['id']), 'aucune seconde fiche sous l\'identifiant du poste B');
        $this->assertSame('Ikpinlè', Customer::find($a['id'])->city, 'la fiche du serveur est gardée telle quelle');

        // Poste ancien : l'identifiant reste ACCEPTÉ (il est bien arrivé). Poste à jour : il lit `merged`.
        $this->assertSame([$b['id']], $r->json('customers.accepted'));
        $this->assertSame([], $r->json('customers.rejected'));
        $this->assertSame($b['id'], $r->json('customers.merged.0.id'));
        $this->assertSame($a['id'], $r->json('customers.merged.0.id_serveur'));
        $this->assertStringContainsString('existe déjà', $r->json('customers.merged.0.motif'));

        $c = CorrespondanceIdentifiant::sole();
        $this->assertSame('customers', $c->table_referentiel);
        $this->assertSame($b['id'], $c->id_poste);
        $this->assertSame($a['id'], $c->id_serveur);
        $this->assertSame('POSTE-B', $c->poste, 'le poste est celui du jeton');
        $this->assertSame($this->admin->id, $c->user_id);
        $this->assertNotNull($c->fusionne_le);
        $this->assertDatabaseHas('audit_logs', ['action' => 'customer.merged']);
    }

    public function test_deux_postes_creent_le_meme_fournisseur_un_seul_au_serveur(): void
    {
        $a = $this->fournisseur();
        $b = $this->fournisseur(['name' => 'PROVENDERIE DU PLATEAU', 'phone' => '96-00-11-22', 'category' => 'Matériel']);

        $this->pousser('POSTE-A', ['suppliers' => [$a]]);
        $r = $this->pousser('POSTE-B', ['suppliers' => [$b]]);

        $this->assertSame(1, Supplier::count());
        $this->assertSame('Aliments', Supplier::find($a['id'])->category);
        $this->assertSame([$b['id']], $r->json('suppliers.accepted'));
        $this->assertSame(['id' => $b['id'], 'id_serveur' => $a['id']], array_intersect_key($r->json('suppliers.merged.0'), ['id' => 1, 'id_serveur' => 1]));
        $this->assertDatabaseHas('correspondances_identifiants', ['table_referentiel' => 'suppliers', 'id_poste' => $b['id'], 'id_serveur' => $a['id']]);
        $this->assertDatabaseHas('audit_logs', ['action' => 'supplier.merged']);
    }

    public function test_deux_postes_creent_le_meme_produit_un_seul_au_serveur_sans_ajouter_le_stock_initial(): void
    {
        $a = $this->produit(['stock_qty' => 12]);
        // Deux SKU PROVISOIRES différents : le SKU n'est pas la clé (le serveur l'engendre).
        $b = $this->produit(['name' => 'POULET  Fermier', 'stock_qty' => 30, 'price_min' => 2500]);

        $this->pousser('POSTE-A', ['products' => [$a]]);
        $r = $this->pousser('POSTE-B', ['products' => [$b]]);

        $this->assertSame(1, Product::count());
        $this->assertEquals(12, Product::find($a['id'])->stock_qty, 'le stock initial du second poste n\'est pas ajouté');
        $this->assertEquals(3000, Product::find($a['id'])->price_min);
        $this->assertSame([$b['id']], $r->json('products.accepted'));
        $this->assertSame($a['id'], $r->json('products.merged.0.id_serveur'));
        $this->assertStringContainsString('ajustement', $r->json('products.merged.0.motif'));
        $this->assertDatabaseHas('audit_logs', ['action' => 'product.merged']);
    }

    // ── Les références du second poste sont traduites ───────────────────────────────────────────────────────────────

    public function test_la_vente_a_credit_du_second_poste_est_rattachee_au_client_du_serveur(): void
    {
        $produit = $this->produit();
        $a = $this->client();
        $b = $this->client(['name' => 'Amoussou Régis']);
        $this->pousser('POSTE-A', ['customers' => [$a], 'products' => [$produit]]);
        $this->pousser('POSTE-B', ['customers' => [$b]]);

        // Envoi ULTÉRIEUR (autre lot) : la vente porte encore l'identifiant du poste B.
        $venteId = (string) Str::uuid();
        $r = $this->pousser('POSTE-B', ['sales' => [[
            'id' => $venteId, 'customer_id' => $b['id'], 'payment_mode' => 'credit',
            'subtotal' => 7000, 'discount' => 0, 'total' => 7000, 'status' => 'validee',
            'lines' => [['product_id' => $produit['id'], 'qty' => 2, 'unit_price' => 3500, 'manual_total_amount' => 7000]],
        ]]]);

        $this->assertSame([$venteId], $r->json('sales.accepted'), json_encode($r->json('sales.rejected')));
        $this->assertSame($a['id'], Sale::findOrFail($venteId)->customer_id);
        $this->assertSame($a['id'], Receivable::where('sale_id', $venteId)->sole()->customer_id, 'la créance est au client du serveur');
    }

    public function test_une_vente_du_meme_envoi_que_le_client_fusionne_est_aussi_rattachee(): void
    {
        $produit = $this->produit();
        $a = $this->client();
        $this->pousser('POSTE-A', ['customers' => [$a], 'products' => [$produit]]);

        $b = $this->client();
        $venteId = (string) Str::uuid();
        $r = $this->pousser('POSTE-B', [
            'sales' => [[
                'id' => $venteId, 'customer_id' => $b['id'], 'payment_mode' => 'credit',
                'subtotal' => 3500, 'discount' => 0, 'total' => 3500, 'status' => 'validee',
                'lines' => [['product_id' => $produit['id'], 'qty' => 1, 'unit_price' => 3500, 'manual_total_amount' => 3500]],
            ]],
            'customers' => [$b],
        ]);

        $this->assertSame([$venteId], $r->json('sales.accepted'), json_encode($r->json('sales.rejected')));
        $this->assertSame($a['id'], Sale::findOrFail($venteId)->customer_id);
    }

    public function test_la_ligne_de_vente_et_l_ajustement_sur_un_produit_fusionne_visent_le_produit_du_serveur(): void
    {
        $a = $this->produit(['stock_qty' => 20]);
        $b = $this->produit(['stock_qty' => 20]);
        $this->pousser('POSTE-A', ['products' => [$a]]);

        $venteId = (string) Str::uuid();
        $ref = (string) Str::uuid();
        $r = $this->pousser('POSTE-B', [
            'products' => [$b],
            'sales' => [[
                'id' => $venteId, 'payment_mode' => 'especes',
                'subtotal' => 3500, 'discount' => 0, 'total' => 3500, 'status' => 'validee',
                'lines' => [['product_id' => $b['id'], 'qty' => 1, 'unit_price' => 3500, 'manual_total_amount' => 3500]],
            ]],
            'stock_adjustments' => [[
                'client_ref' => $ref, 'product_id' => $b['id'], 'type' => 'entree',
                'quantity' => 4, 'reference_type' => 'ajustement',
            ]],
        ]);

        $this->assertSame([$venteId], $r->json('sales.accepted'), json_encode($r->json('sales.rejected')));
        $this->assertSame([$ref], $r->json('stock_adjustments.accepted'), json_encode($r->json('stock_adjustments.rejected')));
        $this->assertSame($a['id'], SaleLine::where('sale_id', $venteId)->sole()->product_id);
        $this->assertSame($a['id'], StockMovement::where('reference_id', $ref)->sole()->product_id);
        $this->assertEquals(20 - 1 + 4, Product::find($a['id'])->stock_qty);
    }

    public function test_achat_et_reglement_du_second_poste_vont_au_fournisseur_et_au_produit_du_serveur(): void
    {
        $fa = $this->fournisseur();
        $pa = $this->produit();
        $this->pousser('POSTE-A', ['suppliers' => [$fa], 'products' => [$pa]]);

        $fb = $this->fournisseur();
        $pb = $this->produit();
        $this->pousser('POSTE-B', ['suppliers' => [$fb], 'products' => [$pb]]);

        $achatId = (string) Str::uuid();
        $reglementId = (string) Str::uuid();
        $r = $this->pousser('POSTE-B', [
            'purchases' => [[
                'id' => $achatId, 'supplier_id' => $fb['id'], 'payment_mode' => 'credit',
                'treasury_account_id' => $this->caisse->id, 'amount_paid' => 0,
                'purchase_date' => now()->toDateString(),
                'lines' => [['product_id' => $pb['id'], 'qty' => 10, 'unit_price' => 2000]],
            ]],
            'supplier_payments' => [[
                'id' => $reglementId, 'supplier_id' => $fb['id'], 'treasury_account_id' => $this->caisse->id,
                'amount' => 5000, 'payment_date' => now()->toDateString(),
            ]],
        ]);

        $this->assertSame([$achatId], $r->json('purchases.accepted'), json_encode($r->json('purchases.rejected')));
        $this->assertSame([$reglementId], $r->json('supplier_payments.accepted'), json_encode($r->json('supplier_payments.rejected')));
        $this->assertSame($fa['id'], Purchase::findOrFail($achatId)->supplier_id);
        $this->assertSame($pa['id'], PurchaseLine::where('purchase_id', $achatId)->sole()->product_id);
        $this->assertSame($fa['id'], Payable::where('purchase_id', $achatId)->sole()->supplier_id);
        $this->assertSame($fa['id'], SupplierPayment::findOrFail($reglementId)->supplier_id);
        $this->assertSame(1, Supplier::count());
    }

    public function test_l_avance_du_second_poste_va_au_client_du_serveur(): void
    {
        $a = $this->client();
        $b = $this->client();
        $this->pousser('POSTE-A', ['customers' => [$a]]);
        $this->pousser('POSTE-B', ['customers' => [$b]]);

        $avanceId = (string) Str::uuid();
        $r = $this->pousser('POSTE-B', ['customer_advances' => [[
            'id' => $avanceId, 'customer_id' => $b['id'], 'treasury_account_id' => $this->caisse->id,
            'amount' => 10000, 'advance_date' => now()->toDateString(), 'payment_mode' => 'especes',
        ]]]);

        $this->assertSame([$avanceId], $r->json('customer_advances.accepted'), json_encode($r->json('customer_advances.rejected')));
        $this->assertSame($a['id'], CustomerAdvance::findOrFail($avanceId)->customer_id);
    }

    // ── Jamais de fusion sans correspondance certaine ───────────────────────────────────────────────────────────────

    public function test_deux_jean_sans_telephone_restent_deux_clients(): void
    {
        $this->pousser('POSTE-A', ['customers' => [$this->client(['name' => 'Jean', 'phone' => null])]]);
        $r = $this->pousser('POSTE-B', ['customers' => [$this->client(['name' => 'Jean', 'phone' => null])]]);

        $this->assertSame(2, Customer::count());
        $this->assertSame([], $r->json('customers.merged'));
        $this->assertSame(0, CorrespondanceIdentifiant::count());
    }

    public function test_meme_nom_mais_autre_telephone_ou_telephone_trop_court_ne_fusionne_pas(): void
    {
        $this->pousser('POSTE-A', ['customers' => [
            $this->client(),
            $this->client(['name' => 'Kossi', 'phone' => '1234']),
        ], 'suppliers' => [$this->fournisseur()]]);
        $this->pousser('POSTE-B', ['customers' => [
            $this->client(['phone' => '+229 97 12 34 57']),
            // « 97 12 34 56 » contre « 01 97 12 34 56 » : ancienne et nouvelle numérotation, aucune certitude.
            $this->client(['phone' => '01 97 12 34 56']),
            $this->client(['name' => 'Kossi', 'phone' => '1234']),
        ], 'suppliers' => [$this->fournisseur(['phone' => '+229 96 00 11 23'])]]);

        $this->assertSame(5, Customer::count());
        $this->assertSame(2, Supplier::count());
        $this->assertSame(0, CorrespondanceIdentifiant::count());
    }

    public function test_un_produit_d_une_autre_unite_categorie_ou_filiere_ne_fusionne_pas(): void
    {
        $autreCategorie = ProductCategory::create(['label' => 'Cuniculture', 'is_active' => true]);
        $espece = LivestockSpecies::create(['code' => 'lapins', 'label' => 'Lapins', 'is_enabled' => true]);

        $this->pousser('POSTE-A', ['products' => [$this->produit()]]);
        $this->pousser('POSTE-B', ['products' => [
            $this->produit(['unit' => 'kg']),
            $this->produit(['category_id' => $autreCategorie->id]),
            $this->produit(['species_id' => $espece->id]),
        ]]);

        $this->assertSame(4, Product::count());
        $this->assertSame(0, CorrespondanceIdentifiant::count());
    }

    public function test_une_fiche_archivee_au_serveur_ou_recue_archivee_ne_fusionne_pas(): void
    {
        $a = $this->client();
        $this->pousser('POSTE-A', ['customers' => [$a]]);
        Customer::find($a['id'])->update(['is_active' => false]);

        $this->pousser('POSTE-B', ['customers' => [$this->client()]]);
        $this->assertSame(2, Customer::count(), 'une fiche archivée n\'absorbe pas une création');

        $this->pousser('POSTE-B', ['customers' => [$this->client(['is_active' => false])]]);
        $this->assertSame(3, Customer::count(), 'une fiche reçue archivée ne se fusionne pas');
        $this->assertSame(0, CorrespondanceIdentifiant::count());
    }

    public function test_une_modification_ne_fusionne_jamais_deux_fiches_existantes(): void
    {
        $a = $this->client();
        $b = $this->client(['phone' => '+229 97 00 00 00']);
        $this->pousser('POSTE-A', ['customers' => [$a, $b]]);

        // B corrige son téléphone : il devient celui de A. C'est une modification de B, pas une création.
        $this->pousser('POSTE-A', ['customers' => [array_merge($b, ['phone' => $a['phone']])]]);

        $this->assertSame(2, Customer::count());
        $this->assertSame(0, CorrespondanceIdentifiant::count());
    }

    public function test_plusieurs_doublons_au_serveur_la_plus_ancienne_fiche_est_retenue(): void
    {
        $vieille = Customer::create(['name' => 'AMOUSSOU Régis', 'phone' => '97123456', 'is_active' => true]);
        $vieille->forceFill(['created_at' => now()->subYear()])->save();
        Customer::create(['name' => 'Amoussou Regis', 'phone' => '+229 97 12 34 56', 'is_active' => true]);

        $r = $this->pousser('POSTE-B', ['customers' => [$this->client()]]);

        $this->assertSame($vieille->id, $r->json('customers.merged.0.id_serveur'));
    }

    // ── Idempotence ─────────────────────────────────────────────────────────────────────────────────────────────────

    public function test_un_renvoi_apres_fusion_rend_la_meme_correspondance_sans_rien_ecrire(): void
    {
        $a = $this->client();
        $b = $this->client();
        $this->pousser('POSTE-A', ['customers' => [$a]]);
        $premiere = $this->pousser('POSTE-B', ['customers' => [$b]]);

        // Accusé perdu, puis poste ancien qui modifie ET archive sa copie : rien n'atteint la fiche partagée.
        $renvoi = $this->pousser('POSTE-B', ['customers' => [$b]]);
        $modif = $this->pousser('POSTE-B', ['customers' => [array_merge($b, ['city' => 'Kétou', 'is_active' => false])]]);

        $this->assertSame($premiere->json('customers.merged'), $renvoi->json('customers.merged'));
        $this->assertSame($premiere->json('customers.merged'), $modif->json('customers.merged'));
        $this->assertSame([$b['id']], $modif->json('customers.accepted'));
        $this->assertSame(1, Customer::count());
        $this->assertSame(1, CorrespondanceIdentifiant::count());
        $fiche = Customer::find($a['id']);
        $this->assertTrue((bool) $fiche->is_active, 'archiver la copie d\'un poste ancien n\'archive pas la fiche partagée');
        $this->assertSame('Ikpinlè', $fiche->city);
        $this->assertSame(1, AuditLog::where('action', 'customer.merged')->count());
    }

    public function test_le_meme_poste_qui_saisit_deux_fois_le_meme_client_dans_un_envoi_n_en_cree_qu_un(): void
    {
        $a = $this->client();
        $b = $this->client();
        $r = $this->pousser('POSTE-A', ['customers' => [$a, $b]]);

        $this->assertSame(1, Customer::count());
        $this->assertSame([$a['id'], $b['id']], $r->json('customers.accepted'));
        $this->assertSame($a['id'], $r->json('customers.merged.0.id_serveur'));
    }

    public function test_la_page_web_n_est_pas_concernee_par_la_fusion(): void
    {
        $this->pousser('POSTE-A', ['customers' => [$this->client()]]);
        $this->actingAs($this->admin);

        Livewire::test(ListeClients::class)
            ->set('name', 'AMOUSSOU Régis')
            ->set('phone', '+229 97 12 34 56')
            ->call('saveCustomer')
            ->assertHasNoErrors();

        $this->assertSame(2, Customer::count());
    }

    // ── Règle et garde-fous ─────────────────────────────────────────────────────────────────────────────────────────

    public function test_normalisation_des_noms_et_des_telephones(): void
    {
        $f = app(FusionReferentielsService::class);

        $this->assertSame('societe agricole d ikpinle', $f->normaliserNom("  SOCIÉTÉ  Agricole d'Ikpinlè "));
        $this->assertSame('97123456', $f->normaliserTelephone('+229 97 12 34 56'));
        $this->assertSame('97123456', $f->normaliserTelephone('00229 97-12-34-56'));
        $this->assertSame('97123456', $f->normaliserTelephone('97.12.34.56'));
        $this->assertSame('0197123456', $f->normaliserTelephone('+229 01 97 12 34 56'));
        $this->assertSame('0197123456', $f->normaliserTelephone('01 97 12 34 56'));
        // Un numéro national de 8 chiffres qui COMMENCE par 229 n'est pas un indicatif : il est gardé entier.
        $this->assertSame('22912345', $f->normaliserTelephone('22 91 23 45'));
        $this->assertNull($f->normaliserTelephone('1234567'));
        $this->assertNull($f->normaliserTelephone(null));
        $this->assertNull($f->cleNaturelle('customers', ['name' => 'Jean', 'phone' => null]));
        $this->assertNull($f->cleNaturelle('customers', ['name' => '  ', 'phone' => '97123456']));
        $this->assertNull($f->cleNaturelle('products', ['name' => 'Poulet', 'category_id' => null, 'unit' => 'u']));
        $this->assertSame(
            $f->cleNaturelle('suppliers', ['name' => 'Provenderie du Plateau', 'phone' => '+229 96 00 11 22']),
            $f->cleNaturelle('suppliers', ['name' => 'provenderie-du-plateau', 'phone' => '96001122']),
        );
    }

    public function test_traduire_envoi_remplace_chaque_chemin_declare_et_laisse_le_reste(): void
    {
        $f = app(FusionReferentielsService::class);
        $idPoste = (string) Str::uuid();
        $idServeur = (string) Str::uuid();
        $autre = (string) Str::uuid();
        foreach (['customers', 'products'] as $table) {
            CorrespondanceIdentifiant::create([
                'table_referentiel' => $table, 'id_poste' => $idPoste,
                'id_serveur' => $idServeur, 'cle_naturelle' => 'x', 'fusionne_le' => now(),
            ]);
        }

        $fiche = $f->traduireEnvoi('livestock_daily_entries', [
            ['id' => 'f1', 'feed_product_id' => $idPoste, 'treatment_product_id' => $autre],
            ['id' => 'f2', 'treatment_product_id' => $idPoste, 'lot_id' => $idPoste],
            'pas-un-tableau',
        ]);
        $this->assertSame($idServeur, $fiche[0]['feed_product_id']);
        $this->assertSame($autre, $fiche[0]['treatment_product_id']);
        $this->assertSame($idServeur, $fiche[1]['treatment_product_id']);
        $this->assertSame($idPoste, $fiche[1]['lot_id'], 'un champ non déclaré n\'est jamais traduit');
        $this->assertSame('pas-un-tableau', $fiche[2]);

        $vente = $f->traduireEnvoi('sales', [[
            'customer_id' => $idPoste,
            'lines' => [['product_id' => $idPoste], ['product_id' => $autre], 'x'],
        ]]);
        $this->assertSame($idServeur, $vente[0]['customer_id'], 'correspondance de la table customers');
        $this->assertSame($idServeur, $vente[0]['lines'][0]['product_id']);
        $this->assertSame($autre, $vente[0]['lines'][1]['product_id']);

        // Une correspondance de PRODUIT ne traduit pas un FOURNISSEUR de même identifiant.
        CorrespondanceIdentifiant::where('table_referentiel', 'customers')->delete();
        $achat = $f->traduireEnvoi('purchases', [['supplier_id' => $idPoste, 'lines' => [['product_id' => $idPoste]]]]);
        $this->assertSame($idPoste, $achat[0]['supplier_id']);
        $this->assertSame($idServeur, $achat[0]['lines'][0]['product_id']);

        $this->assertSame([['x' => $idPoste]], $f->traduireEnvoi('mails', [['x' => $idPoste]]), 'table non déclarée : rendue telle quelle');
    }

    /**
     * ⚠️⚠️ GARDE-FOU — chaque référence validée par `SyncController` vers un client, un fournisseur ou un produit
     * (`customer_id`, `supplier_id`, `…product_id`) est déclarée dans `FusionReferentielsService::REFERENCES`, et
     * chaque table déclarée passe par `envoiTraduit()` dans `push`. Une nouvelle table d'envoi portant une telle
     * référence, oubliée ici, ferait rattacher ses enregistrements à un identifiant de poste fusionné qui n'existe
     * pas au serveur : refus « inconnu », ou — pire — référence orpheline.
     */
    public function test_garde_fou_toute_reference_vers_les_trois_referentiels_est_traduite(): void
    {
        $source = file_get_contents((new \ReflectionClass(SyncController::class))->getFileName());

        // Les champs de validation des traitements d'envoi (le tirage ne valide rien).
        $debutPush = strpos($source, 'public function push(');
        preg_match_all("/'((?:[a-z_]+\\.\\*\\.)?[a-z_]*(?:customer|supplier|product)_id)'\\s*=>\\s*\\[/", substr($source, $debutPush), $m);
        $champs = array_unique($m[1]);
        $this->assertNotEmpty($champs);

        $declares = [];
        foreach (FusionReferentielsService::REFERENCES as $chemins) {
            foreach (array_keys($chemins) as $chemin) {
                $declares[$chemin] = true;
            }
        }
        foreach ($champs as $champ) {
            $this->assertArrayHasKey($champ, $declares, "« {$champ} » est validé par un envoi mais n'est déclaré dans aucune table de FusionReferentielsService::REFERENCES");
        }

        foreach (array_keys(FusionReferentielsService::REFERENCES) as $table) {
            $this->assertStringContainsString("\$this->envoiTraduit(\$request, '{$table}')", $source, "la table « {$table} » n'est pas traduite par push()");
            $this->assertStringNotContainsString("\$request->input('{$table}')", $source, "la table « {$table} » est lue sans traduction");
        }

        // Chaque table déclarée a bien un traitement d'envoi.
        foreach (array_keys(FusionReferentielsService::REFERENCES) as $table) {
            $this->assertContains($table, (new \ReflectionClassConstant(SyncController::class, 'CLES_DE_PUSH'))->getValue());
        }
    }
}
