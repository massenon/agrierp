<?php

namespace Tests\Feature;

use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\Expense;
use App\Models\Permission;
use App\Models\Role;
use App\Models\TreasuryAccount;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 14.62 (Sprint 14) — LES DÉPENSES ENTRENT DANS LE CONTRAT DE SYNCHRO.
 *
 * ⚠️⚠️ CE QUE CES TESTS PROTÈGENT. Une dépense porte **deux effets**, pas un :
 * elle décaisse la trésorerie ET passe son écriture SYSCOHADA. Enregistrer la
 * ligne sans ses effets produirait exactement le défaut déjà corrigé pour les
 * ventes hors ligne (14.52) et la ponte (14.59) — un enregistrement qui existe
 * et ne pèse sur rien, découvert des semaines plus tard au rapprochement.
 */
class SyncDepensesTest extends TestCase
{
    use RefreshDatabase;

    private User $utilisateur;

    private TreasuryAccount $caisse;

    protected function setUp(): void
    {
        parent::setUp();

        $this->utilisateur = User::create([
            'name' => 'Caissier', 'username' => 'caisse',
            'email' => 'caisse@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);

        // Ticket S1 : l'envoi du poste exige désormais le rôle qui écrit chaque table.

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);

        $this->utilisateur->assignRole('admin');

        $this->caisse = TreasuryAccount::create([
            'label' => 'Caisse Physique',
            'account_code' => '531',
            'type' => 'caisse',
            'balance' => 500000,
            'is_active' => true,
        ]);

        // Un exercice ouvert : sans lui, aucune écriture n'est possible.
        \App\Models\FiscalYear::create([
            'year' => (int) now()->format('Y'),
            'start_date' => now()->startOfYear()->toDateString(),
            'end_date' => now()->endOfYear()->toDateString(),
            'status' => 'ouvert',
        ]);

        // Comptes du plan nécessaires à l'écriture : charge et trésorerie.
        foreach ([['601', 'Achats d\'aliments', 6], ['531', 'Caisse', 5]] as [$numero, $libelle, $classe]) {
            ChartOfAccount::firstOrCreate(
                ['code' => $numero],
                ['label' => $libelle, 'class' => $classe, 'is_active' => true],
            );
        }
    }

    /** @return array<string, mixed> */
    private function depense(array $remplacements = []): array
    {
        return array_merge([
            'id' => '99999999-9999-4999-8999-999999999999',
            'expense_date' => now()->toDateString(),
            'label' => 'Sac de provende ponte',
            'category' => '601 - Aliments',
            'amount' => 25000,
            'treasury_account_id' => $this->caisse->id,
        ], $remplacements);
    }

    private function pousser(array $depenses): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($this->utilisateur, 'sanctum')
            ->postJson('/api/sync/push', ['expenses' => $depenses]);
    }

    /**
     * ⚠️⚠️ LE TEST QUI COMPTE : la dépense arrive avec ses DEUX effets.
     */
    public function test_a_pushed_expense_debits_treasury_and_posts_its_entry(): void
    {
        $reponse = $this->pousser([$this->depense()]);

        $reponse->assertOk();
        $reponse->assertJsonPath('expenses.accepted.0', '99999999-9999-4999-8999-999999999999');

        $depense = Expense::firstOrFail();
        $this->assertEquals('payee', $depense->status);

        // Effet 1 — la trésorerie a réellement baissé.
        $this->assertEquals(475000.0, (float) $this->caisse->fresh()->balance,
            'une depense qui ne decaisse pas laisse une caisse fausse');

        // Effet 2 — l'écriture existe et est rattachée à la dépense.
        $this->assertNotNull($depense->accounting_entry_id);
        $this->assertEquals(1, AccountingEntry::count());
    }

    /**
     * ⚠️ L'écriture est équilibrée : Débit classe 6 / Crédit trésorerie.
     */
    public function test_the_generated_entry_is_balanced(): void
    {
        $this->pousser([$this->depense()]);

        $ecriture = AccountingEntry::with('lines')->firstOrFail();

        $debits = $ecriture->lines->sum('debit');
        $credits = $ecriture->lines->sum('credit');

        $this->assertEquals($debits, $credits, 'SUM(debit) = SUM(credit)');
        $this->assertEquals(25000.0, (float) $debits);
    }

    /**
     * ⚠️⚠️ UN RENVOI NE DÉCAISSE PAS DEUX FOIS. Le poste qui n'a pas eu son
     * accusé de réception rejoue son envoi : ce doit être un succès silencieux,
     * pas une seconde sortie de caisse.
     */
    public function test_pushing_the_same_expense_twice_debits_once(): void
    {
        $this->pousser([$this->depense()])->assertOk();
        $this->pousser([$this->depense()])->assertOk();

        $this->assertEquals(1, Expense::count());
        $this->assertEquals(475000.0, (float) $this->caisse->fresh()->balance);
        $this->assertEquals(1, AccountingEntry::count());
    }

    /**
     * ⚠️ UN COMPTE DE CHARGE INCONNU EST REFUSÉ. Sans cette borne, un poste
     * modifié pourrait imputer n'importe quoi et l'écriture partirait sur un
     * compte inexistant.
     */
    public function test_an_unknown_charge_account_is_refused(): void
    {
        $reponse = $this->pousser([$this->depense(['category' => '999 - Compte inventé'])]);

        $reponse->assertOk();
        $reponse->assertJsonPath('expenses.accepted', []);
        $this->assertEquals(0, Expense::count());
        $this->assertEquals(500000.0, (float) $this->caisse->fresh()->balance,
            'rien ne doit avoir bouge');
    }

    /** ⚠️ Un montant nul ou négatif est refusé, comme à l'écran. */
    public function test_a_zero_amount_is_refused(): void
    {
        $this->pousser([$this->depense(['amount' => 0])])->assertOk();

        $this->assertEquals(0, Expense::count());
        $this->assertEquals(500000.0, (float) $this->caisse->fresh()->balance);
    }

    /** Un compte payeur inconnu est refusé plutôt que créé. */
    public function test_an_unknown_treasury_account_is_refused(): void
    {
        $this->pousser([$this->depense([
            'treasury_account_id' => '11111111-1111-4111-8111-111111111111',
        ])])->assertOk();

        $this->assertEquals(0, Expense::count());
    }

    /**
     * ⚠️ LE TIRAGE SERT CE QU'IL FAUT POUR SAISIR HORS LIGNE : les comptes de
     * trésorerie (qui paie) et la liste des comptes de charge (source unique,
     * pour que poste et web ne divergent pas).
     */
    public function test_the_pull_serves_what_is_needed_to_enter_an_expense(): void
    {
        $reponse = $this->actingAs($this->utilisateur, 'sanctum')->getJson('/api/sync/pull');

        $reponse->assertOk();

        $comptes = $reponse->json('treasury_accounts');
        $this->assertNotEmpty($comptes);
        $this->assertEquals('Caisse Physique', $comptes[0]['label']);

        $this->assertEquals(Expense::CATEGORIES, $reponse->json('expense_categories'));
    }

    /**
     * ⚠️⚠️ UN REFUS COMPTABLE NE FAIT PAS ÉCHOUER TOUT L'ENVOI. Sans exercice
     * ouvert, l'écriture est impossible ; laisser remonter l'exception
     * renverrait 500 pour la requête ENTIÈRE, et les fiches d'élevage du même
     * envoi seraient perdues avec elle.
     */
    public function test_a_closed_fiscal_year_rejects_the_expense_alone(): void
    {
        \App\Models\FiscalYear::query()->update(['status' => 'cloture']);

        $reponse = $this->pousser([$this->depense()]);

        $reponse->assertOk();
        $reponse->assertJsonPath('expenses.accepted', []);
        $this->assertStringContainsString(
            'exercice',
            strtolower($reponse->json('expenses.rejected.0.reason')),
            'le motif doit etre lisible par l utilisateur du poste',
        );

        // ⚠️ Et surtout : rien n'a bougé — la transaction a été annulée.
        $this->assertEquals(0, Expense::count());
        $this->assertEquals(500000.0, (float) $this->caisse->fresh()->balance,
            'aucune caisse fausse ne doit subsister');
    }
}
