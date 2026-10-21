<?php

namespace Tests\Feature;

use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Notification;
use App\Models\PeriodicClosure;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\Sale;
use App\Models\StockMovement;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Models\VeterinaryWithdrawalPeriod;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 15.30 — SOCLE DES VENTES DATÉES.
 *
 * Le client veut pouvoir enregistrer une vente ANTÉRIEURE. Ce ticket ne livre
 * pas le champ : il rend le serveur SÛR pour une `sold_at` passée. Quatre
 * défauts trouvés par lecture, reproduits ici avant d'être corrigés :
 *
 *  1. un exercice clos / absent faisait échouer TOUT l'envoi en 500 (seule
 *     `ValidationException` était rattrapée par `pushSales`) ;
 *  2. le mois clôturé n'était contrôlé nulle part pour une vente ;
 *  3. la rémanence était jugée sur `created_at`, le mouvement de stock n'était
 *     pas daté sur `sold_at` ;
 *  4. soupçon de double comptage fiche + vente dans un même envoi.
 *
 * Date figée au 14/10/2026 : aucun test ne dépend du jour où la suite tourne.
 */
class SyncVenteDateeSocleTest extends TestCase
{
    use RefreshDatabase;

    private const MDP = 'AgriERP@2026';

    private const VENTE_A = '11111111-1111-4111-8111-111111111111';

    private const VENTE_B = '22222222-2222-4222-8222-222222222222';

    private Product $poulet;

    private LivestockLot $bande;

    private string $token;

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow('2026-10-14 12:00:00');

        foreach (['view-ventes', 'manage-ventes'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('caissier', 'web')->givePermissionTo(['view-ventes', 'manage-ventes']);
        // Ticket S1 : ces tests envoient aussi des fiches complètes, qui exigent `manage-elevage`.
        Permission::findOrCreate('manage-elevage', 'web');
        Role::findOrCreate('animalier', 'web')->givePermissionTo('manage-elevage');

        $caissier = User::create([
            'name' => 'Caissière POS', 'username' => 'caisse',
            'email' => 'caisse@fermeolouwachegoun.com',
            'password' => bcrypt(self::MDP), 'is_active' => true,
        ]);
        $caissier->assignRole('caissier', 'animalier');

        FiscalYear::create([
            'year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert',
        ]);

        foreach ([
            ['411', 'Clients', 4], ['531', 'Caisse', 5],
            ['701', 'Ventes de marchandises', 7], ['443', 'TVA collectée', 4],
        ] as [$code, $label, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $classe, 'is_active' => true]);
        }

        TreasuryAccount::create([
            'type' => 'caisse', 'label' => 'Caisse Principale', 'account_code' => '531',
            'balance' => 0, 'is_active' => true,
        ]);

        $espece = LivestockSpecies::create(['label' => 'Aviculture', 'code' => 'AVI', 'is_active' => true]);
        $categorie = ProductCategory::create(['label' => 'Volailles', 'is_active' => true]);

        $this->poulet = Product::create([
            'sku' => 'AVI-001', 'name' => 'Poulet goliath', 'category_id' => $categorie->id,
            'species_id' => $espece->id, 'unit' => 'u', 'pricing_mode' => 'fourchette',
            'price_min' => 3_000, 'price_max' => 4_000, 'tva_rate' => 0,
            'stock_qty' => 50, 'is_active' => true,
        ]);

        $this->bande = LivestockLot::create([
            'code' => 'AVI-2026-01', 'species_id' => $espece->id, 'stage' => 'croissance',
            'initial_quantity' => 50, 'current_quantity' => 50,
            'created_date' => '2026-01-05', 'status' => 'actif', 'is_active' => true,
        ]);

        $this->token = $this->postJson('/api/auth/login', [
            'identifiant' => 'caisse', 'password' => self::MDP, 'device_name' => 'poste-ferme-01',
        ])->json('token');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();

        parent::tearDown();
    }

    private function vente(string $id, array $remplacements = []): array
    {
        return array_merge([
            'id' => $id,
            'payment_mode' => 'especes',
            'subtotal' => 21_000, 'discount' => 0, 'total' => 21_000,
            'status' => 'validee',
            'lines' => [[
                'product_id' => $this->poulet->id,
                'lot_id' => $this->bande->id,
                'qty' => 6, 'unit_price' => 3_500, 'manual_total_amount' => 21_000,
            ]],
        ], $remplacements);
    }

    private function pousser(array $ventes, array $en_plus = [])
    {
        return $this->withHeader('Authorization', 'Bearer '.$this->token)
            ->postJson('/api/sync/push', array_merge(['sales' => $ventes], $en_plus));
    }

    // ═══════════════════ DÉFAUT 1 — exercice clos ou absent ═══════════════════

    /** Une vente datée d'une année sans exercice : rejet motivé, JAMAIS un 500. */
    public function test_une_vente_sans_exercice_couvrant_est_rejetee_avec_son_motif(): void
    {
        $this->pousser([$this->vente(self::VENTE_A, ['sold_at' => '2024-03-10 09:00:00'])])
            ->assertOk()
            ->assertJsonPath('sales.accepted', [])
            ->assertJsonPath('sales.rejected.0.id', self::VENTE_A);

        $motif = $this->pousser([$this->vente(self::VENTE_A, ['sold_at' => '2024-03-10 09:00:00'])])
            ->json('sales.rejected.0.reason');
        $this->assertStringContainsString('exercice', mb_strtolower($motif));
        $this->assertStringContainsString('10/03/2024', $motif, 'la date refusée doit être nommée, en format français');

        // Rien n'a survécu au refus : ni vente, ni stock, ni écriture, ni caisse.
        $this->assertSame(0, Sale::count());
        $this->assertEquals(50, $this->poulet->fresh()->stock_qty);
        $this->assertSame(0, AccountingEntry::count());
        $this->assertEquals(0, TreasuryAccount::first()->balance);
    }

    /** Un exercice CLOS qui couvre la date refuse aussi. */
    public function test_une_vente_dans_un_exercice_clos_est_rejetee_avec_son_motif(): void
    {
        FiscalYear::create([
            'year' => 2025, 'start_date' => '2025-01-01', 'end_date' => '2025-12-31', 'status' => 'cloture',
        ]);

        $reponse = $this->pousser([$this->vente(self::VENTE_A, ['sold_at' => '2025-06-15 09:00:00'])])->assertOk();

        $this->assertSame(self::VENTE_A, $reponse->json('sales.rejected.0.id'));
        $this->assertStringContainsString('exercice', mb_strtolower($reponse->json('sales.rejected.0.reason')));
        $this->assertSame(0, Sale::count());
    }

    /**
     * Sans `sold_at` (poste ancien) le garde de date ne joue pas : c'est le
     * rattrapage des deux exceptions comptables qui doit protéger l'envoi.
     */
    public function test_sans_sold_at_l_exercice_absent_ne_fait_pas_echouer_l_envoi(): void
    {
        FiscalYear::query()->delete();

        $reponse = $this->pousser([$this->vente(self::VENTE_A)])->assertOk();

        $this->assertSame(self::VENTE_A, $reponse->json('sales.rejected.0.id'));
        $this->assertStringContainsString('exercice', mb_strtolower($reponse->json('sales.rejected.0.reason')));
        $this->assertSame(0, Sale::count());
        $this->assertEquals(50, $this->poulet->fresh()->stock_qty, 'la transaction annulée ne doit laisser aucune sortie de stock');
    }

    /** Une vente rejetée n'empêche NI les autres ventes NI les fiches du même envoi. */
    public function test_une_vente_rejetee_n_empeche_pas_les_autres_du_meme_envoi(): void
    {
        $reponse = $this->pousser(
            [
                $this->vente(self::VENTE_A, ['sold_at' => '2024-03-10 09:00:00']),
                $this->vente(self::VENTE_B, ['sold_at' => '2026-10-13 09:00:00']),
            ],
            ['livestock_daily_entries' => [[
                'id' => '33333333-3333-4333-8333-333333333333',
                'lot_id' => $this->bande->id, 'entry_date' => '2026-10-12', 'mort' => 1,
            ]]],
        )->assertOk();

        $this->assertSame([self::VENTE_B], $reponse->json('sales.accepted'));
        $this->assertSame(self::VENTE_A, $reponse->json('sales.rejected.0.id'));
        $this->assertSame(1, Sale::count());
        $this->assertNotNull(Sale::find(self::VENTE_B));
        $this->assertSame(1, LivestockDailyEntry::where('entry_date', '2026-10-12')->count(),
            'la fiche du même envoi est conservée');
        $this->assertEquals(44, $this->poulet->fresh()->stock_qty, 'seule la vente acceptée décrémente le stock');
    }

    /**
     * IDEMPOTENCE PAR UUID : une vente rejetée puis renvoyée est rejetée de
     * nouveau, sans trace ; une fois l'obstacle levé elle est acceptée UNE fois,
     * et un renvoi supplémentaire ne double rien.
     */
    public function test_idempotence_d_une_vente_rejetee_puis_renvoyee(): void
    {
        $vente = $this->vente(self::VENTE_A, ['sold_at' => '2025-06-15 09:00:00']);

        $this->pousser([$vente])->assertOk()->assertJsonPath('sales.rejected.0.id', self::VENTE_A);
        $this->pousser([$vente])->assertOk()->assertJsonPath('sales.rejected.0.id', self::VENTE_A);
        $this->assertSame(0, Sale::count());
        $this->assertEquals(50, $this->poulet->fresh()->stock_qty);

        // L'obstacle est levé : l'exercice 2025 existe, ouvert.
        FiscalYear::create([
            'year' => 2025, 'start_date' => '2025-01-01', 'end_date' => '2025-12-31', 'status' => 'ouvert',
        ]);

        $this->pousser([$vente])->assertOk()->assertJsonPath('sales.accepted.0', self::VENTE_A);
        $this->pousser([$vente])->assertOk()->assertJsonPath('sales.accepted.0', self::VENTE_A);

        $this->assertSame(1, Sale::count());
        $this->assertEquals(44, $this->poulet->fresh()->stock_qty, 'le stock n\'est décrémenté qu\'une fois');
        $this->assertSame(1, AccountingEntry::count());
    }

    // ═══════════════════ DÉFAUT 2 — mois clôturé ═══════════════════

    public function test_une_vente_datee_d_un_mois_cloture_est_rejetee_avec_son_motif(): void
    {
        PeriodicClosure::create(['period' => '2026-07', 'closed_at' => now()]);

        $reponse = $this->pousser([$this->vente(self::VENTE_A, ['sold_at' => '2026-07-28 09:00:00'])])->assertOk();

        $this->assertSame(self::VENTE_A, $reponse->json('sales.rejected.0.id'));
        $motif = $reponse->json('sales.rejected.0.reason');
        $this->assertStringContainsString('clôturé', $motif);
        $this->assertStringContainsString('2026-07', $motif);
        $this->assertSame(0, Sale::count());
        $this->assertEquals(50, $this->poulet->fresh()->stock_qty);
    }

    public function test_un_mois_decloture_ou_un_autre_mois_n_empeche_pas_la_vente(): void
    {
        PeriodicClosure::create(['period' => '2026-07', 'closed_at' => now(), 'reopened_at' => now()]);
        PeriodicClosure::create(['period' => '2026-08', 'closed_at' => now()]);

        $reponse = $this->pousser([
            $this->vente(self::VENTE_A, ['sold_at' => '2026-07-28 09:00:00']),
            $this->vente(self::VENTE_B, ['sold_at' => '2026-09-02 09:00:00']),
        ])->assertOk();

        $this->assertEqualsCanonicalizing([self::VENTE_A, self::VENTE_B], $reponse->json('sales.accepted'));
        $this->assertSame([], $reponse->json('sales.rejected'));
    }

    /** Le mois est jugé sur la date de la VENTE, jamais sur celle de la réception. */
    public function test_le_mois_courant_cloture_ne_bloque_pas_une_vente_d_un_mois_ouvert(): void
    {
        PeriodicClosure::create(['period' => '2026-10', 'closed_at' => now()]);

        $this->pousser([$this->vente(self::VENTE_A, ['sold_at' => '2026-09-20 09:00:00'])])
            ->assertOk()
            ->assertJsonPath('sales.accepted.0', self::VENTE_A);
    }

    /** Une vente déjà enregistrée reste un succès silencieux même si son mois est clôturé depuis. */
    public function test_une_vente_deja_synchronisee_reste_acquittee_apres_la_cloture_de_son_mois(): void
    {
        $vente = $this->vente(self::VENTE_A, ['sold_at' => '2026-07-28 09:00:00']);
        $this->pousser([$vente])->assertOk()->assertJsonPath('sales.accepted.0', self::VENTE_A);

        PeriodicClosure::create(['period' => '2026-07', 'closed_at' => now()]);

        $this->pousser([$vente])->assertOk()
            ->assertJsonPath('sales.accepted.0', self::VENTE_A)
            ->assertJsonPath('sales.rejected', []);
        $this->assertSame(1, Sale::count());
        $this->assertEquals(44, $this->poulet->fresh()->stock_qty);
    }

    /** Une date future reste refusée (règle `before_or_equal:now` conservée). */
    public function test_une_vente_future_reste_refusee(): void
    {
        $reponse = $this->pousser([$this->vente(self::VENTE_A, ['sold_at' => '2026-10-15 09:00:00'])])->assertOk();

        $this->assertSame(self::VENTE_A, $reponse->json('sales.rejected.0.id'));
        $this->assertSame(0, Sale::count());
    }

    /**
     * POINT DE VÉRITÉ UNIQUE du verrou mensuel : le garde de vente appelle
     * `PeriodicClosure::isDateLocked()` (celle du Journal) et personne d'autre
     * n'interroge `periodic_closures` pour une vente. Lecture du SOURCE : une
     * réimplémentation divergente ne produit aucune erreur, seulement des chiffres.
     */
    public function test_le_verrou_mensuel_n_a_qu_un_seul_texte(): void
    {
        $garde = file_get_contents(app_path('Actions/VerifySaleDateAction.php'));
        $this->assertStringContainsString('PeriodicClosure::isDateLocked(', $garde);

        foreach (['Http/Controllers/Api/SyncController.php', 'Livewire/Ventes/PosInterface.php', 'Actions/VerifySaleDateAction.php'] as $fichier) {
            $source = file_get_contents(app_path($fichier));
            $this->assertStringNotContainsString("periodic_closures", $source, $fichier);
            $this->assertStringNotContainsString('PeriodicClosure::where', $source, $fichier);
            $this->assertStringNotContainsString('PeriodicClosure::query', $source, $fichier);
        }
    }

    // ═══════════════════ DÉFAUT 3 — rémanence et mouvement de stock datés ═══════════════════

    private function remanence(string $debut, string $fin): void
    {
        VeterinaryWithdrawalPeriod::create([
            'lot_id' => $this->bande->id, 'product_used' => 'Ivermectine',
            'start_date' => $debut, 'withdrawal_days' => 7, 'end_date' => $fin,
        ]);
    }

    /** Vendue le 04/10 pendant un délai 01/10 → 08/10, reçue le 14/10 : SIGNALÉE (et enregistrée). */
    public function test_la_remanence_est_jugee_a_la_date_de_la_vente(): void
    {
        $this->remanence('2026-10-01', '2026-10-08');

        $this->pousser([$this->vente(self::VENTE_A, ['sold_at' => '2026-10-04 09:00:00'])])
            ->assertOk()->assertJsonPath('sales.accepted.0', self::VENTE_A);

        $this->assertSame(1, Sale::count(), 'enregistrée, jamais refusée pour ce motif');
        $this->assertSame(1, Notification::where('type', 'sale_under_withdrawal')->count());
    }

    /** Vendue le 04/10, traitement commencé le 10/10 : la vente était LÉGALE, aucune fausse alerte. */
    public function test_un_traitement_posterieur_a_la_vente_ne_la_signale_pas(): void
    {
        $this->remanence('2026-10-10', '2026-10-20');

        $this->pousser([$this->vente(self::VENTE_A, ['sold_at' => '2026-10-04 09:00:00'])])->assertOk();

        $this->assertSame(1, Sale::count());
        $this->assertSame(0, Notification::where('type', 'sale_under_withdrawal')->count());
    }

    /** Vendue le 04/10, délai 01/10 → 03/10 expiré AVANT la vente : pas d'alerte. */
    public function test_un_delai_expire_avant_la_vente_ne_la_signale_pas(): void
    {
        $this->remanence('2026-09-26', '2026-10-03');

        $this->pousser([$this->vente(self::VENTE_A, ['sold_at' => '2026-10-04 09:00:00'])])->assertOk();

        $this->assertSame(0, Notification::where('type', 'sale_under_withdrawal')->count());
    }

    public function test_le_mouvement_de_stock_est_date_sur_la_vente(): void
    {
        $this->pousser([$this->vente(self::VENTE_A, ['sold_at' => '2026-10-04 09:30:00'])])->assertOk();

        $mouvement = StockMovement::where('reference_type', 'sale')->where('reference_id', self::VENTE_A)->firstOrFail();
        $this->assertSame('2026-10-04 09:30', $mouvement->movement_date->format('Y-m-d H:i'));
    }

    /** Sans `sold_at` (poste ancien) le mouvement garde la date de réception. */
    public function test_sans_sold_at_le_mouvement_est_date_a_la_reception(): void
    {
        $this->pousser([$this->vente(self::VENTE_A)])->assertOk();

        $mouvement = StockMovement::where('reference_id', self::VENTE_A)->firstOrFail();
        $this->assertSame('2026-10-14', $mouvement->movement_date->format('Y-m-d'));
    }

    // ═══════════════════ DÉFAUT 4 — double comptage fiche + vente ═══════════════════

    /**
     * Le poste envoie la fiche du jour avec `vente = N` PUIS la vente. Le
     * serveur traite les fiches avant les ventes ; la vente ne doit pas
     * rajouter N sur une fiche qui le porte déjà.
     */
    public function test_la_fiche_et_la_vente_du_meme_envoi_ne_comptent_pas_deux_fois(): void
    {
        $this->pousser(
            [$this->vente(self::VENTE_A, ['sold_at' => '2026-10-13 09:00:00'])],
            ['livestock_daily_entries' => [[
                'id' => '44444444-4444-4444-8444-444444444444',
                'lot_id' => $this->bande->id, 'entry_date' => '2026-10-13', 'vente' => 6,
            ]]],
        )->assertOk();

        $fiche = LivestockDailyEntry::where('lot_id', $this->bande->id)->where('entry_date', '2026-10-13')->firstOrFail();
        $this->assertSame(6, (int) $fiche->vente, 'N attendu, 2N = double comptage');
        $this->assertSame(44, (int) $this->bande->fresh()->current_quantity, 'la bande perd 6 têtes, pas 12');
    }

    /** La vente d'une AUTRE bande (ou d'un autre jour) que la fiche reçue est, elle, bien répercutée. */
    public function test_la_vente_sans_fiche_correspondante_est_toujours_repercutee(): void
    {
        $this->pousser(
            [$this->vente(self::VENTE_A, ['sold_at' => '2026-10-13 09:00:00'])],
            ['livestock_daily_entries' => [[
                'id' => '44444444-4444-4444-8444-444444444444',
                'lot_id' => $this->bande->id, 'entry_date' => '2026-10-12', 'vente' => 3,
            ]]],
        )->assertOk();

        $this->assertSame(3, (int) LivestockDailyEntry::where('entry_date', '2026-10-12')->value('vente'));
        $this->assertSame(6, (int) LivestockDailyEntry::where('entry_date', '2026-10-13')->value('vente'));
    }

    /** Une fiche REJETÉE du même envoi ne dispense pas la vente de se répercuter. */
    public function test_une_fiche_rejetee_ne_dispense_pas_la_vente(): void
    {
        $this->pousser(
            [$this->vente(self::VENTE_A, ['sold_at' => '2026-10-13 09:00:00'])],
            ['livestock_daily_entries' => [[
                'id' => '44444444-4444-4444-8444-444444444444',
                'lot_id' => $this->bande->id, 'entry_date' => '2026-10-13', 'vente' => -4,
            ]]],
        )->assertOk();

        $this->assertSame(6, (int) LivestockDailyEntry::where('entry_date', '2026-10-13')->value('vente'));
    }
}
