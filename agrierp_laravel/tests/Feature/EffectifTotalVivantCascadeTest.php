<?php

namespace Tests\Feature;

use App\Livewire\Elevage\EnregistrerSujets;
use App\Livewire\Elevage\FichePondeuses;
use App\Livewire\Elevage\FicheReproducteurs;
use App\Livewire\Elevage\GestionBandes;
use App\Livewire\Elevage\GestionElevage;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * CORRECTIF « EFFECTIF TOTAL VIVANT » FAUX APRÈS SAISIE D'UNE FICHE JOURNALIÈRE.
 *
 * ⚠️⚠️ LE DÉFAUT CORRIGÉ. Les fiches Reproducteurs, Pondeuses et Escargots écrivaient
 * `current_quantity` = effectif final du jour ÉDITÉ. Saisir (ou corriger) une fiche antérieure à
 * la dernière ramenait la bande à l'effectif de CE jour, et les fiches suivantes n'étaient jamais
 * recalculées : « Effectif Total Vivant » (Gestion des Bandes, Gestion Élevage) devenait faux.
 * `EnregistrerSujets` partait de `current_quantity` pour une date passée et incrémentait la bande
 * sans cascade.
 *
 * ⚠️ Les valeurs attendues sont des LITTÉRAUX calculés à la main, jamais produits par le code testé.
 * Date figée au 14/10/2026 ; J1 = 13/10 (veille), J2 = 14/10 (aujourd'hui).
 */
class EffectifTotalVivantCascadeTest extends TestCase
{
    use RefreshDatabase;

    private const J1 = '2026-10-13';

    private const J2 = '2026-10-14';

    private LivestockSpecies $aviculture;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow('2026-10-14 12:00:00');

        foreach (['view-elevage', 'manage-elevage'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('admin', 'web')->givePermissionTo(['view-elevage', 'manage-elevage']);

        $admin = User::create([
            'name' => 'Directeur', 'username' => 'admin',
            'email' => 'dg@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $admin->assignRole('admin');
        $this->actingAs($admin);

        $this->aviculture = LivestockSpecies::firstOrCreate(
            ['code' => 'aviculture'],
            ['label' => 'Aviculture', 'is_active' => true, 'is_enabled' => true],
        );
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function bande(string $code, string $stade, int $initial): LivestockLot
    {
        return LivestockLot::create([
            'code' => $code, 'species_id' => $this->aviculture->id, 'stage' => $stade,
            'initial_quantity' => $initial, 'current_quantity' => $initial,
            'created_date' => '2026-10-01', 'status' => 'actif', 'is_active' => true,
        ]);
    }

    private function effectifDuJour(LivestockLot $lot, string $jour): int
    {
        return (int) LivestockDailyEntry::where('lot_id', $lot->id)->whereDate('entry_date', $jour)->value('effectif_final');
    }

    /**
     * Bande de reproduction de 60. J2 : 10 poussins nés → 70. Puis J1, saisi APRÈS : 5 morts.
     * J1 = 60 − 5 = 55 ; J2 recalculé = 55 + 10 = 65 ; bande = 65 (dernière fiche), jamais 55.
     */
    public function test_reproducteurs_une_fiche_anterieure_ne_ramene_pas_la_bande_a_son_jour(): void
    {
        $lot = $this->bande('AVI-REP-01', 'reproduction', 60);

        $fiche = Livewire::test(FicheReproducteurs::class)
            ->set('selectedLotId', $lot->id)
            ->call('loadDay', self::J2)
            ->set('poussinsNes', 10)
            ->call('saveDay');

        $this->assertSame(70, (int) $lot->fresh()->current_quantity);

        $fiche->call('loadDay', self::J1)
            ->set('mortRepro', 5)
            ->call('saveDay');

        $this->assertSame(55, $this->effectifDuJour($lot, self::J1));
        $this->assertSame(65, $this->effectifDuJour($lot, self::J2));
        $this->assertSame(65, (int) $lot->fresh()->current_quantity);
    }

    /**
     * Bande de ponte de 200. J2 : 4 morts → 196. Puis J1 : 6 morts.
     * J1 = 194 ; J2 recalculé = 190 ; bande = 190.
     */
    public function test_pondeuses_une_fiche_anterieure_recalcule_les_jours_suivants(): void
    {
        $lot = $this->bande('AVI-PON-01', 'ponte', 200);

        $fiche = Livewire::test(FichePondeuses::class)
            ->call('loadDay', self::J2)
            ->set('mortRepro', 4)
            ->call('saveDay');

        $this->assertSame(196, (int) $lot->fresh()->current_quantity);

        $fiche->call('loadDay', self::J1)
            ->set('mortRepro', 6)
            ->call('saveDay');

        $this->assertSame(194, $this->effectifDuJour($lot, self::J1));
        $this->assertSame(190, $this->effectifDuJour($lot, self::J2));
        $this->assertSame(190, (int) $lot->fresh()->current_quantity);
    }

    /**
     * Bande de 60. Achat de 10 aujourd'hui → 70. Achat de 5 antidaté à J1.
     * J1 = 60 + 5 = 65 (la veille réelle, pas l'effectif d'aujourd'hui) ; J2 = 65 + 10 = 75 ; bande = 75.
     */
    public function test_enregistrer_sujets_une_entree_antidatee_recalcule_la_bande(): void
    {
        $lot = $this->bande('AVI-REP-02', 'reproduction', 60);

        $saisie = fn (string $jour, int $quantite) => Livewire::test(EnregistrerSujets::class)
            ->set('species_id', $this->aviculture->id)
            ->set('lot_id', $lot->id)
            ->set('origine', 'Achat')
            ->set('quantite', $quantite)
            ->set('entry_date', $jour)
            ->call('saveEntry')
            ->assertHasNoErrors();

        $saisie(self::J2, 10);
        $this->assertSame(70, (int) $lot->fresh()->current_quantity);

        $saisie(self::J1, 5);

        $this->assertSame(65, $this->effectifDuJour($lot, self::J1));
        $this->assertSame(75, $this->effectifDuJour($lot, self::J2));
        $this->assertSame(75, (int) $lot->fresh()->current_quantity);
    }

    /**
     * Le KPI lui-même : deux bandes, une fiche antérieure saisie après coup sur la première.
     * Reproduction 60 → J2 +10 nés, J1 −5 morts → 65 ; Ponte 200 sans fiche → 200. Total 265.
     */
    public function test_le_kpi_effectif_total_vivant_suit_la_derniere_fiche_de_chaque_bande(): void
    {
        $repro = $this->bande('AVI-REP-03', 'reproduction', 60);
        $this->bande('AVI-PON-02', 'ponte', 200);

        Livewire::test(FicheReproducteurs::class)
            ->set('selectedLotId', $repro->id)
            ->call('loadDay', self::J2)
            ->set('poussinsNes', 10)
            ->call('saveDay')
            ->call('loadDay', self::J1)
            ->set('mortRepro', 5)
            ->call('saveDay');

        $this->assertSame(265, Livewire::test(GestionElevage::class)->instance()->effectifTotal);
        $this->assertSame(265, Livewire::test(GestionBandes::class)->instance()->kpis['effectif_total']);
    }
}
