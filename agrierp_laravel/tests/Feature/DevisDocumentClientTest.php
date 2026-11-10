<?php

namespace Tests\Feature;

use App\Livewire\Ventes\Devis;
use App\Models\Customer;
use App\Models\Quote;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * DEV-Q3 (DV-35) — le devis « document client » (A4) : le PDF se génère, porte tous ses éléments (en-tête de la ferme du gabarit commun, titre « Devis », numéro,
 * dates, validité, client, désignation, montants en FCFA entiers, « Bon pour accord »), sous le droit `export-ventes` ; un devis archivé ne s'imprime pas.
 */
class DevisDocumentClientTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolesAndPermissionsSeeder::class);
    }

    private function compte(string $role): User
    {
        $u = User::create(['name' => $role, 'username' => $role, 'email' => $role.'@fermeolouwachegoun.com', 'password' => bcrypt('LogiAgriERP@2026'), 'is_active' => true]);
        $u->assignRole($role);

        return $u;
    }

    private function devis(array $plus = []): Quote
    {
        $client = Customer::create(['name' => 'Awa KPOGNON', 'phone' => '97000000', 'city' => 'Porto-Novo', 'ifu' => '1234567890123', 'is_active' => true]);

        return Quote::create(array_merge([
            'quote_number' => 'DEV-2026-007', 'customer_id' => $client->id, 'articles_description' => "50 poulets de chair\nLivraison comprise", 'amount' => 100000,
            'tva_rate' => 18, 'validity_days' => 15, 'quote_date' => '2026-11-09', 'note' => 'Paiement à la commande', 'status' => 'brouillon', 'is_active' => true,
        ], $plus));
    }

    public function test_le_devis_porte_tous_ses_elements_dans_l_ordre(): void
    {
        $html = view('exports.devis-document', ['quote' => $this->devis()->load('customer')])->render();
        $texte = preg_replace('/\s+/', ' ', html_entity_decode(strip_tags(str_replace('<br />', ' ', $html))));
        $ordre = ['Devis DEV-2026-007', 'Client : Awa KPOGNON — 97000000 — Porto-Novo', 'IFU du client : 1234567890123', "Date d'émission : 09/11/2026", "Valable jusqu'au : 24/11/2026 (durée de validité : 15 jours)",
            'Désignation', 'Montant HT', '50 poulets de chair Livraison comprise', 'Montant HT : 100 000 FCFA', 'TVA (18 %) : 18 000 FCFA', 'Total TTC : 118 000 FCFA',
            'Observations : Paiement à la commande', 'Bon pour accord Date : ____ / ____ / ________', 'Signature du client :'];
        $dernier = -1;
        foreach ($ordre as $element) {
            $position = mb_strpos($texte, str_replace(' ', "\u{a0}", $element)) !== false ? mb_strpos($texte, str_replace(' ', "\u{a0}", $element)) : mb_strpos($texte, $element);
            $this->assertNotFalse($position, "absent du devis : « {$element} »");
            $this->assertGreaterThan($dernier, $position, "« {$element} » hors de l'ordre");
            $dernier = $position;
        }
    }

    public function test_les_montants_sont_des_entiers_tva_egale_ttc_moins_ht(): void
    {
        foreach ([[100000, 18, '100 000', '18 000', '118 000'], [12345, 18, '12 345', '2 222', '14 567'], [999.5, 0, '1 000', '0', '1 000'], [1000, 7.5, '1 000', '75', '1 075']] as [$ht, $taux, $h, $t, $c]) {
            $texte = html_entity_decode(strip_tags(view('exports.devis-document', ['quote' => $this->devis(['amount' => $ht, 'tva_rate' => $taux, 'quote_number' => 'DEV-2026-'.random_int(100, 999)])->load('customer')])->render()));
            $texte = str_replace("\u{a0}", ' ', preg_replace('/\s+/', ' ', $texte));
            $this->assertStringContainsString("Montant HT : {$h} FCFA", $texte, "HT {$ht}");
            $this->assertStringContainsString("{$t} FCFA", $texte, "TVA {$ht}/{$taux}");
            $this->assertStringContainsString("Total TTC : {$c} FCFA", $texte, "TTC {$ht}/{$taux}");
        }
    }

    public function test_le_pdf_se_genere_pour_le_comptable_et_le_caissier_pas_pour_l_animalier(): void
    {
        $devis = $this->devis();
        foreach (['comptable', 'caissier'] as $role) {
            Livewire::actingAs($this->compte($role))->test(Devis::class)->call('imprimerDevis', $devis->id)->assertFileDownloaded('devis-DEV-2026-007.pdf');
            User::query()->delete();
        }
        try {
            Livewire::actingAs($this->compte('animalier'))->test(Devis::class)->call('imprimerDevis', $devis->id)->assertForbidden();
        } catch (\Illuminate\Auth\Access\AuthorizationException|\Symfony\Component\HttpKernel\Exception\HttpException) {
            $this->addToAssertionCount(1);
        }
    }

    public function test_un_devis_archive_ne_s_imprime_pas(): void
    {
        $devis = $this->devis(['is_active' => false]);
        $this->expectException(\Illuminate\Database\Eloquent\ModelNotFoundException::class);
        $this->withoutExceptionHandling();
        Livewire::actingAs($this->compte('caissier'))->test(Devis::class)->call('imprimerDevis', $devis->id);
    }

    public function test_le_bouton_est_propose_a_qui_peut_exporter(): void
    {
        $this->devis();
        Livewire::actingAs($this->compte('comptable'))->test(Devis::class)->assertSee('Imprimer le devis');
        User::query()->delete();
        Livewire::actingAs($this->compte('caissier'))->test(Devis::class)->assertSee('Imprimer le devis');
    }
}
