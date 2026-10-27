<?php

namespace Tests\Feature;

use App\Livewire\Ventes\ProfileClient;
use App\Livewire\Ventes\SuiviDettes;
use App\Models\AccountingEntry;
use App\Models\AccountingEntryLine;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\Customer;
use App\Models\FiscalYear;
use App\Models\Permission;
use App\Models\Receivable;
use App\Models\ReceivablePayment;
use App\Models\Role;
use App\Models\TreasuryAccount;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket VC-1 — L'ENCAISSEMENT D'UNE CRÉANCE CLIENT S'ÉCRIT AU POSTE.
 *
 * Le poste n'envoie que le FAIT (`receivable_payments` : client, créance visée ou non, compte, montant, jour) ; le
 * serveur applique les effets par `CustomerSettlementService`, le point de passage de `SuiviDettes` et de
 * `ProfileClient` : créance, trésorerie (DEUX livres), écriture D 5xx / C 411, audit — dans une transaction. Le renvoi
 * d'un envoi dont l'accusé s'est perdu ne rejoue RIEN.
 */
class SyncEncaissementCreanceTest extends TestCase
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
            'label' => 'Caisse Physique', 'account_code' => '531', 'type' => 'caisse', 'balance' => 100000, 'is_active' => true,
        ]);

        FiscalYear::create([
            'year' => (int) now()->format('Y'),
            'start_date' => now()->startOfYear()->toDateString(),
            'end_date' => now()->endOfYear()->toDateString(),
            'status' => 'ouvert',
        ]);
        foreach ([['411', 'Clients', 4], ['531', 'Caisse', 5]] as [$code, $libelle, $classe]) {
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

    private function creance(float $montant, int $echeanceDans = 10, float $paye = 0): Receivable
    {
        return Receivable::create([
            'customer_id' => $this->client->id, 'amount' => $montant, 'amount_paid' => $paye,
            'due_date' => now()->addDays($echeanceDans)->toDateString(), 'status' => 'en_cours',
        ]);
    }

    /** @return array<string, mixed> */
    private function encaissement(array $remplace = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'customer_id' => $this->client->id,
            'treasury_account_id' => $this->caisse->id,
            'amount' => 30000,
            'payment_date' => now()->toDateString(),
        ], $remplace);
    }

    private function pousser(array $lignes, ?User $qui = null): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($qui ?? $this->vendeur, 'sanctum')
            ->postJson('/api/sync/push', ['device_id' => 'poste-test', 'receivable_payments' => $lignes]);
    }

    private function solde(string $code): float
    {
        $compte = ChartOfAccount::where('code', $code)->first();

        return (float) AccountingEntryLine::where('account_id', $compte->id)->sum('debit')
            - (float) AccountingEntryLine::where('account_id', $compte->id)->sum('credit');
    }

    public function test_un_encaissement_du_poste_solde_la_creance_entre_en_caisse_et_passe_l_ecriture(): void
    {
        $creance = $this->creance(100000);
        $e = $this->encaissement(['receivable_id' => $creance->id]);

        $this->pousser([$e])->assertOk()->assertJsonPath('receivable_payments.accepted.0', $e['id']);

        $this->assertEquals(30000, (float) $creance->fresh()->amount_paid);
        $this->assertEquals(130000, (float) $this->caisse->fresh()->balance, 'solde du compte');
        $this->assertEquals(30000, $this->solde('531'), 'classe 5');
        $this->assertEquals(-30000, $this->solde('411'));
        $this->assertSame(1, AccountingEntry::where('source_type', 'receivable_settlement')->count());
        $this->assertSame(1, AuditLog::where('action', 'receivable.payment_recorded')->count());
        $p = ReceivablePayment::find($e['id']);
        $this->assertSame('poste-test', $p->device_id);
        $this->assertEquals(30000, (float) $p->applied_amount);
    }

    public function test_un_envoi_rejoue_ne_rejoue_rien(): void
    {
        $creance = $this->creance(100000);
        $e = $this->encaissement(['receivable_id' => $creance->id]);

        $this->pousser([$e])->assertOk();
        $this->pousser([$e])->assertOk()->assertJsonPath('receivable_payments.accepted.0', $e['id']);

        $this->assertEquals(30000, (float) $creance->fresh()->amount_paid);
        $this->assertEquals(130000, (float) $this->caisse->fresh()->balance);
        $this->assertSame(1, AccountingEntry::where('source_type', 'receivable_settlement')->count());
    }

    public function test_seule_la_part_imputee_entre_en_caisse_jamais_le_montant_saisi(): void
    {
        $creance = $this->creance(20000);

        $this->pousser([$this->encaissement(['receivable_id' => $creance->id, 'amount' => 50000])])->assertOk();

        $this->assertEquals(20000, (float) $creance->fresh()->amount_paid);
        $this->assertSame('soldee', $creance->fresh()->status);
        $this->assertEquals(120000, (float) $this->caisse->fresh()->balance);
        $this->assertEquals(20000, $this->solde('531'));
    }

    public function test_sans_creance_visee_le_versement_apure_les_plus_anciennes_d_abord(): void
    {
        $recente = $this->creance(50000, 30);
        $ancienne = $this->creance(40000, 5);

        $this->pousser([$this->encaissement(['amount' => 60000])])->assertOk();

        $this->assertEquals(40000, (float) $ancienne->fresh()->amount_paid);
        $this->assertEquals(20000, (float) $recente->fresh()->amount_paid);
        $this->assertSame(1, AccountingEntry::where('source_type', 'receivable_settlement')->count(), 'UNE écriture pour le versement');
        $this->assertEquals(160000, (float) $this->caisse->fresh()->balance);
    }

    public function test_les_refus_sont_motives_et_n_ecrivent_rien(): void
    {
        $soldee = $this->creance(10000, 5, 10000);
        $autre = Customer::create(['name' => 'Autre client', 'is_active' => true]);
        $creanceAutre = Receivable::create(['customer_id' => $autre->id, 'amount' => 9000, 'amount_paid' => 0, 'due_date' => now()->toDateString(), 'status' => 'en_cours']);

        $sansCreance = Customer::create(['name' => 'Sans créance', 'is_active' => true]);

        $cas = [
            'créance déjà soldée' => [$this->encaissement(['receivable_id' => $soldee->id]), 'déjà soldée'],
            "créance d'un autre client" => [$this->encaissement(['receivable_id' => $creanceAutre->id]), "n'appartient pas"],
            'créance inconnue' => [$this->encaissement(['receivable_id' => (string) Str::uuid()]), 'introuvable'],
            'client sans créance' => [$this->encaissement(['customer_id' => $sansCreance->id, 'amount' => 1]), 'aucune créance'],
            'montant nul' => [$this->encaissement(['amount' => 0]), 'montant'],
            'jour futur' => [$this->encaissement(['payment_date' => now()->addDay()->toDateString()]), 'date'],
            'compte inconnu' => [$this->encaissement(['treasury_account_id' => (string) Str::uuid()]), 'trésorerie'],
        ];
        foreach ($cas as $nom => [$ligne, $attendu]) {
            $reponse = $this->pousser([$ligne])->assertOk();
            $this->assertSame([], $reponse->json('receivable_payments.accepted'), $nom);
            if ($attendu !== null) {
                $this->assertStringContainsStringIgnoringCase($attendu, $reponse->json('receivable_payments.rejected.0.reason'), $nom);
            }
        }
        $this->assertEquals(100000, (float) $this->caisse->fresh()->balance);
        $this->assertSame(0, AccountingEntry::count());
        $this->assertSame(0, ReceivablePayment::count());
    }

    public function test_exercice_clos_refuse_avec_son_motif_et_rien_ne_bouge(): void
    {
        FiscalYear::query()->update(['status' => 'cloture']);
        $creance = $this->creance(100000);

        $reponse = $this->pousser([$this->encaissement(['receivable_id' => $creance->id])])->assertOk();

        $this->assertSame([], $reponse->json('receivable_payments.accepted'));
        $this->assertNotEmpty($reponse->json('receivable_payments.rejected.0.reason'));
        $this->assertEquals(0, (float) $creance->fresh()->amount_paid);
        $this->assertEquals(100000, (float) $this->caisse->fresh()->balance);
    }

    public function test_sans_le_droit_manage_ventes_l_encaissement_est_refuse(): void
    {
        $creance = $this->creance(100000);

        $reponse = $this->pousser([$this->encaissement(['receivable_id' => $creance->id])], $this->lecteur)->assertOk();

        $this->assertSame([], $reponse->json('receivable_payments.accepted'));
        $this->assertStringContainsString('rôle', $reponse->json('receivable_payments.rejected.0.reason'));
        $this->assertEquals(0, (float) $creance->fresh()->amount_paid);
    }

    public function test_les_deux_ecrans_web_passent_par_le_meme_service(): void
    {
        $creance = $this->creance(80000);

        Livewire::actingAs($this->vendeur)->test(SuiviDettes::class)
            ->call('openPaymentModal', $creance->id)
            ->set('paymentMontant', 30000)->set('paymentTreasuryId', $this->caisse->id)
            ->call('confirmPayment')
            ->assertDispatched('toast', message: 'Règlement enregistré avec succès.', type: 'success');
        $this->assertEquals(30000, (float) $creance->fresh()->amount_paid);

        // Fiche client, règlement global : au-delà du dû, seule la part imputée entre en caisse (50 000 restent dus).
        Livewire::actingAs($this->vendeur)->test(ProfileClient::class, ['customer' => $this->client])
            ->set('regularisationMontant', 90000)->set('regularisationTreasuryId', $this->caisse->id)
            ->call('confirmRegularisation')
            ->assertDispatched('toast', message: 'Règlement enregistré avec succès.', type: 'success');

        $this->assertEquals(80000, (float) $creance->fresh()->amount_paid);
        $this->assertSame('soldee', $creance->fresh()->status);
        $this->assertEquals(180000, (float) $this->caisse->fresh()->balance, '30 000 + 50 000, pas 90 000');
        $this->assertSame(2, AccountingEntry::where('source_type', 'receivable_settlement')->count());
        $this->assertSame(0, ReceivablePayment::count(), 'un encaissement saisi au web ne laisse pas de trace d\'idempotence');
    }

    public function test_l_ecran_web_refuse_une_creance_deja_soldee_au_lieu_de_passer_une_ecriture_a_zero(): void
    {
        $creance = $this->creance(10000, 5, 10000);

        Livewire::actingAs($this->vendeur)->test(SuiviDettes::class)
            ->set('paymentTargetId', $creance->id)
            ->set('paymentMontant', 5000)->set('paymentTreasuryId', $this->caisse->id)
            ->call('confirmPayment')
            ->assertDispatched('toast', message: 'Cette créance est déjà soldée : rien à encaisser.', type: 'error');

        $this->assertEquals(100000, (float) $this->caisse->fresh()->balance);
        $this->assertSame(0, AccountingEntry::count());
    }
}
