<?php

namespace Tests\Feature;

use App\Livewire\Elevage\SoinsVaccinsHub;
use App\Models\AuditLog;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\User;
use App\Models\VeterinaryRecord;
use App\Models\VeterinaryWithdrawalPeriod;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket U3 (décision client D-U3 du 19/10/2026) — L'ARCHIVAGE D'UN SOIN SE FAIT AU POSTE COMME AU WEB.
 *
 * Web : `SoinsVaccinsHub::archiveSoin()` met `is_active = false` et journalise `veterinary_record.archived`, droit
 * `manage-elevage`. 🔴 Avant : `pushVeterinaryRecords` ignorait `is_active` (ticket S1) et le tirage ne servait que les
 * soins actifs — un soin archivé au web restait compté au poste, et le poste ne pouvait rien archiver.
 */
class SyncArchivageSoinTest extends TestCase
{
    use RefreshDatabase;

    private const ID = '77777777-7777-4777-8777-777777777777';

    private LivestockLot $bande;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $esp = LivestockSpecies::firstOrCreate(['code' => 'cuniculture'], ['label' => 'Cuniculture', 'is_enabled' => true]);
        $this->bande = LivestockLot::create([
            'code' => 'LOT-U3', 'species_id' => $esp->id, 'stage' => 'engraissement', 'initial_quantity' => 30,
            'current_quantity' => 30, 'created_date' => now()->subDays(20)->toDateString(), 'status' => 'actif', 'is_active' => true,
        ]);
    }

    private function compte(string $role): User
    {
        $u = User::create([
            'name' => ucfirst($role), 'username' => $role, 'email' => $role.'.u3@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);
        Sanctum::actingAs($u);

        return $u;
    }

    private function soin(array $remplacements = []): array
    {
        return array_merge([
            'id' => self::ID, 'lot_id' => $this->bande->id, 'action_type' => 'Traitement curatif',
            'product_used' => 'Oxytétracycline', 'record_date' => now()->toDateString(), 'withdrawal_days' => 7, 'cost' => 2500,
        ], $remplacements);
    }

    /** Soin écrit directement en base, avec SON identifiant (`id` n'est pas assignable en masse). */
    private function creer(array $remplacements, bool $actif): VeterinaryRecord
    {
        $donnees = $this->soin($remplacements);
        $soin = new VeterinaryRecord(collect($donnees)->except(['id', 'withdrawal_days'])->all() + ['is_active' => $actif]);
        $soin->id = $donnees['id'];
        $soin->save();

        return $soin;
    }

    public function test_un_soin_connu_s_archive_par_son_identifiant_comme_au_web(): void
    {
        $this->compte('animalier');
        $this->postJson('/api/sync/push', ['veterinary_records' => [$this->soin()]])->assertOk()
            ->assertJsonPath('veterinary_records.accepted.0', self::ID);
        $this->assertTrue(VeterinaryRecord::findOrFail(self::ID)->is_active);

        $this->postJson('/api/sync/push', ['veterinary_records' => [['id' => self::ID, 'is_active' => false]]])->assertOk()
            ->assertJsonPath('veterinary_records.accepted.0', self::ID)
            ->assertJsonCount(0, 'veterinary_records.rejected');

        $this->assertFalse(VeterinaryRecord::findOrFail(self::ID)->is_active, 'archivage logique : la ligne reste');
        $this->assertSame(1, AuditLog::where('action', 'veterinary_record.archived')->count());
        // Comme après `archiveSoin()` : la rémanence créée par le soin reste en vigueur.
        $this->assertTrue(VeterinaryWithdrawalPeriod::isLotBlocked($this->bande->id));

        // Renvoi (accusé perdu) : succès silencieux, pas de second journal.
        $this->postJson('/api/sync/push', ['veterinary_records' => [$this->soin(['is_active' => false])]])->assertOk()
            ->assertJsonPath('veterinary_records.accepted.0', self::ID);
        $this->assertSame(1, AuditLog::where('action', 'veterinary_record.archived')->count());
        $this->assertSame(1, VeterinaryWithdrawalPeriod::count(), 'aucune rémanence empilée');
    }

    public function test_l_archivage_ne_se_defait_pas_par_le_poste(): void
    {
        $this->compte('animalier');
        $this->postJson('/api/sync/push', ['veterinary_records' => [$this->soin(['is_active' => false])]])->assertOk();
        $this->assertFalse(VeterinaryRecord::findOrFail(self::ID)->is_active);

        $this->postJson('/api/sync/push', ['veterinary_records' => [['id' => self::ID, 'is_active' => true]]])->assertOk()
            ->assertJsonPath('veterinary_records.accepted.0', self::ID);
        $this->assertFalse(VeterinaryRecord::findOrFail(self::ID)->is_active, 'la restauration passe par la Corbeille du web');
    }

    public function test_un_soin_saisi_puis_archive_hors_ligne_arrive_archive_avec_sa_remanence(): void
    {
        $this->compte('animalier');
        $this->postJson('/api/sync/push', ['veterinary_records' => [$this->soin(['is_active' => false])]])->assertOk()
            ->assertJsonPath('veterinary_records.accepted.0', self::ID);

        $soin = VeterinaryRecord::findOrFail(self::ID);
        $this->assertFalse($soin->is_active);
        $this->assertSame('Oxytétracycline', $soin->product_used);
        $this->assertTrue(VeterinaryWithdrawalPeriod::isLotBlocked($this->bande->id));
        $this->assertSame(1, AuditLog::where('action', 'veterinary_record.archived')->count());
    }

    public function test_un_is_active_illisible_est_refuse_avec_son_motif(): void
    {
        $this->compte('animalier');
        $this->postJson('/api/sync/push', ['veterinary_records' => [$this->soin()]])->assertOk();

        $this->postJson('/api/sync/push', ['veterinary_records' => [['id' => self::ID, 'is_active' => 'peut-être']]])->assertOk()
            ->assertJsonCount(1, 'veterinary_records.rejected');
        $this->assertTrue(VeterinaryRecord::findOrFail(self::ID)->is_active);
    }

    public function test_un_caissier_ne_peut_pas_archiver_un_soin(): void
    {
        $this->creer([], true);
        $this->compte('caissier');

        $this->postJson('/api/sync/push', ['veterinary_records' => [['id' => self::ID, 'is_active' => false]]])->assertOk()
            ->assertJsonCount(1, 'veterinary_records.rejected')
            ->assertJsonCount(0, 'veterinary_records.accepted');
        $this->assertTrue(VeterinaryRecord::findOrFail(self::ID)->is_active);
    }

    public function test_le_tirage_sert_is_active_et_les_soins_archives_depuis_le_dernier_tirage(): void
    {
        $this->compte('animalier');
        $actif = $this->creer(['id' => '88888888-8888-4888-8888-888888888888'], true);
        $archive = $this->creer([], true);
        $avant = now()->subMinute();
        $archive->update(['is_active' => false]);

        // Tirage complet : un poste neuf ne reçoit que les soins actifs.
        $complet = collect($this->getJson('/api/sync/pull')->assertOk()->json('veterinary_records'));
        $this->assertSame([$actif->id], $complet->pluck('id')->all());
        $this->assertTrue($complet->first()['is_active']);

        // Tirage incrémental : l'archivage descend, avec `is_active = false`.
        $increment = collect($this->getJson('/api/sync/pull?since='.urlencode($avant->toIso8601String()))->assertOk()
            ->json('veterinary_records'))->keyBy('id');
        $this->assertFalse($increment[self::ID]['is_active']);
    }

    /**
     * 🔴→✅ Le KPI du registre comptait les soins ARCHIVÉS (« Interventions (mois) », « Coût sanitaire (mois) ») alors
     * que le registre, le Dashboard Élevage, le Bilan et le protocole les écartent. Soins actifs seulement, comme au
     * poste.
     */
    public function test_les_kpi_du_registre_ignorent_les_soins_archives(): void
    {
        $u = $this->compte('animalier');
        $this->actingAs($u);
        $this->creer(['id' => '88888888-8888-4888-8888-888888888888', 'cost' => 1000], true);
        $this->creer(['cost' => 4000], false);

        $kpis = Livewire::test(SoinsVaccinsHub::class)->instance()->kpisRegistre;
        $this->assertSame(1, $kpis['interventions_mois']);
        $this->assertEquals(1000.0, $kpis['cout_sanitaire_mois']);
    }

    public function test_l_archivage_du_web_reste_identique(): void
    {
        $u = $this->compte('animalier');
        $this->actingAs($u);
        $this->creer([], true);

        Livewire::test(SoinsVaccinsHub::class)->call('archiveSoin', self::ID)
            ->assertDispatched('toast', message: 'Fiche archivée avec succès.', type: 'warning');
        $this->assertFalse(VeterinaryRecord::findOrFail(self::ID)->is_active);
        $this->assertSame(1, AuditLog::where('action', 'veterinary_record.archived')->count());
    }
}
