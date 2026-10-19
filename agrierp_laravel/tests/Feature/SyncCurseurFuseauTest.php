<?php

namespace Tests\Feature;

use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Sale;
use App\Models\SaleLine;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket S-T12 (trouvé par l'essai à plusieurs postes) — LE CURSEUR DU TIRAGE ENVOYÉ EN UTC EST LU À L'HEURE DU SERVEUR.
 *
 * Le poste renvoie `since` en UTC (`…Z`). Le serveur, à l'heure du Bénin (UTC+1), le comparait à `updated_at` comme
 * une heure murale : le curseur reculait d'une heure et chaque tirage « incrémental » resservait toute l'heure écoulée
 * (sur l'essai, 6 pages de 1 000 lignes au lieu de quelques lignes — et tout à refaire à chaque coupure).
 *
 * Attendus à la main : il est 10 h 30 au Bénin. Vente A modifiée à 10 h 00, vente B à 10 h 20. Le poste a tiré à
 * 10 h 10 (heure du Bénin) = 09 h 10 UTC : seule B est nouvelle pour lui. Lu comme une heure murale, « 09 h 10 »
 * faisait resservir A.
 */
class SyncCurseurFuseauTest extends TestCase
{
    use RefreshDatabase;

    private User $caissier;

    private Product $produit;

    protected function setUp(): void
    {
        parent::setUp();

        config(['app.timezone' => 'Africa/Porto-Novo']);
        date_default_timezone_set('Africa/Porto-Novo');

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $this->caissier = User::create([
            'name' => 'Caissière', 'username' => 'caisse', 'email' => 'caisse@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->caissier->assignRole('caissier');

        $categorie = ProductCategory::create(['label' => 'Engrais', 'is_active' => true]);
        $this->produit = Product::create([
            'sku' => 'ENG-001', 'name' => 'Fumier composté', 'category_id' => $categorie->id, 'unit' => 'sac',
            'pricing_mode' => 'fourchette', 'price_min' => 1000, 'price_max' => 2000, 'stock_qty' => 100, 'is_active' => true,
        ]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function venteA(string $heure): Sale
    {
        Carbon::setTestNow('2026-10-19 '.$heure);
        $vente = Sale::create(['payment_mode' => 'especes', 'subtotal' => 1500, 'total' => 1500, 'status' => 'validee']);
        SaleLine::create([
            'sale_id' => $vente->id, 'product_id' => $this->produit->id, 'qty' => 1,
            'unit_price' => 1500, 'manual_total_amount' => 1500, 'is_manual_price' => true,
        ]);

        return $vente;
    }

    /** @return array<int, string> identifiants des ventes servies, toutes pages confondues */
    private function ventesServies(string $since, bool $pagine): array
    {
        Carbon::setTestNow('2026-10-19 10:30:00');
        $ids = [];
        $jeton = null;
        for ($page = 1; $page < 20; $page++) {
            $parametres = ['since' => $since] + ($pagine ? ['page' => $page] + ($jeton ? ['curseur_page' => $jeton] : []) : []);
            $reponse = $this->actingAs($this->caissier, 'sanctum')->getJson('/api/sync/pull?'.http_build_query($parametres))->assertOk();
            $ids = array_merge($ids, array_column($reponse->json('sales') ?? [], 'id'));
            $jeton = $reponse->json('page_suivante');
            if (! $pagine || $jeton === null) {
                break;
            }
        }

        return $ids;
    }

    public function test_un_curseur_en_utc_ne_resservit_pas_l_heure_ecoulee(): void
    {
        $a = $this->venteA('10:00:00');
        $b = $this->venteA('10:20:00');

        foreach ([true, false] as $pagine) {
            $servies = $this->ventesServies('2026-10-19T09:10:00.000Z', $pagine);
            $this->assertSame([$b->id], $servies, ($pagine ? 'tirage paginé' : 'tirage d\'un poste ancien').' : seule la vente de 10 h 20 est nouvelle');
        }

        // Le même instant écrit avec le décalage du Bénin : même réponse.
        $this->assertSame([$b->id], $this->ventesServies('2026-10-19T10:10:00+01:00', true));
        // Un curseur antérieur aux deux ventes les sert toutes les deux.
        $this->assertEqualsCanonicalizing([$a->id, $b->id], $this->ventesServies('2026-10-19T08:50:00Z', true));
    }
}
