<?php

namespace Tests\Feature;

use App\Actions\SaisieDepenseAction;
use App\Exceptions\ClosedFiscalYearException;
use App\Exceptions\DepenseNonComptabilisableException;
use App\Exceptions\DepenseNonModifiableException;
use App\Livewire\Achats\DettesFournisseurs;
use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\Expense;
use App\Models\ExpenseLine;
use App\Models\FiscalYear;
use App\Models\Payable;
use App\Services\SupplierSettlementService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket DEP7 (PRD `docs/prd/depenses-multilignes.md`, § 11 — DEP-Q3 close : OUI) — UNE DÉPENSE À UN FOURNISSEUR, NON PAYÉE
 * COMPTANT, CRÉE UNE DETTE FOURNISSEUR par le mécanisme des achats à crédit (`DetteFournisseurService` : la dette `payables`
 * et le compte 401), réglée ensuite par l'écran existant des dettes (`SupplierSettlementService`).
 *
 * Exemple calculé à la main : 15/06/2026, fournisseur Agri-Bénin, À CRÉDIT, 60 000 F = « Provende ponte » 601 45 000 +
 * « Vermifuge » 602 10 000 + « Sac d'aliment bis » 601 5 000.
 *   Écriture : D 601 = 50 000 ; D 602 = 10 000 ; C 401 = 60 000 (3 lignes, équilibrée). Caisse inchangée : 500 000.
 *   Dette : 60 000, payé 0, échéance 15/07/2026 (date + 30 jours, comme un achat). Dépense `en_attente`.
 *   Règlement de 25 000 (20/06) : D 401 25 000 / C 531 25 000 ; caisse 475 000 ; dette 35 000 ; dépense `en_attente`.
 *   Règlement de 35 000 : dette soldée ; dépense `payee` ; caisse 440 000 ; solde du 401 : 0.
 *   Archivage SANS règlement : D 401 60 000 / C 601 50 000 / C 602 10 000 ; la dette disparaît ; caisse inchangée.
 */
class DepenseFournisseurCreditTest extends TestCase
{
    use DecorDepenses;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->preparerDecorDepenses();
    }

    private function action(): SaisieDepenseAction
    {
        return app(SaisieDepenseAction::class);
    }

    /** @return array<string, mixed> le document de l'exemple, À CRÉDIT chez Agri-Bénin (aucune trésorerie) */
    private function credit(array $remplacements = []): array
    {
        $doc = $this->document(['supplier_id' => $this->fournisseur->id, 'on_credit' => true]);
        unset($doc['treasury_account_id'], $doc['payment_mode']);

        return array_merge($doc, $remplacements);
    }

    /** Solde créditeur du 401 au grand livre (ce que la ferme doit). */
    private function solde401(): float
    {
        $id = ChartOfAccount::where('code', '401')->value('id');

        return (float) DB::table('accounting_entry_lines')->where('account_id', $id)->sum('credit')
            - (float) DB::table('accounting_entry_lines')->where('account_id', $id)->sum('debit');
    }

    /** @return array<string, array{debit: float, credit: float}> */
    private function ecriture(AccountingEntry $e): array
    {
        $r = [];
        foreach ($e->lines()->with('account')->get() as $l) {
            $r[$l->account->code] = ['debit' => (float) $l->debit, 'credit' => (float) $l->credit];
        }

        return $r;
    }

    public function test_une_depense_a_credit_credite_le_401_au_lieu_de_la_tresorerie_et_ouvre_la_dette(): void
    {
        $depense = $this->action()->creer($this->credit());

        $this->assertSame('en_attente', $depense->status);
        $this->assertTrue((bool) $depense->on_credit);
        $this->assertNull($depense->treasury_account_id, 'aucune trésorerie ne bouge');
        $this->assertNull($depense->payment_mode);
        $this->assertSame($this->fournisseur->id, $depense->supplier_id);
        $this->assertEquals(60_000.0, (float) $depense->amount);

        $entry = AccountingEntry::with('lines')->findOrFail($depense->accounting_entry_id);
        $this->assertEquals([
            '601' => ['debit' => 50_000.0, 'credit' => 0.0],
            '602' => ['debit' => 10_000.0, 'credit' => 0.0],
            '401' => ['debit' => 0.0, 'credit' => 60_000.0],
        ], $this->ecriture($entry));
        $this->assertCount(3, $entry->lines);
        $this->assertEquals($entry->lines->sum('debit'), $entry->lines->sum('credit'), 'écriture équilibrée');
        $this->assertSame('expense', $entry->source_type);
        $this->assertEquals([$this->filiere->id], $entry->lines->pluck('cost_center_id')->unique()->values()->all());

        $this->assertEquals(500_000.0, (float) $this->caisse->fresh()->balance, 'la caisse est intacte');
        $this->assertEquals(800_000.0, (float) $this->banque->fresh()->balance);
        $this->assertEquals(60_000.0, $this->solde401());

        $dette = Payable::where('expense_id', $depense->id)->sole();
        $this->assertSame($this->fournisseur->id, $dette->supplier_id);
        $this->assertEquals(60_000.0, (float) $dette->amount);
        $this->assertEquals(0.0, (float) $dette->amount_paid);
        $this->assertSame('en_cours', $dette->status);
        $this->assertSame('2026-07-15', $dette->due_date->format('Y-m-d'));
        $this->assertNull($dette->purchase_id);
        $this->assertSame(1, Payable::count());
    }

    public function test_une_depense_comptant_chez_un_fournisseur_ne_cree_aucune_dette_comme_avant(): void
    {
        $depense = $this->action()->creer($this->document(['supplier_id' => $this->fournisseur->id]));

        $this->assertSame('payee', $depense->status);
        $this->assertFalse((bool) $depense->on_credit);
        $this->assertSame(0, Payable::count());
        $this->assertEquals(440_000.0, (float) $this->caisse->fresh()->balance);
        $this->assertArrayHasKey('531', $this->ecriture(AccountingEntry::findOrFail($depense->accounting_entry_id)));
        $this->assertEquals(0.0, $this->solde401());
    }

    public function test_sans_fournisseur_la_tresorerie_reste_obligatoire_comme_avant(): void
    {
        $doc = $this->document();
        unset($doc['treasury_account_id'], $doc['payment_mode']);

        try {
            $this->action()->creer($doc);
            $this->fail('La dépense aurait dû être refusée.');
        } catch (ValidationException $e) {
            $this->assertArrayHasKey('treasury_account_id', $e->errors());
        }
        $this->assertSame(0, Expense::count());
    }

    public function test_a_credit_sans_fournisseur_est_refuse_avec_un_motif_clair(): void
    {
        try {
            $this->action()->creer($this->credit(['supplier_id' => null]));
            $this->fail('La dépense aurait dû être refusée.');
        } catch (ValidationException $e) {
            $this->assertStringContainsString('une dépense à crédit crée une dette', $e->errors()['supplier_id'][0]);
        }
        $this->assertSame(0, Expense::count());
        $this->assertSame(0, Payable::count());
        $this->assertSame(0, AccountingEntry::count());
    }

    public function test_a_credit_une_tresorerie_envoyee_est_ecartee_jamais_decaissee(): void
    {
        $depense = $this->action()->creer($this->credit(['treasury_account_id' => $this->caisse->id, 'payment_mode' => 'caisse']));

        $this->assertNull($depense->treasury_account_id);
        $this->assertNull($depense->payment_mode);
        $this->assertEquals(500_000.0, (float) $this->caisse->fresh()->balance);
    }

    public function test_le_401_absent_du_plan_refuse_tout_ni_depense_ni_dette(): void
    {
        ChartOfAccount::where('code', '401')->delete();

        $this->expectException(DepenseNonComptabilisableException::class);
        try {
            $this->action()->creer($this->credit());
        } finally {
            $this->assertSame(0, Expense::count());
            $this->assertSame(0, ExpenseLine::count());
            $this->assertSame(0, Payable::count());
            $this->assertSame(0, AccountingEntry::count());
        }
    }

    public function test_un_exercice_clos_refuse_la_depense_a_credit_sans_dette(): void
    {
        FiscalYear::where('year', 2026)->update(['status' => 'cloture']);

        $this->expectException(ClosedFiscalYearException::class);
        try {
            $this->action()->creer($this->credit());
        } finally {
            $this->assertSame(0, Expense::count());
            $this->assertSame(0, Payable::count());
        }
    }

    public function test_le_reglement_par_l_ecran_existant_solde_la_dette_puis_passe_la_depense_a_payee(): void
    {
        $depense = $this->action()->creer($this->credit());
        $reglement = app(SupplierSettlementService::class);

        $applique = $reglement->regler($this->fournisseur->id, 25_000, $this->caisse->id, '2026-06-20');

        $this->assertEquals(25_000.0, $applique);
        $dette = Payable::where('expense_id', $depense->id)->sole();
        $this->assertEquals(25_000.0, (float) $dette->amount_paid);
        $this->assertSame('en_cours', $dette->status);
        $this->assertSame('en_attente', $depense->fresh()->status, 'dette non soldée : dépense en attente');
        $this->assertEquals(475_000.0, (float) $this->caisse->fresh()->balance);
        $this->assertEquals(35_000.0, $this->solde401());

        $reglement->regler($this->fournisseur->id, 35_000, $this->caisse->id, '2026-06-21');

        $this->assertSame('soldee', $dette->fresh()->status);
        $this->assertSame('payee', $depense->fresh()->status, 'dette soldée : dépense payée');
        $this->assertEquals(440_000.0, (float) $this->caisse->fresh()->balance);
        $this->assertEquals(0.0, $this->solde401(), 'le 401 est soldé : 60 000 − 25 000 − 35 000');
        $this->assertTrue($depense->fresh()->is_active);
    }

    public function test_le_reglement_ne_touche_pas_la_depense_d_un_autre_statut_ni_un_achat(): void
    {
        $comptant = $this->action()->creer($this->document(['supplier_id' => $this->fournisseur->id]));
        $this->action()->creer($this->credit());

        app(SupplierSettlementService::class)->regler($this->fournisseur->id, 60_000, $this->caisse->id, '2026-06-20');

        $this->assertSame('payee', $comptant->fresh()->status);
        $this->assertSame(1, Expense::where('status', 'payee')->where('on_credit', true)->count());
    }

    public function test_l_archivage_sans_reglement_contre_passe_la_charge_et_la_dette_la_tresorerie_ne_bouge_pas(): void
    {
        $depense = $this->action()->creer($this->credit());

        $resultat = $this->action()->archiver($depense->id);

        $this->assertSame(SaisieDepenseAction::ARCHIVEE, $resultat);
        $this->assertFalse((bool) $depense->fresh()->is_active);
        $this->assertSame(0, Payable::count(), 'la dette de la dépense archivée disparaît');
        $this->assertEquals(500_000.0, (float) $this->caisse->fresh()->balance, 'rien n\'avait été décaissé, rien n\'est réintégré');
        $this->assertEquals(0.0, $this->solde401(), '401 : 60 000 crédités puis 60 000 débités');

        $annulation = AccountingEntry::where('source_type', 'expense_reversal')->where('source_id', $depense->id)->sole();
        $this->assertSame('2026-06-20', $annulation->entry_date->format('Y-m-d'));
        $this->assertEquals([
            '601' => ['debit' => 0.0, 'credit' => 50_000.0],
            '602' => ['debit' => 0.0, 'credit' => 10_000.0],
            '401' => ['debit' => 60_000.0, 'credit' => 0.0],
        ], $this->ecriture($annulation));
        $this->assertEquals($annulation->lines->sum('debit'), $annulation->lines->sum('credit'));
        $this->assertSame(2, AccountingEntry::count(), 'jamais de suppression de l\'originale');
        $this->assertSame(SaisieDepenseAction::DEJA_ARCHIVEE, $this->action()->archiver($depense->id), 'un second archivage ne refait rien');
        $this->assertSame(2, AccountingEntry::count());
    }

    public function test_l_archivage_apres_un_reglement_meme_partiel_est_refuse_sans_rien_toucher(): void
    {
        $depense = $this->action()->creer($this->credit());
        app(SupplierSettlementService::class)->regler($this->fournisseur->id, 10_000, $this->caisse->id, '2026-06-20');
        $ecritures = AccountingEntry::count();

        try {
            $this->action()->archiver($depense->id);
            $this->fail('L\'archivage aurait dû être refusé.');
        } catch (DepenseNonModifiableException $e) {
            $this->assertStringContainsString('déjà réglée', $e->getMessage());
            $this->assertStringContainsString('10 000', $e->getMessage());
        }

        $this->assertTrue((bool) $depense->fresh()->is_active);
        $this->assertSame(1, Payable::count());
        $this->assertEquals(10_000.0, (float) Payable::first()->amount_paid);
        $this->assertSame($ecritures, AccountingEntry::count());
        $this->assertEquals(490_000.0, (float) $this->caisse->fresh()->balance);
    }

    public function test_une_depense_a_credit_est_immuable_comme_toute_depense_comptabilisee(): void
    {
        $depense = $this->action()->creer($this->credit());

        $this->expectException(DepenseNonModifiableException::class);
        $this->expectExceptionMessage(SaisieDepenseAction::MESSAGE_DEJA_COMPTABILISEE);
        $this->action()->modifier($depense->id, $this->credit(['beneficiary' => 'x']));
    }

    public function test_une_depense_sans_piece_reprise_de_l_ancien_ne_passe_pas_a_credit(): void
    {
        $depense = $this->action()->creer($this->document());
        Expense::whereKey($depense->id)->update(['accounting_entry_id' => null]);

        try {
            $this->action()->modifier($depense->id, $this->credit());
            $this->fail('La modification aurait dû être refusée.');
        } catch (DepenseNonModifiableException $e) {
            $this->assertStringContainsString('crédit', $e->getMessage());
        }
        $this->assertSame(0, Payable::count());
    }

    public function test_la_dette_apparait_dans_dettes_fournisseurs_avec_le_fournisseur(): void
    {
        $this->action()->creer($this->credit());

        Livewire::test(DettesFournisseurs::class)
            ->assertSee('Agri-Bénin')
            ->assertSee('60 000')
            ->assertSee('À échoir')
            ->assertSet('kpis.dettes_totales', 60_000.0)
            ->assertSet('kpis.fournisseurs_concernes', 1);
    }

    public function test_le_reglement_depuis_l_ecran_des_dettes_solde_la_dette_de_la_depense(): void
    {
        $depense = $this->action()->creer($this->credit());

        Livewire::test(DettesFournisseurs::class)
            ->set('paymentSupplierId', $this->fournisseur->id)
            ->set('paymentAmount', 60_000)
            ->set('paymentDate', '2026-06-20')
            ->set('paymentTreasuryAccountId', $this->caisse->id)
            ->call('submitPaiementFournisseur')
            ->assertHasNoErrors();

        $this->assertSame('payee', $depense->fresh()->status);
        $this->assertSame('soldee', Payable::sole()->status);
        $this->assertEquals(440_000.0, (float) $this->caisse->fresh()->balance);
    }

    public function test_les_achats_a_credit_ouvrent_toujours_leur_dette_par_le_meme_mecanisme(): void
    {
        $this->assertTrue(class_exists(\App\Services\DetteFournisseurService::class));
        $source = file_get_contents(app_path('Actions/RecordPurchaseAction.php'));
        $this->assertStringContainsString('DetteFournisseurService', $source, 'l\'achat ouvre sa dette par le service partagé');
        $this->assertStringNotContainsString('Payable::create', $source, 'plus de copie de la création de dette dans l\'achat');
        $this->assertStringNotContainsString('Payable::create', file_get_contents(app_path('Actions/SaisieDepenseAction.php')));
        $this->assertStringNotContainsString("where('code', '401')", file_get_contents(app_path('Actions/RecordExpenseAccountingEntryAction.php')), 'le 401 se lit par le service partagé');
    }
}
