<?php

namespace Tests\Feature;

use App\Actions\AdjustStockAction;
use App\Http\Controllers\Api\SyncController;
use App\Models\AccountingEntry;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\JournalSynchronisation;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Purchase;
use App\Models\PurchaseLine;
use App\Models\Sale;
use App\Models\SaleLine;
use App\Models\StockMovement;
use App\Models\Supplier;
use App\Models\User;
use App\Services\AccountingEntryService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Collection;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Ticket S-T4 (méthode TATACORA) — TIRAGE PAGINÉ ET LIMITÉ AUX TABLES QUE LE COMPTE LIT.
 *
 * Ce que ces tests verrouillent :
 *  - un poste ANCIEN (sans `page`) reçoit la réponse d'avant S-T4, complète et non filtrée ;
 *  - la correspondance table → permission(s) couvre EXACTEMENT les tables du tirage, ne nomme que des permissions
 *    du seeder, et donne la même permission à une pièce et à ses lignes ;
 *  - les tables servies à chacun des quatre rôles (listes écrites à la main, pas recalculées par le code testé) ;
 *  - la pagination : tout est servi une fois, une pièce JAMAIS séparée de ses lignes (même au-delà de la taille),
 *    curseur composite sans perte ni doublon à `updated_at` égal, `server_time` et `accounting_entry_ids` à la
 *    DERNIÈRE page seulement, ce qui s'écrit pendant le tirage descend au suivant ;
 *  - le jeton de page : illisible ou d'un autre compte → 422 ; une seule ligne de journal par tirage paginé.
 */
class SyncTiragePagineTest extends TestCase
{
    use RefreshDatabase;

    private Product $porc;

    private Supplier $fournisseur;

    /** Tables du fonctionnement de base, servies à tout compte (comptées à la main dans la correspondance). */
    private const BASE = [
        'products', 'product_categories', 'livestock_lots', 'livestock_daily_entries', 'livestock_reproduction_events',
        'customers', 'receivables', 'purchases', 'purchase_lines', 'purchase_returns', 'payables', 'fiscal_years',
        'company_settings', 'modules_config', 'roles', 'users', 'audit_logs', 'notifications', 'sales', 'sale_lines',
        'treasury_accounts',
        // Ticket U13 — les dépenses : le Tableau de bord (quatre rôles) les liste au web.
        'expenses',
    ];

    protected function setUp(): void
    {
        parent::setUp();

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        Carbon::setTestNow('2026-10-19 09:00:00');

        $categorie = ProductCategory::create(['label' => 'Porciculture', 'is_active' => true]);
        $this->porc = Product::create([
            'sku' => 'POR-CHA', 'name' => 'Porc charcutier', 'category_id' => $categorie->id, 'unit' => 'tête',
            'pricing_mode' => 'fourchette', 'price_min' => 10000, 'price_max' => 90000,
            'stock_qty' => 1000, 'is_active' => true,
        ]);
        $this->fournisseur = Supplier::create(['name' => 'Provenderie du Plateau', 'category' => 'Aliments', 'is_active' => true]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function compte(string $role): User
    {
        $utilisateur = User::create([
            'name' => 'Compte '.$role, 'username' => $role, 'email' => $role.'@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $utilisateur->assignRole($role);

        return $utilisateur;
    }

    private function vente(int $lignes = 2, float $montant = 30000): Sale
    {
        $vente = Sale::create([
            'payment_mode' => 'especes', 'subtotal' => $montant * $lignes, 'total' => $montant * $lignes, 'status' => 'validee',
        ]);
        for ($i = 0; $i < $lignes; $i++) {
            SaleLine::create([
                'sale_id' => $vente->id, 'product_id' => $this->porc->id, 'qty' => 1,
                'unit_price' => $montant, 'manual_total_amount' => $montant, 'is_manual_price' => true,
            ]);
        }

        return $vente;
    }

    private function achat(int $lignes = 3): Purchase
    {
        $achat = Purchase::create([
            'supplier_id' => $this->fournisseur->id, 'payment_mode' => 'especes', 'total' => 8000 * $lignes,
            'purchase_date' => now()->format('Y-m-d'),
        ]);
        for ($i = 0; $i < $lignes; $i++) {
            PurchaseLine::create(['purchase_id' => $achat->id, 'product_id' => $this->porc->id, 'qty' => 1, 'unit_price' => 8000]);
        }

        return $achat;
    }

    private function page(User $compte, ?string $jeton = null, int $numero = 1, ?int $taille = null, ?string $since = null)
    {
        $parametres = array_filter([
            'page' => $numero,
            'curseur_page' => $jeton,
            'taille' => $taille,
            'since' => $since,
        ], fn ($v) => $v !== null);

        return $this->actingAs($compte, 'sanctum')->getJson('/api/sync/pull?'.http_build_query($parametres));
    }

    /**
     * Toutes les pages d'un tirage, dans l'ordre.
     *
     * @param  \Closure|null  $entreDeux  appelée après chaque page (écritures « pendant le tirage »)
     * @return array<int, array<string, mixed>>
     */
    private function toutesLesPages(User $compte, ?int $taille = null, ?string $since = null, ?\Closure $entreDeux = null): array
    {
        $pages = [];
        $jeton = null;
        do {
            $corps = $this->page($compte, $jeton, count($pages) + 1, $taille, $since)->assertOk()->json();
            $pages[] = $corps;
            $this->assertArrayHasKey('page_suivante', $corps, 'une page du tirage paginé dit toujours s\'il en reste');
            $jeton = $corps['page_suivante'];
            if ($entreDeux) {
                $entreDeux(count($pages));
            }
            $this->assertLessThan(200, count($pages), 'le tirage ne finit pas');
        } while ($jeton !== null);

        return $pages;
    }

    /** @param  array<int, array<string, mixed>>  $pages */
    private function servis(array $pages, string $cle): Collection
    {
        return collect($pages)->flatMap(fn (array $p) => $p[$cle] ?? []);
    }

    public function test_un_poste_ancien_sans_page_recoit_la_reponse_complete_et_non_filtree(): void
    {
        $caissier = $this->compte('caissier');
        $this->vente();

        $corps = $this->actingAs($caissier, 'sanctum')->getJson('/api/sync/pull')->assertOk()->json();

        $this->assertArrayNotHasKey('page_suivante', $corps);
        $this->assertArrayNotHasKey('tables_servies', $corps);
        // Non filtré : le journal, le personnel et les soins partent comme avant S-T4, même à un caissier.
        foreach (['accounting_entries', 'accounting_entry_ids', 'employees', 'veterinary_records', 'stock_movements'] as $cle) {
            $this->assertArrayHasKey($cle, $corps);
        }
        $this->assertNotNull($corps['server_time']);
    }

    public function test_la_correspondance_couvre_exactement_les_tables_du_tirage_dans_leur_ordre(): void
    {
        $corps = $this->actingAs($this->compte('admin'), 'sanctum')->getJson('/api/sync/pull')->assertOk()->json();

        $tables = array_values(array_diff(array_keys($corps), ['server_time', 'data_reset_at']));

        // Une table ajoutée au tirage sans entrer dans la correspondance ferait échouer ce test (et inversement).
        $this->assertSame(array_keys(SyncController::PERMISSIONS_DE_TIRAGE), $tables);
    }

    public function test_chaque_permission_de_la_correspondance_existe_au_seeder(): void
    {
        $existantes = \App\Models\Permission::pluck('name')->all();
        foreach (SyncController::PERMISSIONS_DE_TIRAGE as $table => $permissions) {
            foreach ($permissions ?? [] as $permission) {
                $this->assertContains($permission, $existantes, "{$table} : permission « {$permission} » inconnue");
            }
        }
    }

    public function test_une_piece_et_ses_lignes_ont_la_meme_permission(): void
    {
        $p = SyncController::PERMISSIONS_DE_TIRAGE;
        $this->assertSame($p['sales'], $p['sale_lines']);
        $this->assertSame($p['purchases'], $p['purchase_lines']);
        $this->assertSame($p['purchases'], $p['purchase_returns']);
        $this->assertSame($p['accounting_entries'], $p['accounting_entry_lines']);
        $this->assertSame($p['accounting_entries'], $p['accounting_entry_ids']);
    }

    public function test_tables_servies_a_chacun_des_quatre_roles(): void
    {
        $attendu = [
            // Tickets DEV et AV1 — `quotes` (Devis Prestations) et `credit_notes` (Retours et Avoirs) : `view-ventes`.
            'caissier' => [...self::BASE, 'feed_ration_standards', 'veterinary_withdrawal_periods', 'customer_advances',
                'customer_reminders', 'quotes', 'credit_notes'],
            'animalier' => [...self::BASE, 'livestock_transfers', 'feed_ration_standards', 'growth_standards',
                'veterinary_withdrawal_periods', 'prophylaxis_schedule_standards', 'veterinary_records', 'infirmary_records',
                'veterinary_calendar_events', 'feed_types', 'elevage_numbering', 'lot_revenues', 'animals',
                'livestock_species', 'stock_movements'],
            'comptable' => [...self::BASE, 'suppliers', 'chart_of_accounts', 'accounting_entries', 'accounting_entry_lines',
                'accounting_entry_ids', 'stock_movements', 'payslips'],
            'admin' => array_keys(SyncController::PERMISSIONS_DE_TIRAGE),
        ];

        foreach ($attendu as $role => $tables) {
            $corps = $this->page($this->compte($role))->assertOk()->json();
            $this->assertEqualsCanonicalizing($tables, $corps['tables_servies'], "tables servies au rôle {$role}");

            // Les clés de DONNÉES de la réponse sont exactement les tables servies.
            $donnees = array_diff(array_keys($corps), ['page', 'page_suivante', 'server_time', 'data_reset_at', 'tables_servies']);
            $this->assertEqualsCanonicalizing($tables, array_values($donnees), "clés servies au rôle {$role}");
        }
    }

    public function test_les_droits_lus_sont_ceux_de_la_base_pas_ceux_du_seeder(): void
    {
        $caissier = $this->compte('caissier');
        $this->assertNotContains('accounting_entries', $this->page($caissier)->json('tables_servies'));

        // L'administrateur ouvre la comptabilité au rôle caissier dans la matrice des droits.
        \App\Models\Role::findByName('caissier', 'web')->givePermissionTo('view-comptabilite');

        $this->assertContains('accounting_entries', $this->page($caissier->fresh())->json('tables_servies'));
    }

    public function test_le_journal_d_audit_reste_servi_vide_sans_manage_users(): void
    {
        $caissier = $this->compte('caissier');
        AuditLog::record('vente.creee', 'ventes', $caissier->id);

        $corps = $this->page($caissier)->assertOk()->json();

        // Ticket S3 inchangé : une liste VIDE (qui purge un poste partagé), pas une clé absente.
        $this->assertArrayHasKey('audit_logs', $corps);
        $this->assertSame([], $corps['audit_logs']);
        $this->assertArrayNotHasKey('employees', $corps);
        $this->assertArrayNotHasKey('accounting_entries', $corps);
    }

    public function test_la_pagination_sert_chaque_piece_une_fois_avec_toutes_ses_lignes(): void
    {
        $admin = $this->compte('admin');
        $ventes = collect(range(1, 9))->map(fn () => $this->vente(2));
        $achats = collect(range(1, 4))->map(fn () => $this->achat(3));

        Carbon::setTestNow('2026-10-19 10:00:00');
        $pages = $this->toutesLesPages($admin, 5);

        $this->assertGreaterThan(5, count($pages), 'la taille 5 impose plusieurs pages');

        // Chaque vente, chaque achat : servi UNE fois.
        $idsVentes = $this->servis($pages, 'sales')->pluck('id');
        $this->assertEqualsCanonicalizing($ventes->pluck('id')->all(), $idsVentes->all());
        $idsAchats = $this->servis($pages, 'purchases')->pluck('id');
        $this->assertEqualsCanonicalizing($achats->pluck('id')->all(), $idsAchats->all());

        // Chaque ligne DANS LA PAGE de sa pièce, et toutes les lignes servies.
        foreach ($pages as $page) {
            $piecesDeLaPage = collect($page['sales'])->pluck('id');
            foreach ($page['sale_lines'] as $ligne) {
                $this->assertContains($ligne['sale_id'], $piecesDeLaPage->all(), 'ligne de vente séparée de sa vente');
            }
            $achatsDeLaPage = collect($page['purchases'])->pluck('id');
            foreach ($page['purchase_lines'] as $ligne) {
                $this->assertContains($ligne['purchase_id'], $achatsDeLaPage->all(), "ligne d'achat séparée de son achat");
            }
            // Une page ne dépasse la taille que pour ne pas couper une pièce : ici, aucune pièce ne pèse plus de 5.
            $this->assertLessThanOrEqual(5, count($page['sales']) + count($page['sale_lines'])
                + count($page['purchases']) + count($page['purchase_lines']));
        }
        $this->assertCount(18, $this->servis($pages, 'sale_lines'));
        $this->assertCount(12, $this->servis($pages, 'purchase_lines'));

        // Curseur et liste des écritures actives : à la DERNIÈRE page seulement ; le curseur est le DÉBUT du tirage.
        $derniere = array_pop($pages);
        $this->assertSame(
            Carbon::parse('2026-10-19 10:00:00')->subSeconds(SyncController::HORIZON_TIRAGE_SECONDES)->toIso8601String(),
            $derniere['server_time'],
        );
        $this->assertArrayHasKey('accounting_entry_ids', $derniere);
        foreach ($pages as $page) {
            $this->assertArrayNotHasKey('server_time', $page);
            $this->assertArrayNotHasKey('accounting_entry_ids', $page);
            $this->assertNotNull($page['page_suivante']);
        }
        // Les tables entières ne viennent qu'à la page 1, sans être découpées.
        $this->assertArrayHasKey('products', $pages[0]);
        $this->assertArrayNotHasKey('products', $pages[1]);
    }

    public function test_une_piece_n_est_jamais_coupee_meme_au_dela_de_la_taille(): void
    {
        $admin = $this->compte('admin');
        $grosse = $this->vente(6);
        $this->vente(1);

        Carbon::setTestNow('2026-10-19 10:00:00');
        $pages = $this->toutesLesPages($admin, 3);

        $page = collect($pages)->first(fn (array $p) => collect($p['sales'])->contains('id', $grosse->id));
        $this->assertCount(6, collect($page['sale_lines'])->where('sale_id', $grosse->id));
        $this->assertCount(1, $page['sales'], 'la grosse vente occupe sa page à elle seule');
        $this->assertCount(2, $this->servis($pages, 'sales'));
    }

    public function test_a_updated_at_egal_le_curseur_composite_ne_perd_ni_ne_double(): void
    {
        $admin = $this->compte('admin');
        // Douze mouvements à la MÊME seconde : seul l'identifiant les départage.
        foreach (range(1, 12) as $i) {
            app(AdjustStockAction::class)->execute($this->porc, -1, 'sale', (string) Str::uuid());
        }

        Carbon::setTestNow('2026-10-19 10:00:00');
        $servis = $this->servis($this->toutesLesPages($admin, 5), 'stock_movements')->pluck('id');

        $this->assertCount(12, $servis);
        $this->assertCount(12, $servis->unique());
        $this->assertEqualsCanonicalizing(StockMovement::pluck('id')->all(), $servis->all());
    }

    public function test_ce_qui_s_ecrit_pendant_le_tirage_descend_au_tirage_suivant(): void
    {
        $admin = $this->compte('admin');
        $this->vente(1);
        $this->vente(1);
        $this->vente(1);

        Carbon::setTestNow('2026-10-19 10:00:00');
        $pendant = null;
        $produitPendant = null;
        $pages = $this->toutesLesPages($admin, 2, null, function (int $page) use (&$pendant, &$produitPendant) {
            if ($page === 1) {
                // Pendant le tirage (après la page 1, qui a servi les produits) : un produit, son mouvement, une vente.
                Carbon::setTestNow('2026-10-19 10:00:30');
                $produitPendant = Product::create([
                    'sku' => 'NOUVEAU', 'name' => 'Produit pendant', 'category_id' => $this->porc->category_id,
                    'unit' => 'u', 'pricing_mode' => 'fourchette', 'price_min' => 100, 'price_max' => 100, 'stock_qty' => 0,
                    'is_active' => true,
                ]);
                app(AdjustStockAction::class)->execute($produitPendant, 5, 'purchase', (string) Str::uuid());
                $pendant = $this->vente(1);
            }
        });

        $this->assertNotContains($pendant->id, $this->servis($pages, 'sales')->pluck('id')->all(),
            'une vente écrite pendant le tirage ne descend pas avec des pages commencées avant elle');
        $this->assertNotContains($produitPendant->id, $this->servis($pages, 'stock_movements')->pluck('product_id')->all(),
            'un mouvement d\'un produit que la page 1 n\'a pas servi serait refusé par le poste');
        $this->assertCount(3, $this->servis($pages, 'sales'));

        // Le tirage suivant, au curseur rendu, les apporte — produit compris.
        Carbon::setTestNow('2026-10-19 10:15:00');
        $suivant = $this->toutesLesPages($admin, 50, end($pages)['server_time']);
        $this->assertContains($pendant->id, $this->servis($suivant, 'sales')->pluck('id')->all());
        $this->assertContains($produitPendant->id, $this->servis($suivant, 'products')->pluck('id')->all());
        $this->assertContains($produitPendant->id, $this->servis($suivant, 'stock_movements')->pluck('product_id')->all());
    }

    public function test_le_since_de_la_page_1_vaut_pour_toutes_les_pages(): void
    {
        $admin = $this->compte('admin');
        $ancienne = $this->vente(1);
        Carbon::setTestNow('2026-10-19 09:30:00');
        $this->vente(1);
        $this->vente(1);

        Carbon::setTestNow('2026-10-19 10:00:00');
        $since = Carbon::parse('2026-10-19 09:15:00')->toIso8601String();
        $premiere = $this->page($admin, null, 1, 2, $since)->assertOk()->json();
        // La page 2 demandée avec un AUTRE `since` (plus récent que les ventes) : celui du jeton fait foi.
        $autre = Carbon::parse('2026-10-19 09:45:00')->toIso8601String();
        $seconde = $this->page($admin, $premiere['page_suivante'], 2, 50, $autre)->assertOk()->json();

        $ids = collect([$premiere, $seconde])->flatMap(fn ($p) => $p['sales'])->pluck('id');
        $this->assertCount(2, $ids);
        $this->assertNotContains($ancienne->id, $ids->all());
    }

    public function test_un_jeton_de_page_illisible_ou_d_un_autre_compte_est_refuse(): void
    {
        $admin = $this->compte('admin');
        $this->vente(1);
        $this->vente(1);

        Carbon::setTestNow('2026-10-19 10:00:00');
        $this->page($admin, 'nimporte-quoi', 2)
            ->assertStatus(422)
            ->assertJsonPath('message', 'Page de tirage illisible : la synchronisation doit reprendre depuis le début.');

        $jeton = $this->page($admin, null, 1, 1)->assertOk()->json('page_suivante');
        $this->assertNotNull($jeton);
        $this->page($this->compte('caissier'), $jeton, 2)->assertStatus(422);
    }

    public function test_un_tirage_pagine_fait_une_seule_ligne_de_journal_toutes_pages_comptees(): void
    {
        $admin = $this->compte('admin');
        foreach (range(1, 4) as $i) {
            $this->vente(2);
        }

        Carbon::setTestNow('2026-10-19 10:00:00');
        $pages = $this->toutesLesPages($admin, 3);

        $this->assertGreaterThan(2, count($pages));
        $this->assertSame(1, JournalSynchronisation::where('sens', 'tirage')->count());
        $attendu = collect($pages)->sum(fn (array $p) => collect($p)
            ->except(['accounting_entry_ids', 'expense_categories', 'tables_servies'])
            ->filter(fn ($v, $cle) => is_array($v) && array_is_list($v) && ! in_array($cle, ['elevage_numbering', 'company_settings', 'attestation_counts'], true))
            ->sum(fn ($v) => count($v)));
        $this->assertSame($attendu, (int) JournalSynchronisation::where('sens', 'tirage')->value('nb_recus'));
    }

    public function test_les_pages_ont_leur_propre_compteur_de_debit(): void
    {
        $caissier = $this->compte('caissier');

        // Plus que les 30 appels du compteur commun : un long tirage paginé ne tombe pas en 429 au milieu.
        for ($i = 0; $i < 120; $i++) {
            $this->page($caissier)->assertOk();
        }
        $this->page($caissier)->assertStatus(429);

        // L'envoi garde son compteur à lui, intact.
        $this->actingAs($caissier, 'sanctum')->postJson('/api/sync/push', [])->assertOk();
    }

    public function test_le_journal_comptable_descend_par_piece_et_la_liste_des_actives_a_la_derniere_page(): void
    {
        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
        $caisse = ChartOfAccount::create(['code' => '531', 'label' => 'Caisse', 'class' => 5, 'is_active' => true]);
        $ventes = ChartOfAccount::create(['code' => '701', 'label' => 'Ventes', 'class' => 7, 'is_active' => true]);
        foreach (range(1, 5) as $i) {
            app(AccountingEntryService::class)->recordManual($caisse->id, $ventes->id, 1000 * $i, '2026-10-05', 'OD-000'.$i);
        }
        $comptable = $this->compte('comptable');

        Carbon::setTestNow('2026-10-19 10:00:00');
        $pages = $this->toutesLesPages($comptable, 3);

        $ecritures = $this->servis($pages, 'accounting_entries')->pluck('id');
        $this->assertEqualsCanonicalizing(AccountingEntry::pluck('id')->all(), $ecritures->all());
        foreach ($pages as $page) {
            $dePage = collect($page['accounting_entries'])->pluck('id');
            foreach ($page['accounting_entry_lines'] as $ligne) {
                $this->assertContains($ligne['entry_id'], $dePage->all(), 'ligne d\'écriture séparée de son écriture');
            }
        }
        $this->assertCount(10, $this->servis($pages, 'accounting_entry_lines'));
        $this->assertEqualsCanonicalizing($ecritures->all(), end($pages)['accounting_entry_ids']);
    }
}
