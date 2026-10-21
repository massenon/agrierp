<?php

namespace Tests\Feature;

use App\Actions\CreditTreasuryForSaleAction;
use App\Exceptions\TransactionInterbloqueeException;
use App\Livewire\Facturation\Facturation;
use App\Livewire\Ventes\PosInterface;
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
use App\Models\SaleLine;
use App\Models\StockMovement;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Services\Mecef\FacturationMecefService;
use App\Services\Mecef\MecefGatewayInterface;
use App\Services\TransactionRejouable;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket S-T13 — LA CAISSE DU WEB RÉSISTE AUX INTERBLOCAGES COMME L'ENVOI DES POSTES.
 *
 * Sur MariaDB, une vente du web faite pendant que des postes envoient des ventes de la même bande s'interbloquait avec
 * leur envoi (fiche du jour, bande, stock) : la vente était annulée et perdue (graine 314 de l'essai à plusieurs
 * postes). Elle est maintenant une transaction rejouée (`TransactionRejouable`, le même point que l'envoi des postes),
 * et la facture normalisée MeCeF part APRÈS la validation de la transaction, une seule fois.
 *
 * SQLite ne s'interbloque pas : l'interblocage est SIMULÉ — l'encaissement (`CreditTreasuryForSaleAction`, le dernier
 * effet de la vente, après pièce, lignes, stock, fiche et écriture) lève l'exception de MariaDB une ou plusieurs fois.
 * Chaque test tourne dans la transaction de `RefreshDatabase` : le service y est posé « au sommet » à ce niveau
 * (`niveauDeBase`), et SQLite annule vraiment chaque essai par son point de sauvegarde, comme MariaDB au sommet.
 */
class CaisseWebInterblocageTest extends TestCase
{
    use RefreshDatabase;

    private const JOUR = '2026-10-14';

    private Product $poulet;

    private LivestockLot $bande;

    /** Le dispositif MeCeF de l'essai : compte ses appels, note le niveau de transaction, répond dans l'ordre demandé. */
    private MecefGatewayInterface $mecef;

    private int $niveauDeBase;

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow(self::JOUR.' 12:00:00');

        foreach (['view-ventes', 'manage-ventes', 'view-facturation', 'manage-facturation'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('caissier', 'web')->givePermissionTo(['view-ventes', 'manage-ventes', 'view-facturation', 'manage-facturation']);

        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
        foreach ([['411', 'Clients', 4], ['531', 'Caisse', 5], ['701', 'Ventes de marchandises', 7], ['443', 'TVA collectée', 4]] as [$code, $label, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $classe, 'is_active' => true]);
        }
        TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse Principale', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);

        $espece = LivestockSpecies::create(['label' => 'Aviculture', 'code' => 'aviculture', 'is_active' => true]);
        $categorie = ProductCategory::create(['label' => 'Volailles', 'is_active' => true]);
        $this->poulet = Product::create([
            'sku' => 'AVI-001', 'name' => 'Poulet goliath', 'category_id' => $categorie->id,
            'species_id' => $espece->id, 'unit' => 'u', 'pricing_mode' => 'fourchette',
            'price_min' => 3_000, 'price_max' => 4_000, 'tva_rate' => 0, 'stock_qty' => 50, 'is_active' => true,
        ]);
        $this->bande = LivestockLot::create([
            'code' => 'ESSAI-A', 'species_id' => $espece->id, 'stage' => 'engraissement',
            'initial_quantity' => 300, 'current_quantity' => 300,
            'created_date' => '2026-10-01', 'status' => 'actif', 'is_active' => true,
        ]);

        $caissiere = User::create([
            'name' => 'Caissière', 'username' => 'caisse', 'email' => 'caisse@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $caissiere->assignRole('caissier');
        $this->actingAs($caissiere);

        // La transaction de `RefreshDatabase` est le « sommet » de ces tests (voir l'en-tête).
        $this->niveauDeBase = DB::transactionLevel();
        $this->app->instance(TransactionRejouable::class, new TransactionRejouable($this->niveauDeBase));

        $this->mecef = new class implements MecefGatewayInterface
        {
            public int $appels = 0;

            /** @var array<int, int> niveau de transaction à chaque appel */
            public array $niveaux = [];

            /** @var array<int, bool|\Throwable> réponses à venir (vide : succès) */
            public array $reponses = [];

            public function transmit(Sale $sale): array
            {
                $this->appels++;
                $this->niveaux[] = DB::transactionLevel();
                $reponse = array_shift($this->reponses) ?? true;

                if ($reponse instanceof \Throwable) {
                    throw $reponse;
                }

                return $reponse
                    ? ['success' => true, 'qr_ref' => 'NIM-ESSAI|'.$this->appels, 'message' => 'Facture transmise (essai).']
                    : ['success' => false, 'qr_ref' => null, 'message' => 'Délai de connexion dépassé avec le dispositif MeCeF (essai).'];
            }
        };
        $this->app->instance(MecefGatewayInterface::class, $this->mecef);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();

        parent::tearDown();
    }

    // ═══ Outils ═══

    /** L'exception que MariaDB lève sur un interblocage (SQLSTATE 40001, code 1213). */
    private static function interblocage(): QueryException
    {
        $pdo = new \PDOException('SQLSTATE[40001]: Serialization failure: 1213 Deadlock found when trying to get lock; try restarting transaction');
        $pdo->errorInfo = ['40001', 1213, 'Deadlock found when trying to get lock; try restarting transaction'];

        return new QueryException('mysql', 'update `livestock_daily_entries` set `vente` = ? where `id` = ?', [], $pdo);
    }

    /**
     * Attente de verrou dépassée (1205), message d'un serveur réglé en FRANÇAIS (`lc_messages`) : SQLSTATE HY000, aucun
     * mot anglais que Laravel reconnaîtrait — seul le CODE la désigne.
     */
    private static function attenteDeVerrou(): QueryException
    {
        $pdo = new \PDOException("SQLSTATE[HY000]: General error: 1205 Timeout sur l'obtention du verrou; Essayez de redémarrer la transaction");
        $pdo->errorInfo = ['HY000', 1205, "Timeout sur l'obtention du verrou; Essayez de redémarrer la transaction"];

        return new QueryException('mysql', 'select * from `products` where `id` = ? for update', [], $pdo);
    }

    /**
     * L'encaissement (dernier effet de la vente) lève ces exceptions, dans l'ordre, puis fait son vrai travail ; `null`
     * dans la liste : cet appel-là passe.
     */
    private function encaissementQuiEchoue(?\Throwable ...$erreurs): object
    {
        $double = new class(app(CreditTreasuryForSaleAction::class), $erreurs) extends CreditTreasuryForSaleAction
        {
            public int $appels = 0;

            public function __construct(private CreditTreasuryForSaleAction $reelle, private array $erreurs) {}

            public function execute(Sale $sale): ?TreasuryAccount
            {
                $this->appels++;
                $erreur = array_shift($this->erreurs);
                if ($erreur !== null) {
                    throw $erreur;
                }

                return $this->reelle->execute($sale);
            }
        };
        $this->app->instance(CreditTreasuryForSaleAction::class, $double);

        return $double;
    }

    private function caisseAvecPanier()
    {
        return Livewire::test(PosInterface::class)
            ->call('selectProduct', $this->poulet->id)
            ->set('weightQty', 2)
            ->set('weightPrice', 7_000)
            ->set('weightLotId', $this->bande->id)
            ->call('confirmWeightAdd')
            ->set('paymentMode', 'especes')
            ->set('cashReceived', 7_000);
    }

    /** Un toast de ce type contenant cet extrait, parmi TOUS ceux du dernier appel (`assertDispatched` ne lit que le premier). */
    private function toast($composant, string $type, string $extrait): void
    {
        $toasts = collect(data_get($composant->effects, 'dispatches'))->where('name', 'toast')->pluck('params');
        $this->assertTrue(
            $toasts->contains(fn (array $p) => $p['type'] === $type && str_contains($p['message'], $extrait)),
            "Toast {$type} « {$extrait} » absent : ".json_encode($toasts->all(), JSON_UNESCAPED_UNICODE),
        );
    }

    /** Une vente de 2 poulets, et rien d'autre : chaque effet écrit UNE fois. */
    private function assertUneSeuleVente(): Sale
    {
        $this->assertSame(1, Sale::count(), 'une seule vente');
        $this->assertSame(1, SaleLine::count(), 'une seule ligne');
        $this->assertSame(1, StockMovement::where('product_id', $this->poulet->id)->count(), 'un seul mouvement de stock');
        $this->assertEquals(48, (float) $this->poulet->fresh()->stock_qty, 'stock 50 − 2, une fois');
        $this->assertSame(1, AccountingEntry::where('source_type', 'sale')->count(), 'une seule écriture');
        $this->assertEquals(7_000, (float) TreasuryAccount::where('account_code', '531')->value('balance'), 'caisse créditée une fois');
        $fiche = LivestockDailyEntry::where('lot_id', $this->bande->id)->sole();
        $this->assertSame(2, (int) $fiche->vente, 'la fiche du jour compte la vente une fois');
        $this->assertSame(298, (int) $this->bande->fresh()->current_quantity);

        return Sale::sole();
    }

    private function assertRienEcrit(): void
    {
        $this->assertSame(0, Sale::count());
        $this->assertSame(0, SaleLine::count());
        $this->assertSame(0, StockMovement::count());
        $this->assertEquals(50, (float) $this->poulet->fresh()->stock_qty);
        $this->assertSame(0, AccountingEntry::count());
        $this->assertEquals(0, (float) TreasuryAccount::where('account_code', '531')->value('balance'));
        $this->assertSame(0, LivestockDailyEntry::count());
        $this->assertSame(300, (int) $this->bande->fresh()->current_quantity);
    }

    // ═══ 1. La vente du web est rejouée ═══

    /** 🔴 Un interblocage au dernier effet : la vente passe au second essai, chaque effet écrit une fois, une facture. */
    public function test_un_interblocage_pendant_la_vente_web_est_rejoue_sans_rien_doubler(): void
    {
        $encaissement = $this->encaissementQuiEchoue(self::interblocage());

        $caisse = $this->caisseAvecPanier()->call('validateSale');

        $this->assertSame(2, $encaissement->appels, 'la vente a été rejouée une fois');
        $vente = $this->assertUneSeuleVente();
        $this->assertSame(1, $this->mecef->appels, 'une seule facture MeCeF');
        $this->assertSame('transmise', $vente->mecef_status);
        $this->toast($caisse, 'success', 'Vente enregistree avec succes');
        $caisse->assertSet('cart', []);
    }

    /** 🔴 Deux échecs (interblocage, puis attente de verrou d'un serveur en français) : la vente passe au troisième. */
    public function test_deux_interblocages_dont_une_attente_de_verrou_en_francais_la_vente_passe(): void
    {
        $encaissement = $this->encaissementQuiEchoue(self::interblocage(), self::attenteDeVerrou());

        $this->caisseAvecPanier()->call('validateSale');

        $this->assertSame(3, $encaissement->appels);
        $this->assertUneSeuleVente();
        $this->assertSame(1, $this->mecef->appels);
    }

    /** 🔴 Trois interblocages : rien n'est écrit, aucune facture, message clair, le panier est gardé pour revalider. */
    public function test_trois_interblocages_rien_n_est_ecrit_et_la_caissiere_le_sait(): void
    {
        $this->encaissementQuiEchoue(self::interblocage(), self::interblocage(), self::interblocage());

        $caisse = $this->caisseAvecPanier()->call('validateSale');

        $this->assertRienEcrit();
        $this->assertSame(0, $this->mecef->appels, 'aucune facture pour une vente non enregistrée');
        $this->toast($caisse, 'error', "rien n'a été enregistré");
        $this->toast($caisse, 'error', 'Le panier est conservé');
        $this->assertCount(1, $caisse->get('cart'), 'le panier reste à revalider');

        // La caissière revalide, l'interblocage est passé : UNE vente.
        $caisse->call('validateSale');
        $this->assertUneSeuleVente();
        $this->assertSame(1, $this->mecef->appels);
    }

    /** Une autre erreur n'est jamais rejouée : elle remonte entière, au premier essai, et rien n'est écrit. */
    public function test_une_autre_erreur_n_est_pas_rejouee(): void
    {
        $encaissement = $this->encaissementQuiEchoue(new \RuntimeException('panne qui n\'est pas un interblocage'));

        try {
            $this->caisseAvecPanier()->call('validateSale');
            $this->fail('l\'erreur aurait dû remonter');
        } catch (\RuntimeException $e) {
            $this->assertSame('panne qui n\'est pas un interblocage', $e->getMessage());
        }

        $this->assertSame(1, $encaissement->appels, 'jamais rejouée');
        $this->assertRienEcrit();
        $this->assertSame(0, $this->mecef->appels);
    }

    /**
     * 🔴 L'appel MeCeF se fait APRÈS la validation de la transaction de vente : la seule transaction ouverte est alors
     * la courte transaction de facturation (la vente relue sous verrou). Dans la transaction de vente, il serait un
     * niveau plus bas — et refait à chaque essai rejoué.
     */
    public function test_la_facture_mecef_part_apres_la_transaction_de_vente(): void
    {
        $this->caisseAvecPanier()->call('validateSale');

        $this->assertSame([$this->niveauDeBase + 1], $this->mecef->niveaux,
            'appelé dans la transaction de vente, le dispositif recevrait une seconde facture à chaque essai rejoué');
    }

    // ═══ 2. Un échec MeCeF ne défait pas la vente ═══

    /** 🔴 MeCeF en échec : la vente reste, « Erreur MeCeF », à retransmettre ; la retransmission ne double jamais. */
    public function test_un_echec_mecef_garde_la_vente_a_facturer_et_la_retransmission_ne_double_pas(): void
    {
        $this->mecef->reponses = [false];

        $caisse = $this->caisseAvecPanier()->call('validateSale');

        $vente = $this->assertUneSeuleVente();
        $this->assertSame('erreur', $vente->mecef_status, 'à facturer : « Erreur MeCeF » à l\'écran Facturation');
        $this->assertNull($vente->mecef_qr_ref);
        $this->toast($caisse, 'warning', 'facture normalisée MeCeF non transmise');
        $this->toast($caisse, 'warning', 'retransmettez-la depuis Facturation & MeCeF');
        $caisse->assertSet('cart', []);

        // Retransmission depuis Facturation : transmise.
        Livewire::test(Facturation::class)->call('retryMecef', $vente->id)
            ->assertDispatched('toast', fn ($n, $p) => $p['type'] === 'success');
        $this->assertSame('transmise', $vente->fresh()->mecef_status);
        $this->assertSame(2, $this->mecef->appels);

        // Un second clic (page restée ouverte) : aucune seconde facture.
        Livewire::test(Facturation::class)->call('retryMecef', $vente->id)
            ->assertDispatched('toast', fn ($n, $p) => $p['type'] === 'warning' && str_contains($p['message'], 'déjà transmise'));
        $this->assertSame(2, $this->mecef->appels, 'une vente déjà facturée ne l\'est pas deux fois');
        $this->assertSame('NIM-ESSAI|2', $vente->fresh()->mecef_qr_ref);
    }

    /** Le dispositif lève une exception (réseau coupé) : traité comme un échec de transmission, la vente reste. */
    public function test_une_exception_du_dispositif_mecef_ne_defait_pas_la_vente(): void
    {
        $this->mecef->reponses = [new \RuntimeException('connexion refusée')];

        $caisse = $this->caisseAvecPanier()->call('validateSale');

        $vente = $this->assertUneSeuleVente();
        $this->assertSame('erreur', $vente->mecef_status);
        $this->toast($caisse, 'warning', 'connexion refusée');
    }

    /** Le service de facturation est idempotent : une vente transmise n'est jamais retransmise. */
    public function test_facturer_deux_fois_une_vente_ne_la_transmet_qu_une_fois(): void
    {
        $this->caisseAvecPanier()->call('validateSale');
        $vente = Sale::sole();

        $resultat = app(FacturationMecefService::class)->facturer($vente->id);

        $this->assertTrue($resultat['deja']);
        $this->assertSame(1, $this->mecef->appels);
    }

    /**
     * Deux retransmissions SIMULTANÉES (deux onglets, la caisse et l'écran Facturation) : la seconde doit attendre la
     * première et voir `transmise`. SQLite sérialise tout et ne peut pas le montrer : ce garde-fou lit le code — la
     * vente est relue SOUS VERROU avant le contrôle « déjà transmise ».
     */
    public function test_la_vente_est_relue_sous_verrou_avant_le_controle_deja_transmise(): void
    {
        $source = (string) file_get_contents(app_path('Services/Mecef/FacturationMecefService.php'));
        $controle = strpos($source, "if (\$sale->mecef_status === 'transmise')");
        $this->assertNotFalse($controle, 'le contrôle « déjà transmise » a disparu');
        $this->assertStringContainsString('->lockForUpdate()', substr($source, 0, $controle),
            'sans verrou, deux retransmissions simultanées liraient toutes deux « erreur » et factureraient deux fois');
    }

    // ═══ 3. Le même service pour l'envoi des postes ═══

    /**
     * 🔴 Deux ventes dans un envoi ; l'encaissement de la SECONDE s'interbloque. L'envoi est rejoué entier et passe ;
     * chaque vente a UNE facture. Quand l'appel MeCeF était dans la transaction de l'envoi, la première vente était
     * transmise à l'essai annulé PUIS à l'essai suivant : deux factures pour une vente.
     */
    public function test_l_envoi_d_un_poste_rejoue_ne_facture_qu_une_fois_chaque_vente(): void
    {
        $encaissement = $this->encaissementQuiEchoue(null, self::interblocage());
        $ids = ['a1111111-1111-4111-8111-111111111111', 'a3333333-3333-4333-8333-333333333333'];

        $this->actingAs(User::where('username', 'caisse')->sole(), 'sanctum')->postJson('/api/sync/push', ['sales' => array_map(fn ($id) => [
            'id' => $id, 'payment_mode' => 'especes', 'status' => 'validee',
            'subtotal' => 3_500, 'discount' => 0, 'total' => 3_500, 'sold_at' => self::JOUR.' 10:00:00',
            'lines' => [['product_id' => $this->poulet->id, 'lot_id' => $this->bande->id, 'qty' => 1, 'unit_price' => 3_500, 'manual_total_amount' => 3_500]],
        ], $ids)])->assertOk()->assertJsonPath('sales.accepted', $ids);

        $this->assertSame(4, $encaissement->appels, 'essai 1 : vente 1 puis interblocage ; essai 2 : les deux ventes');
        $this->assertSame(2, Sale::count());
        $this->assertSame(2, StockMovement::where('product_id', $this->poulet->id)->count());
        $this->assertEquals(48, (float) $this->poulet->fresh()->stock_qty);
        $this->assertSame(2, AccountingEntry::where('source_type', 'sale')->count());
        $this->assertEquals(7_000, (float) TreasuryAccount::where('account_code', '531')->value('balance'));
        $this->assertSame(2, (int) LivestockDailyEntry::where('lot_id', $this->bande->id)->sole()->vente);
        $this->assertSame(2, $this->mecef->appels, 'une seule facture MeCeF par vente reçue');
        $this->assertSame([$this->niveauDeBase + 1, $this->niveauDeBase + 1], $this->mecef->niveaux,
            'facturées après la transaction de l\'envoi, chacune dans sa courte transaction');
        $this->assertSame(['transmise', 'transmise'], Sale::orderBy('id')->pluck('mecef_status')->all());
    }

    /** Envoi interbloqué trois fois : 500, rien d'écrit, aucune facture — le poste renverra. */
    public function test_l_envoi_d_un_poste_trois_fois_interbloque_n_ecrit_rien(): void
    {
        $this->encaissementQuiEchoue(self::interblocage(), self::interblocage(), self::interblocage());

        $this->actingAs(User::where('username', 'caisse')->sole(), 'sanctum')->postJson('/api/sync/push', ['sales' => [[
            'id' => 'a2222222-2222-4222-8222-222222222222', 'payment_mode' => 'especes', 'status' => 'validee',
            'subtotal' => 7_000, 'discount' => 0, 'total' => 7_000, 'sold_at' => self::JOUR.' 10:00:00',
            'lines' => [['product_id' => $this->poulet->id, 'lot_id' => $this->bande->id, 'qty' => 2, 'unit_price' => 3_500, 'manual_total_amount' => 7_000]],
        ]]])->assertStatus(500);

        $this->assertRienEcrit();
        $this->assertSame(0, $this->mecef->appels);
    }

    // ═══ 4. Le service lui-même ═══

    /**
     * ⚠️ Jamais rejouée DANS une autre transaction : MariaDB annule alors l'englobante entière, rejouer la seule partie
     * interne écrirait hors transaction. L'interblocage remonte au premier essai.
     */
    public function test_une_transaction_imbriquee_n_est_jamais_rejouee(): void
    {
        $essais = 0;

        try {
            DB::transaction(function () use (&$essais) {
                app(TransactionRejouable::class)->executer(function () use (&$essais) {
                    $essais++;
                    throw self::interblocage();
                }, 'essai imbriqué');
            });
            $this->fail('l\'interblocage aurait dû remonter');
        } catch (QueryException|\Illuminate\Database\DeadlockException) {
        }

        $this->assertSame(1, $essais);
    }

    /** Un interblocage ENVELOPPÉ par une action (rendu comme sa propre exception, l'erreur de la base en cause) est rejoué. */
    public function test_un_interblocage_enveloppe_est_reconnu_et_rejoue(): void
    {
        $essais = 0;

        $resultat = app(TransactionRejouable::class)->executer(function () use (&$essais) {
            if (++$essais === 1) {
                throw new \RuntimeException('Écriture de la fiche impossible.', 0, self::attenteDeVerrou());
            }

            return 'fait';
        }, 'essai');

        $this->assertSame('fait', $resultat);
        $this->assertSame(2, $essais);
    }

    /** Trois essais au plus, puis l'exception au message rédigé pour l'utilisateur, l'erreur de la base gardée. */
    public function test_apres_trois_essais_l_exception_est_claire(): void
    {
        $essais = 0;

        try {
            app(TransactionRejouable::class)->executer(function () use (&$essais) {
                $essais++;
                throw self::interblocage();
            }, 'essai');
            $this->fail('l\'interblocage aurait dû remonter');
        } catch (TransactionInterbloqueeException $e) {
            $this->assertSame(3, $essais);
            $this->assertSame(TransactionRejouable::ESSAIS, $e->essais);
            $this->assertStringContainsString("rien n'a été enregistré", $e->getMessage());
            $this->assertInstanceOf(QueryException::class, $e->getPrevious());
        }
    }
}
