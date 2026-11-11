<?php

namespace Tests\Feature;

use App\Actions\CloturesCaisse\ValiderClotureCaisseAction;
use App\Livewire\Ventes\ClotureCaisse;
use App\Models\CashClosure;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\Sale;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Validation\ValidationException;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Sprint C — Clôture de caisse (C1 : action métier, C2 : composant Livewire, C3 : sync, C4 : SYSCOHADA).
 */
class ClotureCaisseTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;
    private FiscalYear $exercice;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);

        $this->admin = User::create([
            'name'      => 'Admin Test',
            'username'  => 'admin-cloture',
            'email'     => 'admin-cloture@fermeolouwachegoun.com',
            'password'  => bcrypt('LogiAgriERP@2026'),
            'is_active' => true,
        ]);
        $this->admin->assignRole('admin');

        $this->exercice = FiscalYear::create([
            'name'       => 'Exercice 2026',
            'start_date' => '2026-01-01',
            'end_date'   => '2026-12-31',
            'status'     => 'active',
        ]);

        // Comptes SYSCOHADA nécessaires aux écritures d'écart.
        foreach (['571' => 'Caisse', '658' => 'Charges diverses de gestion courante', '718' => 'Produits divers'] as $code => $libelle) {
            ChartOfAccount::create([
                'code'      => $code,
                'label'     => $libelle,
                'class'     => (int) substr($code, 0, 1),
                'is_active' => true,
            ]);
        }

        $this->actingAs($this->admin);
    }

    // ─── C1 : ValiderClotureCaisseAction ────────────────────────────────────

    /** @test */
    public function test_c1_cloture_sans_ecart_ne_cree_pas_ecriture(): void
    {
        $vente = $this->creerVente(1000.0, 'especes');

        /** @var ValiderClotureCaisseAction $action */
        $action = app(ValiderClotureCaisseAction::class);

        $cloture = $action->execute(
            closureDate:   '2026-11-11',
            fondDeCaisse:  500.0,
            montantCompte: 1500.0,  // fond + especes = 500 + 1000 = 1500 → écart = 0
            userId:        $this->admin->id,
        );

        $this->assertEquals('validée', $cloture->statut);
        $this->assertEquals(0.0, $cloture->ecart);
        $this->assertNull($cloture->accounting_entry_id);
    }

    /** @test */
    public function test_c4_ecart_positif_genere_gain_571_718(): void
    {
        $this->creerVente(1000.0, 'especes');

        $action = app(ValiderClotureCaisseAction::class);

        // montant compté = fond + ventes + 200 d'excédent
        $cloture = $action->execute(
            closureDate:   '2026-11-11',
            fondDeCaisse:  500.0,
            montantCompte: 1700.0,
            userId:        $this->admin->id,
        );

        $this->assertEquals(200.0, $cloture->ecart);
        $this->assertNotNull($cloture->accounting_entry_id);

        $lignes = \App\Models\AccountingEntryLine::where('accounting_entry_id', $cloture->accounting_entry_id)->get();
        $debitCodes  = $lignes->where('debit', '>', 0)->pluck('account_code')->sort()->values()->all();
        $creditCodes = $lignes->where('credit', '>', 0)->pluck('account_code')->sort()->values()->all();

        $this->assertEquals(['571'], $debitCodes);
        $this->assertEquals(['718'], $creditCodes);
    }

    /** @test */
    public function test_c4_ecart_negatif_genere_perte_658_571(): void
    {
        $this->creerVente(1000.0, 'especes');

        $action = app(ValiderClotureCaisseAction::class);

        $cloture = $action->execute(
            closureDate:   '2026-11-11',
            fondDeCaisse:  500.0,
            montantCompte: 1300.0,  // 200 de moins que prévu → perte
            userId:        $this->admin->id,
        );

        $this->assertEquals(-200.0, $cloture->ecart);
        $this->assertNotNull($cloture->accounting_entry_id);

        $lignes = \App\Models\AccountingEntryLine::where('accounting_entry_id', $cloture->accounting_entry_id)->get();
        $debitCodes  = $lignes->where('debit', '>', 0)->pluck('account_code')->sort()->values()->all();
        $creditCodes = $lignes->where('credit', '>', 0)->pluck('account_code')->sort()->values()->all();

        $this->assertEquals(['658'], $debitCodes);
        $this->assertEquals(['571'], $creditCodes);
    }

    /** @test */
    public function test_c1_double_cloture_meme_jour_meme_poste_refusee(): void
    {
        $action = app(ValiderClotureCaisseAction::class);

        $action->execute('2026-11-11', 100.0, 100.0, $this->admin->id, 'poste-01');

        $this->expectException(ValidationException::class);

        $action->execute('2026-11-11', 100.0, 100.0, $this->admin->id, 'poste-01');
    }

    /** @test */
    public function test_c1_deux_postes_differents_meme_jour_acceptes(): void
    {
        $action = app(ValiderClotureCaisseAction::class);

        $c1 = $action->execute('2026-11-11', 100.0, 100.0, $this->admin->id, 'poste-01');
        $c2 = $action->execute('2026-11-11', 100.0, 100.0, $this->admin->id, 'poste-02');

        $this->assertEquals('validée', $c1->statut);
        $this->assertEquals('validée', $c2->statut);
    }

    /** @test */
    public function test_c1_exercice_clos_refuse(): void
    {
        $this->exercice->update(['status' => 'closed']);

        $this->expectException(ValidationException::class);

        app(ValiderClotureCaisseAction::class)->execute('2026-11-11', 100.0, 100.0, $this->admin->id);
    }

    // ─── C2 : composant Livewire ────────────────────────────────────────────

    /** @test */
    public function test_c2_composant_livewire_affiche_recapitulatif(): void
    {
        $this->creerVente(2000.0, 'especes');
        $this->creerVente(500.0, 'mobile_money');

        Livewire::test(ClotureCaisse::class)
            ->assertSee('2 000')
            ->assertSee('500');
    }

    /** @test */
    public function test_c2_valider_via_livewire_cree_cloture(): void
    {
        Livewire::test(ClotureCaisse::class)
            ->set('fondDeCaisse', '300')
            ->set('montantCompte', '300')
            ->call('valider')
            ->assertHasNoErrors();

        $this->assertDatabaseHas('cash_closures', ['statut' => 'validée']);
    }

    // ─── C3 : push depuis le poste ─────────────────────────────────────────

    /** @test */
    public function test_c3_push_cloture_depuis_poste_cree_enregistrement(): void
    {
        $token = $this->admin->createToken('poste-sync')->plainTextToken;

        $this->postJson('/api/sync/push', [
            'cash_closures' => [[
                'id'            => \Illuminate\Support\Str::uuid(),
                'closure_date'  => '2026-11-11',
                'fond_de_caisse' => 200,
                'montant_compte' => 200,
                'device_id'     => 'poste-sync-test',
                'statut'        => 'en_cours',
                'updated_at'    => now()->toIso8601String(),
            ]],
        ], ['Authorization' => "Bearer $token"])
            ->assertOk();

        $this->assertDatabaseHas('cash_closures', [
            'closure_date' => '2026-11-11',
            'statut'       => 'validée',
        ]);
    }

    // ─── Helpers ────────────────────────────────────────────────────────────

    private function creerVente(float $total, string $mode): Sale
    {
        return Sale::create([
            'id'           => \Illuminate\Support\Str::uuid(),
            'sold_at'      => '2026-11-11 10:00:00',
            'total'        => $total,
            'payment_mode' => $mode,
            'status'       => 'normalisee',
            'device_id'    => null,
            'created_by'   => $this->admin->id,
        ]);
    }
}
