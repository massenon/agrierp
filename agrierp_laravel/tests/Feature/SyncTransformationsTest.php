<?php

namespace Tests\Feature;

use App\Livewire\Elevage\TransformationForm;
use App\Models\AuditLog;
use App\Models\FiscalYear;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\StockMovement;
use App\Models\Transformation;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket EL-1 — LES TRANSFORMATIONS S'ÉCRIVENT AU POSTE.
 *
 * Le poste envoie le FAIT (`transformations`) ; `SaisieTransformationAction`, partagée avec
 * `Elevage\TransformationForm`, joue les mêmes règles, la même vente sur la fiche du jour, le même stock et le même audit.
 * Valeurs attendues = littéraux calculés à la main (bande de 40, 5 sujets : 35).
 */
class SyncTransformationsTest extends TestCase
{
    use RefreshDatabase;

    private const JOUR = '2026-10-10';

    private User $animalier;

    private LivestockLot $bande;

    private Product $produit;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow('2026-10-14 12:00:00');

        foreach (['view-elevage', 'manage-elevage'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('animalier', 'web')->givePermissionTo(['view-elevage', 'manage-elevage']);
        Role::findOrCreate('lecteur', 'web')->givePermissionTo('view-elevage');
        $this->animalier = $this->utilisateur('animalier');

        $espece = LivestockSpecies::firstOrCreate(['code' => 'aviculture'], ['label' => 'Aviculture', 'is_enabled' => true, 'is_active' => true]);
        $this->bande = LivestockLot::create([
            'code' => 'AVI-ENG-1', 'species_id' => $espece->id, 'stage' => 'engraissement', 'initial_quantity' => 40,
            'current_quantity' => 40, 'created_date' => '2026-09-01', 'status' => 'actif', 'is_active' => true,
        ]);
        $this->produit = Product::create([
            'sku' => 'AVI-005', 'name' => 'Poulet fumé', 'category_id' => ProductCategory::create(['label' => 'Transformés', 'is_active' => true])->id,
            'unit' => 'pièce', 'pricing_mode' => 'fourchette', 'price_min' => 5000, 'price_max' => 6000, 'tva_rate' => 0, 'stock_qty' => 0, 'is_active' => true,
        ]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
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
    private function transformation(array $remplace = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(), 'lot_id' => $this->bande->id, 'product_id' => $this->produit->id,
            'qty_animals' => 5, 'qty_produced' => 5, 'transformation_date' => self::JOUR,
        ], $remplace);
    }

    private function envoyer(User $u, array $corps)
    {
        return $this->actingAs($u, 'sanctum')->postJson('/api/sync/push', ['device_id' => 'poste-test'] + $corps);
    }

    public function test_une_transformation_du_poste_sort_les_sujets_comme_une_vente_et_entre_le_stock(): void
    {
        $t = $this->transformation();

        $this->envoyer($this->animalier, ['transformations' => [$t]])
            ->assertOk()->assertJsonPath('transformations.accepted.0', $t['id']);

        $ligne = Transformation::findOrFail($t['id']);
        $this->assertSame(5, (int) $ligne->qty_animals);
        $this->assertSame($this->animalier->id, $ligne->operator_id);

        $fiche = LivestockDailyEntry::where('lot_id', $this->bande->id)->whereDate('entry_date', self::JOUR)->firstOrFail();
        $this->assertSame(5, (int) $fiche->vente);
        $this->assertSame(35, (int) $fiche->effectif_final);
        $this->assertSame(35, (int) $this->bande->fresh()->current_quantity);
        $this->assertSame(5.0, (float) $this->produit->fresh()->stock_qty);
        $this->assertSame(1, StockMovement::where('reference_type', 'transformation')->where('reference_id', $t['id'])->count());
        $this->assertSame(1, AuditLog::where('action', 'transformation.recorded')->where('user_id', $this->animalier->id)->count());
    }

    public function test_un_renvoi_de_la_meme_transformation_ne_rejoue_rien(): void
    {
        $t = $this->transformation();

        $this->envoyer($this->animalier, ['transformations' => [$t]])->assertOk();
        $this->envoyer($this->animalier, ['transformations' => [$t]])
            ->assertOk()->assertJsonPath('transformations.accepted.0', $t['id'])->assertJsonPath('transformations.rejected', []);

        $this->assertSame(1, Transformation::count());
        $this->assertSame(35, (int) $this->bande->fresh()->current_quantity);
        $this->assertSame(5.0, (float) $this->produit->fresh()->stock_qty);
        $this->assertSame(1, AuditLog::where('action', 'transformation.recorded')->count());
    }

    public function test_un_effectif_insuffisant_est_refuse_avec_le_message_du_web_et_rien_n_est_ecrit(): void
    {
        $t = $this->transformation(['qty_animals' => 41]);

        $r = $this->envoyer($this->animalier, ['transformations' => [$t]])->assertOk();

        $this->assertSame($t['id'], $r->json('transformations.rejected.0.id'));
        $this->assertSame("La quantité ne peut pas dépasser l'effectif disponible du lot (40).", $r->json('transformations.rejected.0.reason'));
        $this->assertSame(0, Transformation::count());
        $this->assertSame(40, (int) $this->bande->fresh()->current_quantity);
        $this->assertSame(0.0, (float) $this->produit->fresh()->stock_qty);
    }

    public function test_une_bande_ou_un_produit_inconnu_est_refuse_en_clair(): void
    {
        $r = $this->envoyer($this->animalier, ['transformations' => [
            $this->transformation(['lot_id' => (string) Str::uuid()]),
            $this->transformation(['product_id' => (string) Str::uuid()]),
        ]])->assertOk();

        $this->assertCount(2, $r->json('transformations.rejected'));
        $this->assertStringContainsString('champ bande', $r->json('transformations.rejected.0.reason'));
        $this->assertStringContainsString('champ produit', $r->json('transformations.rejected.1.reason'));
        $this->assertSame(0, Transformation::count());
    }

    public function test_une_date_absente_ou_une_quantite_negative_est_refusee(): void
    {
        $r = $this->envoyer($this->animalier, ['transformations' => [
            $this->transformation(['transformation_date' => null]),
            $this->transformation(['qty_produced' => -1]),
        ]])->assertOk();

        $this->assertStringContainsString('date de transformation', $r->json('transformations.rejected.0.reason'));
        $this->assertSame('Le champ quantité produite doit être au moins égal à 0.', $r->json('transformations.rejected.1.reason'));
    }

    public function test_un_exercice_clos_refuse_la_transformation(): void
    {
        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'cloture']);

        $r = $this->envoyer($this->animalier, ['transformations' => [$this->transformation()]])->assertOk();

        $this->assertSame("L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 10/10/2026.", $r->json('transformations.rejected.0.reason'));
        $this->assertSame(0, Transformation::count());
        $this->assertSame(40, (int) $this->bande->fresh()->current_quantity);
    }

    public function test_un_compte_sans_le_droit_d_ecriture_est_refuse(): void
    {
        $lecteur = $this->utilisateur('lecteur');

        $this->envoyer($lecteur, ['transformations' => [$this->transformation()]]);

        $this->assertSame(0, Transformation::count());
        $this->assertSame(40, (int) $this->bande->fresh()->current_quantity);
    }

    public function test_le_tirage_sert_les_transformations_a_qui_voit_l_elevage(): void
    {
        $t = $this->transformation();
        $this->envoyer($this->animalier, ['transformations' => [$t]])->assertOk();

        $corps = $this->actingAs($this->animalier, 'sanctum')->getJson('/api/sync/pull')->assertOk()->json();

        $this->assertEquals(
            ['id' => $t['id'], 'lot_id' => $this->bande->id, 'product_id' => $this->produit->id, 'qty_animals' => 5,
                'qty_produced' => 5.0, 'operator_id' => $this->animalier->id, 'transformation_date' => self::JOUR],
            collect($corps['transformations'])->firstWhere('id', $t['id']) === null ? null
                : \Illuminate\Support\Arr::except(collect($corps['transformations'])->firstWhere('id', $t['id']), ['updated_at']),
        );
    }

    public function test_le_web_passe_par_la_meme_action_et_affiche_le_refus_sous_le_champ(): void
    {
        $this->actingAs($this->animalier);

        Livewire::test(TransformationForm::class)
            ->set('lotId', $this->bande->id)->set('qtyAnimals', 41)->set('productId', $this->produit->id)->set('qtyProduced', 5)->set('transformationDate', self::JOUR)
            ->call('validateTransformation')
            ->assertHasErrors(['qtyAnimals'])
            ->assertSee("La quantité ne peut pas dépasser l'effectif disponible du lot (40).");

        Livewire::test(TransformationForm::class)
            ->set('lotId', $this->bande->id)->set('qtyAnimals', 5)->set('productId', $this->produit->id)->set('qtyProduced', 5)->set('transformationDate', self::JOUR)
            ->call('validateTransformation')->assertHasNoErrors();

        $this->assertSame(35, (int) $this->bande->fresh()->current_quantity);
        $this->assertSame(1, Transformation::count());
        $this->assertSame(1, AuditLog::where('action', 'transformation.recorded')->count());
    }

    public function test_le_menu_web_relie_la_page_transformation(): void
    {
        $this->actingAs($this->animalier)->get('/gestion-elevage')->assertOk()->assertSee('href="/transformation"', false);
    }
}
