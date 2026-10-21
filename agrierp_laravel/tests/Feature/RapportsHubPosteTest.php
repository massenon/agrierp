<?php

namespace Tests\Feature;

use App\Livewire\Rapports\Creances;
use App\Livewire\Rapports\Dettes;
use App\Livewire\Rapports\RapportsExportsHub;
use App\Livewire\Rapports\RecettesDepenses;
use App\Livewire\Rapports\StocksSynth;
use App\Models\Customer;
use App\Models\Expense;
use App\Models\Payable;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Purchase;
use App\Models\Receivable;
use App\Models\Role;
use App\Models\Supplier;
use App\Models\TreasuryAccount;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket U12b — hub « Rapports & Exports » : ce que le portage au poste a révélé côté web.
 *
 *  1. 🔴 Une dépense ARCHIVÉE (montant réintégré en trésorerie, charge contre-passée par
 *     `SaisieDepenses::archiveExpense()`) restait une dépense de l'état des Recettes et Dépenses.
 *  2. 🔴 Ordre non déterminé : deux pièces de la même date (achats, dépenses, ventes de la même seconde,
 *     créances ou dettes de la même échéance) sortaient dans l'ordre du moteur de base ; le poste ne pouvait
 *     pas le reproduire. Second critère : l'identifiant.
 *  3. 🔴 `StocksSynth::getRowsProperty()` gardait les clés après `filter()` : une catégorie vide retirée
 *     décalait le zébrage (`$i % 2`).
 *  4. Le droit `export-rapports` masque les boutons d'export du hub (repris au poste).
 */
class RapportsHubPosteTest extends TestCase
{
    use RefreshDatabase;

    private function connecter(array $permissions): void
    {
        foreach ($permissions as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('essai-'.count($permissions), 'web');
        $role->syncPermissions($permissions);
        $utilisateur = User::create([
            'name' => 'Comptable', 'email' => 'rapports'.count($permissions).'@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'),
        ]);
        $utilisateur->assignRole($role);
        $this->actingAs($utilisateur);
    }

    private function parametres(): array
    {
        return ['startDate' => '2026-07-01', 'endDate' => '2026-07-31'];
    }

    public function test_une_depense_archivee_n_est_plus_une_depense(): void
    {
        $this->connecter(['view-rapports']);
        $caisse = TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse', 'account_code' => '531']);
        Expense::create([
            'expense_date' => '2026-07-10', 'label' => 'Carburant', 'category' => '628 - Autres charges',
            'amount' => 5000, 'treasury_account_id' => $caisse->id,
        ]);
        Expense::create([
            'expense_date' => '2026-07-11', 'label' => 'Annulée', 'category' => '628 - Autres charges',
            'amount' => 70000, 'treasury_account_id' => $caisse->id, 'is_active' => false,
        ]);

        $composant = Livewire::test(RecettesDepenses::class, $this->parametres());

        $this->assertSame(['Carburant'], $composant->instance()->depenses->pluck('label')->all());
        $this->assertSame(5000.0, $composant->instance()->kpis['depenses']);
        $composant->assertDontSee('Annulée');
    }

    public function test_deux_pieces_du_meme_jour_sortent_par_identifiant(): void
    {
        $this->connecter(['view-rapports']);
        $fournisseur = Supplier::create(['name' => 'Provenderie du Plateau']);
        $client = Customer::create(['name' => 'Bar Le Palmier']);
        $ids = ['ffffffff-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002', '88888888-0000-4000-8000-000000000003'];
        foreach ($ids as $i => $id) {
            $achat = new Purchase(['supplier_id' => $fournisseur->id, 'payment_mode' => 'especes', 'total' => 1000 + $i, 'purchase_date' => '2026-07-10']);
            $achat->id = $id;
            $achat->save();
            $creance = new Receivable(['customer_id' => $client->id, 'amount' => 500 + $i, 'due_date' => '2026-07-20']);
            $creance->id = $id;
            $creance->save();
            $dette = new Payable(['supplier_id' => $fournisseur->id, 'amount' => 500 + $i, 'due_date' => '2026-07-20']);
            $dette->id = $id;
            $dette->save();
        }
        $attendu = [1001.0, 1002.0, 1000.0];

        $this->assertSame($attendu, Livewire::test(RecettesDepenses::class, $this->parametres())
            ->instance()->depenses->pluck('amount')->all());
        $this->assertSame([501.0, 502.0, 500.0], Livewire::test(Creances::class, $this->parametres())
            ->instance()->receivables->map(fn ($r) => (float) $r->amount)->all());
        $this->assertSame([501.0, 502.0, 500.0], Livewire::test(Dettes::class, $this->parametres())
            ->instance()->payables->map(fn ($p) => (float) $p->amount)->all());
    }

    public function test_le_rapport_de_stocks_est_reindexe_apres_le_filtre(): void
    {
        $this->connecter(['view-rapports']);
        ProductCategory::create(['label' => 'A — vide', 'is_active' => true]);
        foreach (['B — aliments', 'C — œufs'] as $libelle) {
            $categorie = ProductCategory::create(['label' => $libelle, 'is_active' => true]);
            Product::create([
                'sku' => substr($libelle, 0, 1), 'name' => $libelle, 'category_id' => $categorie->id, 'unit' => 'u',
                'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 2, 'stock_qty' => 1, 'is_active' => true,
            ]);
        }

        $lignes = Livewire::test(StocksSynth::class, $this->parametres())->instance()->rows;

        $this->assertSame([0, 1], $lignes->keys()->all());
        $this->assertSame(['B — aliments', 'C — œufs'], $lignes->map(fn ($r) => $r['category']->label)->all());
    }

    public function test_les_boutons_d_export_suivent_le_droit_export_rapports(): void
    {
        $this->connecter(['view-rapports']);
        Livewire::test(RapportsExportsHub::class)->assertDontSee('Exporter PDF')->assertDontSee('Exporter Excel');

        $this->connecter(['view-rapports', 'export-rapports']);
        Livewire::test(RapportsExportsHub::class)->assertSee('Exporter PDF')->assertSee('Exporter Excel');
    }
}
