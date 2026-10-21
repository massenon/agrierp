<?php

namespace Tests\Feature;

use App\Livewire\Comptabilite\ClotureExercice;
use App\Models\BankStatementLine;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use App\Services\AccountingEntryService;
use App\Services\BankReconciliationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.43 (Sprint 14) — TAUX DE LETTRAGE de l'écran Clôture d'Exercice.
 *
 * La carte KPI « Lettrage Bancaire » affichait « — » depuis le Sprint 10 au
 * motif qu'« aucun mécanisme de rapprochement bancaire réel n'existe dans ce
 * projet ». Le mécanisme existe depuis le ticket 14.8 ; la carte n'y était
 * jamais revenue.
 *
 * Deux propriétés protègent la clôture : les DEUX côtés comptent (livre et
 * relevé), et l'absence de relevé n'est JAMAIS présentée comme 100 %.
 */
class TauxLettrageClotureTest extends TestCase
{
    use RefreshDatabase;

    private ChartOfAccount $banque;

    private ChartOfAccount $ventes;

    private ChartOfAccount $achats;

    protected function setUp(): void
    {
        parent::setUp();

        FiscalYear::create([
            'year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert',
        ]);

        $this->banque = ChartOfAccount::create(['code' => '521101', 'label' => 'Banque', 'class' => 5, 'is_active' => true]);
        $this->ventes = ChartOfAccount::create(['code' => '701', 'label' => 'Ventes', 'class' => 7, 'is_active' => true]);
        $this->achats = ChartOfAccount::create(['code' => '601', 'label' => 'Achats', 'class' => 6, 'is_active' => true]);
    }

    private function encaissement(float $montant, string $date): void
    {
        app(AccountingEntryService::class)
            ->recordManual($this->banque->id, $this->ventes->id, $montant, $date, 'OD — Encaissement');
    }

    private function ligneReleve(float $montant, string $date, string $libelle = 'Virement'): void
    {
        BankStatementLine::create([
            'account_id' => $this->banque->id, 'statement_date' => $date,
            'label' => $libelle, 'amount' => $montant, 'is_reconciled' => false,
        ]);
    }

    private function taux(): array
    {
        return app(BankReconciliationService::class)->tauxDeLettrage('2026-01-01', '2026-12-31');
    }

    /** Livre et relevé concordants : tout est lettré. */
    public function test_a_fully_matching_period_reaches_one_hundred_percent(): void
    {
        $this->encaissement(150_000, '2026-03-10');
        $this->ligneReleve(150_000, '2026-03-12');

        $resultat = $this->taux();

        $this->assertEquals(100, $resultat['taux']);
        $this->assertEquals(2, $resultat['lignes'], 'Une ligne de livre et une de releve.');
    }

    /**
     * ⚠️ LES DEUX CÔTÉS COMPTENT. Un chèque non présenté (livre seul) et des
     * frais bancaires non saisis (relevé seul) sont deux anomalies distinctes.
     */
    public function test_both_sides_count_in_the_denominator(): void
    {
        $this->encaissement(150_000, '2026-03-10');
        $this->ligneReleve(150_000, '2026-03-12');

        $this->encaissement(40_000, '2026-04-01');       // en instance, côté livre
        $this->ligneReleve(-2_500, '2026-04-05', 'Frais'); // non saisi, côté relevé

        $resultat = $this->taux();

        $this->assertEquals(4, $resultat['lignes']);
        $this->assertEquals(2, $resultat['lettrees']);
        $this->assertEquals(50, $resultat['taux'], 'Les deux anomalies pesent, pas une seule.');
    }

    /**
     * ⚠️ AUCUN RELEVÉ IMPORTÉ ⇒ AUCUN TAUX, JAMAIS 100 %. Autoriser une
     * clôture sur « 100 % » alors que rien n'a été vérifié serait le pire des
     * affichages possibles.
     */
    public function test_no_statement_never_reads_as_fully_reconciled(): void
    {
        $this->encaissement(150_000, '2026-03-10');

        $resultat = $this->taux();

        $this->assertNull($resultat['taux']);
        $this->assertNotEquals(100, $resultat['taux']);
    }

    /**
     * Un compte mouvementé sans relevé n'est pas « mal lettré » : il est non
     * rapprochable. Compté à part, et affiché.
     */
    public function test_an_account_without_a_statement_is_counted_separately(): void
    {
        $this->encaissement(150_000, '2026-03-10');
        $this->ligneReleve(150_000, '2026-03-12');

        // Seconde banque, mouvementée mais sans relevé importé.
        $autre = ChartOfAccount::create(['code' => '521102', 'label' => 'Banque 2', 'class' => 5, 'is_active' => true]);
        app(AccountingEntryService::class)
            ->recordManual($autre->id, $this->ventes->id, 90_000, '2026-05-02', 'OD — Autre banque');

        $resultat = $this->taux();

        $this->assertEquals(100, $resultat['taux'], 'Le compte sans releve ne degrade pas le taux...');
        $this->assertEquals(1, $resultat['comptes_sans_releve'], '...mais il est signale.');
    }

    /** Hors exercice, une ligne n'entre pas au calcul. */
    public function test_lines_outside_the_fiscal_year_are_excluded(): void
    {
        $this->encaissement(150_000, '2026-03-10');
        $this->ligneReleve(150_000, '2026-03-12');
        $this->ligneReleve(77_000, '2025-11-20');   // exercice précédent

        $this->assertEquals(2, $this->taux()['lignes']);
    }

    /** L'écran expose réellement le taux dans ses KPI. */
    public function test_the_screen_exposes_the_rate(): void
    {
        $this->encaissement(150_000, '2026-03-10');
        $this->ligneReleve(150_000, '2026-03-12');
        $this->encaissement(40_000, '2026-04-01');

        foreach (['view-comptabilite', 'manage-comptabilite'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('admin', 'web');
        $role->givePermissionTo(['view-comptabilite', 'manage-comptabilite']);

        $user = User::create([
            'name' => 'DG', 'email' => 'dg@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $user->assignRole($role);
        $this->actingAs($user);

        $kpis = Livewire::test(ClotureExercice::class)
            ->set('selectedYear', '2026')
            ->instance()->kpis;

        // 2 lettrées sur 3 lignes (l'encaissement d'avril reste en instance).
        $this->assertEquals(67, $kpis['lettrage']['taux']);
        $this->assertEquals(3, $kpis['lettrage']['lignes']);
    }
}
