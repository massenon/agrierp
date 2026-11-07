<?php

namespace Tests\Feature;

use App\Livewire\Ventes\RetoursAvoirs;
use App\Models\CreditNote;
use App\Services\AvoirClientService;
use App\Services\Mecef\FacturationMecefService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Livewire\Livewire;
use Tests\Feature\Concerns\AvecEmecef;
use Tests\TestCase;

/**
 * MECEF-1 — la correction d'une facture normalisée passe par un AVOIR : transmis comme facture d'avoir `FA`, `reference` =
 * uid de la facture d'origine, même passerelle, même mécanisme ; un avoir sur une vente non normalisée ne transmet rien.
 */
class AvoirMecefTest extends TestCase
{
    use AvecEmecef;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->decorVentes();
        $this->reglerEmecef();
    }

    private function retourner(string $venteId, float $montant = 5900, float $qte = 1): void
    {
        Livewire::test(RetoursAvoirs::class)
            ->set('saleId', $venteId)->set('productId', $this->taxable->id)->set('qty', $qte)->set('amount', $montant)
            ->set('reason', 'Produit détérioré')->set('decision', 'reintegre')
            ->call('saveReturn')->assertHasNoErrors();
    }

    private function venteNormalisee(): \App\Models\Sale
    {
        $this->fauxEmecefSucces('uid-origine');
        $vente = $this->venteAFacturer();
        app(FacturationMecefService::class)->facturer($vente);

        return $vente->fresh();
    }

    public function test_l_avoir_d_une_vente_normalisee_part_comme_facture_fa_referencee_a_l_origine(): void
    {
        $vente = $this->venteNormalisee();
        Http::swap(new \Illuminate\Http\Client\Factory);
        Http::fake([
            self::URL.'/invoice' => Http::response(['uid' => 'uid-avoir-1'], 200),
            self::URL.'/invoice/*/confirm' => Http::response([
                'qrCode' => 'F;ED01000001;AVOIR-CODE;3202601234567;20261107111500', 'codeMECeFDGI' => 'AVOIR-CODE', 'counters' => '2/34 FA',
                'nim' => 'ED01000001', 'dateTime' => '2026-11-07T11:15:00',
            ], 200),
        ]);

        $this->retourner($vente->id);

        $avoir = CreditNote::firstOrFail();
        $this->assertSame('transmise', $avoir->mecef_status);
        $this->assertSame('uid-avoir-1', $avoir->mecef_uid);
        $this->assertSame('AVOIR-CODE', $avoir->mecef_code);
        $this->assertSame('2/34 FA', $avoir->mecef_compteurs);
        $this->assertNotNull($avoir->mecef_normalise_le);

        Http::assertSent(function (Request $q) {
            return $q->method() === 'POST' && str_ends_with($q->url(), '/invoice')
                && $q['type'] === 'FA' && $q['reference'] === 'uid-origine'
                && $q['items'][0]['quantity'] == 1 && $q['items'][0]['price'] == 5900.0
                && $q['payment'] === [['name' => 'ESPECES', 'amount' => 5900.0]];
        });

        // La vente d'origine, elle, n'a pas bougé : toujours normalisée, intacte.
        $this->assertSame('transmise', $vente->fresh()->mecef_status);
        $this->assertEquals(11800, (float) $vente->fresh()->total);
    }

    public function test_un_avoir_ne_repart_jamais_une_fois_normalise(): void
    {
        $vente = $this->venteNormalisee();
        $this->retourner($vente->id);
        $avoir = CreditNote::firstOrFail();
        $this->assertSame('transmise', $avoir->mecef_status);

        Http::swap(new \Illuminate\Http\Client\Factory);
        Http::fake();
        $r = app(FacturationMecefService::class)->facturerAvoir($avoir->id);

        $this->assertTrue($r['deja']);
        Http::assertNothingSent();
    }

    public function test_un_avoir_sur_une_vente_non_normalisee_garde_le_comportement_actuel_aucune_transmission(): void
    {
        Http::fake();
        $vente = $this->venteAFacturer();   // jamais facturée : en attente

        $this->retourner($vente->id);

        $avoir = CreditNote::firstOrFail();
        $this->assertNull($avoir->mecef_status);
        $this->assertNotNull($avoir->accounting_entry_id, 'l\'avoir est comptabilisé comme avant');
        Http::assertNothingSent();
        $this->assertTrue(app(FacturationMecefService::class)->facturerAvoir($avoir->id)['sans_objet']);
    }

    public function test_avoir_en_echec_reste_en_attente_et_se_retransmet_sans_doubler(): void
    {
        $vente = $this->venteNormalisee();
        Http::swap(new \Illuminate\Http\Client\Factory);
        Http::fake([self::URL.'/*' => Http::response('', 503)]);

        $this->retourner($vente->id);

        $avoir = CreditNote::firstOrFail();
        $this->assertSame('en_attente', $avoir->mecef_status);
        $this->assertStringContainsString('indisponible', $avoir->mecef_message);
        $this->assertNotNull($avoir->accounting_entry_id, 'l\'avoir existe et est comptabilisé même sans la DGI');

        Http::swap(new \Illuminate\Http\Client\Factory);
        $this->fauxEmecefSucces('uid-avoir-2');
        Livewire::test(RetoursAvoirs::class)->call('retryMecef', $avoir->id)
            ->assertDispatched('toast', fn ($n, $p) => $p['type'] === 'success');

        $this->assertSame('transmise', $avoir->fresh()->mecef_status);
    }

    public function test_module_desactive_l_avoir_d_une_facture_normalisee_attend_la_reactivation(): void
    {
        $vente = $this->venteNormalisee();
        $this->reglerEmecef('desactive');
        Http::swap(new \Illuminate\Http\Client\Factory);
        Http::fake();

        $this->retourner($vente->id);

        $avoir = CreditNote::firstOrFail();
        $this->assertSame('en_attente', $avoir->mecef_status);
        $this->assertStringContainsString('Module MeCeF désactivé', $avoir->mecef_message);
        Http::assertNothingSent();
    }

    public function test_le_service_d_avoir_seul_ne_transmet_pas_dans_sa_transaction(): void
    {
        $vente = $this->venteNormalisee();
        Http::swap(new \Illuminate\Http\Client\Factory);
        Http::fake();

        app(AvoirClientService::class)->enregistrer([
            'sale_id' => $vente->id, 'product_id' => $this->taxable->id, 'qty' => 1, 'amount' => 5900, 'reason' => 'Test', 'decision' => 'reintegre',
        ]);

        Http::assertNothingSent();   // la transmission est faite APRÈS la transaction, par l'appelant
    }

    public function test_l_avoir_envoye_par_un_poste_est_transmis_apres_la_transaction_de_l_envoi(): void
    {
        $vente = $this->venteNormalisee();
        Http::swap(new \Illuminate\Http\Client\Factory);
        $this->fauxEmecefSucces('uid-avoir-poste');

        $id = '88888888-8888-4888-8888-888888888888';
        $this->actingAs(\App\Models\User::first(), 'sanctum')->postJson('/api/sync/push', ['credit_notes' => [[
            'id' => $id, 'sale_id' => $vente->id, 'product_id' => $this->taxable->id, 'qty' => 1, 'amount' => 5900,
            'reason' => 'Retour du poste', 'decision' => 'reintegre', 'status' => 'en_attente', 'credit_date' => now()->toDateString(),
        ]]])->assertOk()->assertJsonPath('credit_notes.accepted.0', $id);

        $this->assertSame('transmise', CreditNote::find($id)->mecef_status);
        $this->assertSame(1, Http::recorded(fn (Request $q) => $q->method() === 'POST' && str_ends_with($q->url(), '/invoice'))->count());
    }
}
