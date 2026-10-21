<?php

namespace Tests\Feature;

use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\StockMovement;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 14.67 (Sprint 14) — L'ÉCART D'INVENTAIRE CONSTATÉ HORS LIGNE.
 *
 * ⚠️⚠️ CE QUE CES TESTS PROTÈGENT. Le CDC exige que « toute opération
 * financière (vente, achat, paie, **perte**) déclenche automatiquement la
 * génération de l'écriture ». L'écran web le fait depuis le ticket 14.41 ; le
 * chemin de synchronisation, non.
 *
 * Un manquant d'inventaire saisi sur un poste hors ligne faisait donc baisser le
 * stock **sans jamais réduire le résultat** — quatrième occurrence du même
 * défaut, après les ventes (14.52), la ponte (14.59) et les dépenses (14.62).
 */
class SyncEcartInventaireTest extends TestCase
{
    use RefreshDatabase;

    private Product $produit;

    private User $utilisateur;

    protected function setUp(): void
    {
        parent::setUp();

        $this->utilisateur = User::create([
            'name' => 'Animalier', 'username' => 'elevage',
            'email' => 'elevage@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);

        // Ticket S1 : l'envoi du poste exige désormais le rôle qui écrit chaque table.

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);

        $this->utilisateur->assignRole('admin');

        FiscalYear::create([
            'year' => (int) now()->format('Y'),
            'start_date' => now()->startOfYear()->toDateString(),
            'end_date' => now()->endOfYear()->toDateString(),
            'status' => 'ouvert',
        ]);

        foreach ([['601', "Achats d'aliments", 6], ['657', 'Pertes sur stocks', 6]] as [$code, $libelle, $classe]) {
            ChartOfAccount::firstOrCreate(
                ['code' => $code],
                ['label' => $libelle, 'class' => $classe, 'is_active' => true],
            );
        }

        $categorie = new ProductCategory();
        $categorie->id = '11111111-1111-4111-8111-111111111111';
        $categorie->label = 'Aliments';
        $categorie->is_active = true;
        $categorie->save();

        $this->produit = Product::create([
            'sku' => 'ALI-001', 'name' => 'Provende ponte',
            'category_id' => $categorie->id, 'unit' => 'sac',
            'pricing_mode' => 'fourchette', 'tva_rate' => 0,
            'stock_qty' => 100, 'is_active' => true,
        ]);

        // ⚠️ LE PMP SE CALCULE SUR LES LIGNES D'ACHAT, pas sur les mouvements
        // de stock (`Product::computePmp()` : `stock_movements` ne porte aucun
        // cout). Sans achat valorise, l'Action refuse de valoriser la perte —
        // c'est son garde-fou, pas un echec du test.
        $fournisseur = \App\Models\Supplier::create([
            'name' => 'Provenderie du Sud', 'phone' => '97000010', 'is_active' => true,
        ]);

        $achat = \App\Models\Purchase::create([
            'supplier_id' => $fournisseur->id,
            'payment_mode' => 'especes',
            'total' => 1800000,
            'purchase_date' => now()->subDays(10)->toDateString(),
        ]);

        \App\Models\PurchaseLine::create([
            'purchase_id' => $achat->id,
            'product_id' => $this->produit->id,
            'qty' => 100,
            'unit_price' => 18000,
        ]);
    }

    private function pousser(string $type, float $quantite): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($this->utilisateur, 'sanctum')->postJson('/api/sync/push', [
            'stock_adjustments' => [[
                'client_ref' => 'ajust-1',
                'product_id' => $this->produit->id,
                'type' => $type,
                'quantity' => $quantite,
                'reference_type' => 'adjustment',
                'reason' => 'Inventaire physique du mois',
            ]],
        ]);
    }

    /**
     * ⚠️⚠️ LE TEST QUI COMPTE : un manquant poussé depuis un poste réduit le
     * stock ET le résultat.
     */
    public function test_a_pushed_shortfall_posts_its_accounting_entry(): void
    {
        $reponse = $this->pousser('sortie', 5);

        $reponse->assertOk();
        $reponse->assertJsonPath('stock_adjustments.accepted.0', 'ajust-1');

        // Effet 1 — le stock a baissé.
        $this->assertEquals(95.0, (float) $this->produit->fresh()->stock_qty);

        // Effet 2 — la perte est passée au journal, valorisée au PMP.
        $ecriture = AccountingEntry::with('lines')->first();
        $this->assertNotNull($ecriture,
            'une perte qui ne reduit pas le resultat ne se voit qu a l inventaire suivant');

        $debits = $ecriture->lines->sum('debit');
        $credits = $ecriture->lines->sum('credit');

        $this->assertEquals($debits, $credits, 'SUM(debit) = SUM(credit)');
        // 5 sacs × 18 000 F de PMP.
        $this->assertEquals(90000.0, (float) $debits);
    }

    /**
     * ⚠️⚠️ UN EXCÉDENT N'EST PAS UN PROFIT. C'est le signe d'une entrée non
     * saisie : régularisé en stock, jamais inscrit au résultat. Le garde-fou
     * vit dans l'Action et doit tenir aussi sur ce chemin.
     */
    public function test_a_surplus_adjusts_the_stock_but_posts_nothing(): void
    {
        $this->pousser('entree', 5)->assertOk();

        $this->assertEquals(105.0, (float) $this->produit->fresh()->stock_qty);
        $this->assertEquals(0, AccountingEntry::count(),
            'inscrire un excedent au resultat inventerait un gain');
    }

    /**
     * ⚠️ SANS PMP, AUCUNE ÉCRITURE — plutôt qu'une perte valorisée au hasard.
     * Le stock est tout de même corrigé : la correction physique ne dépend pas
     * de la valorisation.
     */
    public function test_without_a_weighted_cost_no_entry_is_invented(): void
    {
        \App\Models\PurchaseLine::query()->delete();

        $this->pousser('sortie', 5)->assertOk();

        $this->assertEquals(95.0, (float) $this->produit->fresh()->stock_qty);
        $this->assertEquals(0, AccountingEntry::count());
    }

    /**
     * 🔴→✅ TICKET 14.74 — LE RENVOI NE REJOUE PLUS L'AJUSTEMENT.
     *
     * ⚠️⚠️ CE CANAL ACQUITTAIT AVEC LE `product_id` quand `client_ref`
     * manquait — et le client Flutter, lui, envoyait `id`, jamais
     * `client_ref`. Le poste ne se reconnaissait donc pas dans l'accuse de
     * reception, laissait l'ajustement EN ATTENTE et le renvoyait a chaque
     * synchronisation. Chaque renvoi rejouait le decrement de stock ET passait
     * une nouvelle ecriture de perte : un manquant de 5 sacs constate UNE fois
     * en retirait 5 de plus a chaque tirage, indefiniment.
     *
     * Le defaut n'avait jamais tire a blanc parce qu'AUCUN ecran du poste ne
     * creait d'ajustement — comble au ticket F0.38, ce qui l'a fait
     * apparaitre.
     */
    public function test_a_resent_adjustment_is_not_replayed(): void
    {
        $avant = (float) $this->produit->fresh()->stock_qty;

        $this->pousser('sortie', 5)->assertOk();
        $apresPremier = (float) $this->produit->fresh()->stock_qty;

        $reponse = $this->pousser('sortie', 5);

        $reponse->assertOk();
        $reponse->assertJsonPath('stock_adjustments.accepted.0', 'ajust-1');

        $this->assertEquals(
            $apresPremier,
            (float) $this->produit->fresh()->stock_qty,
            'le renvoi ne doit RIEN retirer de plus',
        );
        $this->assertNotEquals($avant, $apresPremier, 'le premier envoi, lui, a bien agi');
    }

    /**
     * ⚠️ L'ACCUSE PORTE L'IDENTIFIANT DE LA LIGNE DU POSTE, jamais celui du
     * produit : deux ajustements sur le meme produit auraient porte le meme
     * accuse, et le poste en aurait acquitte un pour l'autre.
     */
    public function test_the_acknowledgement_carries_the_client_reference(): void
    {
        $this->pousser('sortie', 5)
            ->assertOk()
            ->assertJsonPath('stock_adjustments.accepted.0', 'ajust-1');
    }
}
