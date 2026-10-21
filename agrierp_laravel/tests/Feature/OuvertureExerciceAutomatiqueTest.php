<?php

namespace Tests\Feature;

use App\Exceptions\NoOpenFiscalYearException;
use App\Livewire\Comptabilite\ClotureExercice;
use App\Models\AccountingEntry;
use App\Models\AuditLog;
use App\Models\FiscalYear;
use App\Models\Notification;
use App\Models\Sale;
use App\Models\User;
use App\Services\AccountingEntryService;
use Carbon\Carbon;
use Illuminate\Console\Scheduling\Schedule;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket EX3 (PRD exercices comptables, R2 / EF2, défaut C2) — L'EXERCICE N+1 EXISTE AU 1er JANVIER SANS ATTENDRE LA
 * CLÔTURE DE N.
 *
 * Constat du 20/10/2026 : N+1 n'était créé que par la clôture de N (`ClotureExercice::confirmCloture`) ou par
 * l'assistant de démarrage. Le 10/01/2027, une vente en caisse et une dépense finissaient en erreur 500
 * (`NoOpenFiscalYearException`), et la clôture se fait d'ordinaire en mars, après le bilan.
 *
 * Trois chemins, un seul point d'ouverture (`OuvertureExerciceService`) :
 *  - la tâche planifiée du 01/01 à 00:00, heure du Bénin (`agrierp:ouvrir-exercice`) ;
 *  - le FILET : la première saisie datée de N+1 crée N+1 avant tout refus, si la tâche n'a pas tourné ;
 *  - le bouton « Ouvrir l'exercice 2027 » de l'écran Clôture, à partir du 1er décembre (`close-fiscal-year`).
 * Jamais N+2 tant que N est ouvert, jamais plus de deux exercices ouverts, jamais de doublon.
 */
class OuvertureExerciceAutomatiqueTest extends TestCase
{
    use PreparationExercices;
    use RefreshDatabase;

    private const VENTE_31 = 'e3000000-0000-4000-8000-000000000031';

    private const VENTE_01 = 'e3000000-0000-4000-8000-000000000001';

    private const VENTE_02 = 'e3000000-0000-4000-8000-000000000002';

    private const DEPENSE_01 = 'e3000000-0000-4000-8000-0000000000d1';

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    // ═══════════════════ La tâche planifiée ═══════════════════

    public function test_la_tache_est_planifiee_le_1er_janvier_a_minuit_heure_du_benin(): void
    {
        $this->preparerDecor('2026-12-15 10:00:00');

        $taches = collect(app(Schedule::class)->events())
            ->filter(fn ($e) => str_contains((string) $e->command, 'agrierp:ouvrir-exercice'));

        $this->assertCount(1, $taches, 'une seule tâche « agrierp:ouvrir-exercice » doit être planifiée');
        $tache = $taches->first();
        $this->assertSame('0 0 1 1 *', $tache->expression, 'le 1er janvier à 00:00');
        $this->assertSame('Africa/Porto-Novo', $tache->timezone, 'à l’heure du Bénin, jamais à l’heure UTC du serveur');
    }

    public function test_la_tache_du_1er_janvier_ouvre_l_exercice_suivant(): void
    {
        $this->preparerDecor('2027-01-01 00:00:30');
        $this->exercice(2026);

        $this->artisan('agrierp:ouvrir-exercice')->assertSuccessful();

        $nouveau = FiscalYear::where('year', 2027)->first();
        $this->assertNotNull($nouveau, 'la tâche du 01/01/2027 doit créer l’exercice 2027');
        $this->assertSame('ouvert', $nouveau->status);
        $this->assertSame('2027-01-01', $nouveau->start_date->format('Y-m-d'));
        $this->assertSame('2027-12-31', $nouveau->end_date->format('Y-m-d'));
        $this->assertSame('ouvert', FiscalYear::where('year', 2026)->value('status'), '2026 reste ouvert : rien n’est clôturé');
        $this->assertTrue(AuditLog::where('action', 'fiscal_year.opened_auto')->exists(), 'l’ouverture laisse sa trace d’audit');
    }

    public function test_la_tache_relancee_ne_cree_aucun_doublon(): void
    {
        $this->preparerDecor('2027-01-01 00:00:30');
        $this->exercice(2026);

        $this->artisan('agrierp:ouvrir-exercice')->assertSuccessful();
        $this->artisan('agrierp:ouvrir-exercice')->assertSuccessful();

        $this->assertSame(1, FiscalYear::where('year', 2027)->count());
        $this->assertSame(2, FiscalYear::count());
    }

    // ═══════════════════ Le filet (cron absent) ═══════════════════

    public function test_le_filet_ouvre_l_exercice_a_la_premiere_vente_du_2_janvier_sans_tache(): void
    {
        $this->preparerDecor('2027-01-02 10:00:00');
        $this->exercice(2026);
        $this->stockDeMais(10, '2026-11-02 08:00:00');

        $reponse = $this->envoyer(['sales' => [$this->venteDuPoste(self::VENTE_02, '2027-01-02T09:00:00+01:00')]])->assertOk();

        $this->assertSame([self::VENTE_02], $reponse->json('sales.accepted'), json_encode($reponse->json('sales.rejected')));
        $exercice2027 = FiscalYear::where('year', 2027)->first();
        $this->assertNotNull($exercice2027, 'la première vente datée de 2027 ouvre 2027 avant tout refus');
        $this->assertSame('ouvert', $exercice2027->status);
        $this->assertSame($exercice2027->id, AccountingEntry::where('source_id', self::VENTE_02)->value('fiscal_year_id'));
        $this->assertTrue(AuditLog::where('action', 'fiscal_year.opened_on_first_entry')->exists());
    }

    /**
     * L'invariant de l'essai à plusieurs postes, rejoué ici : un poste resté HORS LIGNE le 31/12 et le 01/01 envoie le
     * 03/01 ses ventes des deux jours et une dépense du 1er janvier — sans tâche planifiée. Rien n'est refusé à tort.
     */
    public function test_un_poste_hors_ligne_au_passage_de_l_annee_ne_voit_rien_refuse_a_tort(): void
    {
        $this->preparerDecor('2027-01-03 08:30:00');
        $this->exercice(2026);
        $this->stockDeMais(10, '2026-11-02 08:00:00');

        $reponse = $this->envoyer([
            'sales' => [
                $this->venteDuPoste(self::VENTE_31, '2026-12-31T17:45:00+01:00'),
                $this->venteDuPoste(self::VENTE_01, '2027-01-01T09:10:00+01:00'),
            ],
            'expenses' => [$this->depenseDuPoste(self::DEPENSE_01, '2027-01-01')],
        ])->assertOk();

        $this->assertSame([], $reponse->json('sales.rejected'));
        $this->assertSame([], $reponse->json('expenses.rejected'));
        $this->assertSame(2, Sale::count());

        $annees = FiscalYear::pluck('id', 'year');
        $this->assertSame($annees[2026], AccountingEntry::where('source_id', self::VENTE_31)->value('fiscal_year_id'));
        $this->assertSame($annees[2027], AccountingEntry::where('source_id', self::VENTE_01)->value('fiscal_year_id'));
    }

    /** Le filet ne saute jamais une année : sans 2027, une saisie de 2028 est refusée, et rien n'est créé. */
    public function test_le_filet_ne_cree_jamais_n_plus_2(): void
    {
        $this->preparerDecor('2028-03-01 09:00:00');
        $this->exercice(2026);

        try {
            app(AccountingEntryService::class)->recordManual(
                $this->comptes['531']->id, $this->comptes['701']->id, 10_000, '2028-03-01'
            );
            $this->fail('une saisie de 2028 ne doit pas ouvrir d’exercice tant que 2027 n’existe pas');
        } catch (NoOpenFiscalYearException $e) {
            $this->assertSame(
                "Aucun exercice comptable ne couvre le 01/03/2028. Ouvrez l'exercice 2028 (Comptabilité › Clôture d'exercice).",
                $e->getMessage(),
            );
        }

        $this->assertSame([2026], FiscalYear::pluck('year')->all());
    }

    /** Une saisie datée de 2027 faite en 2026 (date future) n'ouvre rien : le filet ne remplace que la tâche du 01/01. */
    public function test_le_filet_ne_joue_pas_avant_le_1er_janvier(): void
    {
        $this->preparerDecor('2026-12-28 09:00:00');
        $this->exercice(2026);

        $this->expectException(NoOpenFiscalYearException::class);

        try {
            app(AccountingEntryService::class)->recordManual(
                $this->comptes['531']->id, $this->comptes['701']->id, 10_000, '2027-01-05'
            );
        } finally {
            $this->assertSame(0, FiscalYear::where('year', 2027)->count());
        }
    }

    /** Deux exercices déjà ouverts (2026 et 2027) : ni la tâche ni le filet n'ouvrent 2028. Le refus a son motif R4. */
    public function test_jamais_plus_de_deux_exercices_ouverts(): void
    {
        $this->preparerDecor('2028-01-02 10:00:00');
        $this->exercice(2026);
        $this->exercice(2027);
        $this->stockDeMais(10, '2027-11-02 08:00:00');

        $this->artisan('agrierp:ouvrir-exercice')->assertFailed();
        $this->assertSame(0, FiscalYear::where('year', 2028)->count());
        $this->assertTrue(
            Notification::where('target_role', 'admin')->where('title', "Exercice 2028 non ouvert")->exists(),
            'l’administrateur est prévenu : la caisse refusera tout ce qui est daté de 2028',
        );

        $reponse = $this->envoyer(['sales' => [$this->venteDuPoste(self::VENTE_02, '2028-01-02T09:00:00+01:00')]])->assertOk();
        $this->assertSame(
            "Vente refusée : aucun exercice comptable ne couvre le 02/01/2028. Ouvrez l'exercice 2028 (Comptabilité › Clôture d'exercice).",
            $reponse->json('sales.rejected.0.reason'),
        );
        $this->assertSame(2, FiscalYear::count());
    }

    // ═══════════════════ Le bouton « Ouvrir l'exercice 2027 » ═══════════════════

    public function test_le_bouton_n_existe_pas_avant_le_1er_decembre_et_le_serveur_refuse(): void
    {
        $this->preparerDecor('2026-11-30 16:00:00');
        $this->exercice(2026);

        Livewire::test(ClotureExercice::class)
            ->set('tab', 'annuelle')
            ->assertDontSee("Ouvrir l'exercice 2027", false)
            ->call('ouvrirExerciceSuivant')
            ->assertDispatched('toast', message: "L'exercice 2027 ne peut s'ouvrir qu'à partir du 01/12/2026.", type: 'error');

        $this->assertSame(0, FiscalYear::where('year', 2027)->count());
    }

    public function test_le_bouton_ouvre_l_exercice_a_partir_du_1er_decembre_sans_doublon(): void
    {
        $this->preparerDecor('2026-12-01 08:00:00');
        $this->exercice(2026);

        $ecran = Livewire::test(ClotureExercice::class)
            ->set('tab', 'annuelle')
            ->assertSee("Ouvrir l'exercice 2027", false)
            ->call('ouvrirExerciceSuivant')
            ->assertDispatched('toast', message: "Exercice 2027 ouvert (du 01/01/2027 au 31/12/2027).", type: 'success');

        $this->assertSame('ouvert', FiscalYear::where('year', 2027)->value('status'));
        $this->assertSame('ouvert', FiscalYear::where('year', 2026)->value('status'));
        $this->assertTrue(AuditLog::where('action', 'fiscal_year.opened')->exists());

        $ecran->assertDontSee("Ouvrir l'exercice 2027", false)
            ->call('ouvrirExerciceSuivant')
            ->assertDispatched('toast', message: "L'exercice 2027 existe déjà.", type: 'error');
        $this->assertSame(1, FiscalYear::where('year', 2027)->count());
    }

    public function test_le_bouton_exige_le_droit_de_cloturer(): void
    {
        $this->preparerDecor('2026-12-05 08:00:00');
        $this->exercice(2026);

        $caissier = User::create([
            'name' => 'Caisse', 'username' => 'caisse-ex', 'email' => 'caisse-ex@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $caissier->assignRole('caissier');

        Livewire::actingAs($caissier)->test(ClotureExercice::class)->call('ouvrirExerciceSuivant')->assertForbidden();
        $this->assertSame(0, FiscalYear::where('year', 2027)->count());
    }

    public function test_le_bouton_refuse_un_troisieme_exercice_ouvert(): void
    {
        $this->preparerDecor('2026-12-05 08:00:00');
        $this->exercice(2025);
        $this->exercice(2026);

        Livewire::test(ClotureExercice::class)
            ->set('selectedYear', '2026')
            ->call('ouvrirExerciceSuivant')
            ->assertDispatched('toast', message: "Deux exercices sont déjà ouverts (2025 et 2026) : clôturez l'exercice 2025 avant d'ouvrir 2027.", type: 'error');

        $this->assertSame(0, FiscalYear::where('year', 2027)->count());
    }

    // ═══════════════════ Deux exercices ouverts ═══════════════════

    /**
     * Effet documenté (le choix de l'exercice affiché relève du lot 2, EX7) : avec 2026 et 2027 ouverts,
     * `FiscalYear::current()` reste le plus récent (2027, celui qui contient le jour) ; l'écran Clôture, lui, s'ouvre
     * sur l'exercice à clôturer, le plus ANCIEN encore ouvert.
     */
    public function test_avec_deux_exercices_ouverts_la_cloture_s_ouvre_sur_le_plus_ancien(): void
    {
        $this->preparerDecor('2027-01-12 09:00:00');
        $this->exercice(2026);
        $this->exercice(2027);

        $this->assertSame(2027, FiscalYear::current()->year);
        Livewire::test(ClotureExercice::class)->assertSet('selectedYear', '2026');
    }
}
