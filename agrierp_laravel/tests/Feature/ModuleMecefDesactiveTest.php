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

    public function test_le_menu_et_la_page_disent_le_module_desactive(): void
    {
        config(['mecef.actif' => false]);
        $this->assertStringContainsString('config(\'mecef.actif\')', file_get_contents(resource_path('views/layouts/app.blade.php')));

        $html = view('livewire.facturation.module-desactive')->render();
        $this->assertStringContainsString('Module MeCeF désactivé', $html);
    }
}
