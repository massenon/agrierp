<?php

namespace Tests\Feature;

use App\Livewire\Comptabilite\ClotureExercice;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\User;
use App\Services\AccountingEntryService;
use Illuminate\Support\Carbon;
use Livewire\Livewire;

/**
 * Tickets EX1 / EX2 — l'exemple du PRD `docs/prd/exercices-comptables.md` § 5, calculé à la main.
 *
 * | Date       | Écriture                 | Débit              | Crédit             |
 * |------------|--------------------------|--------------------|--------------------|
 * | 02/01/2026 | Apport                   | 521101 : 1 000 000 | 101 : 1 000 000    |
 * | 10/03/2026 | Vente comptant           | 531 : 300 000      | 701 : 300 000      |
 * | 15/04/2026 | Énergie payée en caisse  | 605 : 100 000      | 531 : 100 000      |
 * | 15/01/2027 | Vente comptant           | 531 : 50 000       | 701 : 50 000       |
 *
 * L'étape 2 (solde des comptes de gestion au 31/12/2026) et l'à-nouveau du 01/01/2027 (étape 3) sont passés par
 * le VRAI assistant de clôture (`cloturer2026()`), jamais écrits à la main.
 */
trait JeuBasculeExercice
{
    /** @var array<string, ChartOfAccount> */
    protected array $comptes = [];

    protected FiscalYear $exercice2026;

    protected FiscalYear $exercice2027;

    protected function preparerComptable(): User
    {
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $comptable = User::create([
            'name' => 'Comptable', 'username' => 'compta-bascule', 'email' => 'compta-bascule@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $comptable->assignRole('comptable');
        $this->actingAs($comptable);

        return $comptable;
    }

    protected function compte(string $code, string $libelle, int $classe): ChartOfAccount
    {
        return $this->comptes[$code] = ChartOfAccount::create([
            'code' => $code, 'label' => $libelle, 'class' => $classe, 'is_active' => true,
        ]);
    }

    /** Les deux exercices ouverts en même temps (N et N+1), comme au début de 2027. */
    protected function ouvrirExercices(): void
    {
        $this->exercice2026 = FiscalYear::firstOrCreate(['year' => 2026], [
            'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert',
        ]);
        $this->exercice2027 = FiscalYear::firstOrCreate(['year' => 2027], [
            'start_date' => '2027-01-01', 'end_date' => '2027-12-31', 'status' => 'ouvert',
        ]);
    }

    protected function planDeLExemple(): void
    {
        $this->compte('101', 'Capital social', 1);
        $this->compte('131', 'Résultat net : bénéfice', 1);
        $this->compte('139', 'Résultat net : perte', 1);
        $this->compte('521101', 'Banque principale', 5);
        $this->compte('531', 'Caisse', 5);
        $this->compte('605', 'Autres achats (énergie)', 6);
        $this->compte('701', 'Ventes de produits', 7);
    }

    protected function ecrire(string $date, string $debit, string $credit, float $montant, string $libelle): void
    {
        app(AccountingEntryService::class)->record(
            lines: [
                ['account_id' => $this->comptes[$debit]->id, 'debit' => $montant, 'credit' => 0],
                ['account_id' => $this->comptes[$credit]->id, 'debit' => 0, 'credit' => $montant],
            ],
            entryDate: $date,
            reference: 'OD-'.$date.' — '.$libelle,
            sourceType: 'manual',
        );
    }

    /** Le jeu du § 5, sans l'étape 2 ni l'à-nouveau (2026 encore ouvert). */
    protected function jeuDuParagraphe5(): void
    {
        $this->ouvrirExercices();
        $this->planDeLExemple();
        $this->ecrire('2026-01-02', '521101', '101', 1_000_000, 'Apport');
        $this->ecrire('2026-03-10', '531', '701', 300_000, 'Vente comptant');
        $this->ecrire('2026-04-15', '605', '531', 100_000, 'Énergie payée en caisse');
        $this->ecrire('2027-01-15', '531', '701', 50_000, 'Vente comptant');
    }

    /**
     * Clôture de 2026 par le vrai parcours (étapes 1, 2 et 3), le 15/03/2027 — après l'échéance, comme à la ferme.
     * L'heure du test est rendue à l'appelant ensuite.
     */
    protected function cloturer2026(): void
    {
        $avant = Carbon::getTestNow();
        Carbon::setTestNow('2027-03-15 10:00:00');

        Livewire::test(ClotureExercice::class)
            ->set('selectedYear', '2026')
            ->call('confirmStep1')
            ->call('soldeComptesGestion')
            ->call('confirmCloture');

        $this->assertSame('cloture', $this->exercice2026->fresh()->status, 'la clôture de 2026 doit avoir abouti');
        Carbon::setTestNow($avant);
    }
}
