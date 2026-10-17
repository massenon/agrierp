<?php

namespace Tests\Feature;

use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Services\FinancialReportService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Ticket 15.29 — LE JEU D'ÉCRITURES DU GRAND LIVRE DU POSTE, REJOUÉ SUR LE VRAI SERVICE.
 *
 * ⚠️⚠️ Le Grand Livre du poste Flutter (ticket F0.85) est vérifié contre des chiffres calculés À LA MAIN
 * (`test/grand_livre_poste_test.dart`). Rien ne prouvait que ces chiffres sont CEUX DU SERVEUR : ce
 * test écrit exactement le même jeu et exige exactement les mêmes littéraux de
 * `FinancialReportService::grandLivre`. Si l'un des deux côtés change de règle, l'autre test rougit.
 *
 * Ce que ce test ne peut PAS prouver (sqlite en mémoire) : l'insensibilité aux accents de la recherche
 * (`utf8mb4_unicode_ci` sur MySQL, pas sur sqlite) et l'ordre de deux pièces créées à la MÊME seconde
 * (le serveur ne le définit pas : ici elles sont insérées dans l'ordre de leurs identifiants, comme le
 * fait le poste en dernier recours).
 */
class GrandLivreJeuDuPosteTest extends TestCase
{
    use RefreshDatabase;

    /** @var array<string, string> code => id de compte */
    private array $comptes = [];

    private string $exercice;

    protected function setUp(): void
    {
        parent::setUp();

        $this->exercice = FiscalYear::create([
            'year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert',
        ])->id;

        foreach ([
            ['531', 'Caisse', 5], ['101', 'Capital', 1], ['601', 'Achats', 6], ['401', 'Fournisseurs', 4],
            ['701', 'Ventes', 7], ['4456', 'TVA récupérable', 4], ['4457', 'TVA collectée', 4],
            ['681', 'Dotations', 6], ['281', 'Amortissements', 2], ['409', 'Fournisseurs débiteurs', 4],
            ['411', 'Clients', 4],
        ] as [$code, $libelle, $classe]) {
            // `firstOrCreate` : certaines migrations (15.19, 15.20) posent déjà 409 / 419 sur une base vide.
            $this->comptes[$code] = ChartOfAccount::firstOrCreate(
                ['code' => $code],
                ['label' => $libelle, 'class' => $classe, 'is_active' => true]
            )->id;
        }

        // Même jeu que `jeu()` du test Flutter. Colonnes : clé, date, instant de création, référence,
        // compte débité, compte crédité, montant.
        foreach ([
            ['e01', '2026-01-10', '2026-01-10 08:00:00', 'OD-2026-0001 — Capital initial', '531', '101', 100000],
            ['e02', '2026-02-15', '2026-02-15 08:00:00', 'OD-2026-0002 — Achat aliment', '601', '401', 40000],
            ['e03', '2026-02-28', '2026-02-28 08:00:00', 'OD-2026-0009 — Vente veille', '531', '701', 3000],
            ['e04', '2026-03-01', '2026-03-01 08:00:00', 'OD-2026-0006 — Vente début de mois', '531', '701', 2000],
            ['e06', '2026-03-02', '2026-03-02 10:00:05', 'OD-2026-0003 — Vente comptant', '531', '701', 25000],
            ['e07', '2026-03-02', '2026-03-02 10:00:05', 'OD-2026-0007 — Frais divers', '601', '531', 500],
            // ⚠️ e05 est insérée APRÈS e06 et e07 : seule la date de création peut la remettre en tête.
            ['e05', '2026-03-02', '2026-03-02 10:00:01', 'OD-2026-0004 — Règlement fournisseur', '401', '531', 15000],
            ['e08', '2026-03-10', '2026-03-10 08:00:00', 'OD-2026-0008 — TVA', '4456', '4457', 1800],
            ['e09', '2026-03-12', '2026-03-12 08:00:00', 'OD-2026-0010 — Dotation', '681', '281', 600],
            ['e10', '2026-03-20', '2026-03-20 08:00:00', 'OD-2026-0005 — Avance fournisseur', '409', '531', 5000],
            ['e11', '2026-03-31', '2026-03-31 08:00:00', 'OD-2026-0011 — Vente fin de mois', '531', '701', 1000],
            ['e12', '2026-04-01', '2026-04-01 08:00:00', 'OD-2026-0012 — Vente après période', '531', '701', 7000],
        ] as [$cle, $date, $creeLe, $reference, $debit, $credit, $montant]) {
            $id = (string) Str::uuid();
            DB::table('accounting_entries')->insert([
                'id' => $id, 'fiscal_year_id' => $this->exercice, 'entry_date' => $date,
                'reference' => $reference, 'is_locked' => false, 'is_active' => true,
                'created_at' => $creeLe, 'updated_at' => $creeLe,
            ]);
            DB::table('accounting_entry_lines')->insert([
                ['id' => (string) Str::uuid(), 'entry_id' => $id, 'account_id' => $this->comptes[$debit],
                    'debit' => $montant, 'credit' => 0, 'created_at' => $creeLe, 'updated_at' => $creeLe],
                ['id' => (string) Str::uuid(), 'entry_id' => $id, 'account_id' => $this->comptes[$credit],
                    'debit' => 0, 'credit' => $montant, 'created_at' => $creeLe, 'updated_at' => $creeLe],
            ]);
        }
    }

    private function livre(string $code, string $debut = '2026-03-01', string $fin = '2026-03-31', ?string $recherche = null): array
    {
        return app(FinancialReportService::class)->grandLivre($this->comptes[$code], $debut, $fin, $recherche);
    }

    /** @return array<int, float> */
    private function soldes(array $livre): array
    {
        return array_map(fn ($l) => $l['running_balance'], $livre['lines']);
    }

    public function test_531_debiteur_memes_chiffres_que_le_poste(): void
    {
        $g = $this->livre('531');

        $this->assertTrue($g['is_debit_nature']);
        $this->assertEquals(103000.0, $g['opening_balance']);
        $this->assertEquals([105000.0, 90000.0, 115000.0, 114500.0, 109500.0, 110500.0], $this->soldes($g));
        $this->assertEquals(28000.0, $g['total_debit']);
        $this->assertEquals(20500.0, $g['total_credit']);
        $this->assertEquals(110500.0, $g['closing_balance']);
        $this->assertSame(
            ['OD-2026-0006', 'OD-2026-0004', 'OD-2026-0003', 'OD-2026-0007', 'OD-2026-0005', 'OD-2026-0011'],
            array_column($g['lines'], 'reference')
        );
        $this->assertSame('Vente début de mois', $g['lines'][0]['label']);
    }

    public function test_701_401_101_crediteurs_memes_chiffres_que_le_poste(): void
    {
        $v = $this->livre('701');
        $this->assertFalse($v['is_debit_nature']);
        $this->assertEquals(3000.0, $v['opening_balance']);
        $this->assertEquals([5000.0, 30000.0, 31000.0], $this->soldes($v));
        $this->assertEquals([0.0, 28000.0, 31000.0], [$v['total_debit'], $v['total_credit'], $v['closing_balance']]);

        $f = $this->livre('401');
        $this->assertEquals(40000.0, $f['opening_balance']);
        $this->assertEquals([25000.0], $this->soldes($f));
        $this->assertEquals([15000.0, 0.0, 25000.0], [$f['total_debit'], $f['total_credit'], $f['closing_balance']]);

        $c = $this->livre('101');
        $this->assertEquals(100000.0, $c['opening_balance']);
        $this->assertSame([], $c['lines']);
        $this->assertEquals([0.0, 0.0, 100000.0], [$c['total_debit'], $c['total_credit'], $c['closing_balance']]);
    }

    public function test_natures_particulieres_memes_chiffres_que_le_poste(): void
    {
        $this->assertEquals([5000.0], $this->soldes($this->livre('409')));
        $this->assertTrue($this->livre('409')['is_debit_nature']);
        $this->assertEquals([1800.0], $this->soldes($this->livre('4456')));
        $this->assertTrue($this->livre('4456')['is_debit_nature']);
        $this->assertEquals([1800.0], $this->soldes($this->livre('4457')));
        $this->assertFalse($this->livre('4457')['is_debit_nature']);
        $this->assertEquals([600.0], $this->soldes($this->livre('281')));
        $this->assertFalse($this->livre('281')['is_debit_nature']);
        $this->assertEquals(40000.0, $this->livre('601')['opening_balance']);
        $this->assertEquals([40500.0], $this->soldes($this->livre('601')));
    }

    public function test_bornes_et_recherche_memes_chiffres_que_le_poste(): void
    {
        // Début EXCLU de l'ouverture, fin INCLUSE.
        $un = $this->livre('531', '2026-03-02', '2026-03-02');
        $this->assertEquals(105000.0, $un['opening_balance']);
        $this->assertEquals([90000.0, 115000.0, 114500.0], $this->soldes($un));

        $avantFin = $this->livre('531', '2026-03-01', '2026-03-30');
        $this->assertEquals([105000.0, 90000.0, 115000.0, 114500.0, 109500.0], $this->soldes($avantFin));

        // Début après fin : aucune ligne, ouverture calculée avant le début.
        $inverse = $this->livre('531', '2026-03-31', '2026-03-01');
        $this->assertSame([], $inverse['lines']);
        $this->assertEquals(109500.0, $inverse['opening_balance']);

        // Recherche : le solde progressif ne cumule QUE les lignes filtrées, à partir de l'ouverture.
        $vente = $this->livre('531', '2026-03-01', '2026-03-31', 'VENTE');
        $this->assertEquals([105000.0, 130000.0, 131000.0], $this->soldes($vente));
        $this->assertEquals([28000.0, 0.0, 131000.0], [$vente['total_debit'], $vente['total_credit'], $vente['closing_balance']]);

        $piece = $this->livre('531', '2026-03-01', '2026-03-31', 'od-2026-0011');
        $this->assertSame('Vente fin de mois', $piece['lines'][0]['label']);
    }

    public function test_compte_sans_ecriture_est_a_zero_cote_serveur(): void
    {
        // Côté serveur un compte sans écriture donne 0 ; le poste, lui, affiche « — » (il ne SAIT pas).
        // Ce test documente l'écart d'AFFICHAGE voulu : aucune règle comptable n'est en jeu.
        $g = $this->livre('411');

        $this->assertSame([], $g['lines']);
        $this->assertEquals([0.0, 0.0, 0.0, 0.0], [$g['opening_balance'], $g['total_debit'], $g['total_credit'], $g['closing_balance']]);
    }
}
