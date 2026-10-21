<?php

namespace Tests\Feature;

use App\Actions\SaisieDepenseAction;
use App\Livewire\Achats\SaisieDepenses;
use App\Models\AccountingEntry;
use App\Models\Expense;
use App\Models\ExpenseLine;
use App\Models\FiscalYear;
use App\Models\TreasuryAccount;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket DEP2 — la modale « Nouvelle Dépense » à lignes dynamiques de « Saisie des Dépenses » (web, maître du poste).
 * Mêmes valeurs que `DepensesMultilignesTest` : 60 000 F = 45 000 + 10 000 + 5 000 ; caisse 500 000 → 440 000.
 */
class DepensesMultilignesLivewireTest extends TestCase
{
    use DecorDepenses;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->preparerDecorDepenses();
    }

    /** Remplit la modale comme l'utilisateur : en-tête, puis trois lignes. */
    private function remplir(\Livewire\Features\SupportTesting\Testable $c): \Livewire\Features\SupportTesting\Testable
    {
        $c->call('nouvelleDepense')
            ->set('expenseDate', '2026-06-15')
            ->set('paymentMode', 'caisse')
            ->set('treasuryAccountId', $this->caisse->id)
            ->call('addLine')->call('addLine');

        foreach ([['Provende ponte', '601', 45_000], ['Vermifuge', '602', 10_000], ['Sac d\'aliment bis', '601', 5_000]] as $i => [$libelle, $code, $montant]) {
            $c->set("lines.$i.label", $libelle)
                ->set("lines.$i.chargeAccountId", $this->plan[$code]->id)
                ->set("lines.$i.amount", (string) $montant);
        }

        return $c;
    }

    public function test_la_modale_s_ouvre_avec_une_ligne_vide(): void
    {
        Livewire::test(SaisieDepenses::class)
            ->call('nouvelleDepense')
            ->assertDispatched('open-modal', name: 'modal-depense')
            ->assertCount('lines', 1)
            ->assertSet('lines.0.label', '')
            ->assertSee('Nouvelle Dépense')
            ->assertSee('Ajouter une ligne')
            ->assertSee('Compte de Charge *')
            ->assertSee('Mode de Paiement *');
    }

    public function test_ajout_et_retrait_de_lignes_la_derniere_ne_se_retire_pas(): void
    {
        Livewire::test(SaisieDepenses::class)
            ->call('addLine')->call('addLine')
            ->assertCount('lines', 3)
            ->set('lines.1.label', 'B')
            ->call('removeLine', 0)
            ->assertCount('lines', 2)
            ->assertSet('lines.0.label', 'B')
            ->call('removeLine', 0)
            ->assertCount('lines', 1)
            ->call('removeLine', 0)
            ->assertCount('lines', 1);
    }

    public function test_le_total_est_la_somme_des_lignes_en_direct(): void
    {
        $c = Livewire::test(SaisieDepenses::class);
        $c->call('addLine')->call('addLine');
        $c->set('lines.0.amount', '45000')->set('lines.1.amount', '10000');

        $this->assertSame(55_000, $c->get('total'));
        $c->assertSeeHtml('data-total-depense')->assertSee('55 000');

        $c->set('lines.2.amount', '5000');
        $this->assertSame(60_000, $c->get('total'));
        $c->assertSee('60 000');

        $c->call('removeLine', 1);
        $this->assertSame(50_000, $c->get('total'), 'retirer une ligne retire son montant');

        $c->set('lines.0.amount', 'abc');
        $this->assertSame(5_000, $c->get('total'), 'une ligne illisible compte 0');
    }

    public function test_l_enregistrement_cree_la_depense_ses_lignes_et_la_piece(): void
    {
        $c = $this->remplir(Livewire::test(SaisieDepenses::class));
        $c->call('submitExpense')
            ->assertHasNoErrors()
            ->assertDispatched('toast', message: 'Dépense enregistrée avec succès.', type: 'success')
            ->assertDispatched('close-modal', name: 'modal-depense')
            ->assertCount('lines', 1)
            ->assertSet('lines.0.label', '');

        $depense = Expense::with('lines')->sole();
        $this->assertEquals(60_000.0, (float) $depense->amount);
        $this->assertCount(3, $depense->lines);
        $this->assertNotNull($depense->accounting_entry_id);
        $this->assertSame(1, AccountingEntry::count());
        $this->assertEquals(440_000.0, (float) $this->caisse->fresh()->balance);

        // Le tableau : résumé, total, mode, numéro de pièce RELU de l'écriture, lignes dans le détail déplié.
        $numero = AccountingEntry::first()->numero;
        $this->assertMatchesRegularExpression('/^OD-2026-\d{4}$/', $numero);
        $c->assertSee('Provende ponte (+2 autres)')->assertSee('60 000 FCFA')->assertSee('Espèces')
            ->assertSee($numero)->assertSee('Vermifuge')->assertSee('601 - Achats de marchandises')
            ->assertSee('Saisie par : Direction');
    }

    public function test_les_erreurs_se_posent_sous_le_champ_et_rien_n_est_ecrit(): void
    {
        Livewire::test(SaisieDepenses::class)
            ->call('nouvelleDepense')
            ->set('expenseDate', '')
            ->call('submitExpense')
            ->assertHasErrors(['expenseDate', 'paymentMode', 'treasuryAccountId', 'lines.0.label', 'lines.0.chargeAccountId', 'lines.0.amount'])
            ->set('treasuryAccountId', $this->caisse->id)
            ->set('expenseDate', '2026-06-15')
            ->set('lines.0.label', 'X')
            ->set('lines.0.chargeAccountId', $this->plan['531']->id)
            ->set('lines.0.amount', '0')
            ->call('submitExpense')
            ->assertHasErrors(['lines.0.chargeAccountId', 'lines.0.amount'])
            ->assertHasNoErrors(['lines.0.label'])
            ->set('lines.0.chargeAccountId', $this->plan['605']->id)
            ->set('lines.0.amount', '100.5')
            ->call('submitExpense')
            ->assertHasErrors(['lines.0.amount']);

        $this->assertSame(0, Expense::count());
        $this->assertSame(0, ExpenseLine::count());
    }

    public function test_une_ligne_au_moins_est_exigee(): void
    {
        $c = Livewire::test(SaisieDepenses::class)->call('nouvelleDepense')
            ->set('expenseDate', '2026-06-15')->set('treasuryAccountId', $this->caisse->id)
            ->set('lines', [])
            ->call('submitExpense')
            ->assertHasErrors(['lines']);
        $this->assertSame(0, Expense::count());
    }

    public function test_une_piece_refusee_ne_laisse_ni_depense_ni_lignes(): void
    {
        $orphelin = TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse orpheline', 'account_code' => '999', 'balance' => 100_000, 'is_active' => true]);

        $c = $this->remplir(Livewire::test(SaisieDepenses::class))
            ->set('treasuryAccountId', $orphelin->id)
            ->call('submitExpense')
            ->assertHasErrors(['treasuryAccountId']);

        $this->assertSame(0, Expense::count());
        $this->assertSame(0, ExpenseLine::count());
        $this->assertEquals(100_000.0, (float) $orphelin->fresh()->balance);
    }

    public function test_un_exercice_clos_se_dit_sous_la_date(): void
    {
        FiscalYear::where('year', 2026)->update(['status' => 'cloture']);

        $this->remplir(Livewire::test(SaisieDepenses::class))
            ->call('submitExpense')
            ->assertHasErrors(['expenseDate']);

        $this->assertSame(0, Expense::count());
    }

    public function test_le_mode_filtre_les_comptes_de_tresorerie_et_le_compte_fixe_le_mode(): void
    {
        Livewire::test(SaisieDepenses::class)
            ->call('nouvelleDepense')
            ->assertSee('Caisse Principale')->assertSee('Banque (')
            ->set('paymentMode', 'banque')
            ->assertDontSee('Caisse Principale (')
            ->assertSee('Banque (')
            ->set('treasuryAccountId', $this->banque->id)
            ->set('paymentMode', 'caisse')
            ->assertSet('treasuryAccountId', '', 'un compte d\'un autre type est abandonné')
            ->set('treasuryAccountId', $this->caisse->id)
            ->assertSet('paymentMode', 'caisse');
    }

    public function test_une_depense_comptabilisee_ne_s_ouvre_pas_en_modification(): void
    {
        $depense = app(SaisieDepenseAction::class)->creer($this->document());

        Livewire::test(SaisieDepenses::class)
            ->call('editExpense', $depense->id)
            ->assertSet('editingExpenseId', null)
            ->assertNotDispatched('open-modal')
            ->assertDispatched('toast', message: SaisieDepenseAction::MESSAGE_DEJA_COMPTABILISEE, type: 'error');

        // Et le tableau n'offre pas le crayon sur une dépense comptabilisée.
        Livewire::test(SaisieDepenses::class)->assertDontSeeHtml('editExpense(\''.$depense->id.'\')');
    }

    public function test_une_depense_sans_piece_se_modifie_par_la_modale(): void
    {
        $depense = new Expense();
        $depense->fill(['expense_date' => '2026-06-10', 'label' => 'Ancienne', 'category' => '605 - Énergie', 'amount' => 25_000,
            'treasury_account_id' => $this->caisse->id, 'payment_mode' => 'caisse', 'status' => 'payee', 'is_active' => true]);
        $depense->save();
        $ligne = new ExpenseLine();
        $ligne->id = ExpenseLine::idDeConversion($depense->id);
        $ligne->fill(['expense_id' => $depense->id, 'position' => 0, 'label' => 'Ancienne', 'charge_account_id' => $this->plan['605']->id, 'amount' => 25_000])->save();
        $this->caisse->decrement('balance', 25_000);

        Livewire::test(SaisieDepenses::class)
            ->assertSeeHtml('editExpense(\''.$depense->id.'\')')
            ->call('editExpense', $depense->id)
            ->assertDispatched('open-modal', name: 'modal-depense')
            ->assertSet('editingExpenseId', $depense->id)
            ->assertSet('lines.0.label', 'Ancienne')
            ->assertSet('lines.0.amount', '25000')
            ->assertSee('Modifier la Dépense')
            ->set('lines.0.amount', '30000')
            ->call('submitExpense')
            ->assertHasNoErrors();

        $this->assertEquals(30_000.0, (float) $depense->fresh()->amount);
        $this->assertSame(ExpenseLine::idDeConversion($depense->id), $depense->fresh()->lines->sole()->id, 'la ligne est reconnue');
        $this->assertEquals(470_000.0, (float) $this->caisse->fresh()->balance);
        $this->assertNull($depense->fresh()->accounting_entry_id);
    }

    public function test_l_archivage_contre_passe_comme_avant(): void
    {
        $depense = app(SaisieDepenseAction::class)->creer($this->document());

        Livewire::test(SaisieDepenses::class)
            ->call('archiveExpense', $depense->id)
            ->assertDispatched('toast', message: 'Dépense archivée — trésorerie réintégrée et charge annulée.', type: 'warning')
            ->assertDontSee('Provende ponte');

        $this->assertEquals(500_000.0, (float) $this->caisse->fresh()->balance);
        $this->assertSame(2, AccountingEntry::count());
    }

    public function test_recherche_par_libelle_de_ligne_et_filtre_de_piece(): void
    {
        app(SaisieDepenseAction::class)->creer($this->document());
        app(SaisieDepenseAction::class)->creer($this->document(['lines' => [
            ['label' => 'Gasoil groupe', 'charge_account_id' => $this->plan['605']->id, 'amount' => 20_000],
        ]]));
        $sansPiece = new Expense();
        $sansPiece->fill(['expense_date' => '2026-06-10', 'label' => 'Reprise ancienne', 'category' => '605 - Énergie', 'amount' => 1_000,
            'treasury_account_id' => $this->caisse->id, 'status' => 'payee', 'is_active' => true])->save();

        Livewire::test(SaisieDepenses::class)
            ->assertSee('Provende ponte (+2 autres)')->assertSee('Gasoil groupe')->assertSee('Reprise ancienne')
            ->set('search', 'Vermifuge')
            ->assertSee('Provende ponte (+2 autres)')->assertDontSee('Gasoil groupe')
            ->set('search', '')
            ->set('pieceFilter', 'Sans pièce')
            ->assertSee('Reprise ancienne')->assertDontSee('Gasoil groupe')
            ->set('pieceFilter', 'Comptabilisée')
            ->assertSee('Gasoil groupe')->assertDontSee('Reprise ancienne');
    }

    public function test_les_colonnes_du_tableau(): void
    {
        $html = Livewire::test(SaisieDepenses::class)->html();
        $this->assertMatchesRegularExpression('/<th[^>]*>Date<\/th>\s*<th[^>]*>Libellé<\/th>\s*<th[^>]*>Total<\/th>\s*<th[^>]*>Mode<\/th>\s*<th[^>]*>Pièce<\/th>\s*<th[^>]*>Actions<\/th>/', $html);
    }
}
