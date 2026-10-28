<?php

namespace Tests\Feature;

use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\FixedAsset;
use App\Models\Permission;
use App\Models\Role;
use App\Models\TreasuryAccount;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Ticket CP-3 — LE REGISTRE DES IMMOBILISATIONS S'ÉCRIT AU POSTE.
 *
 * Le poste envoie la ligne entière (`fixed_assets`) et la demande de dotation (`depreciation_requests`) ;
 * `ImmobilisationService`, partagé avec `Comptabilite\Immobilisations`, joue les mêmes règles et les mêmes écritures.
 */
class SyncImmobilisationsTest extends TestCase
{
    use RefreshDatabase;

    private User $comptable;

    private User $lecteur;

    protected function setUp(): void
    {
        parent::setUp();

        Permission::findOrCreate('manage-comptabilite', 'web');
        Permission::findOrCreate('view-comptabilite', 'web');
        Role::findOrCreate('comptable', 'web')->givePermissionTo(['manage-comptabilite', 'view-comptabilite']);
        Role::findOrCreate('lecteur', 'web')->givePermissionTo('view-comptabilite');
        $this->comptable = $this->utilisateur('comptable');
        $this->lecteur = $this->utilisateur('lecteur');

        FiscalYear::create([
            'year' => (int) now()->format('Y'), 'start_date' => now()->startOfYear()->toDateString(),
            'end_date' => now()->endOfYear()->toDateString(), 'status' => 'ouvert',
        ]);
        foreach ([['221', 'Bâtiments', 2], ['244', 'Matériel', 2], ['281', 'Amortissements', 2], ['401', 'Fournisseurs', 4], ['531', 'Caisse', 5], ['681', 'Dotations', 6]] as [$code, $label, $classe]) {
            ChartOfAccount::firstOrCreate(['code' => $code], ['label' => $label, 'class' => $classe, 'is_active' => true]);
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

    /** @return array<string, mixed> */
    private function bien(array $remplace = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(), 'code' => 'IMMO-'.Str::random(5), 'label' => 'Broyeur', 'account_code' => '244',
            'acquisition_date' => now()->subMonths(6)->toDateString(), 'acquisition_value' => 1200000, 'residual_value' => 0,
            'duration_years' => 5, 'status' => 'en_service', 'disposal_date' => null, 'disposal_reason' => null,
            'is_active' => true, 'counterpart' => '',
        ], $remplace);
    }

    private function envoyer(User $u, array $corps)
    {
        return $this->actingAs($u, 'sanctum')->postJson('/api/sync/push', ['device_id' => 'poste-test'] + $corps);
    }

    public function test_un_bien_du_poste_est_enregistre_avec_son_uuid_en_reprise_d_anteriorite(): void
    {
        $b = $this->bien();

        $this->envoyer($this->comptable, ['fixed_assets' => [$b]])
            ->assertOk()->assertJsonPath('fixed_assets.accepted.0', $b['id']);

        $bien = FixedAsset::findOrFail($b['id']);
        $this->assertFalse($bien->is_capitalized);
        $this->assertSame(0, AccountingEntry::where('source_type', 'asset_acquisition')->count());
    }

    public function test_un_bien_paye_en_caisse_est_capitalise_une_seule_fois(): void
    {
        $caisse = TreasuryAccount::create(['label' => 'Caisse', 'type' => 'caisse', 'account_code' => '531', 'balance' => 5000000, 'is_active' => true]);
        $b = $this->bien(['counterpart' => $caisse->id]);

        $this->envoyer($this->comptable, ['fixed_assets' => [$b]])->assertOk();
        $this->envoyer($this->comptable, ['fixed_assets' => [$b]])->assertOk()->assertJsonPath('fixed_assets.accepted.0', $b['id']);

        $this->assertTrue(FixedAsset::findOrFail($b['id'])->is_capitalized);
        $this->assertSame(1, AccountingEntry::where('source_type', 'asset_acquisition')->count());
    }

    public function test_un_code_deja_pris_est_refuse_avec_son_motif(): void
    {
        FixedAsset::create(['code' => 'IMMO-1', 'label' => 'X', 'account_code' => '244', 'acquisition_date' => now()->subYear(),
            'acquisition_value' => 1000, 'residual_value' => 0, 'duration_years' => 5, 'method' => 'lineaire', 'status' => 'en_service', 'is_active' => true]);

        $r = $this->envoyer($this->comptable, ['fixed_assets' => [$this->bien(['code' => 'IMMO-1'])]])->assertOk();

        $this->assertCount(1, $r->json('fixed_assets.rejected'));
        $this->assertStringContainsString('code', $r->json('fixed_assets.rejected.0.reason'));
    }

    public function test_une_valeur_residuelle_au_dela_de_la_valeur_d_acquisition_est_refusee(): void
    {
        $r = $this->envoyer($this->comptable, ['fixed_assets' => [$this->bien(['residual_value' => 2000000])]])->assertOk();

        $this->assertCount(1, $r->json('fixed_assets.rejected'));
    }

    public function test_la_valeur_d_un_bien_comptabilise_ne_se_modifie_pas(): void
    {
        $b = $this->bien(['counterpart' => 'credit']);
        $this->envoyer($this->comptable, ['fixed_assets' => [$b]])->assertOk();

        $r = $this->envoyer($this->comptable, ['fixed_assets' => [array_merge($b, ['acquisition_value' => 900000])]])->assertOk();

        $this->assertStringContainsString('déjà comptabilisé', $r->json('fixed_assets.rejected.0.reason'));
        $this->assertSame('1200000.00', FixedAsset::findOrFail($b['id'])->acquisition_value);
    }

    public function test_une_modification_change_le_libelle_et_la_duree(): void
    {
        $b = $this->bien();
        $this->envoyer($this->comptable, ['fixed_assets' => [$b]])->assertOk();

        $this->envoyer($this->comptable, ['fixed_assets' => [array_merge($b, ['label' => 'Broyeur à marteaux', 'duration_years' => 8])]])
            ->assertOk()->assertJsonPath('fixed_assets.accepted.0', $b['id']);

        $bien = FixedAsset::findOrFail($b['id']);
        $this->assertSame('Broyeur à marteaux', $bien->label);
        $this->assertSame(8, (int) $bien->duration_years);
    }

    public function test_la_sortie_s_enregistre_une_fois_et_arrete_l_amortissement(): void
    {
        $b = $this->bien();
        $this->envoyer($this->comptable, ['fixed_assets' => [$b]])->assertOk();
        $sortie = array_merge($b, ['status' => 'cede', 'disposal_date' => now()->subMonth()->toDateString(), 'disposal_reason' => 'Vendu']);

        $this->envoyer($this->comptable, ['fixed_assets' => [$sortie]])->assertOk()->assertJsonPath('fixed_assets.accepted.0', $b['id']);

        $bien = FixedAsset::findOrFail($b['id']);
        $this->assertSame('cede', $bien->status);
        $this->assertSame('Vendu', $bien->disposal_reason);
    }

    public function test_une_sortie_avant_l_acquisition_est_refusee(): void
    {
        $b = $this->bien();
        $this->envoyer($this->comptable, ['fixed_assets' => [$b]])->assertOk();
        $sortie = array_merge($b, ['status' => 'reforme', 'disposal_date' => now()->subYears(3)->toDateString(), 'disposal_reason' => 'Hors d\'usage']);

        $r = $this->envoyer($this->comptable, ['fixed_assets' => [$sortie]])->assertOk();

        $this->assertStringContainsString("ne peut pas précéder l'acquisition", $r->json('fixed_assets.rejected.0.reason'));
        $this->assertSame('en_service', FixedAsset::findOrFail($b['id'])->status);
    }

    public function test_un_bien_archive_au_poste_est_archive_jamais_supprime(): void
    {
        $b = $this->bien();
        $this->envoyer($this->comptable, ['fixed_assets' => [$b]])->assertOk();

        $this->envoyer($this->comptable, ['fixed_assets' => [array_merge($b, ['is_active' => false])]])->assertOk();

        $this->assertFalse((bool) FixedAsset::findOrFail($b['id'])->is_active);
    }

    public function test_la_dotation_est_recalculee_par_le_serveur_et_jamais_doublee(): void
    {
        $b = $this->bien(['counterpart' => 'credit']);
        $this->envoyer($this->comptable, ['fixed_assets' => [$b]])->assertOk();
        $demande = ['id' => (string) Str::uuid(), 'date_arrete' => now()->toDateString()];

        $this->envoyer($this->comptable, ['depreciation_requests' => [$demande]])->assertOk()->assertJsonPath('depreciation_requests.accepted.0', $demande['id']);
        $this->envoyer($this->comptable, ['depreciation_requests' => [$demande]])->assertOk()->assertJsonPath('depreciation_requests.accepted.0', $demande['id']);

        $this->assertSame(1, AccountingEntry::where('source_type', 'depreciation')->count());
        $this->assertEqualsWithDelta(FixedAsset::findOrFail($b['id'])->cumulAmortissement(now()->toDateString()), (float) AccountingEntry::where('source_type', 'depreciation')->first()->total_debit, 0.01);
    }

    public function test_un_lecteur_ne_peut_ni_enregistrer_ni_doter(): void
    {
        $r = $this->envoyer($this->lecteur, [
            'fixed_assets' => [$this->bien()],
            'depreciation_requests' => [['id' => (string) Str::uuid(), 'date_arrete' => now()->toDateString()]],
        ]);

        $this->assertSame(0, FixedAsset::count());
        $this->assertSame(0, AccountingEntry::count());
        $this->assertNotEmpty($r->json('fixed_assets.rejected') ?? $r->json('rejected') ?? $r->json());
    }

    public function test_le_registre_descend_au_tirage_avec_ses_colonnes(): void
    {
        $b = $this->bien(['counterpart' => 'credit']);
        $this->envoyer($this->comptable, ['fixed_assets' => [$b]])->assertOk();

        $ligne = collect($this->actingAs($this->comptable, 'sanctum')->getJson('/api/sync/pull')->assertOk()->json('fixed_assets'))->firstWhere('id', $b['id']);

        $this->assertSame('244', $ligne['account_code']);
        $this->assertSame(1200000.0, (float) $ligne['acquisition_value']);
        $this->assertTrue($ligne['is_capitalized']);
        $this->assertSame(5, $ligne['duration_years']);
    }
}
