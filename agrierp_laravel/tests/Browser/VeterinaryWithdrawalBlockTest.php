<?php

namespace Tests\Browser;

use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Product;
use App\Models\User;
use App\Models\VeterinaryWithdrawalPeriod;
use Illuminate\Foundation\Testing\DatabaseMigrations;
use Laravel\Dusk\Browser;
use Tests\DuskTestCase;

/**
 * Ticket 13.1 — Parcours critique 3/8 (Document 07 §4) : Vente bloquée
 * par rémanence. Tentative de vente sur un lot sous rémanence vétérinaire
 * active → blocage effectif avec message explicite, pas seulement un
 * avertissement visuel contournable.
 *
 * Bloqué par `VeterinaryWithdrawalPeriod::isLotBlocked()`, vérifié côté
 * serveur dans `PosInterface::confirmWeightAdd()` (ticket 3.11).
 *
 * ⚠️ Le sélecteur de lot (`weightLotId`) n'est affiché dans la modale de
 * confirmation que pour un produit réellement lié à une espèce d'élevage
 * (pesée sur pied) — ce test sélectionne délibérément un produit de
 * catégorie aviculture pour garantir que ce champ est bien présent,
 * plutôt que de deviner un sélecteur générique qui pourrait cibler un
 * produit sans lot associé.
 */
class VeterinaryWithdrawalBlockTest extends DuskTestCase
{
    use DatabaseMigrations;

    public function test_sale_is_blocked_for_lot_under_active_withdrawal_period(): void
    {
        $this->seed();
        $cashier = User::where('email', 'caisse@fermeolouwachegoun.com')->firstOrFail();

        $species = LivestockSpecies::where('code', 'aviculture')->firstOrFail();
        $product = Product::where('species_id', $species->id)->where('is_active', true)->firstOrFail();

        $lot = LivestockLot::create([
            'code' => 'LOT-TEST-REMANENCE',
            'species_id' => $species->id,
            'stage' => 'engraissement',
            'initial_quantity' => 50,
            'current_quantity' => 45,
            'created_date' => now()->subWeeks(6),
            'status' => 'actif',
            'is_active' => true,
        ]);

        VeterinaryWithdrawalPeriod::create([
            'lot_id' => $lot->id,
            'product_used' => 'Antibiotique Test',
            'start_date' => now()->subDays(2),
            'withdrawal_days' => 14,
            'end_date' => now()->addDays(12),
        ]);

        $this->browse(function (Browser $browser) use ($cashier, $product, $lot) {
            $browser->loginAs($cashier)
                ->visit('/ventes-devis?tab=vente')
                ->waitForText($product->name, 10)
                ->click('button[wire\\:click="selectProduct(\''.$product->id.'\')"]')
                // ⚠️ Selecteurs `dusk` (ticket 14.28) : `weightLotId` et `weightQty`
                // ne sont que des `wire:model`, ni `name` ni `id` — Selenium
                // cherchait litteralement « body weightLotId ». Parcours ecrit
                // sans avoir jamais ete execute, comme les 4 autres.
                // ⚠️ On attend l'ELEMENT, jamais son libelle : la classe
                // `uppercase` fait lire « BANDE SOURCE * » a Selenium, qui voit
                // le texte REELLEMENT RENDU. Meme piege qu'au ticket 14.19.
                ->waitFor('@weight-lot', 5)
                ->select('@weight-lot', $lot->id)
                ->type('@weight-qty', '1')
                // ⚠️ Le MONTANT est obligatoire et valide AVANT le controle de
                // remanence : sans lui la validation echoue, le blocage veterinaire
                // n'est jamais atteint et le test passerait pour une mauvaise raison.
                ->type('@weight-price', '5000')
                ->press('@weight-confirm')
                ->waitForText('interdite', 10)
                // Message explicite, pas un simple style visuel discret —
                // ET le panier reste réellement vide (texte affiché quand
                // aucune ligne n'a été ajoutée, cf. pos-interface.blade.php).
                ->assertSee('interdite')
                ->assertSee($lot->code)
                ->assertSee('Le panier est vide');
        });
    }
}
