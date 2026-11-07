<?php

namespace Tests\Feature;

use App\Actions\RecordSaleAccountingEntryAction;
use App\Livewire\Ventes\PosInterface;
use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\Customer;
use App\Models\Receivable;
use App\Models\Sale;
use App\Models\TreasuryAccount;
use App\Services\Mecef\FacturationMecefService;
use App\Services\Mecef\MecefFactureBuilder;
use App\Services\VatDeclarationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Livewire\Livewire;
use Tests\Feature\Concerns\AvecEmecef;
use Tests\TestCase;

/**
 * Demande du client (07/11/2026) — LES FRAIS DE LIVRAISON SONT INCLUS DANS LA VENTE.
 *
 * Décision : une livraison « facturée » entre dans `sales.total` (nouvelles ventes, drapeau `delivery_in_total`) ; encaissée ou
 * due avec le reste (trésorerie, créance) ; produit propre au compte 7071 « Ports, emballages perdus et autres frais facturés »
 * (SYSCOHADA révisé ; repli sur 701 si le compte manque) ; TVA AU TAUX DE LA VENTE (celui de la ligne principale) ; ligne
 * « Frais de livraison » sur la facture normalisée, groupe B (18 %) ou A (exonéré) comme le reste. Les ventes DÉJÀ enregistrées
 * (drapeau faux) gardent leurs frais hors total, d'un centime près.
 */
class MecefLivraisonTest extends TestCase
{
    use AvecEmecef;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->decorVentes();
        $this->reglerEmecef();
        ChartOfAccount::create(['code' => '7071', 'label' => 'Ports, emballages perdus et autres frais facturés', 'class' => 7, 'is_active' => true]);
        TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse Principale', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);
    }

    /** @param array<int, array{0: \App\Models\Product, 1: float, 2: int}> $lignes */
    private function caisseLivree(array $lignes, $frais, string $mode = 'especes', ?string $client = null)
    {
        return Livewire::test(PosInterface::class)
            ->set('cart', array_map(fn ($l) => [
                'product_id' => $l[0]->id, 'name' => $l[0]->name, 'unit' => $l[0]->unit, 'qty' => $l[1], 'montant' => $l[2], 'lot_id' => null, 'lot_code' => null,
            ], $lignes))
            ->set('paymentMode', $mode)
            ->set('customerId', $client ?? '')
            ->set('deliveryConcerned', true)
            ->set('deliveryMode', 'facturee')
            ->set('deliveryFrais', $frais);
    }

    /** @return array<string, float> débit/crédit par code de compte de l'écriture de la vente */
    private function ecriture(Sale $vente): array
    {
        $entree = AccountingEntry::findOrFail($vente->fresh()->accounting_entry_id);
        $lignes = [];
        foreach ($entree->lines()->with('account')->get() as $l) {
            $lignes[$l->account->code] = ['debit' => (float) $l->debit, 'credit' => (float) $l->credit];
        }

        return $lignes;
    }

    private function assertEquilibre(Sale $vente): void
    {
        $entree = AccountingEntry::findOrFail($vente->fresh()->accounting_entry_id);
        $this->assertEqualsWithDelta((float) $entree->lines->sum('debit'), (float) $entree->lines->sum('credit'), 0.001, 'SUM(debit) = SUM(credit)');
        $this->assertEqualsWithDelta((float) $vente->total, (float) $entree->lines->sum('debit'), 0.001, 'le débit = le total de la vente (livraison comprise)');
    }

    public function test_la_livraison_facturee_entre_dans_le_total_la_tresorerie_et_l_ecriture(): void
    {
        Http::fake();
        // 2 plaquettes à 18 % (11 800 TTC) + 2 500 de livraison : total 14 300.
        $this->caisseLivree([[$this->taxable, 2, 11800]], 2500)->call('validateSale');

        $vente = Sale::sole();
        $this->assertEquals(11800, (float) $vente->subtotal);
        $this->assertEquals(2500, (float) $vente->delivery_fee);
        $this->assertTrue($vente->delivery_in_total);
        $this->assertEquals(14300, (float) $vente->total, 'le total de la vente INCLUT la livraison');

        // Écriture : D 531 14 300 ; C 701 10 000 (produits HT) ; C 7071 2 119 (livraison HT) ; C 443 2 181 (1 800 + 381).
        $this->assertEquals([
            '531' => ['debit' => 14300.0, 'credit' => 0.0],
            '701' => ['debit' => 0.0, 'credit' => 10000.0],
            '7071' => ['debit' => 0.0, 'credit' => 2119.0],
            '443' => ['debit' => 0.0, 'credit' => 2181.0],
        ], $this->ecriture($vente));
        $this->assertEquilibre($vente);

        // Trésorerie : les frais sont encaissés avec le reste (les deux livres : table et grand livre).
        $this->assertEquals(14300, (float) TreasuryAccount::where('account_code', '531')->value('balance'));
    }

    public function test_livraison_exoneree_quand_la_ligne_principale_l_est_aucune_tva_sur_les_frais(): void
    {
        Http::fake();
        // Maïs exonéré 20 000 > plaquettes 11 800 : la ligne principale est exonérée, la livraison aussi.
        $this->caisseLivree([[$this->taxable, 2, 11800], [$this->exonere, 40, 20000]], 3000)->call('validateSale');

        $vente = Sale::sole();
        $this->assertEquals(34800, (float) $vente->total);
        $e = $this->ecriture($vente);
        $this->assertEquals(3000.0, $e['7071']['credit'], 'livraison exonérée : tout au produit, aucune TVA dessus');
        $this->assertEquals(1800.0, $e['443']['credit'], 'la TVA des seules plaquettes');
        $this->assertEquals(10000.0 + 20000.0, $e['701']['credit']);
        $this->assertEquilibre($vente);
    }

    public function test_creance_a_credit_inclut_la_livraison(): void
    {
        Http::fake();
        $client = Customer::create(['name' => 'Client à terme', 'is_active' => true]);

        $this->caisseLivree([[$this->exonere, 10, 5000]], 1000, 'credit', $client->id)->call('validateSale');

        $vente = Sale::sole();
        $this->assertEquals(6000, (float) $vente->total);
        $this->assertEquals(6000, (float) Receivable::sole()->amount, 'la créance couvre la livraison');
        $e = $this->ecriture($vente);
        $this->assertEquals(6000.0, $e['411']['debit']);
        $this->assertEquilibre($vente);
        $this->assertEquals(0, (float) TreasuryAccount::where('account_code', '531')->value('balance'), 'rien en caisse : tout est à crédit');
    }

    public function test_sans_compte_7071_le_produit_de_la_livraison_va_au_701_et_l_ecriture_reste_equilibree(): void
    {
        Http::fake();
        ChartOfAccount::where('code', '7071')->delete();

        $this->caisseLivree([[$this->taxable, 2, 11800]], 2500)->call('validateSale');

        $vente = Sale::sole();
        $e = $this->ecriture($vente);
        $this->assertArrayNotHasKey('7071', $e);
        $this->assertEquals(10000.0 + 2119.0, $e['701']['credit']);
        $this->assertEquilibre($vente);
    }

    public function test_les_ventes_deja_enregistrees_gardent_leurs_frais_hors_total_et_leur_ecriture(): void
    {
        Http::fake();
        // Une vente d'AVANT (drapeau faux, frais saisis mais hors total) : écriture sur 11 800 seulement, comme avant.
        $vente = $this->venteAFacturer(choix: ['facture_type' => 'simple']);
        $vente->update(['delivery_mode' => 'facturee', 'delivery_fee' => 2500]);
        $this->assertFalse($vente->fresh()->delivery_in_total);

        app(RecordSaleAccountingEntryAction::class)->execute($vente->fresh('lines'));

        $this->assertEquals([
            '531' => ['debit' => 11800.0, 'credit' => 0.0],
            '701' => ['debit' => 0.0, 'credit' => 10000.0],
            '443' => ['debit' => 0.0, 'credit' => 1800.0],
        ], $this->ecriture($vente));
        $this->assertEquilibre($vente);

        // Et sa facture DGI ne porte aucune ligne de livraison (hors total, hors facture, comme avant).
        $charge = app(MecefFactureBuilder::class)->pourVente($vente->fresh('lines'), ['ifu' => '3202601234567', 'operateur_id' => '7', 'operateur_nom' => 'X']);
        $this->assertCount(1, $charge['items']);
    }

    public function test_la_facture_normalisee_porte_une_ligne_frais_de_livraison_et_le_total_envoye_inclut_la_livraison(): void
    {
        $this->fauxEmecefSucces();

        $this->caisseLivree([[$this->taxable, 2, 11800]], 2500)
            ->set('factureType', 'normalisee')->set('clientNomFacture', 'Client Livré')->set('aibTaux', '5%')
            ->call('validateSale');

        $vente = Sale::sole();
        $this->assertSame('transmise', $vente->mecef_status);

        Http::assertSent(function (Request $q) {
            if (! str_ends_with($q->url(), '/invoice') || $q->method() !== 'POST') {
                return false;
            }
            $charge = json_decode($q->body(), true);
            $this->assertCount(2, $charge['items']);
            $this->assertSame(['name' => 'Plaquette d\'œufs', 'price' => 5900, 'quantity' => 2, 'taxGroup' => 'B'], $charge['items'][0]);
            $this->assertSame(['name' => 'Frais de livraison', 'price' => 2500, 'quantity' => 1, 'taxGroup' => 'B'], $charge['items'][1], 'livraison taxable 18 % = B, comme la vente');
            $this->assertSame([['name' => 'ESPECES', 'amount' => 14300]], $charge['payment'], 'total envoyé = 11 800 + 2 500');

            return true;
        });
    }

    public function test_livraison_d_une_vente_exoneree_part_en_groupe_a(): void
    {
        $vente = $this->venteAFacturer([[$this->exonere, 10, 5000]], choix: ['facture_type' => 'normalisee', 'client_nom_facture' => 'N', 'aib_taux' => 'N/A']);
        $vente->update(['delivery_mode' => 'facturee', 'delivery_fee' => 1000, 'delivery_in_total' => true, 'subtotal' => 5000, 'total' => 6000]);

        $charge = app(MecefFactureBuilder::class)->pourVente($vente->fresh('lines'), ['ifu' => '3202601234567', 'operateur_id' => '7', 'operateur_nom' => 'X']);

        $this->assertSame(['A', 'A'], array_column($charge['items'], 'taxGroup'));
        $this->assertSame(['Maïs brut', 'Frais de livraison'], array_column($charge['items'], 'name'));
        $this->assertSame(6000, $charge['payment'][0]['amount']);
    }

    public function test_les_frais_decimaux_sont_arrondis_a_l_entier_a_la_saisie(): void
    {
        Http::fake();

        $this->caisseLivree([[$this->exonere, 10, 5000]], 1000.6)->call('validateSale');

        $vente = Sale::sole();
        $this->assertSame(1001, (int) $vente->delivery_fee);
        $this->assertEquals(6001, (float) $vente->total);
    }

    public function test_les_autres_modes_de_livraison_n_ajoutent_rien(): void
    {
        Http::fake();

        foreach (['gratuite', 'client', 'incluse'] as $mode) {
            Sale::query()->delete();
            AccountingEntry::query()->delete();
            Livewire::test(PosInterface::class)
                ->set('cart', [['product_id' => $this->exonere->id, 'name' => 'Maïs', 'unit' => 'kg', 'qty' => 10, 'montant' => 5000, 'lot_id' => null, 'lot_code' => null]])
                ->set('deliveryConcerned', true)->set('deliveryMode', $mode)->set('deliveryFrais', 999)
                ->call('validateSale');

            $v = Sale::sole();
            $this->assertEquals(5000, (float) $v->total, $mode);
            $this->assertEquals(0, (float) $v->delivery_fee, $mode);
            $this->assertFalse($v->delivery_in_total, $mode);
        }
    }

    public function test_la_declaration_de_tva_reprend_la_tva_de_la_livraison_au_taux_de_la_vente(): void
    {
        $vente = $this->venteAFacturer([[$this->taxable, 2, 11800]], choix: ['facture_type' => 'normalisee', 'client_nom_facture' => 'N', 'aib_taux' => 'N/A']);
        $vente->update(['delivery_fee' => 2500, 'delivery_in_total' => true, 'total' => 14300]);
        \Illuminate\Support\Facades\DB::table('sales')->where('id', $vente->id)->update(['mecef_status' => 'transmise']);

        $d = app(VatDeclarationService::class)->tvaCollectee(now()->startOfMonth()->toDateString(), now()->endOfMonth()->toDateString());

        $this->assertEquals([14300.0, 2181.0], [$d['total_ttc'], $d['total_tva']]);
        $this->assertEquals(14300.0, $d['total_ht'] + $d['total_tva']);
    }

    public function test_le_total_envoye_a_la_dgi_n_est_jamais_inclusif_de_frais_hors_total_et_la_facturation_garde_l_idempotence(): void
    {
        $this->fauxEmecefSucces();
        $vente = $this->venteAFacturer(choix: ['facture_type' => 'normalisee', 'client_nom_facture' => 'N', 'aib_taux' => 'N/A']);
        $vente->update(['delivery_fee' => 2500]);   // drapeau faux : hors total

        $this->assertTrue(app(FacturationMecefService::class)->facturer($vente)['transmise']);
        Http::assertSent(fn (Request $q) => str_ends_with($q->url(), '/invoice') && json_decode($q->body(), true)['payment'][0]['amount'] === 11800);
    }
}
