<?php

namespace Tests\Feature;

use App\Models\Customer;
use App\Models\Receivable;
use App\Services\AgedBalanceService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

/**
 * Ticket 14.66 (Sprint 14) — BALANCE ÂGÉE.
 *
 * ⚠️ ÉCRAN HORS MAQUETTE, assumé : `prototype_html` ne porte aucune balance
 * âgée — le mot « âgée » n'y apparaît que sur des écrans de STOCK. Il répond à
 * un besoin exprimé par le client comptable. Aucun écran du prototype n'est
 * modifié.
 *
 * ⚠️⚠️ Les deux règles que ces tests protègent :
 * 1. **l'âge se compte depuis l'ÉCHÉANCE, pas depuis l'émission** — sinon on
 *    relance un client parfaitement à jour ;
 * 2. **c'est le RESTE DÛ qui est ventilé**, jamais le montant initial.
 */
class BalanceAgeeTest extends TestCase
{
    use RefreshDatabase;

    private Customer $client;

    private Carbon $arrete;

    protected function setUp(): void
    {
        parent::setUp();

        $this->arrete = Carbon::create(2026, 8, 31);

        $this->client = Customer::create([
            'name' => 'Boutique ABC',
            'phone' => '97000000',
            'is_active' => true,
        ]);
    }

    private function creance(float $montant, float $regle, ?string $echeance): Receivable
    {
        return Receivable::create([
            'customer_id' => $this->client->id,
            'amount' => $montant,
            'amount_paid' => $regle,
            'due_date' => $echeance,
            'status' => 'en_cours',
        ]);
    }

    private function service(): AgedBalanceService
    {
        return app(AgedBalanceService::class);
    }

    /** @return array<string, float> */
    private function totaux(): array
    {
        return $this->service()->creances($this->arrete)['totaux'];
    }

    /**
     * ⚠️⚠️ UNE FACTURE À ÉCHOIR N'EST PAS EN RETARD. La classer selon son
     * ancienneté d'émission ferait relancer un client à jour.
     */
    public function test_a_future_due_date_is_not_overdue(): void
    {
        $this->creance(100000, 0, '2026-09-15');

        $this->assertEquals(100000.0, $this->totaux()['Non échu']);
        $this->assertEquals(0.0, $this->totaux()['1 à 30 jours']);
    }

    /** Les tranches se lisent en jours de retard depuis l'échéance. */
    public function test_each_bucket_matches_its_days_overdue(): void
    {
        $this->creance(10000, 0, '2026-08-20');  // 11 j  → 1 à 30
        $this->creance(20000, 0, '2026-07-15');  // 47 j  → 31 à 60
        $this->creance(30000, 0, '2026-06-15');  // 77 j  → 61 à 90
        $this->creance(40000, 0, '2026-01-10');  // 233 j → plus de 90

        $totaux = $this->totaux();

        $this->assertEquals(10000.0, $totaux['1 à 30 jours']);
        $this->assertEquals(20000.0, $totaux['31 à 60 jours']);
        $this->assertEquals(30000.0, $totaux['61 à 90 jours']);
        $this->assertEquals(40000.0, $totaux['Plus de 90 jours']);
    }

    /**
     * ⚠️⚠️ LE RESTE DÛ, JAMAIS LE MONTANT INITIAL. Retenir le montant d'origine
     * gonflerait l'encours de tout ce qui a déjà été encaissé.
     */
    public function test_only_the_outstanding_amount_is_aged(): void
    {
        $this->creance(100000, 90000, '2026-08-01');

        $this->assertEquals(10000.0, $this->service()->creances($this->arrete)['total']);
    }

    /** Une créance soldée disparaît de la balance âgée. */
    public function test_a_settled_receivable_is_excluded(): void
    {
        $this->creance(50000, 50000, '2026-08-01');

        $this->assertEquals(0.0, $this->service()->creances($this->arrete)['total']);
        $this->assertEmpty($this->service()->creances($this->arrete)['tiers']);
    }

    /**
     * ⚠️ SANS ÉCHÉANCE, LA LIGNE EST « NON ÉCHUE », jamais rangée dans la
     * tranche la plus ancienne : une date manquante est une lacune de saisie,
     * pas un retard de paiement.
     */
    public function test_a_missing_due_date_is_never_treated_as_the_oldest(): void
    {
        $this->creance(75000, 0, null);

        $totaux = $this->totaux();

        $this->assertEquals(75000.0, $totaux['Non échu']);
        $this->assertEquals(0.0, $totaux['Plus de 90 jours']);
    }

    /** La borne exacte du jour d'échéance n'est pas encore un retard. */
    public function test_the_due_date_itself_is_not_yet_overdue(): void
    {
        $this->creance(60000, 0, $this->arrete->toDateString());

        $this->assertEquals(60000.0, $this->totaux()['Non échu']);
    }

    /** Les tiers sont classés par encours décroissant : on relance le plus gros. */
    public function test_parties_are_sorted_by_outstanding_amount(): void
    {
        $petit = Customer::create(['name' => 'Petit client', 'phone' => '97000001', 'is_active' => true]);

        $this->creance(10000, 0, '2026-08-01');
        Receivable::create([
            'customer_id' => $petit->id, 'amount' => 500000, 'amount_paid' => 0,
            'due_date' => '2026-08-01', 'status' => 'en_cours',
        ]);

        $tiers = $this->service()->creances($this->arrete)['tiers'];

        $this->assertEquals('Petit client', $tiers[0]['nom']);
        $this->assertEquals('Boutique ABC', $tiers[1]['nom']);
    }

    /** Le total général égale la somme des tranches. */
    public function test_the_grand_total_equals_the_sum_of_buckets(): void
    {
        $this->creance(10000, 0, '2026-08-20');
        $this->creance(20000, 0, '2026-07-15');
        $this->creance(30000, 0, '2026-09-30');

        $resultat = $this->service()->creances($this->arrete);

        $this->assertEquals(array_sum($resultat['totaux']), $resultat['total']);
        $this->assertEquals(60000.0, $resultat['total']);
    }

    /**
     * ⚠️ L'ÉCRAN REND VRAIMENT, et il annonce son origine hors maquette. Un
     * service juste ne garantit pas une vue qui compile : `php -l` ne valide
     * pas le Blade.
     */
    public function test_the_screen_renders_and_states_its_origin(): void
    {
        \App\Models\Permission::findOrCreate('view-comptabilite', 'web');
        \App\Models\Role::findOrCreate('comptable', 'web')->givePermissionTo('view-comptabilite');

        $comptable = \App\Models\User::create([
            'name' => 'Comptable', 'username' => 'compta',
            'email' => 'compta@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $comptable->assignRole('comptable');

        $this->creance(100000, 0, '2026-06-15');

        \Livewire\Livewire::actingAs($comptable)
            ->test(\App\Livewire\Comptabilite\BalanceAgee::class)
            ->set('arrete', '2026-08-31')
            ->assertOk()
            ->assertSee('Balance Âgée')
            ->assertSee('Boutique ABC')
            ->assertSee('hors maquette')
            ->assertSee('61 à 90 jours');
    }

    /**
     * ⚠️ LE VOLET FOURNISSEURS EXISTE VRAIMENT : une balance âgée qui
     * n'afficherait que les créances laisserait le comptable sans vue sur ce
     * que l'exploitation DOIT.
     */
    public function test_the_supplier_side_is_available(): void
    {
        $this->assertArrayHasKey('totaux', $this->service()->dettes($this->arrete));
        $this->assertArrayHasKey('tiers', $this->service()->dettes($this->arrete));
    }
}
