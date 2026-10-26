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
use App\Models\Role;
use App\Models\Supplier;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Route;
use Tests\TestCase;

/**
 * Ticket 14.22 (Sprint 14) — AUDIT RBAC : chaque rôle × chaque route.
 *
 * `AuditToutesLesRoutesTest` (ticket 14.20) prouve que toutes les routes
 * rendent **pour un administrateur**. Il ne prouve rien sur l'inverse : qu'un
 * caissier soit réellement bloqué sur la Comptabilité en tapant l'URL.
 *
 * C'est pourtant l'exigence explicite du Document 07 §4 : « un lien masqué ne
 * suffit pas — vérifier qu'une requête directe sur l'URL est aussi bloquée ».
 * Le parcours Dusk correspondant est rouge depuis toujours, et aucun test
 * Feature ne couvrait la question de façon systématique.
 *
 * ⚠️ MATRICE DÉRIVÉE DES DONNÉES RÉELLES, JAMAIS ÉCRITE À LA MAIN : la
 * permission attendue est lue dans le middleware `can:` de chaque route, et
 * les permissions de chaque rôle viennent du `RolesAndPermissionsSeeder`. Une
 * matrice recopiée à la main dériverait au premier ajout de route — c'est
 * exactement le faux positif rencontré au ticket 14.20.
 */
class AuditRbacRoutesTest extends TestCase
{
    use RefreshDatabase;

    /** Les 4 rôles réellement implémentés (`RBAC_PAGE_MAP`, Document 00 §6). */
    private const ROLES = ['admin', 'comptable', 'caissier', 'animalier'];

    private const EXCLUES = ['login', 'password.reset', 'logout', 'health-check'];

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

    /** Permission exigée par la route, lue dans son middleware `can:`. */
    private function permissionRequise($route): ?string
    {
        foreach ($route->gatherMiddleware() as $middleware) {
            if (is_string($middleware) && str_starts_with($middleware, 'can:')) {
                return substr($middleware, 4);
            }
        }

        return null;
    }

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
            'code' => 'LOT-RBAC', 'species_id' => $species->id, 'stage' => 'reproduction',
            'initial_quantity' => 5, 'current_quantity' => 5,
            'created_date' => now()->format('Y-m-d'), 'status' => 'actif', 'is_active' => true,
        ]);

        $categorie = ProductCategory::create(['label' => 'RBAC', 'is_active' => true]);

        return [
            'product' => Product::create([
                'sku' => 'RBAC-1', 'name' => 'Produit', 'category_id' => $categorie->id,
                'unit' => 'pièce', 'pricing_mode' => 'fourchette', 'price_min' => 1,
                'price_max' => 2, 'stock_qty' => 1, 'is_active' => true,
            ])->id,
            'customer' => Customer::create(['name' => 'Client', 'phone' => '+22997000000', 'is_active' => true])->id,
            'supplier' => Supplier::create(['name' => 'Fournisseur', 'phone' => '+22997111111', 'is_active' => true])->id,
            'animal' => Animal::create([
                'identifier' => 'RBAC-0001', 'species_id' => $species->id, 'lot_id' => $lot->id,
                'category' => 'reproducteur', 'sex' => 'F', 'entry_date' => now()->format('Y-m-d'),
            ])->id,
        ];
    }

    public function test_every_role_reaches_exactly_what_its_permissions_allow(): void
    {
        $this->withoutVite();

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $parametres = $this->fixtures();

        $anomalies = [];
        $verifications = 0;

        foreach (self::ROLES as $nomRole) {
            $role = Role::findByName($nomRole, 'web');

            $user = User::create([
                'name' => 'Audit '.$nomRole,
                'email' => $nomRole.'.rbac@fermeolouwachegoun.com',
                'password' => bcrypt('AgriERP@2026'),
            ]);
            $user->assignRole($role);

            foreach (Route::getRoutes() as $route) {
                $nom = $route->getName();

                if (! in_array('GET', $route->methods(), true)
                    || $nom === null
                    || in_array($nom, self::EXCLUES, true)
                    || $this->estRouteDeFramework($nom)) {
                    continue;
                }

                $uri = $route->uri();

                foreach ($route->parameterNames() as $param) {
                    if (! isset($parametres[$param])) {
                        continue 2;
                    }
                    $uri = preg_replace('/\{'.$param.'\??\}/', $parametres[$param], $uri);
                }

                $permission = $this->permissionRequise($route);
                $autorise = $permission === null || $user->can($permission);

                $reponse = $this->actingAs($user)->get('/'.ltrim($uri, '/'));
                $verifications++;

                $statut = $reponse->status();

                if ($autorise && $statut >= 400) {
                    $anomalies[] = "[$nomRole] {$nom} : autorise ({$permission}) mais HTTP {$statut}";
                }

                // Le point critique : un rôle SANS la permission doit être
                // refusé par une requête directe sur l'URL, pas seulement
                // privé du lien dans le menu.
                if (! $autorise && $statut !== 403) {
                    $anomalies[] = "[$nomRole] {$nom} ({$uri}) : NON autorise ({$permission}) mais HTTP {$statut} au lieu de 403";
                }
            }
        }

        $this->assertGreaterThan(200, $verifications, 'La matrice doit couvrir 4 roles x toutes les routes.');
        $this->assertSame([], $anomalies, "Anomalies RBAC :\n".implode("\n", $anomalies));
    }

    /**
     * Aucune route métier ne doit reposer sur `auth` seul : sans permission,
     * tout utilisateur connecté y accède quel que soit son rôle. Les seules
     * exceptions légitimes sont les écrans universels.
     */
    public function test_no_business_route_relies_on_authentication_alone(): void
    {
        $universelles = [
            'dashboard.index', 'profil.index', 'aide.index', 'contact.index',
            'notifications.index', 'public.welcome', 'public.presentation',
            // Sprint VW : l'écran de verrouillage protège la session de tout compte connecté, sans permission dédiée.
            'session.verrou',
        ];

        $sansPermission = [];

        foreach (Route::getRoutes() as $route) {
            $nom = $route->getName();

            if (! in_array('GET', $route->methods(), true)
                || $nom === null
                || in_array($nom, self::EXCLUES, true)
                || in_array($nom, $universelles, true)
                || $this->estRouteDeFramework($nom)) {
                continue;
            }

            $middlewares = $route->gatherMiddleware();

            if (! in_array('auth', $middlewares, true)) {
                continue;   // route publique assumée
            }

            if ($this->permissionRequise($route) === null) {
                $sansPermission[] = $nom.' ('.$route->uri().')';
            }
        }

        $this->assertSame(
            [],
            $sansPermission,
            "Routes metier protegees par 'auth' seul, sans permission :\n".implode("\n", $sansPermission)
        );
    }
}
