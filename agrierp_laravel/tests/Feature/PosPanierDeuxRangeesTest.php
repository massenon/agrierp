<?php

namespace Tests\Feature;

use Tests\TestCase;

/**
 * Ticket #47 (suite, 27/10/2026) — le panier du POS web se range en DEUX rangées de deux colonnes
 * (Sous-total + Remise, puis Total à Payer + Mode de Règlement), et « Client » / « Date de la vente »
 * ne se touchent pas. Le défaut n'émet aucune erreur : on lit donc le Blade.
 */
class PosPanierDeuxRangeesTest extends TestCase
{
    private function source(): string
    {
        return file_get_contents(resource_path('views/livewire/ventes/pos-interface.blade.php'));
    }

    public function test_les_quatre_blocs_du_total_sont_dans_deux_grilles_de_deux_colonnes(): void
    {
        $b = $this->source();
        $debut = strpos($b, '>Sous-total</span>');
        $this->assertNotFalse($debut);
        $zone = substr($b, $debut - 200, 2600);

        $this->assertSame(2, substr_count($zone, 'grid grid-cols-2 gap-md'), 'deux rangées de deux colonnes');
        $this->assertGreaterThan(strpos($zone, '>Sous-total<'), strpos($zone, '>Remise (FCFA)<'));
        $this->assertGreaterThan(strpos($zone, '>Remise (FCFA)<'), strpos($zone, '>Total à Payer<'));
        $this->assertGreaterThan(strpos($zone, '>Total à Payer<'), strpos($zone, '>Mode de Règlement<'));
        // Remise et Sous-total dans la 1re grille ; Total et Mode dans la 2e.
        $deuxieme = strpos($zone, 'grid grid-cols-2 gap-md', strpos($zone, 'grid grid-cols-2 gap-md') + 5);
        $this->assertLessThan($deuxieme, strpos($zone, '>Remise (FCFA)<'));
        $this->assertGreaterThan($deuxieme, strpos($zone, '>Total à Payer<'));
        $this->assertGreaterThan($deuxieme, strpos($zone, '>Mode de Règlement<'));
    }

    public function test_client_et_date_ont_un_ecart_franc_et_peuvent_retrecir(): void
    {
        $b = $this->source();
        $this->assertStringContainsString('<div class="grid grid-cols-2 gap-md items-start">', $b);
        $this->assertStringContainsString('<select wire:model="customerId" class="flex-1 min-w-0', $b);
    }
}
