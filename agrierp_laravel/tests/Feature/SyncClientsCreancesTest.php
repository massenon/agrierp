<?php

namespace Tests\Feature;

use App\Models\Customer;
use App\Models\CustomerAdvance;
use App\Models\CustomerReminder;
use App\Models\Receivable;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Tickets 14.75 + 14.76 (Sprint 14) — LE FICHIER CLIENTS, LES CRÉANCES,
 * LES AVANCES ET LES RELANCES DESCENDENT AU POSTE.
 *
 * 🔴 CE QUE CES TICKETS DÉBLOQUENT. Quatre tables réelles, alimentées depuis
 * les premiers sprints, qu'aucun tirage ne servait :
 *   • la caisse hors ligne ne pouvait NOMMER aucun client — `sales.customer_id`
 *     partait vide, et l'historique affichait « Client non synchronisé » ;
 *   • « Encours Créances » était un tiret sur le Tableau de Bord ET sur
 *     l'historique des ventes ;
 *   • le hub « Clients et Créances » (4 onglets) était impossible à bâtir ;
 *   • la file de relance ne distinguait pas le débiteur relancé ce matin de
 *     celui que personne n'a jamais contacté.
 *
 * ⚠️⚠️ LA RÈGLE DE SERVICE DES CRÉANCES EST CELLE DES RÉMANENCES. Une facture
 * échue il y a trois mois n'a plus bougé depuis : un tirage incrémental filtré
 * sur `updated_at` la manquerait — alors que c'est précisément celle qu'il faut
 * relancer. Ce qui reste dû descend donc SANS filtre `since`.
 *
 * ⚠️ LES QUATRE SONT SERVIES EN LECTURE SEULE. Une créance se solde par un
 * encaissement, jamais par une édition ; une relance suppose le réseau et le
 * canal mail du serveur. Le poste les affiche, il ne les modifie pas.
 */
class SyncClientsCreancesTest extends TestCase
{
    use RefreshDatabase;

    private User $utilisateur;

    private Customer $client;

    protected function setUp(): void
    {
        parent::setUp();

        $this->utilisateur = User::create([
            'name' => 'Caissier', 'username' => 'caisse',
            'email' => 'caisse@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);

        $this->client = Customer::create([
            'name' => 'AMOUSSOU Régis',
            'phone' => '+22997123456',
            'city' => 'Ikpinlè',
            'credit_limit' => 100000,
            'is_active' => true,
        ]);
    }

    private function tirer(array $parametres = []): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($this->utilisateur, 'sanctum')
            ->getJson('/api/sync/pull'.($parametres ? '?'.http_build_query($parametres) : ''));
    }

    private function creance(array $remplacements = []): Receivable
    {
        return Receivable::create(array_merge([
            'customer_id' => $this->client->id,
            'amount' => 95000,
            'amount_paid' => 0,
            'due_date' => now()->subDays(26)->toDateString(),
            'status' => 'en_cours',
        ], $remplacements));
    }

    /** 🔴→✅ Le client arrive au poste, avec de quoi l'appeler. */
    public function test_the_customer_file_reaches_the_device(): void
    {
        $this->tirer()
            ->assertOk()
            ->assertJsonCount(1, 'customers')
            ->assertJsonPath('customers.0.name', 'AMOUSSOU Régis')
            ->assertJsonPath('customers.0.phone', '+22997123456')
            ->assertJsonPath('customers.0.city', 'Ikpinlè');
    }

    /**
     * ⚠️⚠️ LE POINT CENTRAL : une facture échue il y a trois mois n'a plus
     * bougé depuis. Un tirage incrémental la manquerait si elle n'était servie
     * que sur `updated_at` — et c'est exactement celle qu'il faut relancer.
     */
    public function test_an_old_unpaid_receivable_survives_an_incremental_pull(): void
    {
        $creance = $this->creance(['due_date' => now()->subMonths(3)->toDateString()]);
        $creance->timestamps = false;
        $creance->update(['updated_at' => now()->subMonths(3)]);

        $this->tirer(['since' => now()->subDay()->toIso8601String()])
            ->assertOk()
            ->assertJsonCount(1, 'receivables')
            ->assertJsonPath('receivables.0.id', $creance->id);
    }

    /**
     * ⚠️⚠️ LE POSTE REMPLACE SA TABLE À CHAQUE TIRAGE : ce que le serveur ne
     * sert plus DISPARAÎT de sa charge. C'est la seule façon qu'une créance
     * soldée entre deux tirages quitte l'encours du poste — sinon un débiteur
     * serait relancé pour une facture qu'il a déjà payée.
     */
    public function test_a_settled_receivable_is_no_longer_served(): void
    {
        $this->creance(['amount' => 40000, 'amount_paid' => 40000, 'status' => 'soldee']);

        $this->tirer()->assertOk()->assertJsonCount(0, 'receivables');
    }

    /** Un règlement partiel reste dû : il descend, avec ce qui a déjà été payé. */
    public function test_a_partly_paid_receivable_still_descends_with_its_payment(): void
    {
        $this->creance(['amount' => 8000, 'amount_paid' => 3000]);

        $this->tirer()
            ->assertOk()
            ->assertJsonCount(1, 'receivables')
            ->assertJsonPath('receivables.0.amount', '8000.00')
            ->assertJsonPath('receivables.0.amount_paid', '3000.00');
    }

    /** L'avance suit son client, avec la part déjà imputée. */
    public function test_the_advance_reaches_the_device(): void
    {
        CustomerAdvance::create([
            'customer_id' => $this->client->id,
            'amount' => 50000,
            'amount_used' => 20000,
            'advance_date' => now()->subDays(10)->toDateString(),
            'is_active' => true,
        ]);

        $this->tirer()
            ->assertOk()
            ->assertJsonCount(1, 'customer_advances')
            ->assertJsonPath('customer_advances.0.amount_used', '20000.00');
    }

    /** Une avance archivée ne descend pas — le poste ne l'imputerait sur rien. */
    public function test_an_archived_advance_is_not_served(): void
    {
        CustomerAdvance::create([
            'customer_id' => $this->client->id,
            'amount' => 50000, 'amount_used' => 0,
            'advance_date' => now()->toDateString(), 'is_active' => false,
        ]);

        $this->tirer()->assertOk()->assertJsonCount(0, 'customer_advances');
    }

    /**
     * 🔴→✅ TICKET 14.76 — sans les relances déjà faites, le poste rappelle un
     * débiteur contacté le matin même.
     */
    public function test_the_reminders_already_sent_reach_the_device(): void
    {
        $creance = $this->creance();

        CustomerReminder::create([
            'customer_id' => $this->client->id,
            'receivable_id' => $creance->id,
            'channel' => 'whatsapp',
            'reminder_date' => now()->subDays(3)->toDateString(),
            'message' => 'Bonjour AMOUSSOU Régis, votre facture est en retard.',
        ]);

        $this->tirer()
            ->assertOk()
            ->assertJsonCount(1, 'customer_reminders')
            ->assertJsonPath('customer_reminders.0.channel', 'whatsapp')
            ->assertJsonPath('customer_reminders.0.receivable_id', $creance->id);
    }

    /**
     * ⚠️ SANS FILTRE `since`, comme les créances : une relance faite il y a
     * trois semaines n'a plus bougé depuis, et c'est justement celle qui dit
     * qu'il ne faut pas rappeler aujourd'hui.
     */
    public function test_an_old_reminder_survives_an_incremental_pull(): void
    {
        $relance = CustomerReminder::create([
            'customer_id' => $this->client->id,
            'receivable_id' => $this->creance()->id,
            'channel' => 'sms',
            'reminder_date' => now()->subWeeks(3)->toDateString(),
            'message' => 'Rappel ferme.',
        ]);
        $relance->timestamps = false;
        $relance->update(['updated_at' => now()->subWeeks(3)]);

        $this->tirer(['since' => now()->subDay()->toIso8601String()])
            ->assertOk()
            ->assertJsonCount(1, 'customer_reminders')
            ->assertJsonPath('customer_reminders.0.id', $relance->id);
    }

    /**
     * ⚠️⚠️ LES CRÉANCES ET LES RELANCES RESTENT DES RÉFÉRENTIELS : un poste qui
     * tenterait de les modifier doit être IGNORÉ, pas obéi — et le comptage
     * `referentiels_ignored` doit le dire, sinon l'écart passerait pour un succès.
     *
     * Ticket 15.18 : `customers` N'EN FAIT PLUS PARTIE — les fiches clients s'écrivent au
     * poste, sous le droit `manage-ventes` (voir `SyncClientTest`).
     * Ticket 15.19 : `customer_advances` non plus — l'avance s'encaisse au poste
     * (voir `SyncAvancesClientsTest`). Ticket VC-2 : `customer_reminders` non plus — la relance
     * s'envoie du poste (voir `SyncRelancesClientsTest`). Ne restent ignorées que les créances.
     */
    public function test_the_device_cannot_write_back_on_these_referentials(): void
    {
        $reponse = $this->actingAs($this->utilisateur, 'sanctum')->postJson('/api/sync/push', [
            'receivables' => [['id' => '11111111-1111-4111-8111-111111111111', 'amount' => 1]],
        ]);

        $reponse->assertOk();
        $this->assertGreaterThanOrEqual(1, $reponse->json('referentiels_ignored'));
        $this->assertSame('AMOUSSOU Régis', $this->client->fresh()->name);
        $this->assertSame(0, Receivable::count());
        $this->assertSame(0, CustomerReminder::count());
    }
}
