<?php

namespace Tests\Feature;

use App\Models\AccountingEntryLine;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Services\AccountingEntryService;
use App\Services\FinancialReportService;
use Database\Seeders\ChartOfAccountsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Ticket 15.21 (A) — SENS NATUREL DES COMPTES DE TIERS AU GRAND LIVRE.
 *
 * `FinancialReportService::isDebitNature` ne classait en nature débitrice un compte de classe 4 que s'il
 * commençait par `41`. Un 409 « Fournisseurs débiteurs » (créance) et un 445 « TVA récupérable » étaient donc
 * lus comme des comptes créditeurs : le grand livre de 409 affichait `closing_balance = -2000` pour 2000 de
 * débit et 0 de crédit. Pire : 419 « Avances et acomptes reçus » (dette) commence par `41` et était lu comme
 * une créance. Aucune erreur, aucun test rouge : seul le signe du solde progressif était faux.
 *
 * ⚠️ PROPOSITIONS COMPTABLES À FAIRE VALIDER PAR LE CABINET FAGUEZ : le tableau `NATURES_ATTENDUES` ci-dessous
 * est LA décision (compte par compte, plan semé). Il est écrit à la main, indépendamment du code, et un test
 * échoue si un compte est ajouté au plan semé sans y figurer.
 */
class NatureComptesTiersTest extends TestCase
{
    use RefreshDatabase;

    /** true = débitrice par nature, false = créditrice. Compte par compte du plan semé (ChartOfAccountsSeeder). */
    private const NATURES_ATTENDUES = [
        '101' => false,     // Capital social
        '131' => false,     // Résultat net (bénéfice)
        '139' => true,      // Résultat net (PERTE) : un résultat négatif est un solde débiteur — corrigé au 15.21
        '221' => true, '241' => true, '244' => true,
        '281' => false,     // Amortissements : contre-compte d'actif, créditeur — corrigé au 15.21
        '313' => true,
        '401' => false,     // Fournisseurs
        '409' => true,      // Fournisseurs débiteurs (créance) — corrigé au 15.21
        '411' => true,      // Clients
        '419' => false,     // Avances et acomptes reçus (dette envers le client) — corrigé au 15.21
        '443' => false,     // TVA facturée (collectée)
        '445' => true,      // TVA récupérable — corrigé au 15.21
        '431' => false,     // Sécurité sociale
        '4472' => false, '4473' => false,
        '521101' => true, '521201' => true, '531' => true,
        '601' => true, '602' => true, '604' => true, '605' => true, '606' => true, '614' => true,
        '621' => true, '624' => true, '628' => true, '65' => true, '657' => true, '661' => true,
        '664' => true, '681' => true,
        '701' => false,
        '73' => false,      // AMBIGU (une variation de stock peut être débitrice ou créditrice) : règle de classe conservée
    ];

    private function ouvrirExercice(): void
    {
        FiscalYear::create([
            'year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert',
        ]);
    }

    private function compte(string $code): ChartOfAccount
    {
        return ChartOfAccount::where('code', $code)->firstOrFail();
    }

    public function test_chaque_compte_du_plan_seme_a_une_nature_decidee_et_le_service_la_respecte(): void
    {
        $this->seed(ChartOfAccountsSeeder::class);

        $tous = ChartOfAccount::pluck('code')->map(fn ($c) => (string) $c)->sort()->values()->all();
        $attendus = collect(array_keys(self::NATURES_ATTENDUES))->map(fn ($c) => (string) $c)->sort()->values()->all();

        // TICKET 15.27 : le seeder importe aussi les 1 332 comptes du CSV SYSCOHADA. Leur nature (débitrice/créditrice) n'est PAS
        // décidée (phase B, cabinet FAGUEZ) : la règle par classe de `natureDebitrice` est fausse pour plusieurs d'entre eux
        // (109, 119, 129, 47x, 48x, 56, 82…). Le garde-fou garde donc son sens sur les comptes de la FERME : tout compte ajouté
        // au plan HORS CSV, sans décision de nature, fait échouer ce test.
        // TICKET 15.27-bis (A3) — GARDE-FOU STRICT. La version 15.27 ne comparait que les comptes HORS CSV : un compte ajouté
        // au semis dont le code existe aussi au CSV (mutation « 2312 ajouté au seeder ») passait inaperçu. On compare donc
        // la liste RÉELLE du semis (`comptesDeLaFerme`) à la liste des natures décidées, sans tenir compte du CSV.
        $ferme = array_map(fn ($c) => (string) $c['code'], ChartOfAccountsSeeder::comptesDeLaFerme());
        $this->assertSame($ferme, array_values(array_unique($ferme)), 'Code en double dans le semis de la ferme.');
        $fermeTriee = $ferme;
        $attendusTries = $attendus;
        sort($fermeTriee, SORT_STRING);
        sort($attendusTries, SORT_STRING);
        $this->assertSame($attendusTries, $fermeTriee, 'Compte du semis de la ferme sans nature décidée (ou nature décidée pour un compte absent du semis) : trancher sa nature dans NATURES_ATTENDUES.');

        $csv = collect(file(base_path('database/data/plan-comptable-syscohada-revise.csv'), FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES))
            ->skip(1)->map(fn ($l) => (string) explode(';', $l, 2)[0])->all();
        $horsCsv = array_values(array_diff($tous, $csv));
        $this->assertSame(array_values(array_diff($attendus, $csv)), $horsCsv, 'Compte ajouté au plan hors CSV sans décision de nature : trancher sa nature.');
        $this->assertSame([], array_values(array_diff($attendus, $tous)), 'Un compte de la ferme a disparu du plan semé.');
        $this->assertCount(1337, $tous, '1 332 comptes du CSV + 5 de la ferme absents du CSV.');

        $codes = $attendus;

        $rapports = app(FinancialReportService::class);

        foreach ($codes as $code) {
            $compte = $this->compte($code);
            $this->assertSame(
                self::NATURES_ATTENDUES[$code],
                $rapports->grandLivre($compte->id, '2026-01-01', '2026-12-31')['is_debit_nature'],
                "Nature du compte {$code} ({$compte->label})"
            );
        }
    }

    public function test_les_sous_comptes_suivent_la_regle_du_plan_en_base(): void
    {
        // Sous-comptes absents du plan semé : la règle suit le compte parent en base (445x récupérable → débiteur,
        // 443x facturée → créditeur, 409x/41x débiteurs, 419x/40x créditeurs). 4456 : sous 445 (récupérable) ;
        // 4457 : hors 445 et hors 443 → créditeur (TVA collectée dans les plans usuels) — AMBIGU, à valider.
        $this->assertTrue(FinancialReportService::natureDebitrice('4456', 4));
        $this->assertFalse(FinancialReportService::natureDebitrice('4457', 4));
        $this->assertTrue(FinancialReportService::natureDebitrice('4451', 4));
        $this->assertFalse(FinancialReportService::natureDebitrice('4431', 4));
        $this->assertTrue(FinancialReportService::natureDebitrice('4091', 4));
        $this->assertFalse(FinancialReportService::natureDebitrice('4011', 4));
        $this->assertTrue(FinancialReportService::natureDebitrice('4111', 4));
        $this->assertFalse(FinancialReportService::natureDebitrice('4191', 4));
        $this->assertFalse(FinancialReportService::natureDebitrice('2811', 2));
        $this->assertTrue(FinancialReportService::natureDebitrice('2411', 2));
    }

    /** @return array<string, ChartOfAccount> */
    private function jeuEcritures(): array
    {
        $this->seed(ChartOfAccountsSeeder::class);
        $this->ouvrirExercice();

        foreach ([['4456', 'TVA récupérable (sous-compte)'], ['4457', 'TVA collectée (sous-compte)']] as [$code, $label]) {
            // Ticket 15.27 : 4456 existe désormais (CSV) ; on le garde tel quel plutôt que de le recréer.
            ChartOfAccount::firstOrCreate(['code' => $code], ['label' => $label, 'class' => 4, 'is_active' => true]);
        }

        $c = fn (string $code) => $this->compte($code)->id;
        $service = app(AccountingEntryService::class);

        // E0 — apport (avant la période : sert de solde d'ouverture).
        $service->record([['account_id' => $c('531'), 'debit' => 10000], ['account_id' => $c('101'), 'credit' => 10000]], '2026-06-15', 'E0');
        // E1 — achat à crédit : 601 HT + TVA récupérable / 401.
        $service->record([['account_id' => $c('601'), 'debit' => 10000], ['account_id' => $c('4456'), 'debit' => 1800], ['account_id' => $c('401'), 'credit' => 11800]], '2026-07-01', 'E1');
        // E2 — règlement partiel du fournisseur.
        $service->record([['account_id' => $c('401'), 'debit' => 3000], ['account_id' => $c('531'), 'credit' => 3000]], '2026-07-05', 'E2');
        // E3 — retour : Débit 401 (part non payée), Débit 409 (part déjà payée) / Crédit 601 et TVA récupérable.
        $service->record([['account_id' => $c('401'), 'debit' => 5000], ['account_id' => $c('409'), 'debit' => 3000], ['account_id' => $c('601'), 'credit' => 7000], ['account_id' => $c('4456'), 'credit' => 1000]], '2026-07-08', 'E3');
        // E4 — vente à crédit : 411 / 701 + TVA collectée.
        $service->record([['account_id' => $c('411'), 'debit' => 5900], ['account_id' => $c('701'), 'credit' => 5000], ['account_id' => $c('4457'), 'credit' => 900]], '2026-07-10', 'E4');
        // E5 — avance reçue d'un client : banque / 419.
        $service->record([['account_id' => $c('521101'), 'debit' => 2000], ['account_id' => $c('419'), 'credit' => 2000]], '2026-07-11', 'E5');
        // E6 — encaissement client.
        $service->record([['account_id' => $c('531'), 'debit' => 1500], ['account_id' => $c('411'), 'credit' => 1500]], '2026-07-12', 'E6');
        // E7 — remboursement fournisseur : banque / 409 (le 409 ne reste débiteur que de 2 000).
        $service->record([['account_id' => $c('521101'), 'debit' => 1000], ['account_id' => $c('409'), 'credit' => 1000]], '2026-07-13', 'E7');
        // E8 — amortissement : 681 / 281.
        $service->record([['account_id' => $c('681'), 'debit' => 400], ['account_id' => $c('281'), 'credit' => 400]], '2026-07-14', 'E8');

        return [];
    }

    /** Somme brute débit/crédit d'un compte, par SQL, sans passer par le service testé. */
    private function sommes(string $code, ?string $avant = null): array
    {
        $q = DB::table('accounting_entry_lines as l')
            ->join('accounting_entries as e', 'e.id', '=', 'l.entry_id')
            ->join('chart_of_accounts as a', 'a.id', '=', 'l.account_id')
            ->where('a.code', $code);

        if ($avant) {
            $q->where('e.entry_date', '<', $avant);
        }

        $r = $q->selectRaw('COALESCE(SUM(l.debit),0) as d, COALESCE(SUM(l.credit),0) as c')->first();

        return [(float) $r->d, (float) $r->c];
    }

    public function test_grand_livre_donne_le_solde_dans_le_sens_naturel_pour_chaque_compte_du_jeu(): void
    {
        $this->jeuEcritures();
        $rapports = app(FinancialReportService::class);

        // Soldes de clôture attendus, écrits à la main depuis les écritures E0..E8 ci-dessus.
        $attendus = [
            '401' => 3800.0,      // C 11800 - D 3000 - D 5000
            '409' => 2000.0,      // D 3000 - C 1000
            '411' => 4400.0,      // D 5900 - C 1500
            '419' => 2000.0,      // C 2000
            '4456' => 800.0,      // D 1800 - C 1000
            '4457' => 900.0,      // C 900
            '531' => 8500.0,      // D 10000 + 1500 - 3000
            '521101' => 3000.0,   // D 2000 + 1000
            '281' => 400.0,       // C 400
        ];

        foreach ($attendus as $code => $solde) {
            $code = (string) $code;
            $compte = $this->compte($code);
            $gl = $rapports->grandLivre($compte->id, '2026-07-01', '2026-07-31');

            $this->assertEquals($solde, $gl['closing_balance'], "Solde de clôture du grand livre de {$code}");

            // Recalcul indépendant : somme SQL brute, signe selon le tableau de natures décidé.
            [$d, $c] = $this->sommes($code);
            $debitrices = ['409', '411', '4456', '531', '521101'];
            $independant = in_array($code, $debitrices, true) ? round($d - $c, 2) : round($c - $d, 2);
            $this->assertEquals($independant, $gl['closing_balance'], "Recalcul indépendant de {$code}");
        }

        // Le cas relevé par l'audit : 409, 2000 de débit net, jamais -2000.
        $gl409 = $rapports->grandLivre($this->compte('409')->id, '2026-07-01', '2026-07-31');
        $this->assertTrue($gl409['is_debit_nature']);
        $this->assertEquals([3000.0, 2000.0], array_column($gl409['lines'], 'running_balance'));

        // Ouverture d'un compte débiteur de classe 5 : 531 avant le 01/07 = 10 000.
        $this->assertEquals(10000.0, $rapports->grandLivre($this->compte('531')->id, '2026-07-01', '2026-07-31')['opening_balance']);
    }

    /**
     * NON-RÉGRESSION : le Bilan et la Balance se lisent au signe réel du solde, jamais à la nature. Ce test fixe
     * leurs chiffres (écrits à la main) : le correctif du sens naturel ne doit en bouger aucun.
     */
    public function test_bilan_et_balance_sont_inchanges_avec_un_409_debiteur(): void
    {
        $this->jeuEcritures();
        $rapports = app(FinancialReportService::class);

        $bilan = $rapports->bilan('2026-12-31');

        $creances = collect($bilan['creances'])->mapWithKeys(fn ($l) => [$l['code'] => $l['balance']])->all();
        $this->assertEquals(['409' => 2000.0, '411' => 4400.0, '4456' => 800.0], $creances);

        $dettes = collect($bilan['dettes'])->mapWithKeys(fn ($l) => [$l['code'] => $l['balance']])->all();
        $this->assertEquals(['401' => 3800.0, '419' => 2000.0, '4457' => 900.0], $dettes);

        $this->assertEquals(11500.0, $bilan['total_tresorerie']);       // 531 : 8500 + 521101 : 3000
        $this->assertEquals(7200.0, $bilan['total_circulant']);         // 2000 + 4400 + 800
        $this->assertEquals(-400.0 + 0.0, $bilan['total_immo']);        // 281 seul : -400 (actif immobilisé net)
        $this->assertEquals(6700.0, $bilan['total_dettes']);
        $this->assertEquals(10000.0, $bilan['total_capitaux']);
        $this->assertEquals(1600.0, $bilan['resultat']);                // produits 5000 - charges (3000 + 400)
        $this->assertEquals(18300.0, $bilan['total_actif']);
        $this->assertEquals(18300.0, $bilan['total_passif']);
        $this->assertTrue($bilan['is_balanced']);

        $balance = $rapports->balanceGenerale('2026-07-01', '2026-07-31');
        $this->assertTrue($balance['is_balanced']);

        $lignes = collect($balance['rows'])->keyBy('code');
        $this->assertEquals(2000.0, $lignes['409']['final_debit']);
        $this->assertEquals(0.0, $lignes['409']['final_credit']);
        $this->assertEquals(3800.0, $lignes['401']['final_credit']);
        $this->assertEquals(2000.0, $lignes['419']['final_credit']);
        $this->assertEquals(800.0, $lignes['4456']['final_debit']);
        $this->assertEquals(900.0, $lignes['4457']['final_credit']);
        $this->assertEquals(400.0, $lignes['281']['final_credit']);

        // Σ des lignes de la base : la somme des soldes finaux débiteurs = celle des créditeurs.
        $this->assertSame(
            (float) AccountingEntryLine::sum('debit'),
            (float) AccountingEntryLine::sum('credit')
        );
    }
}
