<?php

namespace Tests\Feature;

use App\Livewire\Ventes\CreancesClientsHub;
use App\Livewire\Ventes\HistoriqueAvances;
use App\Livewire\Ventes\ListeClients;
use App\Livewire\Ventes\ProfileClient;
use App\Livewire\Ventes\RelancesClients;
use App\Livewire\Ventes\SuiviDettes;
use App\Models\Customer;
use App\Models\CustomerAdvance;
use App\Models\CustomerReminder;
use App\Models\Receivable;
use App\Models\TreasuryAccount;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket CONF-5 (1) — « CLIENTS ET CRÉANCES » EN LECTURE POUR LE COMPTABLE.
 *
 * Le comptable a `view-ventes` (CONF-4) : il CONSULTE soldes, profil et historique. Il n'a PAS `manage-ventes` : il ne relance
 * pas, n'encaisse pas, n'impute pas d'avance, ne crée ni ne modifie ni n'archive un client. Chaque méthode qui écrit (ou qui
 * ouvre la modale d'une écriture) commence par `authorize('manage-ventes')`. Rôles : le VRAI seeder.
 */
class ComptableCreancesLectureTest extends TestCase
{
    use RefreshDatabase;

    private User $comptable;

    private User $caissier;

    private Customer $client;

    private Receivable $creance;

    private TreasuryAccount $caisse;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);

        $this->comptable = $this->compte('comptable');
        $this->caissier = $this->compte('caissier');

        $this->client = Customer::create(['name' => 'AMOUSSOU Régis', 'phone' => '97123456', 'email' => 'r@x.bj', 'is_active' => true]);
        $this->creance = Receivable::create([
            'customer_id' => $this->client->id, 'amount' => 100000, 'amount_paid' => 0,
            'due_date' => now()->subDays(10)->toDateString(), 'status' => 'en_retard',
        ]);
        $this->caisse = TreasuryAccount::create(['label' => 'Caisse', 'account_code' => '531', 'type' => 'caisse', 'balance' => 0, 'is_active' => true]);
    }

    private function compte(string $role): User
    {
        $u = User::create([
            'name' => 'Compte '.$role, 'username' => 'c-'.$role, 'email' => $role.'@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    // ------------------------------------------------------------------ Lecture : le comptable consulte

    public function test_le_comptable_ouvre_les_pages_clients_et_creances_en_lecture(): void
    {
        $this->actingAs($this->comptable);

        $this->get('/creances-clients')->assertOk();
        $this->get('/clients/'.$this->client->id.'/profil')->assertOk()->assertSee('AMOUSSOU Régis');
        foreach ([ListeClients::class, SuiviDettes::class, RelancesClients::class, HistoriqueAvances::class, CreancesClientsHub::class] as $c) {
            Livewire::test($c)->assertOk();
        }
        Livewire::test(ProfileClient::class, ['customer' => $this->client])->assertOk();
    }

    public function test_les_boutons_d_ecriture_ne_sont_pas_montres_au_comptable_et_le_sont_au_caissier(): void
    {
        $this->actingAs($this->comptable);
        Livewire::test(ListeClients::class)
            ->assertDontSee('wire:click="newCustomer"', false)->assertDontSee('wire:click="editCustomer', false)->assertDontSee('openBulkArchiveModal', false);
        Livewire::test(ProfileClient::class, ['customer' => $this->client])
            ->assertDontSee('wire:click="openGlobalRegularisation"', false)->assertDontSee('wire:click="sendQuickReminder"', false);
        Livewire::test(RelancesClients::class)
            ->assertDontSee('sendMailReminder', false)->assertDontSee('sendWhatsappReminder', false)->assertDontSee('callReminder', false);

        $this->actingAs($this->caissier);
        Livewire::test(ListeClients::class)->assertSee('wire:click="newCustomer"', false);
        Livewire::test(ProfileClient::class, ['customer' => $this->client])->assertSee('wire:click="openGlobalRegularisation"', false);
        Livewire::test(RelancesClients::class)->assertSee('sendMailReminder', false);
    }

    // ------------------------------------------------------------------ Écriture : 403 sur chaque geste

    public function test_chaque_geste_d_ecriture_est_refuse_au_comptable_et_n_ecrit_rien(): void
    {
        $this->actingAs($this->comptable);

        Livewire::test(ListeClients::class)->call('newCustomer')->assertForbidden();
        Livewire::test(ListeClients::class)->call('editCustomer', $this->client->id)->assertForbidden();
        Livewire::test(ListeClients::class)->set('name', 'Nouveau')->call('saveCustomer')->assertForbidden();
        Livewire::test(ListeClients::class)->call('archiveCustomer', $this->client->id)->assertForbidden();
        Livewire::test(ListeClients::class)->set('selectedIds', [$this->client->id])->call('openBulkArchiveModal')->assertForbidden();
        Livewire::test(ListeClients::class)->set('selectedIds', [$this->client->id])->call('bulkArchiveCustomers')->assertForbidden();

        $profil = fn () => Livewire::test(ProfileClient::class, ['customer' => $this->client]);
        $profil()->call('openGlobalRegularisation')->assertForbidden();
        $profil()->call('openReceivableRegularisation', $this->creance->id)->assertForbidden();
        $profil()->set('regularisationMontant', 1000)->set('regularisationTreasuryId', $this->caisse->id)->call('confirmRegularisation')->assertForbidden();
        $profil()->call('sendQuickReminder')->assertForbidden();

        Livewire::test(SuiviDettes::class)->call('openPaymentModal', $this->creance->id)->assertForbidden();
        Livewire::test(SuiviDettes::class)->set('paymentTargetId', $this->creance->id)->set('paymentMontant', 1000)->set('paymentTreasuryId', $this->caisse->id)->call('confirmPayment')->assertForbidden();
        Livewire::test(SuiviDettes::class)->call('sendReminder', $this->creance->id)->assertForbidden();

        Livewire::test(RelancesClients::class)->call('sendMailReminder', $this->creance->id)->assertForbidden();
        Livewire::test(RelancesClients::class)->call('sendWhatsappReminder', $this->creance->id)->assertForbidden();
        Livewire::test(RelancesClients::class)->call('callReminder', $this->creance->id)->assertForbidden();

        Livewire::test(HistoriqueAvances::class)->call('newAdvance')->assertForbidden();
        Livewire::test(HistoriqueAvances::class)->call('saveAdvance')->assertForbidden();
        Livewire::test(HistoriqueAvances::class)->call('openImputationModal', 'x')->assertForbidden();
        Livewire::test(HistoriqueAvances::class)->call('confirmImputation')->assertForbidden();
        Livewire::test(HistoriqueAvances::class)->call('archiveAdvance', 'x')->assertForbidden();

        $this->assertSame(1, Customer::count());
        $this->assertTrue($this->client->fresh()->is_active);
        $this->assertSame(0.0, (float) $this->creance->fresh()->amount_paid);
        $this->assertSame(0, CustomerReminder::count());
        $this->assertSame(0, CustomerAdvance::count());
    }

    public function test_le_caissier_garde_ses_gestes_clients_et_creances(): void
    {
        $this->actingAs($this->caissier);

        Livewire::test(ListeClients::class)->call('newCustomer')->assertOk();
        Livewire::test(ListeClients::class)->call('editCustomer', $this->client->id)->assertOk();
        Livewire::test(ProfileClient::class, ['customer' => $this->client])->call('openGlobalRegularisation')->assertOk();
        Livewire::test(SuiviDettes::class)->call('openPaymentModal', $this->creance->id)->assertOk();
        Livewire::test(HistoriqueAvances::class)->call('newAdvance')->assertOk();
        Livewire::test(RelancesClients::class)->call('callReminder', $this->creance->id)->assertOk();
        $this->assertSame(1, CustomerReminder::count());
    }

    // ------------------------------------------------------------------ Gardes qui lisent les sources (mutations)

    public function test_source_chaque_methode_qui_ecrit_commence_par_la_garde_manage_ventes(): void
    {
        $attendu = [
            'ListeClients' => ['newCustomer', 'editCustomer', 'saveCustomer', 'archiveCustomer', 'bulkArchiveCustomers', 'openBulkArchiveModal'],
            'ProfileClient' => ['openGlobalRegularisation', 'openReceivableRegularisation', 'confirmRegularisation', 'sendQuickReminder'],
            'SuiviDettes' => ['openPaymentModal', 'confirmPayment', 'sendReminder'],
            'RelancesClients' => ['sendMailReminder', 'sendWhatsappReminder', 'callReminder'],
            'HistoriqueAvances' => ['newAdvance', 'editAdvance', 'saveAdvance', 'openImputationModal', 'confirmImputation', 'archiveAdvance'],
        ];
        foreach ($attendu as $classe => $methodes) {
            $source = file_get_contents(base_path("app/Livewire/Ventes/{$classe}.php"));
            foreach ($methodes as $m) {
                $this->assertMatchesRegularExpression(
                    '/function '.$m.'\([^)]*\)[^{]*\{\s*\$this->authorize\(\'manage-ventes\'\);/',
                    $source,
                    "{$classe}::{$m} doit commencer par authorize('manage-ventes')",
                );
            }
        }
    }
}
