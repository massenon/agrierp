<?php

namespace Tests\Feature;

use App\Models\GrowthStandard;
use App\Models\User;
use App\Services\GrowthAnalysisService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Ticket U2 (décision client D-U2 du 19/10/2026) — OBJECTIFS DE GMQ : UNE SEULE SOURCE, `growth_standards`, au web et au
 * poste.
 *
 * 🔴 Avant : le poste portait des constantes (`DashboardElevageRepository.objectifs` : 15-20, 20-55, 400-650 g/j) et le
 * Dashboard Élevage web les avait recopiées (ticket H11), alors que le serveur a un référentiel. La table descend
 * désormais au tirage (référentiel en lecture seule, complet à chaque tirage) et la règle d'agrégation par espèce est
 * `GrowthAnalysisService::objectifPour()`, portée telle quelle au poste.
 */
class SyncObjectifsCroissanceTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
    }

    private function compte(string $role): User
    {
        $u = User::create([
            'name' => ucfirst($role), 'username' => $role, 'email' => $role.'.u2@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);
        Sanctum::actingAs($u);

        return $u;
    }

    private function bareme(string $espece, string $stade, int $min, int $max): GrowthStandard
    {
        return GrowthStandard::create(['species_code' => $espece, 'stage_label' => $stade,
            'gmq_min_g_per_day' => $min, 'gmq_max_g_per_day' => $max]);
    }

    public function test_le_tirage_sert_tout_le_bareme_meme_en_incremental(): void
    {
        $this->compte('animalier');
        $this->bareme('porciculture', 'engraissement', 500, 650);
        $this->bareme('cuniculture', 'engraissement', 15, 20);

        // Tirage incrémental bien APRÈS la création : le barème est servi quand même (référentiel complet).
        $lignes = $this->getJson('/api/sync/pull?since='.urlencode(now()->addDay()->toIso8601String()))
            ->assertOk()->json('growth_standards');

        $this->assertCount(2, $lignes);
        $this->assertSame(['cuniculture', 'porciculture'], array_column($lignes, 'species_code'));
        $this->assertSame(['id', 'species_code', 'stage_label', 'gmq_min_g_per_day', 'gmq_max_g_per_day'], array_keys($lignes[0]));
        $this->assertSame(15, (int) $lignes[0]['gmq_min_g_per_day']);
        $this->assertSame(650, (int) $lignes[1]['gmq_max_g_per_day']);
    }

    public function test_un_envoi_du_bareme_est_ignore_et_compte(): void
    {
        $this->compte('admin');
        $bareme = $this->bareme('cuniculture', 'engraissement', 15, 20);

        $this->postJson('/api/sync/push', ['growth_standards' => [[
            'id' => $bareme->id, 'species_code' => 'cuniculture', 'stage_label' => 'engraissement',
            'gmq_min_g_per_day' => 1, 'gmq_max_g_per_day' => 2,
        ]]])->assertOk()->assertJsonPath('referentiels_ignored', 1);

        $this->assertSame(15, (int) $bareme->fresh()->gmq_min_g_per_day);
        $this->assertSame(1, GrowthStandard::count());
    }

    /**
     * La règle d'agrégation, calculée à la main :
     *  - stade de chaque bande moyennée, égalité stricte (comme `rows()`) ;
     *  - enveloppe : plus petit des minima, plus grand des maxima ;
     *  - aucun barème pour ces stades → null (« — »), jamais un barème d'un autre stade ni 0.
     */
    public function test_objectif_pour_est_l_enveloppe_des_baremes_des_stades_moyennes(): void
    {
        $baremes = collect([
            $this->bareme('porciculture', 'engraissement', 500, 650),
            $this->bareme('porciculture', 'croissance', 300, 550),
            $this->bareme('porciculture', 'reproduction', 40, 80),
            $this->bareme('aviculture', 'engraissement', 45, 55),
        ]);

        $this->assertSame([500, 650], GrowthAnalysisService::objectifPour($baremes, 'porciculture', ['engraissement', 'engraissement']));
        $this->assertSame([300, 650], GrowthAnalysisService::objectifPour($baremes, 'porciculture', ['croissance', 'engraissement', null]));
        $this->assertSame([40, 650], GrowthAnalysisService::objectifPour($baremes, 'porciculture', ['reproduction', 'engraissement']));
        // Stade sans barème : rien n'est emprunté à un autre stade ni à une autre espèce.
        $this->assertNull(GrowthAnalysisService::objectifPour($baremes, 'porciculture', ['ponte']));
        $this->assertNull(GrowthAnalysisService::objectifPour($baremes, 'cuniculture', ['engraissement']));
        $this->assertNull(GrowthAnalysisService::objectifPour($baremes, 'porciculture', []));
        // Lignes en tableau (forme du tirage) : même résultat.
        $this->assertSame([45, 55], GrowthAnalysisService::objectifPour(
            $baremes->map(fn ($b) => $b->only(['species_code', 'stage_label', 'gmq_min_g_per_day', 'gmq_max_g_per_day']))->all(),
            'aviculture', ['engraissement'],
        ));
    }
}
