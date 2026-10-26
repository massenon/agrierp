<?php

namespace Tests\Feature;

use App\Livewire\Achats\SaisieDepenses;
use App\Models\Expense;
use App\Models\Payable;
use App\Services\SupplierSettlementService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Tickets DEP6 et DEP7 — la modale « Nouvelle Dépense » du web (le MAÎTRE du poste) : « Centre de Coût * » obligatoire avec son
 * message sous le champ ; « Règlement * » (Payée comptant / À crédit (dette fournisseur)) dès qu'un fournisseur est choisi ;
 * à crédit, ni mode de paiement ni compte de trésorerie (rien n'est décaissé) ; la dette part au fournisseur.
 */
class DepenseFournisseurCreditLivewireTest extends TestCase
{
    use DecorDepenses;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->preparerDecorDepenses();
    }

    /** La modale ouverte, une ligne remplie (25 000 F de provende) ; le reste à la charge de chaque test. */
    private function modale(): \Livewire\Features\SupportTesting\Testable
    {
        return Livewire::test(SaisieDepenses::class)
            ->call('nouvelleDepense')
            ->set('expenseDate', '2026-06-15')
            ->set('lines.0.label', 'Provende ponte')
            ->set('lines.0.chargeAccountId', $this->plan['601']->id)
            ->set('lines.0.amount', '25000');
    }

    public function test_le_centre_de_cout_est_un_champ_obligatoire_a_asterisque_avec_son_message_sous_le_champ(): void
    {
        $page = Livewire::test(SaisieDepenses::class)->call('nouvelleDepense')->assertSee('Centre de Coût *');
        $this->assertSame(1, substr_count($page->html(), '-- Aucun --'), 'seul « Fournisseur » garde « Aucun » : le centre de coût n\'est plus facultatif');

        $this->modale()->set('paymentMode', 'caisse')->set('treasuryAccountId', $this->caisse->id)
            ->call('submitExpense')
            ->assertHasErrors(['costCenterId'])
            ->assertSee('Le centre de coût est obligatoire');

        $this->assertSame(0, Expense::count());
        $this->assertEquals(500_000.0, (float) $this->caisse->fresh()->balance);
    }

    public function test_avec_un_centre_la_depense_comptant_est_enregistree(): void
    {
        $this->modale()->set('treasuryAccountId', $this->caisse->id)->set('costCenterId', $this->filiere->id)
            ->call('submitExpense')->assertHasNoErrors()
            ->assertDispatched('toast', message: 'Dépense enregistrée avec succès.', type: 'success');

        $this->assertSame($this->filiere->id, Expense::sole()->cost_center_id);
        $this->assertEquals(475_000.0, (float) $this->caisse->fresh()->balance);
    }

    public function test_le_choix_de_reglement_n_apparait_qu_avec_un_fournisseur_et_dit_la_regle(): void
    {
        $c = Livewire::test(SaisieDepenses::class)->call('nouvelleDepense')
            ->assertDontSee('Règlement *')->assertSee('Mode de Paiement *')->assertSee('Compte de Trésorerie Débité *');

        $c->set('supplierId', $this->fournisseur->id)
            ->assertSee('Règlement *')->assertSee('Payée comptant')->assertSee('À crédit (dette fournisseur)')
            ->assertSee('Mode de Paiement *', 'comptant : la trésorerie reste demandée')
            ->assertSet('reglement', 'comptant');

        $c->set('reglement', 'credit')
            ->assertDontSee('Mode de Paiement *')->assertDontSee('Compte de Trésorerie Débité *')
            ->assertSeeHtml('data-aide-credit')->assertSee('la dette est créée au nom du fournisseur');

        $c->set('supplierId', '')->assertSet('reglement', 'comptant')->assertDontSee('Règlement *')->assertSee('Mode de Paiement *');
    }

    public function test_a_credit_la_depense_cree_la_dette_sans_toucher_la_tresorerie(): void
    {
        $this->modale()->set('costCenterId', $this->filiere->id)->set('supplierId', $this->fournisseur->id)->set('reglement', 'credit')
            ->call('submitExpense')->assertHasNoErrors()
            ->assertDispatched('toast', message: 'Dépense enregistrée avec succès.', type: 'success');

        $depense = Expense::sole();
        $this->assertTrue((bool) $depense->on_credit);
        $this->assertSame('en_attente', $depense->status);
        $this->assertNull($depense->treasury_account_id);
        $this->assertEquals(25_000.0, (float) Payable::sole()->amount);
        $this->assertEquals(500_000.0, (float) $this->caisse->fresh()->balance);

        Livewire::test(SaisieDepenses::class)->assertSee('À crédit')->assertSee('Règlement : À crédit — en attente');
    }

    public function test_un_fournisseur_choisi_en_comptant_exige_toujours_la_tresorerie(): void
    {
        $this->modale()->set('costCenterId', $this->filiere->id)->set('supplierId', $this->fournisseur->id)
            ->call('submitExpense')->assertHasErrors(['treasuryAccountId', 'paymentMode']);

        $this->assertSame(0, Expense::count());
        $this->assertSame(0, Payable::count());
    }

    public function test_l_archivage_d_une_depense_a_credit_annule_la_dette_et_le_dit(): void
    {
        $this->modale()->set('costCenterId', $this->filiere->id)->set('supplierId', $this->fournisseur->id)->set('reglement', 'credit')->call('submitExpense');
        $depense = Expense::sole();

        Livewire::test(SaisieDepenses::class)->call('archiveExpense', $depense->id)
            ->assertDispatched('toast', message: 'Dépense archivée — dette fournisseur annulée et charge annulée.', type: 'warning');

        $this->assertFalse((bool) $depense->fresh()->is_active);
        $this->assertSame(0, Payable::count());
        $this->assertEquals(500_000.0, (float) $this->caisse->fresh()->balance);
    }

    public function test_l_archivage_apres_reglement_est_refuse_avec_son_motif(): void
    {
        $this->modale()->set('costCenterId', $this->filiere->id)->set('supplierId', $this->fournisseur->id)->set('reglement', 'credit')->call('submitExpense');
        $depense = Expense::sole();
        app(SupplierSettlementService::class)->regler($this->fournisseur->id, 5_000, $this->caisse->id, '2026-06-20');

        Livewire::test(SaisieDepenses::class)->call('archiveExpense', $depense->id)
            ->assertDispatched('toast', type: 'error');

        $this->assertTrue((bool) $depense->fresh()->is_active);
        $this->assertSame(1, Payable::count());
    }

    public function test_une_depense_sans_piece_reprise_s_ouvre_en_comptant_au_centre_general(): void
    {
        $depense = new Expense();
        $depense->fill(['expense_date' => '2026-06-10', 'label' => 'Ancienne', 'category' => '605 - Énergie', 'amount' => 25_000,
            'treasury_account_id' => $this->caisse->id, 'payment_mode' => 'caisse', 'status' => 'payee', 'is_active' => true,
            'cost_center_id' => \App\Models\CostCenter::general()->id]);
        $depense->save();
        $ligne = new \App\Models\ExpenseLine();
        $ligne->id = \App\Models\ExpenseLine::idDeConversion($depense->id);
        $ligne->fill(['expense_id' => $depense->id, 'position' => 0, 'label' => 'Ancienne', 'charge_account_id' => $this->plan['605']->id, 'amount' => 25_000])->save();

        Livewire::test(SaisieDepenses::class)->call('editExpense', $depense->id)
            ->assertSet('costCenterId', \App\Models\CostCenter::general()->id)
            ->assertSet('reglement', 'comptant');
    }
}
