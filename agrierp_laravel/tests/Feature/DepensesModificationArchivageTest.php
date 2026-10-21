<?php

namespace Tests\Feature;

use App\Actions\SaisieDepenseAction;
use App\Livewire\Achats\SaisieDepenses;
use App\Models\AccountingEntry;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\Expense;
use App\Models\ExpenseLine;
use App\Models\FiscalYear;
use App\Models\TreasuryAccount;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket U14 — MODIFIER ET ARCHIVER UNE DÉPENSE : au web (« Saisie des Dépenses ») et depuis un poste (`/api/sync/push`),
 * par le même point de passage (`SaisieDepenseAction`), avec les mêmes règles et les mêmes messages.
 *
 * 🔴 Défauts corrigés, chacun verrouillé ci-dessous :
 *  - l'envoi d'un poste acquittait sans rien rejouer une dépense déjà connue : modification et archivage faits au poste
 *    se perdaient en silence ;
 *  - au web, changer le COMPTE DE TRÉSORERIE d'une dépense comptabilisée faisait diverger les deux livres ;
 *  - au web, modifier une dépense ARCHIVÉE (page restée ouverte) débitait la caisse une seconde fois ;
 *  - au web, un second archivage (double clic) réintégrait le montant et contre-passait la charge deux fois ;
 *  - deux dépenses du même jour sans ordre défini dans la liste ;
 *  - une dépense créée par un poste n'écrivait pas `expense.created` au journal d'audit.
 *
 * Ticket DEP1 à DEP3 — une dépense a des LIGNES et une dépense COMPTABILISÉE est IMMUABLE (même son libellé) : on la
 * corrige par archivage (contre-passation). Seule une dépense SANS pièce (reprise de l'ancien) se modifie.
 */
class DepensesModificationArchivageTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    private TreasuryAccount $caisse;

    private TreasuryAccount $banque;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seed(RolesAndPermissionsSeeder::class);
        $this->admin = User::create([
            'name' => 'Direction', 'username' => 'admin', 'email' => 'dg@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->admin->assignRole('admin');

        FiscalYear::create([
            'year' => now()->year, 'start_date' => now()->startOfYear()->format('Y-m-d'),
            'end_date' => now()->endOfYear()->format('Y-m-d'), 'status' => 'ouvert',
        ]);
        foreach ([['531', 'Caisse', 5], ['521', 'Banque', 5], ['601', 'Aliments', 6], ['605', 'Énergie', 6]] as [$code, $libelle, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $libelle, 'class' => $classe, 'is_active' => true]);
        }
        $this->caisse = TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse Principale', 'account_code' => '531', 'balance' => 500_000, 'is_active' => true]);
        $this->banque = TreasuryAccount::create(['type' => 'banque', 'label' => 'Banque', 'account_code' => '521', 'balance' => 800_000, 'is_active' => true]);
    }

    /** Une dépense comptabilisée de 25 000 sur la caisse, saisie au web. */
    private function depenseDuWeb(string $libelle = 'Sac de provende', string $date = null): Expense
    {
        $this->actingAs($this->admin);
        $depense = app(SaisieDepenseAction::class)->creer([
            'expense_date' => $date ?? now()->format('Y-m-d'), 'treasury_account_id' => $this->caisse->id,
            'lines' => [['label' => $libelle, 'charge_account_id' => ChartOfAccount::where('code', '601')->value('id'), 'amount' => 25_000]],
        ]);
        $this->assertNotNull($depense->accounting_entry_id);

        return $depense;
    }

    /** Une dépense de l'ancien régime (reprise) : une ligne, AUCUNE pièce, 25 000 F décaissés de la caisse. */
    private function depenseSansPiece(string $libelle = 'Reprise'): Expense
    {
        $this->actingAs($this->admin);
        $d = new Expense();
        $d->fill(['expense_date' => now()->format('Y-m-d'), 'label' => $libelle, 'category' => '601 - Aliments', 'amount' => 25_000,
            'treasury_account_id' => $this->caisse->id, 'payment_mode' => 'caisse', 'status' => 'payee', 'is_active' => true]);
        $d->save();
        $l = new ExpenseLine();
        $l->id = ExpenseLine::idDeConversion($d->id);
        $l->fill(['expense_id' => $d->id, 'position' => 0, 'label' => $libelle, 'charge_account_id' => ChartOfAccount::where('code', '601')->value('id'), 'amount' => 25_000])->save();
        $this->caisse->decrement('balance', 25_000);

        return $d;
    }

    /**
     * Le document d'envoi d'un poste migré pour [$d] ; [$remplacements] remplace des champs de l'en-tête, `libelle`
     * celui de la première ligne, `montant` son montant, `compte` son compte de charge.
     *
     * @return array<string, mixed>
     */
    private function ligne(Expense $d, array $remplacements = []): array
    {
        $d->load('lines');
        $l = $d->lines->first();
        $ligne = ['id' => $l->id, 'label' => $remplacements['libelle'] ?? $l->label,
            'charge_account_id' => $remplacements['compte'] ?? $l->charge_account_id, 'amount' => $remplacements['montant'] ?? (int) $l->amount];
        unset($remplacements['libelle'], $remplacements['compte'], $remplacements['montant']);

        return array_merge([
            'id' => $d->id, 'expense_date' => $d->expense_date->format('Y-m-d'), 'treasury_account_id' => $d->treasury_account_id,
            'payment_mode' => $d->payment_mode, 'lines' => [$ligne], 'is_active' => true,
        ], $remplacements);
    }

    private function pousser(array $lignes, ?User $qui = null): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($qui ?? $this->admin, 'sanctum')->postJson('/api/sync/push', ['expenses' => $lignes]);
    }

    /** Solde du compte de classe 5 au grand livre (débit − crédit). */
    private function grandLivre(string $code): float
    {
        $compte = ChartOfAccount::where('code', $code)->firstOrFail();

        return (float) \DB::table('accounting_entry_lines')->where('account_id', $compte->id)->sum(\DB::raw('debit - credit'));
    }

    // ── Web ────────────────────────────────────────────────────────────────

    public function test_web_une_depense_comptabilisee_ne_se_modifie_plus_ni_compte_ni_libelle(): void
    {
        $d = $this->depenseDuWeb();

        Livewire::test(SaisieDepenses::class)
            ->call('editExpense', $d->id)
            ->assertNotDispatched('open-modal')
            ->assertDispatched('toast', message: SaisieDepenseAction::MESSAGE_DEJA_COMPTABILISEE, type: 'error');

        // Même en forçant l'état (page forgée) : le point de passage refuse.
        $this->expectException(\App\Exceptions\DepenseNonModifiableException::class);
        try {
            app(SaisieDepenseAction::class)->modifier($d->id, $this->ligne($d, ['treasury_account_id' => $this->banque->id, 'payment_mode' => 'banque']));
        } finally {
            $this->assertSame($this->caisse->id, $d->fresh()->treasury_account_id);
            // Les deux livres restent d'accord, pour les deux comptes.
            $this->assertEquals(475_000, (float) $this->caisse->fresh()->balance);
            $this->assertEquals(800_000, (float) $this->banque->fresh()->balance);
            $this->assertEquals(-25_000, $this->grandLivre('531'));
            $this->assertEquals(0, $this->grandLivre('521'));
        }
    }

    public function test_web_le_libelle_d_une_depense_sans_piece_se_modifie(): void
    {
        $d = $this->depenseSansPiece();

        Livewire::test(SaisieDepenses::class)
            ->call('editExpense', $d->id)
            ->set('lines.0.label', 'Sac de provende ponte')
            ->call('submitExpense')
            ->assertHasNoErrors()
            ->assertDispatched('toast', message: 'Dépense enregistrée avec succès.', type: 'success');

        $this->assertSame('Sac de provende ponte', $d->fresh()->label);
        $this->assertEquals(475_000, (float) $this->caisse->fresh()->balance);
        $this->assertSame(1, AuditLog::where('action', 'expense.updated')->count());
    }

    public function test_web_une_depense_archivee_ne_se_modifie_plus(): void
    {
        $d = $this->depenseSansPiece();
        $page = Livewire::test(SaisieDepenses::class)->call('editExpense', $d->id);
        app(SaisieDepenseAction::class)->archiver($d->id);   // archivée ailleurs, la page reste ouverte

        $page->set('lines.0.label', 'Autre')->call('submitExpense')->assertHasErrors(['formulaire']);
        $this->assertSame(SaisieDepenseAction::MESSAGE_ARCHIVEE, $page->errors()->first('formulaire'));

        $this->assertEquals(500_000, (float) $this->caisse->fresh()->balance, 'la caisse ne perd pas le montant une seconde fois');
    }

    public function test_web_un_second_archivage_ne_reintegre_pas_deux_fois(): void
    {
        $d = $this->depenseDuWeb();

        Livewire::test(SaisieDepenses::class)
            ->call('archiveExpense', $d->id)
            ->assertDispatched('toast', message: 'Dépense archivée — trésorerie réintégrée et charge annulée.', type: 'warning')
            ->call('archiveExpense', $d->id);

        $this->assertEquals(500_000, (float) $this->caisse->fresh()->balance);
        $this->assertSame(1, AccountingEntry::where('source_type', 'expense_reversal')->count());
        $this->assertSame(1, AuditLog::where('action', 'expense.archived')->count());
    }

    public function test_web_recherche_filtre_de_piece_et_ordre_de_deux_depenses_du_meme_jour(): void
    {
        $b = $this->depenseDuWeb('Carburant B');
        $a = $this->depenseDuWeb('Carburant A');
        $this->depenseDuWeb('Électricité', now()->subDay()->format('Y-m-d'));
        Expense::whereKey($a->id)->update(['accounting_entry_id' => null]);

        $liste = fn ($c) => $c->instance()->expenses->pluck('label')->all();

        $c = Livewire::test(SaisieDepenses::class);
        $memeJour = collect([$a, $b])->sortBy('id')->pluck('label')->all();
        $this->assertSame([...$memeJour, 'Électricité'], $liste($c));

        $this->assertSame(['Carburant A'], $liste($c->set('search', 'carburant')->set('pieceFilter', 'Sans pièce')));
        $this->assertSame(['Carburant B'], $liste($c->set('pieceFilter', 'Comptabilisée')));
        // (SQLite des tests : `LIKE` insensible à la casse pour l'ASCII seulement ; MySQL, `utf8mb4_unicode_ci`, l'est
        // aussi aux accents — le poste suit MySQL, `cleCommeLeServeur`.)
        $this->assertSame(['Électricité'], $liste($c->set('search', 'ECTRI')->set('pieceFilter', '')));
    }

    // ── Envoi d'un poste ───────────────────────────────────────────────────

    public function test_poste_archive_une_depense_comme_le_web(): void
    {
        $d = $this->depenseDuWeb();

        $this->pousser([$this->ligne($d, ['is_active' => false])])
            ->assertOk()->assertJsonPath('expenses.accepted', [$d->id])->assertJsonPath('expenses.rejected', []);

        $this->assertFalse($d->fresh()->is_active);
        $this->assertEquals(500_000, (float) $this->caisse->fresh()->balance);
        $this->assertEquals(0, $this->grandLivre('531'), 'contre-passation');
        $this->assertSame(1, AuditLog::where('action', 'expense.archived')->count());

        // Renvoi (réponse perdue) : rien n'est refait.
        $this->pousser([$this->ligne($d, ['is_active' => false])])->assertJsonPath('expenses.accepted', [$d->id]);
        $this->assertEquals(500_000, (float) $this->caisse->fresh()->balance);
        $this->assertSame(1, AccountingEntry::where('source_type', 'expense_reversal')->count());
    }

    /**
     * 🔁 Ticket DEP1 — une dépense COMPTABILISÉE est immuable : le libellé comme la date, le montant, le compte de
     * charge ou le compte de trésorerie. Le renvoi INCHANGÉ de la saisie d'origine reste acquitté (idempotence).
     */
    public function test_poste_toute_modification_d_une_depense_comptabilisee_est_refusee_avec_le_message_du_web(): void
    {
        $d = $this->depenseDuWeb();
        $hier = now()->subDay()->format('Y-m-d');
        $autreCompte = ChartOfAccount::where('code', '605')->value('id');

        foreach ([['libelle' => 'Provende ponte'], ['expense_date' => $hier], ['montant' => 30_000], ['compte' => $autreCompte],
            ['treasury_account_id' => $this->banque->id, 'payment_mode' => 'banque']] as $changement) {
            $this->pousser([$this->ligne($d, $changement)])
                ->assertJsonPath('expenses.accepted', [])
                ->assertJsonPath('expenses.rejected.0.reason', SaisieDepenseAction::MESSAGE_DEJA_COMPTABILISEE);
        }

        $this->assertSame('Sac de provende', $d->fresh()->label);
        $this->assertEquals(25_000, (float) $d->fresh()->amount);
        $this->assertEquals(475_000, (float) $this->caisse->fresh()->balance);

        $this->pousser([$this->ligne($d)])->assertJsonPath('expenses.accepted', [$d->id]);
        $this->assertSame(0, AuditLog::where('action', 'expense.updated')->count());
    }

    public function test_poste_modifie_une_depense_sans_piece(): void
    {
        $d = $this->depenseSansPiece();

        $this->pousser([$this->ligne($d, ['libelle' => 'Provende ponte', 'montant' => 30_000])])
            ->assertJsonPath('expenses.accepted', [$d->id]);

        $this->assertSame('Provende ponte', $d->fresh()->label);
        $this->assertEquals(30_000, (float) $d->fresh()->amount);
        $this->assertEquals(470_000, (float) $this->caisse->fresh()->balance);
        $this->assertSame(1, AuditLog::where('action', 'expense.updated')->count());
    }

    public function test_poste_une_depense_archivee_au_web_ne_se_modifie_plus(): void
    {
        $d = $this->depenseDuWeb();
        app(SaisieDepenseAction::class)->archiver($d->id);

        $this->pousser([$this->ligne($d, ['libelle' => 'Autre'])])
            ->assertJsonPath('expenses.rejected.0.reason', SaisieDepenseAction::MESSAGE_ARCHIVEE);
        // Le renvoi de la saisie d'origine (inchangée) reste acquitté.
        $this->pousser([$this->ligne($d)])->assertJsonPath('expenses.accepted', [$d->id]);
        $this->assertEquals(500_000, (float) $this->caisse->fresh()->balance);
    }

    public function test_poste_une_depense_saisie_puis_archivee_hors_ligne_est_creee_puis_archivee(): void
    {
        $id = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';

        $this->pousser([[
            'id' => $id, 'expense_date' => now()->format('Y-m-d'), 'treasury_account_id' => $this->caisse->id, 'is_active' => false,
            'lines' => [['id' => 'bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb', 'label' => 'Doublon', 'charge_account_id' => ChartOfAccount::where('code', '601')->value('id'), 'amount' => 9_000]],
        ]])->assertJsonPath('expenses.accepted', [$id]);

        $this->assertFalse(Expense::findOrFail($id)->is_active);
        $this->assertEquals(500_000, (float) $this->caisse->fresh()->balance);
        $this->assertSame(1, AccountingEntry::where('source_type', 'expense')->count());
        $this->assertSame(1, AccountingEntry::where('source_type', 'expense_reversal')->count());
        $this->assertSame(1, AuditLog::where('action', 'expense.created')->count());
        $this->assertSame(1, AuditLog::where('action', 'expense.archived')->count());
    }

    public function test_poste_sans_le_droit_du_web_ni_modification_ni_archivage(): void
    {
        $d = $this->depenseSansPiece();
        $comptable = User::create([
            'name' => 'Comptable', 'username' => 'compta', 'email' => 'compta@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $comptable->assignRole('comptable');   // pas `manage-achats`

        $this->pousser([$this->ligne($d, ['is_active' => false]), $this->ligne($d, ['libelle' => 'X'])], $comptable)
            ->assertJsonPath('expenses.accepted', []);

        $this->assertTrue($d->fresh()->is_active);
        $this->assertSame('Reprise', $d->fresh()->label);
    }

    public function test_le_tirage_sert_le_statut_l_ecriture_et_les_lignes(): void
    {
        $d = $this->depenseDuWeb();

        $reponse = $this->actingAs($this->admin, 'sanctum')->getJson('/api/sync/pull');
        $servie = collect($reponse->json('expenses'))->firstWhere('id', $d->id);

        $this->assertSame('payee', $servie['status']);
        $this->assertSame($d->accounting_entry_id, $servie['accounting_entry_id']);
        $this->assertSame('caisse', $servie['payment_mode']);
        $this->assertSame($this->admin->id, $servie['created_by']);
        $this->assertEquals([[
            'id' => $d->lines->first()->id, 'expense_id' => $d->id, 'position' => 0, 'label' => 'Sac de provende',
            'charge_account_id' => ChartOfAccount::where('code', '601')->value('id'), 'amount' => 25000.0,
        ]], $reponse->json('expense_lines'));
    }
}
