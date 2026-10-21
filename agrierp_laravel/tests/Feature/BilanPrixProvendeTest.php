<?php

namespace Tests\Feature;

use App\Livewire\Elevage\BilanTechnicoEconomique;
use App\Models\FeedType;
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
 * Décision D-U7 (19/10/2026, « uniformiser web et poste ») — valorisation de la provende servie au Bilan.
 *
 * Le web faisait la moyenne de TOUS les types de provende de l'espèce, archivés compris, et valorisait à 0 sans prix ;
 * le poste ne prenait que les types actifs et affichait « — ». Une seule règle désormais, celle du poste
 * (`BilanTechnicoEconomiqueRepository`) : types actifs, et « — » avec son motif quand aucun prix n'est connu.
 */
class BilanPrixProvendeTest extends TestCase
{
    use RefreshDatabase;

    private LivestockLot $bande;

    private LivestockSpecies $espece;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-elevage', 'manage-elevage'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('admin', 'web');
        $role->givePermissionTo(['view-elevage', 'manage-elevage']);
        $user = User::create([
            'name' => 'Animalier', 'email' => 'elevage@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $user->assignRole($role);
        $this->actingAs($user);

        $this->espece = LivestockSpecies::create(['label' => 'Aviculture', 'code' => 'AVI', 'is_active' => true]);
        $this->bande = LivestockLot::create([
            'code' => 'AVI-2026-001', 'species_id' => $this->espece->id, 'stage' => 'croissance',
            'initial_quantity' => 100, 'current_quantity' => 100,
            'created_date' => '2026-01-15', 'acquisition_cost' => 200_000,
            'status' => 'actif', 'is_active' => true,
        ]);
        LivestockDailyEntry::create([
            'lot_id' => $this->bande->id, 'entry_date' => '2026-01-16', 'feed_qty_kg' => 10,
            'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0, 'effectif_final' => 100,
        ]);
    }

    private function provende(float $prix, bool $actif = true): void
    {
        FeedType::create([
            'name' => 'Provende '.$prix, 'species_id' => $this->espece->id,
            'standard_bag_weight_kg' => 50, 'price_per_kg' => $prix, 'is_active' => $actif,
        ]);
    }

    private function ligneProvende(): array
    {
        $couts = Livewire::test(BilanTechnicoEconomique::class)->set('lotId', $this->bande->id)->instance()->couts;

        return collect($couts)->firstWhere('label', 'Provende servie (cumul, prix indicatif)');
    }

    public function test_un_type_archive_ne_pese_pas_sur_le_prix_moyen(): void
    {
        $this->provende(300);
        $this->provende(500);
        $this->provende(10_000, actif: false);

        // 10 kg × moyenne des ACTIFS (300 + 500) / 2 = 4 000 ; avec l'archivé : 36 000.
        $this->assertEquals(4_000, $this->ligneProvende()['montant']);
        $this->assertTrue($this->ligneProvende()['reel']);
    }

    public function test_sans_prix_connu_la_provende_n_est_pas_valorisee_a_zero(): void
    {
        $this->provende(800, actif: false);

        $ligne = $this->ligneProvende();
        $this->assertNull($ligne['montant']);
        $this->assertFalse($ligne['reel']);
        $this->assertStringContainsString('ne peut pas être valorisée', $ligne['motif']);
    }
}
