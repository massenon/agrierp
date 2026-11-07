<?php

namespace Tests\Feature;

use App\Exceptions\FactureNormaliseeException;
use App\Livewire\Facturation\Facturation;
use App\Livewire\Ventes\ListeClients;
use App\Livewire\Ventes\PosInterface;
use App\Models\CompanySetting;
use App\Models\Customer;
use App\Models\Sale;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Services\Mecef\ChoixFactureService;
use App\Services\Mecef\FacturationMecefService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Validation\ValidationException;
use Livewire\Livewire;
use Tests\Feature\Concerns\AvecEmecef;
use Tests\TestCase;

/**
 * Demande du client (07/11/2026) — CHOIX À LA VENTE : « Facture simple » (défaut, JAMAIS transmise, pas de QR) ou « Facture
 * normalisée » (IFU du client facultatif, nom et prénom obligatoires, taux d'AIB 5 % / 1 % / N/A). Validé par UN point de passage
 * (`ChoixFactureService`) pour la caisse du web et l'envoi des postes ; sans AUCUN appel réel (`Http::fake`).
 */
class MecefChoixFactureTest extends TestCase
{
    use AvecEmecef;
    use RefreshDatabase;

    private const SALE = 'b1111111-1111-4111-8111-111111111111';

    protected function setUp(): void
    {
        parent::setUp();
        $this->decorVentes();
        $this->reglerEmecef();
        TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse Principale', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);
    }

    /** La caisse du web avec un panier d'une ligne (11 800 FCFA, deux plaquettes à 18 %). */
    private function caisse()
    {
        return Livewire::test(PosInterface::class)
            ->set('cart', [[
                'product_id' => $this->taxable->id, 'name' => $this->taxable->name, 'unit' => 'plaquette',
                'qty' => 2, 'montant' => 11800, 'lot_id' => null, 'lot_code' => null,
            ]])
            ->set('paymentMode', 'especes')
            ->set('cashReceived', 11800);
    }

    /** @return array<string, mixed> */
    private function lignePoste(array $plus = []): array
    {
        return array_merge([
            'id' => self::SALE, 'payment_mode' => 'especes', 'status' => 'validee',
            'subtotal' => 11800, 'discount' => 0, 'total' => 11800, 'sold_at' => now()->subMinute()->toDateTimeString(),
            'lines' => [['product_id' => $this->taxable->id, 'qty' => 2, 'unit_price' => 5900, 'manual_total_amount' => 11800]],
        ], $plus);
    }

    private function pousser(array $vente)
    {
        return $this->actingAs(User::first(), 'sanctum')->postJson('/api/sync/push', ['sales' => [$vente]]);
    }

    private function corps(): array
    {
        $envois = Http::recorded(fn (Request $r) => $r->method() === 'POST' && str_ends_with($r->url(), '/invoice'));
        $this->assertCount(1, $envois, 'une seule création e-MECeF');

        return json_decode($envois->first()[0]->body(), true);
    }

    // ═══ Facture simple ═══

    public function test_une_facture_simple_n_est_jamais_transmise_meme_module_actif(): void
    {
        Http::fake();

        $caisse = $this->caisse()->call('validateSale');

        $vente = Sale::sole();
        $this->assertSame('simple', $vente->facture_type);
        $this->assertNull($vente->client_ifu);
        $this->assertNull($vente->client_nom_facture);
        $this->assertNull($vente->aib_taux);
        $this->assertSame('en_attente', $vente->mecef_status);
        $this->assertNull($vente->mecef_qr_ref);
        Http::assertNothingSent();
        // Aucune alerte « non transmise » : la facture simple n'a rien à transmettre.
        $caisse->assertNotDispatched('toast', type: 'warning');

        // Même par la retransmission de l'écran Facturation, ou en appelant le service : rien ne part.
        $this->assertTrue(app(FacturationMecefService::class)->facturer($vente)['simple']);
        Livewire::test(Facturation::class)->call('retryMecef', $vente->id)->assertDispatched('toast', type: 'warning');
        Http::assertNothingSent();
    }

    public function test_le_choix_n_est_propose_que_module_actif_et_sinon_c_est_une_facture_simple(): void
    {
        Http::fake();
        $this->assertTrue($this->caisse()->instance()->facturationNormaliseeDisponible);

        CompanySetting::current()->update(['mecef_mode' => 'desactive']);
        $caisse = $this->caisse()->set('factureType', 'normalisee')->set('clientNomFacture', 'X')->call('validateSale');

        $this->assertFalse($caisse->instance()->facturationNormaliseeDisponible);
        $caisse->assertDontSee('Type de Facture');
        $this->assertSame('simple', Sale::sole()->facture_type);
        Http::assertNothingSent();
    }

    // ═══ Facture normalisée ═══

    public function test_une_facture_normalisee_est_transmise_avec_le_client_l_ifu_et_l_aib(): void
    {
        $this->fauxEmecefSucces();

        $this->caisse()
            ->set('factureType', 'normalisee')
            ->set('clientIfu', '1234567890123')
            ->set('clientNomFacture', 'KPOGNON Séraphin')
            ->set('aibTaux', '5%')
            ->call('validateSale');

        $vente = Sale::sole();
        $this->assertSame(['normalisee', '1234567890123', 'KPOGNON Séraphin', '5%'], [$vente->facture_type, $vente->client_ifu, $vente->client_nom_facture, $vente->aib_taux]);
        $this->assertSame('transmise', $vente->mecef_status);

        $charge = $this->corps();
        $this->assertSame(['name' => 'KPOGNON Séraphin', 'ifu' => '1234567890123'], $charge['client']);
        $this->assertSame('B', $charge['aib'], '5 % = B pour l\'API e-MECeF');
        $this->assertSame(11800, $charge['payment'][0]['amount']);
    }

    public function test_les_trois_taux_d_aib_vers_l_api(): void
    {
        foreach (['1%' => 'A', '5%' => 'B', 'N/A' => null] as $taux => $attendu) {
            Http::fake([self::URL.'/*' => Http::response(['uid' => 'u', 'qrCode' => 'F;NIM;X;ifu;date', 'codeMECeFDGI' => 'C', 'counters' => '1/1 FV', 'nim' => 'N', 'dateTime' => '2026-11-07T10:00:00'], 200)]);
            $vente = $this->venteAFacturer(choix: ['facture_type' => 'normalisee', 'client_nom_facture' => 'Client '.$taux, 'aib_taux' => $taux]);

            app(FacturationMecefService::class)->facturer($vente);

            $charge = json_decode(Http::recorded(fn (Request $r) => str_ends_with($r->url(), '/invoice'))->first()[0]->body(), true);
            $this->assertSame($attendu, $charge['aib'] ?? null, 'AIB '.$taux);
            Http::swap(new \Illuminate\Http\Client\Factory);
        }
    }

    public function test_ifu_vide_est_un_client_sans_ifu_le_champ_est_omis(): void
    {
        $this->fauxEmecefSucces();

        $this->caisse()->set('factureType', 'normalisee')->set('clientNomFacture', 'Madame ADJOVI Rose')->set('aibTaux', 'N/A')->call('validateSale');

        $vente = Sale::sole();
        $this->assertNull($vente->client_ifu, 'IFU vide = client sans IFU');
        $this->assertSame('transmise', $vente->mecef_status);
        $charge = $this->corps();
        $this->assertSame(['name' => 'Madame ADJOVI Rose'], $charge['client']);
        $this->assertArrayNotHasKey('aib', $charge);
    }

    public function test_validations_ifu_nom_et_aib_refus_motives_aucune_vente_ecrite(): void
    {
        Http::fake();

        $caisse = $this->caisse()->set('factureType', 'normalisee')->set('clientNomFacture', 'Client Essai');

        $caisse->set('clientIfu', '12345')->call('validateSale')
            ->assertHasErrors('clientIfu')
            ->assertDispatched('toast', message: ChoixFactureService::MOTIF_IFU, type: 'error')
            ->assertDispatched('open-modal', name: 'modal-facture-normalisee');
        $this->assertSame(0, Sale::count());

        $caisse->set('clientIfu', '12345678901234')->call('validateSale')->assertHasErrors('clientIfu');   // 14 chiffres
        $caisse->set('clientIfu', 'ABCDEFGHIJKLM')->call('validateSale')->assertHasErrors('clientIfu');

        $caisse->set('clientIfu', '')->set('clientNomFacture', '   ')->call('validateSale')
            ->assertHasErrors('clientNomFacture')
            ->assertDispatched('toast', message: ChoixFactureService::MOTIF_NOM, type: 'error');

        $caisse->set('clientNomFacture', 'Client Essai')->set('aibTaux', '9%')->call('validateSale')
            ->assertHasErrors('aibTaux')
            ->assertDispatched('toast', message: ChoixFactureService::MOTIF_AIB, type: 'error');

        $this->assertSame(0, Sale::count(), 'panier gardé, rien d\'écrit');
        Http::assertNothingSent();

        // Corrigé : la vente passe.
        $this->fauxEmecefSucces();
        $caisse->set('aibTaux', '5%')->call('validateSale')->assertHasNoErrors();
        $this->assertSame(1, Sale::count());
    }

    public function test_le_service_valide_pour_le_web_et_le_poste_avec_les_memes_motifs(): void
    {
        $service = app(ChoixFactureService::class);

        $this->assertSame(['facture_type' => 'simple', 'client_ifu' => null, 'client_nom_facture' => null, 'aib_taux' => null], $service->valider([]), 'absent = facture simple');
        $this->assertSame('simple', $service->valider(['facture_type' => 'simple', 'client_ifu' => 'zz', 'aib_taux' => '9%'])['facture_type'], 'une facture simple ignore l\'identité fiscale');
        $this->assertSame('1234567890123', $service->valider(['facture_type' => 'normalisee', 'client_ifu' => '123 456 789 0123', 'client_nom_facture' => ' A B ', 'aib_taux' => '1%'])['client_ifu']);

        foreach ([
            [['facture_type' => 'speciale'], 'facture_type', ChoixFactureService::MOTIF_TYPE],
            [['facture_type' => 'normalisee', 'aib_taux' => '5%'], 'client_nom_facture', ChoixFactureService::MOTIF_NOM],
            [['facture_type' => 'normalisee', 'client_nom_facture' => 'A', 'aib_taux' => null], 'aib_taux', ChoixFactureService::MOTIF_AIB],
            [['facture_type' => 'normalisee', 'client_nom_facture' => 'A', 'aib_taux' => '5%', 'client_ifu' => '1'], 'client_ifu', ChoixFactureService::MOTIF_IFU],
        ] as [$donnees, $champ, $motif]) {
            try {
                $service->valider($donnees);
                $this->fail('refus attendu pour '.$champ);
            } catch (ValidationException $e) {
                $this->assertSame($motif, $e->errors()[$champ][0]);
            }
        }
    }

    public function test_la_fenetre_se_prerempli_depuis_le_client_de_la_vente(): void
    {
        $client = Customer::create(['name' => 'SODJI Béatrice', 'ifu' => '9876543210123', 'is_active' => true]);

        $caisse = $this->caisse()->set('customerId', $client->id)->set('factureType', 'normalisee');

        $caisse->assertSet('clientNomFacture', 'SODJI Béatrice')
            ->assertSet('clientIfu', '9876543210123')
            ->assertSet('aibTaux', '5%')   // 5 % par défaut : le cas général
            ->assertDispatched('open-modal', name: 'modal-facture-normalisee');

        // Un client sans IFU : le nom seul est repris.
        $sans = Customer::create(['name' => 'Particulier', 'is_active' => true]);
        $this->caisse()->set('customerId', $sans->id)->set('factureType', 'normalisee')
            ->assertSet('clientNomFacture', 'Particulier')->assertSet('clientIfu', '');

        // Annuler la fenêtre ramène à la facture simple.
        $caisse->call('annulerFactureNormalisee')->assertSet('factureType', 'simple');
    }

    public function test_la_fenetre_est_un_x_modal_ouvert_par_evenement_jamais_par_if(): void
    {
        $blade = (string) file_get_contents(resource_path('views/livewire/ventes/pos-interface.blade.php'));

        $this->assertStringContainsString('<x-modal name="modal-facture-normalisee"', $blade);
        $this->assertStringNotContainsString('@if($factureType', str_replace("@if(\$factureType === 'normalisee')\n                            <button", '', $blade), 'la fenêtre n\'est jamais conditionnée par @if');
        $source = (string) file_get_contents(app_path('Livewire/Ventes/PosInterface.php'));
        $this->assertStringContainsString("dispatch('open-modal', name: 'modal-facture-normalisee')", $source);
        // Libellés et ordre de la fenêtre (le poste les reprend).
        $ordre = array_map(fn ($t) => strpos($blade, $t), ['>IFU du client<', '>Nom et prénom du client *<', '>Taux AIB<']);
        $this->assertSame($ordre, collect($ordre)->sort()->values()->all());
        $this->assertNotContains(false, $ordre);
    }

    // ═══ Poste : le choix voyage avec la vente, le serveur le revalide ═══

    public function test_le_poste_envoie_son_choix_le_serveur_le_valide_et_le_garde(): void
    {
        $this->fauxEmecefSucces();

        $this->pousser($this->lignePoste(['facture_type' => 'normalisee', 'client_ifu' => '1234567890123', 'client_nom_facture' => 'KPOGNON Séraphin', 'aib_taux' => '1%']))
            ->assertOk()->assertJsonPath('sales.accepted.0', self::SALE);

        $vente = Sale::findOrFail(self::SALE);
        $this->assertSame(['normalisee', '1234567890123', 'KPOGNON Séraphin', '1%'], [$vente->facture_type, $vente->client_ifu, $vente->client_nom_facture, $vente->aib_taux]);
        $this->assertSame('transmise', $vente->mecef_status);
        $this->assertSame('A', $this->corps()['aib']);
    }

    public function test_le_poste_sans_choix_est_une_facture_simple_jamais_transmise(): void
    {
        Http::fake();

        $this->pousser($this->lignePoste())->assertOk()->assertJsonPath('sales.accepted.0', self::SALE);

        $this->assertSame('simple', Sale::findOrFail(self::SALE)->facture_type);
        Http::assertNothingSent();
    }

    public function test_le_serveur_refuse_avec_un_motif_francais_un_choix_invalide_du_poste(): void
    {
        Http::fake();

        foreach ([
            [['facture_type' => 'normalisee', 'client_nom_facture' => 'A', 'aib_taux' => '5%', 'client_ifu' => '123'], ChoixFactureService::MOTIF_IFU],
            [['facture_type' => 'normalisee', 'client_nom_facture' => '', 'aib_taux' => '5%'], ChoixFactureService::MOTIF_NOM],
            [['facture_type' => 'normalisee', 'client_nom_facture' => 'A', 'aib_taux' => '7%'], ChoixFactureService::MOTIF_AIB],
            [['facture_type' => 'inconnue'], ChoixFactureService::MOTIF_TYPE],
        ] as [$choix, $motif]) {
            $this->pousser($this->lignePoste($choix))->assertOk()
                ->assertJsonPath('sales.accepted', [])
                ->assertJsonPath('sales.rejected.0.reason', $motif);
        }

        $this->assertSame(0, Sale::count());
        Http::assertNothingSent();
    }

    public function test_hors_ligne_la_vente_arrive_en_attente_puis_part_a_la_synchronisation(): void
    {
        // Le poste a vendu sans internet ; à la synchronisation la DGI est encore injoignable : la vente est gardée « en attente ».
        Http::fake([self::URL.'/*' => Http::response('', 503)]);
        $this->pousser($this->lignePoste(['facture_type' => 'normalisee', 'client_nom_facture' => 'Client Hors Ligne', 'aib_taux' => '5%']))->assertOk();

        $vente = Sale::findOrFail(self::SALE);
        $this->assertSame('en_attente', $vente->mecef_status);
        $this->assertStringContainsString('indisponible', $vente->mecef_message);

        // Plus tard (nouvelle synchronisation / retransmission) : elle part, une seule fois.
        Http::swap(new \Illuminate\Http\Client\Factory);
        $this->fauxEmecefSucces('uid-tardif');
        Livewire::test(Facturation::class)->call('retryMecef', $vente->id);
        $this->assertSame('transmise', $vente->fresh()->mecef_status);

        // Le tirage sert le choix et le statut au poste (« Facture normalisée demandée — en attente » tant que non normalisée).
        $tirage = $this->actingAs(User::first(), 'sanctum')->getJson('/api/sync/pull')->assertOk()->json('sales.0');
        $this->assertSame(['normalisee', 'Client Hors Ligne', '5%', 'transmise'], [$tirage['facture_type'], $tirage['client_nom_facture'], $tirage['aib_taux'], $tirage['mecef_status']]);
    }

    // ═══ Client : IFU ═══

    public function test_l_ifu_du_client_se_saisit_au_web_et_au_poste_synchronise(): void
    {
        // Fiche client du web.
        Livewire::test(ListeClients::class)->set('name', 'ZINSOU Marc')->set('ifu', '123')->call('saveCustomer')->assertHasErrors('ifu');
        Livewire::test(ListeClients::class)->set('name', 'ZINSOU Marc')->set('ifu', '1234567890123')->call('saveCustomer')->assertHasNoErrors();
        $this->assertSame('1234567890123', Customer::where('name', 'ZINSOU Marc')->value('ifu'));

        // Envoi du poste : IFU présent, mêmes règles.
        $id = 'c2222222-2222-4222-8222-222222222222';
        $this->actingAs(User::first(), 'sanctum')->postJson('/api/sync/push', ['customers' => [['id' => $id, 'name' => 'ZINSOU Poste', 'ifu' => '3200000000123']]])
            ->assertOk()->assertJsonPath('customers.accepted.0', $id);
        $this->assertSame('3200000000123', Customer::find($id)->ifu);

        $refus = $this->actingAs(User::first(), 'sanctum')->postJson('/api/sync/push', ['customers' => [['id' => 'c3333333-3333-4333-8333-333333333333', 'name' => 'Mauvais', 'ifu' => '42']]])
            ->assertOk()->assertJsonPath('customers.accepted', []);
        $this->assertStringContainsString('13 chiffres', $refus->json('customers.rejected.0.reason'));

        // Tirage : l'IFU descend ; un poste ancien (sans la clé) ne l'efface pas.
        $tirage = $this->actingAs(User::first(), 'sanctum')->getJson('/api/sync/pull')->json('customers');
        $this->assertContains('3200000000123', array_column($tirage, 'ifu'));
        $this->actingAs(User::first(), 'sanctum')->postJson('/api/sync/push', ['customers' => [['id' => $id, 'name' => 'ZINSOU Poste renommé']]])->assertOk();
        $this->assertSame('3200000000123', Customer::find($id)->ifu, 'clé absente = IFU conservé');
    }

    public function test_modifier_le_client_ne_touche_pas_la_facture_deja_normalisee_qui_reste_verrouillee(): void
    {
        $this->fauxEmecefSucces();
        $client = Customer::create(['name' => 'Ancien Nom', 'ifu' => '1111111111111', 'is_active' => true]);
        $vente = $this->venteAFacturer(choix: ['facture_type' => 'normalisee', 'client_ifu' => '1111111111111', 'client_nom_facture' => 'Ancien Nom', 'aib_taux' => '5%']);
        $vente->update(['customer_id' => $client->id]);
        app(FacturationMecefService::class)->facturer($vente);
        $this->assertTrue($vente->fresh()->estNormalisee());

        // La fiche change ...
        $client->update(['name' => 'Nouveau Nom', 'ifu' => '2222222222222']);

        // ... la facture normalisée garde ce qui a été déclaré, et ne se modifie plus.
        $v = $vente->fresh();
        $this->assertSame(['Ancien Nom', '1111111111111', '5%'], [$v->client_nom_facture, $v->client_ifu, $v->aib_taux]);
        foreach (['client_nom_facture' => 'Autre', 'client_ifu' => '3333333333333', 'aib_taux' => '1%', 'facture_type' => 'simple'] as $colonne => $valeur) {
            try {
                $v->update([$colonne => $valeur]);
                $this->fail($colonne.' d\'une facture normalisée modifié');
            } catch (FactureNormaliseeException) {
                $this->assertTrue(true);
            }
        }
    }

    // ═══ Écran Facturation et PDF ═══

    public function test_l_ecran_facturation_les_statuts_ne_concernent_que_les_normalisees(): void
    {
        Http::fake();
        $simple = $this->venteAFacturer(choix: ['facture_type' => 'simple']);
        $normalisee = $this->venteAFacturer(choix: ['facture_type' => 'normalisee', 'client_nom_facture' => 'N', 'aib_taux' => 'N/A']);

        $c = Livewire::test(Facturation::class);
        $c->assertSee('Facture simple');
        $kpis = $c->instance()->kpis;
        $this->assertSame([2, 0, 1, 0], [$kpis['factures_mois'], $kpis['transmises'], $kpis['en_attente'], $kpis['erreurs']], 'seule la normalisée compte dans les statuts MeCeF');

        $this->assertSame([$simple->id], $c->set('statusFilter', 'Facture simple')->instance()->sales->pluck('id')->all());
        $this->assertSame([$normalisee->id], $c->set('statusFilter', 'En attente')->instance()->sales->pluck('id')->all());
        $this->assertSame([], $c->set('statusFilter', 'Normalisée')->instance()->sales->pluck('id')->all());

        // Le bouton « Retransmettre » n'existe que pour la normalisée.
        $c->set('statusFilter', '')->assertSeeHtml("retryMecef('{$normalisee->id}')")->assertDontSeeHtml("retryMecef('{$simple->id}')");
    }

    public function test_la_facture_pdf_porte_ifu_nom_et_aib_si_normalisee_et_la_mention_simple_sinon(): void
    {
        Http::fake([
            self::URL.'/invoice' => Http::response(['uid' => 'uid-aib', 'total' => 11800, 'aib' => 590], 200),
            self::URL.'/invoice/*/confirm' => Http::response(['qrCode' => 'F;ED01;CODE;ifu;date', 'codeMECeFDGI' => 'CODE-DGI', 'counters' => '1/1 FV', 'nim' => 'ED01', 'dateTime' => '2026-11-07T10:15:00'], 200),
        ]);
        $normalisee = $this->venteAFacturer(choix: ['facture_type' => 'normalisee', 'client_ifu' => '1234567890123', 'client_nom_facture' => 'KPOGNON Séraphin', 'aib_taux' => '5%']);
        $simple = $this->venteAFacturer(choix: ['facture_type' => 'simple']);

        app(FacturationMecefService::class)->facturer($normalisee);
        // L'AIB est celui que la DGI a CALCULÉ (réponse de création), jamais le nôtre.
        $this->assertEquals(590, $normalisee->fresh()->mecef_aib_montant);

        $rendre = fn (Sale $v) => view('exports.facture-vente', ['sale' => $v->fresh()->load(['customer', 'lines.product'])])->render();

        $html = $rendre($normalisee);
        $this->assertStringContainsString('KPOGNON Séraphin', $html);
        $this->assertStringContainsString('1234567890123', $html);
        $this->assertStringContainsString('AIB : <strong>5 %</strong>', $html);
        $this->assertStringContainsString('montant calculé par la DGI : 590 FCFA', $html);
        $this->assertStringContainsString('CODE-DGI', $html);
        $this->assertStringNotContainsString('Facture simple', $html);

        $htmlSimple = $rendre($simple);
        $this->assertStringContainsString('Facture simple — non normalisée DGI', $htmlSimple);
        $this->assertStringNotContainsString('IFU du client', $htmlSimple);
        $this->assertStringNotContainsString('AIB', $htmlSimple);
        $this->assertStringNotContainsString('Code MeCeF/DGI', $htmlSimple);
    }
}
