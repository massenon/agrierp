<?php

namespace Tests\Feature;

use App\Livewire\Comptabilite\Bilan;
use App\Livewire\Comptabilite\EtatsFinanciers;
use App\Models\FiscalYear;
use App\Services\FinancialReportService;
use App\Services\PdfExportService;
use Barryvdh\DomPDF\PDF as PdfDocument;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket EX8 (EF11, PRD `docs/prd/exercices-comptables.md` § 4 et § 7) — BILAN ET COMPTE DE RÉSULTAT N / N-1.
 *
 * Deux colonnes juxtaposées « Exercice N » / « Exercice N-1 » au Bilan et au Compte de résultat (écran Bilan, onglets
 * Bilan et Compte de Résultat des États financiers, et leurs PDF). La colonne N-1 dit « — » quand l'exercice N-1
 * n'existe pas, JAMAIS 0. L'exercice affiché est un paramètre explicite (`exercice` des composants, date d'arrêté du
 * service) ; sans lui, le comportement d'avant.
 *
 * ⚠️ POINT RELEVÉ PAR EX1 : l'étape 2 de la clôture écrit au 31/12/N une écriture `closing` qui solde les classes 6 et 7
 * au 131/139. Lu tel quel, le Compte de résultat d'un exercice clos vaut 0, et son Bilan porte le résultat dans le 131
 * au lieu de « Résultat de l'exercice ». Le Bilan et le Compte de résultat ÉCARTENT cette écriture (les deux côtés : les
 * classes 6-7 ET leur contrepartie 131/139) : le vrai résultat de 2026 reste 200 000, et le Bilan de 2026 au 31/12 reste
 * juste (mêmes totaux).
 *
 * Valeurs calculées à la main sur l'exemple du § 5 (`JeuBasculeExercice`) :
 *  - Bilan 2027 au 31/01/2027 : caisse 250 000, banque 1 000 000, total actif 1 250 000 ; capital 1 000 000, 131
 *    (résultat 2026 reporté) 200 000, résultat 2027 en cours 50 000, total passif 1 250 000 ;
 *  - Bilan 2026 au 31/12/2026 : caisse 200 000 (300 000 − 100 000), banque 1 000 000, total actif 1 200 000 ; capital
 *    1 000 000, 131 : 0 (l'écriture de solde est écartée), résultat de l'exercice 200 000, total passif 1 200 000 ;
 *  - Compte de résultat 2026 : ventes 300 000, achats (605) 100 000, marge 200 000, résultat net 200 000 ;
 *  - Compte de résultat 2027 au 31/01/2027 : ventes 50 000, résultat net 50 000.
 */
class ComparatifNMoinsUnTest extends TestCase
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

    /** La ligne fusionnée d'un compte dans une rubrique du comparatif. */
    private function ligne(array $lignes, string $code): array
    {
        $trouvees = array_values(array_filter($lignes, fn ($l) => $l['code'] === $code && ! ($l['provisoire'] ?? false)));
        $this->assertCount(1, $trouvees, "une seule ligne attendue pour le compte {$code}");

        return $trouvees[0];
    }

    /** Les chiffres du comparatif Bilan 2027 / 2026, mêmes avant et après la clôture de 2026. */
    private function verifierBilanComparatif(bool $provisoire): void
    {
        $c = $this->service()->bilanComparatif('2027-01-31');

        $this->assertSame(['annee' => 2027, 'arrete' => '2027-01-31'], $c['exercice_n']);
        $this->assertSame(2026, $c['exercice_n1']['annee']);
        $this->assertSame('2026-12-31', $c['exercice_n1']['arrete'], 'N-1 est présenté à sa clôture');

        // Colonne N : l'exercice 2027 au 31/01/2027.
        $this->assertEquals(1_250_000.0, $c['n']['total_actif']);
        $this->assertEquals(50_000.0, $c['n']['resultat']);
        $this->assertEquals(1_250_000.0, $c['n']['total_passif']);

        // Colonne N-1 : l'exercice 2026 au 31/12/2026.
        $this->assertEquals(1_200_000.0, $c['n1']['total_actif']);
        $this->assertEquals(1_200_000.0, $c['n1']['total_tresorerie']);
        $this->assertEquals(200_000.0, $c['n1']['resultat'], 'le vrai résultat de 2026, écriture de solde écartée');
        $this->assertEquals(1_000_000.0, $c['n1']['total_capitaux']);
        $this->assertEquals(1_200_000.0, $c['n1']['total_passif']);
        $this->assertTrue($c['n1']['is_balanced']);

        // Lignes juxtaposées.
        $caisse = $this->ligne($c['lignes']['tresorerie'], '531');
        $this->assertEquals([250_000.0, 200_000.0], [$caisse['n'], $caisse['n1']]);
        $banque = $this->ligne($c['lignes']['tresorerie'], '521101');
        $this->assertEquals([1_000_000.0, 1_000_000.0], [$banque['n'], $banque['n1']]);
        $capital = $this->ligne($c['lignes']['capitaux'], '101');
        $this->assertEquals([-1_000_000.0, -1_000_000.0], [$capital['n'], $capital['n1']]);

        // 131 en 2027 : le résultat 2026 reporté (ligne provisoire tant que 2026 est ouvert) ; en 2026 : rien.
        $resultatReporte = array_values(array_filter($c['lignes']['capitaux'], fn ($l) => $l['code'] === '131'));
        $this->assertCount(1, $resultatReporte);
        $this->assertSame($provisoire, (bool) ($resultatReporte[0]['provisoire'] ?? false));
        $this->assertEquals(-200_000.0, $resultatReporte[0]['n']);
        $this->assertEquals(0.0, $resultatReporte[0]['n1'], 'N-1 existe : un compte sans solde y vaut 0, mesuré');
    }

    public function test_bilan_2027_et_2026_juxtaposes_avant_la_cloture_de_2026(): void
    {
        $this->jeuDuParagraphe5();

        $this->verifierBilanComparatif(provisoire: true);
    }

    public function test_bilan_2027_et_2026_juxtaposes_apres_la_cloture_memes_chiffres(): void
    {
        $this->jeuDuParagraphe5();
        $this->cloturer2026();

        $this->verifierBilanComparatif(provisoire: false);
    }

    public function test_compte_de_resultat_2026_vaut_200_000_malgre_l_ecriture_de_solde(): void
    {
        $this->jeuDuParagraphe5();
        $this->cloturer2026();

        // L'écriture de solde existe bien : sans l'écarter, 2026 vaudrait 0.
        $this->assertTrue(\App\Models\AccountingEntry::where('source_type', 'closing')->exists());

        $c = $this->service()->compteResultatComparatif('2027-01-31');
        $this->assertSame(2026, $c['exercice_n1']['annee']);

        $n1 = $c['n1'];
        $this->assertEquals(300_000.0, $n1['ventes']);
        $this->assertEquals(100_000.0, $n1['achats'], '605 est une charge de la classe 60');
        $this->assertEquals(200_000.0, $n1['marge_commerciale']);
        $this->assertEquals(200_000.0, $n1['resultat_net']);

        $this->assertEquals(50_000.0, $c['n']['ventes']);
        $this->assertEquals(50_000.0, $c['n']['resultat_net']);

        // Le Compte de résultat de 2026 lu seul, et le Bilan de 2026 au 31/12 : le résultat est 200 000, le total
        // reste juste.
        $this->assertEquals(200_000.0, $this->service()->compteResultat('2026-12-31')['resultat_net']);
        $bilan2026 = $this->service()->bilan('2026-12-31');
        $this->assertEquals(200_000.0, $bilan2026['resultat']);
        $this->assertSame([], array_values(array_filter($bilan2026['capitaux'], fn ($l) => $l['code'] === '131')));
        $this->assertEquals(1_200_000.0, $bilan2026['total_actif']);
        $this->assertEquals(1_200_000.0, $bilan2026['total_passif']);
    }

    public function test_sans_exercice_n_moins_un_la_colonne_dit_tiret_jamais_zero(): void
    {
        $this->jeuDuParagraphe5();

        // 2026 est le premier exercice : pas de 2025.
        $c = $this->service()->bilanComparatif('2026-06-30');
        $this->assertSame(2026, $c['exercice_n']['annee']);
        $this->assertNull($c['exercice_n1']);
        $this->assertNull($c['n1']);
        foreach ($c['lignes'] as $rubrique => $lignes) {
            foreach ($lignes as $l) {
                $this->assertNull($l['n1'], "{$rubrique} {$l['code']} : inconnu, pas 0");
            }
        }
        $this->assertNull($this->service()->compteResultatComparatif('2026-06-30')['n1']);

        // À l'écran : chaque cellule N-1 vaut « — ».
        $html = Livewire::test(Bilan::class)->set('asOfDate', '2026-06-30')
            ->assertSee('Exercice N')->assertSee('Exercice N-1')
            ->html();
        $this->assertCellulesN1Tiret($html);

        $html = Livewire::test(EtatsFinanciers::class, ['exercice' => 2026])->html();
        $this->assertCellulesN1Tiret($html);
        $html = Livewire::test(EtatsFinanciers::class, ['exercice' => 2026])->call('switchTab', 'resultat')->html();
        $this->assertCellulesN1Tiret($html);
    }

    /** Toutes les cellules marquées `data-colonne="n1"` disent « — ». */
    private function assertCellulesN1Tiret(string $html): void
    {
        preg_match_all('/data-colonne="n1"[^>]*>(.*?)<\//su', $html, $m);
        $this->assertNotEmpty($m[1], 'des cellules N-1 doivent être rendues');
        foreach ($m[1] as $texte) {
            $this->assertSame('—', trim(strip_tags($texte)), 'cellule N-1 sans exercice N-1');
        }
    }

    /** Les valeurs des cellules d'une colonne, dans l'ordre de la page. */
    private function cellules(string $html, string $colonne): array
    {
        preg_match_all('/data-colonne="'.$colonne.'"[^>]*>(.*?)<\//su', $html, $m);

        return array_map(fn ($t) => trim(strip_tags($t)), $m[1]);
    }

    public function test_ecran_bilan_deux_colonnes_et_exercice_en_parametre(): void
    {
        $this->jeuDuParagraphe5();
        $this->cloturer2026();
        Carbon::setTestNow('2027-03-20 09:00:00');

        // Sans paramètre : le comportement d'avant (arrêté au jour même, exercice 2027).
        $defaut = Livewire::test(Bilan::class);
        $this->assertSame('2027-03-20', $defaut->get('asOfDate'));
        $html = $defaut->assertSee('Exercice N')->assertSee('Exercice N-1')
            ->assertSee('2027')->assertSee('au 31/12/2026')->html();
        $n1 = $this->cellules($html, 'n1');
        $this->assertContains('200 000', $n1, 'caisse 2026 et résultat 2026');
        $this->assertContains('1 200 000', $n1, 'total actif / passif 2026');
        $this->assertNotContains('—', $n1, 'N-1 existe : aucun tiret');

        // L'exercice en paramètre (EX7 y branchera son sélecteur) : 2026 arrêté à sa clôture, N-1 = 2025 absent.
        $exercice2026 = Livewire::test(Bilan::class, ['exercice' => 2026]);
        $this->assertSame('2026-12-31', $exercice2026->get('asOfDate'));
        $html = $exercice2026->html();
        $this->assertContains('200 000', $this->cellules($html, 'n'), 'résultat de 2026 dans la colonne N');
        $this->assertCellulesN1Tiret($html);

        // Changer d'exercice en cours de route recale la date d'arrêté.
        $exercice2026->set('exercice', 2027);
        $this->assertSame('2027-03-20', $exercice2026->get('asOfDate'));
    }

    public function test_etats_financiers_bilan_et_compte_de_resultat_en_deux_colonnes(): void
    {
        $this->jeuDuParagraphe5();
        $this->cloturer2026();

        $etats = Livewire::test(EtatsFinanciers::class);
        // Le comportement d'avant reste : `bilan` et `resultat` sont ceux de l'exercice affiché.
        $this->assertEquals(1_250_000.0, $etats->instance()->bilan['total_actif']);
        $this->assertEquals(50_000.0, $etats->instance()->resultat['resultat_net']);

        $html = $etats->assertSee('Exercice N-1')->html();
        $this->assertContains('1 200 000', $this->cellules($html, 'n1'));

        $html = $etats->call('switchTab', 'resultat')->assertSee('Exercice N')->assertSee('Exercice N-1')->html();
        $n = $this->cellules($html, 'n');
        $n1 = $this->cellules($html, 'n1');
        $this->assertSame('50 000 F', end($n), 'résultat net 2027');
        $this->assertSame('200 000 F', end($n1), 'résultat net 2026, écriture de solde écartée');
        $this->assertContains('300 000', $n1, 'ventes 2026');

        // L'exercice en paramètre : 2026 en colonne N.
        $html = Livewire::test(EtatsFinanciers::class, ['exercice' => 2026])->call('switchTab', 'resultat')
            ->assertSee('2026 — au 31/12/2026')->html();
        $n = $this->cellules($html, 'n');
        $this->assertSame('200 000 F', end($n));
    }

    public function test_les_pdf_portent_les_deux_colonnes(): void
    {
        $this->jeuDuParagraphe5();
        $this->cloturer2026();

        $espion = new class extends PdfExportService
        {
            public array $html = [];

            public function render(string $view, array $data, string $title, string $period, string $orientation = 'landscape'): PdfDocument
            {
                $this->html[] = view($view, $data)->render();

                return parent::render($view, $data, $title, $period, $orientation);
            }
        };
        $this->app->instance(PdfExportService::class, $espion);

        Livewire::test(EtatsFinanciers::class)->call('exportEtatActifPdf')
            ->call('switchTab', 'resultat')->call('exportEtatActifPdf');

        [$bilan, $resultat] = $espion->html;
        foreach ([$bilan, $resultat] as $document) {
            $this->assertStringContainsString('Exercice N', $document);
            $this->assertStringContainsString('Exercice N-1', $document);
        }
        $this->assertContains('1 200 000', $this->cellules($bilan, 'n1'), 'total actif 2026 au PDF');
        $this->assertContains('1 250 000', $this->cellules($bilan, 'n'), 'total actif 2027 au PDF');
        $this->assertContains('200 000', $this->cellules($resultat, 'n1'), 'résultat net 2026 au PDF');

        // Sans N-1 : « — » au PDF aussi.
        $espion->html = [];
        Livewire::test(EtatsFinanciers::class, ['exercice' => 2026])->call('exportEtatActifPdf');
        $this->assertCellulesN1Tiret($espion->html[0]);
    }

    public function test_date_d_arrete_d_un_exercice(): void
    {
        $this->ouvrirExercices();
        Carbon::setTestNow('2027-03-20 09:00:00');

        $s = $this->service();
        $this->assertSame('2026-12-31', $s->arreteDeLExercice(2026), 'exercice passé : sa clôture');
        $this->assertSame('2027-03-20', $s->arreteDeLExercice(2027), 'exercice en cours : aujourd\'hui');
        FiscalYear::create(['year' => 2028, 'start_date' => '2028-01-01', 'end_date' => '2028-12-31', 'status' => 'ouvert']);
        $this->assertSame('2028-01-01', $s->arreteDeLExercice(2028), 'exercice à venir : son premier jour');
        $this->assertSame('2025-12-31', $s->arreteDeLExercice(2025), 'année sans exercice enregistré : l\'année civile');
    }
}
