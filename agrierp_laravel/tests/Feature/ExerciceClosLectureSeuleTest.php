<?php

namespace Tests\Feature;

use App\Actions\SaisieDepenseAction;
use App\Livewire\Achats\SaisieDepenses;
use App\Livewire\Comptabilite\JournalComptable;
use App\Livewire\Elevage\FichePondeuses;
use App\Livewire\RH\GestionPaie;
use App\Livewire\Stocks\GestionStocks;
use App\Livewire\Ventes\PosInterface;
use App\Models\AccountingEntry;
use App\Models\CompanySetting;
use App\Models\Employee;
use App\Models\Expense;
use App\Models\FiscalYear;
use App\Models\LivestockDailyEntry;
use App\Models\Payslip;
use App\Models\Sale;
use App\Models\StockMovement;
use App\Services\AccountingEntryService;
use Carbon\Carbon;
use Database\Seeders\IncomeTaxBracketsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket EX5 (PRD exercices comptables, EF5 / EF6 / R4) — UN EXERCICE CLOS EST EN LECTURE SEULE, AU WEB COMME À
 * L'ENVOI D'UN POSTE, AVEC LE MÊME MESSAGE.
 *
 * Trous constatés le 20/10/2026 (2026 clôturé, saisies du 15/03/2027) : le serveur ACCEPTAIT un ajout de stock daté du
 * 20/12/2026, une fiche d'élevage du 22/12/2026 (web et poste), la paie de 11/2026 (écriture datée du jour), le
 * déplacement au Journal d'une écriture 2027 au 15/12/2026 (`fiscal_year_id` restait 2027) et le passage d'une dépense
 * comptabilisée à une autre date (son écriture restait à l'ancienne). Un cas par trou, au web ET à l'envoi du poste
 * quand le poste saisit la donnée (la paie et le Journal ne se saisissent qu'au web).
 *
 * Messages R4, mot pour mot :
 *  - « L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 20/12/2026. »
 *  - « Aucun exercice comptable ne couvre le 10/01/2027. Ouvrez l'exercice 2027 (Comptabilité › Clôture d'exercice). »
 * Les ventes gardent leur préfixe « Vente refusée : ».
 */
class ExerciceClosLectureSeuleTest extends TestCase
{
    use PreparationExercices;
    use RefreshDatabase;

    private const CLOS_20_12 = "L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 20/12/2026.";

    private const UUID_A = 'e5000000-0000-4000-8000-00000000000a';

    private const UUID_B = 'e5000000-0000-4000-8000-00000000000b';

    protected function setUp(): void
    {
        parent::setUp();

        $this->preparerDecor('2027-03-15 10:00:00');
        $this->exercice(2026, 'cloture');
        $this->exercice(2027);
        $this->stockDeMais(10, '2026-11-02 08:00:00');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    // ═══════════════════ Stock ═══════════════════

    public function test_ajout_de_stock_web_date_d_un_exercice_clos_refuse(): void
    {
        $this->assertErreurSousLeChamp(
            Livewire::test(GestionStocks::class)
                ->set('addDate', '2026-12-20')
                ->set('addProductId', $this->mais->id)
                ->set('addQty', 5)
                ->call('submitAjouterStock'),
            'addDate',
            self::CLOS_20_12,
        );

        $this->assertEquals(10, $this->mais->fresh()->stock_qty);
        $this->assertSame(0, StockMovement::where('reference_type', 'manual_addition')->count());
    }

    public function test_ajout_de_stock_du_poste_date_d_un_exercice_clos_refuse(): void
    {
        $reponse = $this->envoyer(['stock_adjustments' => [[
            'client_ref' => self::UUID_A, 'product_id' => $this->mais->id, 'type' => 'entree', 'quantity' => 5,
            'reference_type' => 'manual_addition', 'movement_date' => '2026-12-20',
        ]]])->assertOk();

        $this->assertSame(self::UUID_A, $reponse->json('stock_adjustments.rejected.0.id'));
        $this->assertSame(self::CLOS_20_12, $reponse->json('stock_adjustments.rejected.0.reason'));
        $this->assertEquals(10, $this->mais->fresh()->stock_qty);
    }

    public function test_inventaire_du_poste_compte_dans_un_exercice_clos_refuse(): void
    {
        $reponse = $this->envoyer(['stock_adjustments' => [[
            'client_ref' => self::UUID_A, 'product_id' => $this->mais->id, 'type' => 'sortie', 'quantity' => 7,
            'reference_type' => 'inventaire', 'counted_quantity' => 3, 'counted_at' => '2026-12-20T10:00:00+01:00',
        ]]])->assertOk();

        $this->assertSame(self::CLOS_20_12, $reponse->json('stock_adjustments.rejected.0.reason'));
        $this->assertEquals(10, $this->mais->fresh()->stock_qty);
        $this->assertSame(0, AccountingEntry::where('source_type', 'stock_adjustment')->count());
    }

    // ═══════════════════ Fiche d'élevage (Q3 : refusée) ═══════════════════

    public function test_fiche_d_elevage_web_datee_d_un_exercice_clos_refusee(): void
    {
        Livewire::test(FichePondeuses::class)
            ->set('selectedDate', '2026-12-22')
            ->set('oeufsRecoltes', 120)
            ->call('saveDay')
            ->assertDispatched('toast', message: "L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 22/12/2026.", type: 'error');

        $this->assertSame(0, LivestockDailyEntry::count());
    }

    public function test_fiche_d_elevage_du_poste_datee_d_un_exercice_clos_refusee(): void
    {
        $reponse = $this->envoyer(['livestock_daily_entries' => [[
            'id' => self::UUID_A, 'lot_id' => $this->pondeuses->id, 'entry_date' => '2026-12-22', 'mort' => 1,
        ]]])->assertOk();

        $this->assertSame(self::UUID_A, $reponse->json('livestock_daily_entries.rejected.0.id'));
        $this->assertSame(
            "L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 22/12/2026.",
            $reponse->json('livestock_daily_entries.rejected.0.reason'),
        );
        $this->assertSame(0, LivestockDailyEntry::count());
        $this->assertSame(200, $this->pondeuses->fresh()->current_quantity);
    }

    /** Une fiche de 2027 (exercice ouvert) passe toujours. */
    public function test_fiche_d_elevage_d_un_exercice_ouvert_acceptee(): void
    {
        $reponse = $this->envoyer(['livestock_daily_entries' => [[
            'id' => self::UUID_A, 'lot_id' => $this->pondeuses->id, 'entry_date' => '2027-03-14', 'mort' => 1,
        ]]])->assertOk();

        $this->assertSame([self::UUID_A], $reponse->json('livestock_daily_entries.accepted'));
    }

    // ═══════════════════ Paie (Q4) ═══════════════════

    private function employe(): Employee
    {
        CompanySetting::create([
            'company_name' => 'FERME ÉCOLE OLOUWACHEGOUN',
            'vps_rate' => 4, 'cnss_employee_rate' => 3.6,
            'cnss_employer_pension_rate' => 6.4, 'cnss_employer_family_rate' => 9,
            'cnss_employer_risk_rate' => 2,
        ]);
        (new IncomeTaxBracketsSeeder())->run();

        return Employee::create([
            'first_name' => 'Kossi', 'last_name' => 'ADJOVI', 'phone' => '+22997222222',
            'base_salary' => 100_000, 'hire_date' => '2025-01-06', 'is_active' => true,
        ]);
    }

    public function test_paie_d_une_periode_d_un_exercice_clos_refusee(): void
    {
        $employe = $this->employe();

        Livewire::test(GestionPaie::class)
            ->set('periodMonth', '2026-11')
            ->call('validerReglement', $employe->id)
            ->assertDispatched('toast', message: "L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 30/11/2026.", type: 'error');

        $this->assertSame(0, Payslip::count());
        $this->assertEquals(5_000_000, $this->caisse->fresh()->balance);
        $this->assertSame(0, AccountingEntry::where('source_type', 'payroll')->count());
    }

    /**
     * Q4 — paie de décembre 2026 réglée le 10/01/2027, 2026 encore OUVERT : la charge appartient à 2026 (datée du
     * 31/12/2026), le règlement à 2027 (daté du 10/01/2027), par le compte 422 « Personnel, rémunérations dues ».
     *
     * Brut 100 000 : CNSS salariale 3 600, ITS 3 640 → net 92 760 ; charge due 661 = 100 000 ; charges patronales 664
     * = VPS 4 000 + CNSS 6 400 + 9 000 + 2 000 = 21 400. Écriture de charge : D 661 100 000, D 664 21 400 / C 4472
     * 3 640, C 4473 4 000, C 431 21 000, C 422 92 760. Règlement : D 422 92 760 / C 531 92 760.
     */
    public function test_paie_de_decembre_reglee_en_janvier_charge_au_31_decembre_reglement_a_sa_date(): void
    {
        FiscalYear::where('year', 2026)->update(['status' => 'ouvert', 'closed_at' => null]);
        Carbon::setTestNow(Carbon::parse('2027-01-10 11:00:00', 'Africa/Porto-Novo'));
        $employe = $this->employe();

        Livewire::test(GestionPaie::class)
            ->set('periodMonth', '2026-12')
            ->call('validerReglement', $employe->id)
            ->assertDispatched('toast', type: 'success');

        $bulletin = Payslip::sole();
        $this->assertEquals(92_760, $bulletin->net_salary);
        $annees = FiscalYear::pluck('id', 'year');

        $charge = AccountingEntry::with('lines.account')->find($bulletin->accounting_entry_id);
        $this->assertSame('2026-12-31', $charge->entry_date->format('Y-m-d'));
        $this->assertSame($annees[2026], $charge->fiscal_year_id);
        $parCompte = fn ($e) => $e->lines->mapWithKeys(fn ($l) => [$l->account->code => round((float) $l->debit - (float) $l->credit, 2)])->all();
        $this->assertEquals(['661' => 100_000, '664' => 21_400, '4472' => -3_640, '4473' => -4_000, '431' => -21_000, '422' => -92_760], $parCompte($charge));

        $reglement = AccountingEntry::with('lines.account')->where('source_type', 'payroll_payment')->where('source_id', $bulletin->id)->sole();
        $this->assertSame('2027-01-10', $reglement->entry_date->format('Y-m-d'));
        $this->assertSame($annees[2027], $reglement->fiscal_year_id);
        $this->assertEquals(['422' => 92_760, '531' => -92_760], $parCompte($reglement));
        $this->assertEquals(5_000_000 - 92_760, $this->caisse->fresh()->balance);
    }

    // ═══════════════════ Journal : déplacement d'écriture ═══════════════════

    private function ecritureDe2027(): AccountingEntry
    {
        return app(AccountingEntryService::class)->recordManual(
            $this->comptes['605']->id, $this->comptes['531']->id, 40_000, '2027-02-10', 'JNL-2027-0001 — Carburant'
        );
    }

    private function deplacer(AccountingEntry $ecriture, string $date)
    {
        return Livewire::test(JournalComptable::class)
            ->call('editEntry', $ecriture->id)
            ->set('entryDate', $date)
            ->call('saveEntry');
    }

    public function test_une_ecriture_ne_se_deplace_pas_dans_un_exercice_clos(): void
    {
        $ecriture = $this->ecritureDe2027();

        $this->deplacer($ecriture, '2026-12-15')
            ->assertDispatched('toast', message: "L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 15/12/2026.", type: 'error');

        $ecriture->refresh();
        $this->assertSame('2027-02-10', $ecriture->entry_date->format('Y-m-d'));
        $this->assertSame(FiscalYear::where('year', 2027)->value('id'), $ecriture->fiscal_year_id);
    }

    public function test_une_ecriture_ne_change_pas_d_exercice_meme_ouvert(): void
    {
        FiscalYear::where('year', 2026)->update(['status' => 'ouvert', 'closed_at' => null]);
        $ecriture = $this->ecritureDe2027();

        $this->deplacer($ecriture, '2026-12-15')
            ->assertDispatched('toast', message: "Une écriture ne change pas d'exercice : celle-ci appartient à l'exercice 2027. Archivez-la, puis saisissez-la à nouveau dans l'exercice 2026.", type: 'error');

        $this->assertSame('2027-02-10', $ecriture->fresh()->entry_date->format('Y-m-d'));

        // Dans le même exercice, la date se corrige toujours.
        $this->deplacer($ecriture, '2027-02-12')->assertDispatched('toast', type: 'success');
        $this->assertSame('2027-02-12', $ecriture->fresh()->entry_date->format('Y-m-d'));
    }

    // ═══════════════════ Dépenses (D-U14-1) ═══════════════════

    private const COMPTABILISEE = SaisieDepenseAction::MESSAGE_DEJA_COMPTABILISEE;

    private function depenseComptabilisee(): Expense
    {
        $depense = app(SaisieDepenseAction::class)->creer($this->depenseDuPoste(self::UUID_B, '2027-02-10'), self::UUID_B);
        $this->assertNotNull($depense->accounting_entry_id, 'décor : la dépense doit être comptabilisée');

        return $depense;
    }

    public function test_une_depense_comptabilisee_ne_s_ouvre_plus_en_modification_au_web(): void
    {
        $depense = $this->depenseComptabilisee();

        Livewire::test(SaisieDepenses::class)
            ->call('editExpense', $depense->id)
            ->assertNotDispatched('open-modal')
            ->assertDispatched('toast', message: self::COMPTABILISEE, type: 'error');

        $this->assertSame('2027-02-10', $depense->fresh()->expense_date->format('Y-m-d'));
    }

    public function test_la_date_d_une_depense_comptabilisee_est_verrouillee_a_l_envoi_du_poste(): void
    {
        $depense = $this->depenseComptabilisee();

        $reponse = $this->envoyer(['expenses' => [$this->depenseDuPoste($depense->id, '2027-02-01')]])->assertOk();

        $this->assertSame(self::COMPTABILISEE, $reponse->json('expenses.rejected.0.reason'));
        $this->assertSame('2027-02-10', $depense->fresh()->expense_date->format('Y-m-d'));
    }

    public function test_une_depense_datee_d_un_exercice_clos_est_refusee_au_web_et_au_poste(): void
    {
        $this->assertErreurSousLeChamp(
            Livewire::test(SaisieDepenses::class)
                ->call('nouvelleDepense')
                ->set('expenseDate', '2026-12-20')
                ->set('treasuryAccountId', $this->caisse->id)
                ->set('lines.0.label', 'Facture SBEE')
                ->set('lines.0.chargeAccountId', $this->comptes['605']->id)
                ->set('lines.0.amount', '25000')
                ->call('submitExpense'),
            'expenseDate',
            self::CLOS_20_12,
        );

        $reponse = $this->envoyer(['expenses' => [$this->depenseDuPoste(self::UUID_A, '2026-12-20')]])->assertOk();
        $this->assertSame(self::CLOS_20_12, $reponse->json('expenses.rejected.0.reason'));

        $this->assertSame(0, Expense::count());
        $this->assertEquals(5_000_000, $this->caisse->fresh()->balance);
    }

    /** Une dépense de 2026 (saisie avant la clôture) ne se modifie ni ne s'archive plus. */
    public function test_une_depense_d_un_exercice_clos_ne_se_modifie_ni_ne_s_archive(): void
    {
        FiscalYear::where('year', 2026)->update(['status' => 'ouvert']);
        $depense = app(SaisieDepenseAction::class)->creer($this->depenseDuPoste(self::UUID_A, '2026-12-20'), self::UUID_A);
        FiscalYear::where('year', 2026)->update(['status' => 'cloture']);

        Livewire::test(SaisieDepenses::class)
            ->call('editExpense', $depense->id)
            ->assertNotDispatched('open-modal')
            ->assertDispatched('toast', message: self::CLOS_20_12, type: 'error');

        Livewire::test(SaisieDepenses::class)
            ->call('archiveExpense', $depense->id)
            ->assertDispatched('toast', message: self::CLOS_20_12, type: 'error');

        $archivage = $this->depenseDuPoste($depense->id, '2026-12-20') + ['is_active' => false];
        $reponse = $this->envoyer(['expenses' => [$archivage]])->assertOk();
        $this->assertSame(self::CLOS_20_12, $reponse->json('expenses.rejected.0.reason'));

        $depense->refresh();
        $this->assertTrue($depense->is_active);
        $this->assertSame('Facture SBEE', $depense->label);
    }

    // ═══════════════════ Vente datée (préfixe gardé) ═══════════════════

    public function test_une_vente_datee_d_un_exercice_clos_garde_son_prefixe_au_web_et_au_poste(): void
    {
        $attendu = "Vente refusée : l'exercice 2026 est clôturé : aucune saisie ne peut être datée du 20/12/2026.";

        $pos = Livewire::test(PosInterface::class)->set('dateVente', '2026-12-20');
        $this->assertSame($attendu, $pos->errors()->first('dateVente'));

        $reponse = $this->envoyer(['sales' => [$this->venteDuPoste(self::UUID_A, '2026-12-20T09:00:00+01:00')]])->assertOk();
        $this->assertSame($attendu, $reponse->json('sales.rejected.0.reason'));
        $this->assertSame(0, Sale::count());
    }
}
