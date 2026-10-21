<?php

namespace Tests\Feature;

use App\Models\Notification;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 15.10 — les notifications descendent au poste (`/sync/pull`) et s'y
 * marquent lues ou se suppriment.
 */
class ApiNotificationsTest extends TestCase
{
    use RefreshDatabase;

    private const MDP = 'AgriERP@2026';

    private User $caissier;

    private User $animalier;

    protected function setUp(): void
    {
        parent::setUp();

        Role::findOrCreate('caissier', 'web');
        Role::findOrCreate('animalier', 'web');

        $this->caissier = $this->utilisateur('caisse', 'caissier');
        $this->animalier = $this->utilisateur('animal', 'animalier');
    }

    private function utilisateur(string $username, string $role): User
    {
        $u = User::create([
            'name' => ucfirst($username),
            'username' => $username,
            'email' => $username.'@fermeolouwachegoun.com',
            'password' => bcrypt(self::MDP),
            'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    private function jeton(string $username): string
    {
        return $this->postJson('/api/auth/login', [
            'identifiant' => $username,
            'password' => self::MDP,
            'device_name' => 'poste-'.$username,
        ])->json('token');
    }

    private function notif(array $attributs = []): Notification
    {
        return Notification::create(array_merge([
            'type' => 'stock_low',
            'severity' => 'critique',
            'title' => 'Seuil critique',
            'message' => 'Vaccin Newcastle (2 boîtes restantes)',
        ], $attributs));
    }

    private function avec(string $jeton)
    {
        return $this->withHeader('Authorization', 'Bearer '.$jeton);
    }

    public function test_le_tirage_ne_sert_que_les_notifications_visibles_par_le_jeton(): void
    {
        $miennes = $this->notif(['user_id' => $this->caissier->id]);
        $dureole = $this->notif(['target_role' => 'caissier', 'type' => 'payment_due', 'severity' => 'moyen']);
        $this->notif(['user_id' => $this->animalier->id]);
        $this->notif(['target_role' => 'animalier']);

        $ids = collect(
            $this->avec($this->jeton('caisse'))->getJson('/api/sync/pull')->assertOk()->json('notifications')
        )->pluck('id');

        $this->assertEqualsCanonicalizing([$miennes->id, $dureole->id], $ids->all());
    }

    public function test_la_categorie_vient_du_serveur(): void
    {
        $this->notif(['user_id' => $this->caissier->id, 'type' => 'payment_due']);

        $ligne = $this->avec($this->jeton('caisse'))->getJson('/api/sync/pull')->json('notifications.0');

        $this->assertSame('Finance', $ligne['category']);
        $this->assertSame('critique', $ligne['severity']);
        $this->assertArrayHasKey('is_read', $ligne);
        $this->assertArrayHasKey('link_url', $ligne);
    }

    public function test_marquer_lue(): void
    {
        $n = $this->notif(['user_id' => $this->caissier->id]);

        $this->avec($this->jeton('caisse'))
            ->postJson("/api/notifications/{$n->id}/read")
            ->assertOk();

        $this->assertTrue($n->fresh()->is_read);
        $this->assertNotNull($n->fresh()->read_at);
    }

    public function test_supprimer(): void
    {
        $n = $this->notif(['user_id' => $this->caissier->id]);

        $this->avec($this->jeton('caisse'))
            ->deleteJson("/api/notifications/{$n->id}")
            ->assertOk();

        $this->assertDatabaseMissing('notifications', ['id' => $n->id]);
    }

    public function test_la_notification_d_un_autre_repond_404_et_reste_intacte(): void
    {
        $autre = $this->notif(['user_id' => $this->animalier->id]);
        $jeton = $this->jeton('caisse');

        $this->avec($jeton)->postJson("/api/notifications/{$autre->id}/read")->assertNotFound();
        $this->avec($jeton)->deleteJson("/api/notifications/{$autre->id}")->assertNotFound();

        $this->assertFalse($autre->fresh()->is_read);
        $this->assertDatabaseHas('notifications', ['id' => $autre->id]);
    }

    public function test_les_routes_sont_fermees_sans_jeton(): void
    {
        $n = $this->notif(['user_id' => $this->caissier->id]);

        $this->postJson("/api/notifications/{$n->id}/read")->assertStatus(401);
        $this->deleteJson("/api/notifications/{$n->id}")->assertStatus(401);
    }

    public function test_un_envoi_de_notifications_par_le_poste_est_ignore(): void
    {
        $reponse = $this->avec($this->jeton('caisse'))->postJson('/api/sync/push', [
            'notifications' => [['id' => 'x', 'message' => 'forgé']],
        ])->assertOk();

        $this->assertGreaterThanOrEqual(1, $reponse->json('referentiels_ignored'));
        $this->assertDatabaseCount('notifications', 0);
    }
}
