<?php

namespace Tests\Feature;

use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use App\Services\AccountingEntryService;
use App\Services\ImportModuleService;
use App\Services\SauvegardeService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/**
 * Ticket 15.20b — le compteur `accounting_reference_sequences` voyage AVEC les écritures.
 *
 * Défaut (audit de 15.20a) : absent du module « comptabilité », il survivait au remplacement
 * (`accounting_entries` et `fiscal_years` vidés) : orphelin, ou trop haut / trop bas selon les identifiants.
 */
class SauvegardeCompteurEcrituresTest extends TestCase
{
    use RefreshDatabase;

    private ChartOfAccount $caisse;
    private ChartOfAccount $ventes;

    protected function setUp(): void
    {
        parent::setUp();

        Storage::fake('local');

        // RefreshDatabase enveloppe le test dans une transaction : SQLite y ignore la suspension des clés
        // étrangères de l'import (qui, en production, s'exécute hors transaction externe). On les DIFFÈRE
        // ici, sans quoi l'ordre « enfants d'abord » du fichier d'export échoue pour une raison étrangère au ticket.
        DB::statement('PRAGMA defer_foreign_keys = ON');

        foreach (['view-parametres', 'manage-parametres'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('admin', 'web')->givePermissionTo(['view-parametres', 'manage-parametres']);
        $admin = User::create([
            'name' => 'Directeur', 'username' => 'admin', 'email' => 'dg@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $admin->assignRole('admin');
        $this->actingAs($admin);

        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
        $this->caisse = ChartOfAccount::create(['code' => '531', 'label' => 'Caisse', 'class' => 5, 'is_active' => true]);
        $this->ventes = ChartOfAccount::create(['code' => '701', 'label' => 'Ventes', 'class' => 7, 'is_active' => true]);
    }

    private function passer(string $libelle): string
    {
        $e = app(AccountingEntryService::class)->record(
            lines: [
                ['account_id' => $this->caisse->id, 'debit' => 100, 'credit' => 0],
                ['account_id' => $this->ventes->id, 'debit' => 0, 'credit' => 100],
            ],
            entryDate: '2026-07-01',
            reference: AccountingEntry::generateReference().' — '.$libelle,
        );

        return explode(' — ', $e->reference, 2)[0];
    }

    public function test_le_compteur_fait_partie_du_module_comptabilite_avant_fiscal_years(): void
    {
        $tables = SauvegardeService::modules()['comptabilite']['tables'];

        $this->assertContains('accounting_reference_sequences', $tables);
        $this->assertLessThan(
            array_search('fiscal_years', $tables, true),
            array_search('accounting_reference_sequences', $tables, true),
            'Enfant d\'abord : le compteur référence l\'exercice.',
        );
    }

    public function test_aller_retour_export_import_la_prochaine_ecriture_ne_duplique_aucun_numero(): void
    {
        foreach (['A', 'B', 'C'] as $l) {
            $this->passer($l);
        }

        $fichier = app(SauvegardeService::class)->genererModule('comptabilite');
        $sql = Storage::disk('local')->get(SauvegardeService::DOSSIER.'/'.$fichier);
        $this->assertStringContainsString('INSERT INTO `accounting_reference_sequences`', $sql);

        // Le poste continue de vivre après la sauvegarde, puis on restaure : retour à l'état exporté.
        $this->passer('D');
        $this->passer('E');

        $r = app(ImportModuleService::class)->importer($sql, 'comptabilite');
        // Seules les deux lignes `SET FOREIGN_KEY_CHECKS` de l'en-tête sont refusées (comportement existant).
        $this->assertSame(2, $r['rejetees'], implode(' | ', $r['motifs']));

        $this->assertSame(3, AccountingEntry::count());
        $this->assertSame(3, (int) DB::table('accounting_reference_sequences')->value('last_number'));
        $this->assertSame('OD-2026-0004', $this->passer('F'));

        $numeros = AccountingEntry::pluck('reference')->map(fn ($r) => explode(' — ', $r, 2)[0]);
        $this->assertSame($numeros->count(), $numeros->unique()->count(), 'Aucun doublon.');
    }

    /** Sauvegarde ancienne (sans la table du compteur) : le compteur vidé est reconstruit depuis les écritures. */
    public function test_import_d_une_sauvegarde_sans_compteur_ne_duplique_aucun_numero(): void
    {
        foreach (['A', 'B', 'C'] as $l) {
            $this->passer($l);
        }

        $fichier = app(SauvegardeService::class)->genererModule('comptabilite');
        $sql = Storage::disk('local')->get(SauvegardeService::DOSSIER.'/'.$fichier);
        $sansCompteur = collect(explode(PHP_EOL, $sql))
            ->reject(fn ($l) => str_contains($l, 'accounting_reference_sequences'))->implode(PHP_EOL);

        app(ImportModuleService::class)->importer($sansCompteur, 'comptabilite');

        $this->assertSame('OD-2026-0004', $this->passer('D'));
    }
}
