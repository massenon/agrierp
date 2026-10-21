<?php

namespace Tests\Feature;

use App\Models\CompanySetting;
use App\Models\ElevageNumberingSetting;
use App\Models\FeedRationStandard;
use App\Models\FeedType;
use App\Models\LivestockSpecies;
use App\Models\ProphylaxisScheduleStandard;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Ticket H9b (décision D-H9 du 19/10/2026) — PARAMÈTRES ÉLEVAGE MODIFIABLES AU POSTE COMME AU WEB.
 *
 * 🔴 Avant : rations, prophylaxie, provendes, numérotation et délai de rappel étaient des référentiels « le serveur
 * gagne » : un envoi du poste était compté dans `referentiels_ignored` et perdu. Mêmes règles que l'écran web
 * (`ParametresElevage`) : validations, archivage logique, droit `manage-elevage`.
 */
class SyncParametresElevageModifiablesTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        CompanySetting::current();
    }

    private function compte(string $role): void
    {
        $u = User::create([
            'name' => ucfirst($role), 'username' => $role, 'email' => $role.'@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);
        Sanctum::actingAs($u);
    }

    public function test_une_ration_creee_au_poste_puis_modifiee_puis_archivee(): void
    {
        $this->compte('animalier');
        $id = '77777777-7777-4777-8777-777777777777';
        $ration = ['id' => $id, 'species_code' => 'cuniculture', 'stage_label' => 'Jeune', 'ration_g_per_day' => 60];

        $this->postJson('/api/sync/push', ['feed_ration_standards' => [$ration]])->assertOk()
            ->assertJsonPath('feed_ration_standards.accepted.0', $id);
        $this->assertSame(60, (int) FeedRationStandard::findOrFail($id)->ration_g_per_day);

        $this->postJson('/api/sync/push', ['feed_ration_standards' => [['ration_g_per_day' => 65] + $ration]])->assertOk();
        $this->assertSame(65, (int) FeedRationStandard::findOrFail($id)->ration_g_per_day);

        // Supprimer = archiver (ticket 14.55) : la ligne reste, restaurable.
        $this->postJson('/api/sync/push', ['feed_ration_standards' => [['is_active' => false] + $ration]])->assertOk();
        $this->assertFalse(FeedRationStandard::findOrFail($id)->is_active);
        $this->getJson('/api/sync/pull')->assertOk()->assertJsonMissing(['id' => $id]);
    }

    public function test_les_validations_du_web_s_appliquent(): void
    {
        $this->compte('animalier');
        $this->postJson('/api/sync/push', ['feed_ration_standards' => [[
            'id' => '78787878-7878-4878-8878-787878787878', 'species_code' => 'helico', 'stage_label' => 'Naissain', 'ration_g_per_day' => 0,
        ]]])->assertOk()->assertJsonCount(1, 'feed_ration_standards.rejected');
        $this->assertSame(0, FeedRationStandard::count());
    }

    public function test_prophylaxie_provende_numerotation_et_rappel_des_soins(): void
    {
        $this->compte('animalier');
        $esp = LivestockSpecies::firstOrCreate(['code' => 'porciculture'], ['label' => 'Porciculture', 'is_enabled' => true]);

        $this->postJson('/api/sync/push', [
            'prophylaxis_schedule_standards' => [[
                'id' => '79797979-7979-4979-8979-797979797979', 'species_code' => 'porciculture', 'period_label' => 'J+21',
                'treatment' => 'Vermifuge', 'product_recommended' => 'Ivermectine', 'dosage' => '1 ml / 33 kg', 'withdrawal_days' => 14,
            ]],
            'feed_types' => [[
                'id' => '80808080-8080-4080-8080-808080808080', 'name' => 'Aliment porc croissance', 'species_id' => $esp->id,
                'standard_bag_weight_kg' => 50, 'price_per_kg' => 320,
            ]],
            'elevage_numbering' => [[
                'bande_format' => 'LOT', 'lapine_prefix' => 'L', 'male_prefix' => 'M', 'truie_prefix' => 'T', 'verrat_prefix' => 'V',
                'portee_prefix' => 'P', 'volaille_prefix' => 'VOL', 'parc_prefix' => 'PARC', 'escargot_prefix' => 'ESC',
            ]],
            'company_settings' => [['rappel_soins_jours' => 5]],
        ])->assertOk()->assertJsonPath('referentiels_ignored', 0);

        $this->assertSame(14, (int) ProphylaxisScheduleStandard::sole()->withdrawal_days);
        $this->assertSame(320.0, (float) FeedType::sole()->price_per_kg);
        $this->assertSame('L', ElevageNumberingSetting::current()->lapine_prefix);
        $this->assertSame(5, (int) CompanySetting::current()->rappel_soins_jours);
        $this->getJson('/api/sync/pull')->assertJsonPath('company_settings.rappel_soins_jours', 5);
    }

    public function test_un_caissier_ne_modifie_aucun_bareme(): void
    {
        $this->compte('caissier');
        $this->postJson('/api/sync/push', [
            'company_settings' => [['rappel_soins_jours' => 9]],
        ])->assertOk()->assertJsonCount(1, 'company_settings.rejected');
        $this->assertNotSame(9, (int) CompanySetting::current()->rappel_soins_jours);
    }
}
