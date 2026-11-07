<?php

namespace Tests\Feature;

use App\Services\Mecef\ChargeBoitierEltrade;
use App\Services\Mecef\MecefFactureBuilder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Feature\Concerns\AvecEmecef;
use Tests\TestCase;

/**
 * CONF-2 — la couche de traduction vers le boîtier Eltrade CC300 (`bill.spec.json`) : elle renomme, elle ne recalcule pas ;
 * le dossier `presentation/` (spécimens) est généré par le VRAI code sur une base en mémoire, jamais sur la base de développement.
 */
class MecefChargeBoitierTest extends TestCase
{
    use AvecEmecef;
    use RefreshDatabase;

    private const EMETTEUR = ['ifu' => '3202601234567', 'operateur_id' => '1', 'operateur_nom' => 'Caissier'];

    protected function setUp(): void
    {
        parent::setUp();
        $this->decorVentes();
        $this->reglerEmecef();
    }

    public function test_la_charge_respecte_le_schema_du_pilote_et_les_montants_du_constructeur_unique(): void
    {
        $vente = $this->venteAFacturer([[$this->taxable, 2.5, 7000], [$this->exonere, 10, 2000]], 1000, 'mobile_money', ['facture_type' => 'normalisee', 'client_nom_facture' => 'Client Test', 'client_ifu' => '8888888888888', 'aib_taux' => '5%']);
        $enLigne = (new MecefFactureBuilder)->pourVente($vente, self::EMETTEUR);

        $charge = (new ChargeBoitierEltrade)->depuisChargeEnLigne($enLigne, 'V1', str_repeat('N', 40));

        $this->assertSame('FV', $charge['vt']);
        $this->assertSame('V1', $charge['seller_id']);
        $this->assertSame(ChargeBoitierEltrade::VENDEUR_MAX, mb_strlen($charge['seller_name']));
        $this->assertSame('8888888888888', $charge['buyer_ifu']);
        $this->assertSame('Client Test', $charge['buyer_name']);
        $this->assertSame('5%', $charge['aib']);
        $this->assertSame([['mode' => 'M', 'amount' => $enLigne['payment'][0]['amount']]], $charge['payments']);
        $this->assertCount(count($enLigne['items']), $charge['products']);

        $somme = 0;
        foreach ($charge['products'] as $i => $p) {
            $this->assertContains($p['tax'], ['A', 'B']);
            $this->assertIsInt($p['price'], 'prix entier, jamais décimal');
            $this->assertLessThanOrEqual(60, mb_strlen($p['label']));
            $this->assertSame($enLigne['items'][$i]['price'], $p['price'], 'aucun recalcul : le prix est celui du constructeur');
            $somme += $p['price'] * $p['items'];
        }
        $this->assertSame((int) $charge['payments'][0]['amount'], (int) round($somme), 'règlement = somme des lignes');
    }

    public function test_les_valeurs_d_aib_et_de_mode_sont_celles_de_l_enumeration_du_pilote(): void
    {
        foreach (['5%' => '5%', '1%' => '1%', 'N/A' => 'N/A'] as $taux => $attendu) {
            $vente = $this->venteAFacturer([], 0, 'especes', ['facture_type' => 'normalisee', 'client_nom_facture' => 'X '.$taux, 'aib_taux' => $taux]);
            $charge = (new ChargeBoitierEltrade)->depuisChargeEnLigne((new MecefFactureBuilder)->pourVente($vente, self::EMETTEUR), 'V', 'Vendeur');
            $this->assertSame($attendu, $charge['aib']);
            $this->assertSame('E', $charge['payments'][0]['mode']);
            $this->assertArrayNotHasKey('buyer_ifu', $charge, 'client sans IFU : champ omis');
        }
    }

    public function test_une_remise_donne_prix_d_origine_et_explication_du_boitier(): void
    {
        $vente = $this->venteAFacturer([[$this->taxable, 2, 11800]], 1800);
        $charge = (new ChargeBoitierEltrade)->depuisChargeEnLigne((new MecefFactureBuilder)->pourVente($vente, self::EMETTEUR), 'V', 'Vendeur');

        $this->assertArrayHasKey('original_price', $charge['products'][0]);
        $this->assertSame('Remise', $charge['products'][0]['price_change_explanation']);
        $this->assertLessThanOrEqual(24, mb_strlen($charge['products'][0]['price_change_explanation']));
    }

    public function test_le_script_de_presentation_ne_touche_jamais_la_base_de_developpement(): void
    {
        $source = (string) file_get_contents(base_path('../presentation/generer.php'));

        $this->assertStringContainsString("'DB_DATABASE' => ':memory:'", $source);
        $this->assertStringContainsString("getDatabaseName() !== ':memory:'", $source, 'refus si la connexion n\'est pas en mémoire');
        $this->assertStringNotContainsString('migrate:fresh', $source);
        $this->assertStringNotContainsString('Http::', $source, 'aucun appel réseau');
    }

    public function test_le_json_de_presentation_est_conforme_au_schema_du_pilote(): void
    {
        $chemin = base_path('../presentation/ticket_essai_mecef.json');
        $this->assertFileExists($chemin);
        $charge = json_decode((string) file_get_contents($chemin), true, flags: JSON_THROW_ON_ERROR);

        foreach (['vt', 'seller_id', 'seller_name', 'payments', 'products'] as $cle) {
            $this->assertArrayHasKey($cle, $charge);
        }
        $this->assertLessThanOrEqual(30, mb_strlen($charge['seller_name']));
        $this->assertContains($charge['aib'], ['1%', '5%', 'N/A']);
        foreach ($charge['products'] as $p) {
            $this->assertIsInt($p['price']);
            $this->assertContains($p['tax'], ['A', 'B', 'C', 'D', 'E', 'F']);
        }
    }
}
