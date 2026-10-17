<?php

namespace Tests\Feature;

use App\Livewire\Auth\Login;
use App\Livewire\Parametres\AuditLogs;
use App\Models\AuditLog;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\RateLimiter;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.42 (Sprint 14) — TRAÇABILITÉ DES CONNEXIONS ÉCHOUÉES.
 *
 * Seule la connexion RÉUSSIE était journalisée. Le blocage serveur existait
 * bien (RateLimiter, 5 tentatives / 15 min) mais ne laissait AUCUNE trace
 * consultable après coup : une campagne de force brute était invisible, et le
 * KPI « Connexions échouées » de l'écran Audit Logs n'avait pas de source.
 */
class TracabiliteConnexionsEchoueesTest extends TestCase
{
    use RefreshDatabase;

    private const MDP = 'AgriERP@2026';

    private User $comptable;

    protected function setUp(): void
    {
        parent::setUp();

        RateLimiter::clear('compta@olouwachegoun.bj|127.0.0.1');
        RateLimiter::clear('compta|127.0.0.1');

        $this->comptable = User::create([
            'name' => 'Comptable', 'username' => 'compta', 'email' => 'compta@olouwachegoun.bj',
            'password' => bcrypt(self::MDP), 'is_active' => true,
        ]);
    }

    private function tenter(string $email, string $motDePasse)
    {
        return Livewire::test(Login::class)
            ->set('identifiant', $email)
            ->set('password', $motDePasse)
            ->call('submit');
    }

    /** LE FLUX MANQUANT : un échec laisse désormais une trace. */
    public function test_a_failed_attempt_is_journalled(): void
    {
        $this->tenter('compta@olouwachegoun.bj', 'mauvais-mot-de-passe');

        $trace = AuditLog::where('action', 'login.failed')->firstOrFail();

        $this->assertEquals('auth', $trace->module);
        $this->assertNotNull($trace->ip_address);
    }

    /**
     * ⚠️ LE COMPTE VISÉ EST RÉSOLU. « 5 échecs sur compta@ depuis la même IP »
     * se lit ; « 5 échecs anonymes » ne se lit pas.
     */
    public function test_the_targeted_account_is_identified(): void
    {
        $this->tenter('compta@olouwachegoun.bj', 'mauvais-mot-de-passe');

        $this->assertEquals(
            $this->comptable->id,
            AuditLog::where('action', 'login.failed')->value('user_id')
        );
    }

    /** Une adresse inconnue reste tracée : user_id nul, mais l'IP demeure. */
    public function test_an_unknown_address_is_still_traced(): void
    {
        $this->tenter('intrus@example.com', 'peu-importe');

        $trace = AuditLog::where('action', 'login.failed')->firstOrFail();

        $this->assertNull($trace->user_id);
        $this->assertNotNull($trace->ip_address);
    }

    /** ⚠️ LE MOT DE PASSE SAISI N'EST JAMAIS ÉCRIT NULLE PART. */
    public function test_the_submitted_password_is_never_stored(): void
    {
        $this->tenter('compta@olouwachegoun.bj', 'Secret-Tres-Reconnaissable-123');

        foreach (AuditLog::all() as $trace) {
            $this->assertStringNotContainsString('Secret-Tres-Reconnaissable', $trace->action);
            $this->assertStringNotContainsString('Secret-Tres-Reconnaissable', (string) $trace->module);
        }
    }

    /** Le verrouillage est l'événement de sécurité : journalisé une seule fois. */
    public function test_the_lockout_itself_is_journalled_once(): void
    {
        for ($i = 0; $i < 7; $i++) {
            $this->tenter('compta@olouwachegoun.bj', 'mauvais-mot-de-passe');
        }

        $this->assertEquals(1, AuditLog::where('action', 'login.locked')->count(),
            'Le verrouillage se journalise a la tentative qui le declenche, pas a chaque tentative suivante.');

        // Après verrouillage, `submit()` sort avant `Auth::attempt()` : les
        // tentatives suivantes ne gonflent plus le journal.
        $this->assertEquals(5, AuditLog::where('action', 'login.failed')->count());
    }

    /** Une connexion réussie ne produit aucun échec. */
    public function test_a_successful_login_produces_no_failure(): void
    {
        $this->tenter('compta@olouwachegoun.bj', self::MDP);

        $this->assertEquals(0, AuditLog::where('action', 'login.failed')->count());
        $this->assertEquals(1, AuditLog::where('action', 'login')->count());
    }

    /** Le KPI de l'écran Audit Logs compte réellement, et seulement les échecs. */
    public function test_the_kpi_counts_the_failures_of_the_last_24h(): void
    {
        $this->tenter('compta@olouwachegoun.bj', 'faux-1');
        $this->tenter('compta@olouwachegoun.bj', 'faux-2');

        // Un échec d'avant-hier ne doit pas entrer dans la fenêtre de 24 h.
        AuditLog::where('action', 'login.failed')->first()
            ->forceFill(['created_at' => now()->subDays(2)])->save();

        foreach (['view-parametres', 'manage-parametres'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('admin', 'web');
        $role->givePermissionTo(['view-parametres', 'manage-parametres']);
        $this->comptable->assignRole($role);
        $this->actingAs($this->comptable);

        $kpis = Livewire::test(AuditLogs::class)->instance()->kpis;

        $this->assertEquals(1, $kpis['connexions_echouees']);
    }

    /**
     * Ticket 14.50 — CONNEXION PAR IDENTIFIANT COURT. Le libellé du champ
     * promettait « NOM D'UTILISATEUR OU EMAIL » depuis la maquette, mais seule
     * l'adresse était acceptée. Les deux fonctionnent désormais.
     */
    public function test_a_short_username_signs_in(): void
    {
        $this->tenter('compta', self::MDP);

        $this->assertTrue(auth()->check(), "L'identifiant court doit ouvrir la session.");
        $this->assertEquals(0, AuditLog::where('action', 'login.failed')->count());
    }

    /** ⚠️ Un échec sur l'identifiant court vise bien le même compte. */
    public function test_a_failure_on_the_short_username_targets_the_same_account(): void
    {
        $this->tenter('compta', 'mauvais');

        $this->assertEquals(
            $this->comptable->id,
            AuditLog::where('action', 'login.failed')->value('user_id')
        );
    }

    /** Un identifiant inconnu ne doit pas être cherché parmi les adresses. */
    public function test_an_unknown_short_username_is_traced_without_a_user(): void
    {
        $this->tenter('intrus', 'peu-importe');

        $trace = AuditLog::where('action', 'login.failed')->firstOrFail();

        $this->assertNull($trace->user_id);
        $this->assertNotNull($trace->ip_address);
    }

    /** Le libellé français existe : jamais une clé technique affichée brute. */
    public function test_the_french_label_exists(): void
    {
        $this->tenter('compta@olouwachegoun.bj', 'faux');

        $this->assertEquals(
            'Tentative de connexion échouée',
            AuditLog::where('action', 'login.failed')->first()->action_label
        );
    }
}
