<?php

namespace Tests\Feature;

use App\Livewire\Comptabilite\Bilan;
use App\Models\AccountingEntry;
use App\Services\FinancialReportService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket EX2 — RÈGLE R3, À-NOUVEAUX PROVISOIRES (PRD `docs/prd/exercices-comptables.md` § 5, EF3).
 *
 * Tant que N est ouvert et que N+1 existe, l'ouverture de N+1 est CALCULÉE : solde au 31/12/N des classes 1 à 5, plus
 * une ligne « Résultat de l'exercice N (provisoire) » au 131 (bénéfice) ou au 139 (perte). Rien n'est écrit au
 * journal. Elle suit toute écriture passée ensuite en N ; à la clôture, l'à-nouveau écrit donne EXACTEMENT les mêmes
 * chiffres.
 *
 * Exemple R3 calculé à la main : le 20/02/2027, 2026 encore ouvert, le comptable passe en 2026 une dotation de 30 000
 * (681 au débit, 2841 au crédit). L'ouverture provisoire de 2027 porte alors 2841 = 30 000 au crédit et le résultat
 * 2026 provisoire passe de 200 000 à 170 000 ; la clôture écrit 2841 = 30 000 et 131 = 170 000.
 */
class AnouveauxProvisoiresTest extends TestCase
{
    use JeuBasculeExercice;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->preparerComptable();
        Carbon::setTestNow('2027-02-20 09:00:00');
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

    /** @return array<string, float> code => solde net (débit − crédit), résultat provisoire à part sous « provisoire » */
    private function ouverture2027(): array
    {
        $ouverture = $this->service()->ouvertureExercice('2027-01-01');
        $nets = [];
        foreach ($ouverture['comptes'] as $c) {
            if (abs($c['net']) >= 0.01) {
                $nets[$c['code']] = $c['net'];
            }
        }
        ksort($nets);
        if ($ouverture['resultat_provisoire'] !== null) {
            $nets['provisoire '.$ouverture['resultat_provisoire']['code']] = $ouverture['resultat_provisoire']['net'];
        }

        return $nets;
    }

    private function bilan2027(): array
    {
        return $this->service()->bilan('2027-01-31');
    }

    public function test_l_ouverture_provisoire_suit_la_dotation_passee_en_2026_et_la_cloture_ecrit_les_memes_montants(): void
    {
        $this->jeuDuParagraphe5();
        $this->compte('2841', 'Amortissements du matériel', 2);
        $this->compte('681', 'Dotations aux amortissements', 6);

        $ouverture = $this->service()->ouvertureExercice('2027-01-01');
        $this->assertSame('provisoire', $ouverture['mode']);
        $this->assertSame(2026, $ouverture['precedent']);
        $this->assertEquals([
            '101' => -1_000_000.0, '521101' => 1_000_000.0, '531' => 200_000.0, 'provisoire 131' => -200_000.0,
        ], $this->ouverture2027());
        $this->assertSame("Résultat de l'exercice 2026 (provisoire)", $ouverture['resultat_provisoire']['label']);

        // Le 20/02/2027 : dotation de 30 000 passée EN 2026.
        $this->ecrire('2026-12-31', '681', '2841', 30_000, 'Dotation 2026');

        $this->assertEquals([
            '101' => -1_000_000.0, '2841' => -30_000.0, '521101' => 1_000_000.0, '531' => 200_000.0,
            'provisoire 131' => -170_000.0,
        ], $this->ouverture2027(), "l'ouverture provisoire suit l'écriture, sans rien écrire au journal");
        $this->assertSame(0, AccountingEntry::where('source_type', 'ran')->count());

        $avant = $this->bilan2027();
        $this->assertEquals(-30_000.0, $avant['total_immo'], '2841 = 30 000 au crédit');
        $this->assertEquals(1_250_000.0, $avant['total_tresorerie']);
        $this->assertEquals(1_220_000.0, $avant['total_actif']);
        $this->assertEquals(1_170_000.0, $avant['total_capitaux'], '101 + résultat 2026 provisoire de 170 000');
        $this->assertEquals(50_000.0, $avant['resultat']);
        $this->assertEquals(1_220_000.0, $avant['total_passif']);

        $this->cloturer2026();

        // L'à-nouveau écrit : 2841 = 30 000 et 131 = 170 000, les mêmes chiffres.
        $ran = AccountingEntry::with('lines.account')->where('source_type', 'ran')->sole();
        $lignes = [];
        foreach ($ran->lines as $l) {
            $lignes[$l->account->code] = round((float) $l->debit - (float) $l->credit, 2);
        }
        ksort($lignes);
        $this->assertEquals([
            '101' => -1_000_000.0, '131' => -170_000.0, '2841' => -30_000.0, '521101' => 1_000_000.0, '531' => 200_000.0,
        ], $lignes);

        $apres = $this->bilan2027();
        foreach (['total_immo', 'total_tresorerie', 'total_actif', 'total_capitaux', 'resultat', 'total_dettes', 'total_passif'] as $cle) {
            $this->assertEquals($avant[$cle], $apres[$cle], "le Bilan 2027 ne bouge pas à la clôture ({$cle})");
        }
        $this->assertFalse($apres['ouverture']['provisoire']);
        $this->assertSame('anouveau', $this->service()->ouvertureExercice('2027-01-01')['mode']);
    }

    public function test_une_perte_provisoire_va_au_139(): void
    {
        $this->ouvrirExercices();
        $this->planDeLExemple();
        $this->ecrire('2026-01-02', '521101', '101', 1_000_000, 'Apport');
        $this->ecrire('2026-05-10', '605', '521101', 100_000, 'Énergie');

        $ouverture = $this->service()->ouvertureExercice('2027-01-01');
        $this->assertSame('139', $ouverture['resultat_provisoire']['code']);
        $this->assertEquals(100_000.0, $ouverture['resultat_provisoire']['net'], 'perte : solde débiteur');

        $avant = $this->bilan2027();
        $this->assertEquals(900_000.0, $avant['total_actif']);
        $this->assertEquals(900_000.0, $avant['total_capitaux'], '1 000 000 − perte 100 000');
        $this->assertEquals(0.0, $avant['resultat']);
        $this->assertTrue($avant['is_balanced']);

        $this->cloturer2026();

        $apres = $this->bilan2027();
        $this->assertEquals($avant['total_actif'], $apres['total_actif']);
        $this->assertEquals($avant['total_capitaux'], $apres['total_capitaux']);
        $ran = AccountingEntry::with('lines.account')->where('source_type', 'ran')->sole();
        $this->assertEquals(100_000.0, (float) $ran->lines->firstWhere('account.code', '139')->debit);
    }

    public function test_apres_l_etape_2_seule_le_resultat_est_deja_au_131_et_rien_n_est_compte_deux_fois(): void
    {
        $this->jeuDuParagraphe5();

        // Étape 2 faite, étape 3 pas encore : le résultat 2026 est passé au 131 par une vraie écriture.
        Carbon::setTestNow('2027-03-01 09:00:00');
        Livewire::test(\App\Livewire\Comptabilite\ClotureExercice::class)
            ->set('selectedYear', '2026')
            ->call('soldeComptesGestion');

        $ouverture = $this->service()->ouvertureExercice('2027-01-01');
        $this->assertSame('provisoire', $ouverture['mode']);
        $this->assertNull($ouverture['resultat_provisoire'], 'le résultat 2026 est déjà au 131 : pas de seconde ligne');
        $this->assertEquals(1_200_000.0, $this->bilan2027()['total_capitaux']);
        $this->assertEquals(1_250_000.0, $this->bilan2027()['total_actif']);
    }

    public function test_le_bilan_montre_la_ligne_provisoire_et_la_mention(): void
    {
        $this->jeuDuParagraphe5();

        Livewire::test(Bilan::class)
            ->set('asOfDate', '2027-01-31')
            ->assertSee('À-nouveaux provisoires')
            ->assertSee("131 - Résultat de l'exercice 2026 (provisoire)", false)
            ->assertSee("Elle suit toute écriture passée en 2026 ; à la clôture, l'à-nouveau définitif la remplace sans changer aucun chiffre.", false);
    }
}
