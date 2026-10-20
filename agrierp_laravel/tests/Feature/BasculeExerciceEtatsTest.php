<?php

namespace Tests\Feature;

use App\Actions\RecordDepreciationEntryAction;
use App\Livewire\Comptabilite\BalanceGenerale;
use App\Livewire\Comptabilite\Bilan;
use App\Livewire\Comptabilite\ComptabiliteHub;
use App\Livewire\Comptabilite\EtatsFinanciers;
use App\Livewire\Comptabilite\GrandLivre;
use App\Livewire\Comptabilite\RapprochementBancaire;
use App\Livewire\Rapports\Tresorerie;
use App\Models\AccountingEntry;
use App\Models\AccountingEntryLine;
use App\Models\FixedAsset;
use App\Services\AnouveauInitialService;
use App\Services\FinancialReportService;
use App\Services\ReinitialisationDonneesService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket EX1 — RÈGLE R1 (PRD `docs/prd/exercices-comptables.md` § 5), DÉFAUT C1.
 *
 * Après la clôture, les états cumulaient l'historique depuis l'origine ET l'à-nouveau du 01/01/N+1 : la caisse
 * réelle de 901 592 F s'affichait 1 803 184 F, et le Bilan restait « équilibré » parce que l'erreur était la même des
 * deux côtés. Règle R1 : classes 1 à 5 = ouverture de l'exercice + mouvements de l'exercice ; classes 6 et 7 =
 * mouvements de l'exercice seulement ; ouverture = à-nouveau si l'exercice précédent est clos, calcul R3 sinon ;
 * jamais historique + à-nouveau.
 *
 * Valeurs attendues calculées à la main sur l'exemple du § 5 (`JeuBasculeExercice`), AVANT et APRÈS la clôture de
 * 2026 : mêmes chiffres en provisoire et en définitif.
 */
class BasculeExerciceEtatsTest extends TestCase
{
    use JeuBasculeExercice;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->preparerComptable();
        Carbon::setTestNow('2027-01-31 12:00:00');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function service(): FinancialReportService
    {
        return app(FinancialReportService::class);
    }

    /** @param array<int, array<string, mixed>> $lignes */
    private function ligne(array $lignes, string $code, ?bool $provisoire = null): array
    {
        $trouvees = array_values(array_filter(
            $lignes,
            fn ($l) => $l['code'] === $code && ($provisoire === null || (bool) ($l['provisoire'] ?? false) === $provisoire)
        ));
        $this->assertCount(1, $trouvees, "une seule ligne attendue pour le compte {$code}");

        return $trouvees[0];
    }

    /** Bilan au 31/01/2027, exercice 2027 : les chiffres du § 5, colonne « Attendu ». */
    private function verifierBilan2027(bool $provisoire): void
    {
        $bilan = $this->service()->bilan('2027-01-31');

        $this->assertEquals(250_000.0, $this->ligne($bilan['tresorerie'], '531')['balance'], 'Caisse 531 = 200 000 + 50 000');
        $this->assertEquals(1_000_000.0, $this->ligne($bilan['tresorerie'], '521101')['balance'], 'Banque 521101');
        $this->assertEquals(1_250_000.0, $bilan['total_tresorerie']);
        $this->assertEquals(1_250_000.0, $bilan['total_actif']);
        $this->assertEquals(-1_000_000.0, $this->ligne($bilan['capitaux'], '101')['balance'], 'Capital 101');
        $resultat2026 = $this->ligne($bilan['capitaux'], '131');
        $this->assertEquals(-200_000.0, $resultat2026['balance'], 'Résultat 2026 au 131');
        $this->assertSame($provisoire, (bool) ($resultat2026['provisoire'] ?? false));
        if ($provisoire) {
            $this->assertSame("Résultat de l'exercice 2026 (provisoire)", $resultat2026['label']);
        }
        $this->assertEquals(1_200_000.0, $bilan['total_capitaux']);
        $this->assertEquals(50_000.0, $bilan['resultat'], 'Résultat 2027 en cours');
        $this->assertEquals(1_250_000.0, $bilan['total_passif']);
        $this->assertTrue($bilan['is_balanced']);
        $this->assertSame($provisoire, $bilan['ouverture']['provisoire']);
        $this->assertSame(2027, $bilan['ouverture']['annee']);
    }

    private function verifierBalance2027(bool $provisoire): void
    {
        $balance = $this->service()->balanceGenerale('2027-01-01', '2027-12-31');
        $rows = $balance['rows'];

        $this->assertSame(['101', '131', '521101', '531', '701'], array_column($rows, 'code'));

        $capital = $this->ligne($rows, '101');
        $this->assertEquals([1_000_000.0, 0.0, 0.0, 1_000_000.0], [$capital['opening_credit'], $capital['period_debit'], $capital['period_credit'], $capital['final_credit']]);

        $resultat = $this->ligne($rows, '131');
        $this->assertEquals(200_000.0, $resultat['opening_credit']);
        $this->assertEquals(200_000.0, $resultat['final_credit']);
        $this->assertSame($provisoire, (bool) ($resultat['provisoire'] ?? false));

        $caisse = $this->ligne($rows, '531');
        $this->assertEquals(200_000.0, $caisse['opening_debit'], "ouverture = à-nouveau (ou calcul R3), jamais historique + à-nouveau");
        $this->assertEquals(50_000.0, $caisse['period_debit'], "l'à-nouveau n'est pas un mouvement de la période");
        $this->assertEquals(0.0, $caisse['period_credit']);
        $this->assertEquals(250_000.0, $caisse['final_debit']);

        $this->assertEquals(1_000_000.0, $this->ligne($rows, '521101')['opening_debit']);
        $ventes = $this->ligne($rows, '701');
        $this->assertEquals([0.0, 50_000.0, 50_000.0], [$ventes['opening_credit'], $ventes['period_credit'], $ventes['final_credit']], 'classe 7 : 2027 seulement');

        $this->assertEquals(1_200_000.0, $balance['total_opening_debit']);
        $this->assertEquals(1_200_000.0, $balance['total_opening_credit']);
        $this->assertEquals(50_000.0, $balance['total_period_debit']);
        $this->assertEquals(50_000.0, $balance['total_period_credit']);
        $this->assertEquals(1_250_000.0, $balance['total_final_debit']);
        $this->assertEquals(1_250_000.0, $balance['total_final_credit']);
        $this->assertTrue($balance['is_balanced']);
        $this->assertSame($provisoire, $balance['ouverture']['provisoire']);
    }

    private function verifierGrandLivre2027(): void
    {
        $caisse = $this->service()->grandLivre($this->comptes['531']->id, '2027-01-01', '2027-01-31');
        $this->assertEquals(200_000.0, $caisse['opening_balance']);
        $this->assertCount(1, $caisse['lines'], "la seule vente du 15/01 ; l'à-nouveau est l'ouverture, pas une ligne");
        $this->assertEquals(50_000.0, $caisse['total_debit']);
        $this->assertEquals(250_000.0, $caisse['closing_balance']);

        $resultat = $this->service()->grandLivre($this->comptes['131']->id, '2027-01-01', '2027-12-31');
        $this->assertEquals(200_000.0, $resultat['opening_balance'], '131 créditeur par nature');
        $this->assertEquals(200_000.0, $resultat['closing_balance']);

        $ventes = $this->service()->grandLivre($this->comptes['701']->id, '2027-01-01', '2027-01-31');
        $this->assertEquals(0.0, $ventes['opening_balance'], 'une classe 7 repart de zéro chaque exercice');
        $this->assertEquals(50_000.0, $ventes['closing_balance']);

        // Au milieu de l'exercice : ouverture du 01/02 = à-nouveau + janvier.
        $fevrier = $this->service()->grandLivre($this->comptes['531']->id, '2027-02-01', '2027-02-28');
        $this->assertEquals(250_000.0, $fevrier['opening_balance']);
    }

    private function verifierEtatsFinanciers(bool $provisoire): void
    {
        $etats = Livewire::test(EtatsFinanciers::class)->instance();
        $this->assertEquals(1_250_000.0, $etats->bilan['total_actif']);
        $this->assertEquals(250_000.0, $this->ligne($etats->bilan['tresorerie'], '531')['balance']);
        $this->assertEquals(50_000.0, $etats->resultat['resultat_net'], 'Compte de résultat 2027 : la vente du 15/01 seule');
        $this->assertEquals(50_000.0, $etats->resultat['ventes']);

        $tafire = $etats->tafire;
        $this->assertEquals(1_200_000.0, $tafire['tresorerie_ouverture'], 'trésorerie à l\'ouverture de 2027');
        $this->assertEquals(50_000.0, $tafire['flux_exploitation']);
        $this->assertEquals(0.0, $tafire['flux_financement'], 'le résultat 2026 reporté n\'est pas un financement');
        $this->assertEquals(1_250_000.0, $tafire['tresorerie_cloture']);
        $this->assertTrue($tafire['is_coherent']);

        $hub = Livewire::test(ComptabiliteHub::class)->instance()->kpis;
        $this->assertEquals(1_250_000.0, $hub['total_actif']);
        $this->assertEquals(1_250_000.0, $hub['tresorerie']);
    }

    private function verifierTresorerieEtRapprochement(): void
    {
        $rows = Livewire::test(Tresorerie::class, ['startDate' => '2027-01-01', 'endDate' => '2027-01-31'])->instance()->rows;
        $this->assertSame(['2027-01-15'], array_map(fn ($r) => substr((string) $r['date'], 0, 10), $rows), "l'à-nouveau n'est pas une date d'activité");
        $this->assertEquals([250_000.0, 1_000_000.0, 1_250_000.0], [$rows[0]['caisse'], $rows[0]['banque'], $rows[0]['total']]);

        $rapprochement = Livewire::test(RapprochementBancaire::class)
            ->set('accountId', $this->comptes['521101']->id)
            ->set('startDate', '2027-01-01')
            ->set('endDate', '2027-01-31')
            ->instance()->reconciliation;
        $this->assertEquals(1_000_000.0, $rapprochement['opening_balance']);
        $this->assertSame([], $rapprochement['ledger'], "l'à-nouveau n'est pas une ligne à rapprocher du relevé");
        $this->assertEquals(1_000_000.0, $rapprochement['solde_livre']);
    }

    public function test_les_etats_2027_sont_justes_avant_la_cloture_de_2026_a_nouveaux_provisoires(): void
    {
        $this->jeuDuParagraphe5();

        $this->verifierBilan2027(provisoire: true);
        $this->verifierBalance2027(provisoire: true);
        $this->verifierGrandLivre2027();
        $this->verifierEtatsFinanciers(provisoire: true);
        $this->verifierTresorerieEtRapprochement();

        // 2026 n'est pas touché par 2027 : Bilan au 31/12/2026 (résultat 2026 encore dans les classes 6-7).
        $bilan2026 = $this->service()->bilan('2026-12-31');
        $this->assertEquals(200_000.0, $this->ligne($bilan2026['tresorerie'], '531')['balance']);
        $this->assertEquals(200_000.0, $bilan2026['resultat']);
        $this->assertEquals(1_200_000.0, $bilan2026['total_actif']);
        $this->assertFalse($bilan2026['ouverture']['provisoire'], '2026 est le premier exercice : rien de provisoire');
    }

    public function test_les_etats_2027_sont_identiques_apres_la_cloture_de_2026(): void
    {
        $this->jeuDuParagraphe5();
        $this->cloturer2026();

        // L'à-nouveau a bien été écrit au 01/01/2027 : c'est lui qui, ajouté à l'historique, doublait tout.
        $ran = AccountingEntry::where('source_type', 'ran')->sole();
        $this->assertSame('2027-01-01', $ran->entry_date->format('Y-m-d'));

        $this->verifierBilan2027(provisoire: false);
        $this->verifierBalance2027(provisoire: false);
        $this->verifierGrandLivre2027();
        $this->verifierEtatsFinanciers(provisoire: false);
        $this->verifierTresorerieEtRapprochement();

        // 2026 clos, lu au 31/12/2026 : l'étape 2 a porté le résultat au 131, le total ne change pas.
        $bilan2026 = $this->service()->bilan('2026-12-31');
        $this->assertEquals(200_000.0, $this->ligne($bilan2026['tresorerie'], '531')['balance']);
        $this->assertEquals(-200_000.0, $this->ligne($bilan2026['capitaux'], '131')['balance']);
        $this->assertEquals(0.0, $bilan2026['resultat']);
        $this->assertEquals(1_200_000.0, $bilan2026['total_actif']);
        $this->assertEquals(1_200_000.0, $bilan2026['total_passif']);
    }

    public function test_les_ecrans_disent_a_nouveaux_provisoires_tant_que_2026_est_ouvert(): void
    {
        $this->jeuDuParagraphe5();

        $mention = 'À-nouveaux provisoires';
        $explication = "L'exercice 2026 n'est pas clôturé : l'ouverture de l'exercice 2027 est calculée à partir de ses soldes au 31/12/2026";

        Livewire::test(Bilan::class)->set('asOfDate', '2027-01-31')->assertSee($mention)->assertSee($explication, false)
            ->assertSee("Résultat de l'exercice 2026 (provisoire)");
        Livewire::test(BalanceGenerale::class)->set('periode', 'exercice')->assertSee($mention)->assertSee("Résultat de l'exercice 2026 (provisoire)");
        Livewire::test(GrandLivre::class)->set('accountId', $this->comptes['531']->id)
            ->set('startDate', '2027-01-01')->set('endDate', '2027-01-31')->assertSee($mention);
        Livewire::test(EtatsFinanciers::class)->assertSee($mention);

        // Un état de 2026 n'a rien de provisoire.
        Livewire::test(Bilan::class)->set('asOfDate', '2026-12-31')->assertDontSee($mention);

        $this->cloturer2026();

        Livewire::test(Bilan::class)->set('asOfDate', '2027-01-31')->assertDontSee($mention)
            ->assertDontSee("Résultat de l'exercice 2026 (provisoire)");
        Livewire::test(BalanceGenerale::class)->set('periode', 'exercice')->assertDontSee($mention);
        Livewire::test(GrandLivre::class)->set('accountId', $this->comptes['531']->id)
            ->set('startDate', '2027-01-01')->set('endDate', '2027-01-31')->assertDontSee($mention);
        Livewire::test(EtatsFinanciers::class)->assertDontSee($mention);
    }

    public function test_ouverture_2027_egale_cloture_2026_pour_chaque_compte_de_bilan(): void
    {
        $this->jeuDuParagraphe5();
        $this->cloturer2026();

        // Clôture 2026 calculée à la main (classes 1 à 5, débit − crédit).
        $attendu = ['101' => -1_000_000.0, '131' => -200_000.0, '521101' => 1_000_000.0, '531' => 200_000.0];

        $ouverture = $this->service()->ouvertureExercice('2027-06-30');
        $this->assertSame('anouveau', $ouverture['mode']);
        $this->assertNull($ouverture['resultat_provisoire']);
        $obtenu = [];
        foreach ($ouverture['comptes'] as $c) {
            $obtenu[$c['code']] = $c['net'];
        }
        ksort($obtenu);
        $this->assertEquals($attendu, $obtenu);

        // Contrôle S-T6 : aucun écart.
        $this->assertEquals([[
            'exercice' => 2027, 'precedent' => 2026, 'statut_precedent' => 'cloture', 'ecarts' => [],
        ]], $this->service()->controleAnouveaux());
    }

    public function test_le_controle_s_t6_signale_un_a_nouveau_qui_ne_reprend_pas_la_cloture(): void
    {
        $this->jeuDuParagraphe5();
        $this->cloturer2026();

        // L'à-nouveau de la caisse est altéré en base (écriture rendue déséquilibrée, à dessein) : 180 000 au lieu de 200 000.
        $ran = AccountingEntry::where('source_type', 'ran')->sole();
        AccountingEntryLine::where('entry_id', $ran->id)->where('account_id', $this->comptes['531']->id)->update(['debit' => 180_000]);

        $controle = $this->service()->controleAnouveaux();
        $this->assertSame([['code' => '531', 'libelle' => 'Caisse', 'cloture' => 200_000.0, 'ouverture' => 180_000.0]], $controle[0]['ecarts']);

        // Et l'API de cohérence le sert au poste du comptable.
        $jeton = auth()->user()->createToken('POSTE-COMPTA', ['*'], now()->addDays(90))->plainTextToken;
        $this->app['auth']->forgetGuards();
        $reponse = $this->withHeader('Authorization', 'Bearer '.$jeton)
            ->getJson('/api/sync/coherence?depuis=2027-01-01')
            ->assertOk()
            ->json('anouveaux');
        $this->assertSame('531', $reponse[0]['ecarts'][0]['code']);
        $this->assertEquals(200_000, $reponse[0]['ecarts'][0]['cloture']);
        $this->assertEquals(180_000, $reponse[0]['ecarts'][0]['ouverture']);
    }

    public function test_le_controle_des_a_nouveaux_n_est_pas_servi_a_un_compte_sans_la_comptabilite(): void
    {
        $this->jeuDuParagraphe5();
        $caissier = \App\Models\User::create([
            'name' => 'Caissier', 'username' => 'caisse-bascule', 'email' => 'caisse-bascule@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $caissier->assignRole('caissier');
        $jeton = $caissier->createToken('POSTE-CAISSE', ['*'], now()->addDays(90))->plainTextToken;
        $this->app['auth']->forgetGuards();

        $this->withHeader('Authorization', 'Bearer '.$jeton)
            ->getJson('/api/sync/coherence?depuis=2027-01-01')
            ->assertOk()
            ->assertJsonPath('anouveaux', null);
    }

    public function test_la_dotation_2027_part_de_l_a_nouveau_et_non_du_double(): void
    {
        $this->ouvrirExercices();
        $this->planDeLExemple();
        $this->compte('241', 'Matériel et outillage agricole', 2);
        $this->compte('281', 'Amortissements des immobilisations corporelles', 2);
        $this->compte('681', 'Dotations aux amortissements', 6);

        // Bien de 120 000 sur 2 ans (annuité 60 000), acquis le 01/01/2026, payé par la banque.
        $this->ecrire('2026-01-01', '521101', '101', 500_000, 'Apport');
        $this->ecrire('2026-01-01', '241', '521101', 120_000, 'Acquisition broyeur');
        FixedAsset::create([
            'code' => 'IMMO-001', 'label' => 'Broyeur', 'account_code' => '241',
            'acquisition_date' => '2026-01-01', 'acquisition_value' => 120_000, 'residual_value' => 0,
            'duration_years' => 2, 'method' => 'lineaire', 'status' => 'en_service', 'is_active' => true, 'is_capitalized' => true,
        ]);

        // Dotation 2026 arrêtée au 01/12/2026 : 11 mois (`diffInMonths`) → 60 000 × 11 / 12 = 55 000.
        $this->assertEquals(55_000.0, (float) app(RecordDepreciationEntryAction::class)->execute('2026-12-01')->lines->sum('debit'));

        $this->cloturer2026();

        // 01/06/2027 : 17 mois → 85 000 de cumul théorique ; déjà comptabilisé 55 000 (l'à-nouveau du 281, une
        // seule fois) → 30 000 à doter. Avec historique + à-nouveau (110 000), rien n'aurait été doté.
        $this->assertEquals(30_000.0, app(RecordDepreciationEntryAction::class)->montantADoter('2027-06-01'));
    }

    public function test_q7_les_reprises_d_avant_le_premier_exercice_deviennent_un_a_nouveau_initial_idempotent(): void
    {
        $this->ouvrirExercices();
        $this->planDeLExemple();
        $this->compte('241', 'Matériel et outillage agricole', 2);

        // Une reprise datée AVANT le premier exercice (impossible par `record()` : écrite en base, comme une
        // écriture déplacée au Journal avant le correctif d'EX5).
        DB::statement('PRAGMA defer_foreign_keys = ON');
        $id = (string) Str::uuid();
        DB::table('accounting_entries')->insert([
            'id' => $id, 'fiscal_year_id' => $this->exercice2026->id, 'entry_date' => '2025-06-30',
            'reference' => 'Reprise du broyeur', 'source_type' => 'manual', 'is_locked' => false, 'is_active' => true,
            'created_at' => now(), 'updated_at' => now(),
        ]);
        foreach ([['241', 400_000, 0], ['101', 0, 400_000]] as [$code, $d, $c]) {
            DB::table('accounting_entry_lines')->insert([
                'id' => (string) Str::uuid(), 'entry_id' => $id, 'account_id' => $this->comptes[$code]->id,
                'debit' => $d, 'credit' => $c, 'created_at' => now(), 'updated_at' => now(),
            ]);
        }

        $service = app(AnouveauInitialService::class);
        $this->assertSame(1, $service->regulariser(), 'une écriture d\'à-nouveau initial');
        $this->assertSame(0, $service->regulariser(), 'idempotent : rien la seconde fois');

        $initial = AccountingEntry::where('source_type', 'ran')->whereNull('source_id')->sole();
        $this->assertSame('2026-01-01', $initial->entry_date->format('Y-m-d'));
        $this->assertSame("À-nouveau initial — reprises antérieures au 01/01/2026", $initial->reference);

        // Comptée UNE fois : l'ouverture du premier exercice vient de l'à-nouveau initial, pas de l'historique en plus.
        $bilan = $this->service()->bilan('2026-03-31');
        $this->assertEquals(400_000.0, $this->ligne($bilan['immo'], '241')['balance']);
        $this->assertEquals(-400_000.0, $this->ligne($bilan['capitaux'], '101')['balance']);
        $this->assertEquals(400_000.0, $bilan['total_actif']);
        $balance = $this->service()->balanceGenerale('2026-01-01', '2026-12-31');
        $this->assertEquals(400_000.0, $this->ligne($balance['rows'], '241')['opening_debit']);
        $this->assertEquals(0.0, $balance['total_period_debit'], "l'à-nouveau initial est l'ouverture, pas un mouvement");
    }

    public function test_la_reinitialisation_efface_l_a_nouveau_avec_le_journal_et_garde_les_reprises_hors_comptabilite(): void
    {
        $this->jeuDuParagraphe5();
        $this->cloturer2026();
        FixedAsset::create([
            'code' => 'IMMO-REPRISE', 'label' => 'Bâtiment repris', 'account_code' => '231',
            'acquisition_date' => '2020-01-01', 'acquisition_value' => 900_000, 'residual_value' => 0,
            'duration_years' => 20, 'method' => 'lineaire', 'status' => 'en_service', 'is_active' => true, 'is_capitalized' => false,
        ]);

        app(ReinitialisationDonneesService::class)->executer();

        $this->assertSame(0, AccountingEntry::count(), 'à-nouveau compris');
        $this->assertSame(1, FixedAsset::count(), 'la reprise d\'antériorité est un paramètre de base, gardée');
        $this->assertSame(0, app(AnouveauInitialService::class)->regulariser(), 'aucune écriture antérieure : rien à reprendre');
        $bilan = $this->service()->bilan('2027-01-31');
        $this->assertEquals(0.0, $bilan['total_actif']);
        $this->assertSame([], array_merge(...array_column($this->service()->controleAnouveaux(), 'ecarts')));
    }
}
