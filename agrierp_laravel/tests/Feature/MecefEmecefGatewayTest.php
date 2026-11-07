<?php

namespace Tests\Feature;

use App\Models\Sale;
use App\Services\Mecef\EmecefGateway;
use App\Services\Mecef\FacturationMecefService;
use App\Services\Mecef\MecefFactureBuilder;
use App\Services\Mecef\MecefGatewayInterface;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\Feature\Concerns\AvecEmecef;
use Tests\TestCase;

/**
 * MECEF-1 — la passerelle e-MECeF, sans AUCUN appel réel (`Http::fake`) : succès, refus, expiration, réseau coupé,
 * double clic, jeton absent, modes désactivé et boîtier, reprise par la confirmation seule, charge utile.
 */
class MecefEmecefGatewayTest extends TestCase
{
    use AvecEmecef;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->decorVentes();
        $this->reglerEmecef();
    }

    private function appels(string $methode, string $fin): int
    {
        return Http::recorded(fn (Request $r) => $r->method() === $methode && str_ends_with($r->url(), $fin))->count();
    }

    public function test_succes_la_vente_est_normalisee_avec_tout_ce_que_la_dgi_renvoie(): void
    {
        $this->fauxEmecefSucces();
        $vente = $this->venteAFacturer();

        $r = app(FacturationMecefService::class)->facturer($vente);

        $this->assertTrue($r['transmise']);
        $v = $vente->fresh();
        $this->assertSame('transmise', $v->mecef_status);
        $this->assertSame('uid-dgi-001', $v->mecef_uid);
        $this->assertSame('F;ED01000001;TEST-AAAA-BBBB-CCCC;3202601234567;20261107101500', $v->mecef_qr_ref);
        $this->assertSame('TEST-AAAA-BBBB-CCCC', $v->mecef_code);
        $this->assertSame('ED01000001', $v->mecef_nim);
        $this->assertSame('12/34 FV', $v->mecef_compteurs);
        $this->assertSame('2026-11-07 10:15:00', $v->mecef_normalise_le->format('Y-m-d H:i:s'));
        $this->assertNull($v->mecef_message);

        // Le jeton part en Bearer, l'IFU et l'opérateur dans la charge.
        Http::assertSent(fn (Request $q) => str_ends_with($q->url(), '/invoice') && $q->method() === 'POST'
            && $q->hasHeader('Authorization', 'Bearer '.self::JETON)
            && $q['ifu'] === '3202601234567' && $q['type'] === 'FV'
            && $q['operator'] === ['id' => '7', 'name' => 'Caissière Test']);
    }

    public function test_double_clic_une_vente_normalisee_n_est_jamais_retransmise(): void
    {
        $this->fauxEmecefSucces();
        $vente = $this->venteAFacturer();
        $service = app(FacturationMecefService::class);

        $service->facturer($vente);
        $deuxieme = $service->facturer($vente->id);

        $this->assertTrue($deuxieme['deja']);
        $this->assertSame(1, $this->appels('POST', '/invoice'));
        $this->assertSame(1, $this->appels('PUT', '/confirm'));
    }

    public function test_refus_4xx_la_vente_est_refusee_avec_le_motif_de_la_dgi_en_francais_et_reste_retransmissible(): void
    {
        Http::fake([self::URL.'/invoice' => Http::response(['errorCode' => '4', 'errorDesc' => 'IFU inconnu'], 422)]);
        $vente = $this->venteAFacturer();

        $r = app(FacturationMecefService::class)->facturer($vente);

        $this->assertFalse($r['transmise']);
        $v = $vente->fresh();
        $this->assertSame('erreur', $v->mecef_status);
        $this->assertStringContainsString('Création refusée par e-MECeF (422)', $v->mecef_message);
        $this->assertStringContainsString('IFU inconnu', $v->mecef_message);
        $this->assertNull($v->mecef_uid);
        $this->assertSame(0, $this->appels('PUT', '/confirm'), 'jamais de confirmation sans création');
    }

    public function test_jeton_refuse_401_la_vente_reste_en_attente_et_aucune_exception(): void
    {
        Http::fake([self::URL.'/invoice' => Http::response(['message' => 'Unauthenticated'], 401)]);
        $vente = $this->venteAFacturer();

        $r = app(FacturationMecefService::class)->facturer($vente);

        $this->assertFalse($r['transmise']);
        $this->assertSame('en_attente', $vente->fresh()->mecef_status);
        $this->assertStringContainsString('Jeton e-MECeF refusé par la DGI (401)', $vente->fresh()->mecef_message);
        $this->assertStringNotContainsString(self::JETON, $vente->fresh()->mecef_message);
    }

    public function test_reseau_coupe_la_vente_reste_en_attente_avec_un_motif_francais(): void
    {
        $essais = 0;
        Http::fake(function () use (&$essais) {
            $essais++;

            throw new ConnectionException('cURL error 6: Could not resolve host');
        });
        $vente = $this->venteAFacturer();

        $r = app(FacturationMecefService::class)->facturer($vente);

        $this->assertFalse($r['transmise']);
        $v = $vente->fresh();
        $this->assertSame('en_attente', $v->mecef_status);
        $this->assertStringContainsString('Réseau indisponible', $v->mecef_message);
        $this->assertStringNotContainsString('cURL', $v->mecef_message, 'le détail technique n\'est jamais montré');
        $this->assertSame(1, $essais, 'un seul essai de création');
    }

    public function test_service_indisponible_5xx_reste_en_attente(): void
    {
        Http::fake([self::URL.'/invoice' => Http::response('Bad gateway', 502)]);
        $vente = $this->venteAFacturer();

        app(FacturationMecefService::class)->facturer($vente);

        $this->assertSame('en_attente', $vente->fresh()->mecef_status);
        $this->assertStringContainsString('Service e-MECeF indisponible (502)', $vente->fresh()->mecef_message);
    }

    public function test_creation_reussie_confirmation_perdue_l_uid_est_garde_et_la_reprise_confirme_sans_recreer(): void
    {
        Http::fake([
            self::URL.'/invoice' => Http::response(['uid' => 'uid-dgi-777'], 200),
            self::URL.'/invoice/*/confirm' => Http::response('', 500),
        ]);
        $vente = $this->venteAFacturer();

        app(FacturationMecefService::class)->facturer($vente);

        $v = $vente->fresh();
        $this->assertSame('en_attente', $v->mecef_status);
        $this->assertSame('uid-dgi-777', $v->mecef_uid, 'l\'uid est gardé pour reprendre');
        $this->assertSame(1, $this->appels('POST', '/invoice'));

        // Reprise : synchronisation (GET) puis CONFIRMATION seule — jamais une seconde création.
        Http::swap(new \Illuminate\Http\Client\Factory);
        Http::fake([
            self::URL.'/invoice/uid-dgi-777' => Http::response(['uid' => 'uid-dgi-777', 'status' => 'pending'], 200),
            self::URL.'/invoice/*/confirm' => Http::response([
                'qrCode' => 'F;NIM;CODE;3202601234567;20261107101600', 'codeMECeFDGI' => 'CODE', 'counters' => '1/1 FV', 'nim' => 'NIM',
                'dateTime' => '2026-11-07T10:16:00',
            ], 200),
        ]);

        $r = app(FacturationMecefService::class)->facturer($vente->id);

        $this->assertTrue($r['transmise']);
        $this->assertSame('transmise', $vente->fresh()->mecef_status);
        $this->assertSame(0, $this->appels('POST', '/invoice'), 'aucune nouvelle création lors de la reprise');
        $this->assertSame(1, $this->appels('GET', '/invoice/uid-dgi-777'));
    }

    public function test_expiration_a_la_confirmation_la_vente_est_expiree_puis_une_nouvelle_creation_est_permise(): void
    {
        Http::fake([
            self::URL.'/invoice' => Http::response(['uid' => 'uid-vieux'], 200),
            self::URL.'/invoice/*/confirm' => Http::response(['errorCode' => '9', 'errorDesc' => 'Invoice expired'], 400),
        ]);
        $vente = $this->venteAFacturer();

        app(FacturationMecefService::class)->facturer($vente);

        $v = $vente->fresh();
        $this->assertSame('expiree', $v->mecef_status);
        $this->assertNull($v->mecef_uid, 'une facture expirée ne se reprend plus : l\'uid est oublié');
        $this->assertStringContainsString('expirée', $v->mecef_message);

        // Retransmission : cette fois une NOUVELLE création est légitime.
        Http::swap(new \Illuminate\Http\Client\Factory);
        $this->fauxEmecefSucces('uid-neuf');
        app(FacturationMecefService::class)->facturer($vente->id);
        $this->assertSame('transmise', $vente->fresh()->mecef_status);
        $this->assertSame('uid-neuf', $vente->fresh()->mecef_uid);
    }

    public function test_reprise_d_une_facture_disparue_chez_la_dgi_est_expiree(): void
    {
        $vente = $this->venteAFacturer();
        $vente->update(['mecef_uid' => 'uid-disparu']);
        Http::fake([self::URL.'/invoice/uid-disparu' => Http::response('', 404)]);

        app(FacturationMecefService::class)->facturer($vente->id);

        $this->assertSame('expiree', $vente->fresh()->mecef_status);
        $this->assertSame(0, $this->appels('PUT', '/confirm'));
        $this->assertSame(0, $this->appels('POST', '/invoice'));
    }

    public function test_jeton_absent_aucun_appel_la_vente_reste_en_attente(): void
    {
        $this->reglerEmecef('emecef', null);
        Http::fake();
        $vente = $this->venteAFacturer();

        $r = app(FacturationMecefService::class)->facturer($vente);

        $this->assertFalse($r['transmise']);
        $this->assertSame('en_attente', $vente->fresh()->mecef_status);
        $this->assertStringContainsString('Jeton e-MECeF non configuré', $vente->fresh()->mecef_message);
        Http::assertNothingSent();
    }

    public function test_ifu_invalide_aucun_appel(): void
    {
        $this->reglerEmecef('emecef', self::JETON, '12345');
        Http::fake();
        $vente = $this->venteAFacturer();

        app(FacturationMecefService::class)->facturer($vente);

        $this->assertStringContainsString('13 chiffres', $vente->fresh()->mecef_message);
        Http::assertNothingSent();
    }

    public function test_mode_desactive_rien_n_est_transmis(): void
    {
        $this->reglerEmecef('desactive');
        Http::fake();
        $vente = $this->venteAFacturer();

        $r = app(FacturationMecefService::class)->facturer($vente);

        $this->assertTrue($r['inactif']);
        $this->assertSame('en_attente', $vente->fresh()->mecef_status);
        Http::assertNothingSent();
    }

    public function test_mode_boitier_squelette_ne_transmet_rien_et_le_dit(): void
    {
        $this->reglerEmecef('boitier');
        Http::fake();
        $vente = $this->venteAFacturer();

        $r = app(FacturationMecefService::class)->facturer($vente);

        $this->assertFalse($r['transmise']);
        $this->assertSame('Mode boîtier : transmission par le poste non encore disponible.', $r['message']);
        $this->assertSame('en_attente', $vente->fresh()->mecef_status);
        $this->assertSame('Mode boîtier : transmission par le poste non encore disponible.', $vente->fresh()->mecef_message);
        Http::assertNothingSent();
    }

    public function test_la_fabrique_choisit_la_passerelle_selon_le_mode(): void
    {
        $this->assertInstanceOf(EmecefGateway::class, app(MecefGatewayInterface::class));

        $this->reglerEmecef('boitier');
        $this->assertInstanceOf(\App\Services\Mecef\BoitierMecefGateway::class, app(MecefGatewayInterface::class));

        // Jamais réglé : le commutateur général décide (phpunit.xml l'allume : passerelle de démonstration).
        \App\Models\CompanySetting::current()->update(['mecef_mode' => null]);
        $this->assertInstanceOf(\App\Services\Mecef\FakeMecefGateway::class, app(MecefGatewayInterface::class));
    }

    public function test_charge_utile_groupes_de_taxe_remise_et_paiement_egal_au_total(): void
    {
        $vente = $this->venteAFacturer([[$this->taxable, 2, 11800], [$this->exonere, 10, 2000]], remise: 1380, mode: 'mobile_money');

        $charge = app(MecefFactureBuilder::class)->pourVente($vente, ['ifu' => '3202601234567', 'operateur_id' => '7', 'operateur_nom' => 'Caissière Test']);

        $this->assertSame('FV', $charge['type']);
        $this->assertSame(['name' => 'AMOUSSOU Régis'], $charge['client']);
        $this->assertSame('B', $charge['items'][0]['taxGroup']);
        $this->assertSame('A', $charge['items'][1]['taxGroup']);
        // Remise de 1 380 au prorata de 11 800 / 2 000 : 1 180 puis le reliquat 200 sur la dernière ligne.
        $this->assertEquals(5310.0, $charge['items'][0]['price']);     // (11 800 − 1 180) / 2
        $this->assertEquals(5900.0, $charge['items'][0]['originalPrice']);
        $this->assertSame('Remise', $charge['items'][0]['priceModification']);
        $this->assertEquals(180.0, $charge['items'][1]['price']);      // (2 000 − 200) / 10
        $this->assertEquals(200.0, $charge['items'][1]['originalPrice']);

        $totalLignes = 5310 * 2 + 180 * 10;
        $this->assertSame(12420, $totalLignes);
        $this->assertSame(12420, (int) $vente->total);
        $this->assertSame([['name' => 'MOBILEMONEY', 'amount' => 12420.0]], $charge['payment']);
    }

    public function test_un_taux_de_tva_inconnu_est_refuse_avec_son_motif_sans_appel(): void
    {
        $this->taxable->update(['tva_rate' => 9]);
        Http::fake();
        $vente = $this->venteAFacturer();

        app(FacturationMecefService::class)->facturer($vente);

        $v = $vente->fresh();
        $this->assertSame('erreur', $v->mecef_status);
        $this->assertStringContainsString('Taux de TVA de 9 % non pris en charge', $v->mecef_message);
        Http::assertNothingSent();
    }

    public function test_la_facture_pdf_porte_le_qr_et_les_mentions_de_la_dgi_et_rien_d_invente_sans_normalisation(): void
    {
        $vente = $this->venteAFacturer();
        $html = fn () => view('exports.facture-vente', ['sale' => $vente->fresh()->load(['customer', 'lines.product'])])->render();

        // En attente : aucune mention inventée.
        $this->assertStringContainsString('Facture émise sans certification MeCeF.', $html());
        $this->assertStringNotContainsString('Code MeCeF/DGI', $html());
        $this->assertStringNotContainsString('data:image/svg+xml', $html());

        $this->fauxEmecefSucces();
        app(FacturationMecefService::class)->facturer($vente);

        $page = $html();
        $this->assertStringContainsString('Facture normalisée MeCeF', $page);
        $this->assertStringContainsString('Code MeCeF/DGI : TEST-AAAA-BBBB-CCCC', $page);
        $this->assertStringContainsString('NIM : ED01000001', $page);
        $this->assertStringContainsString('Compteurs : 12/34 FV', $page);
        $this->assertStringContainsString('Normalisée le 07/11/2026 à 10:15:00', $page);
        $this->assertStringContainsString('data:image/svg+xml;base64,', $page);
        $this->assertStringNotContainsString('Facture émise sans certification', $page);

        // Le PDF se rend réellement, QR compris.
        $pdf = app(\App\Services\PdfExportService::class)->render('exports.facture-vente', ['sale' => $vente->fresh()->load(['customer', 'lines.product'])], 'Facture', 'Test', 'portrait');
        $this->assertStringStartsWith('%PDF', $pdf->output());
    }
}
