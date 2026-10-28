<?php

namespace Tests\Feature;

use App\Livewire\Ventes\RelancesClients;
use App\Mail\CustomerReminderMail;
use App\Models\AuditLog;
use App\Models\Customer;
use App\Models\CustomerReminder;
use App\Models\Permission;
use App\Models\Receivable;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket VC-2 — LES RELANCES DE CLIENTS SE FONT (ET SE DEMANDENT) AU POSTE.
 *
 * Le poste envoie le fait « relance de ce client / cette créance, par ce canal, ce message, tel jour » ; le serveur
 * (`RelanceClientService`, partagé avec `RelancesClients`) fait l'envoi que le canal exige — e-mail et SMS partent DU
 * SERVEUR — puis tient la trace. Un envoi refusé ne laisse aucune trace ; un rejeu ne renvoie rien.
 */
class SyncRelancesClientsTest extends TestCase
{
    use RefreshDatabase;

    private User $vendeur;

    private User $lecteur;

    private Customer $client;

    private Receivable $creance;

    protected function setUp(): void
    {
        parent::setUp();

        Permission::findOrCreate('manage-ventes', 'web');
        Permission::findOrCreate('view-ventes', 'web');
        Role::findOrCreate('vendeur', 'web')->givePermissionTo(['manage-ventes', 'view-ventes']);
        Role::findOrCreate('lecteur', 'web');
        $this->vendeur = $this->utilisateur('vendeur');
        $this->lecteur = $this->utilisateur('lecteur');

        $this->client = Customer::create(['name' => 'AMOUSSOU Régis', 'phone' => '+229 97 20 20 20', 'email' => 'regis@exemple.bj', 'is_active' => true]);
        $this->creance = Receivable::create([
            'customer_id' => $this->client->id, 'amount' => 100000, 'amount_paid' => 0,
            'due_date' => now()->subDays(10)->toDateString(), 'status' => 'en_retard',
        ]);
    }

    private function utilisateur(string $role): User
    {
        $u = User::create([
            'name' => ucfirst($role), 'username' => $role, 'email' => $role.'@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    /** @return array<string, mixed> */
    private function relance(array $remplace = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'customer_id' => $this->client->id,
            'receivable_id' => $this->creance->id,
            'channel' => 'whatsapp',
            'message' => 'Bonjour AMOUSSOU Régis, la facture reste impayée.',
            'reminder_date' => now()->toDateString(),
        ], $remplace);
    }

    private function pousser(array $lignes, ?User $qui = null): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($qui ?? $this->vendeur, 'sanctum')
            ->postJson('/api/sync/push', ['device_id' => 'poste-test', 'customer_reminders' => $lignes]);
    }

    public function test_whatsapp_et_courrier_ne_font_que_tenir_la_trace_avec_l_uuid_du_poste(): void
    {
        Mail::fake();
        foreach (['whatsapp', 'courrier'] as $canal) {
            $r = $this->relance(['channel' => $canal]);
            $this->pousser([$r])->assertOk()->assertJsonPath('customer_reminders.accepted.0', $r['id']);

            $ligne = CustomerReminder::find($r['id']);
            $this->assertNotNull($ligne, $canal);
            $this->assertSame($canal, $ligne->channel);
            $this->assertSame($this->creance->id, $ligne->receivable_id);
            $this->assertSame(1, AuditLog::where('action', 'customer_reminder.sent_'.$canal)->count());
        }
        Mail::assertNothingSent();
    }

    public function test_un_email_demande_au_poste_part_du_serveur_une_seule_fois(): void
    {
        Mail::fake();
        $r = $this->relance(['channel' => 'email']);

        $this->pousser([$r])->assertOk()->assertJsonPath('customer_reminders.accepted.0', $r['id']);
        $this->pousser([$r])->assertOk()->assertJsonPath('customer_reminders.accepted.0', $r['id']);

        Mail::assertSent(CustomerReminderMail::class, 1);
        $this->assertSame(1, CustomerReminder::where('id', $r['id'])->count());
    }

    public function test_un_envoi_refuse_est_rendu_avec_son_motif_et_ne_laisse_aucune_trace(): void
    {
        Mail::fake();
        $sansMail = Customer::create(['name' => 'Sans Mail', 'phone' => '+22997000000', 'is_active' => true]);
        $sansTel = Customer::create(['name' => 'Sans Tel', 'email' => 'x@exemple.bj', 'is_active' => true]);

        $cas = [
            'email sans adresse' => [$this->relance(['channel' => 'email', 'customer_id' => $sansMail->id, 'receivable_id' => null]), "pas d'adresse email"],
            'appel sans numéro' => [$this->relance(['channel' => 'appel', 'customer_id' => $sansTel->id, 'receivable_id' => null]), "pas de numéro de téléphone"],
            'whatsapp sans numéro' => [$this->relance(['channel' => 'whatsapp', 'customer_id' => $sansTel->id, 'receivable_id' => null]), "pas de numéro de téléphone"],
            'canal inconnu' => [$this->relance(['channel' => 'pigeon']), 'canal'],
            'message vide' => [$this->relance(['message' => '']), 'message'],
            'jour futur' => [$this->relance(['reminder_date' => now()->addDay()->toDateString()]), 'date'],
            'client inconnu' => [$this->relance(['customer_id' => (string) Str::uuid()]), 'client'],
        ];
        foreach ($cas as $nom => [$ligne, $attendu]) {
            $reponse = $this->pousser([$ligne])->assertOk();
            $this->assertSame([], $reponse->json('customer_reminders.accepted'), $nom);
            $this->assertStringContainsStringIgnoringCase($attendu, $reponse->json('customer_reminders.rejected.0.reason'), $nom);
        }
        $this->assertSame(0, CustomerReminder::count());
        Mail::assertNothingSent();
    }

    public function test_un_appel_ne_fait_que_tenir_la_trace_et_un_sms_n_existe_plus(): void
    {
        $r = $this->relance(['channel' => 'appel']);
        $this->pousser([$r])->assertOk()->assertJsonPath('customer_reminders.accepted.0', $r['id']);
        $this->assertSame('appel', CustomerReminder::find($r['id'])->channel);

        $sms = $this->relance(['channel' => 'sms']);
        $reponse = $this->pousser([$sms])->assertOk();
        $this->assertSame([], $reponse->json('customer_reminders.accepted'));
        $this->assertNull(CustomerReminder::find($sms['id']));
    }

    public function test_un_e_mail_deja_parti_du_poste_n_est_pas_renvoye_mais_exige_une_adresse(): void
    {
        Mail::fake();

        $r = $this->relance(['channel' => 'email', 'already_sent' => true]);
        $this->pousser([$r])->assertOk()->assertJsonPath('customer_reminders.accepted.0', $r['id']);
        $this->assertNotNull(CustomerReminder::find($r['id']));
        Mail::assertNothingSent();

        $sansMail = \App\Models\Customer::create(['name' => 'Sans Mail', 'phone' => '+22997000000', 'is_active' => true]);
        $ko = $this->relance(['channel' => 'email', 'already_sent' => true, 'customer_id' => $sansMail->id, 'receivable_id' => null]);
        $reponse = $this->pousser([$ko])->assertOk();
        $this->assertStringContainsString("pas d'adresse email", $reponse->json('customer_reminders.rejected.0.reason'));
    }

    public function test_sans_le_droit_manage_ventes_la_relance_est_refusee(): void
    {
        $reponse = $this->pousser([$this->relance()], $this->lecteur)->assertOk();

        $this->assertSame([], $reponse->json('customer_reminders.accepted'));
        $this->assertStringContainsString('rôle', $reponse->json('customer_reminders.rejected.0.reason'));
        $this->assertSame(0, CustomerReminder::count());
    }

    public function test_l_ecran_web_passe_par_le_meme_service(): void
    {
        Mail::fake();

        Livewire::actingAs($this->vendeur)->test(RelancesClients::class)
            ->call('sendMailReminder', $this->creance->id)
            ->assertDispatched('toast', message: 'Relance envoyée par email avec succès.', type: 'success');
        Mail::assertSent(CustomerReminderMail::class, 1);
        $this->assertSame(1, CustomerReminder::where('channel', 'email')->count());

        Livewire::actingAs($this->vendeur)->test(RelancesClients::class)
            ->call('sendWhatsappReminder', $this->creance->id);
        $this->assertSame(1, CustomerReminder::where('channel', 'whatsapp')->count());

        $sansMail = Customer::create(['name' => 'Sans Mail', 'is_active' => true]);
        $c2 = Receivable::create(['customer_id' => $sansMail->id, 'amount' => 5000, 'amount_paid' => 0, 'due_date' => now()->subDay()->toDateString(), 'status' => 'en_retard']);
        Livewire::actingAs($this->vendeur)->test(RelancesClients::class)
            ->call('sendMailReminder', $c2->id)
            ->assertDispatched('toast', message: "Ce client n'a pas d'adresse email enregistrée.", type: 'error');
        $this->assertSame(0, CustomerReminder::where('customer_id', $sansMail->id)->count());
    }
}
