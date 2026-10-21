<?php

namespace Tests\Feature;

use App\Http\Controllers\Api\SyncController;
use App\Models\Employee;
use App\Models\Expense;
use App\Models\Payslip;
use App\Models\TreasuryAccount;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Collection;
use Tests\TestCase;

/**
 * Ticket U13 — `expenses` ET `payslips` DESCENDENT AU POSTE (tirage paginé S-T4).
 *
 * Le rapport « Recettes et Dépenses » du poste calculait comme le web mais ne voyait ni la paie, ni les dépenses
 * saisies au web ou sur un autre poste, et comptait une dépense du poste archivée ensuite au web. Verrouillé ici :
 *  - les dépenses sont de BASE (le Tableau de bord, ouvert aux quatre rôles, les liste au web) ; la paie n'est servie
 *    qu'aux comptes `view-rapports` (comptable, administrateur) — jamais au caissier ni à l'animalier ;
 *  - ⚠️ S3 : un bulletin descend avec les SEULES colonnes du calcul du web (identifiant, nom de l'employé, net versé,
 *    instant du règlement en heure murale) — ni brut, ni retenues, ni charges patronales, ni période ;
 *  - tirage complet : toutes les dépenses, ARCHIVÉES comprises (`is_active`) ; tirage incrémental : la dépense archivée
 *    au web depuis le curseur redescend avec `is_active = false` ;
 *  - pagination par pièce (taille imposée) : chaque dépense et chaque bulletin servis une fois ;
 *  - un poste ne peut pas écrire la paie : `payslips` envoyé est ignoré et compté.
 */
class SyncDepensesPaieTirageTest extends TestCase
{
    use RefreshDatabase;

    private TreasuryAccount $caisse;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        Carbon::setTestNow('2026-10-19 09:00:00');

        $this->caisse = TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function compte(string $role): User
    {
        $u = User::create([
            'name' => 'Compte '.$role, 'username' => $role, 'email' => $role.'@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    private function depense(string $libelle, float $montant, string $jour, bool $active = true): Expense
    {
        return Expense::create([
            'expense_date' => $jour, 'label' => $libelle, 'category' => '605 - Énergie', 'amount' => $montant,
            'treasury_account_id' => $this->caisse->id, 'status' => 'payee', 'is_active' => $active,
        ]);
    }

    private function bulletin(string $nom, string $prenom, float $net): Payslip
    {
        $employe = Employee::create(['first_name' => $prenom, 'last_name' => $nom, 'base_salary' => 150000, 'is_active' => true]);

        return Payslip::create([
            'employee_id' => $employe->id, 'period_month' => '2026-10-01', 'gross_salary' => 150000,
            'absence_deduction' => 0, 'cnss_deduction' => 5400, 'its_deduction' => 1200, 'vps_employer' => 6000,
            'cnss_employer_pension' => 9600, 'cnss_employer_family' => 13500, 'cnss_employer_risk' => 1500,
            'net_salary' => $net,
        ]);
    }

    /**
     * Toutes les pages d'un tirage paginé, une minute après les écritures : le tirage ne sert que les pièces écrites
     * AVANT son début (S-T4).
     *
     * @return array<int, array<string, mixed>>
     */
    private function pages(User $compte, ?int $taille = null, ?string $since = null): array
    {
        Carbon::setTestNow(now()->addMinute());
        $pages = [];
        $jeton = null;
        do {
            $corps = $this->actingAs($compte, 'sanctum')->getJson('/api/sync/pull?'.http_build_query(array_filter([
                'page' => count($pages) + 1, 'curseur_page' => $jeton, 'taille' => $taille, 'since' => $since,
            ], fn ($v) => $v !== null)))->assertOk()->json();
            $pages[] = $corps;
            $jeton = $corps['page_suivante'];
        } while ($jeton !== null && count($pages) < 100);

        return $pages;
    }

    private function servis(array $pages, string $cle): Collection
    {
        return collect($pages)->flatMap(fn (array $p) => $p[$cle] ?? []);
    }

    public function test_la_correspondance_des_permissions_de_u13(): void
    {
        $this->assertNull(SyncController::PERMISSIONS_DE_TIRAGE['expenses']);
        $this->assertSame(['view-rapports'], SyncController::PERMISSIONS_DE_TIRAGE['payslips']);
    }

    public function test_depenses_a_tous_les_roles_paie_aux_seuls_comptes_qui_lisent_les_rapports(): void
    {
        $this->depense('Électricité SBEE', 42000, '2026-10-02');
        $this->bulletin('HOUNKPÈ', 'Codjo', 138650);

        foreach (['admin' => true, 'comptable' => true, 'caissier' => false, 'animalier' => false] as $role => $paie) {
            $page = $this->pages($this->compte($role))[0];
            $this->assertContains('expenses', $page['tables_servies'], $role);
            $this->assertCount(1, $page['expenses'], $role);
            $this->assertSame($paie, in_array('payslips', $page['tables_servies'], true), $role);
            $this->assertSame($paie, array_key_exists('payslips', $page), "clé payslips — {$role}");
        }
    }

    public function test_un_bulletin_ne_descend_qu_avec_les_colonnes_du_rapport(): void
    {
        Carbon::setTestNow('2026-10-18 23:30:00');
        $b = $this->bulletin('HOUNKPÈ', 'Codjo', 138650.5);
        Carbon::setTestNow('2026-10-19 09:00:00');

        $servi = $this->servis($this->pages($this->compte('comptable')), 'payslips')->sole();

        // ⚠️ S3 : exactement ces quatre clés — ni brut, ni retenues, ni charges patronales, ni période, ni employé.
        $this->assertSame(['id', 'employee_name', 'net_salary', 'created_at'], array_keys($servi));
        $this->assertSame($b->id, $servi['id']);
        $this->assertSame('HOUNKPÈ Codjo', $servi['employee_name']);
        $this->assertEquals(138650.5, $servi['net_salary']);
        // Heure MURALE du serveur : le jour du rapport est le 18 (et non le 18 à 22 h 30 UTC lu à l'heure de Windows).
        $this->assertSame('2026-10-18 23:30:00', $servi['created_at']);
    }

    public function test_tirage_complet_toutes_les_depenses_archivees_comprises_incremental_l_archivage(): void
    {
        $active = $this->depense('Carburant groupe', 15000, '2026-10-03');
        $archivee = $this->depense('Doublon', 9000, '2026-10-04', false);
        $admin = $this->compte('admin');

        $complet = $this->servis($this->pages($admin), 'expenses')->keyBy('id');
        $this->assertEqualsCanonicalizing([$active->id, $archivee->id], $complet->keys()->all());
        $this->assertTrue($complet[$active->id]['is_active']);
        $this->assertFalse($complet[$archivee->id]['is_active'], 'un poste en service doit apprendre l\'archivage');
        // Le JSON ne garde pas « 15000.0 » : égalité de valeur, clés dans leur ordre.
        // Ticket U14 — plus `status` (badge et filtre du Blade) et `accounting_entry_id` (règle de modification).
        $this->assertSame(['id', 'expense_date', 'label', 'category', 'amount', 'treasury_account_id', 'is_active', 'status',
            'accounting_entry_id', 'updated_at'], array_keys($complet[$active->id]));
        $this->assertEquals([
            'id' => $active->id, 'expense_date' => '2026-10-03', 'label' => 'Carburant groupe', 'category' => '605 - Énergie',
            'amount' => 15000.0, 'treasury_account_id' => $this->caisse->id, 'is_active' => true,
            'status' => $active->status, 'accounting_entry_id' => $active->accounting_entry_id,
            'updated_at' => $active->updated_at->toIso8601String(),
        ], $complet[$active->id]);

        // Archivée au web APRÈS le curseur : elle redescend, désactivée ; l'autre ne redescend pas.
        $curseur = now()->toIso8601String();
        Carbon::setTestNow('2026-10-19 10:00:00');
        $active->update(['is_active' => false]);

        $increment = $this->servis($this->pages($admin, since: $curseur), 'expenses');
        $this->assertSame([$active->id], $increment->pluck('id')->all());
        $this->assertFalse($increment->sole()['is_active']);
    }

    public function test_un_employe_renomme_au_web_fait_redescendre_ses_bulletins_avec_le_nouveau_nom(): void
    {
        $b = $this->bulletin('HOUNKPE', 'Codjo', 138650);
        $admin = $this->compte('admin');
        $this->pages($admin);
        $curseur = now()->toIso8601String();

        // Le nom est corrigé au web : le rapport du web affiche aussitôt le nouveau nom (relation `employee`).
        Carbon::setTestNow(now()->addMinutes(5));
        $b->employee->update(['last_name' => 'HOUNKPÈ']);

        $servi = $this->servis($this->pages($admin, since: $curseur), 'payslips')->sole();
        $this->assertSame($b->id, $servi['id']);
        $this->assertSame('HOUNKPÈ Codjo', $servi['employee_name']);
    }

    public function test_pagination_par_piece_chaque_depense_et_chaque_bulletin_une_fois(): void
    {
        for ($i = 1; $i <= 7; $i++) {
            $this->depense("Dépense {$i}", 1000 * $i, '2026-10-0'.(1 + $i % 5));
        }
        for ($i = 1; $i <= 5; $i++) {
            $this->bulletin("NOM{$i}", 'Prénom', 100000 + $i);
        }

        $pages = $this->pages($this->compte('admin'), taille: 3);
        $this->assertGreaterThan(3, count($pages), 'le tirage se découpe');
        $depenses = $this->servis($pages, 'expenses')->pluck('id');
        $paie = $this->servis($pages, 'payslips')->pluck('id');
        $this->assertCount(7, $depenses);
        $this->assertCount(7, $depenses->unique());
        $this->assertCount(5, $paie);
        $this->assertCount(5, $paie->unique());
    }

    public function test_le_tirage_ancien_sans_page_sert_aussi_depenses_et_paie(): void
    {
        $this->depense('Eau', 3000, '2026-10-05');
        $this->bulletin('ADJO', 'Rémi', 90000);

        $corps = $this->actingAs($this->compte('admin'), 'sanctum')->getJson('/api/sync/pull')->assertOk()->json();
        $this->assertCount(1, $corps['expenses']);
        $this->assertCount(1, $corps['payslips']);
    }

    public function test_un_poste_n_ecrit_jamais_la_paie(): void
    {
        $reponse = $this->actingAs($this->compte('admin'), 'sanctum')->postJson('/api/sync/push', [
            'payslips' => [['id' => '11111111-1111-4111-8111-111111111111', 'net_salary' => 1, 'created_at' => '2026-10-19 08:00:00']],
        ])->assertOk();

        $this->assertSame(1, $reponse->json('referentiels_ignored'));
        $this->assertSame(0, Payslip::count());
    }
}
