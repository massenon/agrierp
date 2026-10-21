<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 14.51 (Sprint 14) — API D'AUTHENTIFICATION : première couverture.
 *
 * 🔴 CONSTAT AVANT CE TICKET : `app/Http/Controllers/Api/` n'avait **aucun
 * test**, alors que le client Flutter va en dépendre entièrement. Une API sans
 * test est une API dont on découvre le contrat en production.
 *
 * Deux défauts réels corrigés ici, tous deux hérités d'une correction faite
 * sur la seule surface web :
 *   1. l'API n'acceptait QUE l'adresse e-mail, alors que le ticket 14.50 a
 *      ouvert la connexion web au nom d'utilisateur court ;
 *   2. un échec d'authentification n'était PAS journalisé côté API, alors que
 *      le ticket 14.42 l'avait comblé côté web.
 */
class ApiAuthentificationTest extends TestCase
{
    use RefreshDatabase;

    private const MDP = 'AgriERP@2026';

    private User $comptable;

    protected function setUp(): void
    {
        parent::setUp();

        Permission::findOrCreate('view-comptabilite', 'web');
        Role::findOrCreate('comptable', 'web')->givePermissionTo('view-comptabilite');

        $this->comptable = User::create([
            'name' => 'Comptable Ferme École',
            'username' => 'compta',
            'email' => 'compta@fermeolouwachegoun.com',
            'password' => bcrypt(self::MDP),
            'is_active' => true,
        ]);
        $this->comptable->assignRole('comptable');
    }

    private function connexion(array $corps)
    {
        return $this->postJson('/api/auth/login', array_merge(
            ['password' => self::MDP, 'device_name' => 'poste-ferme-01'],
            $corps,
        ));
    }

    /** LE FLUX QUE LE CLIENT FLUTTER EMPLOIERA : identifiant court. */
    public function test_the_short_username_issues_a_token(): void
    {
        $reponse = $this->connexion(['identifiant' => 'compta']);

        $reponse->assertOk()
            ->assertJsonPath('user.username', 'compta')
            ->assertJsonPath('user.role', 'comptable');

        $this->assertNotEmpty($reponse->json('token'));
    }

    /** ⚠️ L'ADRESSE CONTINUE DE FONCTIONNER : elle n'est pas remplacée. */
    public function test_the_email_still_works(): void
    {
        $this->connexion(['identifiant' => 'compta@fermeolouwachegoun.com'])->assertOk();
    }

    /**
     * ⚠️ L'ANCIENNE CLÉ `email` RESTE ACCEPTÉE. Un appareil déjà déployé avec
     * l'ancien contrat doit continuer de se connecter : retirer la clé aurait
     * cassé tout client non mis à jour, sans avertissement.
     */
    public function test_the_previous_contract_still_works(): void
    {
        $this->connexion(['email' => 'compta@fermeolouwachegoun.com'])->assertOk();
    }

    /** Un identifiant absent est refusé par la validation, pas par une erreur 500. */
    public function test_an_absent_identifier_is_rejected_cleanly(): void
    {
        $this->postJson('/api/auth/login', [
            'password' => self::MDP,
            'device_name' => 'poste-ferme-01',
        ])->assertStatus(422);
    }

    /** Mot de passe erroné : refus, et aucun jeton émis. */
    public function test_a_wrong_password_issues_no_token(): void
    {
        $reponse = $this->connexion(['identifiant' => 'compta', 'password' => 'faux']);

        $reponse->assertStatus(422);
        $this->assertNull($reponse->json('token'));
        $this->assertEquals(0, $this->comptable->tokens()->count());
    }

    /**
     * 🔴→✅ L'ÉCHEC EST JOURNALISÉ CÔTÉ API AUSSI. Sans cela, une attaque par
     * force brute menée contre l'API ne laissait aucune trace au journal
     * d'audit — l'angle mort que le ticket 14.42 avait fermé côté web
     * seulement.
     */
    public function test_a_failed_api_attempt_is_journalled_with_its_target(): void
    {
        $this->connexion(['identifiant' => 'compta', 'password' => 'faux']);

        $trace = AuditLog::where('action', 'login.failed')->firstOrFail();

        $this->assertEquals($this->comptable->id, $trace->user_id);
        $this->assertEquals('auth', $trace->module);
    }

    /** Un identifiant inconnu est tracé sans utilisateur rattaché. */
    public function test_an_unknown_identifier_is_traced_without_a_user(): void
    {
        $this->connexion(['identifiant' => 'intrus', 'password' => 'faux']);

        $trace = AuditLog::where('action', 'login.failed')->firstOrFail();

        $this->assertNull($trace->user_id);
    }

    /** Un compte désactivé est refusé — et l'échec est tracé. */
    public function test_an_inactive_account_is_refused(): void
    {
        $this->comptable->update(['is_active' => false]);

        $this->connexion(['identifiant' => 'compta'])->assertStatus(422);

        $this->assertEquals(1, AuditLog::where('action', 'login.failed')->count());
        $this->assertEquals(0, $this->comptable->tokens()->count());
    }

    /**
     * ⚠️ UN SEUL JETON ACTIF PAR APPAREIL NOMMÉ. Reconnecter le même poste
     * révoque son jeton précédent au lieu d'en accumuler : sans cela, un poste
     * volé resterait autorisé par tous les jetons qu'il a jamais reçus.
     */
    public function test_reconnecting_the_same_device_revokes_its_previous_token(): void
    {
        $premier = $this->connexion(['identifiant' => 'compta'])->json('token');
        $second = $this->connexion(['identifiant' => 'compta'])->json('token');

        $this->assertNotEquals($premier, $second);
        $this->assertEquals(1, $this->comptable->tokens()->count());
    }

    /** Deux appareils distincts gardent chacun leur jeton. */
    public function test_two_distinct_devices_keep_their_own_tokens(): void
    {
        $this->connexion(['identifiant' => 'compta', 'device_name' => 'poste-01']);
        $this->connexion(['identifiant' => 'compta', 'device_name' => 'poste-02']);

        $this->assertEquals(2, $this->comptable->tokens()->count());
    }

    /** `/api/auth/me` rend la même forme que la connexion. */
    public function test_me_returns_the_same_shape_as_login(): void
    {
        $token = $this->connexion(['identifiant' => 'compta'])->json('token');

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/auth/me')
            ->assertOk()
            ->assertJsonPath('username', 'compta')
            ->assertJsonPath('email', 'compta@fermeolouwachegoun.com')
            ->assertJsonPath('role', 'comptable');
    }

    /**
     * Ticket 14.52 — LES RATIONS NORMATIVES DESCENDENT AU CLIENT.
     *
     * ⚠️ `feed_ration_standards` est un référentiel ÉDITABLE. Sans lui dans le
     * tirage, le client Desktop n'aurait eu que deux options, toutes deux
     * mauvaises : coder les grammages en dur et diverger en silence le jour
     * d'une correction, ou renoncer au calcul de provende.
     */
    public function test_the_pull_serves_the_ration_standards(): void
    {
        \App\Models\FeedRationStandard::create([
            'species_code' => 'cuniculture',
            'stage_label' => 'Lapine Mère / Reproducteur',
            'ration_g_per_day' => 120,
        ]);

        $token = $this->connexion(['identifiant' => 'compta'])->json('token');

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/sync/pull')
            ->assertOk()
            ->assertJsonPath('feed_ration_standards.0.stage_label', 'Lapine Mère / Reproducteur')
            ->assertJsonPath('feed_ration_standards.0.ration_g_per_day', 120);
    }

    /**
     * ⚠️ LES RATIONS SONT SERVIES MÊME AVEC UN `since` RÉCENT. Un appareil qui
     * n'aurait rien tiré depuis une correction de grammage garderait sinon une
     * valeur périmée sans le savoir, et calculerait des provendes fausses.
     */
    public function test_the_rations_are_served_even_with_a_recent_since(): void
    {
        \App\Models\FeedRationStandard::create([
            'species_code' => 'cuniculture',
            'stage_label' => 'Lapin Sevré',
            'ration_g_per_day' => 30,
        ]);

        $token = $this->connexion(['identifiant' => 'compta'])->json('token');

        $this->withHeader('Authorization', 'Bearer '.$token)
            // ⚠️ `urlencode` INDISPENSABLE : le « + » du décalage horaire d'un
            // ISO-8601 est interprété comme une ESPACE dans une chaîne de
            // requête, et le tirage échoue alors en 422 « since must be a
            // valid date ». Le client Dart émet un « Z » et y échappe, mais
            // tout client qui formaterait « +00:00 » tomberait dedans.
            ->getJson('/api/sync/pull?since='.urlencode(now()->addDay()->toIso8601String()))
            ->assertOk()
            ->assertJsonCount(1, 'feed_ration_standards');
    }

    /** Sans jeton, les routes protégées sont fermées. */
    public function test_protected_routes_are_closed_without_a_token(): void
    {
        $this->getJson('/api/auth/me')->assertStatus(401);
        $this->getJson('/api/sync/pull')->assertStatus(401);
        $this->postJson('/api/sync/push', [])->assertStatus(401);
    }
}
