<?php

namespace Tests\Feature;

use App\Livewire\Comptabilite\BalanceGenerale;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Services\FinancialReportService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Ticket F0.86 (item 9, T3) — LE JEU D'ÉCRITURES DE LA BALANCE DU POSTE, REJOUÉ SUR LE VRAI SERVICE.
 *
 * ⚠️⚠️ La Balance Générale du poste Flutter est vérifiée contre des chiffres calculés À LA MAIN
 * (`test/balance_poste_test.dart`). Ce test écrit exactement le même jeu et exige exactement les mêmes
 * littéraux de `FinancialReportService::balanceGenerale`. Si l'un des deux côtés change de règle,
 * l'autre test rougit. Aucun code serveur n'est modifié par ce ticket.
 *
 * Hors de ce jeu (propres au poste, sans équivalent serveur) : journal vide ou incomplet (« — »), ligne
 * sur un compte absent du plan reçu, écart de 0,01 obtenu avec des montants à trois décimales (les
 * colonnes `decimal` du serveur les arrondiraient à l'écriture).
 */
class BalanceJeuDuPosteTest extends TestCase
{
    use RefreshDatabase;

    /** @var array<string, string> code => id de compte */
    private array $comptes = [];

    protected function setUp(): void
    {
        parent::setUp();

        $exercice = FiscalYear::create([
            'year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert',
        ])->id;

        foreach ([
            ['531', 'Caisse', 5], ['101', 'Capital', 1], ['601', 'Achats', 6], ['401', 'Fournisseurs', 4],
            ['701', 'Ventes', 7], ['411', 'Clients', 4], ['521', 'Banque', 5], ['5212', 'Mobile Money', 5],
            ['585', 'Virements de fonds', 5], ['681', 'Dotations', 6], ['281', 'Amortissements', 2],
            ['419', 'Clients créditeurs', 4],
        ] as [$code, $libelle, $classe]) {
            // `firstOrCreate` : certaines migrations posent déjà des comptes sur une base vide.
            $this->comptes[$code] = ChartOfAccount::firstOrCreate(
                ['code' => $code],
                ['label' => $libelle, 'class' => $classe, 'is_active' => true]
            )->id;
        }

        // Même jeu que `jeu()` du test Flutter, inséré dans le même désordre.
        foreach ([
            ['2026-03-26', '531', '585', 3000],
            ['2026-04-01', '531', '701', 7000],
            ['2026-01-10', '531', '101', 100000],
            ['2026-03-20', '601', '5212', 2500],
            ['2026-03-01', '531', '701', 2000],
            ['2026-02-15', '601', '401', 40000],
            ['2026-02-20', '531', '521', 8000],
            ['2026-03-10', '411', '701', 10000.40],
            ['2026-04-02', '681', '281', 600],
            ['2026-02-28', '531', '701', 3000],
            ['2026-03-15', '531', '411', 4000.15],
            ['2026-02-01', '521', '531', 8000],
            ['2026-03-02', '401', '531', 15000],
            ['2026-03-25', '585', '531', 3000],
            ['2026-03-31', '531', '701', 1000],
        ] as [$date, $debit, $credit, $montant]) {
            $id = (string) Str::uuid();
            DB::table('accounting_entries')->insert([
                'id' => $id, 'fiscal_year_id' => $exercice, 'entry_date' => $date,
                'reference' => 'OD — '.$date, 'is_locked' => false, 'is_active' => true,
                'created_at' => $date.' 08:00:00', 'updated_at' => $date.' 08:00:00',
            ]);
            DB::table('accounting_entry_lines')->insert([
                ['id' => (string) Str::uuid(), 'entry_id' => $id, 'account_id' => $this->comptes[$debit],
                    'debit' => $montant, 'credit' => 0, 'created_at' => $date, 'updated_at' => $date],
                ['id' => (string) Str::uuid(), 'entry_id' => $id, 'account_id' => $this->comptes[$credit],
                    'debit' => 0, 'credit' => $montant, 'created_at' => $date, 'updated_at' => $date],
            ]);
        }
    }

    /** @return array<string, array<int, float>> code => [ouvD, ouvC, mvtD, mvtC, finD, finC] */
    private function parCode(array $balance): array
    {
        $lignes = [];
        foreach ($balance['rows'] as $r) {
            $lignes[$r['code']] = array_map('floatval', [
                $r['opening_debit'], $r['opening_credit'], $r['period_debit'],
                $r['period_credit'], $r['final_debit'], $r['final_credit'],
            ]);
        }

        return $lignes;
    }

    /** @return array<int, float> */
    private function totaux(array $b): array
    {
        return [
            $b['total_opening_debit'], $b['total_opening_credit'], $b['total_period_debit'],
            $b['total_period_credit'], $b['total_final_debit'], $b['total_final_credit'],
        ];
    }

    public function test_mars_2026_memes_lignes_que_le_poste(): void
    {
        $b = app(FinancialReportService::class)->balanceGenerale('2026-03-01', '2026-03-31');

        $this->assertSame(['101', '401', '411', '5212', '531', '585', '601', '701'], array_column($b['rows'], 'code'));
        $this->assertEquals([
            '101' => [0, 100000, 0, 0, 0, 100000],
            '401' => [0, 40000, 15000, 0, 0, 25000],
            '411' => [0, 0, 10000.40, 4000.15, 6000.25, 0],
            '5212' => [0, 0, 0, 2500, 0, 2500],
            '531' => [103000, 0, 10000.15, 18000, 95000.15, 0],
            '585' => [0, 0, 3000, 3000, 0, 0],
            '601' => [40000, 0, 2500, 0, 42500, 0],
            '701' => [0, 3000, 0, 13000.40, 0, 16000.40],
        ], $this->parCode($b));
    }

    public function test_mars_2026_memes_totaux_et_ecart_que_le_poste(): void
    {
        $b = app(FinancialReportService::class)->balanceGenerale('2026-03-01', '2026-03-31');

        $this->assertEquals([143000, 143000, 40500.55, 40500.55, 143500.40, 143500.40], $this->totaux($b));
        $this->assertEquals(0.0, $b['ecart']);
        $this->assertTrue($b['is_balanced']);
    }

    public function test_bornes_jour_de_debut_veille_et_jour_de_fin(): void
    {
        $service = app(FinancialReportService::class);

        $premier = $this->parCode($service->balanceGenerale('2026-03-01', '2026-03-01'));
        $this->assertEquals(103000.0, $premier['531'][0]);
        $this->assertEquals(2000.0, $premier['531'][2]);

        $veille = $this->parCode($service->balanceGenerale('2026-02-28', '2026-02-28'));
        $this->assertEquals([0, 0, 0, 3000, 0, 3000], $veille['701']);

        $dernier = $this->parCode($service->balanceGenerale('2026-03-31', '2026-03-31'));
        $this->assertEquals(1000.0, $dernier['701'][3]);
        $this->assertEquals(15000.40, $dernier['701'][1]);
    }

    public function test_exercice_2026_memes_chiffres_que_le_poste(): void
    {
        $b = app(FinancialReportService::class)->balanceGenerale('2026-01-01', '2026-12-31');
        $lignes = $this->parCode($b);

        $this->assertSame(
            ['101', '281', '401', '411', '521', '5212', '531', '585', '601', '681', '701'],
            array_column($b['rows'], 'code')
        );
        $this->assertEquals([0, 0, 8000, 8000, 0, 0], $lignes['521']);
        $this->assertEquals([0, 0, 600, 0, 600, 0], $lignes['681']);
        $this->assertEquals([0, 0, 0, 600, 0, 600], $lignes['281']);
        $this->assertEquals([0, 0, 128000.15, 26000, 102000.15, 0], $lignes['531']);
        $this->assertEquals([0, 0, 207100.55, 207100.55, 151100.40, 151100.40], $this->totaux($b));
    }

    public function test_bornes_du_composant_mois_entier_et_exercice_ouvert(): void
    {
        // Même règle que `DonneesComptabilite.bornesBalance` du poste : le mois va jusqu'au DERNIER jour.
        Carbon::setTestNow('2026-03-15 10:00:00');
        try {
            $composant = new BalanceGenerale;
            $composant->periode = 'mois';
            $this->assertSame(['2026-03-01', '2026-03-31'], $composant->periodBounds());

            $composant->periode = 'exercice';
            $this->assertSame(['2026-01-01', '2026-12-31'], $composant->periodBounds());
            $this->assertSame('Exercice complet — 2026', $composant->periodLabel);
        } finally {
            Carbon::setTestNow();
        }
    }
}
