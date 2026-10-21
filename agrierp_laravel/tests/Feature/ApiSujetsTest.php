<?php

namespace Tests\Feature;

use App\Models\Animal;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use App\Services\AnimalFicheService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 15.14 — les sujets descendent au poste et leur fiche s'exporte en PDF.
 */
class ApiSujetsTest extends TestCase
{
    use RefreshDatabase;

    private const MDP = 'AgriERP@2026';

    private Animal $actif;

    private Animal $vendu;

    protected function setUp(): void
    {
        parent::setUp();

        Permission::findOrCreate('view-elevage', 'web');
        Role::findOrCreate('animalier', 'web')->givePermissionTo('view-elevage');
        Role::findOrCreate('caissier', 'web');

        foreach ([['animal', 'animalier'], ['caisse', 'caissier']] as [$u, $r]) {
            User::create([
                'name' => ucfirst($u), 'username' => $u, 'email' => $u.'@fermeolouwachegoun.com',
                'password' => bcrypt(self::MDP), 'is_active' => true,
            ])->assignRole($r);
        }

        $espece = LivestockSpecies::create(['code' => 'cuniculture', 'label' => 'Lapins', 'is_enabled' => true]);
        $lot = LivestockLot::create([
            'code' => 'LOT-CUNI-2026-011', 'species_id' => $espece->id, 'stage' => 'reproduction',
            'initial_quantity' => 20, 'current_quantity' => 20, 'created_date' => '2026-02-01',
            'status' => 'actif', 'is_active' => true,
        ]);

        $this->actif = Animal::create([
            'identifier' => 'LAP-2026-0143', 'species_id' => $espece->id, 'lot_id' => $lot->id,
            'category' => 'reproducteur', 'sex' => 'F', 'breed' => 'Néo-Zélandais Blanc',
            'birth_date' => '2026-02-12', 'entry_date' => '2026-02-15',
            'origin' => 'Naissance interne', 'cage' => 'C5', 'status' => 'actif',
        ]);
        $this->vendu = Animal::create([
            'identifier' => 'LAP-2026-0098', 'species_id' => $espece->id,
            'category' => 'reproducteur', 'sex' => 'M', 'entry_date' => '2026-01-10',
            'status' => 'vendu', 'exit_date' => '2026-06-01', 'exit_reason' => 'Vente à un éleveur',
            'is_active' => false,
        ]);
    }

    private function avec(string $u)
    {
        $jeton = $this->postJson('/api/auth/login', [
            'identifiant' => $u, 'password' => self::MDP, 'device_name' => 'poste-'.$u,
        ])->json('token');

        return $this->withHeader('Authorization', 'Bearer '.$jeton);
    }

    public function test_le_tirage_sert_tous_les_sujets_sortis_compris(): void
    {
        $sujets = collect($this->avec('animal')->getJson('/api/sync/pull')->assertOk()->json('animals'));

        $this->assertEqualsCanonicalizing(
            ['LAP-2026-0143', 'LAP-2026-0098'],
            $sujets->pluck('identifier')->all(),
        );

        $vendu = $sujets->firstWhere('identifier', 'LAP-2026-0098');
        $this->assertSame('vendu', $vendu['status']);
        $this->assertSame('2026-06-01', $vendu['exit_date']);
        $this->assertFalse($vendu['is_active']);
    }

    public function test_le_libelle_d_espece_et_le_code_de_bande_voyagent_avec_le_sujet(): void
    {
        $a = collect($this->avec('animal')->getJson('/api/sync/pull')->json('animals'))
            ->firstWhere('identifier', 'LAP-2026-0143');

        $this->assertSame('Lapins', $a['species_label']);
        $this->assertSame('LOT-CUNI-2026-011', $a['lot_code']);
        $this->assertSame('2026-02-12', $a['birth_date']);
        $this->assertSame('C5', $a['cage']);
    }

    /**
     * BS3 (BS-Q1, 21/10/2026) : `animals` n'est plus un référentiel en lecture seule — le poste écrit le registre des
     * reproducteurs (`SaisieReproducteurAction`, voir `ReproducteursPosteTest`). Une ligne FORGÉE (sans id, sans espèce…) est
     * REJETÉE avec ses motifs, jamais écrite ni comptée parmi les référentiels ignorés.
     */
    public function test_un_envoi_de_sujets_forge_par_le_poste_est_rejete_et_n_ecrit_rien(): void
    {
        $r = $this->avec('animal')->postJson('/api/sync/push', [
            'animals' => [['identifier' => 'FORGE']],
        ])->assertOk();

        $this->assertSame([], $r->json('animals.accepted'));
        $this->assertCount(1, $r->json('animals.rejected'));
        $this->assertSame(0, (int) $r->json('referentiels_ignored'));
        $this->assertDatabaseMissing('animals', ['identifier' => 'FORGE']);
    }

    public function test_la_fiche_pdf_est_un_pdf_nomme_d_apres_le_sujet(): void
    {
        $r = $this->avec('animal')->get('/api/animals/'.$this->actif->id.'/pdf')->assertOk();

        $this->assertSame('application/pdf', $r->headers->get('Content-Type'));
        $this->assertStringStartsWith('%PDF', $r->getContent());
        $this->assertStringContainsString('sujet-LAP-2026-0143.pdf', $r->headers->get('Content-Disposition'));
    }

    public function test_sans_droit_elevage_la_fiche_est_refusee(): void
    {
        $this->avec('caisse')->get('/api/animals/'.$this->actif->id.'/pdf')->assertForbidden();
    }

    public function test_un_sujet_inconnu_repond_404(): void
    {
        $this->avec('animal')->get('/api/animals/00000000-0000-0000-0000-000000000000/pdf')
            ->assertNotFound();
    }

    public function test_la_route_est_fermee_sans_jeton(): void
    {
        $this->getJson('/api/animals/'.$this->actif->id.'/pdf')->assertStatus(401);
    }

    public function test_le_service_ne_fabrique_aucun_mouvement(): void
    {
        $service = app(AnimalFicheService::class);

        // Un sujet encore présent : UNE ligne, son entrée.
        $this->assertCount(1, $service->mouvements($this->actif));

        // Un sujet sorti : entrée ET sortie, avec le motif saisi.
        $m = $service->mouvements($this->vendu);
        $this->assertCount(2, $m);
        $this->assertSame('Sortie — vendu', $m[1]['libelle']);
        $this->assertSame('Vente à un éleveur', $m[1]['detail']);
    }
}
