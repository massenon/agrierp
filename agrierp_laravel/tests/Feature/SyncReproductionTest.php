<?php

namespace Tests\Feature;

use App\Models\LivestockLot;
use App\Models\LivestockReproductionEvent;
use App\Models\LivestockSpecies;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 14.72 (Sprint 14) — LE CYCLE DE REPRODUCTION DESCEND AU POSTE.
 *
 * 🔴 CE QUE CE TICKET DÉBLOQUE. `livestock_reproduction_events` est la SEULE
 * table du système qui suive une femelle NOMMÉE (R1, R2… / T1, T2…) : les
 * fiches journalières ne connaissent que des agrégats de bande. Elle n'était
 * pas servie par `GET /api/sync/pull`, si bien que :
 *   1. l'écran Suivi Reproduction du poste n'avait **aucune** donnée ;
 *   2. `SoinsRepository` ne pouvait pas calculer le jour de cycle d'une bande
 *      en reproduction — le protocole se compte depuis la DERNIÈRE SAILLIE —
 *      et refusait donc, à raison, de proposer un traitement.
 *
 * ⚠️⚠️ LA RÈGLE DE SERVICE EST CELLE DES RÉMANENCES, ET POUR LA MÊME RAISON.
 * Une gestation ouverte il y a trois semaines n'a plus bougé depuis : un
 * tirage incrémental filtré sur `updated_at` la manquerait — alors que c'est
 * exactement l'événement qu'un poste doit connaître. Les cycles `en_cours`
 * descendent donc SANS filtre `since` ; seul l'historique clos est filtré.
 */
class SyncReproductionTest extends TestCase
{
    use RefreshDatabase;

    private const MDP = 'AgriERP@2026';

    private LivestockLot $bande;

    private string $token;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-elevage', 'manage-elevage'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('animalier', 'web')->givePermissionTo(['view-elevage', 'manage-elevage']);

        $user = User::create([
            'name' => 'Chef d\'Élevage', 'username' => 'elevage',
            'email' => 'elevage@olouwachegoun.bj',
            'password' => bcrypt(self::MDP), 'is_active' => true,
        ]);
        $user->assignRole('animalier');

        $espece = LivestockSpecies::create(['label' => 'Cuniculture', 'code' => 'cuniculture', 'is_active' => true]);

        $this->bande = LivestockLot::create([
            'code' => 'LOT-LAP-2026-06', 'species_id' => $espece->id, 'stage' => 'reproduction',
            'initial_quantity' => 40, 'current_quantity' => 40,
            'created_date' => now()->subMonths(2)->format('Y-m-d'),
            'status' => 'actif', 'is_active' => true,
        ]);

        $this->token = $this->postJson('/api/auth/login', [
            'identifiant' => 'elevage', 'password' => self::MDP, 'device_name' => 'poste-ferme-01',
        ])->json('token');
    }

    private function tirer(array $parametres = [])
    {
        return $this->withHeader('Authorization', 'Bearer '.$this->token)
            ->getJson('/api/sync/pull'.($parametres ? '?'.http_build_query($parametres) : ''));
    }

    private function cycle(array $attributs = []): LivestockReproductionEvent
    {
        return LivestockReproductionEvent::create(array_merge([
            'lot_id' => $this->bande->id,
            'mother_ref' => 'R1',
            'sire_ref' => 'M3',
            'saillie_date' => now()->subDays(20)->format('Y-m-d'),
            'status' => 'en_cours',
        ], $attributs));
    }

    /** 🔴→✅ Le cycle arrive au poste, avec sa femelle nommée. */
    public function test_the_reproduction_cycle_reaches_the_device(): void
    {
        $this->cycle();

        $this->tirer()
            ->assertOk()
            ->assertJsonCount(1, 'livestock_reproduction_events')
            ->assertJsonPath('livestock_reproduction_events.0.mother_ref', 'R1')
            ->assertJsonPath('livestock_reproduction_events.0.sire_ref', 'M3');
    }

    /**
     * ⚠️⚠️ LE POINT CENTRAL : une gestation ouverte il y a trois semaines
     * n'a plus bougé depuis. Un tirage incrémental la manquerait si elle
     * n'était servie que sur `updated_at`.
     */
    public function test_an_ongoing_cycle_survives_an_incremental_pull(): void
    {
        $cycle = $this->cycle();
        // Le cycle n'a pas été touché depuis trois semaines.
        $cycle->forceFill(['updated_at' => now()->subWeeks(3)])->saveQuietly();

        $this->tirer(['since' => now()->subDay()->toIso8601String()])
            ->assertOk()
            ->assertJsonCount(1, 'livestock_reproduction_events')
            ->assertJsonPath('livestock_reproduction_events.0.mother_ref', 'R1');
    }

    /** ⚠️ L'historique clos, lui, se filtre normalement. */
    public function test_a_closed_cycle_is_filtered_by_since(): void
    {
        $ancien = $this->cycle(['mother_ref' => 'R9', 'status' => 'termine']);
        $ancien->forceFill(['updated_at' => now()->subWeeks(3)])->saveQuietly();

        $this->tirer(['since' => now()->subDay()->toIso8601String()])
            ->assertOk()
            ->assertJsonCount(0, 'livestock_reproduction_events');
    }

    /** Un premier tirage, sans `since`, ramène tout l'historique. */
    public function test_a_first_pull_brings_the_whole_history(): void
    {
        $this->cycle(['mother_ref' => 'R1']);
        $this->cycle(['mother_ref' => 'R9', 'status' => 'termine']);

        $this->tirer()
            ->assertOk()
            ->assertJsonCount(2, 'livestock_reproduction_events');
    }

    /**
     * ⚠️ La palpation non faite descend bien à `null` — et pas à une date
     * quelconque. C'est ce `null` qui distingue « pas encore palpée » de
     * « palpée négative », et le poste s'en sert pour son statut.
     */
    public function test_a_pending_palpation_arrives_as_null(): void
    {
        $this->cycle();

        $this->tirer()
            ->assertOk()
            ->assertJsonPath('livestock_reproduction_events.0.palpation_date', null);
    }

    // ────────────────────────────────────────────────────────────────────
    // TICKET 14.73 — LA SAILLIE SE DECLARE AU POSTE.
    //
    // ⚠️ CREATION SEULE. Palpation et mise bas CORRIGENT un cycle que le
    // serveur a pu faire evoluer entre-temps : « dernier ecrivain gagne »
    // convient a une fiche journaliere qui se corrige dans la journee, pas a
    // une gestation de trois mois.
    // ────────────────────────────────────────────────────────────────────

    private function pousserSaillie(array $remplacements = [])
    {
        return $this->withHeader('Authorization', 'Bearer '.$this->token)
            ->postJson('/api/sync/push', [
                'livestock_reproduction_events' => [array_merge([
                    'id' => '22222222-2222-4222-8222-222222222222',
                    'lot_id' => $this->bande->id,
                    'mother_ref' => 'R8',
                    'sire_ref' => 'M2',
                    'saillie_date' => now()->subDay()->format('Y-m-d'),
                ], $remplacements)],
            ]);
    }

    /** 🔴→✅ La saillie declaree au clapier arrive au serveur. */
    public function test_the_offline_saillie_reaches_the_server(): void
    {
        $reponse = $this->pousserSaillie();

        $reponse->assertOk();
        $this->assertCount(1, $reponse->json('livestock_reproduction_events.accepted'));

        $cycle = LivestockReproductionEvent::findOrFail('22222222-2222-4222-8222-222222222222');

        $this->assertEquals('R8', $cycle->mother_ref);
        $this->assertEquals('M2', $cycle->sire_ref);
        $this->assertEquals('en_cours', $cycle->status);
    }

    /**
     * ⚠️⚠️ UN SEUL CYCLE EN COURS PAR FEMELLE. Deux saillies sur R1 — au poste
     * et au bureau le meme jour — produiraient deux gestations concurrentes
     * sur le meme animal : l'ecran les afficherait toutes deux et le KPI
     * « gestantes » compterait double.
     */
    public function test_a_second_cycle_on_the_same_female_is_refused(): void
    {
        $this->cycle(['mother_ref' => 'R8']);

        $reponse = $this->pousserSaillie();

        $reponse->assertOk();
        $this->assertCount(0, $reponse->json('livestock_reproduction_events.accepted'));
        $this->assertCount(1, $reponse->json('livestock_reproduction_events.rejected'));
        $this->assertEquals(1, LivestockReproductionEvent::count());
    }

    /** La meme femelle redevient declarable une fois son cycle clos. */
    public function test_a_closed_cycle_reopens_the_declaration(): void
    {
        $this->cycle(['mother_ref' => 'R8', 'status' => 'termine']);

        $this->pousserSaillie()->assertOk();

        $this->assertEquals(2, LivestockReproductionEvent::count());
    }

    /**
     * ⚠️ IDEMPOTENCE : un renvoi (poste sans accuse de reception) est acquitte
     * sans rien rejouer, jamais transforme en second cycle.
     */
    public function test_a_resent_saillie_is_acknowledged_without_duplicating(): void
    {
        $this->pousserSaillie()->assertOk();
        $reponse = $this->pousserSaillie();

        $reponse->assertOk();
        $this->assertCount(1, $reponse->json('livestock_reproduction_events.accepted'));
        $this->assertEquals(1, LivestockReproductionEvent::count());
    }

    /**
     * Ticket H7 — 🔴 LES ETAPES DU CYCLE SAISIES AU POSTE ETAIENT IGNOREES : un renvoi d'un cycle connu etait acquitte
     * sans rien appliquer. Palpation negative, puis mise bas 7 vivants / 1 mort, puis cloture : memes valeurs que les
     * actions de l'ecran web.
     */
    public function test_les_etapes_du_cycle_envoyees_par_le_poste_sont_appliquees(): void
    {
        $this->pousserSaillie()->assertOk();
        $hier = now()->subDay()->format('Y-m-d');

        $this->pousserSaillie(['palpation_date' => $hier, 'status' => 'echec'])->assertOk()
            ->assertJsonPath('livestock_reproduction_events.accepted.0', '22222222-2222-4222-8222-222222222222');
        $cycle = LivestockReproductionEvent::findOrFail('22222222-2222-4222-8222-222222222222');
        $this->assertSame([$hier, 'echec'], [$cycle->palpation_date->format('Y-m-d'), $cycle->status]);

        $this->pousserSaillie(['status' => 'en_cours', 'mise_bas_date_actual' => $hier, 'nes_vivants' => 7, 'nes_morts' => 1])->assertOk();
        $cycle->refresh();
        $this->assertSame([7, 1, 'en_cours'], [(int) $cycle->nes_vivants, (int) $cycle->nes_morts, $cycle->status]);
        // Une etape non renseignee n'efface pas ce que le serveur sait deja.
        $this->assertSame($hier, $cycle->palpation_date->format('Y-m-d'));

        $this->pousserSaillie(['status' => 'termine'])->assertOk();
        $this->assertSame('termine', $cycle->fresh()->status);
        $this->assertSame(1, LivestockReproductionEvent::count());
    }

    /**
     * 🔴→✅ Ticket S-T12 (trouvé par l'essai à plusieurs postes) — LES ÉTAPES SAISIES AVANT LE PREMIER ENVOI. L'animalier,
     * hors ligne plusieurs jours, déclare la saillie puis la palpe (négative) avant que rien ne parte : une seule ligne,
     * envoyée une fois. La création n'en gardait que la saillie (`en_cours`, sans palpation) ; le poste, acquitté,
     * recevait au tirage suivant la ligne du serveur — la palpation perdue sans un mot.
     */
    public function test_les_etapes_saisies_avant_le_premier_envoi_sont_gardees(): void
    {
        $hier = now()->subDay()->format('Y-m-d');

        $this->pousserSaillie(['palpation_date' => $hier, 'status' => 'echec'])->assertOk()
            ->assertJsonPath('livestock_reproduction_events.accepted.0', '22222222-2222-4222-8222-222222222222');

        $cycle = LivestockReproductionEvent::findOrFail('22222222-2222-4222-8222-222222222222');
        $this->assertSame([$hier, 'echec'], [$cycle->palpation_date?->format('Y-m-d'), $cycle->status]);

        // Mise bas et clôture saisies avant le premier envoi d'une autre femelle.
        $this->pousserSaillie([
            'id' => '33333333-3333-4333-8333-333333333333', 'mother_ref' => 'R9', 'palpation_date' => $hier,
            'mise_bas_date_actual' => $hier, 'nes_vivants' => 6, 'nes_morts' => 2, 'status' => 'termine',
        ])->assertOk();
        $autre = LivestockReproductionEvent::findOrFail('33333333-3333-4333-8333-333333333333');
        $this->assertSame([6, 2, 'termine', $hier], [(int) $autre->nes_vivants, (int) $autre->nes_morts, $autre->status, $autre->mise_bas_date_actual?->format('Y-m-d')]);
    }

    /** Une étape invalide à la création refuse la saillie entière (rien d'écrit), avec son motif. */
    public function test_une_etape_invalide_a_la_creation_refuse_la_saillie(): void
    {
        $reponse = $this->pousserSaillie(['mise_bas_date_actual' => now()->addDays(3)->format('Y-m-d')]);

        $reponse->assertOk();
        $this->assertCount(1, $reponse->json('livestock_reproduction_events.rejected'));
        $this->assertSame(0, LivestockReproductionEvent::count());
    }

    /** Ticket H7 — une etape invalide (statut inconnu, mise bas future) est refusee avec son motif. */
    public function test_une_etape_invalide_est_refusee(): void
    {
        $this->pousserSaillie()->assertOk();

        $reponse = $this->pousserSaillie(['mise_bas_date_actual' => now()->addDays(3)->format('Y-m-d')]);
        $reponse->assertOk();
        $this->assertCount(1, $reponse->json('livestock_reproduction_events.rejected'));
        $this->assertNull(LivestockReproductionEvent::sole()->mise_bas_date_actual);
    }

    /** ⚠️ Une saillie datee du futur n'a pas eu lieu. */
    public function test_a_saillie_dated_in_the_future_is_refused(): void
    {
        $reponse = $this->pousserSaillie([
            'saillie_date' => now()->addDay()->format('Y-m-d'),
        ]);

        $reponse->assertOk();
        $this->assertCount(1, $reponse->json('livestock_reproduction_events.rejected'));
        $this->assertEquals(0, LivestockReproductionEvent::count());
    }

    /**
     * ⚠️⚠️ DEUX ESPECES SEULEMENT. Une saillie declaree sur une bande avicole
     * n'aurait aucun ecran pour l'afficher, et fausserait les KPI qui filtrent
     * sur la cuniculture et la porciculture.
     */
    public function test_a_poultry_lot_is_refused(): void
    {
        $avicole = LivestockSpecies::create(['label' => 'Aviculture', 'code' => 'aviculture', 'is_active' => true]);
        $bande = LivestockLot::create([
            'code' => 'AVI-2026-01', 'species_id' => $avicole->id, 'stage' => 'ponte',
            'initial_quantity' => 100, 'current_quantity' => 100,
            'created_date' => now()->subMonth()->format('Y-m-d'),
            'status' => 'actif', 'is_active' => true,
        ]);

        $reponse = $this->pousserSaillie(['lot_id' => $bande->id]);

        $reponse->assertOk();
        $this->assertCount(1, $reponse->json('livestock_reproduction_events.rejected'));
        $this->assertEquals(0, LivestockReproductionEvent::count());
    }

    /**
     * ⚠️ UN REFUS N'EMPORTE PAS L'ENVOI ENTIER. La seconde saillie est
     * refusee, la premiere passe — c'est la regle de tout ce point d'entree.
     */
    public function test_one_refusal_does_not_carry_away_the_whole_push(): void
    {
        $reponse = $this->withHeader('Authorization', 'Bearer '.$this->token)
            ->postJson('/api/sync/push', [
                'livestock_reproduction_events' => [
                    [
                        'id' => '22222222-2222-4222-8222-222222222222',
                        'lot_id' => $this->bande->id,
                        'mother_ref' => 'R8',
                        'saillie_date' => now()->subDay()->format('Y-m-d'),
                    ],
                    [
                        'id' => '33333333-3333-4333-8333-333333333333',
                        'lot_id' => 'ffffffff-ffff-4fff-8fff-ffffffffffff',
                        'mother_ref' => 'R9',
                        'saillie_date' => now()->subDay()->format('Y-m-d'),
                    ],
                ],
            ]);

        $reponse->assertOk();
        $this->assertCount(1, $reponse->json('livestock_reproduction_events.accepted'));
        $this->assertCount(1, $reponse->json('livestock_reproduction_events.rejected'));
        $this->assertEquals(1, LivestockReproductionEvent::count());
    }
}
