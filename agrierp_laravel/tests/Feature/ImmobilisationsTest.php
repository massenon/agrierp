<?php

namespace Tests\Feature;

use App\Actions\RecordDepreciationEntryAction;
use App\Livewire\Comptabilite\Immobilisations;
use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\FixedAsset;
use App\Models\Permission;
use App\Models\Role;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Services\FinancialReportService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.26 (Sprint 14) — REGISTRE DES IMMOBILISATIONS et dotation.
 *
 * Le point qui compte : la dotation poste un ÉCART, jamais un cumul. Un
 * comptable qui clique deux fois ne doit pas doubler la charge — et c'est
 * exactement ce qu'un calcul « cumul théorique posté tel quel » ferait.
 */
class ImmobilisationsTest extends TestCase
{
    use RefreshDatabase;

    private User $comptable;

    private TreasuryAccount $caisse;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-comptabilite', 'manage-comptabilite'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('comptable', 'web');
        $role->givePermissionTo(['view-comptabilite', 'manage-comptabilite']);

        $this->comptable = User::create([
            'name' => 'Comptable', 'email' => 'immo@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'),
        ]);
        $this->comptable->assignRole($role);
        $this->actingAs($this->comptable);

        FiscalYear::create([
            'year' => now()->year,
            'start_date' => now()->startOfYear()->format('Y-m-d'),
            'end_date' => now()->endOfYear()->format('Y-m-d'),
            'status' => 'ouvert',
        ]);

        foreach ([
            ['221', 'Bâtiments et constructions', 2],
            ['241', "Cages et matériel d'élevage", 2],
            ['244', 'Broyeurs et équipements', 2],
            ['281', 'Amortissements des immobilisations', 2],
            ['681', 'Dotations aux amortissements', 6],
            ['531', 'Caisse', 5],
            ['401', 'Fournisseurs', 4],
        ] as [$code, $label, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $classe, 'is_active' => true]);
        }

        $this->caisse = TreasuryAccount::create([
            'type' => 'caisse', 'label' => 'Caisse Principale',
            'account_code' => '531', 'balance' => 5_000_000, 'is_active' => true,
        ]);
    }

    /** Bien acquis il y a exactement 1 an, amorti sur 5 ans → 1 annuité pleine. */
    private function broyeur(): FixedAsset
    {
        return FixedAsset::create([
            'code' => 'IMM-BR1', 'label' => 'Broyeur à provende', 'account_code' => '244',
            'acquisition_date' => now()->subYear()->format('Y-m-d'),
            'acquisition_value' => 620_000, 'residual_value' => 0,
            'duration_years' => 5, 'method' => 'lineaire', 'status' => 'en_service', 'is_active' => true, 'is_capitalized' => true,
        ]);
    }

    // ---------------------------------------------------------------- calculs

    public function test_linear_depreciation_is_prorated_by_month(): void
    {
        $bien = $this->broyeur();

        $this->assertEquals(124_000, $bien->annuite(), '620 000 / 5 ans.');
        $this->assertEquals(124_000, $bien->cumulAmortissement(now()->format('Y-m-d')), 'Un an ecoule = une annuite.');
        $this->assertEquals(496_000, $bien->valeurNette(now()->format('Y-m-d')));

        // Six mois après l'acquisition : une demi-annuité, pas une annuité pleine.
        $this->assertEquals(62_000, $bien->cumulAmortissement(now()->subMonths(6)->format('Y-m-d')));
    }

    /** L'annuité porte sur la base amortissable, jamais sur la valeur brute. */
    public function test_residual_value_is_excluded_from_the_depreciable_base(): void
    {
        $bien = FixedAsset::create([
            'code' => 'IMM-VEH', 'label' => 'Tricycle de livraison', 'account_code' => '244',
            'acquisition_date' => now()->subYear()->format('Y-m-d'),
            'acquisition_value' => 1_000_000, 'residual_value' => 200_000,
            'duration_years' => 4, 'status' => 'en_service', 'is_active' => true, 'is_capitalized' => true,
        ]);

        $this->assertEquals(200_000, $bien->annuite(), '(1 000 000 - 200 000) / 4.');
        $this->assertEquals(800_000, $bien->valeurNette(now()->format('Y-m-d')));
    }

    /** Un bien totalement amorti ne continue jamais de se déprécier. */
    public function test_a_fully_depreciated_asset_stops_at_its_depreciable_base(): void
    {
        $bien = FixedAsset::create([
            'code' => 'IMM-OLD', 'label' => 'Ancienne couveuse', 'account_code' => '241',
            'acquisition_date' => now()->subYears(9)->format('Y-m-d'),
            'acquisition_value' => 300_000, 'residual_value' => 0,
            'duration_years' => 3, 'status' => 'en_service', 'is_active' => true, 'is_capitalized' => true,
        ]);

        $this->assertEquals(300_000, $bien->cumulAmortissement(now()->format('Y-m-d')));
        $this->assertEquals(0, $bien->valeurNette(now()->format('Y-m-d')));
        $this->assertTrue($bien->estTotalementAmorti(now()->format('Y-m-d')));
    }

    /** Un bien cédé cesse de s'amortir à sa date de sortie. */
    public function test_a_disposed_asset_stops_depreciating_at_its_disposal_date(): void
    {
        $bien = $this->broyeur();
        $bien->update(['status' => 'cede', 'disposal_date' => now()->subMonths(6)->format('Y-m-d')]);

        $this->assertEquals(62_000, $bien->fresh()->cumulAmortissement(now()->format('Y-m-d')),
            "L'amortissement s'arrete a la sortie, il ne court pas jusqu'a aujourd'hui.");
    }

    // -------------------------------------------------------------- écriture

    public function test_the_depreciation_entry_debits_681_and_credits_281(): void
    {
        $this->broyeur();

        $ecriture = app(RecordDepreciationEntryAction::class)->execute(now()->format('Y-m-d'));

        $this->assertNotNull($ecriture);
        $parCompte = $ecriture->load('lines.account')->lines->keyBy(fn ($l) => $l->account->code);

        $this->assertEquals(124_000, (float) $parCompte['681']->debit);
        $this->assertEquals(124_000, (float) $parCompte['281']->credit);
        $this->assertEquals($ecriture->total_debit, $ecriture->total_credit);
    }

    /**
     * LE POINT CENTRAL : la dotation est un écart, pas un cumul.
     */
    public function test_posting_the_depreciation_twice_does_not_double_the_charge(): void
    {
        $this->broyeur();

        $action = app(RecordDepreciationEntryAction::class);
        $action->execute(now()->format('Y-m-d'));

        $this->assertNull($action->execute(now()->format('Y-m-d')),
            'Une seconde dotation le meme jour ne trouve plus rien a doter.');
        $this->assertEquals(1, AccountingEntry::where('source_type', 'depreciation')->count());
        $this->assertEquals(0, $action->montantADoter(now()->format('Y-m-d')));
    }

    /** Un bien ajouté après une première dotation est rattrapé, pas oublié. */
    public function test_an_asset_added_later_is_caught_up_by_the_next_depreciation(): void
    {
        $this->broyeur();

        $action = app(RecordDepreciationEntryAction::class);
        $action->execute(now()->format('Y-m-d'));

        FixedAsset::create([
            'code' => 'IMM-CAG', 'label' => 'Cages galvanisées', 'account_code' => '241',
            'acquisition_date' => now()->subYear()->format('Y-m-d'),
            'acquisition_value' => 850_000, 'residual_value' => 0,
            'duration_years' => 10, 'status' => 'en_service', 'is_active' => true, 'is_capitalized' => true,
        ]);

        $rattrapage = $action->execute(now()->format('Y-m-d'));

        $this->assertNotNull($rattrapage);
        $this->assertEquals(85_000, (float) $rattrapage->total_debit, "Seul l'ecart du bien ajoute est dote.");
        $this->assertEquals(209_000, (float) AccountingEntry::where('source_type', 'depreciation')->get()->sum('total_debit'));
    }

    /** Registre vide : aucune écriture à zéro n'est produite. */
    public function test_an_empty_register_produces_no_entry(): void
    {
        $this->assertNull(app(RecordDepreciationEntryAction::class)->execute(now()->format('Y-m-d')));
        $this->assertEquals(0, AccountingEntry::count());
    }

    /** La dotation apparaît en charge au Compte de Résultat, bilan équilibré. */
    public function test_depreciation_reaches_the_income_statement_and_keeps_the_balance_sheet_balanced(): void
    {
        $this->broyeur();
        app(RecordDepreciationEntryAction::class)->execute(now()->format('Y-m-d'));

        $reports = app(FinancialReportService::class);

        $this->assertEquals(-124_000, $reports->compteResultat(now()->format('Y-m-d'))['resultat_net']);
        $this->assertTrue($reports->bilan(now()->format('Y-m-d'))['is_balanced']);
        $this->assertTrue(
            $reports->balanceGenerale(now()->startOfYear()->format('Y-m-d'), now()->endOfYear()->format('Y-m-d'))['is_balanced']
        );
    }

    // ---------------------------------------------------------------- écran

    public function test_the_screen_loads_and_shows_the_register(): void
    {
        $this->broyeur();

        $this->get(route('comptabilite.immobilisations'))->assertOk();

        Livewire::test(Immobilisations::class)
            ->assertOk()
            ->assertSee('Broyeur à provende')
            ->assertSee('Ventilation par Nature');
    }

    /** KPI : brut, amortissement, net et montant restant à doter. */
    public function test_the_kpis_reflect_the_register(): void
    {
        $this->broyeur();

        $kpis = Livewire::test(Immobilisations::class)->instance()->kpis;

        $this->assertEquals(620_000, $kpis['brut']);
        $this->assertEquals(124_000, $kpis['amortissement']);
        $this->assertEquals(496_000, $kpis['net']);
        $this->assertEquals(124_000, $kpis['a_doter']);
    }

    /** La ventilation par nature — celle que la Note 2 ne pouvait pas produire. */
    public function test_the_breakdown_by_asset_nature_is_real_data_not_an_assumption(): void
    {
        $this->broyeur();
        FixedAsset::create([
            'code' => 'IMM-BAT', 'label' => 'Bâtiment d\'élevage', 'account_code' => '221',
            'acquisition_date' => now()->subYear()->format('Y-m-d'),
            'acquisition_value' => 2_400_000, 'residual_value' => 0,
            'duration_years' => 20, 'status' => 'en_service', 'is_active' => true, 'is_capitalized' => true,
        ]);

        $ventilation = collect(Livewire::test(Immobilisations::class)->instance()->ventilation)->keyBy('code');

        $this->assertEquals(2_400_000, $ventilation['221']['brut']);
        $this->assertEquals(120_000, $ventilation['221']['amortissement']);
        $this->assertEquals(620_000, $ventilation['244']['brut']);
        $this->assertEquals(496_000, $ventilation['244']['net']);
    }

    public function test_creating_an_asset_through_the_screen(): void
    {
        Livewire::test(Immobilisations::class)
            ->call('nouveau')
            ->set('code', 'IMM-042')
            ->set('label', 'Broyeur neuf')
            ->set('accountCode', '244')
            ->set('acquisitionDate', now()->subMonths(6)->format('Y-m-d'))
            ->set('acquisitionValue', 600_000)
            ->set('residualValue', 0)
            ->set('durationYears', 5)
            ->set('contrepartie', $this->caisse->id)
            ->call('enregistrer')
            ->assertHasNoErrors();

        $bien = FixedAsset::firstOrFail();
        $this->assertEquals('IMM-042', $bien->code);
        $this->assertEquals(60_000, $bien->cumulAmortissement(now()->format('Y-m-d')), 'Six mois = une demi-annuite.');
    }

    /** Une valeur résiduelle ≥ valeur d'acquisition rendrait l'annuité absurde. */
    public function test_the_residual_value_must_stay_below_the_acquisition_value(): void
    {
        Livewire::test(Immobilisations::class)
            ->call('nouveau')
            ->set('code', 'IMM-KO')->set('label', 'Bien impossible')->set('accountCode', '244')
            ->set('acquisitionDate', now()->format('Y-m-d'))
            ->set('acquisitionValue', 100_000)->set('residualValue', 100_000)->set('durationYears', 5)
            ->call('enregistrer')
            ->assertHasErrors(['residualValue']);

        $this->assertEquals(0, FixedAsset::count());
    }

    /** Un compte hors classe 2 ne peut pas porter une immobilisation. */
    public function test_an_account_outside_class_2_is_rejected(): void
    {
        Livewire::test(Immobilisations::class)
            ->call('nouveau')
            ->set('code', 'IMM-BAD')->set('label', 'Mal imputé')->set('accountCode', '681')
            ->set('acquisitionDate', now()->format('Y-m-d'))
            ->set('acquisitionValue', 100_000)->set('residualValue', 0)->set('durationYears', 5)
            ->call('enregistrer')
            ->assertHasErrors(['accountCode']);
    }

    /** La cession ne supprime rien : elle change le statut et fige l'amortissement. */
    public function test_disposal_changes_the_status_and_never_deletes(): void
    {
        $bien = $this->broyeur();

        Livewire::test(Immobilisations::class)
            ->call('ouvrirCession', $bien->id)
            ->set('cessionStatus', 'reforme')
            ->set('cessionDate', now()->format('Y-m-d'))
            ->set('cessionReason', 'Hors service après panne moteur')
            ->call('confirmerCession')
            ->assertHasNoErrors();

        $bien->refresh();
        $this->assertEquals('reforme', $bien->status);
        $this->assertEquals(now()->format('Y-m-d'), $bien->disposal_date->format('Y-m-d'));
        $this->assertEquals(1, FixedAsset::count(), 'Le bien reste au registre — son historique doit rester justifiable.');
    }

    public function test_a_disposal_cannot_predate_the_acquisition(): void
    {
        $bien = $this->broyeur();

        Livewire::test(Immobilisations::class)
            ->call('ouvrirCession', $bien->id)
            ->set('cessionDate', now()->subYears(3)->format('Y-m-d'))
            ->set('cessionReason', 'Date impossible')
            ->call('confirmerCession')
            ->assertHasErrors(['cessionDate']);
    }

    /** Le bouton de dotation passe bien l'écriture depuis l'écran. */
    public function test_the_screen_posts_the_depreciation_entry(): void
    {
        $this->broyeur();

        Livewire::test(Immobilisations::class)
            ->call('passerDotation')
            ->assertDispatched('toast');

        $this->assertEquals(1, AccountingEntry::where('source_type', 'depreciation')->count());
    }

    /**
     * Les données réellement semées s'affichent : c'est ce que verra le premier
     * utilisateur qui ouvre l'écran, bandeau « hors comptabilité » compris.
     */
    public function test_the_seeded_register_renders_with_its_out_of_ledger_warning(): void
    {
        $this->seed(\Database\Seeders\FixedAssetsSeeder::class);

        $this->get(route('comptabilite.immobilisations'))
            ->assertOk()
            ->assertSee('Broyeurs et équipements')
            ->assertSee('hors comptabilité');

        $kpis = Livewire::test(Immobilisations::class)->instance()->kpis;

        $this->assertEquals(3_870_000, $kpis['brut'], '2 400 000 + 850 000 + 620 000, valeurs de la Note 2 du prototype.');
        $this->assertEquals(3_870_000, $kpis['hors_compta'], 'Semes en reprise d anteriorite : aucun n est entre a l actif.');
        $this->assertEquals(0, $kpis['a_doter'], "Rien a doter tant qu aucun bien n est capitalise.");
    }

    // ------------------------------------------------------- Note 2 des États

    /**
     * 🔴→✅ LA LIMITE QUE CE REGISTRE LÈVE. La Note 2 des États Financiers
     * annonçait, depuis le ticket 14.6, ne pas pouvoir ventiler par nature
     * d'actif. Elle le peut désormais — et les montants viennent du registre,
     * plus d'une « hypothèse retenue » comme dans le prototype.
     */
    public function test_note_2_of_the_financial_statements_now_breaks_down_by_asset_nature(): void
    {
        $this->broyeur();
        FixedAsset::create([
            'code' => 'IMM-BAT2', 'label' => 'Bâtiment de ponte', 'account_code' => '221',
            'acquisition_date' => now()->subYear()->format('Y-m-d'),
            'acquisition_value' => 2_400_000, 'residual_value' => 0,
            'duration_years' => 20, 'status' => 'en_service', 'is_active' => true, 'is_capitalized' => true,
        ]);

        $registre = Livewire::test(\App\Livewire\Comptabilite\EtatsFinanciers::class)
            ->set('tab', 'notes')
            ->assertSee('Bâtiments et constructions')
            ->assertSee('Broyeurs et équipements')
            ->instance()
            ->registreImmobilisations;

        $parNature = collect($registre['lignes'])->keyBy('code');

        $this->assertEquals(2_400_000, $parNature['221']['brut']);
        $this->assertEquals(120_000, $parNature['221']['amortissement'], "L'amortissement est calcule par nature, plus impute en bloc aux Broyeurs.");
        $this->assertEquals(496_000, $parNature['244']['net']);
        $this->assertEquals(3_020_000, $registre['brut']);
        $this->assertEquals(0, $registre['hors_compta']);
    }

    /** Sans registre, la Note 2 retombe honnêtement sur les soldes de classe 2. */
    public function test_note_2_falls_back_to_ledger_balances_when_the_register_is_empty(): void
    {
        Livewire::test(\App\Livewire\Comptabilite\EtatsFinanciers::class)
            ->set('tab', 'notes')
            ->assertSee('Aucun bien au registre')
            ->assertOk();
    }

    // -------------------------------------------------------- capitalisation

    /**
     * LE DÉFAUT QUE LA CAPITALISATION ÉVITE : `bilan()` somme toute la classe 2,
     * 281 compris. Une dotation sans brut au grand livre afficherait un Actif
     * Immobilisé NÉGATIF.
     */
    public function test_an_acquisition_is_carried_to_the_asset_side_of_the_balance_sheet(): void
    {
        Livewire::test(Immobilisations::class)
            ->call('nouveau')
            ->set('code', 'IMM-CAP')->set('label', 'Broyeur payé comptant')->set('accountCode', '244')
            // ⚠️ Date DANS l'exercice ouvert : une acquisition antérieure ne
            // peut pas être comptabilisée (l'écran le dit alors explicitement).
            ->set('acquisitionDate', now()->startOfYear()->format('Y-m-d'))
            ->set('acquisitionValue', 620_000)->set('residualValue', 0)->set('durationYears', 5)
            ->set('contrepartie', $this->caisse->id)
            ->call('enregistrer')
            ->assertHasNoErrors();

        $bien = FixedAsset::firstOrFail();
        $this->assertTrue($bien->is_capitalized);
        $this->assertNotNull($bien->acquisition_entry_id);

        $parCompte = AccountingEntry::with('lines.account')->findOrFail($bien->acquisition_entry_id)
            ->lines->keyBy(fn ($l) => $l->account->code);

        $this->assertEquals(620_000, (float) $parCompte['244']->debit, "Le bien entre a l'actif.");
        $this->assertEquals(620_000, (float) $parCompte['531']->credit, 'La caisse paie.');

        // Et le Bilan, dotation passée, reste positif ET équilibré.
        app(RecordDepreciationEntryAction::class)->execute(now()->format('Y-m-d'));

        // LA RÉCONCILIATION QUI COMPTE : l'Actif Immobilisé du Bilan (lu au
        // grand livre) dit exactement la même chose que la valeur nette du
        // registre. C'est la propriété que la capitalisation garantit — et
        // qui serait fausse, et même négative, sans écriture d'acquisition.
        $net = Livewire::test(Immobilisations::class)->instance()->kpis['net'];
        $bilan = app(FinancialReportService::class)->bilan(now()->format('Y-m-d'));

        $this->assertEqualsWithDelta($net, $bilan['total_immo'], 0.01,
            'Le grand livre et le registre doivent dire la meme valeur nette.');
        $this->assertGreaterThan(0, $bilan['total_immo'], 'Actif Immobilise jamais negatif.');
        $this->assertLessThan(620_000, $bilan['total_immo'], "L'amortissement doit bien reduire l'actif.");
        $this->assertTrue($bilan['is_balanced']);
    }

    /** Acquisition à crédit : la contrepartie est la dette fournisseur. */
    public function test_a_credit_acquisition_credits_the_supplier_account(): void
    {
        Livewire::test(Immobilisations::class)
            ->call('nouveau')
            ->set('code', 'IMM-CRE')->set('label', 'Cages à crédit')->set('accountCode', '241')
            ->set('acquisitionDate', now()->format('Y-m-d'))
            ->set('acquisitionValue', 850_000)->set('residualValue', 0)->set('durationYears', 10)
            ->set('contrepartie', 'credit')
            ->call('enregistrer')
            ->assertHasNoErrors();

        $parCompte = AccountingEntry::with('lines.account')
            ->findOrFail(FixedAsset::firstOrFail()->acquisition_entry_id)
            ->lines->keyBy(fn ($l) => $l->account->code);

        $this->assertEquals(850_000, (float) $parCompte['241']->debit);
        $this->assertEquals(850_000, (float) $parCompte['401']->credit);
    }

    /**
     * Reprise d'antériorité : aucune écriture inventée, et le bien n'est pas
     * amorti au grand livre — sinon la charge existerait sans l'actif en face.
     */
    public function test_a_prior_period_asset_creates_no_entry_and_is_not_depreciated(): void
    {
        Livewire::test(Immobilisations::class)
            ->call('nouveau')
            ->set('code', 'IMM-ANT')->set('label', 'Bâtiment existant')->set('accountCode', '221')
            ->set('acquisitionDate', now()->subYears(2)->format('Y-m-d'))
            ->set('acquisitionValue', 2_400_000)->set('residualValue', 0)->set('durationYears', 20)
            ->set('contrepartie', '')
            ->call('enregistrer')
            ->assertHasNoErrors();

        $bien = FixedAsset::firstOrFail();
        $this->assertFalse($bien->is_capitalized);
        $this->assertNull($bien->acquisition_entry_id);
        $this->assertEquals(0, AccountingEntry::count(), "Aucune contrepartie n'est inventee.");

        $this->assertNull(app(RecordDepreciationEntryAction::class)->execute(now()->format('Y-m-d')));

        // L'écart est affiché, jamais masqué.
        $kpis = Livewire::test(Immobilisations::class)->instance()->kpis;
        $this->assertEquals(2_400_000, $kpis['hors_compta']);
        $this->assertEquals(240_000, $kpis['amortissement'], 'Le registre calcule bien la depreciation reelle du bien.');
    }

    /** Un bien n'est jamais capitalisé deux fois. */
    public function test_an_asset_is_never_capitalized_twice(): void
    {
        $bien = FixedAsset::create([
            'code' => 'IMM-DBL', 'label' => 'Broyeur à capitaliser', 'account_code' => '244',
            'acquisition_date' => now()->startOfYear()->format('Y-m-d'),   // dans l'exercice ouvert
            'acquisition_value' => 620_000, 'residual_value' => 0,
            'duration_years' => 5, 'status' => 'en_service', 'is_active' => true, 'is_capitalized' => false,
        ]);

        $action = app(\App\Actions\RecordAssetAcquisitionEntryAction::class);
        $this->assertNotNull($action->execute($bien->fresh(), $this->caisse->id));
        $this->assertNull($action->execute($bien->fresh(), $this->caisse->id));

        $this->assertEquals(1, AccountingEntry::where('source_type', 'asset_acquisition')->count());
    }

    /**
     * La valeur d'un bien déjà comptabilisé ne se réécrit pas en douce : le
     * registre divergerait du grand livre.
     */
    public function test_the_value_of_a_capitalized_asset_cannot_be_edited_away(): void
    {
        $bien = $this->broyeur();

        Livewire::test(Immobilisations::class)
            ->call('editer', $bien->id)
            ->set('acquisitionValue', 999_999)
            ->call('enregistrer')
            ->assertHasErrors(['acquisitionValue']);

        $this->assertEquals(620_000, (float) $bien->fresh()->acquisition_value);
    }

    /**
     * ⚠️ `showForm` est une propriété publique donc client-modifiable : la garde
     * doit être sur l'action qui écrit, jamais seulement sur l'ouverture du
     * formulaire.
     */
    public function test_a_read_only_user_cannot_write_even_by_forcing_the_form_open(): void
    {
        $lecteur = User::create([
            'name' => 'Lecteur', 'email' => 'lecture@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'),
        ]);
        $lectureSeule = Role::findOrCreate('observateur', 'web');
        $lectureSeule->givePermissionTo('view-comptabilite');
        $lecteur->assignRole($lectureSeule);

        $this->actingAs($lecteur);

        Livewire::test(Immobilisations::class)
            ->set('showForm', true)
            ->set('code', 'IMM-HACK')->set('label', 'Injection')->set('accountCode', '244')
            ->set('acquisitionDate', now()->format('Y-m-d'))
            ->set('acquisitionValue', 500_000)->set('residualValue', 0)->set('durationYears', 5)
            ->call('enregistrer')
            ->assertForbidden();

        $this->assertEquals(0, FixedAsset::count());

        Livewire::test(Immobilisations::class)->call('passerDotation')->assertForbidden();
    }
}
