<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\Customer;
use App\Models\CustomerAdvance;
use App\Models\FiscalYear;
use App\Models\Permission;
use App\Models\Role;
use App\Models\TreasuryAccount;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Ticket VC-4 — MODIFIER ET ARCHIVER UNE AVANCE CLIENT DEPUIS LE POSTE.
 *
 * Décision du client : « OUI LE POSTE DOIT LE FAIRE ». Le poste n'invente aucune règle : une ligne
 * DÉJÀ CONNUE passe par `CustomerAdvanceService::appliquerDuPoste`, qui appelle `modifier()` et
 * `archiver()` — les mêmes que la page « Historique des Avances ». Mêmes refus, mêmes motifs.
 */
class SyncAvancesModifierArchiverTest extends TestCase
{
    use RefreshDatabase;

    private User $vendeur;

    private User $lecteur;

    private Customer $client;

    private TreasuryAccount $caisse;

    protected function setUp(): void
    {
        parent::setUp();

        Permission::findOrCreate('manage-ventes', 'web');
        Role::findOrCreate('vendeur', 'web')->givePermissionTo('manage-ventes');
        Role::findOrCreate('lecteur', 'web');

        $this->vendeur = $this->utilisateur('vendeur');
        $this->lecteur = $this->utilisateur('lecteur');
        $this->client = Customer::create(['name' => 'AMOUSSOU Régis', 'is_active' => true]);
        $this->caisse = TreasuryAccount::create([
            'label' => 'Caisse Physique', 'account_code' => '531',
            'type' => 'caisse', 'balance' => 100000, 'is_active' => true,
        ]);

        FiscalYear::create([
            'year' => (int) now()->format('Y'),
            'start_date' => now()->startOfYear()->toDateString(),
            'end_date' => now()->endOfYear()->toDateString(),
            'status' => 'ouvert',
        ]);

        foreach ([['411', 'Clients', 4], ['419', 'Avances et acomptes reçus', 4], ['531', 'Caisse', 5]] as [$code, $libelle, $classe]) {
            ChartOfAccount::firstOrCreate(['code' => $code], ['label' => $libelle, 'class' => $classe, 'is_active' => true]);
        }
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

    /** Avance d'avant le ticket 15.19 : ni trésorerie ni écriture, donc entièrement modifiable. */
    private function avanceAncienne(float $montant = 40000, float $utilise = 0): CustomerAdvance
    {
        $a = new CustomerAdvance();
        $a->id = (string) Str::uuid();
        $a->fill([
            'customer_id' => $this->client->id, 'amount' => $montant, 'amount_used' => $utilise,
            'advance_date' => now()->toDateString(), 'is_active' => true,
        ]);
        $a->save();

        return $a;
    }

    /** Avance reçue (comptabilisée) par le chemin normal du poste. */
    private function avanceRecue(float $montant = 40000): CustomerAdvance
    {
        $ligne = $this->ligne(['amount' => $montant]);
        $this->pousser($this->vendeur, [$ligne]);

        return CustomerAdvance::findOrFail($ligne['id']);
    }

    private function ligne(array $remplace = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'customer_id' => $this->client->id,
            'treasury_account_id' => $this->caisse->id,
            'amount' => 40000,
            'advance_date' => now()->toDateString(),
            'payment_mode' => 'especes',
            'motif' => 'Réservation 50 poussins',
        ], $remplace);
    }

    private function de(CustomerAdvance $a, array $remplace = []): array
    {
        return array_merge([
            'id' => $a->id,
            'customer_id' => $a->customer_id,
            'treasury_account_id' => $a->treasury_account_id,
            'amount' => (float) $a->amount,
            'advance_date' => $a->advance_date->format('Y-m-d'),
            'payment_mode' => $a->payment_mode,
            'motif' => $a->motif,
        ], $remplace);
    }

    private function pousser(User $u, array $avances): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($u, 'sanctum')
            ->postJson('/api/sync/push', ['device_id' => 'poste-test', 'customer_advances' => $avances])
            ->assertOk();
    }

    public function test_une_ligne_identique_est_acquittee_sans_rien_rejouer(): void
    {
        $a = $this->avanceRecue();
        $avant = AuditLog::where('action', 'like', 'customer_advance.%')->count();

        $r = $this->pousser($this->vendeur, [$this->de($a)]);

        $this->assertSame([$a->id], $r->json('customer_advances.accepted'));
        $this->assertSame([], $r->json('customer_advances.rejected'));
        $this->assertSame($avant, AuditLog::where('action', 'like', 'customer_advance.%')->count(), 'rien n\'est journalisé');
        $this->assertEquals(140000, $this->caisse->fresh()->balance);
    }

    public function test_une_avance_ancienne_se_modifie_comme_au_web(): void
    {
        $a = $this->avanceAncienne();
        $autre = Customer::create(['name' => 'DOSSOU Marie', 'is_active' => true]);

        $r = $this->pousser($this->vendeur, [$this->de($a, [
            'customer_id' => $autre->id, 'amount' => 55000, 'advance_date' => now()->subDay()->toDateString(),
        ])]);

        $this->assertSame([$a->id], $r->json('customer_advances.accepted'));
        $a->refresh();
        $this->assertSame($autre->id, $a->customer_id);
        $this->assertEquals(55000, $a->amount);
        $this->assertSame(now()->subDay()->toDateString(), $a->advance_date->format('Y-m-d'));
        $this->assertSame(1, AuditLog::where('action', 'customer_advance.updated')->count());
    }

    public function test_le_montant_d_une_avance_comptabilisee_est_fige_avec_le_motif_du_web(): void
    {
        $a = $this->avanceRecue();

        $r = $this->pousser($this->vendeur, [$this->de($a, ['amount' => 50000])]);

        $this->assertSame([], $r->json('customer_advances.accepted'));
        $this->assertSame("Le montant d'une avance déjà comptabilisée ne peut plus être modifié.", $r->json('customer_advances.rejected.0.reason'));
        $this->assertEquals(40000, $a->fresh()->amount);
    }

    public function test_le_client_et_le_montant_d_une_avance_entamee_sont_figes(): void
    {
        $a = $this->avanceAncienne(40000, 10000);
        $autre = Customer::create(['name' => 'DOSSOU Marie', 'is_active' => true]);

        $r = $this->pousser($this->vendeur, [
            $this->de($a, ['amount' => 30000]),
            $this->de($a, ['customer_id' => $autre->id]),
        ]);

        $this->assertSame("Le montant d'une avance déjà entamée ne peut plus être modifié.", $r->json('customer_advances.rejected.0.reason'));
        $this->assertSame("Le client d'une avance déjà entamée ne peut plus être modifié.", $r->json('customer_advances.rejected.1.reason'));
        $this->assertEquals(40000, $a->fresh()->amount);
    }

    public function test_la_date_d_une_avance_comptabilisee_est_figee(): void
    {
        $a = $this->avanceRecue();

        $r = $this->pousser($this->vendeur, [$this->de($a, ['advance_date' => now()->subDay()->toDateString()])]);

        $this->assertStringContainsString("La date d'une avance comptabilisée ne peut plus être modifiée", $r->json('customer_advances.rejected.0.reason'));
    }

    public function test_un_client_inconnu_ou_un_montant_sous_un_franc_est_refuse(): void
    {
        $a = $this->avanceAncienne();

        $r = $this->pousser($this->vendeur, [
            $this->de($a, ['customer_id' => (string) Str::uuid()]),
            $this->de($a, ['amount' => 0.5]),
        ]);

        $this->assertSame([], $r->json('customer_advances.accepted'));
        $this->assertCount(2, $r->json('customer_advances.rejected'));
        $this->assertEquals(40000, $a->fresh()->amount);
    }

    public function test_une_avance_soldee_s_archive_et_un_renvoi_est_acquitte(): void
    {
        $a = $this->avanceAncienne(40000, 40000);

        $r = $this->pousser($this->vendeur, [$this->de($a, ['is_active' => false])]);

        $this->assertSame([$a->id], $r->json('customer_advances.accepted'));
        $this->assertFalse($a->fresh()->is_active);
        $this->assertSame(1, AuditLog::where('action', 'customer_advance.archived')->count());

        $r = $this->pousser($this->vendeur, [$this->de($a, ['is_active' => false])]);
        $this->assertSame([$a->id], $r->json('customer_advances.accepted'));
        $this->assertSame(1, AuditLog::where('action', 'customer_advance.archived')->count(), 'second archivage : rien');
    }

    public function test_une_avance_avec_un_reste_ne_s_archive_pas(): void
    {
        $a = $this->avanceAncienne(40000, 15000);

        $r = $this->pousser($this->vendeur, [$this->de($a, ['is_active' => false])]);

        $this->assertSame([], $r->json('customer_advances.accepted'));
        $this->assertSame("Cette avance a encore un reste de 25 000 FCFA : imputez-la avant de l'archiver.", $r->json('customer_advances.rejected.0.reason'));
        $this->assertTrue($a->fresh()->is_active);
    }

    public function test_une_avance_archivee_n_est_jamais_reactivee_ni_modifiee(): void
    {
        $a = $this->avanceAncienne(40000, 40000);
        $a->update(['is_active' => false]);

        $r = $this->pousser($this->vendeur, [
            $this->de($a, ['is_active' => true]),
            $this->de($a, ['amount' => 90000]),
        ]);

        $this->assertSame([], $r->json('customer_advances.accepted'));
        $this->assertCount(2, $r->json('customer_advances.rejected'));
        $this->assertFalse($a->fresh()->is_active);
        $this->assertEquals(40000, $a->fresh()->amount);
    }

    public function test_archiver_une_avance_inconnue_est_refuse_sans_la_creer(): void
    {
        $ligne = $this->ligne(['is_active' => false]);

        $r = $this->pousser($this->vendeur, [$ligne]);

        $this->assertSame([], $r->json('customer_advances.accepted'));
        $this->assertStringContainsString('inconnue du serveur', $r->json('customer_advances.rejected.0.reason'));
        $this->assertSame(0, CustomerAdvance::count());
        $this->assertEquals(100000, $this->caisse->fresh()->balance);
    }

    public function test_sans_le_droit_manage_ventes_rien_ne_bouge(): void
    {
        $a = $this->avanceAncienne(40000, 40000);

        $r = $this->pousser($this->lecteur, [$this->de($a, ['is_active' => false])]);

        $this->assertSame([], $r->json('customer_advances.accepted'));
        $this->assertStringContainsString('rôle', $r->json('customer_advances.rejected.0.reason'));
        $this->assertTrue($a->fresh()->is_active);
    }

    public function test_une_valeur_is_active_illisible_est_refusee(): void
    {
        $a = $this->avanceAncienne(40000, 40000);

        $r = $this->pousser($this->vendeur, [$this->de($a, ['is_active' => 'peut-etre'])]);

        $this->assertSame([], $r->json('customer_advances.accepted'));
        $this->assertTrue($a->fresh()->is_active);
    }
}
