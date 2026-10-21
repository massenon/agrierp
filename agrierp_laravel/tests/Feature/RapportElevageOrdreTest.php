<?php

namespace Tests\Feature;

use App\Livewire\Rapports\ElevageSynth;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket U11 — RAPPORT ÉLEVAGE : DEUX FICHES DU MÊME JOUR SORTENT TOUJOURS DANS LE MÊME ORDRE.
 *
 * `ElevageSynth::baseQuery()` ne triait que par date : deux bandes saisies le même jour sortaient dans l'ordre du
 * moteur de base (insertion sur SQLite, plan d'exécution sur MySQL), et le poste ne pouvait pas le reproduire. Le
 * second critère est l'identifiant, croissant — le même que celui du poste (`RapportsRepository.ordreDesFiches`,
 * parité exécutée par `agrierp_flutter/test/rapport_elevage_parite_test.dart`).
 */
class RapportElevageOrdreTest extends TestCase
{
    use RefreshDatabase;

    private const PETIT = '11111111-1111-4111-8111-111111111111';

    private const GRAND = 'ffffffff-ffff-4fff-8fff-ffffffffffff';

    protected function setUp(): void
    {
        parent::setUp();

        Permission::findOrCreate('view-rapports', 'web');
        $role = Role::findOrCreate('admin', 'web');
        $role->givePermissionTo('view-rapports');
        $user = User::create([
            'name' => 'DG', 'email' => 'dg@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $user->assignRole($role);
        $this->actingAs($user);
    }

    private function fiche(string $id, LivestockLot $bande, string $date, int $effectif): void
    {
        $fiche = new LivestockDailyEntry([
            'lot_id' => $bande->id, 'entry_date' => $date, 'achat' => 0, 'ne' => 0, 'mort' => 2, 'vente' => 0,
            'effectif_final' => $effectif, 'ponte_total' => 100,
        ]);
        $fiche->id = $id;
        $fiche->save();
    }

    public function test_deux_fiches_du_meme_jour_sortent_par_identifiant_croissant(): void
    {
        $espece = LivestockSpecies::create(['label' => 'Aviculture', 'code' => 'aviculture', 'is_active' => true]);
        $a = LivestockLot::create([
            'code' => 'PON-A', 'species_id' => $espece->id, 'stage' => 'ponte', 'initial_quantity' => 400,
            'current_quantity' => 400, 'created_date' => '2026-01-05', 'status' => 'actif', 'is_active' => true,
        ]);
        $b = LivestockLot::create([
            'code' => 'PON-B', 'species_id' => $espece->id, 'stage' => 'ponte', 'initial_quantity' => 100,
            'current_quantity' => 100, 'created_date' => '2026-01-05', 'status' => 'actif', 'is_active' => true,
        ]);

        // ⚠️ Le GRAND identifiant est inséré le premier : sans second critère, SQLite le rend en tête.
        $this->fiche(self::GRAND, $a, '2026-07-02', 398);
        $this->fiche(self::PETIT, $b, '2026-07-02', 98);

        $composant = Livewire::test(ElevageSynth::class, ['startDate' => '2026-07-01', 'endDate' => '2026-07-31']);

        $this->assertSame(
            [self::PETIT, self::GRAND],
            $composant->instance()->entries->pluck('id')->all(),
        );

        // La fiche « la plus ancienne » de la mortalité hebdo est la première du jour le plus ancien : PON-B
        // (effectif de début 100, sa quantité initiale) — 4 morts ÷ 100 = 4 %, jamais 4 ÷ 400 = 1 %.
        $this->assertSame(4.0, $composant->instance()->kpis['taux_mortalite_hebdo']);

        // Le Tableau 1 rendu suit le même ordre.
        $html = $composant->html();
        $this->assertLessThan(strpos($html, '>PON-A</td>'), strpos($html, '>PON-B</td>'));
    }
}
