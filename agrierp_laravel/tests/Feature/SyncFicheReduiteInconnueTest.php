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
use Tests\TestCase;

/**
 * Ticket 15.34 — GARDE-FOU DE `pushDailyEntries` CONTRE LA FICHE VIDE (version minimale).
 *
 * Depuis F0.90, quand une vente est relancée, le poste renvoie la fiche du jour de la vente
 * RÉDUITE à `{id, lot_id, entry_date}` (aucune colonne de saisie) pour ne pas écraser les
 * corrections faites sur le web. Le serveur ne compte alors pas la vente deux fois parce que
 * la fiche (bande, jour) est « acceptée dans le même envoi » (15.30).
 *
 * ⚠️ RISQUE : si cet `id` est INCONNU du serveur (fiche disparue après restauration ou
 * intervention en base), `pushDailyEntries` créait une fiche VIDE, « acceptée » — et la vente
 * du même envoi n'était pas comptée : 0 au lieu de N, sans aucune erreur.
 *
 * Date figée au 14/10/2026.
 */
class SyncFicheReduiteInconnueTest extends TestCase
{
    use RefreshDatabase;

    private const MDP = 'AgriERP@2026';

    private const FICHE = '44444444-4444-4444-8444-444444444444';

    private const VENTE = '11111111-1111-4111-8111-111111111111';

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
            'name' => 'Caissière POS', 'username' => 'caisse', 'email' => 'caisse@olouwachegoun.bj',
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

    private function ficheReduite(array $en_plus = []): array
    {
        return array_merge([
            'id' => self::FICHE, 'lot_id' => $this->bande->id, 'entry_date' => '2026-10-13',
        ], $en_plus);
    }

    private function pousser(array $fiches, array $ventes = [])
    {
        $corps = ['livestock_daily_entries' => $fiches];
        if ($ventes !== []) {
            $corps['sales'] = $ventes;
        }

        return $this->withHeader('Authorization', 'Bearer '.$this->token)->postJson('/api/sync/push', $corps);
    }

    private function creerFiche(array $attributs): void
    {
        $fiche = new LivestockDailyEntry;
        $fiche->id = self::FICHE;
        $fiche->fill($attributs + ['lot_id' => $this->bande->id, 'entry_date' => '2026-10-13']);
        $fiche->save();
    }

    private function saisie(): array
    {
        $colonnes = ['achat', 'ne', 'mort', 'vente', 'don', 'ponte_total', 'ponte_casses', 'feed_qty_kg', 'weight_sample_avg_g'];

        return LivestockDailyEntry::find(self::FICHE)->only(array_merge(['lot_id', 'entry_date'], $colonnes));
    }

    /** Le cas exact du ticket : fiche réduite d'id INCONNU + vente de 6 sujets de la bande, même envoi. */
    public function test_fiche_reduite_d_id_inconnu_est_refusee_et_la_vente_est_comptee(): void
    {
        $reponse = $this->pousser([$this->ficheReduite()], [$this->vente()])->assertOk();

        $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertSame(self::FICHE, $reponse->json('livestock_daily_entries.rejected.0.id'));
        $this->assertSame(
            MotifsRefusPush::ficheReduiteInconnue(),
            $reponse->json('livestock_daily_entries.rejected.0.reason'),
        );

        $this->assertNull(LivestockDailyEntry::find(self::FICHE), 'aucune fiche vide ne doit être créée sous cet id');

        // La vente est comptée normalement, sur la fiche du jour créée PAR LA VENTE.
        $this->assertContains(self::VENTE, $reponse->json('sales.accepted'));
        $fiche = LivestockDailyEntry::where('lot_id', $this->bande->id)->where('entry_date', '2026-10-13')->firstOrFail();
        $this->assertSame(6, (int) $fiche->vente, '0 au lieu de N = vente perdue');
        $this->assertSame(44, (int) $this->bande->fresh()->current_quantity);
        $this->assertSame(1, LivestockDailyEntry::where('lot_id', $this->bande->id)->count());
        $this->assertSame(1, Sale::count());
    }

    /** Seule, sans vente : refusée aussi, rien n'est créé. */
    public function test_fiche_reduite_inconnue_sans_vente_est_refusee_sans_rien_creer(): void
    {
        $reponse = $this->pousser([$this->ficheReduite()])->assertOk();

        $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertCount(1, $reponse->json('livestock_daily_entries.rejected'));
        $this->assertSame(0, LivestockDailyEntry::count());
    }

    /** Le motif est en français, dit pourquoi et ce qu'il faut faire. */
    public function test_le_motif_est_en_francais_et_explicite(): void
    {
        $motif = $this->pousser([$this->ficheReduite()])->json('livestock_daily_entries.rejected.0.reason');

        $this->assertStringContainsString('Fiche refusée', $motif);
        $this->assertStringContainsString('inconnu', $motif);
        $this->assertStringContainsString('Ressaisissez', $motif);
        $this->assertDoesNotMatchRegularExpression('/\b(The|field|must|errors?)\b/', $motif);
    }

    /** Un id CONNU : la fiche réduite est acceptée et RIEN de la saisie n'est écrasé (le trou signalé par F0.90). */
    public function test_fiche_reduite_d_id_connu_n_ecrit_rien(): void
    {
        $this->creerFiche([
            'achat' => 2, 'ne' => 3, 'mort' => 1, 'vente' => 5, 'don' => 1,
            'ponte_total' => 12, 'ponte_casses' => 2, 'feed_qty_kg' => 7.5, 'weight_sample_avg_g' => 1800,
            'effectif_final' => 48,
        ]);
        $avant = $this->saisie();

        $reponse = $this->pousser([$this->ficheReduite()])->assertOk();

        $this->assertSame([self::FICHE], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertSame([], $reponse->json('livestock_daily_entries.rejected'));
        $this->assertEquals($avant, $this->saisie(), 'une fiche réduite ne doit écraser aucune colonne de saisie');
        $this->assertSame(1, LivestockDailyEntry::count());
    }

    /**
     * Id connu + vente du même envoi : la vente est comptée UNE fois, et son renvoi ne double rien.
     *
     * Ticket S-T9 : une fiche réduite ne dispense plus la vente de son incrément. Le cas que F0.90 protégeait — une
     * fiche créée avec la vente d'une vente REFUSÉE du même envoi, puis relancée — n'existe plus : la vente refusée est
     * retirée de la fiche créée (`SyncEssaiMultipostesTest`). Depuis S-T9 le comptoir n'envoie d'ailleurs plus que la
     * fiche réduite d'une fiche déjà synchronisée : l'exempter, c'était ne jamais compter ses ventes.
     */
    public function test_fiche_reduite_connue_avec_vente_ne_double_pas_le_comptage(): void
    {
        $this->creerFiche(['vente' => 0, 'effectif_final' => 50]);

        $reponse = $this->pousser([$this->ficheReduite()], [$this->vente()])->assertOk();
        $this->pousser([$this->ficheReduite()], [$this->vente()])->assertOk();

        $this->assertSame([self::FICHE], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertSame(6, (int) LivestockDailyEntry::find(self::FICHE)->vente);
        $this->assertContains(self::VENTE, $reponse->json('sales.accepted'));
    }

    /** Une fiche COMPLÈTE d'id inconnu est créée comme avant (aucun changement de comportement). */
    public function test_fiche_complete_d_id_inconnu_reste_creee(): void
    {
        $reponse = $this->pousser([$this->ficheReduite(['mort' => 2])])->assertOk();

        $this->assertSame([self::FICHE], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertSame(2, (int) LivestockDailyEntry::find(self::FICHE)->mort);
    }

    /** Une fiche à zéro (saisie réelle « rien à signaler ») n'est PAS une fiche réduite. */
    public function test_fiche_a_zero_d_id_inconnu_reste_creee(): void
    {
        $reponse = $this->pousser([$this->ficheReduite(['achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0])])->assertOk();

        $this->assertSame([self::FICHE], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertNotNull(LivestockDailyEntry::find(self::FICHE));
    }

    /** Une seule colonne de saisie suffit, quelle qu'elle soit (clé présente = saisie). */
    public function test_une_seule_colonne_de_saisie_suffit_a_ne_pas_etre_reduite(): void
    {
        foreach (['ponte_total' => 10, 'ponte_casses' => 1, 'feed_qty_kg' => 3.5, 'weight_sample_avg_g' => 900, 'don' => 1, 'symptomes' => 'toux'] as $colonne => $valeur) {
            LivestockDailyEntry::query()->delete();
            $reponse = $this->pousser([$this->ficheReduite([$colonne => $valeur])])->assertOk();
            $this->assertSame([self::FICHE], $reponse->json('livestock_daily_entries.accepted'), $colonne);
        }
    }

    /** `effectif_final` n'est jamais repris du client : seul, il ne fait pas une saisie. */
    public function test_effectif_final_seul_ne_fait_pas_une_saisie(): void
    {
        $reponse = $this->pousser([$this->ficheReduite(['effectif_final' => 99])])->assertOk();

        $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertSame(0, LivestockDailyEntry::count());
    }

    /** Un refus ne bloque pas les autres fiches du même envoi. */
    public function test_le_refus_n_empeche_pas_les_autres_fiches(): void
    {
        $autre = '55555555-5555-4555-8555-555555555555';
        $reponse = $this->pousser([
            $this->ficheReduite(),
            ['id' => $autre, 'lot_id' => $this->bande->id, 'entry_date' => '2026-10-12', 'mort' => 1],
        ])->assertOk();

        $this->assertSame([$autre], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertSame(self::FICHE, $reponse->json('livestock_daily_entries.rejected.0.id'));
    }

    // ═══════════════ Ticket 15.37 (L11) — ce qui compte comme « colonne de saisie » ═══════════════

    /** `vente` EST une colonne de saisie : une fiche d'id inconnu qui ne porte que `vente` est acceptée comme saisie. */
    public function test_vente_seule_compte_comme_colonne_de_saisie(): void
    {
        // ⚠️ `vente => null` n'est PAS testé : il provoque aujourd'hui une erreur 500 (contrainte NOT NULL de
        // la colonne, la validation `nullable` laisse passer le null). Défaut préexistant, signalé au ticket 15.37,
        // NON corrigé ici (aucun changement de production).
        foreach ([6, 0] as $valeur) {
            LivestockDailyEntry::query()->delete();
            $reponse = $this->pousser([$this->ficheReduite(['vente' => $valeur])])->assertOk();

            $this->assertSame([self::FICHE], $reponse->json('livestock_daily_entries.accepted'), 'vente='.var_export($valeur, true));
            $this->assertSame([], $reponse->json('livestock_daily_entries.rejected'));
        }
    }

    /** Inversement : ni `effectif_final` (même nul ou à zéro), ni `lot_id`, ni `entry_date` ne font une saisie. */
    public function test_identite_et_effectif_final_seuls_ne_comptent_pas_comme_saisie(): void
    {
        foreach ([[], ['effectif_final' => 0], ['effectif_final' => null], ['effectif_final' => 44]] as $en_plus) {
            LivestockDailyEntry::query()->delete();
            $reponse = $this->pousser([$this->ficheReduite($en_plus)])->assertOk();

            $this->assertSame([], $reponse->json('livestock_daily_entries.accepted'), json_encode($en_plus));
            $this->assertSame(self::FICHE, $reponse->json('livestock_daily_entries.rejected.0.id'));
            $this->assertSame(0, LivestockDailyEntry::count());
        }
    }

    /** `vente` + `effectif_final` : c'est `vente` qui fait la saisie ; `effectif_final` reste recalculé, jamais repris. */
    public function test_vente_avec_effectif_final_est_acceptee_sans_reprendre_l_effectif_du_client(): void
    {
        $reponse = $this->pousser([$this->ficheReduite(['vente' => 3, 'effectif_final' => 9999])])->assertOk();

        $this->assertSame([self::FICHE], $reponse->json('livestock_daily_entries.accepted'));
        $this->assertNotSame(9999, (int) LivestockDailyEntry::find(self::FICHE)->effectif_final);
    }
}
