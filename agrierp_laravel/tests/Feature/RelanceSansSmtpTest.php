<?php

namespace Tests\Feature;

use App\Livewire\Ventes\RelancesClients;
use App\Mail\CustomerReminderMail;
use App\Models\AuditLog;
use App\Models\CompanySetting;
use App\Models\Customer;
use App\Models\CustomerReminder;
use App\Models\Permission;
use App\Models\Receivable;
use App\Models\Role;
use App\Models\User;
use App\Services\RelanceClientService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket CONF-1 — UNE RELANCE E-MAIL N'EST « ENVOYÉE » QUE SI L'ENVOI EST RÉEL.
 *
 * Avec `MAIL_MAILER=log` (ou `array`) et aucun hôte SMTP dans Paramètres, `Mail::send` réussissait en écrivant dans un fichier
 * et la relance était tracée « envoyée », la créance comptée comme relancée. Désormais : refus avec un motif français, ni
 * trace ni audit ; le poste reçoit le même motif (la relance reste en conflit chez lui). WhatsApp, appel et courrier restent
 * des traces.
 */
class RelanceSansSmtpTest extends TestCase
{
    use RefreshDatabase;

    private User $vendeur;

    private Customer $client;

    private Receivable $creance;

    protected function setUp(): void
    {
        parent::setUp();

        Permission::findOrCreate('manage-ventes', 'web');
        Permission::findOrCreate('view-ventes', 'web');
        Role::findOrCreate('vendeur', 'web')->givePermissionTo(['manage-ventes', 'view-ventes']);
        $this->vendeur = User::create(['name' => 'Vendeur', 'username' => 'vendeur', 'email' => 'v@x.bj', 'password' => bcrypt('x'), 'is_active' => true]);
        $this->vendeur->assignRole('vendeur');

        $this->client = Customer::create(['name' => 'AMOUSSOU Régis', 'phone' => '+229 97 20 20 20', 'email' => 'regis@exemple.bj', 'is_active' => true]);
        $this->creance = Receivable::create([
            'customer_id' => $this->client->id, 'amount' => 100000, 'amount_paid' => 0,
            'due_date' => now()->subDays(10)->toDateString(), 'status' => 'en_retard',
        ]);
    }

    private function relance(array $remplace = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(), 'customer_id' => $this->client->id, 'receivable_id' => $this->creance->id,
            'channel' => 'email', 'message' => 'Bonjour, la facture reste impayée.', 'reminder_date' => now()->toDateString(),
        ], $remplace);
    }

    private function pousser(array $lignes)
    {
        return $this->actingAs($this->vendeur, 'sanctum')->postJson('/api/sync/push', ['device_id' => 'poste-test', 'customer_reminders' => $lignes]);
    }

    private function aucuneTrace(): void
    {
        $this->assertSame(0, CustomerReminder::count());
        $this->assertSame(0, AuditLog::where('action', 'customer_reminder.sent_email')->count());
    }

    /** @return array<string, array{0: string}> */
    public static function mailersSansLivraison(): array
    {
        return ['log' => ['log'], 'array' => ['array']];
    }

    /** @dataProvider mailersSansLivraison */
    public function test_le_web_refuse_la_relance_e_mail_sans_smtp_et_ne_la_trace_pas(string $mailer): void
    {
        config(['mail.default' => $mailer]);
        Mail::fake();

        Livewire::actingAs($this->vendeur)->test(RelancesClients::class)
            ->call('sendMailReminder', $this->creance->id)
            ->assertDispatched('toast', message: RelanceClientService::MOTIF_SANS_SMTP, type: 'error')
            ->assertNotDispatched('toast', message: 'Relance envoyée par email avec succès.', type: 'success');

        Mail::assertNothingSent();
        $this->aucuneTrace();
    }

    /** @dataProvider mailersSansLivraison */
    public function test_l_api_refuse_avec_le_motif_et_ne_laisse_aucune_trace(string $mailer): void
    {
        config(['mail.default' => $mailer]);
        Mail::fake();
        $r = $this->relance();

        $this->pousser([$r])->assertOk()
            ->assertJsonPath('customer_reminders.rejected.0.id', $r['id'])
            ->assertJsonPath('customer_reminders.rejected.0.reason', "Aucun serveur SMTP n'est configuré : la relance n'a pas été envoyée. Configurez l'e-mail dans Paramètres > Email (SMTP).")
            ->assertJsonCount(0, 'customer_reminders.accepted');

        Mail::assertNothingSent();
        $this->aucuneTrace();
    }

    public function test_avec_un_hote_smtp_enregistre_la_relance_part_et_est_tracee(): void
    {
        config(['mail.default' => 'log']);
        CompanySetting::current()->update(['smtp_host' => 'smtp.exemple.bj']);
        Mail::fake();
        $r = $this->relance();

        $this->pousser([$r])->assertOk()->assertJsonPath('customer_reminders.accepted.0', $r['id']);

        Mail::assertSent(CustomerReminderMail::class, 1);
        $this->assertSame(1, CustomerReminder::count());
        $this->assertSame(1, AuditLog::where('action', 'customer_reminder.sent_email')->count());
    }

    public function test_un_mailer_reel_dans_l_environnement_suffit_sans_hote_en_base(): void
    {
        config(['mail.default' => 'smtp']);
        Mail::fake();

        $this->pousser([$this->relance()])->assertOk()->assertJsonCount(1, 'customer_reminders.accepted');

        Mail::assertSent(CustomerReminderMail::class, 1);
    }

    public function test_un_e_mail_deja_parti_du_poste_n_exige_pas_de_smtp_au_serveur(): void
    {
        config(['mail.default' => 'array']);
        Mail::fake();
        $r = $this->relance(['already_sent' => true]);

        $this->pousser([$r])->assertOk()->assertJsonPath('customer_reminders.accepted.0', $r['id']);

        Mail::assertNothingSent();
        $this->assertSame(1, CustomerReminder::count());
    }

    public function test_whatsapp_appel_et_courrier_restent_des_traces_sans_smtp(): void
    {
        config(['mail.default' => 'array']);

        foreach (['whatsapp', 'appel', 'courrier'] as $canal) {
            $r = $this->relance(['channel' => $canal]);
            $this->pousser([$r])->assertOk()->assertJsonPath('customer_reminders.accepted.0', $r['id']);
            $this->assertSame(1, AuditLog::where('action', 'customer_reminder.sent_'.$canal)->count());
        }
    }

    public function test_l_adresse_manquante_garde_son_propre_motif(): void
    {
        config(['mail.default' => 'array']);
        $sansMail = Customer::create(['name' => 'Sans Mail', 'phone' => '+22997000000', 'is_active' => true]);

        $this->pousser([$this->relance(['customer_id' => $sansMail->id, 'receivable_id' => null])])
            ->assertJsonPath('customer_reminders.rejected.0.reason', fn ($m) => str_contains($m, "pas d'adresse email"));
    }
}
