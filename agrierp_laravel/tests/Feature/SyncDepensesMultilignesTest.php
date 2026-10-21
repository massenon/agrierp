<?php

namespace Tests\Feature;

use App\Actions\SaisieDepenseAction;
use App\Models\AccountingEntry;
use App\Models\Expense;
use App\Models\ExpenseLine;
use App\Models\FiscalYear;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket DEP3 — `/api/sync` : la dépense part en création AVEC ses lignes dans le même document ; le serveur la rejoue par
 * `SaisieDepenseAction` (sa propre pièce). ABSORBEUR STRICT, IDEMPOTENT, et COMPATIBLE avec un poste non migré (le serveur
 * est déployé AVANT les postes) : une dépense plate est acceptée et convertie en UNE ligne.
 * Mêmes valeurs que `DepensesMultilignesTest` : 60 000 F = 45 000 + 10 000 + 5 000 ; caisse 500 000 → 440 000.
 */
class SyncDepensesMultilignesTest extends TestCase
{
    use DecorDepenses;
    use RefreshDatabase;

    private const ID = '11111111-aaaa-4aaa-8aaa-111111111111';

    private const L1 = 'a1111111-aaaa-4aaa-8aaa-000000000001';

    private const L2 = 'a1111111-aaaa-4aaa-8aaa-000000000002';

    private const L3 = 'a1111111-aaaa-4aaa-8aaa-000000000003';

    protected function setUp(): void
    {
        parent::setUp();
        $this->preparerDecorDepenses();
    }

    /** Le document d'un poste migré (identifiants de lignes inclus). */
    private function depense(array $remplacements = []): array
    {
        $doc = $this->document();
        $doc['id'] = self::ID;
        $doc['amount'] = 60_000;
        foreach ([self::L1, self::L2, self::L3] as $i => $id) {
            $doc['lines'][$i]['id'] = $id;
        }

        return array_merge($doc, $remplacements);
    }

    private function pousser(array $depenses, ?User $qui = null): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($qui ?? $this->admin, 'sanctum')->postJson('/api/sync/push', ['expenses' => $depenses]);
    }

    public function test_une_depense_a_trois_lignes_est_creee_avec_sa_piece_et_son_auteur(): void
    {
        $this->pousser([$this->depense(['cost_center_id' => $this->filiere->id, 'supplier_id' => $this->fournisseur->id, 'beneficiary' => 'M. Dossou'])])
            ->assertOk()->assertJsonPath('expenses.accepted', [self::ID])->assertJsonPath('expenses.rejected', []);

        $depense = Expense::with('lines')->findOrFail(self::ID);
        $this->assertEquals(60_000.0, (float) $depense->amount);
        $this->assertSame('Provende ponte (+2 autres)', $depense->label);
        $this->assertSame([self::L1, self::L2, self::L3], $depense->lines->pluck('id')->all(), 'les identifiants de ligne sont ceux du poste');
        $this->assertSame($this->admin->id, $depense->created_by);
        $this->assertSame($this->filiere->id, $depense->cost_center_id);
        $this->assertNotNull($depense->accounting_entry_id, 'le serveur passe SA pièce');
        $entry = AccountingEntry::with('lines')->findOrFail($depense->accounting_entry_id);
        $this->assertCount(3, $entry->lines);
        $this->assertEquals(60_000.0, (float) $entry->lines->sum('credit'));
        $this->assertEquals(60_000.0, (float) $entry->lines->sum('debit'));
        $this->assertEquals(440_000.0, (float) $this->caisse->fresh()->balance);
    }

    public function test_un_renvoi_identique_ne_cree_ni_ne_decaisse_deux_fois(): void
    {
        $this->pousser([$this->depense()])->assertJsonPath('expenses.accepted', [self::ID]);
        $this->pousser([$this->depense()])->assertJsonPath('expenses.accepted', [self::ID])->assertJsonPath('expenses.rejected', []);

        $this->assertSame(1, Expense::count());
        $this->assertSame(3, ExpenseLine::count());
        $this->assertSame(1, AccountingEntry::count());
        $this->assertEquals(440_000.0, (float) $this->caisse->fresh()->balance);
    }

    public function test_un_ancien_poste_qui_envoie_la_depense_plate_est_accepte_et_converti_en_une_ligne(): void
    {
        $plat = [
            'id' => self::ID, 'expense_date' => '2026-06-15', 'label' => 'Gasoil livraison', 'category' => '605 - Énergie',
            'amount' => 25000.0, 'treasury_account_id' => $this->caisse->id,
        ];

        $this->pousser([$plat])->assertOk()->assertJsonPath('expenses.accepted', [self::ID]);

        $depense = Expense::with('lines')->findOrFail(self::ID);
        $this->assertCount(1, $depense->lines);
        $this->assertSame(ExpenseLine::idDeConversion(self::ID), $depense->lines->first()->id);
        $this->assertSame($this->plan['605']->id, $depense->lines->first()->charge_account_id);
        $this->assertSame('Gasoil livraison', $depense->lines->first()->label);
        $this->assertEquals(25_000.0, (float) $depense->amount);
        $this->assertSame('caisse', $depense->payment_mode, 'mode déduit du compte de trésorerie');
        $this->assertEquals(475_000.0, (float) $this->caisse->fresh()->balance);

        // Son renvoi (réponse perdue) est acquitté sans rien rejouer.
        $this->pousser([$plat])->assertJsonPath('expenses.accepted', [self::ID]);
        $this->assertSame(1, ExpenseLine::count());
        $this->assertSame(1, AccountingEntry::count());
        $this->assertEquals(475_000.0, (float) $this->caisse->fresh()->balance);
    }

    public function test_une_depense_plate_a_categorie_hors_liste_est_refusee(): void
    {
        $this->pousser([[
            'id' => self::ID, 'expense_date' => '2026-06-15', 'label' => 'X', 'category' => '699 - Inconnu',
            'amount' => 1000, 'treasury_account_id' => $this->caisse->id,
        ]])->assertJsonPath('expenses.accepted', [])
            ->assertJsonPath('expenses.rejected.0.reason', 'La valeur du champ catégorie n\'est pas autorisée.');
        $this->assertSame(0, Expense::count());
    }

    /** @return array<string, array{0: callable(array): array, 1: string}> */
    public static function refus(): array
    {
        return [
            'aucune ligne' => [fn ($d) => ['lines' => []] + $d, 'Ajoutez au moins une ligne'],
            'libellé vide' => [fn ($d) => tap($d, fn (&$x) => $x['lines'][1]['label'] = ''), 'libellé de la ligne'],
            'compte inexistant' => [fn ($d) => tap($d, fn (&$x) => $x['lines'][0]['charge_account_id'] = '11111111-1111-4111-8111-111111111111'), 'compte de charge de la ligne n\'existe pas'],
            'montant nul' => [fn ($d) => tap($d, fn (&$x) => $x['lines'][2]['amount'] = 0), 'montant de la ligne'],
            'montant décimal' => [fn ($d) => tap($d, fn (&$x) => $x['lines'][2]['amount'] = 5000.5), 'nombre entier'],
            'total annoncé faux' => [fn ($d) => ['amount' => 59_999] + $d, 'somme de ses lignes'],
            'identifiants de ligne en double' => [fn ($d) => tap($d, fn (&$x) => $x['lines'][1]['id'] = $x['lines'][0]['id']), 'même identifiant'],
            'mode incohérent' => [fn ($d) => ['payment_mode' => 'mobile_money'] + $d, 'mode de paiement'],
            'date absente' => [fn ($d) => ['expense_date' => null] + $d, 'date de la dépense'],
        ];
    }

    /**
     * @dataProvider refus
     *
     * @param  callable(array): array  $abime
     */
    public function test_l_absorbeur_strict_refuse_chaque_regle_avec_son_motif_sans_rien_ecrire(callable $abime, string $extrait): void
    {
        $reponse = $this->pousser([$abime($this->depense())])->assertOk();

        $reponse->assertJsonPath('expenses.accepted', []);
        $this->assertStringContainsString($extrait, $reponse->json('expenses.rejected.0.reason'));
        $this->assertSame(0, Expense::count());
        $this->assertSame(0, ExpenseLine::count());
        $this->assertSame(0, AccountingEntry::count());
        $this->assertEquals(500_000.0, (float) $this->caisse->fresh()->balance);
    }

    public function test_un_refus_ne_fait_pas_echouer_les_autres_depenses_de_l_envoi(): void
    {
        $bonne = $this->depense();
        $mauvaise = $this->depense(['id' => '22222222-bbbb-4bbb-8bbb-222222222222', 'lines' => []]);

        $this->pousser([$mauvaise, $bonne])
            ->assertJsonPath('expenses.accepted', [self::ID])
            ->assertJsonPath('expenses.rejected.0.id', '22222222-bbbb-4bbb-8bbb-222222222222');

        $this->assertSame(1, Expense::count());
    }

    public function test_un_exercice_clos_refuse_la_depense_seule_avec_le_motif(): void
    {
        FiscalYear::where('year', 2026)->update(['status' => 'cloture']);

        $this->pousser([$this->depense()])
            ->assertJsonPath('expenses.accepted', [])
            ->assertJsonPath('expenses.rejected.0.reason', "L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 15/06/2026.");
        $this->assertSame(0, ExpenseLine::count());
    }

    public function test_une_piece_impossible_refuse_la_depense_et_n_ecrit_rien(): void
    {
        $orphelin = \App\Models\TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse orpheline', 'account_code' => '999', 'balance' => 50_000, 'is_active' => true]);

        $reponse = $this->pousser([$this->depense(['treasury_account_id' => $orphelin->id])]);

        $reponse->assertJsonPath('expenses.accepted', []);
        $this->assertStringContainsString('Caisse orpheline', $reponse->json('expenses.rejected.0.reason'));
        $this->assertSame(0, Expense::count());
        $this->assertSame(0, ExpenseLine::count());
        $this->assertEquals(50_000.0, (float) $orphelin->fresh()->balance);
    }

    public function test_le_tirage_sert_les_lignes_avec_la_depense_et_toutes_les_lignes_d_une_depense_modifiee(): void
    {
        // Une dépense SANS pièce (reprise), modifiée ensuite : le tirage resert la liste COMPLÈTE de ses lignes.
        $d = new Expense();
        $d->fill(['expense_date' => '2026-06-10', 'label' => 'Ancienne', 'category' => '605 - Énergie', 'amount' => 25_000,
            'treasury_account_id' => $this->caisse->id, 'payment_mode' => 'caisse', 'status' => 'payee', 'is_active' => true])->save();
        $l = new ExpenseLine();
        $l->id = ExpenseLine::idDeConversion($d->id);
        $l->fill(['expense_id' => $d->id, 'position' => 0, 'label' => 'Ancienne', 'charge_account_id' => $this->plan['605']->id, 'amount' => 25_000])->save();

        $curseur = now()->toIso8601String();
        \Carbon\Carbon::setTestNow(now()->addMinutes(10));
        app(SaisieDepenseAction::class)->modifier($d->id, $this->document());

        \Carbon\Carbon::setTestNow(now()->addMinute());   // le tirage ne sert pas la toute dernière seconde (horizon S-T12)
        // Le tirage paginé : les tables d'historique arrivent par pièces, de page en page (jamais une ligne sans sa dépense).
        $depenses = collect();
        $toutesLesLignes = collect();
        $jeton = null;
        $numero = 0;
        do {
            $corps = $this->actingAs($this->admin, 'sanctum')->getJson('/api/sync/pull?'.http_build_query(array_filter([
                'page' => ++$numero, 'curseur_page' => $jeton, 'since' => $curseur,
            ], fn ($v) => $v !== null)))->assertOk()->json();
            $depenses = $depenses->concat($corps['expenses'] ?? []);
            $toutesLesLignes = $toutesLesLignes->concat($corps['expense_lines'] ?? []);
            $jeton = $corps['page_suivante'];
        } while ($jeton !== null && $numero < 50);

        $servie = $depenses->firstWhere('id', $d->id);
        $this->assertEquals(60_000, $servie['amount']);
        $lignes = $toutesLesLignes->where('expense_id', $d->id);
        $this->assertSame(['Provende ponte', 'Vermifuge', 'Sac d\'aliment bis'], $lignes->pluck('label')->all());
        $this->assertSame([0, 1, 2], $lignes->pluck('position')->all());
        $this->assertNotContains(ExpenseLine::idDeConversion($d->id), $lignes->pluck('id')->all(), 'l\'ancienne ligne a disparu');
    }

    public function test_un_compte_achats_recoit_le_plan_les_centres_de_cout_et_toujours_la_liste_des_postes_anciens(): void
    {
        Permission::findOrCreate('view-achats', 'web');
        Permission::findOrCreate('manage-achats', 'web');
        Role::findOrCreate('acheteur', 'web')->givePermissionTo(['view-achats', 'manage-achats']);
        $acheteur = User::create(['name' => 'Acheteur', 'username' => 'acheteur', 'email' => 'a@fermeolouwachegoun.com', 'password' => bcrypt('x'), 'is_active' => true]);
        $acheteur->assignRole('acheteur');

        $corps = $this->actingAs($acheteur, 'sanctum')->getJson('/api/sync/pull?page=1')->assertOk()->json();

        $this->assertContains('chart_of_accounts', $corps['tables_servies']);
        $this->assertContains('cost_centers', $corps['tables_servies']);
        $this->assertContains('601', collect($corps['chart_of_accounts'])->pluck('code')->all());
        $this->assertSame([['id' => $this->filiere->id, 'label' => 'Cuniculture', 'type' => 'filiere', 'parent_species_id' => null, 'is_active' => true]], $corps['cost_centers']);
        $this->assertSame(Expense::CATEGORIES, $corps['expense_categories'], 'conservée pour les postes non migrés');
    }
}
