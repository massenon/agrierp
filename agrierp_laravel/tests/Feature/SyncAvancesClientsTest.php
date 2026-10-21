<?php

namespace Tests\Feature;

use App\Models\AccountingEntry;
use App\Models\AccountingEntryLine;
use App\Models\AdvanceImputation;
use App\Models\ChartOfAccount;
use App\Models\Customer;
use App\Models\CustomerAdvance;
use App\Models\FiscalYear;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Receivable;
use App\Models\Role;
use App\Models\TreasuryAccount;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Ticket 15.19 — AVANCES CLIENTS ET IMPUTATIONS ENVOYÉES PAR UN POSTE.
 *
 * ⚠️⚠️ CE QUE CES TESTS PROTÈGENT. Le poste n'envoie que le FAIT (« tant, de ce client, dans ce
 * compte » ; « tant de cette avance sur cette créance »). Le serveur applique les effets : entrée
 * en trésorerie (DEUX livres), écriture Débit 5xx / Crédit 419, plafonnement, Débit 419 / Crédit
 * 411. Et le renvoi d'un envoi dont l'accusé s'est perdu ne doit RIEN rejouer — sinon l'argent
 * d'un acompte entre deux fois en caisse.
 */
class SyncAvancesClientsTest extends TestCase
{
    use RefreshDatabase;

    private User $vendeur;

    private User $lecteur;

    private Customer $client;

    private TreasuryAccount $caisse;

    protected function setUp(): void
    {
        parent::setUp();

        Permission::findOrCreate('manage-ventes', 'web');
        Role::findOrCreate('vendeur', 'web')->givePermissionTo('manage-ventes');
        Role::findOrCreate('lecteur', 'web');

        $this->vendeur = $this->utilisateur('vendeur');
        $this->lecteur = $this->utilisateur('lecteur');

        $this->client = Customer::create(['name' => 'AMOUSSOU Régis', 'is_active' => true]);

        $this->caisse = TreasuryAccount::create([
            'label' => 'Caisse Physique', 'account_code' => '531',
            'type' => 'caisse', 'balance' => 100000, 'is_active' => true,
        ]);

        FiscalYear::create([
            'year' => (int) now()->format('Y'),
            'start_date' => now()->startOfYear()->toDateString(),
            'end_date' => now()->endOfYear()->toDateString(),
            'status' => 'ouvert',
        ]);

        foreach ([
            ['411', 'Clients', 4], ['419', 'Avances et acomptes reçus', 4], ['531', 'Caisse', 5],
            ['701', 'Ventes', 7],
        ] as [$code, $libelle, $classe]) {
            ChartOfAccount::firstOrCreate(['code' => $code], [
                'label' => $libelle, 'class' => $classe, 'is_active' => true,
            ]);
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

    private function avance(array $remplace = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'customer_id' => $this->client->id,
            'treasury_account_id' => $this->caisse->id,
            'amount' => 40000,
            'advance_date' => now()->toDateString(),
            'payment_mode' => 'especes',
            'motif' => 'Réservation 50 poussins',
        ], $remplace);
    }

    private function creance(float $montant, float $paye = 0, ?Customer $client = null): Receivable
    {
        return Receivable::create([
            'customer_id' => ($client ?? $this->client)->id,
            'amount' => $montant, 'amount_paid' => $paye,
            'due_date' => now()->addDays(10)->toDateString(), 'status' => 'en_cours',
        ]);
    }

    private function imputation(CustomerAdvance|array $avance, Receivable $creance, float $montant, array $remplace = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'customer_advance_id' => is_array($avance) ? $avance['id'] : $avance->id,
            'receivable_id' => $creance->id,
            'amount' => $montant,
            'imputation_date' => now()->toDateString(),
        ], $remplace);
    }

    private function pousser(User $u, array $corps): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($u, 'sanctum')->postJson('/api/sync/push', array_merge(['device_id' => 'poste-test'], $corps))->assertOk();
    }

    /** Recalcul INDÉPENDANT : Σ débits − Σ crédits des lignes d'un compte. */
    private function soldeGrandLivre(string $code): float
    {
        $compte = ChartOfAccount::where('code', $code)->firstOrFail();

        return round(
            (float) AccountingEntryLine::where('account_id', $compte->id)->sum('debit')
            - (float) AccountingEntryLine::where('account_id', $compte->id)->sum('credit'),
            2
        );
    }

    /** Une avance reçue d'un poste garde l'id du poste et ses colonnes de réception. */
    public function test_une_avance_arrive_avec_l_id_du_poste_et_ses_colonnes(): void
    {
        $a = $this->avance();
        $r = $this->pousser($this->vendeur, ['customer_advances' => [$a]]);

        $this->assertSame([$a['id']], $r->json('customer_advances.accepted'));
        $this->assertSame([], $r->json('customer_advances.rejected'));

        $enBase = CustomerAdvance::findOrFail($a['id']);
        $this->assertEquals(40000, $enBase->amount);
        $this->assertSame($this->caisse->id, $enBase->treasury_account_id);
        $this->assertSame('especes', $enBase->payment_mode);
        $this->assertSame('Réservation 50 poussins', $enBase->motif);
        $this->assertSame('poste-test', $enBase->device_id);
        $this->assertTrue($enBase->is_active);
    }

    /** L'exception à « référentiel = le serveur gagne » : plus comptée dans les ignorés. */
    public function test_customer_advances_n_est_plus_un_referentiel_ignore(): void
    {
        $r = $this->pousser($this->vendeur, ['customer_advances' => [$this->avance()]]);

        $this->assertSame(0, $r->json('referentiels_ignored'));
    }

    /** DEUX livres de trésorerie concordants, recalculés indépendamment. */
    public function test_les_deux_livres_de_tresorerie_concordent(): void
    {
        $this->pousser($this->vendeur, ['customer_advances' => [$this->avance(['amount' => 40000]), $this->avance(['amount' => 15000])]]);

        // Livre 1 : somme des soldes de la table.
        $this->assertEquals(155000, (float) TreasuryAccount::sum('balance'));
        // Livre 2 : classe 5 du grand livre = 40 000 + 15 000 entrés.
        $this->assertEquals(55000.0, $this->soldeGrandLivre('531'));
        $this->assertEquals(-55000.0, $this->soldeGrandLivre('419'));
        // La variation des deux livres est la même.
        $this->assertEquals(
            (float) TreasuryAccount::sum('balance') - 100000.0,
            $this->soldeGrandLivre('531'),
        );
    }

    public function test_un_renvoi_est_un_acquittement_sans_rejeu(): void
    {
        $a = $this->avance();

        $this->pousser($this->vendeur, ['customer_advances' => [$a]]);
        $r = $this->pousser($this->vendeur, ['customer_advances' => [$a]]);

        $this->assertSame([$a['id']], $r->json('customer_advances.accepted'));
        $this->assertSame(1, CustomerAdvance::count());
        $this->assertEquals(140000, $this->caisse->fresh()->balance, "l'argent n'entre qu'une fois");
        $this->assertSame(1, AccountingEntry::where('source_type', 'customer_advance')->count());
    }

    public function test_un_renvoi_reste_acquitte_meme_si_l_exercice_a_ete_clos_entre_temps(): void
    {
        $a = $this->avance();
        $this->pousser($this->vendeur, ['customer_advances' => [$a]]);

        FiscalYear::query()->update(['status' => 'cloture']);
        $r = $this->pousser($this->vendeur, ['customer_advances' => [$a]]);

        $this->assertSame([$a['id']], $r->json('customer_advances.accepted'));
        $this->assertSame([], $r->json('customer_advances.rejected'));
    }

    public function test_sans_le_droit_manage_ventes_rien_ne_bouge(): void
    {
        $r = $this->pousser($this->lecteur, [
            'customer_advances' => [$this->avance()],
            'advance_imputations' => [$this->imputation($this->avance(), $this->creance(1000), 500)],
        ]);

        $this->assertSame([], $r->json('customer_advances.accepted'));
        $this->assertStringContainsString('rôle', $r->json('customer_advances.rejected.0.reason'));
        $this->assertSame([], $r->json('advance_imputations.accepted'));
        $this->assertStringContainsString('rôle', $r->json('advance_imputations.rejected.0.reason'));
        $this->assertSame(0, CustomerAdvance::count());
        $this->assertEquals(100000, $this->caisse->fresh()->balance);
    }

    public function test_un_exercice_clos_refuse_l_avance_avec_son_motif_sans_toucher_la_caisse(): void
    {
        FiscalYear::query()->update(['status' => 'cloture']);

        $r = $this->pousser($this->vendeur, ['customer_advances' => [$this->avance()]]);

        $this->assertSame([], $r->json('customer_advances.accepted'));
        $this->assertStringContainsString('exercice', $r->json('customer_advances.rejected.0.reason'));
        $this->assertSame(0, CustomerAdvance::count());
        $this->assertEquals(100000, $this->caisse->fresh()->balance);
    }

    public function test_aucune_date_hors_exercice_ne_passe(): void
    {
        $r = $this->pousser($this->vendeur, ['customer_advances' => [
            $this->avance(['advance_date' => now()->subYears(3)->toDateString()]),
        ]]);

        $this->assertSame([], $r->json('customer_advances.accepted'));
        $this->assertCount(1, $r->json('customer_advances.rejected'));
        $this->assertEquals(100000, $this->caisse->fresh()->balance);
    }

    public function test_chaque_refus_est_rendu_avec_son_motif_et_les_autres_avances_passent(): void
    {
        $bonne = $this->avance(['amount' => 12000]);
        $r = $this->pousser($this->vendeur, ['customer_advances' => [
            $this->avance(['amount' => 0]),
            $this->avance(['id' => 'pas-un-uuid']),
            $this->avance(['customer_id' => (string) Str::uuid()]),
            $this->avance(['treasury_account_id' => (string) Str::uuid()]),
            $this->avance(['payment_mode' => 'troc']),
            $bonne,
        ]]);

        $this->assertSame([$bonne['id']], $r->json('customer_advances.accepted'));
        $this->assertCount(5, $r->json('customer_advances.rejected'));
        foreach ($r->json('customer_advances.rejected') as $refus) {
            $this->assertNotSame('', trim($refus['reason']), 'un refus sans motif est un refus muet');
        }
        $this->assertEquals(112000, $this->caisse->fresh()->balance, 'seule la bonne avance est entrée');
    }

    public function test_sans_compte_419_rien_n_entre_en_caisse(): void
    {
        ChartOfAccount::where('code', '419')->delete();

        $r = $this->pousser($this->vendeur, ['customer_advances' => [$this->avance()]]);

        $this->assertSame([], $r->json('customer_advances.accepted'));
        $this->assertStringContainsString('419', $r->json('customer_advances.rejected.0.reason'));
        $this->assertEquals(100000, $this->caisse->fresh()->balance);
    }

    // --- imputations -----------------------------------------------------

    private function avanceEnBase(float $montant = 40000, float $utilise = 0): CustomerAdvance
    {
        $a = new CustomerAdvance();
        $a->id = (string) Str::uuid();
        $a->fill([
            'customer_id' => $this->client->id, 'amount' => $montant, 'amount_used' => $utilise,
            'advance_date' => now()->toDateString(), 'is_active' => true,
        ]);
        $a->save();

        return $a;
    }

    public function test_l_imputation_est_plafonnee_au_solde_de_la_creance(): void
    {
        $avance = $this->avanceEnBase(40000);
        $creance = $this->creance(25000);
        $i = $this->imputation($avance, $creance, 40000);

        $r = $this->pousser($this->vendeur, ['advance_imputations' => [$i]]);

        $this->assertSame([$i['id']], $r->json('advance_imputations.accepted'));
        $this->assertEquals(25000, $creance->fresh()->amount_paid);
        $this->assertEquals(25000, $avance->fresh()->amount_used);
        $this->assertEquals(25000, AdvanceImputation::findOrFail($i['id'])->applied_amount);
        $this->assertEquals(40000, AdvanceImputation::findOrFail($i['id'])->amount, 'la demande est conservée');
    }

    public function test_l_imputation_est_plafonnee_au_reste_de_l_avance(): void
    {
        $avance = $this->avanceEnBase(40000, 30000);   // reste 10 000
        $creance = $this->creance(90000);

        $this->pousser($this->vendeur, ['advance_imputations' => [$this->imputation($avance, $creance, 50000)]]);

        $this->assertEquals(10000, $creance->fresh()->amount_paid);
        $this->assertEquals(40000, $avance->fresh()->amount_used);
    }

    public function test_l_imputation_est_plafonnee_au_montant_demande(): void
    {
        $avance = $this->avanceEnBase(40000);
        $creance = $this->creance(90000);

        $this->pousser($this->vendeur, ['advance_imputations' => [$this->imputation($avance, $creance, 7000)]]);

        $this->assertEquals(7000, $creance->fresh()->amount_paid);
        $this->assertEquals(7000, $avance->fresh()->amount_used);
    }

    public function test_une_creance_soldee_est_refusee_avec_son_motif(): void
    {
        $avance = $this->avanceEnBase(40000);
        $creance = $this->creance(10000, 10000);

        $r = $this->pousser($this->vendeur, ['advance_imputations' => [$this->imputation($avance, $creance, 5000)]]);

        $this->assertSame([], $r->json('advance_imputations.accepted'));
        $this->assertStringContainsString('soldée', $r->json('advance_imputations.rejected.0.reason'));
        $this->assertEquals(0, $avance->fresh()->amount_used);
        $this->assertSame(0, AccountingEntry::count(), "pas d'écriture à zéro");
    }

    public function test_une_avance_epuisee_est_refusee_avec_son_motif(): void
    {
        $avance = $this->avanceEnBase(40000, 40000);
        $creance = $this->creance(10000);

        $r = $this->pousser($this->vendeur, ['advance_imputations' => [$this->imputation($avance, $creance, 5000)]]);

        $this->assertSame([], $r->json('advance_imputations.accepted'));
        $this->assertStringContainsString('imputée', $r->json('advance_imputations.rejected.0.reason'));
        $this->assertEquals(0, $creance->fresh()->amount_paid);
    }

    public function test_une_creance_d_un_autre_client_est_refusee(): void
    {
        $autre = Customer::create(['name' => 'TOSSOU Marcel', 'is_active' => true]);
        $avance = $this->avanceEnBase(40000);
        $creance = $this->creance(10000, 0, $autre);

        $r = $this->pousser($this->vendeur, ['advance_imputations' => [$this->imputation($avance, $creance, 5000)]]);

        $this->assertSame([], $r->json('advance_imputations.accepted'));
        $this->assertStringContainsString('client', $r->json('advance_imputations.rejected.0.reason'));
        $this->assertEquals(0, $creance->fresh()->amount_paid);
    }

    public function test_un_exercice_clos_refuse_l_imputation_sans_rien_modifier(): void
    {
        $avance = $this->avanceEnBase(40000);
        $creance = $this->creance(10000);
        FiscalYear::query()->update(['status' => 'cloture']);

        $r = $this->pousser($this->vendeur, ['advance_imputations' => [$this->imputation($avance, $creance, 5000)]]);

        $this->assertSame([], $r->json('advance_imputations.accepted'));
        $this->assertCount(1, $r->json('advance_imputations.rejected'));
        $this->assertEquals(0, $creance->fresh()->amount_paid, 'transaction annulée');
        $this->assertEquals(0, $avance->fresh()->amount_used);
        $this->assertSame(0, AdvanceImputation::count());
    }

    public function test_un_renvoi_d_imputation_n_impute_pas_deux_fois(): void
    {
        $avance = $this->avanceEnBase(40000);
        $creance = $this->creance(30000);
        $i = $this->imputation($avance, $creance, 10000);

        $this->pousser($this->vendeur, ['advance_imputations' => [$i]]);
        $r = $this->pousser($this->vendeur, ['advance_imputations' => [$i]]);

        $this->assertSame([$i['id']], $r->json('advance_imputations.accepted'));
        $this->assertEquals(10000, $creance->fresh()->amount_paid, 'imputée une seule fois');
        $this->assertEquals(10000, $avance->fresh()->amount_used);
        $this->assertSame(1, AdvanceImputation::count());
        $this->assertSame(1, AccountingEntry::where('source_type', 'advance_imputation')->count());
    }

    public function test_l_imputation_passe_419_contre_411_sans_tresorerie(): void
    {
        $avance = $this->avanceEnBase(40000);
        $creance = $this->creance(30000);

        $this->pousser($this->vendeur, ['advance_imputations' => [$this->imputation($avance, $creance, 12000)]]);

        $this->assertEquals(12000.0, $this->soldeGrandLivre('419'), '419 débité de 12 000');
        $this->assertEquals(-12000.0, $this->soldeGrandLivre('411'), '411 crédité de 12 000');
        $this->assertEquals(0.0, $this->soldeGrandLivre('531'));
        $this->assertEquals(100000, $this->caisse->fresh()->balance);
    }

    /**
     * ⚠️ LE PAQUET COMPLET D'UN POSTE HORS LIGNE : le client, sa vente à crédit, son avance et
     * l'imputation de l'avance sur la créance de cette vente — dans UN SEUL envoi, dans le désordre
     * du tableau (l'ordre de traitement est celui du serveur).
     */
    public function test_client_vente_a_credit_avance_et_imputation_dans_le_meme_paquet(): void
    {
        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);
        $produit = Product::create([
            'sku' => 'ALI-001', 'name' => 'Aliment ponte', 'category_id' => $categorie->id,
            'unit' => 'sac', 'pricing_mode' => 'fourchette', 'tva_rate' => 0,
            'stock_qty' => 40, 'is_active' => true,
        ]);

        $clientId = (string) Str::uuid();
        $venteId = (string) Str::uuid();
        $avance = $this->avance(['customer_id' => $clientId, 'amount' => 20000]);
        $imputation = [
            'id' => (string) Str::uuid(),
            'customer_advance_id' => $avance['id'],
            'sale_id' => $venteId,            // le poste ne connaît pas l'id de la créance
            'amount' => 20000,
            'imputation_date' => now()->toDateString(),
        ];

        $r = $this->pousser($this->vendeur, [
            'advance_imputations' => [$imputation],
            'sales' => [[
                'id' => $venteId,
                'customer_id' => $clientId,
                'payment_mode' => 'credit',
                'subtotal' => 30000, 'discount' => 0, 'total' => 30000, 'status' => 'validee',
                'lines' => [[
                    'product_id' => $produit->id, 'qty' => 2,
                    'unit_price' => 15000, 'manual_total_amount' => 30000,
                ]],
            ]],
            'customer_advances' => [$avance],
            'customers' => [['id' => $clientId, 'name' => 'GBAGUIDI Solange']],
        ]);

        $this->assertSame([$clientId], $r->json('customers.accepted'));
        $this->assertSame([$venteId], $r->json('sales.accepted'));
        $this->assertSame([$avance['id']], $r->json('customer_advances.accepted'));
        $this->assertSame([$imputation['id']], $r->json('advance_imputations.accepted'), json_encode($r->json('advance_imputations')));

        $creance = Receivable::where('sale_id', $venteId)->sole();
        $this->assertEquals(30000, $creance->amount);
        $this->assertEquals(20000, $creance->amount_paid);
        $this->assertEquals(20000, CustomerAdvance::findOrFail($avance['id'])->amount_used);

        // 411 : débité de la vente (30 000), crédité de l'imputation (20 000) = reste dû 10 000.
        $this->assertEquals(10000.0, $this->soldeGrandLivre('411'));
        // 419 : crédité de l'avance (20 000), débité de l'imputation (20 000) = soldé.
        $this->assertEquals(0.0, $this->soldeGrandLivre('419'));
        // Les deux livres de trésorerie : +20 000 chacun (la vente était à crédit).
        $this->assertEquals(120000.0, (float) TreasuryAccount::sum('balance'));
        $this->assertEquals(20000.0, $this->soldeGrandLivre('531'));
    }

    /** DÉFAUT DU CANAL : une vente à crédit poussée ne créait AUCUNE créance. */
    public function test_une_vente_a_credit_poussee_cree_sa_creance(): void
    {
        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);
        $produit = Product::create([
            'sku' => 'ALI-001', 'name' => 'Aliment ponte', 'category_id' => $categorie->id,
            'unit' => 'sac', 'pricing_mode' => 'fourchette', 'tva_rate' => 0,
            'stock_qty' => 40, 'is_active' => true,
        ]);
        $venteId = (string) Str::uuid();

        $this->pousser($this->vendeur, ['sales' => [[
            'id' => $venteId, 'customer_id' => $this->client->id, 'payment_mode' => 'credit',
            'subtotal' => 18000, 'discount' => 0, 'total' => 18000, 'status' => 'validee',
            'lines' => [['product_id' => $produit->id, 'qty' => 1, 'unit_price' => 18000, 'manual_total_amount' => 18000]],
        ]]]);

        $creance = Receivable::where('sale_id', $venteId)->sole();
        $this->assertSame($this->client->id, $creance->customer_id);
        $this->assertEquals(18000, $creance->amount);
        $this->assertEquals(0, $creance->amount_paid);
        $this->assertSame(now()->addDays(30)->toDateString(), $creance->due_date->toDateString());
    }

    public function test_une_vente_au_comptant_ne_cree_pas_de_creance(): void
    {
        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);
        $produit = Product::create([
            'sku' => 'ALI-001', 'name' => 'Aliment ponte', 'category_id' => $categorie->id,
            'unit' => 'sac', 'pricing_mode' => 'fourchette', 'tva_rate' => 0,
            'stock_qty' => 40, 'is_active' => true,
        ]);

        $this->pousser($this->vendeur, ['sales' => [[
            'id' => (string) Str::uuid(), 'customer_id' => $this->client->id, 'payment_mode' => 'especes',
            'subtotal' => 18000, 'discount' => 0, 'total' => 18000, 'status' => 'validee',
            'lines' => [['product_id' => $produit->id, 'qty' => 1, 'unit_price' => 18000, 'manual_total_amount' => 18000]],
        ]]]);

        $this->assertSame(0, Receivable::count());
    }

    /** Le tirage sert les nouvelles colonnes de l'avance. */
    public function test_le_tirage_sert_les_nouvelles_colonnes(): void
    {
        $a = $this->avance();
        $this->pousser($this->vendeur, ['customer_advances' => [$a]]);

        $r = $this->actingAs($this->vendeur, 'sanctum')->getJson('/api/sync/pull')->assertOk();

        $this->assertSame($this->caisse->id, $r->json('customer_advances.0.treasury_account_id'));
        $this->assertSame('especes', $r->json('customer_advances.0.payment_mode'));
        $this->assertSame('Réservation 50 poussins', $r->json('customer_advances.0.motif'));
        $this->assertSame('poste-test', $r->json('customer_advances.0.device_id'));
    }

    // --- garde-fous ------------------------------------------------------

    /**
     * ⚠️ LE TEST QUI LIT LE CODE SOURCE. `customer_advances.amount_used` et, pour une imputation,
     * `receivables.amount_paid` ne changent que dans `CustomerAdvanceService`. Une seconde copie
     * (la page web en avait une) fait diverger les plafonds et les écritures sans qu'aucun rendu
     * ne le montre.
     */
    public function test_seul_le_service_ecrit_amount_used_et_n_impute_une_creance(): void
    {
        $racine = base_path('app');
        $ecrivains = [];

        foreach (new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($racine)) as $fichier) {
            if ($fichier->getExtension() !== 'php') {
                continue;
            }

            $code = file_get_contents($fichier->getPathname());
            $chemin = str_replace('\\', '/', substr($fichier->getPathname(), strlen($racine) + 1));

            // (`'amount_used' => 'decimal:2'` du cast n'est pas une écriture : valeur entre guillemets)
            if (preg_match("/'amount_used'\\s*=>\\s*+(?!['\"])|->amount_used\\s*[+\\-]?=[^=]|increment\\(\\s*'amount_used'/", $code)) {
                $ecrivains[] = $chemin;
            }
        }

        sort($ecrivains);
        $this->assertSame(
            ['Services/CustomerAdvanceService.php'],
            $ecrivains,
            "amount_used ne s'écrit que dans le service. Écrivains : ".implode(', ', $ecrivains),
        );

        // La page web et le contrôleur de synchronisation n'écrivent jamais amount_paid d'une
        // créance : ils passent par le service (les encaissements, eux, sont l'affaire de
        // SuiviDettes et ProfileClient, hors imputation d'avance).
        $page = file_get_contents($racine.'/Livewire/Ventes/HistoriqueAvances.php');
        $this->assertStringNotContainsString("'amount_paid'", str_replace("whereColumn('amount_paid'", '', $page),
            'HistoriqueAvances ne doit pas écrire receivables.amount_paid');

        $sync = file_get_contents($racine.'/Http/Controllers/Api/SyncController.php');
        $this->assertDoesNotMatchRegularExpression("/->update\\(\\s*\\[\\s*'amount_paid'/", $sync,
            'SyncController ne doit pas mettre à jour amount_paid : seule la création de la créance (à zéro) y figure');
        $this->assertDoesNotMatchRegularExpression("/->increment\\(\\s*'amount_paid'/", $sync);

        // Et le service l'écrit bien, lui (le garde-fou ne passe pas à vide).
        $this->assertStringContainsString("'amount_paid'", file_get_contents($racine.'/Services/CustomerAdvanceService.php'));
    }
}
