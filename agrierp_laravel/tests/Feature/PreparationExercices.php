<?php

namespace Tests\Feature;

use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Purchase;
use App\Models\PurchaseLine;
use App\Models\StockMovement;
use App\Models\Supplier;
use App\Models\TreasuryAccount;
use App\Models\User;
use Carbon\Carbon;
use Database\Seeders\RolesAndPermissionsSeeder;

/**
 * Tickets EX3 à EX5 (PRD `docs/prd/exercices-comptables.md`) — décor commun aux quatre classes de test de la bascule
 * d'exercice : rôles réels du seeder, un administrateur connecté (web) et appairé (jeton d'un poste), le plan comptable
 * des flux touchés, une caisse, un produit avec un coût d'achat connu (PMP), une bande de pondeuses.
 *
 * ⚠️ Toute date est FIGÉE (`Carbon::setTestNow`) par le test lui-même : aucun test ne dépend du jour où la suite tourne.
 * Les montants attendus sont calculés à la main dans chaque test, jamais relus du code testé.
 */
trait PreparationExercices
{
    protected User $admin;

    protected string $jeton = '';

    protected Product $mais;

    protected Product $oeufs;

    protected LivestockLot $pondeuses;

    protected TreasuryAccount $caisse;

    /** @var array<string, ChartOfAccount> */
    protected array $comptes = [];

    protected function preparerDecor(string $maintenant): void
    {
        Carbon::setTestNow(Carbon::parse($maintenant, 'Africa/Porto-Novo'));

        $this->seed(RolesAndPermissionsSeeder::class);

        $this->admin = User::create([
            'name' => 'Direction', 'username' => 'admin-ex', 'email' => 'admin-ex@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->admin->assignRole('admin');
        $this->actingAs($this->admin);

        foreach ([
            ['101', 'Capital', 1], ['131', 'Résultat net : bénéfice', 1], ['139', 'Résultat net : perte', 1],
            ['401', 'Fournisseurs', 4], ['411', 'Clients', 4], ['422', 'Personnel, rémunérations dues', 4],
            ['431', 'Sécurité sociale (CNSS)', 4], ['443', 'TVA facturée', 4],
            ['4472', 'Impôt sur les traitements et salaires (ITS)', 4], ['4473', 'Versement patronal sur salaires (VPS)', 4],
            ['521101', 'Banque - Compte principal', 5], ['531', 'Caisse', 5],
            ['601', 'Achats de marchandises', 6], ['605', 'Énergie', 6], ['657', 'Charges exceptionnelles', 6],
            ['661', 'Charges de personnel', 6], ['664', 'Charges sociales patronales', 6],
            ['701', 'Ventes de produits', 7],
        ] as [$code, $libelle, $classe]) {
            $this->comptes[$code] = ChartOfAccount::create([
                'code' => $code, 'label' => $libelle, 'class' => $classe, 'is_active' => true,
            ]);
        }

        $this->caisse = TreasuryAccount::create([
            'type' => 'caisse', 'label' => 'Caisse Principale', 'account_code' => '531',
            'balance' => 5_000_000, 'is_active' => true,
        ]);

        $espece = LivestockSpecies::create(['code' => 'aviculture', 'label' => 'Volailles', 'is_enabled' => true, 'is_active' => true]);
        $categorie = ProductCategory::create(['label' => 'Provende', 'is_active' => true]);

        $this->mais = Product::create([
            'sku' => 'MAIS-50', 'name' => 'Maïs grain (sac 50 kg)', 'category_id' => $categorie->id,
            'unit' => 'sac', 'pricing_mode' => 'fourchette', 'price_min' => 18_000, 'price_max' => 22_000, 'tva_rate' => 0,
            'stock_qty' => 0, 'is_active' => true,
        ]);

        $this->oeufs = Product::create([
            'sku' => 'OEUF-PLATEAU', 'name' => 'Plateau d’œufs', 'category_id' => $categorie->id,
            'species_id' => $espece->id, 'unit' => 'plateau', 'pricing_mode' => 'fourchette',
            'price_min' => 2_000, 'price_max' => 2_500, 'tva_rate' => 0,
            'stock_qty' => 0, 'is_active' => true,
        ]);

        $this->pondeuses = LivestockLot::create([
            'code' => 'PON-2026-01', 'species_id' => $espece->id, 'stage' => 'ponte',
            'initial_quantity' => 200, 'current_quantity' => 200,
            'created_date' => '2026-06-01', 'status' => 'actif', 'is_active' => true,
        ]);
    }

    protected function exercice(int $annee, string $statut = 'ouvert'): FiscalYear
    {
        return FiscalYear::create([
            'year' => $annee, 'start_date' => "{$annee}-01-01", 'end_date' => "{$annee}-12-31",
            'status' => $statut, 'closed_at' => $statut === 'cloture' ? now() : null,
        ]);
    }

    /**
     * Stock et coût d'achat connu (PMP 15 000 F le sac : une ligne d'achat de [$quantite] sacs à 15 000 F), posés
     * directement : c'est le décor, pas l'objet du test.
     */
    protected function stockDeMais(float $quantite, string $date): void
    {
        $this->mais->update(['stock_qty' => $quantite]);
        StockMovement::create([
            'product_id' => $this->mais->id, 'type' => 'entree', 'quantity' => $quantite,
            'reference_type' => 'purchase', 'movement_date' => $date,
        ]);
        $fournisseur = Supplier::create(['name' => 'Provenderie du Sud', 'phone' => '97000010', 'is_active' => true]);
        $achat = Purchase::create([
            'supplier_id' => $fournisseur->id, 'payment_mode' => 'especes', 'total' => $quantite * 15_000, 'purchase_date' => $date,
        ]);
        PurchaseLine::create(['purchase_id' => $achat->id, 'product_id' => $this->mais->id, 'qty' => $quantite, 'unit_price' => 15_000]);
    }

    /**
     * Le message exact sous le champ. ⚠️ `assertHasErrors(['champ' => ['message']])` de Livewire coupe la valeur au
     * premier « : » (il la lit comme une règle `regle:parametres`) : inutilisable pour les messages R4.
     */
    protected function assertErreurSousLeChamp($composant, string $champ, string $message): void
    {
        $this->assertSame($message, $composant->errors()->first($champ), "message sous le champ « {$champ} »");
    }

    protected function connecterLePoste(): void
    {
        $this->jeton = $this->postJson('/api/auth/login', [
            'identifiant' => 'admin-ex', 'password' => 'AgriERP@2026', 'device_name' => 'poste-bureau',
        ])->assertOk()->json('token');
    }

    protected function envoyer(array $paquet)
    {
        if ($this->jeton === '') {
            $this->connecterLePoste();
        }

        return $this->withHeader('Authorization', 'Bearer '.$this->jeton)->postJson('/api/sync/push', $paquet);
    }

    protected function venteDuPoste(string $id, ?string $soldAt, float $montant = 20_000): array
    {
        return array_filter([
            'id' => $id,
            'payment_mode' => 'especes',
            'subtotal' => $montant, 'discount' => 0, 'total' => $montant,
            'status' => 'validee',
            'sold_at' => $soldAt,
            'lines' => [[
                'product_id' => $this->mais->id,
                'qty' => 1, 'unit_price' => $montant, 'manual_total_amount' => $montant,
            ]],
        ], fn ($v) => $v !== null);
    }

    protected function depenseDuPoste(string $id, string $date, float $montant = 25_000): array
    {
        return [
            'id' => $id, 'expense_date' => $date, 'label' => 'Facture SBEE',
            'category' => '605 - Énergie', 'amount' => $montant, 'treasury_account_id' => $this->caisse->id,
        ];
    }
}
