<?php

namespace Tests\Feature;

use App\Livewire\Comptabilite\JournalComptable;
use App\Models\AccountingEntry;
use App\Models\AccountingEntryLine;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\User;
use App\Services\AccountingEntryService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.28 — LE JOURNAL SERVI AU POSTE DOIT POUVOIR SE CORRIGER.
 *
 * ⚠️⚠️ Le tirage `/api/sync/pull` ne sert que les écritures ACTIVES modifiées depuis `since`, et le
 * poste fusionne sans jamais rien supprimer. Deux défauts silencieux en découlaient :
 *  (a) une écriture ARCHIVÉE sur le web restait indéfiniment au poste, comptée par son Journal,
 *      son Grand Livre et sa Balance ;
 *  (b) `AccountingEntryService::updateManual` supprime les lignes et en recrée avec de NOUVEAUX
 *      identifiants : le poste gardait les anciennes, donc montants doublés. Pire : quand ni la
 *      date ni la référence ne changeaient, l'en-tête n'était pas « sale », `updated_at` ne
 *      bougeait pas et l'écriture n'était PAS servie du tout.
 *
 * Contrat : le tirage sert `accounting_entry_ids` = identifiants de TOUTES les écritures actives
 * (sans filtre `since`) ; le poste retire ce qui n'y figure plus. Une écriture servie arrive avec
 * TOUTES ses lignes courantes ; le poste remplace ses lignes par celles-là.
 */
class SyncJournalComptableTest extends TestCase
{
    use RefreshDatabase;

    private User $utilisateur;

    private ChartOfAccount $caisse;

    private ChartOfAccount $ventes;

    private ChartOfAccount $banque;

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow('2026-10-10 10:00:00');

        FiscalYear::create([
            'year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert',
        ]);

        $this->caisse = ChartOfAccount::create(['code' => '531', 'label' => 'Caisse', 'class' => 5, 'is_active' => true]);
        $this->ventes = ChartOfAccount::create(['code' => '701', 'label' => 'Ventes', 'class' => 7, 'is_active' => true]);
        $this->banque = ChartOfAccount::create(['code' => '521', 'label' => 'Banque', 'class' => 5, 'is_active' => true]);

        $this->utilisateur = User::create([
            'name' => 'Poste', 'username' => 'poste', 'email' => 'poste@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function ecrire(float $montant = 10_000, string $reference = 'OD-0001 — Vente'): AccountingEntry
    {
        return app(AccountingEntryService::class)
            ->recordManual($this->caisse->id, $this->ventes->id, $montant, '2026-10-05', $reference);
    }

    /** @return \Illuminate\Testing\TestResponse */
    private function tirer(?string $since = null)
    {
        return $this->actingAs($this->utilisateur, 'sanctum')
            ->getJson('/api/sync/pull'.($since ? '?since='.urlencode($since) : ''));
    }

    private function agirCommeComptable(): void
    {
        foreach (['view-comptabilite', 'manage-comptabilite'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('comptable', 'web');
        $role->givePermissionTo(['view-comptabilite', 'manage-comptabilite']);
        $compta = User::create([
            'name' => 'Compta', 'username' => 'compta', 'email' => 'compta@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $compta->assignRole($role);
        $this->actingAs($compta);
    }

    /** Somme (débit, crédit) par compte, recalculée INDÉPENDAMMENT à partir de la réponse. */
    private function totauxParCompte(array $corps): array
    {
        $actives = array_flip($corps['accounting_entry_ids']);
        $t = [];
        foreach ($corps['accounting_entry_lines'] as $l) {
            if (! isset($actives[$l['entry_id']])) {
                continue;
            }
            $t[$l['account_id']]['d'] = ($t[$l['account_id']]['d'] ?? 0) + (float) $l['debit'];
            $t[$l['account_id']]['c'] = ($t[$l['account_id']]['c'] ?? 0) + (float) $l['credit'];
        }

        return $t;
    }

    public function test_le_tirage_sert_les_identifiants_de_toutes_les_ecritures_actives(): void
    {
        $a = $this->ecrire(1_000, 'OD-0001 — A');
        $b = $this->ecrire(2_000, 'OD-0002 — B');
        AccountingEntry::where('id', $b->id)->update(['is_active' => false]);

        $ids = $this->tirer()->assertOk()->json('accounting_entry_ids');

        $this->assertSame([$a->id], $ids);
    }

    public function test_une_ecriture_archivee_sur_le_web_sort_de_la_liste_des_ecritures_actives(): void
    {
        $a = $this->ecrire(1_000, 'OD-0001 — A');
        $b = $this->ecrire(2_000, 'OD-0002 — B');

        $this->assertEqualsCanonicalizing([$a->id, $b->id], $this->tirer()->json('accounting_entry_ids'));

        // Chemin réel : l'écran Journal comptable.
        Carbon::setTestNow('2026-10-10 10:05:00');
        $this->agirCommeComptable();
        Livewire::test(JournalComptable::class)->call('archiveEntry', $b->id);

        $corps = $this->tirer('2026-10-10T10:01:00+00:00')->assertOk()->json();

        $this->assertSame([$a->id], $corps['accounting_entry_ids']);
        // L'archivée n'est plus servie dans le détail, mais les identifiants suffisent à la retirer.
        $this->assertNotContains($b->id, array_column($corps['accounting_entries'], 'id'));
    }

    public function test_la_liste_des_identifiants_actifs_ne_depend_pas_de_since(): void
    {
        $a = $this->ecrire(1_000, 'OD-0001 — A');
        $b = $this->ecrire(2_000, 'OD-0002 — B');

        // `since` dans le futur : plus aucune écriture n'est « modifiée »…
        $corps = $this->tirer('2026-10-10T12:00:00+00:00')->assertOk()->json();

        $this->assertSame([], $corps['accounting_entries']);
        // … mais le poste doit toujours connaître l'ensemble des actives.
        $this->assertEqualsCanonicalizing([$a->id, $b->id], $corps['accounting_entry_ids']);
    }

    public function test_une_ecriture_modifiee_est_servie_avec_toutes_ses_lignes_courantes(): void
    {
        $e = $this->ecrire(10_000);
        $anciennes = $e->lines()->pluck('id')->all();

        Carbon::setTestNow('2026-10-10 10:05:00');
        $this->agirCommeComptable();
        // Même date, même référence : seul le montant et le compte changent.
        app(AccountingEntryService::class)->updateManual(
            $e, $this->banque->id, $this->ventes->id, 4_000, '2026-10-05', 'OD-0001 — Vente',
        );

        $corps = $this->tirer('2026-10-10T10:01:00+00:00')->assertOk()->json();

        $this->assertContains($e->id, array_column($corps['accounting_entries'], 'id'),
            "Une écriture dont les lignes ont été recréées DOIT être servie, même si sa date et sa référence n'ont pas changé.");

        $lignes = array_values(array_filter($corps['accounting_entry_lines'], fn ($l) => $l['entry_id'] === $e->id));
        $this->assertCount(2, $lignes);
        foreach ($lignes as $l) {
            $this->assertNotContains($l['id'], $anciennes, 'Les anciennes lignes ne sont plus servies.');
        }
        $this->assertEquals(4_000.0, array_sum(array_column($lignes, 'debit')));
        $this->assertEquals(4_000.0, array_sum(array_column($lignes, 'credit')));
    }

    public function test_une_modification_qui_change_aussi_la_reference_est_servie(): void
    {
        $e = $this->ecrire(10_000);

        Carbon::setTestNow('2026-10-10 10:05:00');
        app(AccountingEntryService::class)->updateManual(
            $e, $this->caisse->id, $this->ventes->id, 10_000, '2026-10-06', 'OD-0001 — Corrigée',
        );

        $ids = array_column($this->tirer('2026-10-10T10:01:00+00:00')->json('accounting_entries'), 'id');

        $this->assertSame([$e->id], $ids);
    }

    public function test_une_ecriture_restauree_redescend_avec_ses_lignes(): void
    {
        $e = $this->ecrire(7_500);
        AccountingEntry::where('id', $e->id)->update(['is_active' => false]);
        $this->assertSame([], $this->tirer()->json('accounting_entry_ids'));

        // Aucun écran de restauration n'existe (les écritures sont exclues de la corbeille) :
        // la réactivation est simulée au niveau du modèle, comme le ferait une reprise manuelle.
        Carbon::setTestNow('2026-10-10 10:05:00');
        AccountingEntry::findOrFail($e->id)->update(['is_active' => true]);

        $corps = $this->tirer('2026-10-10T10:01:00+00:00')->assertOk()->json();

        $this->assertSame([$e->id], $corps['accounting_entry_ids']);
        $this->assertSame([$e->id], array_column($corps['accounting_entries'], 'id'));
        $this->assertCount(2, $corps['accounting_entry_lines']);
    }

    public function test_une_ecriture_supprimee_physiquement_ne_figure_plus_dans_les_actives(): void
    {
        $a = $this->ecrire(1_000, 'OD-0001 — A');
        $b = $this->ecrire(2_000, 'OD-0002 — B');

        // Réinitialisation / restauration de sauvegarde : DELETE physique, aucun `updated_at` à lire.
        DB::table('accounting_entry_lines')->where('entry_id', $b->id)->delete();
        DB::table('accounting_entries')->where('id', $b->id)->delete();

        $this->assertSame([$a->id], $this->tirer('2026-10-10T12:00:00+00:00')->json('accounting_entry_ids'));
    }

    public function test_la_cloture_de_l_exercice_fait_redescendre_les_ecritures_verrouillees(): void
    {
        $e = $this->ecrire(1_000);

        Carbon::setTestNow('2026-10-10 10:05:00');
        // Chemin de ClotureExercice (étape définitive) : mise à jour de masse via le modèle.
        AccountingEntry::where('fiscal_year_id', $e->fiscal_year_id)->update(['is_locked' => true]);

        $lignes = $this->tirer('2026-10-10T10:01:00+00:00')->json('accounting_entries');

        $this->assertSame([$e->id], array_column($lignes, 'id'));
        $this->assertTrue($lignes[0]['is_locked']);
    }

    public function test_le_poste_peut_recalculer_les_memes_totaux_que_le_serveur_apres_modification(): void
    {
        $e = $this->ecrire(10_000);
        $this->ecrire(500, 'OD-0002 — Petite');

        Carbon::setTestNow('2026-10-10 10:05:00');
        app(AccountingEntryService::class)->updateManual(
            $e, $this->banque->id, $this->ventes->id, 4_000, '2026-10-05', 'OD-0001 — Vente',
        );

        // Vérité du serveur : somme par compte des lignes des écritures actives.
        $verite = [];
        foreach (AccountingEntryLine::whereIn('entry_id', AccountingEntry::where('is_active', true)->pluck('id'))->get() as $l) {
            $verite[$l->account_id]['d'] = ($verite[$l->account_id]['d'] ?? 0) + (float) $l->debit;
            $verite[$l->account_id]['c'] = ($verite[$l->account_id]['c'] ?? 0) + (float) $l->credit;
        }

        $this->assertEquals($verite, $this->totauxParCompte($this->tirer()->json()));
        $this->assertEquals(4_000.0, $verite[$this->banque->id]['d']);
        $this->assertEquals(500.0, $verite[$this->caisse->id]['d']);
        $this->assertEquals(4_500.0, $verite[$this->ventes->id]['c']);
    }

    public function test_non_regression_les_autres_tables_gardent_leur_filtre_since(): void
    {
        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);
        $ancien = Product::create(['sku' => 'P-1', 'name' => 'Ancien', 'category_id' => $categorie->id, 'unit' => 'kg', 'pricing_mode' => 'quote', 'stock_qty' => 1, 'is_active' => true]);
        Product::where('id', $ancien->id)->update(['updated_at' => '2026-10-01 00:00:00']);
        ProductCategory::query()->update(['updated_at' => '2026-10-01 00:00:00']);

        $corps = $this->tirer('2026-10-05T00:00:00+00:00')->assertOk()->json();

        $this->assertSame([], $corps['products']);
        $this->assertArrayHasKey('server_time', $corps);
        $this->assertArrayHasKey('accounting_entries', $corps);
        $this->assertArrayHasKey('accounting_entry_lines', $corps);
        $this->assertArrayHasKey('chart_of_accounts', $corps);
        $this->assertArrayHasKey('fiscal_years', $corps);
    }

    public function test_les_lignes_servies_sont_celles_des_seules_ecritures_servies(): void
    {
        $a = $this->ecrire(1_000, 'OD-0001 — A');
        Carbon::setTestNow('2026-10-10 10:05:00');
        $b = $this->ecrire(2_000, 'OD-0002 — B');

        $corps = $this->tirer('2026-10-10T10:01:00+00:00')->json();

        $this->assertSame([$b->id], array_column($corps['accounting_entries'], 'id'));
        $this->assertEqualsCanonicalizing([$b->id], array_unique(array_column($corps['accounting_entry_lines'], 'entry_id')));
        $this->assertEqualsCanonicalizing([$a->id, $b->id], $corps['accounting_entry_ids']);
    }
}
