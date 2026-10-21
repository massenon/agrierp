<?php

namespace Tests\Feature;

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
 * Ticket 14.63 (Sprint 14) — COHÉRENCE DES FORMULES ENTRE LES DEUX SURFACES.
 *
 * ⚠️⚠️ CE QUE CES TESTS PROTÈGENT. La maquette, le serveur web et le poste
 * Flutter calculent les mêmes indicateurs. Chaque suite vérifiait son propre
 * côté ; **aucune ne comparait les formules**. Deux écarts s'y étaient logés :
 *
 * 1. l'effectif final n'était **pas borné à zéro** côté serveur, alors que les
 *    CINQ maquettes calculent `Math.max(0, ...)` — même saisie, deux résultats ;
 * 2. `weight_sample_avg_g` portait **trois conventions différentes** selon la
 *    fiche : une moyenne (lapins, porcs) ou un total de bande (reproducteurs,
 *    escargots), alors que `GrowthAnalysisService` en tire le GMQ en la
 *    traitant toujours comme une moyenne.
 */
class CoherenceFormulesElevageTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

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
    }

    private function bande(string $codeEspece, string $stade, int $effectif = 40): LivestockLot
    {
        $espece = LivestockSpecies::firstOrCreate(
            ['code' => $codeEspece],
            ['label' => ucfirst($codeEspece), 'is_active' => true],
        );

        // ⚠️ L'HELICICULTURE EST DESACTIVEE PAR DEFAUT (Document 00 §5.1) : sans
        // activation, la fiche Escargots ne retient aucune bande — comportement
        // correct, mais qui rendait ce test muet.
        if ($codeEspece === 'helico') {
            \App\Models\ModuleConfig::updateOrCreate(
                ['species_code' => 'helico'],
                ['is_enabled' => true],
            );
        }

        return LivestockLot::create([
            'code' => strtoupper(substr($codeEspece, 0, 3)).'-01',
            'species_id' => $espece->id,
            'stage' => $stade,
            'initial_quantity' => $effectif,
            'current_quantity' => $effectif,
            'created_date' => now()->subDays(30)->toDateString(),
            'status' => 'actif',
            'is_active' => true,
        ]);
    }

    // ── 1. L'effectif final ────────────────────────────────────────────────

    /**
     * ⚠️⚠️ PLUS DE MORTS QUE D'ANIMAUX DONNE ZÉRO, PAS UN NÉGATIF. Les cinq
     * maquettes bornent ; le serveur ne bornait pas. Un effectif négatif ne
     * lève aucune erreur : il se propage dans l'effectif de départ du
     * lendemain, dans les taux de mortalité et dans la provende servie.
     */
    public function test_the_headcount_never_goes_negative(): void
    {
        $this->assertEquals(
            0,
            LivestockDailyEntry::computeEffectifFinal(40, 0, 0, 50, 0, 0),
            '50 morts sur 40 animaux : la maquette affiche 0',
        );
    }

    /** Le calcul nominal reste inchangé. */
    public function test_the_nominal_formula_is_unchanged(): void
    {
        // 40 + 5 achats + 3 nés − (2 morts + 1 vente + 1 don) = 44
        $this->assertEquals(
            44,
            LivestockDailyEntry::computeEffectifFinal(40, 5, 3, 2, 1, 1),
        );
    }

    // ── 2. La pesée : une seule convention ─────────────────────────────────

    /**
     * ⚠️ ARRONDI, PAS TRONCATURE. La maquette calcule
     * `Math.round(poidsG / effectifFinal)` : 3 500 g sur 40 sujets font **88**,
     * pas 87. `intdiv` donnait 87.
     */
    public function test_the_average_weight_is_rounded_not_truncated(): void
    {
        $lot = $this->bande('cuniculture', 'engraissement');

        Livewire::test(\App\Livewire\Elevage\FicheLapins::class)
            ->set('peseeTotal', 3500)
            ->call('saveDay');

        $fiche = LivestockDailyEntry::where('lot_id', $lot->id)->firstOrFail();

        // 3 500 / 40 = 87,5 → 88.
        $this->assertEquals(88, $fiche->weight_sample_avg_g);
    }

    /**
     * ⚠️⚠️ L'ALLER-RETOUR PRÉSERVE LE TOTAL PESÉ, sur les trois fiches qui
     * l'avaient perdu. Le champ affiche un TOTAL, la colonne stocke une
     * MOYENNE : reprendre la moyenne telle quelle affichait 88 g là où 3 500
     * avaient été pesés.
     *
     * @dataProvider fichesAvecPesee
     */
    public function test_the_weighed_total_survives_the_round_trip(
        string $composant,
        string $codeEspece,
        string $stade,
        string $champ,
    ): void {
        $this->bande($codeEspece, $stade);

        Livewire::test($composant)
            ->set($champ, 3600)
            ->call('saveDay')
            ->call('loadDay', now()->toDateString())
            ->assertSet($champ, 3600);
    }

    /** @return array<string, array{string, string, string, string}> */
    public static function fichesAvecPesee(): array
    {
        return [
            'lapins' => [
                \App\Livewire\Elevage\FicheLapins::class,
                'cuniculture', 'engraissement', 'peseeTotal',
            ],
            'reproducteurs' => [
                \App\Livewire\Elevage\FicheReproducteurs::class,
                'aviculture', 'reproduction', 'peseeTotal',
            ],
            'escargots' => [
                \App\Livewire\Elevage\FicheEscargots::class,
                'helico', 'engraissement', 'peseeTotal',
            ],
        ];
    }

    /**
     * ⚠️⚠️ LA COLONNE PORTE UNE MOYENNE SUR TOUTES LES FICHES. Reproducteurs et
     * Escargots y déposaient le total de bande : `GrowthAnalysisService` en
     * tirait un GMQ négatif dès qu'une bande perdait des animaux — un
     * indicateur de croissance qui lit un amaigrissement.
     */
    public function test_every_sheet_stores_an_average_never_a_herd_total(): void
    {
        $lot = $this->bande('helico', 'engraissement', 2000);

        Livewire::test(\App\Livewire\Elevage\FicheEscargots::class)
            ->set('peseeTotal', 50000)
            ->call('saveDay');

        $fiche = LivestockDailyEntry::where('lot_id', $lot->id)->firstOrFail();

        // 50 000 g pesés sur 2 000 escargots = 25 g par sujet.
        $this->assertEquals(25, $fiche->weight_sample_avg_g);
        $this->assertNotEquals(50000, $fiche->weight_sample_avg_g,
            'stocker le total ferait lire un escargot de 50 kg');
    }
}
