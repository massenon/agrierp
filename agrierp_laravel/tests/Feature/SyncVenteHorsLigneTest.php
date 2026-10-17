<?php

namespace Tests\Feature;

use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\Sale;
use App\Models\StockMovement;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Models\VeterinaryWithdrawalPeriod;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 14.53 (Sprint 14) — UNE VENTE HORS LIGNE PRODUIT LES MÊMES EFFETS
 * QU'UNE VENTE AU COMPTOIR.
 *
 * 🔴 DÉFAUT RÉEL COMBLÉ ICI. `POST /api/sync/push` n'insérait QUE la vente et
 * ses lignes. Une vente encaissée hors ligne puis remontée arrivait donc en
 * base comme une **ligne morte** : stock inchangé, fiche d'élevage inchangée,
 * aucune écriture comptable, aucun encaissement. Bilan, Compte de Résultat,
 * stock et effectif de bande étaient faux — silencieusement, et d'autant plus
 * longtemps que le poste restait hors ligne.
 *
 * C'est exactement la classe de défaut que le Sprint 14 a passé son temps à
 * corriger sur la surface web, restée grande ouverte sur le chemin de la
 * synchronisation.
 */
class SyncVenteHorsLigneTest extends TestCase
{
    use RefreshDatabase;

    private const MDP = 'AgriERP@2026';

    private User $caissier;

    private Product $poulet;

    private LivestockLot $bande;

    private string $token;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-ventes', 'manage-ventes'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('caissier', 'web')->givePermissionTo(['view-ventes', 'manage-ventes']);

        $this->caissier = User::create([
            'name' => 'Caissière POS', 'username' => 'caisse',
            'email' => 'caisse@olouwachegoun.bj',
            'password' => bcrypt(self::MDP), 'is_active' => true,
        ]);
        $this->caissier->assignRole('caissier');

        FiscalYear::create([
            'year' => now()->year,
            'start_date' => now()->startOfYear()->format('Y-m-d'),
            'end_date' => now()->endOfYear()->format('Y-m-d'),
            'status' => 'ouvert',
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
            'created_date' => now()->subMonths(2)->format('Y-m-d'),
            'status' => 'actif', 'is_active' => true,
        ]);

        $this->token = $this->postJson('/api/auth/login', [
            'identifiant' => 'caisse', 'password' => self::MDP, 'device_name' => 'poste-ferme-01',
        ])->json('token');
    }

    private function pousserVente(array $remplacements = [])
    {
        return $this->withHeader('Authorization', 'Bearer '.$this->token)
            ->postJson('/api/sync/push', [
                'sales' => [array_merge([
                    'id' => '11111111-1111-4111-8111-111111111111',
                    'payment_mode' => 'especes',
                    'subtotal' => 21_000,
                    'discount' => 0,
                    'total' => 21_000,
                    'status' => 'validee',
                    'lines' => [[
                        'product_id' => $this->poulet->id,
                        'lot_id' => $this->bande->id,
                        'qty' => 6,
                        'unit_price' => 3_500,
                        'manual_total_amount' => 21_000,
                    ]],
                ], $remplacements)],
            ]);
    }

    /** La vente elle-même arrive bien, avec son UUID client préservé. */
    public function test_the_offline_sale_reaches_the_server(): void
    {
        $this->pousserVente()->assertOk();

        $vente = Sale::findOrFail('11111111-1111-4111-8111-111111111111');
        $this->assertEquals(21_000, (float) $vente->total);
        $this->assertCount(1, $vente->lines);
    }

    /** 🔴→✅ PREMIER EFFET : le stock est décrémenté. */
    public function test_the_stock_is_decremented(): void
    {
        $this->pousserVente();

        $this->assertEquals(44, (float) $this->poulet->fresh()->stock_qty);
        $this->assertEquals(1, StockMovement::where('reference_type', 'sale')->count());
    }

    /** 🔴→✅ DEUXIÈME EFFET : la fiche d'élevage suit. */
    public function test_the_fiche_elevage_follows(): void
    {
        $this->pousserVente();

        $fiche = LivestockDailyEntry::where('lot_id', $this->bande->id)->firstOrFail();

        $this->assertEquals(6, $fiche->vente);
        $this->assertEquals(44, $fiche->effectif_final, '50 sujets moins 6 vendus');
        $this->assertEquals(44, $this->bande->fresh()->current_quantity);
    }

    /** 🔴→✅ TROISIÈME EFFET : l'écriture comptable est générée. */
    public function test_the_accounting_entry_is_generated(): void
    {
        $this->pousserVente();

        $ecriture = AccountingEntry::where('source_type', 'sale')->firstOrFail();

        $this->assertEquals(21_000, (float) $ecriture->total_debit);
        $this->assertEquals((float) $ecriture->total_debit, (float) $ecriture->total_credit,
            'toute ecriture est equilibree avant enregistrement');
    }

    /** 🔴→✅ QUATRIÈME EFFET : la caisse est réellement créditée. */
    public function test_the_treasury_is_credited(): void
    {
        $this->pousserVente();

        $this->assertEquals(21_000, (float) TreasuryAccount::where('type', 'caisse')->value('balance'));
    }

    /**
     * ⚠️ UN RENVOI APRÈS COUPURE RÉSEAU NE DOIT RIEN DOUBLER. Le serveur traite
     * une vente déjà connue comme un succès silencieux : sans cela, le poste
     * renverrait ce dont il n'a pas eu l'accusé et décrémenterait le stock deux
     * fois.
     */
    public function test_a_repeated_push_doubles_nothing(): void
    {
        $this->pousserVente()->assertOk();
        $this->pousserVente()->assertOk();

        $this->assertEquals(1, Sale::count());
        $this->assertEquals(44, (float) $this->poulet->fresh()->stock_qty);
        $this->assertEquals(1, AccountingEntry::where('source_type', 'sale')->count());
        $this->assertEquals(21_000, (float) TreasuryAccount::where('type', 'caisse')->value('balance'));
    }

    /** Une ligne sans bande (provende) ne crée aucune fiche d'élevage. */
    public function test_a_line_without_a_lot_creates_no_fiche(): void
    {
        // ⚠️ TOTAL AJUSTE AUX LIGNES (ticket 14.70). Ce jeu d'essai remplacait
        // les lignes par 7 000 F en laissant le total par defaut a 21 000 :
        // une charge utile qu'aucun client reel n'enverrait. Le controle de
        // coherence l'a relevee des son premier passage.
        $this->pousserVente([
            'subtotal' => 7_000,
            'total' => 7_000,
            'lines' => [[
                'product_id' => $this->poulet->id,
                'lot_id' => null,
                'qty' => 2,
                'unit_price' => 3_500,
                'manual_total_amount' => 7_000,
            ]],
        ]);

        $this->assertEquals(0, LivestockDailyEntry::count());
        $this->assertEquals(48, (float) $this->poulet->fresh()->stock_qty,
            'le stock baisse quand meme');
    }

    /**
     * ⚠️ LA RÉMANENCE VÉTÉRINAIRE DESCEND AU POSTE — C'EST UN BLOCAGE DE SANTÉ
     * PUBLIQUE. Le poste encaisse HORS LIGNE : sans ces périodes, il n'a aucun
     * moyen de connaître l'interdiction et laisserait vendre une viande
     * porteuse de résidus d'antibiotiques.
     */
    public function test_the_withdrawal_periods_reach_the_client(): void
    {
        VeterinaryWithdrawalPeriod::create([
            'lot_id' => $this->bande->id,
            'product_used' => 'Antibiotique polyvalent',
            'start_date' => now()->subDays(2)->format('Y-m-d'),
            'withdrawal_days' => 7,
            'end_date' => now()->addDays(5)->format('Y-m-d'),
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->token)
            ->getJson('/api/sync/pull')
            ->assertOk()
            ->assertJsonPath('veterinary_withdrawal_periods.0.lot_id', $this->bande->id);
    }

    /** Une rémanence expirée n'est plus servie : elle ne bloque plus rien. */
    public function test_an_expired_withdrawal_is_not_served(): void
    {
        VeterinaryWithdrawalPeriod::create([
            'lot_id' => $this->bande->id,
            'product_used' => 'Déparasitant',
            'start_date' => now()->subDays(30)->format('Y-m-d'),
            'withdrawal_days' => 7,
            'end_date' => now()->subDays(23)->format('Y-m-d'),
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->token)
            ->getJson('/api/sync/pull')
            ->assertOk()
            ->assertJsonCount(0, 'veterinary_withdrawal_periods');
    }

    // ────────────────────────────────────────────────────────────────────
    // TICKET 14.71 — LA DATE DE LA VENTE, ET NON CELLE DU TIRAGE.
    //
    // 🔴🔴 `sales` NE PORTAIT AUCUNE DATE DE VENTE : seulement `created_at`,
    // posee par Eloquent a l'INSERT. Une vente encaissee hors ligne le 12 et
    // remontee le 20 etait donc, pour le serveur, une vente du 20. Le poste
    // tenait pourtant l'heure reelle (`sold_at` en base Drift) — il ne
    // l'envoyait pas, et le serveur n'avait pas de colonne pour l'accueillir.
    //
    // Le defaut ne se manifeste QUE sur un poste reste longtemps deconnecte,
    // c'est-a-dire exactement la situation pour laquelle le mode hors ligne
    // existe. Les cinq tests ci-dessus passaient tous : ils poussaient et
    // verifiaient le meme jour.
    // ────────────────────────────────────────────────────────────────────

    /** Le jour reellement encaisse est conserve. */
    public function test_the_sale_keeps_the_day_it_was_encashed(): void
    {
        $jour = now()->subDays(8)->setTime(14, 30);

        $this->pousserVente(['sold_at' => $jour->format('Y-m-d H:i:s')])->assertOk();

        $vente = Sale::findOrFail('11111111-1111-4111-8111-111111111111');

        $this->assertEquals($jour->format('Y-m-d H:i'), $vente->sold_at->format('Y-m-d H:i'));
        $this->assertNotEquals(
            $vente->sold_at->format('Y-m-d'),
            $vente->created_at->format('Y-m-d'),
            'created_at reste la date de RECEPTION : les deux doivent diverger',
        );
    }

    /**
     * 🔴→✅ L'ECRITURE SYSCOHADA PORTE LE JOUR DE LA VENTE.
     *
     * ⚠️ C'est la consequence la plus couteuse du defaut : une vente de fin
     * juillet remontee debut aout etait imputee a l'exercice du mois d'aout.
     * Pour un comptable, la balance des DEUX mois etait fausse.
     */
    public function test_the_accounting_entry_is_dated_on_the_sale_day(): void
    {
        $jour = now()->subDays(8)->setTime(14, 30);

        $this->pousserVente(['sold_at' => $jour->format('Y-m-d H:i:s')]);

        $ecriture = AccountingEntry::where('source_type', 'sale')->firstOrFail();

        $this->assertEquals(
            $jour->format('Y-m-d'),
            \Illuminate\Support\Carbon::parse($ecriture->entry_date)->format('Y-m-d'),
        );
        $this->assertNotEquals(
            now()->format('Y-m-d'),
            \Illuminate\Support\Carbon::parse($ecriture->entry_date)->format('Y-m-d'),
        );
    }

    /**
     * 🔴→✅ LA FICHE D'ELEVAGE EST CELLE DU JOUR DE LA VENTE.
     *
     * ⚠️ `pushSales` appelait `RecordSaleOnFicheElevageAction::execute()` SANS
     * date — l'action retombait sur `now()`. Les six tetes sortaient donc de
     * la fiche du jour du tirage, tandis que la fiche du jour reel restait
     * incoherente avec la sortie physique des animaux.
     */
    public function test_the_fiche_elevage_is_dated_on_the_sale_day(): void
    {
        $jour = now()->subDays(8)->setTime(14, 30);

        $this->pousserVente(['sold_at' => $jour->format('Y-m-d H:i:s')]);

        $fiche = LivestockDailyEntry::where('lot_id', $this->bande->id)->firstOrFail();

        $this->assertEquals(
            $jour->format('Y-m-d'),
            \Illuminate\Support\Carbon::parse($fiche->entry_date)->format('Y-m-d'),
        );
        $this->assertEquals(6, $fiche->vente);
    }

    /** ⚠️ Une vente datee du futur est refusee — et elle seule. */
    public function test_a_sale_dated_in_the_future_is_refused(): void
    {
        $reponse = $this->pousserVente([
            'sold_at' => now()->addDay()->format('Y-m-d H:i:s'),
        ]);

        $reponse->assertOk();
        $this->assertCount(0, $reponse->json('sales.accepted'));
        $this->assertCount(1, $reponse->json('sales.rejected'));
        $this->assertEquals(0, Sale::count());
    }

    /**
     * ⚠️ UN POSTE ANCIEN, QUI N'ENVOIE PAS ENCORE `sold_at`, RESTE ACCEPTE.
     *
     * Le champ est `nullable` pour cette raison exacte : rejeter l'envoi
     * priverait la ferme de ses ventes hors ligne le temps que chaque poste
     * soit mis a jour. Le repli sur `created_at` reproduit alors l'ancien
     * comportement, ni mieux ni pire.
     */
    public function test_a_client_that_does_not_send_the_date_is_still_accepted(): void
    {
        $this->pousserVente()->assertOk();

        $vente = Sale::findOrFail('11111111-1111-4111-8111-111111111111');
        $this->assertNull($vente->sold_at);

        $ecriture = AccountingEntry::where('source_type', 'sale')->firstOrFail();
        $this->assertEquals(
            now()->format('Y-m-d'),
            \Illuminate\Support\Carbon::parse($ecriture->entry_date)->format('Y-m-d'),
        );
    }

    /**
     * 🔴→✅ TICKET 14.80 — LA NORMALISATION FISCALE MANQUAIT À CE CANAL.
     *
     * ⚠️⚠️ CE CANAL APPLIQUAIT QUATRE EFFETS ET EN OUBLIAIT UN CINQUIÈME. La
     * caisse WEB transmet chaque vente au dispositif MeCeF (ticket 7.1) ;
     * l'envoi hors ligne, lui, ne le faisait pas. Une vente encaissée au
     * comptoir sans réseau arrivait donc en base avec `mecef_status` NUL :
     * jamais déclarée à la DGI, sans QR, invisible de l'écran Facturation.
     *
     * Le poste étant fait POUR travailler hors ligne, le trou fiscal grandit
     * avec l'usage — et rien ne le signalait.
     */
    public function test_a_pushed_sale_is_normalised_with_the_mecef_device(): void
    {
        $this->pousserVente()->assertOk();

        $vente = \App\Models\Sale::find('11111111-1111-4111-8111-111111111111');

        $this->assertNotNull($vente);
        $this->assertContains(
            $vente->mecef_status,
            ['transmise', 'erreur'],
            'Une vente remontée du poste doit avoir été présentée au dispositif '
            ."MeCeF : `null` signifie que personne ne l'a jamais déclarée."
        );

        if ($vente->mecef_status === 'transmise') {
            $this->assertNotNull($vente->mecef_qr_ref);
        }
    }

    /**
     * ⚠️ LES FACTURES DESCENDENT AU POSTE avec leur statut : sans cela, l'écran
     * Facturation ne montrerait que les ventes de CE poste — la caissière
     * croirait la ferme à 3 factures le mois où elle en a 40.
     */
    public function test_the_invoices_reach_the_device_with_their_mecef_status(): void
    {
        $this->pousserVente()->assertOk();

        $reponse = $this->withHeader('Authorization', 'Bearer '.$this->token)
            ->getJson('/api/sync/pull')
            ->assertOk();

        $reponse->assertJsonCount(1, 'sales');
        $this->assertContains(
            $reponse->json('sales.0.mecef_status'),
            ['transmise', 'erreur'],
        );
    }
}
