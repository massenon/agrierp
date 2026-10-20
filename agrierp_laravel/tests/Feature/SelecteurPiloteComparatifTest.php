<?php

namespace Tests\Feature;

use App\Livewire\Comptabilite\Bilan;
use App\Livewire\Comptabilite\EtatsFinanciers;
use App\Livewire\Shared\BandeauExercice;
use App\Livewire\Shared\SelecteurExercice;
use App\Services\FinancialReportService;
use App\Services\PdfExportService;
use App\Support\ExerciceChoisi;
use Barryvdh\DomPDF\PDF as PdfDocument;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Fusion EX7 + EX8 — LE SÉLECTEUR D'EXERCICE (EX7, EF8) PILOTE LE COMPARATIF N / N-1 (EX8, EF11).
 *
 * L'exercice choisi dans la barre supérieure est la colonne « Exercice N » du Bilan, des onglets Bilan et Compte de
 * Résultat des États financiers et de leurs PDF ; son précédent, à sa clôture, la colonne « Exercice N-1 ». Changer
 * d'exercice au sélecteur change les DEUX colonnes. Un seul point de passage : `App\Support\ExerciceChoisi` — le
 * paramètre `exercice` d'EX8 n'est pas une seconde vérité (une année donnée à la page est CHOISIE), et la date
 * d'arrêté n'a qu'une règle (`ExerciceChoisi::arreteDe`, à l'heure du Bénin ; `FinancialReportService::arreteDeLExercice`
 * y renvoie).
 *
 * Valeurs calculées à la main sur l'exemple du § 5 (`JeuBasculeExercice`), 2026 clôturé, le 31/01/2027 :
 *  - 2027 affiché : N = 2027 au 31/01/2027 (total actif 1 250 000, résultat 50 000) ; N-1 = 2026 au 31/12/2026
 *    (total actif 1 200 000, résultat 200 000) ;
 *  - 2026 affiché : N = 2026 au 31/12/2026 (1 200 000, résultat 200 000, ventes 300 000) ; N-1 : aucun exercice
 *    antérieur — chaque cellule dit « — », jamais 0.
 */
class SelecteurPiloteComparatifTest extends TestCase
{
    use JeuBasculeExercice;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->preparerComptable();
        Carbon::setTestNow('2027-01-31 12:00:00');
        $this->jeuDuParagraphe5();
        $this->cloturer2026();
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    /** Les valeurs des cellules d'une colonne (`data-colonne`), dans l'ordre de la page. */
    private function cellules(string $html, string $colonne): array
    {
        preg_match_all('/data-colonne="'.$colonne.'"[^>]*>(.*?)<\//su', $html, $m);

        return array_map(fn ($t) => trim(strip_tags($t)), $m[1]);
    }

    private function choisirAuSelecteur(int $annee): void
    {
        Livewire::test(SelecteurExercice::class)->call('choisir', $annee);
        $this->assertSame($annee, ExerciceChoisi::annee());
    }

    public function test_le_selecteur_change_les_deux_colonnes_de_l_ecran_bilan(): void
    {
        // Par défaut : l'exercice qui contient le jour (2027).
        $bilan = Livewire::test(Bilan::class);
        $this->assertSame('2027-01-31', $bilan->get('asOfDate'));
        $this->assertSame(2027, $bilan->get('exercice'));
        $html = $bilan->assertSee('2027 — au 31/01/2027')->assertSee('2026 — au 31/12/2026')->html();
        $this->assertContains('1 250 000', $this->cellules($html, 'n'));
        $this->assertContains('1 200 000', $this->cellules($html, 'n1'), 'total actif 2026 en N-1');
        $this->assertNotContains('—', $this->cellules($html, 'n1'));

        // 2026 choisi au sélecteur : 2026 passe en colonne N (à sa clôture), N-1 n'existe pas.
        $this->choisirAuSelecteur(2026);
        $bilan = Livewire::test(Bilan::class);
        $this->assertSame('2026-12-31', $bilan->get('asOfDate'));
        $this->assertSame(2026, $bilan->get('exercice'));
        $html = $bilan->assertSee('2026 — au 31/12/2026')->assertSee('Aucun exercice antérieur')->html();
        $this->assertContains('1 200 000', $this->cellules($html, 'n'), 'total actif 2026 en N');
        $this->assertContains('200 000', $this->cellules($html, 'n'), 'résultat 2026 en N');
        $this->assertNotContains('1 250 000', $this->cellules($html, 'n'));
        $n1 = $this->cellules($html, 'n1');
        $this->assertNotEmpty($n1);
        $this->assertSame(['—'], array_values(array_unique($n1)), 'N-1 inconnu : « — », jamais 0');

        // Et retour à 2027.
        $this->choisirAuSelecteur(2027);
        $this->assertSame('2027-01-31', Livewire::test(Bilan::class)->get('asOfDate'));
    }

    public function test_la_date_d_arrete_du_bilan_est_bornee_a_l_exercice_choisi(): void
    {
        $this->choisirAuSelecteur(2026);
        $bilan = Livewire::test(Bilan::class);
        $this->assertStringContainsString('type="date" min="2026-01-01" max="2026-12-31"', $bilan->html());

        // Une date hors de l'exercice affiché est ramenée à sa borne : N reste 2026.
        $bilan->set('asOfDate', '2027-01-15')->assertSet('asOfDate', '2026-12-31');
        $bilan->set('asOfDate', '2026-06-30')->assertSet('asOfDate', '2026-06-30')->assertSee('2026 — au 30/06/2026');
        $this->assertSame(2026, $bilan->instance()->comparatif['exercice_n']['annee']);
    }

    public function test_le_selecteur_pilote_les_onglets_des_etats_financiers_et_leurs_pdf(): void
    {
        $espion = new class extends PdfExportService
        {
            public array $rendus = [];

            public function render(string $view, array $data, string $title, string $period, string $orientation = 'landscape'): PdfDocument
            {
                $this->rendus[] = ['html' => view($view, $data)->render(), 'periode' => $period];

                return parent::render($view, $data, $title, $period, $orientation);
            }
        };
        $this->app->instance(PdfExportService::class, $espion);

        // 2027 affiché.
        $etats = Livewire::test(EtatsFinanciers::class);
        $this->assertSame('Situation au 31/01/2027 — Exercice 2027', $etats->instance()->situationLabel);
        $this->assertContains('1 200 000', $this->cellules($etats->html(), 'n1'));
        $resultat = $this->cellules($etats->call('switchTab', 'resultat')->html(), 'n');
        $this->assertSame('50 000 F', end($resultat), 'résultat net 2027 en N');
        $etats->call('exportEtatActifPdf');
        $this->assertSame('Situation au 31/01/2027 — Exercice 2027', $espion->rendus[0]['periode']);
        $this->assertContains('200 000', $this->cellules($espion->rendus[0]['html'], 'n1'), 'résultat net 2026 au PDF');

        // 2026 choisi au sélecteur : les deux colonnes changent, à l'écran et au PDF.
        $this->choisirAuSelecteur(2026);
        $espion->rendus = [];
        $etats = Livewire::test(EtatsFinanciers::class);
        $this->assertSame('Situation au 31/12/2026 — Exercice 2026', $etats->instance()->situationLabel);
        $this->assertEquals(1_200_000.0, $etats->instance()->bilan['total_actif']);
        $html = $etats->assertSee('Aucun exercice antérieur')->html();
        $this->assertContains('1 200 000', $this->cellules($html, 'n'));
        $this->assertSame(['—'], array_values(array_unique($this->cellules($html, 'n1'))));
        $html = $etats->call('switchTab', 'resultat')->html();
        $n = $this->cellules($html, 'n');
        $this->assertSame('200 000 F', end($n), 'résultat net 2026, écriture de solde écartée');
        $this->assertContains('300 000', $n, 'ventes 2026');
        $this->assertSame(['—'], array_values(array_unique($this->cellules($html, 'n1'))));

        $etats->call('switchTab', 'bilan')->call('exportEtatActifPdf')->call('switchTab', 'resultat')->call('exportEtatActifPdf');
        $this->assertCount(2, $espion->rendus);
        foreach ($espion->rendus as $rendu) {
            $this->assertSame('Situation au 31/12/2026 — Exercice 2026', $rendu['periode']);
            $this->assertSame(['—'], array_values(array_unique($this->cellules($rendu['html'], 'n1'))), 'N-1 au PDF');
        }
        $this->assertContains('1 200 000', $this->cellules($espion->rendus[0]['html'], 'n'));
    }

    public function test_l_exercice_en_parametre_est_un_choix_et_non_une_seconde_verite(): void
    {
        // Une année donnée à la page est CHOISIE : bandeau, sélecteur et Bilan disent la même année.
        Livewire::test(Bilan::class, ['exercice' => 2026])->assertSet('exercice', 2026);
        $this->assertSame(2026, session(ExerciceChoisi::CLE_SESSION));
        Livewire::test(BandeauExercice::class)
            ->assertSee("Exercice 2026 clôturé — lecture seule. Les saisies se font dans l'exercice 2027.");
        $this->assertSame(2026, Livewire::test(EtatsFinanciers::class)->get('exercice'), 'sans paramètre : l\'exercice choisi');

        // Changée en cours de route : choisie aussi.
        Livewire::test(EtatsFinanciers::class)->set('exercice', 2027)->assertSet('exercice', 2027);
        $this->assertSame(2027, ExerciceChoisi::annee());
        Livewire::test(BandeauExercice::class)->assertDontSee('clôturé — lecture seule');

        // Une année sans exercice enregistré est refusée : la page reste sur l'exercice affiché.
        $bilan = Livewire::test(Bilan::class, ['exercice' => 2025]);
        $bilan->assertSet('exercice', 2027)->assertSet('asOfDate', '2027-01-31');
        $this->assertSame(2027, ExerciceChoisi::annee());
    }

    public function test_une_seule_regle_de_date_d_arrete_a_l_heure_du_benin(): void
    {
        // 23 h 30 à Greenwich le 20/03/2027 = 00 h 30 le 21/03/2027 à Porto-Novo : le jour métier est le 21.
        Carbon::setTestNow(Carbon::parse('2027-03-20 23:30:00', 'UTC'));
        $service = app(FinancialReportService::class);

        $this->assertSame('2027-03-21', ExerciceChoisi::arreteDe(2027));
        $this->assertSame('2027-03-21', $service->arreteDeLExercice(2027), 'EX8 lisait `now()` à l\'heure du serveur');
        $this->assertSame('2027-03-21', ExerciceChoisi::dateArrete(), 'l\'exercice affiché (2027) : même règle');
        $this->assertSame('2026-12-31', $service->arreteDeLExercice(2026));
        $this->assertSame('2025-12-31', $service->arreteDeLExercice(2025), 'année sans exercice : l\'année civile');
        $this->assertSame('2027-03-21', Livewire::test(Bilan::class)->get('asOfDate'));
    }
}
