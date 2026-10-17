<?php

namespace Tests\Feature;

use App\Actions\RecordSaleOnFicheElevageAction;
use App\Livewire\Ventes\PosInterface;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\PeriodicClosure;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\Sale;
use App\Models\TreasuryAccount;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.31 — RECALCUL EN CASCADE DES FICHES D'ÉLEVAGE (décision client du
 * 14/10/2026 : OUI, côté serveur).
 *
 * Avant : une vente de sujets vivants datée d'avant des fiches déjà saisies
 * n'était répercutée que sur la fiche DU JOUR DE LA VENTE ; les fiches suivantes
 * gardaient leur effectif d'avant la vente (elles « ne savaient pas » que 6
 * têtes étaient parties), et `livestock_lots.current_quantity` était écrasé par
 * l'effectif de la fiche de la vente — donc par un jour ancien. Aucune erreur :
 * un effectif de bande trop haut, qui fait proposer à la caisse des sujets déjà
 * vendus.
 *
 * Jeu d'essai (bande de 50 sujets, date figée au 14/10/2026) :
 *   12/10  mort 1            → 49
 *   13/10  mort 2            → 47
 *   14/10  achat 3           → 50
 * Vente de 6 sujets le 12/10 (J-2) : 43 → 41 → 44, bande à 44 (la DERNIÈRE fiche).
 */
class VenteDateeCascadeFichesTest extends TestCase
{
    use RefreshDatabase;

    private const MDP = 'AgriERP@2026';

    private const VENTE_A = '11111111-1111-4111-8111-111111111111';

    private const VENTE_B = '22222222-2222-4222-8222-222222222222';

    private Product $poulet;

    private LivestockLot $bande;

    private LivestockLot $autreBande;

    private string $token;

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow('2026-10-14 12:00:00');

        foreach (['view-ventes', 'manage-ventes'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('caissier', 'web')->givePermissionTo(['view-ventes', 'manage-ventes']);
        User::create([
            'name' => 'Caissière POS', 'username' => 'caisse', 'email' => 'caisse@olouwachegoun.bj',
            'password' => bcrypt(self::MDP), 'is_active' => true,
        ])->assignRole('caissier');

        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
        foreach ([['411', 'Clients', 4], ['531', 'Caisse', 5], ['701', 'Ventes de marchandises', 7], ['443', 'TVA collectée', 4]] as [$code, $label, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $classe, 'is_active' => true]);
        }
        TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse Principale', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);

        $espece = LivestockSpecies::create(['label' => 'Aviculture', 'code' => 'AVI', 'is_active' => true]);
        $categorie = ProductCategory::create(['label' => 'Volailles', 'is_active' => true]);
        $this->poulet = Product::create([
            'sku' => 'AVI-001', 'name' => 'Poulet goliath', 'category_id' => $categorie->id,
            'species_id' => $espece->id, 'unit' => 'u', 'pricing_mode' => 'fourchette',
            'price_min' => 3_000, 'price_max' => 4_000, 'tva_rate' => 0, 'stock_qty' => 200, 'is_active' => true,
        ]);
        $this->bande = LivestockLot::create([
            'code' => 'AVI-2026-01', 'species_id' => $espece->id, 'stage' => 'croissance',
            'initial_quantity' => 50, 'current_quantity' => 50, 'created_date' => '2026-01-05', 'status' => 'actif', 'is_active' => true,
        ]);
        $this->autreBande = LivestockLot::create([
            'code' => 'AVI-2026-02', 'species_id' => $espece->id, 'stage' => 'croissance',
            'initial_quantity' => 30, 'current_quantity' => 30, 'created_date' => '2026-01-05', 'status' => 'actif', 'is_active' => true,
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

    /** Fiche saisie à la main, effectif calculé par la formule officielle. */
    private function fiche(LivestockLot $lot, string $jour, array $mouvements = []): LivestockDailyEntry
    {
        $fiche = new LivestockDailyEntry(array_merge(
            ['lot_id' => $lot->id, 'entry_date' => $jour, 'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0],
            $mouvements,
        ));
        $fiche->effectif_final = LivestockDailyEntry::computeEffectifFinal(
            $fiche->previousEffectif(), (int) $fiche->achat, (int) $fiche->ne, (int) $fiche->mort, (int) $fiche->vente, (int) $fiche->don,
        );
        $fiche->save();

        return $fiche;
    }

    /** Trois jours déjà saisis : 49, 47, 50. */
    private function troisJoursSaisis(): void
    {
        $this->fiche($this->bande, '2026-10-12', ['mort' => 1]);
        $this->fiche($this->bande, '2026-10-13', ['mort' => 2]);
        $this->fiche($this->bande, '2026-10-14', ['achat' => 3]);
        $this->bande->update(['current_quantity' => 50]);
    }

    private function vente(string $id, string $soldAt, int $qty = 6, ?LivestockLot $lot = null): array
    {
        return [
            'id' => $id, 'payment_mode' => 'especes', 'subtotal' => $qty * 3_500, 'discount' => 0, 'total' => $qty * 3_500,
            'status' => 'validee', 'sold_at' => $soldAt,
            'lines' => [[
                'product_id' => $this->poulet->id, 'lot_id' => ($lot ?? $this->bande)->id,
                'qty' => $qty, 'unit_price' => 3_500, 'manual_total_amount' => $qty * 3_500,
            ]],
        ];
    }

    private function pousser(array $ventes, array $en_plus = [])
    {
        return $this->withHeader('Authorization', 'Bearer '.$this->token)
            ->postJson('/api/sync/push', array_merge(['sales' => $ventes], $en_plus));
    }

    /** @return array<string, int> jour => effectif_final */
    private function effectifs(?LivestockLot $lot = null): array
    {
        return LivestockDailyEntry::where('lot_id', ($lot ?? $this->bande)->id)->orderBy('entry_date')->get()
            ->mapWithKeys(fn ($f) => [Carbon::parse($f->entry_date)->toDateString() => (int) $f->effectif_final])->all();
    }

    /** Recalcul INDÉPENDANT de la formule d'effectif, à partir des mouvements stockés. */
    private function effectifsAttendus(LivestockLot $lot): array
    {
        $courant = (int) $lot->initial_quantity;
        $attendus = [];
        foreach (LivestockDailyEntry::where('lot_id', $lot->id)->orderBy('entry_date')->get() as $f) {
            $courant = max(0, $courant + $f->achat + $f->ne - ($f->mort + $f->vente + $f->don));
            $attendus[Carbon::parse($f->entry_date)->toDateString()] = $courant;
        }

        return $attendus;
    }

    public function test_une_vente_a_j_moins_2_se_repercute_sur_les_jours_suivants_et_la_bande_suit_la_derniere_fiche(): void
    {
        $this->troisJoursSaisis();

        $this->pousser([$this->vente(self::VENTE_A, '2026-10-12 10:00:00')])->assertOk()->assertJsonPath('sales.accepted.0', self::VENTE_A);

        $this->assertSame(['2026-10-12' => 43, '2026-10-13' => 41, '2026-10-14' => 44], $this->effectifs());
        $this->assertSame(6, (int) LivestockDailyEntry::where('entry_date', '2026-10-12')->value('vente'));
        $this->assertSame(44, (int) $this->bande->fresh()->current_quantity, 'La bande suit la DERNIÈRE fiche (14/10), pas celle du jour de la vente (43).');
        $this->assertSame($this->effectifsAttendus($this->bande), $this->effectifs(), 'Recalcul indépendant identique à ce que stocke le serveur.');
    }

    public function test_les_mouvements_saisis_des_jours_suivants_ne_sont_jamais_modifies(): void
    {
        $this->troisJoursSaisis();

        $this->pousser([$this->vente(self::VENTE_A, '2026-10-12 10:00:00')])->assertOk();

        $suivantes = LivestockDailyEntry::whereIn('entry_date', ['2026-10-13', '2026-10-14'])->orderBy('entry_date')->get();
        $this->assertSame([0, 0], $suivantes->pluck('vente')->map(fn ($v) => (int) $v)->all());
        $this->assertSame([2, 0], $suivantes->pluck('mort')->map(fn ($v) => (int) $v)->all());
        $this->assertSame([0, 3], $suivantes->pluck('achat')->map(fn ($v) => (int) $v)->all());
    }

    public function test_une_vente_un_jour_sans_fiche_cree_la_fiche_et_recalcule_la_suite(): void
    {
        $this->troisJoursSaisis();

        // Le 11/10 : aucune fiche. Départ = effectif initial (50), pas la fiche du 12.
        $this->pousser([$this->vente(self::VENTE_A, '2026-10-11 10:00:00')])->assertOk();

        $this->assertSame(['2026-10-11' => 44, '2026-10-12' => 43, '2026-10-13' => 41, '2026-10-14' => 44], $this->effectifs());
        $this->assertSame(44, (int) $this->bande->fresh()->current_quantity);
    }

    public function test_idempotence_le_meme_envoi_rejoue_donne_le_meme_resultat(): void
    {
        $this->troisJoursSaisis();
        $envoi = [$this->vente(self::VENTE_A, '2026-10-12 10:00:00')];

        $this->pousser($envoi)->assertOk();
        $apresPremier = [$this->effectifs(), (int) $this->bande->fresh()->current_quantity, Sale::count(), LivestockDailyEntry::sum('vente')];

        $deuxieme = $this->pousser($envoi)->assertOk();
        $this->assertSame(self::VENTE_A, $deuxieme->json('sales.accepted.0'), 'Une vente déjà reçue reste acquittée.');

        $this->assertSame($apresPremier, [$this->effectifs(), (int) $this->bande->fresh()->current_quantity, Sale::count(), LivestockDailyEntry::sum('vente')]);
    }

    public function test_le_recalcul_en_cascade_est_idempotent_et_se_repare_seul(): void
    {
        $this->troisJoursSaisis();
        $this->pousser([$this->vente(self::VENTE_A, '2026-10-12 10:00:00')])->assertOk();

        // Corruption volontaire d'une fiche suivante, puis recalcul : retour à la valeur juste, deux fois de suite.
        LivestockDailyEntry::where('entry_date', '2026-10-13')->update(['effectif_final' => 99]);
        $action = app(RecordSaleOnFicheElevageAction::class);
        $action->recalculerEnCascade($this->bande->id, '2026-10-12');
        $unePasse = $this->effectifs();
        $action->recalculerEnCascade($this->bande->id, '2026-10-12');

        $this->assertSame(['2026-10-12' => 43, '2026-10-13' => 41, '2026-10-14' => 44], $unePasse);
        $this->assertSame($unePasse, $this->effectifs());
    }

    public function test_deux_ventes_a_des_dates_differentes_se_cumulent_dans_la_cascade(): void
    {
        $this->troisJoursSaisis();

        $this->pousser([
            $this->vente(self::VENTE_A, '2026-10-12 10:00:00', 6),
            $this->vente(self::VENTE_B, '2026-10-13 10:00:00', 4),
        ])->assertOk();

        // 12/10 : 49-6 = 43 ; 13/10 : 43 - 2 - 4 = 37 ; 14/10 : 37 + 3 = 40
        $this->assertSame(['2026-10-12' => 43, '2026-10-13' => 37, '2026-10-14' => 40], $this->effectifs());
        $this->assertSame(40, (int) $this->bande->fresh()->current_quantity);
        $this->assertSame($this->effectifsAttendus($this->bande), $this->effectifs());
    }

    public function test_une_vente_du_jour_garde_son_comportement(): void
    {
        $this->troisJoursSaisis();

        $this->pousser([$this->vente(self::VENTE_A, '2026-10-14 10:00:00')])->assertOk();

        // 14/10 : 47 + 3 achat - 6 vente = 44 ; rien après, la bande = cette fiche.
        $this->assertSame(['2026-10-12' => 49, '2026-10-13' => 47, '2026-10-14' => 44], $this->effectifs());
        $this->assertSame(44, (int) $this->bande->fresh()->current_quantity);
    }

    public function test_une_vente_sans_fiche_du_tout_cree_la_fiche_du_jour_comme_avant(): void
    {
        $this->pousser([$this->vente(self::VENTE_A, '2026-10-14 10:00:00')])->assertOk();

        $this->assertSame(['2026-10-14' => 44], $this->effectifs());
        $this->assertSame(44, (int) $this->bande->fresh()->current_quantity);
    }

    public function test_la_vente_d_une_bande_ne_touche_pas_une_autre_bande(): void
    {
        $this->troisJoursSaisis();
        $this->fiche($this->autreBande, '2026-10-13', ['mort' => 1]);
        $avant = $this->effectifs($this->autreBande);

        $this->pousser([$this->vente(self::VENTE_A, '2026-10-12 10:00:00')])->assertOk();

        $this->assertSame($avant, $this->effectifs($this->autreBande));
        $this->assertSame(30, (int) $this->autreBande->fresh()->current_quantity);
    }

    public function test_la_fiche_recue_dans_le_meme_envoi_ne_double_pas_la_vente_mais_la_suite_est_recalculee(): void
    {
        $this->fiche($this->bande, '2026-10-13', ['mort' => 2]);
        $this->fiche($this->bande, '2026-10-14', ['achat' => 3]);

        // Le poste envoie SA fiche du 12/10 (qui porte déjà la vente de 6) et la vente.
        $this->pousser(
            [$this->vente(self::VENTE_A, '2026-10-12 10:00:00')],
            ['livestock_daily_entries' => [[
                'id' => '44444444-4444-4444-8444-444444444444', 'lot_id' => $this->bande->id,
                'entry_date' => '2026-10-12', 'vente' => 6,
            ]]],
        )->assertOk();

        $this->assertSame(6, (int) LivestockDailyEntry::where('entry_date', '2026-10-12')->value('vente'), 'N, pas 2N.');
        $this->assertSame(['2026-10-12' => 44, '2026-10-13' => 42, '2026-10-14' => 45], $this->effectifs());
        $this->assertSame(45, (int) $this->bande->fresh()->current_quantity);
    }

    public function test_une_vente_rejetee_ne_touche_ni_les_fiches_ni_la_bande(): void
    {
        $this->troisJoursSaisis();
        PeriodicClosure::create(['period' => '2026-10', 'closed_at' => now()]);
        $avant = $this->effectifs();

        $reponse = $this->pousser([$this->vente(self::VENTE_A, '2026-10-12 10:00:00')])->assertOk();

        $this->assertSame(self::VENTE_A, $reponse->json('sales.rejected.0.id'));
        $this->assertSame($avant, $this->effectifs());
        $this->assertSame(50, (int) $this->bande->fresh()->current_quantity);
    }

    public function test_l_effectif_ne_devient_jamais_negatif_dans_la_cascade(): void
    {
        $this->fiche($this->bande, '2026-10-12', ['mort' => 1]);
        $this->fiche($this->bande, '2026-10-13', ['mort' => 2]);
        $this->bande->update(['current_quantity' => 47]);

        // 48 sujets vendus le 12/10 alors qu'il en restait 49 → 1, puis 13/10 : 1 - 2 → borné à 0.
        $this->pousser([$this->vente(self::VENTE_A, '2026-10-12 10:00:00', 48)])->assertOk();

        $this->assertSame(['2026-10-12' => 1, '2026-10-13' => 0], $this->effectifs());
        $this->assertSame(0, (int) $this->bande->fresh()->current_quantity);
    }

    public function test_l_action_appelee_directement_recalcule_aussi_la_suite(): void
    {
        $this->troisJoursSaisis();

        $n = app(RecordSaleOnFicheElevageAction::class)->execute(
            [['lot_id' => $this->bande->id, 'qty' => 6]], '2026-10-12',
        );

        $this->assertSame(1, $n);
        $this->assertSame(['2026-10-12' => 43, '2026-10-13' => 41, '2026-10-14' => 44], $this->effectifs());
        $this->assertSame(44, (int) $this->bande->fresh()->current_quantity);
    }

    /** Le POS web passe par la même action : mêmes effets, sans rien d'autre à brancher. */
    public function test_le_pos_web_avec_une_date_passee_declenche_la_meme_cascade(): void
    {
        $this->troisJoursSaisis();
        $this->actingAs(User::where('username', 'caisse')->firstOrFail());

        Livewire::test(PosInterface::class)
            ->set('paymentMode', 'especes')
            ->set('dateVente', '2026-10-12')
            ->set('cart', [[
                'product_id' => $this->poulet->id, 'name' => 'Poulet', 'unit' => 'u',
                'qty' => 6, 'montant' => 21_000, 'lot_id' => $this->bande->id, 'lot_code' => $this->bande->code,
            ]])
            ->call('validateSale')->assertHasNoErrors();

        $this->assertSame(['2026-10-12' => 43, '2026-10-13' => 41, '2026-10-14' => 44], $this->effectifs());
        $this->assertSame(44, (int) $this->bande->fresh()->current_quantity);
    }
}
