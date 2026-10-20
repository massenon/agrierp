<?php

namespace Tests\Feature;

use App\Actions\ReopenFiscalYearAction;
use App\Exceptions\EcritureVerrouilleeException;
use App\Livewire\Comptabilite\ClotureExercice;
use App\Livewire\Comptabilite\JournalComptable;
use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\User;
use App\Services\AccountingEntryService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket EX4 (PRD exercices comptables, EF4) — LA CLÔTURE GARDÉE.
 *
 * Constat du 20/10/2026 : l'étape 3 (`confirmCloture`) n'avait aucun garde. Elle clôturait un exercice dont l'échéance
 * n'était pas passée (Q2 : refusé), sans que les étapes 1 et 2 soient faites, alors que N-1 était encore ouvert, et
 * finissait en erreur 500 sur un à-nouveau déséquilibré (`UnbalancedAccountingEntryException`). L'étape 2 n'exigeait
 * même pas le droit de clôturer. Après la clôture, l'à-nouveau de N+1 se modifiait et s'archivait au Journal.
 *
 * Exercice 2026, écritures (calculées à la main) :
 *   02/01  Apport            D 521101 1 000 000 / C 101 1 000 000
 *   10/03  Vente comptant    D 531      300 000 / C 701   300 000
 *   15/04  Énergie en caisse D 605      100 000 / C 531   100 000
 * Étape 2 au 31/12 : D 701 300 000 / C 605 100 000, C 131 200 000 (2 comptes soldés, résultat 200 000).
 * À-nouveau 2027 : D 521101 1 000 000, D 531 200 000 / C 101 1 000 000, C 131 200 000.
 */
class ClotureGardeeTest extends TestCase
{
    use PreparationExercices;
    use RefreshDatabase;

    private FiscalYear $exercice2026;

    protected function setUp(): void
    {
        parent::setUp();

        $this->preparerDecor('2027-03-15 10:00:00');
        $this->exercice2026 = $this->exercice(2026);

        $service = app(AccountingEntryService::class);
        $service->recordManual($this->comptes['521101']->id, $this->comptes['101']->id, 1_000_000, '2026-01-02');
        $service->recordManual($this->comptes['531']->id, $this->comptes['701']->id, 300_000, '2026-03-10');
        $service->recordManual($this->comptes['605']->id, $this->comptes['531']->id, 100_000, '2026-04-15');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function ecran()
    {
        return Livewire::test(ClotureExercice::class)->set('tab', 'annuelle')->set('selectedYear', '2026');
    }

    private function assertToujoursOuvert(): void
    {
        $this->assertSame('ouvert', $this->exercice2026->fresh()->status);
        $this->assertSame(0, AccountingEntry::where('source_type', 'ran')->count(), 'aucun à-nouveau ne doit être écrit');
        $this->assertSame(0, AccountingEntry::where('fiscal_year_id', $this->exercice2026->id)->where('is_locked', true)->count());
    }

    // ═══════════════════ Les quatre gardes de l'étape 3 ═══════════════════

    public function test_la_cloture_est_refusee_avant_l_echeance(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-12-20 10:00:00', 'Africa/Porto-Novo'));

        $this->ecran()
            ->call('confirmStep1')
            ->call('soldeComptesGestion')
            ->assertSee("L'exercice 2026 ne peut être clôturé qu'après son échéance du 31/12/2026, à partir du 01/01/2027.")
            ->call('confirmCloture')
            ->assertDispatched('toast', message: "L'exercice 2026 ne peut être clôturé qu'après son échéance du 31/12/2026, à partir du 01/01/2027.", type: 'error');

        $this->assertToujoursOuvert();
    }

    public function test_la_cloture_est_refusee_sans_l_etape_1(): void
    {
        $this->ecran()
            ->call('soldeComptesGestion')
            ->call('confirmCloture')
            ->assertDispatched('toast', message: "Étape 1 non confirmée : marquez les travaux d'inventaire de 2026 comme terminés avant de clôturer.", type: 'error');

        $this->assertToujoursOuvert();
    }

    public function test_la_cloture_est_refusee_sans_l_etape_2(): void
    {
        $this->ecran()
            ->call('confirmStep1')
            ->call('confirmCloture')
            ->assertDispatched('toast', message: "Étape 2 non faite : 2 compte(s) de charges ou de produits de 2026 restent à solder. Lancez « Calculer et Solder » avant de clôturer.", type: 'error');

        $this->assertToujoursOuvert();
    }

    /** Une écriture de gestion passée APRÈS l'étape 2 rouvre un solde : l'étape 2 n'est plus faite. */
    public function test_une_charge_passee_apres_l_etape_2_la_rend_a_refaire(): void
    {
        $ecran = $this->ecran()->call('confirmStep1')->call('soldeComptesGestion');
        app(AccountingEntryService::class)->recordManual($this->comptes['605']->id, $this->comptes['531']->id, 30_000, '2026-12-20');

        $ecran->call('confirmCloture')
            ->assertDispatched('toast', message: "Étape 2 non faite : 1 compte(s) de charges ou de produits de 2026 restent à solder. Lancez « Calculer et Solder » avant de clôturer.", type: 'error');

        $this->assertToujoursOuvert();
    }

    public function test_la_cloture_est_refusee_tant_que_n_moins_1_est_ouvert(): void
    {
        $this->exercice(2025);

        $this->ecran()
            ->call('confirmStep1')
            ->call('soldeComptesGestion')
            ->call('confirmCloture')
            ->assertDispatched('toast', message: "L'exercice 2025 est encore ouvert : clôturez-le avant l'exercice 2026.", type: 'error');

        $this->assertToujoursOuvert();
    }

    /**
     * Un compte HORS des classes 1 à 7 (classe 8, HAO) porte un solde : l'étape 2 ne solde que 6 et 7, l'à-nouveau des
     * classes 1 à 5 ne s'équilibre plus. Avant EX4 : `UnbalancedAccountingEntryException`, erreur 500.
     * 531 : 300 000 − 100 000 − 50 000 = 150 000 D ; 521101 : 1 000 000 D ; 101 : 1 000 000 C ; 131 (étape 2, classes 6
     * et 7 seulement) : 200 000 C. Débit 1 150 000, crédit 1 200 000.
     */
    public function test_un_a_nouveau_desequilibre_est_refuse_avec_son_motif_jamais_une_erreur_500(): void
    {
        $hao = ChartOfAccount::create(['code' => '81', 'label' => 'Valeurs comptables des cessions', 'class' => 8, 'is_active' => true]);
        app(AccountingEntryService::class)->recordManual($hao->id, $this->comptes['531']->id, 50_000, '2026-06-30');

        $this->ecran()
            ->call('confirmStep1')
            ->call('soldeComptesGestion')
            ->call('confirmCloture')
            ->assertDispatched('toast', message: "L'à-nouveau de l'exercice 2027 serait déséquilibré (débit 1 150 000 F, crédit 1 200 000 F) : les comptes de bilan de 2026 ne s'équilibrent pas. Corrigez l'écart au Journal Comptable avant de clôturer.", type: 'error');

        $this->assertToujoursOuvert();
    }

    public function test_l_etape_2_exige_le_droit_de_cloturer(): void
    {
        $caissier = User::create([
            'name' => 'Caisse', 'username' => 'caisse-cl', 'email' => 'caisse-cl@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $caissier->assignRole('caissier');

        Livewire::actingAs($caissier)->test(ClotureExercice::class)
            ->set('selectedYear', '2026')
            ->call('soldeComptesGestion')
            ->assertForbidden();

        $this->assertSame(0, AccountingEntry::where('source_type', 'closing')->count());
    }

    // ═══════════════════ Clôture admise ═══════════════════

    /** 2027 a déjà été ouvert par la tâche du 1er janvier : la clôture le reprend, sans doublon. */
    public function test_la_cloture_admise_reprend_l_exercice_deja_ouvert(): void
    {
        $this->exercice(2027);

        $this->ecran()->call('confirmStep1')->call('soldeComptesGestion')->call('confirmCloture')
            ->assertDispatched('toast', message: 'Exercice 2026 clôturé avec succès — exercice 2027 ouvert.', type: 'success');

        $this->assertSame('cloture', $this->exercice2026->fresh()->status);
        $this->assertSame(1, FiscalYear::where('year', 2027)->count());
        $ran = AccountingEntry::with('lines')->where('source_type', 'ran')->sole();
        $this->assertEquals(1_200_000, $ran->lines->sum('debit'));
        $this->assertEquals(1_200_000, $ran->lines->sum('credit'));
    }

    // ═══════════════════ L'à-nouveau verrouillé ═══════════════════

    private function cloturer(): AccountingEntry
    {
        $this->ecran()->call('confirmStep1')->call('soldeComptesGestion')->call('confirmCloture');
        $this->assertSame('cloture', $this->exercice2026->fresh()->status);

        return AccountingEntry::where('source_type', 'ran')->sole();
    }

    public function test_l_a_nouveau_ne_se_modifie_pas_au_journal(): void
    {
        $ran = $this->cloturer();
        $avant = $ran->lines()->orderBy('debit')->get(['account_id', 'debit', 'credit'])->toArray();
        $message = "L'écriture d'à-nouveau de l'exercice 2027 est verrouillée : elle ne se modifie ni ne s'archive. Pour la corriger, rouvrez l'exercice 2026.";

        Livewire::test(JournalComptable::class)
            ->call('editEntry', $ran->id)
            ->assertDispatched('toast', message: $message, type: 'error');

        // Le formulaire forcé (propriétés publiques) ne passe pas non plus : le service refuse.
        Livewire::test(JournalComptable::class)
            ->set('editingId', $ran->id)
            ->set('entryDate', '2027-01-01')
            ->set('label', 'Tentative')
            ->set('debitAccountId', $this->comptes['531']->id)
            ->set('creditAccountId', $this->comptes['101']->id)
            ->set('amount', 5)
            ->call('saveEntry')
            ->assertDispatched('toast', message: $message, type: 'error');

        $this->assertSame($avant, $ran->fresh()->lines()->orderBy('debit')->get(['account_id', 'debit', 'credit'])->toArray());

        $this->expectException(EcritureVerrouilleeException::class);
        app(AccountingEntryService::class)->updateManual($ran, $this->comptes['531']->id, $this->comptes['101']->id, 5, '2027-01-01');
    }

    public function test_l_a_nouveau_ne_s_archive_pas_au_journal_ni_par_un_poste(): void
    {
        $ran = $this->cloturer();

        Livewire::test(JournalComptable::class)
            ->call('archiveEntry', $ran->id)
            ->assertDispatched('toast', message: "L'écriture d'à-nouveau de l'exercice 2027 est verrouillée : elle ne se modifie ni ne s'archive. Pour la corriger, rouvrez l'exercice 2026.", type: 'error');
        $this->assertTrue($ran->fresh()->is_active);

        // Le poste n'écrit jamais au journal : un envoi qui archiverait l'à-nouveau est ignoré (référentiel).
        $reponse = $this->envoyer(['accounting_entries' => [['id' => $ran->id, 'is_active' => false]]])->assertOk();
        $this->assertGreaterThanOrEqual(1, $reponse->json('referentiels_ignored'));
        $this->assertTrue($ran->fresh()->is_active);
    }

    /** La réouverture 15.53 continue de marcher : contre-passation de l'à-nouveau, puis nouvelle clôture. */
    public function test_la_reouverture_reste_possible_et_la_contre_passation_est_verrouillee_aussi(): void
    {
        $ran = $this->cloturer();

        app(ReopenFiscalYearAction::class)->execute($this->exercice2026->fresh());

        $this->assertSame('ouvert', $this->exercice2026->fresh()->status);
        $contrePassation = AccountingEntry::where('source_type', 'ran_reversal')->where('source_id', $ran->id)->sole();

        Livewire::test(JournalComptable::class)
            ->call('archiveEntry', $contrePassation->id)
            ->assertDispatched('toast', type: 'error');
        $this->assertTrue($contrePassation->fresh()->is_active);

        // Nouvelle clôture : les étapes restent faites (aucune charge nouvelle), un nouvel à-nouveau est passé.
        $this->ecran()->call('confirmCloture')
            ->assertDispatched('toast', message: 'Exercice 2026 clôturé avec succès — exercice 2027 ouvert.', type: 'success');
        $this->assertSame(2, AccountingEntry::where('source_type', 'ran')->count());
    }
}
