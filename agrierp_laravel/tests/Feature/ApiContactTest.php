<?php

namespace Tests\Feature;

use App\Mail\ContactEditorMail;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Mail;
use Tests\TestCase;

/**
 * Ticket 15.11 — `POST /api/contact` : « Contactez l'Éditeur » depuis le poste.
 */
class ApiContactTest extends TestCase
{
    use RefreshDatabase;

    private const MDP = 'AgriERP@2026';

    private User $user;

    protected function setUp(): void
    {
        parent::setUp();

        Role::findOrCreate('caissier', 'web');
        $this->user = User::create([
            'name' => 'Caissier Ferme',
            'username' => 'caisse',
            'email' => 'caisse@fermeolouwachegoun.com',
            'password' => bcrypt(self::MDP),
            'is_active' => true,
        ]);
        $this->user->assignRole('caissier');
    }

    private function appeler(array $corps, bool $avecJeton = true)
    {
        $requete = $this;

        if ($avecJeton) {
            $jeton = $this->postJson('/api/auth/login', [
                'identifiant' => 'caisse',
                'password' => self::MDP,
                'device_name' => 'poste-ferme-01',
            ])->json('token');

            $requete = $this->withHeader('Authorization', 'Bearer '.$jeton);
        }

        return $requete->postJson('/api/contact', $corps);
    }

    public function test_un_message_est_envoye_a_l_editeur_et_journalise(): void
    {
        Mail::fake();

        $this->appeler(['type' => 'message', 'subject' => 'Question', 'message' => 'Bonjour'])
            ->assertOk();

        Mail::assertSent(ContactEditorMail::class, function (ContactEditorMail $m) {
            return $m->payload['type'] === 'message'
                && $m->payload['subject'] === 'Question'
                && $m->senderEmail === 'caisse@fermeolouwachegoun.com'
                && $m->hasTo(config('mail.support_address', 'contact@massenonrhodes.com'));
        });
        $this->assertDatabaseHas('audit_logs', [
            'user_id' => $this->user->id,
            'action' => 'contact.message_sent',
        ]);
    }

    public function test_un_bug_nomme_l_appareil_expediteur(): void
    {
        Mail::fake();

        $this->appeler([
            'type' => 'bug',
            'module' => 'Stocks',
            'description' => 'Le stock ne se met pas à jour',
            'steps' => '1. Ajuster',
        ])->assertOk();

        Mail::assertSent(ContactEditorMail::class, fn (ContactEditorMail $m) => $m->payload['type'] === 'bug'
            && $m->payload['device'] === 'poste-ferme-01'
            && $m->payload['module'] === 'Stocks');
        $this->assertDatabaseHas('audit_logs', ['action' => 'contact.bug_reported']);
    }

    public function test_les_champs_obligatoires_sont_verifies(): void
    {
        Mail::fake();

        $this->appeler(['type' => 'message', 'subject' => '', 'message' => ''])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['subject', 'message']);
        $this->appeler(['type' => 'bug'])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['module', 'description']);
        $this->appeler(['type' => 'autre'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('type');

        Mail::assertNothingSent();
        $this->assertDatabaseMissing('audit_logs', ['action' => 'contact.message_sent']);
    }

    public function test_l_etape_de_reproduction_est_facultative(): void
    {
        Mail::fake();

        $this->appeler(['type' => 'bug', 'module' => 'Autre', 'description' => 'x'])->assertOk();
    }

    public function test_un_echec_de_transport_repond_502_et_ne_journalise_pas_un_envoi(): void
    {
        Mail::shouldReceive('to')->andThrow(new \RuntimeException('SMTP injoignable'));

        $this->appeler(['type' => 'message', 'subject' => 'S', 'message' => 'M'])
            ->assertStatus(502)
            ->assertJsonPath('message', fn ($m) => str_contains($m, 'Conservez votre texte'));

        $this->assertDatabaseMissing('audit_logs', ['action' => 'contact.message_sent']);
    }

    public function test_la_route_est_fermee_sans_jeton(): void
    {
        Mail::fake();

        $this->appeler(['type' => 'message', 'subject' => 'S', 'message' => 'M'], false)
            ->assertStatus(401);

        Mail::assertNothingSent();
    }

    public function test_l_appareil_figure_dans_le_corps_du_courrier(): void
    {
        $html = (new ContactEditorMail(
            senderName: 'X',
            senderEmail: 'x@y.bj',
            payload: ['type' => 'message', 'subject' => 'S', 'message' => 'M', 'device' => 'poste-ferme-01'],
        ))->render();

        $this->assertStringContainsString('poste-ferme-01', $html);
    }
}
