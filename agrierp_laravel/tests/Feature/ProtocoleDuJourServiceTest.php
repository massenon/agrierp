<?php

namespace Tests\Feature;

use App\Jobs\DailyProphylaxyReminderJob;
use App\Models\LivestockLot;
use App\Models\LivestockReproductionEvent;
use App\Models\LivestockSpecies;
use App\Models\Notification;
use App\Models\ProphylaxisScheduleStandard;
use App\Services\ProtocoleDuJourService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 15.35 — LA RÈGLE DU JOUR DE CYCLE, EN UN SEUL EXEMPLAIRE.
 *
 * Elle était écrite en dur dans `DailyProphylaxyReminderJob`. Elle sert
 * désormais aussi aux fiches Lapins et Porcs : deux copies d'une règle
 * sanitaire finissent toujours par diverger.
 *
 * Barème de test volontairement réduit à TROIS entrées, dont les jours sont
 * calculés À LA MAIN (jamais par le code testé) :
 *   - « Anti-stress »     : jours 2 à 4, sans rémanence ;
 *   - « Anti-coccidien »  : jour 5 uniquement, rémanence 5 jours ;
 *   - « Déparasitage »    : « Le 1er du mois », bornes nulles (calendaire).
 *
 * Maintenant figé au 14/10/2026 À 15 h 30 (et non à minuit) : c'est
 * précisément l'heure qui révélait le défaut du job (voir le test dédié).
 */
class ProtocoleDuJourServiceTest extends TestCase
{
    use RefreshDatabase;

    private LivestockSpecies $lapins;

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow('2026-10-14 15:30:00');

        $this->lapins = LivestockSpecies::create(['code' => 'cuniculture', 'label' => 'Lapins', 'is_enabled' => true]);

        $this->standard('Anti-stress', 2, 4, 0, 'Vitalyte', "1C / 10L d'eau");
        $this->standard('Anti-coccidien', 5, 5, 5, 'Antcox', "1C / 20L d'eau");
        $this->standard('Déparasitage', null, null, 7, 'Levalap', "1C / 5L d'eau", 'Le 1er du mois');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function standard(string $traitement, ?int $debut, ?int $fin, int $remanence, string $produit, string $dosage, ?string $libelle = null, string $espece = 'cuniculture', bool $actif = true): ProphylaxisScheduleStandard
    {
        return ProphylaxisScheduleStandard::create([
            'species_code' => $espece,
            'period_label' => $libelle ?? "J{$debut}",
            'cycle_day_start' => $debut,
            'cycle_day_end' => $fin,
            'treatment' => $traitement,
            'product_recommended' => $produit,
            'dosage' => $dosage,
            'withdrawal_days' => $remanence,
            'is_active' => $actif,
        ]);
    }

    private function bande(string $code, string $stade, string $miseEnLot): LivestockLot
    {
        return LivestockLot::create([
            'code' => $code,
            'species_id' => $this->lapins->id,
            'stage' => $stade,
            'initial_quantity' => 20,
            'current_quantity' => 20,
            'created_date' => $miseEnLot,
            'status' => 'actif',
            'is_active' => true,
        ]);
    }

    private function saillie(LivestockLot $bande, string $date): void
    {
        LivestockReproductionEvent::create(['lot_id' => $bande->id, 'mother_ref' => 'F-01', 'saillie_date' => $date, 'status' => 'en_cours']);
    }

    // ───────────────────────── Jour de cycle ─────────────────────────

    /** J1 = le jour de mise en lot : 10/10 -> J1, 11 -> J2, 12 -> J3, 13 -> J4, 14 -> J5. */
    public function test_le_jour_de_cycle_est_un_entier_j1_etant_le_jour_de_reference(): void
    {
        $bande = $this->bande('LOT-A', 'croissance', '2026-10-10');
        $service = app(ProtocoleDuJourService::class);

        $this->assertSame(5, $service->jourDeCycle($bande), 'Le 14/10 à 15 h 30 est le J5 d\'une bande mise en lot le 10/10.');
        $this->assertSame(1, $service->jourDeCycle($bande, Carbon::parse('2026-10-10 23:59:00')));
        $this->assertSame(3, $service->jourDeCycle($bande, Carbon::parse('2026-10-12')));
    }

    /** Une bande en reproduction se compte depuis sa DERNIÈRE saillie, pas depuis sa mise en lot. */
    public function test_une_bande_en_reproduction_se_compte_depuis_la_derniere_saillie(): void
    {
        $bande = $this->bande('LOT-R', 'reproduction', '2026-01-01');
        $this->saillie($bande, '2026-10-01');
        $this->saillie($bande, '2026-10-12');

        // Dernière saillie le 12/10 : le 14/10 est le J3 (12 -> J1, 13 -> J2, 14 -> J3).
        $this->assertSame(3, app(ProtocoleDuJourService::class)->jourDeCycle($bande));
    }

    public function test_une_bande_en_reproduction_sans_saillie_est_indeterminee_et_dit_pourquoi(): void
    {
        $bande = $this->bande('LOT-R', 'reproduction', '2026-01-01');
        $service = app(ProtocoleDuJourService::class);

        $this->assertNull($service->jourDeCycle($bande), 'Pas de saillie connue : jamais de repli silencieux sur la mise en lot.');

        $protocole = $service->pourBande($bande);
        $this->assertFalse($protocole->determinable());
        // Ticket #45 : tous les traitements du barème avec bornes (Anti-stress + Anti-coccidien)
        // sont exposés même sans saillie connue — le cycle est inconnu mais l'administration reste possible.
        $this->assertCount(2, $protocole->traitements);
        $this->assertStringContainsString('saillie', (string) $protocole->motifIndetermine);
        $this->assertSame('Indéterminé', $protocole->etat());
    }

    // ───────────────────────── Traitements dus ─────────────────────────

    public function test_les_traitements_dus_viennent_du_bareme_selon_les_bornes_entieres(): void
    {
        $service = app(ProtocoleDuJourService::class);

        $noms = fn (int $j) => $service->traitementsDus('cuniculture', $j)->pluck('treatment')->all();

        $this->assertSame([], $noms(1));
        $this->assertSame(['Anti-stress'], $noms(2));
        $this->assertSame(['Anti-stress'], $noms(4));
        $this->assertSame(['Anti-coccidien'], $noms(5));
        $this->assertSame([], $noms(6));
    }

    public function test_une_entree_inactive_ou_d_une_autre_espece_n_est_jamais_due(): void
    {
        $this->standard('Retiré', 5, 5, 0, 'X', 'x', null, 'cuniculture', false);
        $this->standard('Porcin', 5, 5, 0, 'Y', 'y', null, 'porciculture');

        $noms = app(ProtocoleDuJourService::class)->traitementsDus('cuniculture', 5)->pluck('treatment')->all();

        $this->assertSame(['Anti-coccidien'], $noms);
    }

    /** « Le 1er du mois » : jamais dû, mais COMPTÉ et annoncé comme non évalué. */
    public function test_l_entree_calendaire_n_est_jamais_evaluee_mais_est_comptee(): void
    {
        $bande = $this->bande('LOT-A', 'croissance', '2026-10-10');
        $service = app(ProtocoleDuJourService::class);

        foreach (range(-3, 40) as $jour) {
            $this->assertNotContains('Déparasitage', $service->traitementsDus('cuniculture', $jour)->pluck('treatment')->all());
        }

        $this->assertSame(1, $service->pourBande($bande)->calendairesNonEvalues);
    }

    public function test_le_protocole_du_jour_d_une_bande_en_croissance(): void
    {
        $bande = $this->bande('LOT-A', 'croissance', '2026-10-10');

        $protocole = app(ProtocoleDuJourService::class)->pourBande($bande);

        $this->assertTrue($protocole->determinable());
        $this->assertSame(5, $protocole->jourDeCycle);
        $this->assertSame(['Anti-coccidien'], $protocole->traitements->pluck('standard.treatment')->all());
        $this->assertSame(1, $protocole->enAttente());
        $this->assertSame('1 Prévu(s)', $protocole->etat());
    }

    public function test_un_jour_sans_traitement_est_libre_et_non_indetermine(): void
    {
        $bande = $this->bande('LOT-A', 'croissance', '2026-10-01'); // J14 : rien au barème

        $protocole = app(ProtocoleDuJourService::class)->pourBande($bande);

        $this->assertTrue($protocole->determinable());
        $this->assertSame('Libre', $protocole->etat());
    }

    public function test_une_bande_pas_encore_mise_en_lot_a_la_date_n_a_aucun_traitement(): void
    {
        $bande = $this->bande('LOT-A', 'croissance', '2026-10-20');

        $protocole = app(ProtocoleDuJourService::class)->pourBande($bande);

        $this->assertLessThan(1, $protocole->jourDeCycle);
        $this->assertCount(0, $protocole->traitements);
    }

    // ───────────────────── Job : non-régression + défaut ─────────────────────

    /**
     * 🔴 DÉFAUT DU JOB TROUVÉ À L'EXTRACTION. `diffInDays(now()) + 1` renvoie un
     * FLOTTANT sous Carbon 3 (4,64 + 1 = 5,64 à 15 h 30, ou 5,25 à 06 h 00, heure
     * réelle du job) : les traitements d'un jour unique (bornes 5 et 5) ne
     * correspondaient JAMAIS, seul un intervalle large avait une chance.
     * Aucun test n'existait pour le job : personne ne l'avait vu.
     */
    public function test_le_job_emet_le_rappel_d_un_jour_unique_meme_a_06h00(): void
    {
        Carbon::setTestNow('2026-10-14 06:00:00');
        $this->bande('LOT-A', 'croissance', '2026-10-10'); // J5

        (new DailyProphylaxyReminderJob)->handle();

        $rappels = Notification::where('type', 'prophylaxis_due')->get();
        $this->assertCount(1, $rappels);
        $this->assertSame("Traitement dû aujourd'hui — LOT-A", $rappels[0]->title);
        $this->assertSame("Anti-coccidien — Antcox, 1C / 20L d'eau — Bande LOT-A, Lapins", $rappels[0]->message);
    }

    public function test_le_job_compte_la_reproduction_depuis_la_derniere_saillie(): void
    {
        $bande = $this->bande('LOT-R', 'reproduction', '2026-01-01');
        $this->saillie($bande, '2026-10-12'); // J3 -> Anti-stress

        (new DailyProphylaxyReminderJob)->handle();

        $messages = Notification::where('type', 'prophylaxis_due')->pluck('message')->all();
        $this->assertCount(1, $messages);
        $this->assertStringStartsWith('Anti-stress — Vitalyte', $messages[0]);
    }

    public function test_le_job_ignore_la_reproduction_sans_saillie_et_les_entrees_calendaires(): void
    {
        $this->bande('LOT-R', 'reproduction', '2026-10-10'); // sans saillie : ignorée, même si la mise en lot dirait J5
        // Entrée « large » : due à N'IMPORTE QUEL jour de 1 à 999. Si la bande indéterminée
        // était évaluée, quel que soit le jour retenu, elle déclencherait un rappel.
        $this->standard('Large', 1, 999, 0, 'Z', 'z');

        (new DailyProphylaxyReminderJob)->handle();

        $this->assertSame(0, Notification::where('type', 'prophylaxis_due')->count());
        $this->assertSame(0, Notification::where('message', 'like', '%Déparasitage%')->count());
    }

    /** Le job lit le barème de l'espèce de CHAQUE bande, pas celui d'une espèce figée. */
    public function test_le_job_utilise_le_bareme_de_l_espece_de_chaque_bande(): void
    {
        $porcs = LivestockSpecies::create(['code' => 'porciculture', 'label' => 'Porcs', 'is_enabled' => true]);
        $this->standard('Vermifuge', 5, 5, 14, 'Ivermectine', '1ml / 33kg', null, 'porciculture');
        LivestockLot::create([
            'code' => 'LOT-POR', 'species_id' => $porcs->id, 'stage' => 'engraissement',
            'initial_quantity' => 10, 'current_quantity' => 10, 'created_date' => '2026-10-10',
            'status' => 'actif', 'is_active' => true,
        ]);

        (new DailyProphylaxyReminderJob)->handle();

        $messages = Notification::where('type', 'prophylaxis_due')->pluck('message')->all();
        $this->assertCount(1, $messages);
        $this->assertStringStartsWith('Vermifuge — Ivermectine', $messages[0]);
    }

    public function test_le_job_n_emet_qu_un_rappel_par_jour_et_par_traitement(): void
    {
        $this->bande('LOT-A', 'croissance', '2026-10-10');

        (new DailyProphylaxyReminderJob)->handle();
        (new DailyProphylaxyReminderJob)->handle();

        $this->assertSame(1, Notification::where('type', 'prophylaxis_due')->count());
    }

    public function test_le_job_ignore_une_espece_desactivee(): void
    {
        $this->lapins->update(['is_enabled' => false]);
        $this->bande('LOT-A', 'croissance', '2026-10-10');

        (new DailyProphylaxyReminderJob)->handle();

        $this->assertSame(0, Notification::where('type', 'prophylaxis_due')->count());
    }
}
