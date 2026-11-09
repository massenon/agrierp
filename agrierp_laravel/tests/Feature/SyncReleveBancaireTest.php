<?php

namespace Tests\Feature;

use App\Models\BankStatementLine;
use App\Models\ChartOfAccount;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Ticket CP-5 — LE RELEVÉ BANCAIRE (CSV) S'IMPORTE DEPUIS LE POSTE, une seule fois par UUID d'import.
 */
class SyncReleveBancaireTest extends TestCase
{
    use RefreshDatabase;

    private User $comptable;

    private ChartOfAccount $banque;

    protected function setUp(): void
    {
        parent::setUp();

        Permission::findOrCreate('manage-comptabilite', 'web');
        Permission::findOrCreate('view-comptabilite', 'web');
        Role::findOrCreate('comptable', 'web')->givePermissionTo(['manage-comptabilite', 'view-comptabilite']);
        Role::findOrCreate('lecteur', 'web')->givePermissionTo('view-comptabilite');
        $this->comptable = $this->utilisateur('comptable');
        $this->banque = ChartOfAccount::create(['code' => '521', 'label' => 'Banque', 'class' => 5, 'is_active' => true]);
    }

    private function utilisateur(string $role): User
    {
        $u = User::create(['name' => $role, 'username' => $role, 'email' => $role.'@ferme.test', 'password' => bcrypt('x'), 'is_active' => true]);
        $u->assignRole($role);

        return $u;
    }

    private function envoyer(User $u, array $import)
    {
        return $this->actingAs($u, 'sanctum')->postJson('/api/sync/push', ['device_id' => 'poste-test', 'bank_statement_imports' => [$import]]);
    }

    private function import(array $remplace = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(), 'account_id' => $this->banque->id,
            "content" => "date;libellé;montant\n2026-10-05;Dépôt;125 000,50\n2026-10-09;Frais de tenue;-2500\nillisible\n",
        ], $remplace);
    }

    public function test_un_releve_est_importe_une_seule_fois_meme_rejoue(): void
    {
        $i = $this->import();

        $this->envoyer($this->comptable, $i)->assertOk()->assertJsonPath('bank_statement_imports.accepted.0', $i['id']);
        $this->envoyer($this->comptable, $i)->assertOk()->assertJsonPath('bank_statement_imports.accepted.0', $i['id']);

        $lignes = BankStatementLine::where('account_id', $this->banque->id)->orderBy('statement_date')->get();
        $this->assertCount(2, $lignes, 'la ligne illisible est ignorée, le rejeu ne duplique rien');
        $this->assertEquals(125000.5, (float) $lignes[0]->amount);
        $this->assertEquals(-2500.0, (float) $lignes[1]->amount);
        $this->assertSame($i['id'], $lignes[0]->import_id);
    }

    public function test_un_compte_inconnu_ou_un_lecteur_sont_refuses(): void
    {
        $r = $this->envoyer($this->comptable, $this->import(['account_id' => (string) Str::uuid()]));
        $this->assertNotEmpty($r->json('bank_statement_imports.rejected.0.reason'));

        $r = $this->envoyer($this->utilisateur('lecteur'), $this->import());
        $this->assertStringContainsString('ne permet pas', $r->json('bank_statement_imports.rejected.0.reason'));
        $this->assertSame(0, BankStatementLine::count());
    }

    public function test_les_lignes_de_releve_descendent_au_tirage(): void
    {
        $i = $this->import();
        $this->envoyer($this->comptable, $i)->assertOk();

        $lignes = $this->actingAs($this->comptable, 'sanctum')->getJson('/api/sync/pull')->assertOk()->json('bank_statement_lines');

        $this->assertCount(2, $lignes);
        $this->assertSame(['id', 'account_id', 'statement_date', 'label', 'amount'], array_keys($lignes[0]));
        $this->assertSame('2026-10-05', $lignes[0]['statement_date']);
    }
}
