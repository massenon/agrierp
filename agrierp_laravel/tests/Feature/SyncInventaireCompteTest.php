<?php

namespace Tests\Feature;

use App\Actions\AdjustStockAction;
use App\Models\AccountingEntry;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\StockMovement;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Ticket S-T10 — L'INVENTAIRE DU POSTE : L'ÉCART EST CALCULÉ PAR LE SERVEUR, À L'INSTANT DU COMPTAGE.
 *
 * Le poste envoyait un ÉCART contre son stock LOCAL ; une vente faite au web (ou sur une autre caisse) et pas encore
 * descendue au poste rendait ce stock trop haut, et le serveur décomptait la vente deux fois — sans erreur, avec une
 * perte fictive au journal. Désormais le poste envoie la QUANTITÉ COMPTÉE et l'INSTANT du comptage (`counted_quantity`,
 * `counted_at`), et le serveur applique la règle du web (écart = compté − stock du serveur) contre son grand livre à
 * cet instant. Un poste ancien, qui n'envoie que l'écart, garde l'ancien comportement.
 *
 * Toutes les valeurs attendues sont calculées à la main dans les commentaires.
 */
class SyncInventaireCompteTest extends TestCase
{
    use RefreshDatabase;

    private Product $produit;

    private User $utilisateur;

    protected function setUp(): void
    {
        parent::setUp();

        // Le serveur de la ferme tourne à l'heure du Bénin (ticket 14.71) — posé ici, quel que soit le `.env`.
        config(['app.timezone' => 'Africa/Porto-Novo']);
        date_default_timezone_set('Africa/Porto-Novo');
        Carbon::setTestNow('2026-10-19 08:00:00');

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $this->utilisateur = User::create([
            'name' => 'Administrateur', 'username' => 'admin', 'email' => 'dg@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->utilisateur->assignRole('admin');

        FiscalYear::create([
            'year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert',
        ]);
        foreach ([['601', "Achats d'aliments", 6], ['657', 'Pertes sur stocks', 6]] as [$code, $libelle, $classe]) {
            ChartOfAccount::firstOrCreate(['code' => $code], ['label' => $libelle, 'class' => $classe, 'is_active' => true]);
        }

        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);
        $this->produit = Product::create([
            'sku' => 'ALI-001', 'name' => 'Provende ponte', 'category_id' => $categorie->id, 'unit' => 'sac',
            'pricing_mode' => 'fourchette', 'tva_rate' => 0, 'stock_qty' => 100, 'is_active' => true,
        ]);

        // PMP = 18 000 F (une ligne d'achat de 100 sacs à 18 000 F).
        $fournisseur = \App\Models\Supplier::create(['name' => 'Provenderie du Sud', 'phone' => '97000010', 'is_active' => true]);
        $achat = \App\Models\Purchase::create([
            'supplier_id' => $fournisseur->id, 'payment_mode' => 'especes', 'total' => 1800000, 'purchase_date' => '2026-10-01',
        ]);
        \App\Models\PurchaseLine::create(['purchase_id' => $achat->id, 'product_id' => $this->produit->id, 'qty' => 100, 'unit_price' => 18000]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    /** Une vente au web à l'heure dite : le mouvement que `PosInterface` écrit (`AdjustStockAction`, `sold_at`). */
    private function venteAuWeb(string $heure, float $quantite): void
    {
        Carbon::setTestNow('2026-10-19 '.$heure);
        app(AdjustStockAction::class)->execute($this->produit->fresh(), -$quantite, 'sale', (string) Str::uuid(), now());
    }

    /** L'envoi d'un poste : écart LOCAL (`type`, `quantity`) et, pour un poste S-T10, le comptage daté. */
    private function pousser(string $type, float $quantite, ?float $compte = null, ?string $compteLe = null, string $ref = 'inv-1')
    {
        $ligne = [
            'client_ref' => $ref,
            'product_id' => $this->produit->id,
            'type' => $type,
            'quantity' => $quantite,
            'reference_type' => 'inventaire',
            'reason' => 'Vol / Disparition',
            'movement_date' => '2026-10-19',
        ];
        if ($compte !== null) {
            $ligne['counted_quantity'] = $compte;
            $ligne['counted_at'] = $compteLe;
        }

        return $this->actingAs($this->utilisateur, 'sanctum')
            ->postJson('/api/sync/push', ['device_id' => 'poste-test', 'stock_adjustments' => [$ligne]])
            ->assertOk();
    }

    private function stock(): float
    {
        return (float) $this->produit->fresh()->stock_qty;
    }

    private function pertes(): float
    {
        return (float) AccountingEntry::with('lines')->get()->sum(fn ($e) => $e->lines->sum('debit'));
    }

    /**
     * ⚠️⚠️ LE CAS DU TICKET. 08h00 : le poste a tiré 100 sacs. 10h00 : le web vend 3 sacs (serveur : 97), pas encore
     * descendus au poste. 10h30 : le poste compte 95 sacs (2 ont réellement disparu) ; son stock local dit encore
     * 100, son écart local est donc −5. 11h00 : envoi.
     *
     * Attendu (à la main) : stock du serveur à 10h30 = 97 ; écart = 95 − 97 = −2 ; stock final = 95 ; perte au
     * journal = 2 × 18 000 = 36 000 F. L'ancien comportement donnait 97 − 5 = 92 (la vente décomptée deux fois) et
     * une perte de 90 000 F.
     */
    public function test_une_vente_au_web_non_descendue_au_poste_n_est_pas_decomptee_deux_fois(): void
    {
        $this->venteAuWeb('10:00:00', 3);
        $this->assertSame(97.0, $this->stock());

        Carbon::setTestNow('2026-10-19 11:00:00');
        $this->pousser('sortie', 5, 95, '2026-10-19T10:30:00+01:00')
            ->assertJsonPath('stock_adjustments.accepted.0', 'inv-1');

        $this->assertSame(95.0, $this->stock(), 'le stock final est le comptage : la vente du web ne compte qu\'une fois');
        $mouvement = StockMovement::where('reference_id', 'inv-1')->sole();
        $this->assertSame('sortie', $mouvement->type);
        $this->assertSame(2.0, (float) $mouvement->quantity, 'écart du SERVEUR : 95 − 97');
        $this->assertSame('2026-10-19 10:30:00', $mouvement->movement_date->format('Y-m-d H:i:s'), 'daté de l\'instant du comptage');
        $this->assertSame(36000.0, $this->pertes(), 'la perte est celle des 2 sacs disparus, pas des 3 vendus');
    }

    /**
     * Comptage ANTÉRIEUR à des mouvements déjà au serveur. 09h00 : le poste compte 95 (5 disparus contre les 100 du
     * serveur à ce moment). 10h00 : le web vend 3 sacs. 11h00 : envoi (écart local −5).
     *
     * Attendu : stock à 09h00 = stock courant 97 − (mouvements après 09h00 : −3) = 100 ; écart = 95 − 100 = −5 ;
     * stock final = 97 − 5 = 92 — la vente de 10h00, postérieure, compte une fois par-dessus le comptage
     * (95 − 3 = 92) ; perte 5 × 18 000 = 90 000 F.
     */
    public function test_un_comptage_anterieur_a_des_mouvements_deja_au_serveur_ne_les_efface_pas(): void
    {
        $this->venteAuWeb('10:00:00', 3);

        Carbon::setTestNow('2026-10-19 11:00:00');
        $this->pousser('sortie', 5, 95, '2026-10-19T09:00:00+01:00');

        $this->assertSame(92.0, $this->stock(), 'comptage 95, puis la vente de 10h00 (−3), une seule fois');
        $this->assertSame(5.0, (float) StockMovement::where('reference_id', 'inv-1')->sole()->quantity);
        $this->assertSame(90000.0, $this->pertes());
    }

    /**
     * ⚠️ L'INSTANT VOYAGE AVEC SON FUSEAU. 09h30 UTC = 10h30 au Bénin : la vente de 10h00 (heure du Bénin) PRÉCÈDE
     * le comptage. Lu comme une heure murale (« 09:30 »), il la placerait après, et le stock final serait 92 au lieu
     * de 95.
     */
    public function test_un_instant_envoye_en_utc_est_ramene_a_l_heure_du_serveur(): void
    {
        $this->venteAuWeb('10:00:00', 3);

        Carbon::setTestNow('2026-10-19 11:00:00');
        $this->pousser('sortie', 5, 95, '2026-10-19T09:30:00Z');

        $this->assertSame(95.0, $this->stock());
        $this->assertSame('2026-10-19 10:30:00', StockMovement::where('reference_id', 'inv-1')->sole()->movement_date->format('Y-m-d H:i:s'));
    }

    /**
     * Poste ancien (avant S-T10) : il n'envoie que l'écart local. Le serveur l'applique comme avant, à la réception —
     * le défaut reste donc entier pour lui (97 − 5 = 92) : c'est pourquoi le serveur se déploie d'abord, puis les
     * postes.
     */
    public function test_un_poste_ancien_garde_l_ancien_comportement(): void
    {
        $this->venteAuWeb('10:00:00', 3);

        Carbon::setTestNow('2026-10-19 11:00:00');
        $this->pousser('sortie', 5)->assertJsonPath('stock_adjustments.accepted.0', 'inv-1');

        $this->assertSame(92.0, $this->stock());
        $mouvement = StockMovement::where('reference_id', 'inv-1')->sole();
        $this->assertSame(5.0, (float) $mouvement->quantity);
        $this->assertSame('2026-10-19 11:00:00', $mouvement->movement_date->format('Y-m-d H:i:s'), 'daté de la réception');
    }

    /**
     * Aucun écart au serveur (le « manquant » du poste n'était que la vente du web) : acquitté sans mouvement ni
     * écriture, comme le web qui répond « Aucun écart détecté » ; le renvoi n'y change rien.
     */
    public function test_sans_ecart_au_serveur_rien_n_est_ecrit_et_le_renvoi_est_inoffensif(): void
    {
        $this->venteAuWeb('10:00:00', 3);

        Carbon::setTestNow('2026-10-19 11:00:00');
        $this->pousser('sortie', 3, 97, '2026-10-19T10:30:00+01:00')->assertJsonPath('stock_adjustments.accepted.0', 'inv-1');
        $this->pousser('sortie', 3, 97, '2026-10-19T10:30:00+01:00')->assertJsonPath('stock_adjustments.accepted.0', 'inv-1');

        $this->assertSame(97.0, $this->stock());
        $this->assertSame(0, StockMovement::where('reference_id', 'inv-1')->count());
        $this->assertSame(0.0, $this->pertes());
        $this->assertSame(2, AuditLog::where('action', 'stock.inventaire_sans_ecart')->count());
    }

    /** Le renvoi d'un comptage déjà appliqué (accusé perdu) ne rejoue rien, même si le stock a bougé entre-temps. */
    public function test_le_renvoi_d_un_comptage_applique_ne_rejoue_rien(): void
    {
        Carbon::setTestNow('2026-10-19 11:00:00');
        $this->pousser('sortie', 5, 95, '2026-10-19T10:30:00+01:00');
        $this->venteAuWeb('11:30:00', 1);
        Carbon::setTestNow('2026-10-19 12:00:00');
        $this->pousser('sortie', 5, 95, '2026-10-19T10:30:00+01:00')->assertJsonPath('stock_adjustments.accepted.0', 'inv-1');

        $this->assertSame(94.0, $this->stock(), '100 → 95 (comptage) → 94 (vente) ; rien de plus');
        $this->assertSame(1, StockMovement::where('reference_id', 'inv-1')->count());
    }

    /**
     * Un comptage DÉPASSÉ : le web a fait son propre inventaire à 10h00 (il trouve 90), le comptage du poste de 09h00
     * arrive à 11h00. Le plus récent fait foi : stock 90, rien d'appliqué pour le poste (l'appliquer donnerait
     * 90 + (95 − 100) = 85).
     */
    public function test_un_comptage_remplace_par_un_inventaire_plus_recent_n_a_plus_d_effet(): void
    {
        Carbon::setTestNow('2026-10-19 10:00:00');
        app(AdjustStockAction::class)->execute($this->produit->fresh(), -10, 'adjustment', null, now(), 'Inventaire web');

        Carbon::setTestNow('2026-10-19 11:00:00');
        $this->pousser('sortie', 5, 95, '2026-10-19T09:00:00+01:00')->assertJsonPath('stock_adjustments.accepted.0', 'inv-1');

        $this->assertSame(90.0, $this->stock());
        $this->assertSame(0, StockMovement::where('reference_id', 'inv-1')->count());
        $this->assertSame(1, AuditLog::where('action', 'stock.inventaire_depasse')->count());
    }

    /**
     * Excédent au serveur alors que le poste croyait à un manquant : le web a vendu 8 sacs, le poste (resté à 100)
     * en compte 95 → localement −5 ; au serveur 95 − 92 = +3. L'excédent est régularisé en stock, SANS écriture
     * (un excédent n'est jamais un profit, 14.41).
     */
    public function test_le_sens_de_l_ecart_est_celui_du_serveur(): void
    {
        $this->venteAuWeb('10:00:00', 8);

        Carbon::setTestNow('2026-10-19 11:00:00');
        $this->pousser('sortie', 5, 95, '2026-10-19T10:30:00+01:00');

        $this->assertSame(95.0, $this->stock());
        $mouvement = StockMovement::where('reference_id', 'inv-1')->sole();
        $this->assertSame('entree', $mouvement->type);
        $this->assertSame(3.0, (float) $mouvement->quantity);
        $this->assertSame(0.0, $this->pertes());
    }

    /**
     * ⚠️ Un mouvement daté du seul JOUR (« Ajouter Stock » du web : minuit du jour choisi) le jour même du comptage est
     * placé par son heure d'ENREGISTREMENT. 10h30 : le poste compte 95 (5 disparus). 14h00 : le web entre 30 sacs datés
     * du 19. 15h00 : l'inventaire arrive.
     *
     * Attendu : l'ajout suit le comptage → stock à 10h30 = 130 − 30 = 100 ; écart −5 ; final 125. Placé par sa seule
     * date (minuit ≤ 10h30), il aurait été compté AVANT : écart 95 − 130 = −35, final 95 — 30 sacs perdus.
     */
    public function test_un_ajout_date_du_jour_saisi_apres_le_comptage_le_suit(): void
    {
        Carbon::setTestNow('2026-10-19 14:00:00');
        app(AdjustStockAction::class)->execute($this->produit->fresh(), 30, 'manual_addition', null, Carbon::parse('2026-10-19'));

        Carbon::setTestNow('2026-10-19 15:00:00');
        $this->pousser('sortie', 5, 95, '2026-10-19T10:30:00+01:00');

        $this->assertSame(125.0, $this->stock());
        $this->assertSame(5.0, (float) StockMovement::where('reference_id', 'inv-1')->sole()->quantity);
    }

    /** Le même ajout saisi à 09h00, AVANT le comptage de 10h30 : le comptage le reflétait (130 − 35 = 95). */
    public function test_un_ajout_date_du_jour_saisi_avant_le_comptage_le_precede(): void
    {
        Carbon::setTestNow('2026-10-19 09:00:00');
        app(AdjustStockAction::class)->execute($this->produit->fresh(), 30, 'manual_addition', null, Carbon::parse('2026-10-19'));

        Carbon::setTestNow('2026-10-19 15:00:00');
        $this->pousser('sortie', 5, 95, '2026-10-19T10:30:00+01:00');

        $this->assertSame(95.0, $this->stock());
        $this->assertSame(35.0, (float) StockMovement::where('reference_id', 'inv-1')->sole()->quantity);
    }

    /** Une horloge de poste EN AVANCE ne place pas le comptage après des ventes qui l'ont suivi : borné à la réception. */
    public function test_un_instant_dans_le_futur_est_borne_a_la_reception(): void
    {
        Carbon::setTestNow('2026-10-19 11:00:00');
        $this->pousser('sortie', 5, 95, '2026-10-19T15:00:00+01:00');

        $this->assertSame('2026-10-19 11:00:00', StockMovement::where('reference_id', 'inv-1')->sole()->movement_date->format('Y-m-d H:i:s'));
        $this->assertSame(95.0, $this->stock());
    }

    /** La quantité comptée sans son instant est refusée avec un motif (jamais devinée), sous l'identifiant du poste. */
    public function test_une_quantite_comptee_sans_instant_est_refusee(): void
    {
        $reponse = $this->pousser('sortie', 5, 95, null);

        $this->assertSame([], $reponse->json('stock_adjustments.accepted'));
        $this->assertSame('inv-1', $reponse->json('stock_adjustments.rejected.0.client_ref'));
        // Trouvé par l'essai à plusieurs postes : le poste range un refus sous `id` (comme toute autre table) ; sans
        // lui, l'inventaire refusé restait en attente au poste, renvoyé à chaque synchronisation, motif jamais vu.
        $this->assertSame('inv-1', $reponse->json('stock_adjustments.rejected.0.id'));
        $this->assertStringContainsString('instant du comptage', $reponse->json('stock_adjustments.rejected.0.reason'), 'motif en français (U5)');
        $this->assertSame(100.0, $this->stock());
    }
}
