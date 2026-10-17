<?php

namespace Tests\Browser;

use App\Models\AccountingEntry;
use App\Models\Product;
use App\Models\Sale;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseMigrations;
use Laravel\Dusk\Browser;
use Tests\DuskTestCase;

/**
 * Ticket 13.1 — Parcours critique 2/8 (Document 07 §4) : Vente POS complète.
 * Sélection produit → modale Vente à la Pièce → confirmation → ligne au panier
 * avec le bon montant → encaissement → écriture comptable générée → stock
 * décrémenté.
 *
 * 🔴→✅ TICKET 14.28 — PARCOURS RÉELLEMENT EXÉCUTÉ POUR LA PREMIÈRE FOIS.
 *
 * Il avait été écrit sans jamais tourner, et trois de ses gestes ne pouvaient
 * pas fonctionner :
 *   - `type('weightQty', '1')` : `weightQty` n'est qu'un `wire:model`, ni un
 *     `name` ni un `id`. Selenium cherchait littéralement `body weightQty`.
 *   - `press('Ajouter au panier')` puis `press('Encaisser')` : le bouton de
 *     validation s'intitule en réalité « Valider la Vente ».
 *   - le champ **Montant Global** n'était jamais rempli, alors que
 *     `confirmWeightAdd()` le valide comme obligatoire.
 * Sélecteurs `dusk` posés sur les 4 commandes du parcours — même correction
 * qu'au ticket 14.19 pour la connexion.
 *
 * 🔴→✅ ET SURTOUT : le dernier maillon du parcours est enfin vérifiable. Ce
 * fichier documentait que « écriture comptable générée » N'ÉTAIT PAS
 * vérifiable, le rétro-câblage du POS vers `AccountingEntryService` restant
 * différé depuis le ticket 10.2. Ce câblage a été fait au ticket 14.23 :
 * l'assertion manquante est donc posée ici, et le parcours est vérifié de bout
 * en bout comme le Document 07 le décrit.
 */
class PosSaleTest extends DuskTestCase
{
    use DatabaseMigrations;

    public function test_full_pos_sale_decrements_stock_with_manual_amount_confirmation(): void
    {
        $this->seed();
        $cashier = User::where('email', 'caisse@olouwachegoun.bj')->firstOrFail();

        // ⚠️ Produit SANS espèce liée : un sujet vivant exigerait en plus la
        // sélection d'une bande source (contrôle de rémanence vétérinaire,
        // ticket 14.21). Ce parcours-ci vérifie la vente ordinaire ; le blocage
        // de rémanence a son propre parcours dédié.
        // ⚠️ SELECTION ENTIEREMENT DETERMINISTE. Sans `orderBy`, MySQL ne
        // garantit aucun ordre : le parcours tombait tantot sur un produit
        // vendable, tantot sur un produit en `pricing_mode = 'quote'` — que
        // `selectProduct()` redirige vers les Devis au lieu d'ouvrir la modale.
        // Un test qui change de sujet a chaque execution n'atteste de rien.
        $product = Product::where('is_active', true)
            ->whereNull('species_id')
            ->where('pricing_mode', 'fourchette')
            ->where('stock_qty', '>', 5)
            ->orderBy('sku')
            ->firstOrFail();

        $stockAvant = (float) $product->stock_qty;

        $this->browse(function (Browser $browser) use ($cashier, $product) {
            $browser->loginAs($cashier)
                ->visit('/ventes-devis?tab=vente')
                ->waitForText($product->name, 10)
                // Sélection produit — doit TOUJOURS ouvrir la modale de
                // confirmation (Document 01 §6.7, vente à la pièce généralisée),
                // jamais un ajout direct au panier.
                ->click('button[wire\\:click="selectProduct(\''.$product->id.'\')"]')
                ->waitForText('Vente à la Pièce', 5)
                ->type('@weight-qty', '2')
                // Montant GLOBAL convenu, jamais un prix unitaire multiplié
                // automatiquement à l'insu du vendeur.
                ->type('@weight-price', '8000')
                ->press('@weight-confirm')
                // ⚠️ ON ATTEND LA FERMETURE DE LA MODALE, pas un montant.
                //
                // Le test attendait le texte « 8 000 » pour conclure que la
                // ligne était au panier. Ce montant est devenu ambigu au ticket
                // 14.36 : la grille produits affiche désormais « Aliment
                // porcelet — 8 000 - 9 000 FCFA ». L'attente était donc
                // satisfaite par le CATALOGUE, et le test repartait pendant que
                // la modale était encore ouverte — son fond interceptait
                // ensuite le clic de validation.
                //
                // La disparition du titre de la modale est une condition sans
                // ambiguïté : elle ne peut être satisfaite que par la fermeture
                // réelle, donc par un ajout au panier réussi.
                ->waitUntilMissingText('Vente à la Pièce', 10)
                ->assertSee($product->name)
                // ⚠️ DEUX OBSTACLES REELS, constates en executant le parcours :
                //  1. le bouton de validation est en bas d'un panneau de panier
                //     defilant — sans recentrage, Selenium clique sur le conteneur
                //     qui le recouvre (« element click intercepted ») ;
                //  2. le toast « ajoute au panier » (fixe, bas-droite, z-200)
                //     RECOUVRE ce meme bouton pendant ses 3,5 s d'affichage.
                //     Chevauchement reel de l'interface, signale au ticket 14.28 :
                //     transitoire pour un utilisateur, bloquant pour un clic
                //     automatise. CORRIGE DANS L'APPLICATION (`pointer-events-none`
                //     sur le conteneur de toasts) plutot que contourne ici.
                ->scrollIntoView('@validate-sale')
                ->press('@validate-sale')
                // Libelle repris TEL QU'IL EST REELLEMENT RENDU (sans accent dans
                // le toast de l'application) — jamais une reecriture supposee.
                ->waitForText('Vente enregistree avec succes', 10);
        });

        // Le stock est réellement décrémenté de la quantité vendue.
        $product->refresh();
        $this->assertEquals(
            $stockAvant - 2,
            (float) $product->stock_qty,
            'Le stock doit être réellement décrémenté après la vente (AdjustStockAction, ticket 6.1).'
        );

        // La vente est enregistrée au montant EXACTEMENT confirmé.
        $sale = Sale::latest()->firstOrFail();
        $this->assertEquals(8_000, (float) $sale->total, 'Le montant global confirmé prime sur tout calcul unitaire.');

        // Dernier maillon du parcours, verifiable depuis le ticket 14.23.
        $this->assertNotNull($sale->accounting_entry_id, 'La vente doit generer son ecriture comptable.');

        $ecriture = AccountingEntry::with('lines.account')->findOrFail($sale->accounting_entry_id);
        $this->assertEquals($ecriture->total_debit, $ecriture->total_credit, "L'ecriture generee doit etre equilibree.");
        $this->assertTrue(
            $ecriture->lines->contains(fn ($l) => $l->account->code === '701'),
            'Le chiffre d affaires doit etre credite au compte 701.'
        );
    }
}
