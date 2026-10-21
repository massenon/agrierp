<?php

namespace Tests\Feature;

use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\Payable;
use App\Models\Permission;
use App\Models\Role;
use App\Models\Supplier;
use App\Models\SupplierPayment;
use App\Models\TreasuryAccount;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Ticket 15.16 — règlement fournisseur envoyé par un poste (`supplier_payments`).
 *
 * ⚠️⚠️ CE QUE CES TESTS PROTÈGENT. Un règlement porte TROIS effets : l'imputation
 * sur les dettes les plus anciennes, la sortie de trésorerie et l'écriture 401/5xx.
 * Le poste n'en applique aucun : il envoie « tant, depuis ce compte », et le serveur
 * rejoue. Et le renvoi d'un règlement dont l'accusé s'est perdu ne doit RIEN
 * rejouer — sinon la trésorerie est décaissée deux fois.
 */
class SyncReglementFournisseurTest extends TestCase
{
    use RefreshDatabase;

    private User $acheteur;

    private User $caissier;

    private Supplier $fournisseur;

    private TreasuryAccount $caisse;

    protected function setUp(): void
    {
        parent::setUp();

        Permission::findOrCreate('manage-achats', 'web');
        Role::findOrCreate('acheteur', 'web')->givePermissionTo('manage-achats');
        Role::findOrCreate('caissier', 'web');

        $this->acheteur = $this->utilisateur('acheteur');
        $this->caissier = $this->utilisateur('caissier');

        $this->fournisseur = Supplier::create([
            'name' => 'Provenderie du Plateau', 'category' => 'Aliments', 'is_active' => true,
        ]);

        $this->caisse = TreasuryAccount::create([
            'label' => 'Caisse Physique', 'account_code' => '531',
            'type' => 'caisse', 'balance' => 500000, 'is_active' => true,
        ]);

        FiscalYear::create([
            'year' => (int) now()->format('Y'),
            'start_date' => now()->startOfYear()->toDateString(),
            'end_date' => now()->endOfYear()->toDateString(),
            'status' => 'ouvert',
        ]);

        foreach ([['401', 'Fournisseurs', 4], ['531', 'Caisse', 5]] as [$code, $libelle, $classe]) {
            ChartOfAccount::firstOrCreate(['code' => $code], [
                'label' => $libelle, 'class' => $classe, 'is_active' => true,
            ]);
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

    private function dette(float $montant, string $echeance, float $paye = 0): Payable
    {
        return Payable::create([
            'supplier_id' => $this->fournisseur->id,
            'amount' => $montant,
            'amount_paid' => $paye,
            'due_date' => $echeance,
            'status' => 'en_cours',
        ]);
    }

    private function reglement(array $remplace = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'supplier_id' => $this->fournisseur->id,
            'treasury_account_id' => $this->caisse->id,
            'amount' => 60000,
            'payment_date' => now()->toDateString(),
        ], $remplace);
    }

    private function pousser(User $u, array ...$reglements): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($u, 'sanctum')->postJson('/api/sync/push', [
            'device_id' => 'poste-test',
            'supplier_payments' => $reglements,
        ])->assertOk();
    }

    public function test_le_reglement_solde_les_dettes_les_plus_anciennes_d_abord(): void
    {
        $recente = $this->dette(50000, now()->addDays(20)->toDateString());
        $ancienne = $this->dette(40000, now()->subDays(10)->toDateString());

        $p = $this->reglement(['amount' => 60000]);
        $r = $this->pousser($this->acheteur, $p);

        $this->assertSame([$p['id']], $r->json('supplier_payments.accepted'));
        // 60 000 : 40 000 sur l'ancienne (soldée), 20 000 sur la récente.
        $this->assertSame('soldee', $ancienne->fresh()->status);
        $this->assertEquals(40000, $ancienne->fresh()->amount_paid);
        $this->assertEquals(20000, $recente->fresh()->amount_paid);
    }

    public function test_la_tresorerie_et_le_journal_concordent(): void
    {
        $this->dette(80000, now()->toDateString());

        $this->pousser($this->acheteur, $this->reglement(['amount' => 60000]));

        $this->assertEquals(440000, $this->caisse->fresh()->balance);

        $ecriture = AccountingEntry::where('source_type', 'payable_settlement')->first();
        $this->assertNotNull($ecriture, 'toute opération financière produit son écriture');
        $this->assertEquals(60000, $ecriture->lines()->sum('debit'));
        $this->assertEquals(60000, $ecriture->lines()->sum('credit'));
    }

    public function test_un_versement_superieur_au_du_ne_sort_que_la_part_imputee(): void
    {
        $this->dette(30000, now()->toDateString());

        $p = $this->reglement(['amount' => 100000]);
        $this->pousser($this->acheteur, $p);

        // Seuls 30 000 existent : 30 000 sortent, pas 100 000.
        $this->assertEquals(470000, $this->caisse->fresh()->balance);
        $this->assertEquals(30000, SupplierPayment::find($p['id'])->applied_amount);
        $this->assertEquals(30000, AccountingEntry::where('source_type', 'payable_settlement')->first()->lines()->sum('debit'));
    }

    public function test_un_renvoi_ne_decaisse_pas_deux_fois(): void
    {
        $this->dette(100000, now()->toDateString());
        $p = $this->reglement(['amount' => 60000]);

        $this->pousser($this->acheteur, $p);
        $r = $this->pousser($this->acheteur, $p);

        $this->assertSame([$p['id']], $r->json('supplier_payments.accepted'));
        $this->assertEquals(440000, $this->caisse->fresh()->balance, 'décaissé une seule fois');
        $this->assertSame(1, AccountingEntry::where('source_type', 'payable_settlement')->count());
        $this->assertSame(1, SupplierPayment::count());
    }

    public function test_sans_dette_ouverte_le_reglement_est_refuse_avec_son_motif(): void
    {
        $p = $this->reglement();
        $r = $this->pousser($this->acheteur, $p);

        $this->assertSame([], $r->json('supplier_payments.accepted'));
        $this->assertStringContainsString('aucune dette', $r->json('supplier_payments.rejected.0.reason'));
        $this->assertEquals(500000, $this->caisse->fresh()->balance);
    }

    public function test_sans_le_droit_manage_achats_rien_ne_bouge(): void
    {
        $this->dette(80000, now()->toDateString());

        $r = $this->pousser($this->caissier, $this->reglement());

        $this->assertSame([], $r->json('supplier_payments.accepted'));
        $this->assertStringContainsString('rôle', $r->json('supplier_payments.rejected.0.reason'));
        $this->assertEquals(500000, $this->caisse->fresh()->balance);
    }

    public function test_un_exercice_clos_refuse_ce_reglement_sans_decaisser(): void
    {
        FiscalYear::query()->update(['status' => 'cloture']);
        $this->dette(80000, now()->toDateString());

        $r = $this->pousser($this->acheteur, $this->reglement());

        $this->assertSame([], $r->json('supplier_payments.accepted'));
        $this->assertCount(1, $r->json('supplier_payments.rejected'));
        $this->assertEquals(500000, $this->caisse->fresh()->balance, 'transaction annulée');
    }

    public function test_montant_fournisseur_et_compte_sont_valides(): void
    {
        $this->dette(80000, now()->toDateString());

        $r = $this->pousser(
            $this->acheteur,
            $this->reglement(['amount' => 0]),
            $this->reglement(['supplier_id' => (string) Str::uuid()]),
            $this->reglement(['treasury_account_id' => (string) Str::uuid()]),
        );

        $this->assertCount(3, $r->json('supplier_payments.rejected'));
        $this->assertEquals(500000, $this->caisse->fresh()->balance);
    }
}
