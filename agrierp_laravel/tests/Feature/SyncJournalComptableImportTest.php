<?php

namespace Tests\Feature;

use App\Livewire\Comptabilite\ClotureExercice;
use App\Livewire\Parametres\Sauvegardes;
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
use App\Services\ImportModuleService;
use App\Services\ReinitialisationDonneesService;
use App\Services\SauvegardeService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.28-bis — LES CHEMINS DE REMPLACEMENT DU JOURNAL ET LA CLÔTURE, PAR LE VRAI CHEMIN.
 *
 * ⚠️⚠️ L'audit de 15.28 a trouvé un chemin manqué : `ImportModuleService::importer` (module
 * « comptabilité », Paramètres > Sauvegardes) vide `accounting_entries` / `accounting_entry_lines`
 * puis réinsère par `DB::table()->insert` avec l'ANCIEN `updated_at` du fichier. Une écriture
 * restaurée n'était jamais servie au tirage `since` alors qu'elle figurait dans
 * `accounting_entry_ids` : le poste l'avait purgée et ne la récupérait plus ; une écriture modifiée
 * après la sauvegarde revenait à ses anciennes lignes sans être servie.
 *
 * Aucune règle inventée : seuls les deux tables du journal reçoivent l'instant de l'import ; les
 * autres modules gardent le comportement existant (leurs `updated_at` d'origine).
 *
 * SQLite : RefreshDatabase enveloppe le test dans une transaction, où la suspension des clés
 * étrangères de l'import est sans effet. On les DIFFÈRE (même procédé que SauvegardeCompteurEcrituresTest) ;
 * le chemin d'import exercé est, lui, le vrai (export réel -> fichier réel -> ImportModuleService).
 */
class SyncJournalComptableImportTest extends TestCase
{
    use RefreshDatabase;

    private ChartOfAccount $caisse;

    private ChartOfAccount $ventes;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();

        Storage::fake('local');
        DB::statement('PRAGMA defer_foreign_keys = ON');
        Carbon::setTestNow('2026-10-10 10:00:00');

        // Ticket S2 : `close-fiscal-year` — la confirmation de clôture exige désormais son autorisation.
        $permissions = ['view-parametres', 'manage-parametres', 'view-comptabilite', 'manage-comptabilite', 'close-fiscal-year'];
        foreach ($permissions as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('admin', 'web')->givePermissionTo($permissions);
        $this->admin = User::create([
            'name' => 'Directeur', 'username' => 'admin', 'email' => 'dg@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->admin->assignRole('admin');
        $this->actingAs($this->admin);

        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
        $this->caisse = ChartOfAccount::create(['code' => '531', 'label' => 'Caisse', 'class' => 5, 'is_active' => true]);
        $this->ventes = ChartOfAccount::create(['code' => '701', 'label' => 'Ventes', 'class' => 7, 'is_active' => true]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function ecrire(float $montant, string $libelle): AccountingEntry
    {
        return app(AccountingEntryService::class)->recordManual(
            $this->caisse->id, $this->ventes->id, $montant, '2026-10-05', AccountingEntry::generateReference().' — '.$libelle,
        );
    }

    private function tirer(?string $since = null)
    {
        return $this->actingAs($this->admin, 'sanctum')
            ->getJson('/api/sync/pull'.($since ? '?since='.urlencode($since) : ''));
    }

    private function sauvegarderComptabilite(): string
    {
        $fichier = app(SauvegardeService::class)->genererModule('comptabilite');

        return Storage::disk('local')->get(SauvegardeService::DOSSIER.'/'.$fichier);
    }

    // ───────────────────────── 1. Import du module « comptabilité » ─────────────────────────

    public function test_une_ecriture_modifiee_apres_la_sauvegarde_puis_restauree_est_servie_au_prochain_tirage(): void
    {
        $e = $this->ecrire(10_000, 'Vente');
        $anciennesLignes = $e->lines()->pluck('id')->all();
        $sql = $this->sauvegarderComptabilite();

        // 10:05 : l'écriture est modifiée sur le web (lignes recréées), puis un poste tire (curseur 10:06).
        Carbon::setTestNow('2026-10-10 10:05:00');
        app(AccountingEntryService::class)->updateManual(
            $e, $this->caisse->id, $this->ventes->id, 4_000, '2026-10-05', $e->reference,
        );
        $curseur = '2026-10-10T10:06:00';

        // 10:10 : restauration de la sauvegarde (retour aux anciennes lignes, ancien updated_at du fichier).
        Carbon::setTestNow('2026-10-10 10:10:00');
        $resultat = app(ImportModuleService::class)->importer($sql, 'comptabilite');
        $this->assertSame(2, $resultat['rejetees'], implode(' | ', $resultat['motifs']));

        $corps = $this->tirer($curseur)->assertOk()->json();

        $this->assertContains($e->id, $corps['accounting_entry_ids'], 'elle est active');
        $this->assertContains($e->id, array_column($corps['accounting_entries'], 'id'),
            "Une écriture réimportée DOIT être servie au tirage suivant (updated_at = instant de l'import).");
        $lignes = array_column(array_filter($corps['accounting_entry_lines'], fn ($l) => $l['entry_id'] === $e->id), 'id');
        $this->assertEqualsCanonicalizing($anciennesLignes, $lignes, 'avec TOUTES ses lignes restaurées');
    }

    public function test_l_import_horodate_les_deux_tables_du_journal_a_l_instant_de_l_import(): void
    {
        $this->ecrire(1_000, 'A');
        $sql = $this->sauvegarderComptabilite();

        Carbon::setTestNow('2026-10-10 11:30:00');
        app(ImportModuleService::class)->importer($sql, 'comptabilite');

        $this->assertSame('2026-10-10 11:30:00', AccountingEntry::first()->getRawOriginal('updated_at'));
        $this->assertSame('2026-10-10 11:30:00', AccountingEntryLine::first()->getRawOriginal('updated_at'));
    }

    public function test_un_import_d_un_autre_module_conserve_les_updated_at_du_fichier(): void
    {
        $categorie = new ProductCategory();
        $categorie->id = '11111111-1111-4111-8111-111111111111';
        $categorie->label = 'Aliments';
        $categorie->is_active = true;
        $categorie->save();
        $produit = Product::create(['sku' => 'P-1', 'name' => 'Aliment', 'category_id' => $categorie->id, 'unit' => 'kg', 'pricing_mode' => 'quote', 'stock_qty' => 1, 'is_active' => true]);
        Product::where('id', $produit->id)->update(['updated_at' => '2026-09-01 08:00:00']);
        $fichier = app(SauvegardeService::class)->genererModule('stocks');
        $sql = Storage::disk('local')->get(SauvegardeService::DOSSIER.'/'.$fichier);

        Carbon::setTestNow('2026-10-10 11:30:00');
        app(ImportModuleService::class)->importer($sql, 'stocks');

        $this->assertSame('2026-09-01 08:00:00', Product::first()->getRawOriginal('updated_at'),
            "Aucune règle inventée : les autres modules gardent l'horodatage du fichier.");
    }

    public function test_la_restauration_par_l_ecran_sauvegardes_sert_aussi_les_ecritures(): void
    {
        $e = $this->ecrire(5_000, 'Écran');
        $nom = app(SauvegardeService::class)->genererModule('comptabilite');

        Carbon::setTestNow('2026-10-10 10:20:00');
        Livewire::test(Sauvegardes::class)
            ->set('fichierAImporter', $nom)
            ->set('moduleAImporter', 'comptabilite')
            ->call('importerModule');

        $ids = array_column($this->tirer('2026-10-10T10:10:00')->json('accounting_entries'), 'id');
        $this->assertSame([$e->id], $ids);
    }

    // ───────────────────────── Réinitialisation ─────────────────────────

    public function test_la_reinitialisation_vide_la_liste_des_actives_et_conserve_exercices_et_comptes(): void
    {
        $this->ecrire(1_000, 'A');
        $this->ecrire(2_000, 'B');
        $this->assertCount(2, $this->tirer()->json('accounting_entry_ids'));

        app(ReinitialisationDonneesService::class)->executer();

        $corps = $this->tirer('2026-10-10T12:00:00')->assertOk()->json();
        $this->assertSame([], $corps['accounting_entry_ids']);
        $this->assertSame([], $corps['accounting_entries']);
        $this->assertSame([], $corps['accounting_entry_lines']);
        $this->assertSame(0, AccountingEntryLine::count());
        $this->assertSame(1, FiscalYear::count(), 'les exercices survivent à la réinitialisation');
    }

    // ───────────────────────── 4c / 4d. Clôture par l'écran réel ─────────────────────────

    public function test_la_cloture_reelle_fait_redescendre_les_ecritures_verrouillees_et_garde_l_exercice_clos_dans_les_ids(): void
    {
        ChartOfAccount::create(['code' => '131', 'label' => 'Résultat - Bénéfice', 'class' => 1, 'is_active' => true]);
        ChartOfAccount::create(['code' => '139', 'label' => 'Résultat - Perte', 'class' => 1, 'is_active' => true]);
        // Ticket EX4 — la clôture de 2026 n'est admise qu'après son échéance (Q2) : le scénario se joue le 10/01/2027.
        Carbon::setTestNow('2027-01-10 10:00:00');
        $e = $this->ecrire(1_000, 'Avant clôture');
        $this->assertFalse((bool) $e->fresh()->is_locked);

        // Un poste a tiré à 10:01, puis l'exercice est clôturé à 10:05 par l'écran réel (étapes 1, 2 et 3).
        Carbon::setTestNow('2027-01-10 10:05:00');
        Livewire::test(ClotureExercice::class)
            ->set('selectedYear', '2026')
            ->call('confirmStep1')
            ->call('soldeComptesGestion')
            ->call('confirmCloture');

        $this->assertSame('cloture', FiscalYear::where('year', 2026)->first()->status, "l'écran a bien clôturé");

        $corps = $this->tirer('2027-01-10T10:01:00')->assertOk()->json();

        $servie = collect($corps['accounting_entries'])->firstWhere('id', $e->id);
        $this->assertNotNull($servie, "L'écriture verrouillée par la clôture DOIT être servie (updated_at mis à jour).");
        $this->assertTrue($servie['is_locked']);
        // L2 : l'exercice est clos, ses écritures restent ACTIVES et figurent dans la liste des ids.
        $this->assertContains($e->id, $corps['accounting_entry_ids']);
    }

    // ───────────────────────── 7. Volume : plus de variables qu'une requête n'en accepte ─────────────────────────

    public function test_le_tirage_sert_les_lignes_de_33_000_ecritures_sans_depasser_la_limite_de_variables(): void
    {
        $annee = FiscalYear::first();
        $maintenant = now()->format('Y-m-d H:i:s');
        $ecritures = [];
        $lignes = [];
        for ($i = 0; $i < 33_000; $i++) {
            $id = sprintf('00000000-0000-4000-8000-%012d', $i);
            $ecritures[] = [
                'id' => $id, 'fiscal_year_id' => $annee->id, 'entry_date' => '2026-10-05', 'reference' => "V-{$i}",
                'is_locked' => 0, 'is_active' => 1, 'created_at' => $maintenant, 'updated_at' => $maintenant,
            ];
            $lignes[] = [
                'id' => sprintf('11111111-1111-4111-8111-%012d', $i), 'entry_id' => $id, 'account_id' => $this->caisse->id,
                'debit' => 1, 'credit' => 0, 'created_at' => $maintenant, 'updated_at' => $maintenant,
            ];
        }
        foreach (array_chunk($ecritures, 500) as $lot) {
            DB::table('accounting_entries')->insert($lot);
        }
        foreach (array_chunk($lignes, 500) as $lot) {
            DB::table('accounting_entry_lines')->insert($lot);
        }

        $corps = $this->tirer()->assertOk()->json();

        $this->assertCount(33_000, $corps['accounting_entries']);
        $this->assertCount(33_000, $corps['accounting_entry_lines']);
        $this->assertCount(33_000, $corps['accounting_entry_ids']);
    }
}
