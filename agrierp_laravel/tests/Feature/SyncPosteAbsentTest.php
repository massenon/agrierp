<?php

namespace Tests\Feature;

use App\Actions\AdjustStockAction;
use App\Models\AccountingEntry;
use App\Models\Customer;
use App\Models\CustomerAdvance;
use App\Models\FiscalYear;
use App\Models\Supplier;
use App\Models\Expense;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Sale;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Models\VeterinaryRecord;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

/**
 * Ticket SW-1 (correction du client du 21/10/2026) — UN POSTE REVENU APRÈS DES SEMAINES HORS LIGNE RÉCUPÈRE TOUT CE
 * QUI S'EST FAIT AU WEB, y compris les archivages et les annulations, sans rien devoir à son « dernier contact ».
 *
 * Scénario : le poste de bureau tire le 01/10 (son curseur est le `server_time` de ce tirage), puis tombe en panne ;
 * pendant 20 jours le web sert de base (le portable). Au retour du poste, son tirage incrémental depuis l'ANCIEN
 * curseur doit rendre chaque création, chaque modification et chaque archivage — jeu calculé à la main ci-dessous.
 */
class SyncPosteAbsentTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    private string $jeton;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $this->admin = User::create([
            'name' => 'Admin', 'username' => 'admin', 'email' => 'admin@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->admin->assignRole('admin');
        $this->jeton = $this->admin->createToken('POSTE-BUREAU', ['*'], now()->addDays(90))->plainTextToken;
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    /** Tirage paginé complet du poste ; rend [données fusionnées, curseur rendu à la dernière page]. */
    private function tirer(?string $since): array
    {
        $donnees = [];
        $jeton = null;
        for ($page = 1; $page < 50; $page++) {
            $this->app['auth']->forgetGuards();
            $reponse = $this->withHeader('Authorization', 'Bearer '.$this->jeton)
                ->getJson('/api/sync/pull?'.http_build_query(array_filter([
                    'since' => $since, 'page' => $page, 'curseur_page' => $jeton,
                ])))->assertOk()->json();
            foreach ($reponse as $cle => $valeur) {
                if (is_array($valeur) && array_is_list($valeur)) {
                    $donnees[$cle] = array_merge($donnees[$cle] ?? [], $valeur);
                } else {
                    $donnees[$cle] = $valeur;
                }
            }
            $jeton = $reponse['page_suivante'] ?? null;
            if ($jeton === null) {
                break;
            }
        }

        return [$donnees, $donnees['server_time']];
    }

    private function ids(array $donnees, string $table): array
    {
        return array_map(fn ($ligne) => $ligne['id'], $donnees[$table] ?? []);
    }

    public function test_un_poste_absent_trois_semaines_recupere_tout_ce_qui_s_est_fait_au_web(): void
    {
        Carbon::setTestNow('2026-10-01 10:00:00');
        $espece = LivestockSpecies::create(['label' => 'Aviculture', 'code' => 'aviculture', 'is_active' => true]);
        $categorie = ProductCategory::create(['label' => 'Volailles', 'is_active' => true]);
        $produit = Product::create([
            'sku' => 'AVI-001', 'name' => 'Poulet goliath', 'category_id' => $categorie->id, 'species_id' => $espece->id,
            'unit' => 'u', 'pricing_mode' => 'fourchette', 'price_min' => 3000, 'price_max' => 4000, 'tva_rate' => 0,
            'stock_qty' => 10, 'is_active' => true,
        ]);
        $client = Customer::create(['name' => 'Client Un', 'phone' => '+22997000001', 'is_active' => true]);
        $clientArchive = Customer::create(['name' => 'Client Deux', 'phone' => '+22997000002', 'is_active' => true]);
        $bande = LivestockLot::create([
            'code' => 'LOT-A', 'species_id' => $espece->id, 'stage' => 'engraissement', 'initial_quantity' => 100,
            'current_quantity' => 100, 'created_date' => '2026-09-20', 'status' => 'actif', 'is_active' => true,
        ]);
        $caisse = TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse Principale', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);
        $depense = Expense::create([
            'expense_date' => '2026-10-01', 'label' => 'Provende', 'category' => 'aliment', 'amount' => 50000, 'is_active' => true,
            'treasury_account_id' => $caisse->id,
        ]);
        $soin = VeterinaryRecord::create([
            'lot_id' => $bande->id, 'action_type' => 'Traitement curatif', 'product_used' => 'Oxy',
            'record_date' => '2026-10-01', 'cost' => 2500, 'is_active' => true,
        ]);
        $vente = Sale::create([
            'payment_mode' => 'especes', 'status' => 'validee', 'subtotal' => 3500, 'discount' => 0, 'total' => 3500,
            'sold_at' => '2026-10-01 09:00:00',
        ]);

        // Le poste de bureau tire : son curseur. Puis il tombe en panne.
        Carbon::setTestNow('2026-10-01 10:05:00');
        [$tirage0, $curseur] = $this->tirer(null);
        foreach ([$produit->id, $client->id, $clientArchive->id, $bande->id, $depense->id, $soin->id, $vente->id] as $id) {
            $this->assertContains($id, array_merge(
                $this->ids($tirage0, 'products'), $this->ids($tirage0, 'customers'), $this->ids($tirage0, 'livestock_lots'),
                $this->ids($tirage0, 'expenses'), $this->ids($tirage0, 'veterinary_records'), $this->ids($tirage0, 'sales'),
            ), 'le premier tirage est complet');
        }

        // ── 20 jours d'absence du poste : le portable sert au web ──
        Carbon::setTestNow('2026-10-21 08:00:00');
        $this->jeton = $this->admin->createToken('POSTE-BUREAU-2', ['*'], now()->addDays(90))->plainTextToken;
        $this->admin->tokens()->where('name', 'POSTE-BUREAU')->delete();
        // Un tirage « 20 jours plus tard » ne dépend pas du dernier contact : le jeton est tout neuf, jamais utilisé.

        app(AdjustStockAction::class)->execute($produit, 5, 'adjustment');
        $nouveau = Product::create([
            'sku' => 'AVI-002', 'name' => 'Pintade', 'category_id' => $categorie->id, 'species_id' => $espece->id,
            'unit' => 'u', 'pricing_mode' => 'fourchette', 'price_min' => 2000, 'price_max' => 3000, 'tva_rate' => 0,
            'stock_qty' => 4, 'is_active' => true,
        ]);
        $client->update(['name' => 'Client Un (renommé)']);
        $clientArchive->update(['is_active' => false]);
        $depense->update(['is_active' => false]);
        $soin->update(['is_active' => false]);
        $vente->update(['status' => 'annulee']);
        $bande->update(['current_quantity' => 90]);
        $nouvelleVente = Sale::create([
            'payment_mode' => 'especes', 'status' => 'validee', 'subtotal' => 7000, 'discount' => 0, 'total' => 7000,
            'sold_at' => '2026-10-20 09:00:00',
        ]);

        Carbon::setTestNow('2026-10-21 08:05:00');
        [$tirage] = $this->tirer($curseur);

        $produits = collect($tirage['products'])->keyBy('id');
        $this->assertEqualsWithDelta(15.0, (float) $produits[$produit->id]['stock_qty'], 0.001, 'le stock ajouté au web redescend');
        $this->assertArrayHasKey($nouveau->id, $produits->all(), 'article créé au web');
        $clients = collect($tirage['customers'])->keyBy('id');
        $this->assertSame('Client Un (renommé)', $clients[$client->id]['name']);
        $this->assertEquals(false, (bool) $clients[$clientArchive->id]['is_active'], 'client archivé au web');
        $this->assertEquals(false, (bool) collect($tirage['expenses'])->keyBy('id')[$depense->id]['is_active'], 'dépense archivée au web');
        $this->assertEquals(false, (bool) collect($tirage['veterinary_records'])->keyBy('id')[$soin->id]['is_active'], 'soin archivé au web');
        $ventes = collect($tirage['sales'])->keyBy('id');
        $this->assertSame('annulee', $ventes[$vente->id]['status'], 'vente annulée au web');
        $this->assertArrayHasKey($nouvelleVente->id, $ventes->all(), 'vente saisie au web');
        $this->assertEquals(90, (int) collect($tirage['livestock_lots'])->keyBy('id')[$bande->id]['current_quantity']);
    }

    /**
     * Les tables servies EN ENTIER (fournisseurs, avances) ou par liste d'identifiants (écritures actives) : ce qui est
     * archivé au web DISPARAÎT de la réponse, et c'est cette absence que le poste lit pour le retirer.
     */
    public function test_un_poste_absent_voit_disparaitre_ce_qui_a_ete_archive_au_web(): void
    {
        Carbon::setTestNow('2026-10-01 10:00:00');
        $fournisseur = Supplier::create(['name' => 'Provenderie', 'category' => 'Aliments', 'is_active' => true]);
        $garde = Supplier::create(['name' => 'Vétérinaire', 'category' => 'Santé', 'is_active' => true]);
        $client = Customer::create(['name' => 'Client', 'phone' => '+22997000003', 'is_active' => true]);
        $avance = CustomerAdvance::create([
            'customer_id' => $client->id, 'amount' => 20000, 'amount_used' => 0, 'advance_date' => '2026-10-01', 'is_active' => true,
        ]);
        $exercice = FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
        $ecriture = AccountingEntry::create([
            'fiscal_year_id' => $exercice->id, 'entry_date' => '2026-10-01', 'reference' => 'OD-1', 'source_type' => 'manual', 'is_active' => true,
        ]);

        Carbon::setTestNow('2026-10-01 10:05:00');
        [$tirage0, $curseur] = $this->tirer(null);
        $this->assertEqualsCanonicalizing([$fournisseur->id, $garde->id], $this->ids($tirage0, 'suppliers'));
        $this->assertSame([$avance->id], $this->ids($tirage0, 'customer_advances'));
        $this->assertContains($ecriture->id, $tirage0['accounting_entry_ids']);

        Carbon::setTestNow('2026-10-21 08:00:00');
        $fournisseur->update(['is_active' => false]);
        $avance->update(['is_active' => false]);
        $ecriture->update(['is_active' => false]);

        Carbon::setTestNow('2026-10-21 08:05:00');
        [$tirage] = $this->tirer($curseur);

        $this->assertSame([$garde->id], $this->ids($tirage, 'suppliers'), 'le fournisseur archivé n\'est plus servi');
        $this->assertSame([], $this->ids($tirage, 'customer_advances'), 'l\'avance archivée n\'est plus servie');
        $this->assertNotContains($ecriture->id, $tirage['accounting_entry_ids'], 'l\'écriture désactivée quitte la liste des actives');
    }
}
