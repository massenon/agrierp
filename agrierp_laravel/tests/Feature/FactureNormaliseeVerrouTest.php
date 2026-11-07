<?php

namespace Tests\Feature;

use App\Actions\AnnulerVenteAction;
use App\Exceptions\FactureNormaliseeException;
use App\Livewire\Ventes\HistoriqueVentes;
use App\Models\Customer;
use App\Models\Sale;
use App\Models\SaleLine;
use App\Services\Mecef\FacturationMecefService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\Feature\Concerns\AvecEmecef;
use Tests\TestCase;

/**
 * MECEF-1 — UNE FACTURE NORMALISÉE EST VERROUILLÉE : ni modification, ni annulation, ni changement de ligne, de montant
 * ou de client ; la correction passe par un avoir. Même refus, même message au web et par l'envoi d'un poste.
 */
class FactureNormaliseeVerrouTest extends TestCase
{
    use AvecEmecef;
    use RefreshDatabase;

    private const MESSAGE = 'Facture normalisée : corrigez-la par un avoir.';

    protected function setUp(): void
    {
        parent::setUp();
        $this->decorVentes();
        $this->reglerEmecef();
    }

    private function venteNormalisee(): Sale
    {
        $this->fauxEmecefSucces();
        $vente = $this->venteAFacturer();
        app(FacturationMecefService::class)->facturer($vente);

        return $vente->fresh('lines');
    }

    public function test_l_annulation_est_refusee_avant_de_toucher_au_stock(): void
    {
        $vente = $this->venteNormalisee();
        $stock = (float) $this->taxable->fresh()->stock_qty;

        try {
            app(AnnulerVenteAction::class)->execute($vente);
            $this->fail('une facture normalisée ne doit pas s\'annuler');
        } catch (FactureNormaliseeException $e) {
            $this->assertSame(self::MESSAGE, $e->getMessage());
        }

        $this->assertSame('validee', $vente->fresh()->status);
        $this->assertEquals($stock, (float) $this->taxable->fresh()->stock_qty);
    }

    public function test_aucun_champ_metier_de_la_vente_ne_se_modifie(): void
    {
        $vente = $this->venteNormalisee();
        $autre = Customer::create(['name' => 'Autre client', 'is_active' => true]);

        foreach ([['total' => 1], ['discount' => 500], ['customer_id' => $autre->id], ['payment_mode' => 'credit'], ['status' => 'annulee'], ['mecef_status' => 'en_attente'], ['mecef_qr_ref' => 'X']] as $changement) {
            try {
                $vente->fresh()->update($changement);
                $this->fail('modification acceptée : '.json_encode($changement));
            } catch (FactureNormaliseeException $e) {
                $this->assertSame(self::MESSAGE, $e->getMessage());
            }
        }

        $v = $vente->fresh();
        $this->assertEquals(11800, (float) $v->total);
        $this->assertSame('transmise', $v->mecef_status);

        // Ce qui reste permis : le lien comptable posé par le système.
        $v->update(['accounting_entry_id' => (string) \Illuminate\Support\Str::uuid()]);
        $this->assertNotNull($v->fresh()->accounting_entry_id);
    }

    public function test_les_lignes_sont_figees_ajout_modification_suppression(): void
    {
        $vente = $this->venteNormalisee();
        $ligne = $vente->lines->first();

        $essais = [
            fn () => $ligne->update(['qty' => 5]),
            fn () => $ligne->update(['manual_total_amount' => 1]),
            fn () => $ligne->delete(),
            fn () => SaleLine::create(['sale_id' => $vente->id, 'product_id' => $this->exonere->id, 'qty' => 1, 'unit_price' => 100, 'manual_total_amount' => 100]),
        ];

        foreach ($essais as $essai) {
            try {
                $essai();
                $this->fail('une ligne de facture normalisée a bougé');
            } catch (FactureNormaliseeException) {
                $this->addToAssertionCount(1);
            }
        }

        $this->assertSame(1, SaleLine::where('sale_id', $vente->id)->count());
        $this->assertEquals(2, (float) $ligne->fresh()->qty);
    }

    public function test_la_vente_normalisee_ne_se_supprime_pas(): void
    {
        $vente = $this->venteNormalisee();

        $this->expectException(FactureNormaliseeException::class);
        $vente->delete();
    }

    public function test_une_vente_non_normalisee_reste_annulable_et_modifiable(): void
    {
        $vente = $this->venteAFacturer();

        $this->assertTrue(app(AnnulerVenteAction::class)->execute($vente));
        $this->assertSame('annulee', $vente->fresh()->status);

        $autre = $this->venteAFacturer();
        $autre->update(['discount' => 100]);
        $this->assertEquals(100, (float) $autre->fresh()->discount);
    }

    public function test_au_web_l_annulation_d_une_facture_normalisee_est_refusee_avec_le_motif(): void
    {
        $vente = $this->venteNormalisee();

        Livewire::test(HistoriqueVentes::class)
            ->call('confirmCancel', $vente->id)
            ->call('cancelSale')
            ->assertDispatched('toast', fn ($nom, $p) => $p['type'] === 'error' && $p['message'] === self::MESSAGE);

        $this->assertSame('validee', $vente->fresh()->status);
    }

    public function test_par_l_envoi_d_un_poste_l_annulation_est_refusee_avec_le_meme_message(): void
    {
        $vente = $this->venteNormalisee();

        $reponse = $this->actingAs(\App\Models\User::first(), 'sanctum')->postJson('/api/sync/push', ['sales' => [[
            'id' => $vente->id, 'payment_mode' => 'especes', 'subtotal' => 11800, 'discount' => 0, 'total' => 11800, 'status' => 'annulee',
            'lines' => [['product_id' => $this->taxable->id, 'qty' => 2, 'unit_price' => 5900, 'manual_total_amount' => 11800]],
        ]]])->assertOk();

        $this->assertSame([], $reponse->json('sales.accepted'));
        $this->assertSame(self::MESSAGE, $reponse->json('sales.rejected.0.reason'));
        $this->assertSame('validee', $vente->fresh()->status);
    }

    public function test_l_historique_montre_le_cadenas_a_la_place_du_bouton_annuler(): void
    {
        $vente = $this->venteNormalisee();

        Livewire::test(HistoriqueVentes::class)
            ->assertSeeHtml('title="'.self::MESSAGE.'"')
            ->assertDontSeeHtml("confirmCancel('{$vente->id}')");
    }
}
