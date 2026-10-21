<?php

namespace Tests\Feature;

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
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Support\MotifsRefusPush;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

/**
 * Ticket 15.38 — VALEURS `null` DANS LE PUSH : REFUS MOTIVÉ OU « CHAMP ABSENT », JAMAIS UN 500.
 *
 * Défaut préexistant (trouvé par l'agent du 15.37) : une règle `nullable` en validation laissait
 * passer un `null` vers une colonne NOT NULL en base -> violation de contrainte NON rattrapée ->
 * HTTP 500 pour TOUT l'envoi (les autres lignes perdues, le poste renvoie indéfiniment).
 *
 * Décision (aucune règle métier inventée) :
 *  - fiches élevage : `achat`, `ne`, `mort`, `vente` (NOT NULL DEFAULT 0) — `null` = « champ ABSENT »
 *    (colonne non réécrite), exactement comme une clé omise ; il ne compte donc pas comme saisie (15.34) ;
 *  - ventes : `discount` (NOT NULL DEFAULT 0) — même traitement ; `subtotal` et `lines.*.unit_price`
 *    (NOT NULL SANS défaut) — l'omission donnait déjà un 500 : refus motivé de CETTE vente.
 *
 * Date figée au 14/10/2026.
 */
class SyncValeursNullTest extends TestCase
{
    use RefreshDatabase;

    private const MDP = 'AgriERP@2026';

    private const FICHE = '44444444-4444-4444-8444-444444444444';

    private const AUTRE_FICHE = '55555555-5555-4555-8555-555555555555';

    private const VENTE = '11111111-1111-4111-8111-111111111111';

    private const AUTRE_VENTE = '22222222-2222-4222-8222-222222222222';

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

        User::create([
            'name' => 'Caissière POS', 'username' => 'caisse', 'email' => 'caisse@fermeolouwachegoun.com',
            'password' => bcrypt(self::MDP), 'is_active' => true,
        ])->assignRole('caissier', 'animalier');

        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);

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

    private function pousser(array $corps)
    {
        return $this->withHeader('Authorization', 'Bearer '.$this->token)->postJson('/api/sync/push', $corps);
    }

    private function fiche(array $en_plus = []): array
    {
        return array_merge([
            'id' => self::FICHE, 'lot_id' => $this->bande->id, 'entry_date' => '2026-10-13',
        ], $en_plus);
    }

    private function autreFiche(): array
    {
        return ['id' => self::AUTRE_FICHE, 'lot_id' => $this->bande->id, 'entry_date' => '2026-10-12', 'mort' => 1];
    }

    private function creerFiche(array $attributs): void
    {
        $fiche = new LivestockDailyEntry;
        $fiche->id = self::FICHE;
        $fiche->fill($attributs + ['lot_id' => $this->bande->id, 'entry_date' => '2026-10-13']);
        $fiche->save();
    }

    private function vente(): array
    {
        return [
            'id' => self::VENTE, 'payment_mode' => 'especes', 'sold_at' => '2026-10-13 09:00:00',
            'subtotal' => 21_000, 'discount' => 0, 'total' => 21_000, 'status' => 'validee',
            'lines' => [[
                'product_id' => $this->poulet->id, 'lot_id' => $this->bande->id,
                'qty' => 6, 'unit_price' => 3_500, 'manual_total_amount' => 21_000,
            ]],
        ];
    }

    private function autreVente(): array
    {
        return ['id' => self::AUTRE_VENTE] + $this->vente();
    }

    // ---- Fiches élevage -----------------------------------------------------------------------

    public static function colonnesNotNull(): array
    {
        return ['achat' => ['achat'], 'ne' => ['ne'], 'mort' => ['mort'], 'vente' => ['vente']];
    }

    #[DataProvider('colonnesNotNull')]
    public function test_fiche_neuve_avec_null_sur_colonne_not_null_est_acceptee_a_zero(string $colonne): void
    {
        $fiche = $this->fiche(['achat' => 1, 'ne' => 3, 'mort' => 1, 'vente' => 1]);
        $fiche[$colonne] = null;

        $reponse = $this->pousser(['livestock_daily_entries' => [$fiche, $this->autreFiche()]]);

        $reponse->assertOk();
        $this->assertContains(self::FICHE, $reponse->json('livestock_daily_entries.accepted'));
        $this->assertContains(self::AUTRE_FICHE, $reponse->json('livestock_daily_entries.accepted'), "les autres fiches de l'envoi passent");
        $this->assertSame([], $reponse->json('livestock_daily_entries.rejected'));
        $this->assertSame(0, (int) LivestockDailyEntry::find(self::FICHE)->{$colonne});
    }

    #[DataProvider('colonnesNotNull')]
    public function test_fiche_existante_avec_null_ne_reecrit_pas_la_colonne(string $colonne): void
    {
        $this->creerFiche(['achat' => 4, 'ne' => 5, 'mort' => 2, 'vente' => 6, 'effectif_final' => 51]);

        $reponse = $this->pousser(['livestock_daily_entries' => [$this->fiche([$colonne => null, 'don' => 1])]]);

        $reponse->assertOk();
        $this->assertSame([self::FICHE], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertSame(['achat' => 4, 'ne' => 5, 'mort' => 2, 'vente' => 6][$colonne], (int) LivestockDailyEntry::find(self::FICHE)->{$colonne});
    }

    /** Une fiche qui ne porte que des null sur les colonnes NOT NULL est « sans colonne de saisie » (15.34). */
    public function test_fiche_inconnue_qui_ne_porte_que_des_null_not_null_est_refusee_comme_reduite(): void
    {
        $reponse = $this->pousser(['livestock_daily_entries' => [
            $this->fiche(['achat' => null, 'ne' => null, 'mort' => null, 'vente' => null]),
            $this->autreFiche(),
        ]])->assertOk();

        $this->assertSame(MotifsRefusPush::ficheReduiteInconnue(), $reponse->json('livestock_daily_entries.rejected.0.reason'));
        $this->assertSame([self::AUTRE_FICHE], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertNull(LivestockDailyEntry::find(self::FICHE));
    }

    /** Un `null` sur une colonne NULLABLE en base reste une valeur explicite et compte comme saisie (15.34 inchangé). */
    public function test_null_sur_colonne_nullable_en_base_reste_une_saisie(): void
    {
        $reponse = $this->pousser(['livestock_daily_entries' => [$this->fiche(['don' => null])]])->assertOk();

        $this->assertSame([self::FICHE], $reponse->json('livestock_daily_entries.accepted'));
    }

    /** Effectif final recalculé par le serveur, un null valant 0 : 50 + 2 - 1 = 51. */
    public function test_effectif_final_recalcule_avec_un_null_vaut_zero(): void
    {
        $this->pousser(['livestock_daily_entries' => [$this->fiche(['achat' => null, 'ne' => 2, 'mort' => 1, 'vente' => null])]])->assertOk();

        $this->assertSame(51, (int) LivestockDailyEntry::find(self::FICHE)->effectif_final);
    }

    /** Mesure exhaustive : AUCUNE colonne du modèle, mise à null, ne fait un 500 (future colonne NOT NULL = test rouge). */
    public function test_aucune_colonne_de_la_fiche_a_null_ne_provoque_un_500(): void
    {
        // Ticket S1 : un envoi par colonne dépasse la limite de 30 appels par minute, sans rapport avec ce test.
        $this->withoutMiddleware(\Illuminate\Routing\Middleware\ThrottleRequests::class);

        $colonnes = array_diff((new LivestockDailyEntry)->getFillable(), ['lot_id', 'entry_date', 'effectif_final']);
        $this->assertNotEmpty($colonnes);

        foreach ($colonnes as $colonne) {
            LivestockDailyEntry::query()->delete();
            $reponse = $this->pousser(['livestock_daily_entries' => [$this->fiche(($colonne === 'symptomes' ? ['mort' => 1] : ['symptomes' => 'RAS']) + [$colonne => null])]]);

            $this->assertSame(200, $reponse->status(), "la colonne {$colonne} à null ne doit pas faire un 500");
            $this->assertSame([], $reponse->json('livestock_daily_entries.rejected'), $colonne);
        }
    }

    /** Fiche complète valide : strictement comme avant (50 + 1 + 2 - 3 - 4 - 5 = 41). */
    public function test_fiche_complete_valide_inchangee(): void
    {
        $this->pousser(['livestock_daily_entries' => [$this->fiche([
            'achat' => 1, 'ne' => 2, 'mort' => 3, 'vente' => 4, 'don' => 5,
        ])]])->assertOk();

        $f = LivestockDailyEntry::find(self::FICHE);
        $this->assertSame([1, 2, 3, 4, 5], [(int) $f->achat, (int) $f->ne, (int) $f->mort, (int) $f->vente, (int) $f->don]);
        $this->assertSame(41, (int) $f->effectif_final);
    }

    // ---- Ventes -------------------------------------------------------------------------------

    public function test_vente_avec_remise_null_est_acceptee_sans_remise(): void
    {
        $v = $this->vente();
        $v['discount'] = null;

        $reponse = $this->pousser(['sales' => [$v]]);

        $reponse->assertOk();
        $this->assertSame([self::VENTE], $reponse->json('sales.accepted'));
        $this->assertSame(0.0, (float) Sale::find(self::VENTE)->discount);
        $this->assertSame(21000.0, (float) Sale::find(self::VENTE)->total);
    }

    public function test_vente_sans_sous_total_est_refusee_avec_motif_et_les_autres_passent(): void
    {
        foreach (['null', 'absent'] as $cas) {
            Sale::query()->delete();
            $v = $this->vente();
            if ($cas === 'null') {
                $v['subtotal'] = null;
            } else {
                unset($v['subtotal']);
            }

            $reponse = $this->pousser(['sales' => [$v, $this->autreVente()]]);

            $reponse->assertOk();
            $this->assertSame([self::AUTRE_VENTE], $reponse->json('sales.accepted'), $cas);
            $this->assertSame(self::VENTE, $reponse->json('sales.rejected.0.id'), $cas);
            $this->assertStringContainsString('sous-total', $reponse->json('sales.rejected.0.reason'));
            $this->assertDoesNotMatchRegularExpression('/\b(The|field|must|SQLSTATE)\b/', $reponse->json('sales.rejected.0.reason'));
            $this->assertNull(Sale::find(self::VENTE));
        }
    }

    public function test_vente_dont_une_ligne_n_a_pas_de_prix_unitaire_est_refusee_avec_motif(): void
    {
        foreach (['null', 'absent'] as $cas) {
            Sale::query()->delete();
            $v = $this->vente();
            if ($cas === 'null') {
                $v['lines'][0]['unit_price'] = null;
            } else {
                unset($v['lines'][0]['unit_price']);
            }

            $reponse = $this->pousser(['sales' => [$v, $this->autreVente()]]);

            $reponse->assertOk();
            $this->assertSame([self::AUTRE_VENTE], $reponse->json('sales.accepted'), $cas);
            $this->assertStringContainsString('prix unitaire', $reponse->json('sales.rejected.0.reason'));
            $this->assertNull(Sale::find(self::VENTE));
        }
    }

    /** `sold_at` null et `lines.*.lot_id` null : déjà tolérés (colonnes nullables en base), inchangés. */
    public function test_sold_at_et_lot_id_null_restent_acceptes(): void
    {
        $v = $this->vente();
        $v['sold_at'] = null;
        $v['lines'][0]['lot_id'] = null;

        $this->assertSame([self::VENTE], $this->pousser(['sales' => [$v]])->assertOk()->json('sales.accepted'));
    }
}
