<?php

namespace Tests\Feature;

use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\User;
use App\Services\AccountingEntryService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

/**
 * Ticket 15.29 — LE TIRAGE SERT LA DATE DE CRÉATION DES ÉCRITURES (item 9, T2 : Grand Livre du poste).
 *
 * ⚠️⚠️ `FinancialReportService::grandLivre` départage deux pièces du MÊME JOUR par
 * `orderBy('accounting_entries.entry_date')->orderBy('accounting_entries.created_at')`. Le poste ne
 * recevait pas `created_at` : il ne pouvait donc pas reproduire l'ordre du serveur, et deux pièces du
 * même jour pouvaient s'inverser — donc le solde progressif de chaque ligne changeait, sans erreur.
 *
 * Contrat : chaque écriture servie porte `created_at` (instant ISO 8601). Il ne change JAMAIS après la
 * création (contrairement à `updated_at`, que `updateManual` fait avancer par `touch()`).
 *
 * Contrat annexe, verrouillé ici parce que le solde d'OUVERTURE du poste en dépend : le tirage ne
 * filtre PAS par exercice — les écritures d'un exercice antérieur, même clos, sont servies. Un poste
 * qui a fait un tirage complet détient donc tout l'historique actif.
 */
class SyncEcrituresDateCreationTest extends TestCase
{
    use RefreshDatabase;

    private User $utilisateur;

    private ChartOfAccount $caisse;

    private ChartOfAccount $ventes;

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow('2026-10-10 10:00:00');

        FiscalYear::create([
            'year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert',
        ]);

        $this->caisse = ChartOfAccount::create(['code' => '531', 'label' => 'Caisse', 'class' => 5, 'is_active' => true]);
        $this->ventes = ChartOfAccount::create(['code' => '701', 'label' => 'Ventes', 'class' => 7, 'is_active' => true]);

        $this->utilisateur = User::create([
            'name' => 'Poste', 'username' => 'poste', 'email' => 'poste@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function ecrire(string $date, string $reference, float $montant = 1_000): AccountingEntry
    {
        return app(AccountingEntryService::class)
            ->recordManual($this->caisse->id, $this->ventes->id, $montant, $date, $reference);
    }

    private function tirer(?string $since = null)
    {
        return $this->actingAs($this->utilisateur, 'sanctum')
            ->getJson('/api/sync/pull'.($since ? '?since='.urlencode($since) : ''));
    }

    public function test_chaque_ecriture_servie_porte_son_instant_de_creation(): void
    {
        Carbon::setTestNow('2026-10-10 10:00:00');
        $a = $this->ecrire('2026-10-05', 'OD-0001 — A');
        Carbon::setTestNow('2026-10-10 11:30:15');
        $b = $this->ecrire('2026-10-05', 'OD-0002 — B');

        $servies = collect($this->tirer()->assertOk()->json('accounting_entries'))->keyBy('id');

        $this->assertArrayHasKey('created_at', $servies[$a->id]);
        $this->assertSame($a->fresh()->created_at->toIso8601String(), $servies[$a->id]['created_at']);
        $this->assertSame($b->fresh()->created_at->toIso8601String(), $servies[$b->id]['created_at']);
        // Deux instants DIFFÉRENTS : c'est bien l'ordre de création qui est servi.
        $this->assertNotSame($servies[$a->id]['created_at'], $servies[$b->id]['created_at']);
        $this->assertTrue(
            Carbon::parse($servies[$a->id]['created_at'])->lt(Carbon::parse($servies[$b->id]['created_at']))
        );
    }

    public function test_l_instant_servi_est_celui_de_la_creation_pas_celui_de_la_derniere_modification(): void
    {
        $a = $this->ecrire('2026-10-05', 'OD-0001 — A');
        $creeA = $a->fresh()->created_at->toIso8601String();

        // Modification ultérieure : `updateManual` appelle `touch()`, `updated_at` avance.
        Carbon::setTestNow('2026-10-11 09:00:00');
        app(AccountingEntryService::class)->updateManual($a->fresh(), $this->caisse->id, $this->ventes->id, 2_000, '2026-10-05', 'OD-0001 — A');

        $servie = collect($this->tirer()->assertOk()->json('accounting_entries'))->firstWhere('id', $a->id);

        $this->assertNotNull($servie);
        $this->assertSame($creeA, $servie['created_at']);
        $this->assertNotSame($a->fresh()->updated_at->toIso8601String(), $servie['created_at']);
    }

    public function test_le_tirage_incremental_sert_aussi_la_date_de_creation(): void
    {
        $this->ecrire('2026-10-05', 'OD-0001 — A');
        Carbon::setTestNow('2026-10-10 12:00:00');
        $b = $this->ecrire('2026-10-06', 'OD-0002 — B');

        $servies = $this->tirer('2026-10-10T11:00:00+00:00')->assertOk()->json('accounting_entries');

        $this->assertCount(1, $servies);
        $this->assertSame($b->id, $servies[0]['id']);
        $this->assertSame($b->fresh()->created_at->toIso8601String(), $servies[0]['created_at']);
    }

    public function test_les_ecritures_d_un_exercice_anterieur_clos_sont_servies_avec_leurs_lignes(): void
    {
        $ancien = FiscalYear::create([
            'year' => 2025, 'start_date' => '2025-01-01', 'end_date' => '2025-12-31', 'status' => 'ouvert',
        ]);
        $vieille = $this->ecrire('2025-06-10', 'OD-2025-0001 — Ancienne', 7_000);
        $ancien->update(['status' => 'cloture']);
        $recente = $this->ecrire('2026-10-05', 'OD-0001 — Récente', 1_000);

        $corps = $this->tirer()->assertOk()->json();

        $ids = array_column($corps['accounting_entries'], 'id');
        $this->assertContains($vieille->id, $ids);
        $this->assertContains($recente->id, $ids);
        // Ses lignes descendent avec elle : sans cela, le solde d'ouverture du poste serait faux.
        $lignes = array_values(array_filter($corps['accounting_entry_lines'], fn ($l) => $l['entry_id'] === $vieille->id));
        $this->assertCount(2, $lignes);
        $this->assertEquals(7_000.0, array_sum(array_column($lignes, 'debit')));
    }
}
