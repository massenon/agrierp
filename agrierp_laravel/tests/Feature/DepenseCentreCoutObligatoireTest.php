<?php

namespace Tests\Feature;

use App\Actions\SaisieDepenseAction;
use App\Models\AccountingEntry;
use App\Models\CostCenter;
use App\Models\Expense;
use App\Models\ExpenseLine;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use Tests\TestCase;

/**
 * Ticket DEP6 (PRD `docs/prd/depenses-multilignes.md`, § 11 — DEP-Q1 close : OUI) — LE CENTRE DE COÛT EST OBLIGATOIRE à
 * la saisie d'une dépense : web, absorbeur du serveur. Un poste ANCIEN (qui n'envoie ni centre de coût ni choix de
 * règlement) est accepté et reçoit le centre par défaut « Général » : l'envoi d'anciennes dépenses n'est JAMAIS bloqué.
 * Les dépenses déjà au dépôt sans centre reçoivent « Général » par la migration, sans rien perdre ni toucher aux pièces.
 */
class DepenseCentreCoutObligatoireTest extends TestCase
{
    use DecorDepenses;
    use RefreshDatabase;

    private const ID = '22222222-bbbb-4bbb-8bbb-222222222222';

    protected function setUp(): void
    {
        parent::setUp();
        $this->preparerDecorDepenses();
        // La migration DEP6 a déjà créé « Général » sur la base de test : le décor repart d'un dépôt qui n'en a pas.
        CostCenter::where('label', CostCenter::LIBELLE_GENERAL)->delete();
    }

    private function action(): SaisieDepenseAction
    {
        return app(SaisieDepenseAction::class);
    }

    public function test_sans_centre_de_cout_la_saisie_est_refusee_avant_d_ecrire(): void
    {
        foreach ([null, ''] as $vide) {
            try {
                $this->action()->creer($this->document(['cost_center_id' => $vide]));
                $this->fail('La dépense aurait dû être refusée.');
            } catch (ValidationException $e) {
                $this->assertArrayHasKey('cost_center_id', $e->errors());
                $this->assertStringContainsString('centre de coût est obligatoire', $e->errors()['cost_center_id'][0]);
            }
        }

        $this->assertSame(0, Expense::count());
        $this->assertSame(0, ExpenseLine::count());
        $this->assertSame(0, AccountingEntry::count());
        $this->assertEquals(500_000.0, (float) $this->caisse->fresh()->balance);
    }

    public function test_avec_un_centre_la_depense_est_creee_et_le_centre_est_porte_par_l_ecriture(): void
    {
        $depense = $this->action()->creer($this->document());

        $this->assertSame($this->filiere->id, $depense->cost_center_id);
        $this->assertEquals([$this->filiere->id], AccountingEntry::findOrFail($depense->accounting_entry_id)->lines->pluck('cost_center_id')->unique()->values()->all());
    }

    public function test_la_modification_d_une_depense_sans_piece_exige_aussi_le_centre(): void
    {
        $depense = $this->action()->creer($this->document());
        // Une reprise de l'ancien : sans pièce, modifiable.
        Expense::whereKey($depense->id)->update(['accounting_entry_id' => null]);

        $this->expectException(ValidationException::class);
        $this->action()->modifier($depense->id, $this->document(['cost_center_id' => null]));
    }

    public function test_un_poste_ancien_sans_centre_ni_choix_de_reglement_est_accepte_au_centre_general(): void
    {
        $this->assertSame(0, CostCenter::where('label', CostCenter::LIBELLE_GENERAL)->count());
        $doc = $this->document() + ['id' => self::ID];
        unset($doc['cost_center_id']);

        $this->actingAs($this->admin, 'sanctum')->postJson('/api/sync/push', ['expenses' => [$doc]])
            ->assertOk()->assertJsonPath('expenses.accepted', [self::ID])->assertJsonPath('expenses.rejected', []);

        $general = CostCenter::where('label', CostCenter::LIBELLE_GENERAL)->sole();
        $this->assertSame('filiere', $general->type);
        $depense = Expense::findOrFail(self::ID);
        $this->assertSame($general->id, $depense->cost_center_id, 'le centre par défaut documenté');
        $this->assertEquals([$general->id], AccountingEntry::findOrFail($depense->accounting_entry_id)->lines->pluck('cost_center_id')->unique()->values()->all());
    }

    public function test_le_poste_ancien_a_plat_est_aussi_accepte_au_centre_general(): void
    {
        $this->actingAs($this->admin, 'sanctum')->postJson('/api/sync/push', ['expenses' => [[
            'id' => self::ID, 'expense_date' => '2026-06-15', 'label' => 'Carburant', 'category' => '614 - Transports',
            'amount' => 25_000, 'treasury_account_id' => $this->caisse->id,
        ]]])->assertOk()->assertJsonPath('expenses.accepted', [self::ID]);

        $this->assertSame(CostCenter::general()->id, Expense::findOrFail(self::ID)->cost_center_id);
    }

    public function test_un_renvoi_identique_d_un_poste_ancien_reste_acquitte_sans_rien_rejouer(): void
    {
        $doc = $this->document() + ['id' => self::ID];
        unset($doc['cost_center_id']);
        foreach ($doc['lines'] as $i => $ligne) {
            $doc['lines'][$i]['id'] = 'b2222222-bbbb-4bbb-8bbb-00000000000'.($i + 1);   // le poste envoie toujours l'identifiant de ses lignes
        }
        $envoi = fn () => $this->actingAs($this->admin, 'sanctum')->postJson('/api/sync/push', ['expenses' => [$doc]]);

        $envoi()->assertJsonPath('expenses.accepted', [self::ID]);
        $envoi()->assertJsonPath('expenses.accepted', [self::ID])->assertJsonPath('expenses.rejected', []);

        $this->assertSame(1, Expense::count());
        $this->assertSame(1, AccountingEntry::count());
        $this->assertEquals(440_000.0, (float) $this->caisse->fresh()->balance);
    }

    public function test_un_poste_migre_qui_envoie_le_choix_de_reglement_doit_envoyer_un_centre(): void
    {
        $doc = $this->document(['on_credit' => false]) + ['id' => self::ID];
        unset($doc['cost_center_id']);

        $reponse = $this->actingAs($this->admin, 'sanctum')->postJson('/api/sync/push', ['expenses' => [$doc]])->assertOk();

        $reponse->assertJsonPath('expenses.accepted', []);
        $this->assertStringContainsString('centre de coût', $reponse->json('expenses.rejected.0.reason'));
        $this->assertStringContainsString('obligatoire', $reponse->json('expenses.rejected.0.reason'));
        $this->assertSame(0, Expense::count());
        $this->assertSame(0, CostCenter::where('label', CostCenter::LIBELLE_GENERAL)->count(), 'aucun centre par défaut créé pour rien');
    }

    public function test_un_centre_inconnu_est_refuse_meme_pour_un_poste_ancien(): void
    {
        $doc = $this->document(['cost_center_id' => '11111111-1111-4111-8111-111111111111']) + ['id' => self::ID];

        $reponse = $this->actingAs($this->admin, 'sanctum')->postJson('/api/sync/push', ['expenses' => [$doc]])->assertOk();

        $this->assertSame([], $reponse->json('expenses.accepted'));
        $this->assertStringContainsString('centre de coût', $reponse->json('expenses.rejected.0.reason'));
    }

    public function test_la_migration_range_les_depenses_existantes_sans_centre_au_centre_general_sans_rien_perdre(): void
    {
        $depense = $this->action()->creer($this->document());
        $entreeId = $depense->accounting_entry_id;
        $lignesEcriture = AccountingEntry::findOrFail($entreeId)->lines()->count();
        // L'état d'avant : un centre jamais choisi, ni sur la dépense ni (donc) sur sa pièce.
        DB::table('expenses')->where('id', $depense->id)->update(['cost_center_id' => null]);
        DB::table('accounting_entry_lines')->where('accounting_entry_id', $entreeId)->update(['cost_center_id' => null]);
        $archivee = $this->action()->creer($this->document());
        DB::table('expenses')->where('id', $archivee->id)->update(['cost_center_id' => null, 'is_active' => false]);
        $this->assertSame(0, CostCenter::where('label', CostCenter::LIBELLE_GENERAL)->count());

        $migration = require database_path('migrations/2026_10_23_000001_dep6_centre_de_cout_obligatoire_et_depense_a_credit.php');
        $migration->up();
        $migration->up();   // rejouable : jamais de second « Général », jamais d'erreur

        $general = CostCenter::where('label', CostCenter::LIBELLE_GENERAL)->sole();
        $this->assertSame($general->id, $depense->fresh()->cost_center_id);
        $this->assertSame($general->id, $archivee->fresh()->cost_center_id, 'les archivées aussi');
        $this->assertSame(2, Expense::count(), 'aucune dépense perdue');
        $this->assertSame($entreeId, $depense->fresh()->accounting_entry_id, 'la pièce reste intacte');
        $this->assertSame($lignesEcriture, AccountingEntry::findOrFail($entreeId)->lines()->count());
        $this->assertSame(0, DB::table('accounting_entry_lines')->where('accounting_entry_id', $entreeId)->whereNotNull('cost_center_id')->count(), 'une écriture passée ne se réécrit JAMAIS');
        $this->assertSame(0, Expense::whereNull('cost_center_id')->count());
    }

    public function test_le_semoir_des_centres_cree_le_centre_general(): void
    {
        $this->seed(\Database\Seeders\CostCentersSeeder::class);
        $this->seed(\Database\Seeders\CostCentersSeeder::class);

        $this->assertSame(1, CostCenter::where('label', CostCenter::LIBELLE_GENERAL)->count());
        $this->assertSame(6, CostCenter::count(), '5 filières (dont « Cuniculture » déjà au décor) + « Général »');
    }
}
