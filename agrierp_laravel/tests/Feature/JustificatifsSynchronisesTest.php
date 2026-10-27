<?php

namespace Tests\Feature;

use App\Livewire\Achats\EnregistrerAchat;
use App\Models\ChartOfAccount;
use App\Models\Expense;
use App\Models\FiscalYear;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Purchase;
use App\Models\Role;
use App\Models\Supplier;
use App\Models\TreasuryAccount;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket AC-3 — LES JUSTIFICATIFS SONT RATTACHÉS, LUS ET SYNCHRONISÉS.
 *
 * Avant : le web rangeait le fichier d'un achat sans le relier à rien, aucun écran ne montrait ceux des dépenses, et le poste
 * gardait sa copie « jamais synchronisée ». Désormais `JustificatifService` rattache (web ET poste), la route authentifiée
 * lit, et `POST /api/sync/receipts` reçoit le fichier d'un enregistrement DÉJÀ accepté par `/sync/push`.
 */
class JustificatifsSynchronisesTest extends TestCase
{
    use RefreshDatabase;

    private User $acheteur;

    private User $lecteur;

    private Supplier $fournisseur;

    private Product $aliment;

    private TreasuryAccount $caisse;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('local');

        Permission::findOrCreate('manage-achats', 'web');
        Permission::findOrCreate('view-achats', 'web');
        Role::findOrCreate('acheteur', 'web')->givePermissionTo(['manage-achats', 'view-achats']);
        Role::findOrCreate('lecteur', 'web')->givePermissionTo('view-achats');
        $this->acheteur = $this->utilisateur('acheteur');
        $this->lecteur = $this->utilisateur('lecteur');

        $this->fournisseur = Supplier::create(['name' => 'Provenderie du Plateau', 'category' => 'Aliments', 'is_active' => true]);
        $this->aliment = Product::create([
            'sku' => 'ALI-PONTE-25', 'name' => 'Aliment ponte 25kg',
            'category_id' => ProductCategory::create(['label' => 'Aliments', 'is_active' => true])->id,
            'unit' => 'sac', 'pricing_mode' => 'fourchette', 'price_min' => 5900, 'price_max' => 5900,
            'tva_rate' => 18, 'stock_qty' => 5, 'is_active' => true,
        ]);
        $this->caisse = TreasuryAccount::create(['label' => 'Caisse Physique', 'account_code' => '531', 'type' => 'caisse', 'balance' => 100_000, 'is_active' => true]);
        FiscalYear::create([
            'year' => (int) now()->format('Y'),
            'start_date' => now()->startOfYear()->toDateString(), 'end_date' => now()->endOfYear()->toDateString(), 'status' => 'ouvert',
        ]);
        foreach ([['601', 'Achats', 6], ['401', 'Fournisseurs', 4], ['445', 'TVA récupérable', 4], ['531', 'Caisse', 5]] as [$code, $libelle, $classe]) {
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

    private function achat(): Purchase
    {
        return Purchase::create([
            'supplier_id' => $this->fournisseur->id, 'payment_mode' => 'especes', 'total' => 59000, 'purchase_date' => now()->toDateString(),
        ]);
    }

    private function depense(): Expense
    {
        $d = new Expense();
        $d->id = (string) Str::uuid();
        $d->fill(['expense_date' => now()->toDateString(), 'label' => 'Réparation', 'category' => 'Entretien', 'amount' => 10000, 'is_active' => true]);
        $d->save();

        return $d;
    }

    private function envoyer(User $u, string $table, string $id, ?UploadedFile $fichier = null)
    {
        return $this->actingAs($u, 'sanctum')->post('/api/sync/receipts', [
            'table' => $table, 'id' => $id, 'file' => $fichier ?? UploadedFile::fake()->create('recu.pdf', 120, 'application/pdf'),
        ], ['Accept' => 'application/json']);
    }

    public function test_le_web_rattache_le_justificatif_a_l_achat_et_le_relit_par_la_route_authentifiee(): void
    {
        $this->actingAs($this->acheteur);

        Livewire::test(EnregistrerAchat::class)
            ->set('supplierId', $this->fournisseur->id)
            ->set('lineProductId', $this->aliment->id)
            ->set('lineQty', 2)
            ->set('linePrice', 5900)
            ->call('addLine')
            ->set('paymentMode', 'especes')
            ->set('treasuryAccountId', $this->caisse->id)
            ->set('amountPaid', 11800)
            ->set('receiptFile', UploadedFile::fake()->image('recu.jpg'))
            ->call('submitAchat');

        $achat = Purchase::firstOrFail();
        $this->assertNotNull($achat->receipt_path, 'le fichier est relié à l\'achat');
        Storage::disk('local')->assertExists($achat->receipt_path);

        $this->actingAs($this->lecteur)->get(route('justificatifs.show', ['type' => 'achat', 'id' => $achat->id]))->assertOk();
    }

    public function test_la_lecture_exige_la_connexion_et_le_droit_et_refuse_ce_qui_n_existe_pas(): void
    {
        $achat = $this->achat();

        $this->get(route('justificatifs.show', ['type' => 'achat', 'id' => $achat->id]))->assertRedirect();
        $this->actingAs($this->acheteur)->get(route('justificatifs.show', ['type' => 'achat', 'id' => $achat->id]))->assertNotFound();
        $this->actingAs($this->acheteur)->get(route('justificatifs.show', ['type' => 'autre', 'id' => $achat->id]))->assertNotFound();

        Role::findOrCreate('sansdroit', 'web');
        $sansDroit = $this->utilisateur('sansdroit');
        $this->actingAs($sansDroit)->get(route('justificatifs.show', ['type' => 'achat', 'id' => $achat->id]))->assertForbidden();
    }

    public function test_le_poste_envoie_le_fichier_d_un_achat_et_d_une_depense_acceptes(): void
    {
        $achat = $this->achat();
        $depense = $this->depense();

        $this->envoyer($this->acheteur, 'purchases', $achat->id)->assertOk()->assertJson(['stored' => true]);
        $this->envoyer($this->acheteur, 'expenses', $depense->id, UploadedFile::fake()->image('facture.png'))->assertOk();

        $this->assertStringStartsWith('achats-recus/', $achat->fresh()->receipt_path);
        $this->assertStringStartsWith('depenses-recus/', $depense->fresh()->receipt_path);
        Storage::disk('local')->assertExists($achat->fresh()->receipt_path);
        Storage::disk('local')->assertExists($depense->fresh()->receipt_path);
        $this->actingAs($this->lecteur)->get(route('justificatifs.show', ['type' => 'depense', 'id' => $depense->id]))->assertOk();
    }

    public function test_renvoyer_le_fichier_remplace_l_ancien_sans_doublon(): void
    {
        $achat = $this->achat();
        $this->envoyer($this->acheteur, 'purchases', $achat->id)->assertOk();
        $premier = $achat->fresh()->receipt_path;

        $this->envoyer($this->acheteur, 'purchases', $achat->id)->assertOk();

        $second = $achat->fresh()->receipt_path;
        $this->assertNotSame($premier, $second);
        Storage::disk('local')->assertMissing($premier);
        Storage::disk('local')->assertExists($second);
        $this->assertCount(1, Storage::disk('local')->files('achats-recus'));
    }

    public function test_refus_sans_droit_enregistrement_inconnu_format_et_taille(): void
    {
        $achat = $this->achat();

        $this->envoyer($this->lecteur, 'purchases', $achat->id)->assertForbidden();
        $this->envoyer($this->acheteur, 'purchases', (string) Str::uuid())->assertNotFound();
        $this->envoyer($this->acheteur, 'purchases', $achat->id, UploadedFile::fake()->create('virus.exe', 10, 'application/octet-stream'))->assertStatus(422);
        $this->envoyer($this->acheteur, 'purchases', $achat->id, UploadedFile::fake()->create('lourd.pdf', 6000, 'application/pdf'))->assertStatus(422);
        $this->envoyer($this->acheteur, 'clients', $achat->id)->assertStatus(422);

        $this->assertNull($achat->fresh()->receipt_path);
    }
}
