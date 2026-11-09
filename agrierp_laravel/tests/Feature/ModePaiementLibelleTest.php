<?php

namespace Tests\Feature;

use App\Models\TreasuryAccount;
use App\Support\ModePaiement;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Feature\Concerns\AvecEmecef;
use Tests\TestCase;

/**
 * Ticket CONF-3 (DV-22) — LE MODE DE RÈGLEMENT S'AFFICHE EN FRANÇAIS LISIBLE sur la facture (PDF) et l'historique des ventes.
 * La clé stockée ne change jamais ; l'unique point de passage est `App\Support\ModePaiement::libelle`.
 */
class ModePaiementLibelleTest extends TestCase
{
    use AvecEmecef;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->decorVentes();
        $this->reglerEmecef();
        TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse Principale', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);
    }

    public function test_libelles_connus_inconnus_et_vides(): void
    {
        $this->assertSame('Espèces', ModePaiement::libelle('especes'));
        $this->assertSame('Mobile Money', ModePaiement::libelle('mobile_money'));
        $this->assertSame('Virement bancaire', ModePaiement::libelle('virement'));
        $this->assertSame('Chèque', ModePaiement::libelle('cheque'));
        $this->assertSame('Crédit client', ModePaiement::libelle('credit'));
        $this->assertSame('Avance', ModePaiement::libelle('avance'));
        $this->assertSame('Carte bancaire', ModePaiement::libelle('carte_bancaire'), 'clé inconnue : la clé lisible, capitalisée');
        $this->assertSame('Moov', ModePaiement::libelle('moov'));
        foreach ([null, '', '   '] as $vide) {
            $this->assertSame('—', ModePaiement::libelle($vide), 'jamais une chaîne vide');
        }
        $this->assertSame('_', ModePaiement::libelle('_'));
    }

    public function test_la_facture_affiche_le_libelle_et_jamais_la_cle_brute(): void
    {
        foreach (['especes' => 'Espèces', 'virement' => 'Virement bancaire', 'mobile_money' => 'Mobile Money', 'credit' => 'Crédit client'] as $cle => $libelle) {
            $vente = $this->venteAFacturer(mode: $cle, choix: ['facture_type' => 'simple']);
            $html = view('exports.facture-vente', ['sale' => $vente->fresh()->load(['customer', 'lines.product'])])->render();

            $this->assertStringContainsString("Mode de règlement : {$libelle}", $html);
            $this->assertStringNotContainsString("Mode de règlement : {$cle}", $html);
            $this->assertSame($cle, $vente->fresh()->payment_mode, 'la clé stockée ne change jamais');
        }
    }

    public function test_une_cle_inconnue_est_capitalisee_sur_la_facture(): void
    {
        $vente = $this->venteAFacturer(mode: 'carte_bancaire', choix: ['facture_type' => 'simple']);
        $html = view('exports.facture-vente', ['sale' => $vente->fresh()->load(['customer', 'lines.product'])])->render();

        $this->assertStringContainsString('Mode de règlement : Carte bancaire', $html);
    }

    public function test_l_historique_des_ventes_utilise_le_meme_libelle(): void
    {
        $source = (string) file_get_contents(resource_path('views/livewire/ventes/historique-ventes.blade.php'));

        $this->assertStringContainsString('ModePaiement::libelle($sale->payment_mode)', $source);
        $this->assertStringContainsString('<option value="virement">Virement bancaire</option>', $source);
        $this->assertStringNotContainsString('$modeLabels', $source);
    }

    public function test_aucune_vue_n_affiche_la_cle_brute_du_mode_de_reglement(): void
    {
        // Garde de structure : aucune vue n'écrit `{{ $x->payment_mode }}` sans passer par le libellé.
        foreach (new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator(resource_path('views'))) as $fichier) {
            if (! str_ends_with((string) $fichier, '.blade.php')) {
                continue;
            }
            $this->assertDoesNotMatchRegularExpression('/\{\{\s*\$[\w>?-]*payment_mode\s*(\?\?[^}]*)?\}\}/', (string) file_get_contents((string) $fichier), "{$fichier} affiche la clé brute du mode de règlement");
        }
    }
}
