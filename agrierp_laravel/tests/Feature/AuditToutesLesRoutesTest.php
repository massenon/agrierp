<?php

namespace Tests\Feature;

use App\Models\Animal;
use App\Models\ChartOfAccount;
use App\Models\Customer;
use App\Models\FiscalYear;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Supplier;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Route;
use Tests\TestCase;

/**
 * Ticket 14.20 (Sprint 14) — AUDIT : 0 erreur, 0 lien cassé, 0 ressource
 * manquante.
 *
 * Ce test parcourt **toutes les routes GET enregistrées** et vérifie que
 * chacune rend réellement, en tant qu'administrateur. Jusqu'ici aucun test ne
 * faisait cela : les 104 tests Feature ciblent des composants précis via
 * `Livewire::test()`, et rien ne garantissait qu'une route déclarée soit
 * seulement atteignable.
 *
 * Le principe est celui qui a payé tout au long de ce sprint : exercer le
 * chemin réel plutôt qu'un chemin qui lui ressemble.
 */
class AuditToutesLesRoutesTest extends TestCase
{
    use RefreshDatabase;

    /** Routes exclues, avec le motif — jamais une exclusion silencieuse. */
    private const EXCLUES = [
        'login' => 'redirige un utilisateur déjà authentifié (middleware guest)',
        'password.reset' => 'redirige un utilisateur déjà authentifié (middleware guest)',
        'logout' => 'POST uniquement',
        'health-check' => 'sonde JSON, pas un écran',
    ];

    /**
     * Routes fournies par le framework ou par un paquet (Dusk, Livewire,
     * stockage local) : ce ne sont pas des ecrans de l'application et elles
     * ne relevent donc pas de cet audit. Exclusion NOMMEE et motivee, jamais
     * un filtre silencieux qui masquerait une route metier.
     */
    private function estRouteDeFramework(?string $nom): bool
    {
        if ($nom === null) {
            return false;
        }

        foreach (['dusk.', 'livewire.', 'storage.', 'sanctum.', 'ignition.'] as $prefixe) {
            if (str_starts_with($nom, $prefixe)) {
                return true;
            }
        }

        return false;
    }

    /**
     * Administrateur construit depuis le VRAI seeder de roles et permissions,
     * jamais depuis une liste ecrite a la main : une liste maintenue ici
     * derive du seeder au premier ajout de permission et produit de faux
     * echecs 403 — c'est exactement ce qui s'est produit au premier passage
     * de cet audit (`view-facturation` oublie).
     */
    private function administrateur(): User
    {
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);

        $user = User::create([
            'name' => 'Auditeur',
            'email' => 'audit@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'),
        ]);
        $user->assignRole('admin');

        return $user;
    }

    /** Jeu minimal permettant de résoudre les routes à paramètre. */
    private function fixtures(): array
    {
        FiscalYear::create([
            'year' => now()->year,
            'start_date' => now()->startOfYear()->format('Y-m-d'),
            'end_date' => now()->endOfYear()->format('Y-m-d'),
            'status' => 'ouvert',
        ]);

        ChartOfAccount::create(['code' => '531', 'label' => 'Caisse', 'class' => 5, 'is_active' => true]);

        $species = LivestockSpecies::create(['code' => 'cuniculture', 'label' => 'Lapins', 'is_enabled' => true]);

        $lot = LivestockLot::create([
            'code' => 'LOT-AUDIT-01', 'species_id' => $species->id, 'stage' => 'reproduction',
            'initial_quantity' => 10, 'current_quantity' => 10,
            'created_date' => now()->format('Y-m-d'), 'status' => 'actif', 'is_active' => true,
        ]);

        $categorie = ProductCategory::create(['label' => 'Audit', 'is_active' => true]);

        return [
            'product' => Product::create([
                'sku' => 'AUDIT-1', 'name' => 'Produit audit', 'category_id' => $categorie->id,
                'unit' => 'pièce', 'pricing_mode' => 'fourchette', 'price_min' => 100,
                'price_max' => 200, 'stock_qty' => 10, 'is_active' => true,
            ])->id,
            'customer' => Customer::create(['name' => 'Client Audit', 'phone' => '+22997000000', 'is_active' => true])->id,
            'supplier' => Supplier::create(['name' => 'Fournisseur Audit', 'phone' => '+22997111111', 'is_active' => true])->id,
            'animal' => Animal::create([
                'identifier' => 'AUDIT-0001', 'species_id' => $species->id, 'lot_id' => $lot->id,
                'category' => 'reproducteur', 'sex' => 'F', 'entry_date' => now()->format('Y-m-d'),
            ])->id,
        ];
    }

    public function test_every_registered_get_route_renders_without_error(): void
    {
        $this->withoutVite();   // le bundling n'est pas l'objet de cet audit

        $this->actingAs($this->administrateur());
        $parametres = $this->fixtures();

        $echecs = [];
        $verifiees = 0;

        foreach (Route::getRoutes() as $route) {
            if (! in_array('GET', $route->methods(), true)) {
                continue;
            }

            $nom = $route->getName();

            if ($nom === null || isset(self::EXCLUES[$nom]) || $this->estRouteDeFramework($nom)) {
                continue;
            }

            $uri = $route->uri();

            // Substitution des paramètres par des enregistrements réels.
            foreach ($route->parameterNames() as $param) {
                if (! isset($parametres[$param])) {
                    continue 2;   // paramètre non couvert : compté à part, jamais ignoré en silence
                }
                $uri = preg_replace('/\{'.$param.'\??\}/', $parametres[$param], $uri);
            }

            $reponse = $this->get('/'.ltrim($uri, '/'));
            $verifiees++;

            if ($reponse->status() >= 400) {
                $echecs[] = $nom.' ('.$uri.') -> HTTP '.$reponse->status();
            }
        }

        $this->assertGreaterThan(50, $verifiees, 'L audit doit couvrir la grande majorite des routes.');
        $this->assertSame([], $echecs, "Routes en erreur :\n".implode("\n", $echecs));
    }

    /** Aucune route à paramètre ne doit rester non couverte sans qu'on le sache. */
    public function test_no_parameterised_route_is_silently_skipped(): void
    {
        $parametresCouverts = ['product', 'customer', 'supplier', 'animal', 'token'];
        $nonCouverts = [];

        foreach (Route::getRoutes() as $route) {
            if (! in_array('GET', $route->methods(), true) || $route->getName() === null) {
                continue;
            }

            if ($this->estRouteDeFramework($route->getName())) {
                continue;
            }

            foreach ($route->parameterNames() as $param) {
                if (! in_array($param, $parametresCouverts, true)) {
                    $nonCouverts[] = $route->getName().' : {'.$param.'}';
                }
            }
        }

        $this->assertSame(
            [],
            $nonCouverts,
            "Routes a parametre non couvertes par l audit :\n".implode("\n", $nonCouverts)
        );
    }
}
