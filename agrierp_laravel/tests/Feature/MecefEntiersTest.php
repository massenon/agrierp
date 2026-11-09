<?php

namespace Tests\Feature;

use App\Models\Sale;
use App\Models\SaleLine;
use App\Services\Mecef\FacturationMecefService;
use App\Services\Mecef\MecefFactureBuilder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\Feature\Concerns\AvecEmecef;
use Tests\TestCase;

/**
 * Demande du client (07/11/2026) : PAS DE PRIX DÉCIMAL. Tout montant envoyé à la DGI (prix unitaire TTC, `originalPrice`,
 * règlement) est un ENTIER en FCFA, calculé par UNE fonction d'arrondi (`MecefFactureBuilder::arrondi`) ; la somme des lignes,
 * le total de la vente et le règlement sont égaux ; la quantité seule peut être décimale (2,5 kg).
 */
class MecefEntiersTest extends TestCase
{
    use AvecEmecef;
    use RefreshDatabase;

    private const EMETTEUR = ['ifu' => '3202601234567', 'operateur_id' => '7', 'operateur_nom' => 'Caissière Test'];

    protected function setUp(): void
    {
        parent::setUp();
        $this->decorVentes();
        $this->reglerEmecef();
    }

    /** @return array<string, mixed> */
    private function charge(Sale $vente): array
    {
        return app(MecefFactureBuilder::class)->pourVente($vente, self::EMETTEUR);
    }

    /**
     * Parcours RÉCURSIF d'un JSON : chemins des nombres à virgule. Seule la quantité (`quantity`) a le droit d'être décimale.
     *
     * @return array<int, string>
     */
    private function nombresADecimales(mixed $noeud, string $chemin = ''): array
    {
        if (is_array($noeud)) {
            $trouves = [];
            foreach ($noeud as $cle => $valeur) {
                $trouves = array_merge($trouves, $this->nombresADecimales($valeur, $chemin.'/'.$cle));
            }

            return $trouves;
        }

        return is_float($noeud) && ! str_ends_with($chemin, '/quantity') ? [$chemin.' = '.$noeud] : [];
    }

    /** Somme prix × quantité des lignes (en entiers : prix entier, quantité au millième). */
    private function sommeDesLignes(array $charge): int
    {
        return (int) round(array_sum(array_map(fn ($it) => $it['price'] * $it['quantity'], $charge['items'])));
    }

    private function assertToutEntierEtCoherent(array $charge, int $totalAttendu): void
    {
        $this->assertSame([], $this->nombresADecimales($charge), 'aucun nombre à virgule hors quantité');
        foreach ($charge['items'] as $it) {
            $this->assertIsInt($it['price']);
            $this->assertGreaterThan(0, $it['price']);
            if (isset($it['originalPrice'])) {
                $this->assertIsInt($it['originalPrice']);
            }
            // prix × quantité tombe JUSTE sur un entier (jamais un montant de ligne approximatif).
            $this->assertEqualsWithDelta(round($it['price'] * $it['quantity']), $it['price'] * $it['quantity'], 1e-9);
        }
        $this->assertSame($totalAttendu, $this->sommeDesLignes($charge), 'somme des lignes');
        $this->assertIsInt($charge['payment'][0]['amount']);
        $this->assertSame($totalAttendu, $charge['payment'][0]['amount'], 'règlement = somme des lignes');
        $this->assertCount(1, $charge['payment']);
    }

    public function test_quantite_decimale_prix_unitaire_entier_quand_la_division_tombe_juste(): void
    {
        // 2,5 kg de maïs pour 5 000 FCFA : 2 000 FCFA le kg, 2,5 × 2 000 = 5 000.
        $vente = $this->venteAFacturer([[$this->exonere, 2.5, 5000]]);

        $charge = $this->charge($vente);

        $this->assertSame(2000, $charge['items'][0]['price']);
        $this->assertSame(2.5, $charge['items'][0]['quantity']);
        $this->assertSame('Maïs brut', $charge['items'][0]['name']);
        $this->assertToutEntierEtCoherent($charge, 5000);
    }

    public function test_quantite_decimale_qui_ne_tombe_pas_juste_la_ligne_part_en_quantite_un(): void
    {
        // 2,5 kg pour 5 001 FCFA : pas de prix entier × 2,5 = 5 001 → ligne à quantité 1, quantité réelle dans le libellé.
        $vente = $this->venteAFacturer([[$this->exonere, 2.5, 5001]]);

        $charge = $this->charge($vente);

        $this->assertSame(5001, $charge['items'][0]['price']);
        $this->assertSame(1, $charge['items'][0]['quantity']);
        $this->assertSame('Maïs brut (2,5 kg)', $charge['items'][0]['name']);
        $this->assertToutEntierEtCoherent($charge, 5001);
    }

    public function test_quantite_entiere_dont_le_prix_n_est_pas_entier_part_aussi_en_quantite_un(): void
    {
        // 3 plaquettes pour 10 000 FCFA : 3 333,33 le prix unitaire → jamais envoyé ; quantité 1 à 10 000.
        $vente = $this->venteAFacturer([[$this->taxable, 3, 10000]]);

        $charge = $this->charge($vente);

        $this->assertSame([['name' => "Plaquette d'œufs (3 plaquette)", 'price' => 10000, 'quantity' => 1, 'taxGroup' => 'B']], $charge['items']);
        $this->assertToutEntierEtCoherent($charge, 10000);
    }

    public function test_remise_tva_et_melange_a_b_somme_exacte_et_entiers(): void
    {
        // 2 plaquettes à 18 % (11 800), 2,5 kg de maïs exonéré (5 000), 4 plaquettes à 18 % (20 000), remise 1 777.
        $vente = $this->venteAFacturer(
            [[$this->taxable, 2, 11800], [$this->exonere, 2.5, 5000], [$this->taxable, 4, 20000]],
            remise: 1777,
        );

        $charge = $this->charge($vente);

        $this->assertSame(['B', 'A', 'B'], array_column($charge['items'], 'taxGroup'));
        $this->assertToutEntierEtCoherent($charge, 11800 + 5000 + 20000 - 1777);
        $this->assertSame((int) $vente->total, $charge['payment'][0]['amount'], 'règlement = total de la vente');
        foreach ($charge['items'] as $it) {
            $this->assertSame('Remise', $it['priceModification']);
            $this->assertIsInt($it['originalPrice']);
        }
    }

    public function test_la_remise_est_repartie_par_le_plus_fort_reste_somme_exacte_et_deterministe(): void
    {
        // Trois lignes égales, remise 1 : une seule ligne la reçoit — la première (égalité de reste tranchée par l'ordre).
        $vente = $this->venteAFacturer([[$this->exonere, 1, 1000], [$this->exonere, 1, 1000], [$this->exonere, 1, 1000]], remise: 1);
        $charge = $this->charge($vente);

        $this->assertSame([999, 1000, 1000], array_column($charge['items'], 'price'));
        $this->assertToutEntierEtCoherent($charge, 2999);

        // Même vente, même résultat : déterministe.
        $this->assertSame($charge, $this->charge($vente->fresh('lines')));
    }

    public function test_l_ecart_d_arrondi_est_absorbe_par_la_plus_grande_ligne_jamais_envoye_tel_quel(): void
    {
        // Deux lignes à 1 000,40 : arrondies 1 000 + 1 000 = 2 000, mais la vente vaut 2 000,80 → 2 001. L'écart (+1) va à la 1re ligne.
        $vente = $this->venteAFacturer([[$this->exonere, 1, 1000], [$this->exonere, 1, 1000]]);
        SaleLine::where('sale_id', $vente->id)->update(['manual_total_amount' => 1000.40, 'unit_price' => 1000.40]);
        $vente->update(['subtotal' => 2000.80, 'total' => 2000.80]);

        $charge = $this->charge($vente->fresh('lines'));

        $this->assertSame([1001, 1000], array_column($charge['items'], 'price'));
        $this->assertToutEntierEtCoherent($charge, 2001);
        $this->assertSame(2001, MecefFactureBuilder::arrondi($vente->fresh()->total));
    }

    public function test_un_total_incoherent_avec_les_lignes_n_est_pas_un_arrondi_la_facture_est_refusee_sans_appel(): void
    {
        Http::fake();
        $vente = $this->venteAFacturer([[$this->exonere, 1, 2000]]);
        // Donnée fabriquée : le total annoncé n'a rien à voir avec les lignes (écart de 7 999 FCFA).
        \Illuminate\Support\Facades\DB::table('sales')->where('id', $vente->id)->update(['total' => 9999]);

        app(FacturationMecefService::class)->facturer($vente->id);

        $v = $vente->fresh();
        $this->assertSame('erreur', $v->mecef_status);
        $this->assertStringContainsString('Total de la vente (9999 FCFA) différent de la somme de ses lignes (2000 FCFA)', $v->mecef_message);
        Http::assertNothingSent();
    }

    public function test_ce_qui_part_vraiment_a_la_dgi_n_a_aucun_nombre_a_virgule_hors_quantite(): void
    {
        $this->fauxEmecefSucces();
        $vente = $this->venteAFacturer(
            [[$this->taxable, 3, 10000], [$this->exonere, 2.5, 5000], [$this->exonere, 2.5, 5001], [$this->taxable, 2, 11800]],
            remise: 1234, mode: 'mobile_money',
        );

        $this->assertTrue(app(FacturationMecefService::class)->facturer($vente)['transmise']);

        Http::assertSent(function (Request $q) use ($vente) {
            if (! str_ends_with($q->url(), '/invoice') || $q->method() !== 'POST') {
                return false;
            }

            // Le CORPS BRUT envoyé, relu : parcours récursif du JSON décodé ...
            $json = json_decode($q->body(), true, 512, JSON_PRESERVE_ZERO_FRACTION);
            $this->assertSame([], $this->nombresADecimales($json), 'aucun nombre à virgule hors quantité');
            // ... et sur le texte : une fois les chaînes et les quantités retirées, plus aucun « chiffre.chiffre ».
            $sansChaines = preg_replace('/"(?:[^"\\\\]|\\\\.)*"/', '""', (string) preg_replace('/"quantity":[0-9.]+/', '"quantity":0', $q->body()));
            $this->assertDoesNotMatchRegularExpression('/\d\.\d/', (string) $sansChaines);

            $total = (int) $vente->total;
            $this->assertSame($total, $json['payment'][0]['amount']);
            $this->assertSame($total, $this->sommeDesLignes($json));

            return true;
        });
    }

    public function test_avoir_en_entiers_prix_unitaire_entier_ou_quantite_un(): void
    {
        $vente = $this->venteAFacturer([[$this->taxable, 2, 11800]]);
        $vente->update(['mecef_uid' => 'uid-origine']);
        $avoir = \App\Models\CreditNote::create([
            'credit_note_number' => 'AV-2026-001', 'sale_id' => $vente->id, 'product_id' => $this->taxable->id,
            'qty' => 1, 'amount' => 5900.40, 'reason' => 'retour', 'decision' => 'reintegre', 'status' => 'traite',
        ]);

        $charge = app(MecefFactureBuilder::class)->pourAvoir($avoir, self::EMETTEUR);

        $this->assertSame('FA', $charge['type']);
        $this->assertSame(5900, $charge['items'][0]['price']);
        $this->assertSame(5900, $charge['payment'][0]['amount']);
        $this->assertSame([], $this->nombresADecimales($charge));
    }

    public function test_une_seule_fonction_d_arrondi_garde_des_sources(): void
    {
        $this->assertSame(1, MecefFactureBuilder::arrondi(0.5));
        $this->assertSame(2, MecefFactureBuilder::arrondi(1.5));
        $this->assertSame(5901, MecefFactureBuilder::arrondi('5900.5'));
        $this->assertSame(5900, MecefFactureBuilder::arrondi(5900.4));
        $this->assertSame(0, MecefFactureBuilder::arrondi(null));

        // Le constructeur n'arrondit ses MONTANTS qu'à un endroit (`arrondi()`) ; les autres `round(` sont la quantité (millièmes)
        // et le taux de TVA. La passerelle et le service de facturation n'arrondissent rien.
        $constructeur = (string) file_get_contents(app_path('Services/Mecef/MecefFactureBuilder.php'));
        $code = preg_replace('#/\*.*?\*/#s', '', $constructeur);
        $code = preg_replace('#^\s*//.*$#m', '', (string) $code);
        preg_match_all('/\bround\(([^;]*)\)/', (string) $code, $m);
        $this->assertCount(3, $m[0], 'arrondi() (montants), millièmes de la quantité, taux de TVA de la livraison : '.implode(' | ', $m[0]));
        foreach (['EmecefGateway', 'FacturationMecefService'] as $fichier) {
            $this->assertStringNotContainsString('round(', (string) file_get_contents(app_path('Services/Mecef/'.$fichier.'.php')), $fichier.' n\'arrondit aucun montant');
        }
    }
}
