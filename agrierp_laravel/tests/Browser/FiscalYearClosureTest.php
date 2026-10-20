<?php

namespace Tests\Browser;

use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\User;
use App\Services\AccountingEntryService;
use Illuminate\Foundation\Testing\DatabaseMigrations;
use Laravel\Dusk\Browser;
use Tests\DuskTestCase;

/**
 * 🔴→✅ TICKET 14.28 — PARCOURS REELLEMENT EXECUTE POUR LA PREMIERE FOIS.
 * Il echouait des sa premiere assertion : ecrit sans jamais tourner, il
 * cherchait le bandeau « OUVERT » sur l'onglet « Cloture Periodique », ouvert
 * par defaut, alors que tout le bloc de cloture annuelle vit dans l'autre
 * onglet. Il ne parcourait pas davantage les 3 etapes de l'assistant : il
 * pressait directement le bouton final. Corrige et etendu au cycle complet,
 * verrouillage ET ouverture de l'exercice suivant compris.
 *
 * Ticket 13.1 — Parcours critique 5/8 (Document 07 §4) : Clôture
 * d'exercice. Exécution complète, vérification qu'une tentative de
 * saisie sur l'exercice clos échoue côté serveur MÊME SI L'UI ÉTAIT
 * CONTOURNÉE DIRECTEMENT (requête HTTP directe).
 *
 * La partie "exécution complète via l'UI" est déjà couverte de façon
 * équivalente et plus rigoureuse par le test Feature réel
 * `tests/Feature/ClotureExerciceTest.php` (ticket 10.6, cycle complet
 * solde→clôture→verrouillage→nouvel exercice, exécuté directement contre
 * le service sans dépendre d'un navigateur). Ce test Dusk se concentre
 * sur le point que Document 07 §4 souligne spécifiquement et qu'un test
 * Feature seul ne prouve pas : que le blocage tient MÊME EN CONTOURNANT
 * l'interface, via une requête directe simulée dans le navigateur.
 */
class FiscalYearClosureTest extends DuskTestCase
{
    use DatabaseMigrations;

    public function test_closure_ui_completes_and_locks_year(): void
    {
        $this->seed();
        $comptable = User::where('email', 'compta@olouwachegoun.bj')->firstOrFail();

        $year = FiscalYear::firstOrCreate(
            ['year' => now()->year],
            ['start_date' => now()->startOfYear(), 'end_date' => now()->endOfYear(), 'status' => 'ouvert']
        );

        $this->browse(function (Browser $browser) use ($comptable, $year) {
            $browser->loginAs($comptable)
                // ⚠️ `?selectedYear=` etait INERTE : `$selectedYear` n'est pas une
                // propriete `#[Url]`, `mount()` la renseigne seul. Le parametre
                // donnait l'illusion de piloter l'ecran sans rien piloter.
                ->visit('/cloture-exercice')
                // ⚠️ L'onglet par defaut est « Cloture Periodique » : sans ce clic,
                // le bandeau « OUVERT » et l'assistant annuel ne sont pas dans le
                // DOM du tout. C'est la raison exacte de l'echec « Did not see
                // expected text [OUVERT] » — l'ecran allait bien, le parcours
                // regardait le mauvais onglet.
                ->press('@tab-annuelle')
                ->waitForText('OUVERT', 5)
                ->assertSee("EXERCICE {$year->year} — OUVERT")

                // Assistant parcouru dans son ORDRE REEL (Document 07 §4 :
                // « execution complete »), pas seulement son dernier bouton.
                ->press('@cloture-step1')
                ->waitForText('Confirmé le', 10)
                ->press('@cloture-step2')
                ->pause(1500)

                ->press('@cloture-step3')
                ->waitForText('réouverture exceptionnelle journalisée', 5)
                ->press('@cloture-confirm')
                ->waitForText('clôturé avec succès', 20)
                // ⚠️ L'ecran BASCULE volontairement sur l'exercice N+1 apres la
                // cloture (ticket 14.2) : afficher encore l'exercice qu'on vient
                // de clore contredirait le message de succes. Le parcours suit
                // donc l'ecran plutot que de supposer qu'il reste en place.
                ->waitForText('EXERCICE '.($year->year + 1).' — OUVERT', 10)
                // Retour d'un exercice en arriere : l'exercice clos doit
                // apparaitre verrouille, en lecture seule.
                ->press('@year-prev')
                // Ticket 14.49 (audit de fidelite) : le badge disait « CLÔTURÉ »,
                // le prototype dit « CLOS ». Le libellé exact fait partie de ce qui
                // se preserve a l identique — c est l ecran qui a ete aligne, et ce
                // test suivait l ancien libelle.
                ->waitForText("EXERCICE {$year->year} — CLOS", 10)
                ->assertSee('Cet exercice est clôturé.');
        });

        $year->refresh();
        $this->assertEquals('cloture', $year->status);
        $this->assertNotNull($year->closed_at);

        // L'exercice suivant est ouvert par la cloture — la contrepartie qui
        // rend le verrouillage acceptable : on ne bloque pas la saisie du jour.
        $suivant = FiscalYear::where('year', $year->year + 1)->first();
        $this->assertNotNull($suivant, "La cloture doit ouvrir l'exercice suivant.");
        $this->assertEquals('ouvert', $suivant->status);
    }

    /**
     * Le point spécifiquement souligné par Document 07 §4 : le blocage
     * serveur tient même si l'UI est contournée. `AccountingEntryService`
     * (ticket 10.6) rejette toute écriture dont la date tombe dans un
     * exercice clos via `ClosedFiscalYearException` — testé ici au
     * niveau service directement (équivalent fonctionnel d'une requête
     * directe qui shunterait le JavaScript du formulaire), déjà couvert
     * de façon unitaire par
     * `ClotureExerciceTest::test_posting_into_a_closed_fiscal_year_is_rejected_server_side`
     * — répété ici pour rester dans le même parcours documenté que
     * Document 07 §4, pas dupliqué par accident.
     */
    public function test_posting_to_closed_year_fails_even_bypassing_the_ui(): void
    {
        $this->seed();

        FiscalYear::create([
            'year' => now()->year - 1,
            'start_date' => now()->subYear()->startOfYear(),
            'end_date' => now()->subYear()->endOfYear(),
            'status' => 'cloture',
            'closed_at' => now(),
        ]);

        $treasury = ChartOfAccount::where('class', 5)->first()
            ?? ChartOfAccount::create(['code' => '531', 'label' => 'Caisse', 'class' => 5, 'is_active' => true]);
        $sales = ChartOfAccount::where('class', 7)->first()
            ?? ChartOfAccount::create(['code' => '701', 'label' => 'Ventes', 'class' => 7, 'is_active' => true]);

        $this->expectException(\App\Exceptions\ClosedFiscalYearException::class);

        app(AccountingEntryService::class)->recordManual(
            $treasury->id,
            $sales->id,
            5000,
            now()->subYear()->format('Y-m-d')
        );
    }
}
