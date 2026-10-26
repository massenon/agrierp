<?php

namespace Tests\Feature;

use App\Models\AccountingEntry;
use App\Models\Expense;
use App\Models\Payable;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket DEP7 — `/api/sync` : la dépense À CRÉDIT d'un poste migré (clés `on_credit` + `supplier_id`, AUCUNE trésorerie) est
 * rejouée par `SaisieDepenseAction` : sa pièce crédite le 401 et la dette naît au serveur ; idempotente ; refus motivés ;
 * archivage par le poste. Au tirage : la dépense (statut, `on_credit`, trésorerie absente) et la dette (`payables`, avec le
 * nom du fournisseur) descendent ; la dette soldée disparaît et la dépense passe `payee`. Mêmes montants que
 * `DepenseFournisseurCreditTest` : 60 000 F = 45 000 + 10 000 + 5 000, caisse 500 000.
 */
class SyncDepenseFournisseurCreditTest extends TestCase
{
    use DecorDepenses;
    use RefreshDatabase;

    private const ID = '33333333-cccc-4ccc-8ccc-333333333333';

    protected function setUp(): void
    {
        parent::setUp();
        $this->preparerDecorDepenses();
    }

    /** Le document d'un poste migré, à crédit chez Agri-Bénin. */
    private function credit(array $remplacements = []): array
    {
        $doc = $this->document(['supplier_id' => $this->fournisseur->id, 'on_credit' => true]) + ['id' => self::ID, 'amount' => 60_000];
        unset($doc['treasury_account_id'], $doc['payment_mode']);
        foreach ($doc['lines'] as $i => $l) {
            $doc['lines'][$i]['id'] = 'c3333333-cccc-4ccc-8ccc-00000000000'.($i + 1);
        }

        return array_merge($doc, $remplacements);
    }

    private function pousser(array $cles): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($this->admin, 'sanctum')->postJson('/api/sync/push', $cles);
    }

    public function test_la_depense_a_credit_d_un_poste_cree_sa_piece_au_401_et_la_dette(): void
    {
        $this->pousser(['expenses' => [$this->credit()]])->assertOk()
            ->assertJsonPath('expenses.accepted', [self::ID])->assertJsonPath('expenses.rejected', []);

        $depense = Expense::findOrFail(self::ID);
        $this->assertSame('en_attente', $depense->status);
        $this->assertTrue((bool) $depense->on_credit);
        $this->assertNull($depense->treasury_account_id);
        $entry = AccountingEntry::with('lines.account')->findOrFail($depense->accounting_entry_id);
        $this->assertEquals(60_000.0, (float) $entry->lines->firstWhere('account.code', '401')->credit);
        $this->assertEquals($entry->lines->sum('debit'), $entry->lines->sum('credit'));
        $dette = Payable::where('expense_id', self::ID)->sole();
        $this->assertEquals(60_000.0, (float) $dette->amount);
        $this->assertEquals(500_000.0, (float) $this->caisse->fresh()->balance);
    }

    public function test_un_renvoi_identique_ne_cree_pas_une_seconde_dette(): void
    {
        $this->pousser(['expenses' => [$this->credit()]])->assertJsonPath('expenses.accepted', [self::ID]);
        $this->pousser(['expenses' => [$this->credit()]])->assertJsonPath('expenses.accepted', [self::ID])->assertJsonPath('expenses.rejected', []);

        $this->assertSame(1, Payable::count());
        $this->assertSame(1, AccountingEntry::count());
        $this->assertSame(1, Expense::count());
    }

    public function test_a_credit_sans_fournisseur_est_rejete_avec_son_motif(): void
    {
        $reponse = $this->pousser(['expenses' => [$this->credit(['supplier_id' => null])]])->assertOk();

        $this->assertSame([], $reponse->json('expenses.accepted'));
        $this->assertStringContainsString('une dépense à crédit crée une dette', $reponse->json('expenses.rejected.0.reason'));
        $this->assertSame(0, Expense::count());
        $this->assertSame(0, Payable::count());
    }

    public function test_a_credit_une_tresorerie_envoyee_est_ecartee(): void
    {
        $this->pousser(['expenses' => [$this->credit(['treasury_account_id' => $this->caisse->id, 'payment_mode' => 'caisse'])]])
            ->assertJsonPath('expenses.accepted', [self::ID]);

        $this->assertNull(Expense::findOrFail(self::ID)->treasury_account_id);
        $this->assertEquals(500_000.0, (float) $this->caisse->fresh()->balance);
    }

    public function test_le_poste_archive_une_depense_a_credit_la_dette_disparait(): void
    {
        $this->pousser(['expenses' => [$this->credit()]]);

        $this->pousser(['expenses' => [$this->credit(['is_active' => false])]])->assertOk()->assertJsonPath('expenses.accepted', [self::ID]);

        $this->assertFalse((bool) Expense::findOrFail(self::ID)->is_active);
        $this->assertSame(0, Payable::count());
        $this->assertSame(2, AccountingEntry::count(), 'écriture d\'origine + contre-passation');
        $this->assertEquals(500_000.0, (float) $this->caisse->fresh()->balance);
    }

    public function test_l_archivage_apres_un_reglement_du_poste_est_rejete_avec_son_motif(): void
    {
        $this->pousser(['expenses' => [$this->credit()]]);
        $this->pousser(['supplier_payments' => [[
            'id' => 'd3333333-dddd-4ddd-8ddd-333333333333', 'supplier_id' => $this->fournisseur->id,
            'treasury_account_id' => $this->caisse->id, 'amount' => 20_000, 'payment_date' => '2026-06-20',
        ]]])->assertJsonPath('supplier_payments.accepted', ['d3333333-dddd-4ddd-8ddd-333333333333']);

        $reponse = $this->pousser(['expenses' => [$this->credit(['is_active' => false])]])->assertOk();

        $this->assertStringContainsString('déjà réglée', $reponse->json('expenses.rejected.0.reason'));
        $this->assertTrue((bool) Expense::findOrFail(self::ID)->is_active);
        $this->assertEquals(20_000.0, (float) Payable::sole()->amount_paid);
    }

    public function test_le_tirage_sert_la_depense_a_credit_et_sa_dette_puis_le_reglement_les_solde(): void
    {
        $this->pousser(['expenses' => [$this->credit()]]);
        Carbon::setTestNow(now()->addMinute());

        $corps = $this->actingAs($this->admin, 'sanctum')->getJson('/api/sync/pull?page=1')->assertOk()->json();
        $servie = collect($corps['expenses'])->firstWhere('id', self::ID);
        $this->assertTrue($servie['on_credit']);
        $this->assertSame('en_attente', $servie['status']);
        $this->assertNull($servie['treasury_account_id']);
        $this->assertSame($this->fournisseur->id, $servie['supplier_id']);
        $dette = collect($corps['payables'])->sole();
        $this->assertSame('Agri-Bénin', $dette['supplier_name']);
        $this->assertEquals(60_000, $dette['amount']);
        $this->assertEquals(0, $dette['amount_paid']);

        $this->pousser(['supplier_payments' => [[
            'id' => 'd3333333-dddd-4ddd-8ddd-444444444444', 'supplier_id' => $this->fournisseur->id,
            'treasury_account_id' => $this->caisse->id, 'amount' => 60_000, 'payment_date' => '2026-06-20',
        ]]])->assertJsonPath('supplier_payments.rejected', []);
        Carbon::setTestNow(now()->addMinute());

        $apres = $this->actingAs($this->admin, 'sanctum')->getJson('/api/sync/pull?page=1')->assertOk()->json();
        $this->assertSame([], $apres['payables'], 'la dette soldée ne descend plus');
        $this->assertSame('payee', Expense::findOrFail(self::ID)->status);
    }
}
