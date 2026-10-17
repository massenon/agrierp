<?php

namespace Tests\Feature;

use App\Livewire\Rapports\RapportMensuel;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Services\AccountingEntryService;
use App\Services\FinancialReportService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.10 (Sprint 14) — Rapport Mensuel de Synthèse.
 *
 * L'enjeu de cet écran n'est pas son affichage mais sa COHÉRENCE : un rapport
 * de synthèse qui contredirait l'écran d'origine d'un indicateur serait pire
 * qu'absent. Les tests vérifient donc que chaque valeur correspond exactement
 * à ce que renvoie le point de vérité correspondant.
 */
class RapportMensuelTest extends TestCase
{
    use RefreshDatabase;

    private function account(string $code, string $label, int $class): ChartOfAccount
    {
        return ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $class, 'is_active' => true]);
    }

    private function seedTwoMonths(): void
    {
        FiscalYear::create([
            'year' => now()->year,
            'start_date' => now()->startOfYear()->format('Y-m-d'),
            'end_date' => now()->endOfYear()->format('Y-m-d'),
            'status' => 'ouvert',
        ]);

        $caisse = $this->account('531', 'Caisse', 5);
        $ventes = $this->account('701', 'Ventes', 7);
        $achats = $this->account('601', 'Achats', 6);

        $s = app(AccountingEntryService::class);

        // Mois précédent : CA 790 000, charges 300 000
        $moisPrecedent = now()->startOfMonth()->subMonth()->addDays(5)->format('Y-m-d');
        $s->recordManual($caisse->id, $ventes->id, 790_000, $moisPrecedent, 'OD-0001 — Ventes M-1');
        $s->recordManual($achats->id, $caisse->id, 300_000, $moisPrecedent, 'OD-0002 — Achats M-1');

        // Mois courant : CA 850 000, charges 610 000
        $moisCourant = now()->startOfMonth()->addDays(5)->format('Y-m-d');
        $s->recordManual($caisse->id, $ventes->id, 850_000, $moisCourant, 'OD-0003 — Ventes M');
        $s->recordManual($achats->id, $caisse->id, 610_000, $moisCourant, 'OD-0004 — Achats M');
    }

    public function test_each_indicator_matches_its_own_source_of_truth(): void
    {
        $this->seedTwoMonths();

        $indicateurs = collect(Livewire::test(RapportMensuel::class)->instance()->indicateurs)
            ->keyBy('label');

        $reports = app(FinancialReportService::class);
        $debut = now()->startOfMonth()->format('Y-m-d');
        $fin = now()->endOfMonth()->format('Y-m-d');

        // Chaque valeur doit être EXACTEMENT celle du service qui en fait foi.
        $this->assertEquals(
            $reports->produitsPeriode($debut, $fin),
            $indicateurs["Chiffre d'affaires"]['courant']
        );
        $this->assertEquals(
            $reports->chargesPeriode($debut, $fin),
            $indicateurs['Charges']['courant']
        );
        $this->assertEquals(
            $reports->bilan($fin)['total_tresorerie'],
            $indicateurs['Trésorerie (fin de mois)']['courant']
        );

        // Valeurs métier attendues, recalculées indépendamment.
        $this->assertEquals(850_000.0, $indicateurs["Chiffre d'affaires"]['courant']);
        $this->assertEquals(790_000.0, $indicateurs["Chiffre d'affaires"]['precedent']);
        $this->assertEquals(610_000.0, $indicateurs['Charges']['courant']);
        $this->assertEquals(240_000.0, $indicateurs['Résultat net']['courant']);   // 850 000 − 610 000
        $this->assertEquals(490_000.0, $indicateurs['Résultat net']['precedent']); // 790 000 − 300 000
    }

    /**
     * Le mois précédent doit être une VRAIE période distincte, pas un cumul :
     * les écritures du mois courant ne doivent jamais s'y retrouver.
     */
    public function test_the_previous_month_column_is_a_distinct_period(): void
    {
        $this->seedTwoMonths();

        $indicateurs = collect(Livewire::test(RapportMensuel::class)->instance()->indicateurs)
            ->keyBy('label');

        $this->assertNotEquals(
            $indicateurs["Chiffre d'affaires"]['courant'],
            $indicateurs["Chiffre d'affaires"]['precedent']
        );
        $this->assertEquals(790_000.0, $indicateurs["Chiffre d'affaires"]['precedent']);
    }

    public function test_search_filters_the_indicator_rows(): void
    {
        $this->seedTwoMonths();

        $component = Livewire::test(RapportMensuel::class);
        $total = count($component->instance()->indicateurs);

        $component->set('search', 'Trésorerie');

        $filtres = $component->instance()->indicateurs;

        $this->assertLessThan($total, count($filtres));
        $this->assertCount(1, $filtres);
        $this->assertEquals('Trésorerie (fin de mois)', $filtres[0]['label']);
    }

    public function test_component_renders_read_only(): void
    {
        $this->seedTwoMonths();

        Livewire::test(RapportMensuel::class)
            ->assertOk()
            ->assertSee('Rapport Mensuel de Synthèse')
            ->assertSee('Lecture seule')
            ->assertSet('periode', now()->format('Y-m'));
    }

    /** Une base sans aucune écriture ne doit pas produire d'erreur ni de division par zéro. */
    public function test_an_empty_ledger_yields_zeroes_not_errors(): void
    {
        FiscalYear::create([
            'year' => now()->year,
            'start_date' => now()->startOfYear()->format('Y-m-d'),
            'end_date' => now()->endOfYear()->format('Y-m-d'),
            'status' => 'ouvert',
        ]);

        $indicateurs = collect(Livewire::test(RapportMensuel::class)->instance()->indicateurs)
            ->keyBy('label');

        $this->assertEquals(0.0, $indicateurs["Chiffre d'affaires"]['courant']);
        $this->assertEquals(0.0, $indicateurs['Taux de mortalité']['courant']);
        $this->assertEquals(0.0, $indicateurs['Effectif élevage']['courant']);
    }
}
