<?php

namespace Tests\Feature;

use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\TreasuryAccount;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

/**
 * Ticket 15.33 — LES MOTIFS DE REFUS DU PUSH SONT EN FRANÇAIS.
 *
 * Défaut D1 (audit indépendant de 15.30/F0.92) : `pushSales` validait `sold_at` avec
 * `before_or_equal:now` AVANT `VerifySaleDateAction`, et le dépôt n'a pas de dossier `lang/` :
 * une date future était refusée par « The sold at field must be a date before or equal to now. »
 * au lieu du motif français de 15.30. Le même mécanisme existait dans TOUS les handlers de
 * `/api/sync/push` : `rejected[].reason` = `$e->getMessage()` d'une `ValidationException`
 * sans messages français (et, pour plusieurs erreurs, « (and N more errors) »).
 *
 * Ce fichier est le GARDE-FOU : il pousse un enregistrement invalide dans CHAQUE table du push
 * et exige un motif sans aucune formule anglaise par défaut. Il ne vérifie PAS le contrat
 * (clés, forme) : seulement le texte des motifs.
 */
class SyncMotifsRefusFrancaisTest extends TestCase
{
    use RefreshDatabase;

    private const ID = '33333333-3333-4333-8333-333333333333';

    private User $admin;

    private Product $poulet;

    private LivestockLot $bande;

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow('2026-10-14 12:00:00');

        // Ticket S1 : `manage-elevage` et `manage-rh` — l'envoi contrôle désormais le rôle de chaque table.
        $permissions = [
            'view-ventes', 'manage-ventes', 'manage-achats', 'manage-stocks', 'manage-administration',
            'manage-elevage', 'manage-rh',
        ];
        foreach ($permissions as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('gestionnaire', 'web')->givePermissionTo($permissions);

        $this->admin = User::create([
            'name' => 'Gestionnaire', 'username' => 'gest', 'email' => 'gest@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->admin->assignRole('gestionnaire');

        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
        foreach ([['411', 'Clients', 4], ['531', 'Caisse', 5], ['701', 'Ventes', 7], ['443', 'TVA collectée', 4]] as [$c, $l, $k]) {
            ChartOfAccount::create(['code' => $c, 'label' => $l, 'class' => $k, 'is_active' => true]);
        }
        TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);

        $espece = LivestockSpecies::create(['label' => 'Aviculture', 'code' => 'AVI', 'is_active' => true]);
        $categorie = ProductCategory::create(['label' => 'Volailles', 'is_active' => true]);
        $this->poulet = Product::create([
            'sku' => 'AVI-001', 'name' => 'Poulet', 'category_id' => $categorie->id, 'species_id' => $espece->id,
            'unit' => 'u', 'pricing_mode' => 'fourchette', 'price_min' => 3000, 'price_max' => 4000,
            'tva_rate' => 0, 'stock_qty' => 50, 'is_active' => true,
        ]);
        $this->bande = LivestockLot::create([
            'code' => 'AVI-2026-01', 'species_id' => $espece->id, 'stage' => 'croissance',
            'initial_quantity' => 50, 'current_quantity' => 50, 'created_date' => '2026-01-05',
            'status' => 'actif', 'is_active' => true,
        ]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();

        parent::tearDown();
    }

    private function pousser(array $corps)
    {
        return $this->actingAs($this->admin, 'sanctum')
            ->postJson('/api/sync/push', array_merge(['device_id' => 'poste-test'], $corps))
            ->assertOk();
    }

    private function vente(array $remplacements = []): array
    {
        return array_merge([
            'id' => self::ID, 'payment_mode' => 'especes', 'subtotal' => 21000, 'discount' => 0, 'total' => 21000,
            'lines' => [[
                'product_id' => $this->poulet->id, 'lot_id' => $this->bande->id,
                'qty' => 6, 'unit_price' => 3500, 'manual_total_amount' => 21000,
            ]],
        ], $remplacements);
    }

    /** Formules anglaises par défaut de Laravel : aucune ne doit atteindre le poste. */
    private function assertMotifFrancais(?string $motif, string $contexte): void
    {
        $this->assertNotNull($motif, "$contexte : aucun motif de rejet");
        $this->assertNotSame('', trim($motif), "$contexte : motif vide");
        $this->assertDoesNotMatchRegularExpression(
            '/\b(The|field|must|selected|valid|has already been|more errors?|greater|less than|characters|required|may not)\b/',
            $motif,
            "$contexte : motif ANGLAIS remonté au poste : « $motif »"
        );
    }

    // ═══════════════ D1 — la vente datée ═══════════════

    public function test_une_vente_datee_du_futur_est_refusee_avec_un_motif_francais(): void
    {
        $r = $this->pousser(['sales' => [$this->vente(['sold_at' => '2026-10-20 09:00:00'])]]);

        $motif = $r->json('sales.rejected.0.reason');
        $this->assertSame(self::ID, $r->json('sales.rejected.0.id'));
        $this->assertMotifFrancais($motif, 'vente future');
        $this->assertStringContainsString('Vente refusée', $motif);
        $this->assertStringContainsString('2026-10-20', $motif, 'le motif nomme la date envoyée par le poste');
        $this->assertStringContainsString('futur', $motif);
        $this->assertSame([], $r->json('sales.accepted'));
    }

    /**
     * DÉCISION : REJET FRANC, pas de tolérance d'horloge. Mesure de la pratique du dépôt : aucune
     * tolérance d'horloge n'existe (`server_time` n'est que le curseur de tirage ; la seule
     * « TOLERANCE_JOURS » est celle du rapprochement bancaire, sans rapport). En inventer une serait
     * une règle métier non décidée. Une vente à 12:03 reçue à 12:00 est donc refusée, AVEC le motif
     * français de `VerifySaleDateAction`.
     */
    public function test_une_vente_du_jour_avec_horloge_avancee_de_3_minutes_est_refusee_en_francais(): void
    {
        $r = $this->pousser(['sales' => [$this->vente(['sold_at' => '2026-10-14 12:03:00'])]]);

        $motif = $r->json('sales.rejected.0.reason');
        $this->assertMotifFrancais($motif, 'vente du jour, horloge avancée');
        $this->assertStringContainsString('Vente refusée', $motif);
        $this->assertStringContainsString('2026-10-14 12:03:00', $motif);
        $this->assertStringContainsString('futur', $motif);
    }

    public function test_une_vente_a_l_heure_exacte_reste_acceptee(): void
    {
        $r = $this->pousser(['sales' => [$this->vente(['sold_at' => '2026-10-14 12:00:00'])]]);

        $this->assertSame([self::ID], $r->json('sales.accepted'));
        $this->assertSame([], $r->json('sales.rejected'));
    }

    // ═══════════════ Garde-fou : un enregistrement invalide par table ═══════════════

    /** @return array<string, array{0: string, 1: array}> */
    public static function enregistrementsInvalides(): array
    {
        $id = self::ID;

        // Champs obligatoires absents + types faux : plusieurs règles échouent à la fois, ce qui
        // exerce aussi le « (and N more errors) » de Laravel.
        return [
            'livestock_daily_entries' => ['livestock_daily_entries', ['id' => $id, 'lot_id' => 'pas-un-uuid', 'entry_date' => '2099-01-01', 'mort' => -3]],
            'sales' => ['sales', ['id' => $id, 'payment_mode' => 'especes', 'total' => 'abc', 'sold_at' => '2099-01-01', 'lines' => []]],
            'stock_adjustments' => ['stock_adjustments', ['client_ref' => 'r1', 'product_id' => 'x', 'type' => 'autre', 'quantity' => 0]],
            'veterinary_records' => ['veterinary_records', ['id' => $id, 'lot_id' => 'x', 'withdrawal_days' => -1]],
            'expenses' => ['expenses', ['id' => $id, 'category' => 'inconnue', 'amount' => 0]],
            'livestock_reproduction_events' => ['livestock_reproduction_events', ['id' => $id, 'lot_id' => 'x', 'saillie_date' => '2099-01-01']],
            'purchases' => ['purchases', ['id' => $id, 'payment_mode' => 'troc', 'purchase_date' => '2099-01-01', 'lines' => []]],
            'attendance_records' => ['attendance_records', ['id' => $id, 'attendance_date' => '2099-01-01', 'check_in' => '25h', 'status' => 'dort']],
            'products' => ['products', ['id' => $id]],
            'suppliers' => ['suppliers', ['id' => $id, 'email' => 'pas-un-courriel']],
            'customers' => ['customers', ['id' => $id, 'email' => 'pas-un-courriel']],
            'mails' => ['mails', ['id' => $id, 'type' => 'autre']],
            'archived_documents' => ['archived_documents', ['id' => $id, 'archived_date' => 'hier-ou-demain']],
            'administrative_documents' => ['administrative_documents', ['id' => $id, 'status' => 'autre']],
            'supplier_payments' => ['supplier_payments', ['id' => $id, 'supplier_id' => 'x', 'amount' => 0]],
            'purchase_returns' => ['purchase_returns', ['id' => $id, 'purchase_id' => 'x']],
            'supplier_refunds' => ['supplier_refunds', ['id' => $id, 'amount' => 0]],
            'customer_advances' => ['customer_advances', ['id' => $id, 'customer_id' => 'x', 'amount' => 0]],
            'advance_imputations' => ['advance_imputations', ['id' => $id, 'amount' => 0]],
        ];
    }

    #[DataProvider('enregistrementsInvalides')]
    public function test_le_motif_de_refus_de_chaque_table_du_push_est_en_francais(string $cle, array $enregistrement): void
    {
        $r = $this->pousser([$cle => [$enregistrement]]);

        $motif = $r->json("$cle.rejected.0.reason");
        $this->assertMotifFrancais($motif, $cle);
        $this->assertSame([], $r->json("$cle.accepted"), "$cle : l'enregistrement invalide ne doit pas être accepté");
    }

    /** Plusieurs erreurs : TOUTES sont rapportées, sans « (and N more errors) ». */
    public function test_plusieurs_erreurs_sont_toutes_rapportees_en_francais(): void
    {
        $r = $this->pousser(['expenses' => [['id' => self::ID, 'category' => 'inconnue', 'amount' => 0]]]);

        $motif = $r->json('expenses.rejected.0.reason');
        $this->assertStringNotContainsString('more error', $motif);
        $this->assertGreaterThanOrEqual(3, substr_count($motif, '.'), 'plusieurs erreurs doivent figurer dans le motif');
    }

    /** Les champs sont nommés en français (« fournisseur », pas « supplier id »). */
    public function test_les_champs_sont_nommes_en_francais_dans_le_motif(): void
    {
        $r = $this->pousser(['purchases' => [['id' => self::ID, 'payment_mode' => 'troc', 'lines' => []]]]);

        $motif = $r->json('purchases.rejected.0.reason');
        $this->assertStringContainsString('fournisseur', $motif);
        $this->assertStringContainsString('compte de trésorerie', $motif);
        $this->assertStringNotContainsString('supplier id', $motif);
    }

    // ═══════════════ Ticket 15.37 (L12) — UUID VALIDE mais INCONNU : la règle `exists` ═══════════════

    private const INCONNU = '99999999-9999-4999-8999-999999999999';

    /**
     * Les cas de la table `enregistrementsInvalides` utilisent des identifiants comme « x » ou « pas-un-uuid » :
     * ils échouent sur la règle `uuid` et n'atteignent JAMAIS la règle `exists`. Retirer le message `exists`
     * de `MotifsRefusPush::messages()` laissait donc toute la suite verte, alors qu'un identifiant bien formé
     * mais inconnu (bande supprimée, produit créé ailleurs) est le cas RÉEL du terrain. Ici l'UUID est valide.
     *
     * @return array<string, array{0: string, 1: string}> nom => [table, clé du jeu dans `payloadInconnu`]
     */
    public static function identifiantsInconnus(): array
    {
        return [
            'fiches : bande inconnue' => ['livestock_daily_entries', 'fiche_bande'],
            'ventes : produit inconnu' => ['sales', 'vente_produit'],
            'ventes : bande inconnue' => ['sales', 'vente_bande'],
            'pointages : employé inconnu' => ['attendance_records', 'pointage_employe'],
            'achats : fournisseur inconnu' => ['purchases', 'achat_fournisseur'],
            'achats : compte inconnu' => ['purchases', 'achat_compte'],
            'achats : produit inconnu' => ['purchases', 'achat_produit'],
            'règlements fournisseur : fournisseur inconnu' => ['supplier_payments', 'reglement_fournisseur'],
            'règlements fournisseur : compte inconnu' => ['supplier_payments', 'reglement_compte'],
            'dépenses : compte inconnu' => ['expenses', 'depense_compte'],
            'soins : bande inconnue' => ['veterinary_records', 'soin_bande'],
            'reproduction : bande inconnue' => ['livestock_reproduction_events', 'repro_bande'],
            'ajustements de stock : produit inconnu' => ['stock_adjustments', 'ajustement_produit'],
        ];
    }

    /** Un enregistrement par ailleurs VALIDE, dont les seuls identifiants fautifs sont des UUID bien formés mais inconnus. */
    private function payloadInconnu(string $cle): array
    {
        $compte = TreasuryAccount::first()->id;
        $ligneAchat = fn (string $produit) => [['product_id' => $produit, 'qty' => 2, 'unit_price' => 1000]];
        $achat = fn (array $r) => array_merge([
            'id' => self::ID, 'supplier_id' => self::INCONNU, 'treasury_account_id' => $compte, 'payment_mode' => 'especes',
            'purchase_date' => '2026-10-13', 'lines' => $ligneAchat($this->poulet->id),
        ], $r);

        return match ($cle) {
            'fiche_bande' => ['id' => self::ID, 'lot_id' => self::INCONNU, 'entry_date' => '2026-10-13', 'mort' => 1],
            'vente_produit' => $this->vente(['lines' => [[
                'product_id' => self::INCONNU, 'lot_id' => $this->bande->id,
                'qty' => 6, 'unit_price' => 3500, 'manual_total_amount' => 21000,
            ]]]),
            'vente_bande' => $this->vente(['lines' => [[
                'product_id' => $this->poulet->id, 'lot_id' => self::INCONNU,
                'qty' => 6, 'unit_price' => 3500, 'manual_total_amount' => 21000,
            ]]]),
            'pointage_employe' => [
                'id' => self::ID, 'employee_id' => self::INCONNU, 'attendance_date' => '2026-10-13',
                'check_in' => '08:00', 'status' => 'present',
            ],
            'achat_fournisseur' => $achat([]),
            'achat_compte' => $achat(['treasury_account_id' => self::INCONNU]),
            'achat_produit' => $achat(['lines' => $ligneAchat(self::INCONNU)]),
            'reglement_fournisseur' => [
                'id' => self::ID, 'supplier_id' => self::INCONNU, 'treasury_account_id' => $compte,
                'amount' => 5000, 'payment_date' => '2026-10-13',
            ],
            'reglement_compte' => [
                'id' => self::ID, 'supplier_id' => self::INCONNU, 'treasury_account_id' => self::INCONNU,
                'amount' => 5000, 'payment_date' => '2026-10-13',
            ],
            'depense_compte' => [
                'id' => self::ID, 'expense_date' => '2026-10-13', 'label' => 'Test', 'category' => 'autre',
                'amount' => 1000, 'treasury_account_id' => self::INCONNU,
            ],
            'soin_bande' => [
                'id' => self::ID, 'lot_id' => self::INCONNU, 'record_date' => '2026-10-13',
                'action_type' => 'vaccin', 'label' => 'Test',
            ],
            'repro_bande' => ['id' => self::ID, 'lot_id' => self::INCONNU, 'saillie_date' => '2026-10-01'],
            'ajustement_produit' => [
                'client_ref' => 'r1', 'product_id' => self::INCONNU, 'type' => 'perte', 'quantity' => 1,
            ],
        };
    }

    #[DataProvider('identifiantsInconnus')]
    public function test_un_uuid_valide_mais_inconnu_est_refuse_avec_le_motif_exists_en_francais(string $table, string $cle): void
    {
        $r = $this->pousser([$table => [$this->payloadInconnu($cle)]]);

        $motif = $r->json("$table.rejected.0.reason");
        $this->assertMotifFrancais($motif, $cle);
        $this->assertStringContainsString(
            'ne correspond à aucun enregistrement connu du serveur',
            $motif,
            "$cle : le motif `exists` doit être celui de MotifsRefusPush : « $motif »"
        );
        $this->assertStringNotContainsString('UUID', $motif, "$cle : l'UUID est valide, seule la règle `exists` échoue");
        $this->assertSame([], $r->json("$table.accepted"));
    }

    /** Client inconnu : l'avance ne passe pas par `exists` mais par le service — le motif doit rester français. */
    public function test_une_avance_pour_un_client_inconnu_est_refusee_en_francais(): void
    {
        $r = $this->pousser(['customer_advances' => [[
            'id' => self::ID, 'customer_id' => self::INCONNU, 'treasury_account_id' => TreasuryAccount::first()->id,
            'amount' => 5000, 'advance_date' => '2026-10-13',
        ]]]);

        $this->assertMotifFrancais($r->json('customer_advances.rejected.0.reason'), 'avance, client inconnu');
        $this->assertSame([], $r->json('customer_advances.accepted'));
    }
}
