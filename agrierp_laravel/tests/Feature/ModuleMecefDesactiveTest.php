<?php

namespace Tests\Feature;

use App\Models\Sale;
use App\Services\Mecef\FacturationMecefService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket VC-5 — le module MeCeF est DÉSACTIVÉ jusqu'à sa configuration : aucun appel au dispositif, aucune alerte.
 */
class ModuleMecefDesactiveTest extends TestCase
{
    use RefreshDatabase;

    public function test_le_service_ne_transmet_rien_et_ne_touche_pas_la_vente_quand_le_module_est_desactive(): void
    {
        config(['mecef.actif' => false]);

        $resultat = app(FacturationMecefService::class)->facturer((string) \Illuminate\Support\Str::uuid());

        $this->assertSame(['transmise' => false, 'deja' => false, 'inactif' => true, 'message' => 'module MeCeF désactivé'], $resultat);
        $this->assertSame(0, Sale::count());
    }

    public function test_le_defaut_de_la_configuration_est_desactive_et_les_tests_l_activent(): void
    {
        $this->assertTrue((bool) config('mecef.actif'), 'phpunit.xml active le module pour couvrir son circuit');
        $this->assertStringContainsString("env('MECEF_ACTIF', false)", file_get_contents(config_path('mecef.php')));
    }

    public function test_la_facturation_reste_disponible_sans_mecef_et_sans_colonne_ni_geste_mecef(): void
    {
        config(['mecef.actif' => false]);
        \App\Models\Permission::findOrCreate('view-facturation', 'web');
        \App\Models\Permission::findOrCreate('manage-facturation', 'web');
        $u = \App\Models\User::create(['name' => 'Admin', 'username' => 'admin', 'email' => 'a@x.bj', 'password' => bcrypt('x'), 'is_active' => true]);
        $u->givePermissionTo(['view-facturation', 'manage-facturation']);

        $client = \App\Models\Customer::create(['name' => 'AMOUSSOU Régis', 'is_active' => true]);
        $vente = Sale::create(['customer_id' => $client->id, 'payment_mode' => 'especes', 'subtotal' => 5000, 'discount' => 0, 'total' => 5000, 'status' => 'validee']);

        \Livewire\Livewire::actingAs($u)->test(\App\Livewire\Facturation\Facturation::class)
            ->assertSee('Registre des factures de vente')
            ->assertSee('Montant facturé (mois)')
            ->assertSee($vente->numero_facture)
            ->assertDontSee('Statut MeCeF')
            ->assertDontSee('Transmises MeCeF')
            ->call('retryMecef', $vente->id)
            ->assertDispatched('toast');

        config(['mecef.actif' => true]);
        \Livewire\Livewire::actingAs($u)->test(\App\Livewire\Facturation\Facturation::class)
            ->assertSee('Statut MeCeF')
            ->assertSee('Transmises MeCeF');
    }

    public function test_la_facture_pdf_se_rend_avec_ou_sans_certification(): void
    {
        $client = \App\Models\Customer::create(['name' => 'GBAGUIDI Solange', 'is_active' => true]);
        $vente = Sale::create(['customer_id' => $client->id, 'payment_mode' => 'especes', 'subtotal' => 8000, 'discount' => 0, 'total' => 8000, 'status' => 'validee']);

        $html = view('exports.facture-vente', ['sale' => $vente->load(['customer', 'lines.product'])])->render();
        $this->assertStringContainsString($vente->numero_facture, $html);
        $this->assertStringContainsString('Facture émise sans certification MeCeF.', $html);

        $vente->update(['mecef_status' => 'transmise', 'mecef_qr_ref' => 'REF-123']);
        $html = view('exports.facture-vente', ['sale' => $vente->fresh()->load(['customer', 'lines.product'])])->render();
        $this->assertStringContainsString('référence : REF-123', $html);
    }

    public function test_le_tirage_dit_au_poste_si_le_module_mecef_est_active(): void
    {
        \App\Models\Permission::findOrCreate('view-ventes', 'web');
        $u = \App\Models\User::create(['name' => 'Caisse', 'username' => 'caisse', 'email' => 'c@x.bj', 'password' => bcrypt('x'), 'is_active' => true]);
        $u->givePermissionTo('view-ventes');
        \App\Models\CompanySetting::current()->update(['company_name' => 'Ferme']);

        config(['mecef.actif' => false]);
        $this->actingAs($u, 'sanctum')->getJson('/api/sync/pull')->assertOk()->assertJsonPath('company_settings.mecef_actif', false);

        config(['mecef.actif' => true]);
        $this->actingAs($u, 'sanctum')->getJson('/api/sync/pull')->assertOk()->assertJsonPath('company_settings.mecef_actif', true);
    }
}
