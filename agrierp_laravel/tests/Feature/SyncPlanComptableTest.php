<?php

namespace Tests\Feature;

use App\Livewire\Comptabilite\PlanComptable;
use App\Models\AccountingEntry;
use App\Models\AccountingEntryLine;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket CP-1 — LE PLAN COMPTABLE S'ÉCRIT AU POSTE (créer, modifier, archiver un compte).
 *
 * `PlanComptableService`, partagé avec `Comptabilite\PlanComptable`, porte les règles du web : numéro unique, intitulé, classe 1
 * à 9, archivage refusé si le compte est utilisé par une écriture.
 */
class SyncPlanComptableTest extends TestCase
{
    use RefreshDatabase;

    private User $comptable;

    private User $lecteur;

    protected function setUp(): void
    {
        parent::setUp();

        Permission::findOrCreate('manage-comptabilite', 'web');
        Permission::findOrCreate('view-comptabilite', 'web');
        Role::findOrCreate('comptable', 'web')->givePermissionTo(['manage-comptabilite', 'view-comptabilite']);
        Role::findOrCreate('lecteur', 'web')->givePermissionTo('view-comptabilite');
        $this->comptable = $this->utilisateur('comptable');
        $this->lecteur = $this->utilisateur('lecteur');
    }

    private function utilisateur(string $role): User
    {
        $u = User::create([
            'name' => ucfirst($role), 'username' => $role, 'email' => $role.'@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    /** @return array<string, mixed> */
    private function compte(array $remplace = []): array
    {
        return array_merge(['id' => (string) Str::uuid(), 'code' => '6181', 'label' => 'Frais de déplacement', 'class' => 6], $remplace);
    }

    private function envoyer(User $u, array $comptes)
    {
        return $this->actingAs($u, 'sanctum')->postJson('/api/sync/push', ['device_id' => 'poste-test', 'chart_of_accounts' => $comptes]);
    }

    public function test_un_compte_du_poste_est_cree_avec_son_uuid_et_rejoue_sans_doublon(): void
    {
        $c = $this->compte();

        $this->envoyer($this->comptable, [$c])->assertOk()->assertJsonPath('chart_of_accounts.accepted.0', $c['id']);
        $this->envoyer($this->comptable, [$c])->assertOk()->assertJsonPath('chart_of_accounts.accepted.0', $c['id']);

        $this->assertSame(1, ChartOfAccount::where('code', '6181')->count());
        $cree = ChartOfAccount::findOrFail($c['id']);
        $this->assertSame('Frais de déplacement', $cree->label);
        $this->assertSame(6, (int) $cree->class);
        $this->assertTrue($cree->is_active);
        $this->assertSame(1, AuditLog::where('action', 'chart_of_account.created')->count());
    }

    public function test_une_modification_change_numero_intitule_et_classe(): void
    {
        $c = $this->compte();
        $this->envoyer($this->comptable, [$c]);

        $this->envoyer($this->comptable, [array_merge($c, ['code' => '6182', 'label' => 'Déplacements', 'class' => 6])])->assertOk()
            ->assertJsonPath('chart_of_accounts.accepted.0', $c['id']);

        $this->assertSame('6182', ChartOfAccount::findOrFail($c['id'])->code);
        $this->assertSame(1, AuditLog::where('action', 'chart_of_account.updated')->count());
    }

    public function test_les_refus_du_web_sont_les_memes_avec_leur_motif(): void
    {
        ChartOfAccount::create(['code' => '411', 'label' => 'Clients', 'class' => 4, 'is_active' => true]);
        $avant = ChartOfAccount::count();

        $doublon = $this->envoyer($this->comptable, [$this->compte(['code' => '411'])])->assertOk();
        $this->assertNotEmpty($doublon->json('chart_of_accounts.rejected.0.reason'));

        foreach ([['class' => 0], ['class' => 10], ['label' => ''], ['code' => '']] as $i => $mauvais) {
            $r = $this->envoyer($this->comptable, [$this->compte(array_merge(['code' => '7'.$i], $mauvais))])->assertOk();
            $this->assertNotEmpty($r->json('chart_of_accounts.rejected.0.reason'), json_encode($mauvais));
        }
        $this->assertSame($avant, ChartOfAccount::count(), 'aucun compte créé par un envoi refusé');
    }

    public function test_l_archivage_est_refuse_pour_un_compte_utilise_et_accepte_sinon(): void
    {
        $libre = $this->compte();
        $utilise = $this->compte(['code' => '6182']);
        $this->envoyer($this->comptable, [$libre, $utilise]);

        $exercice = FiscalYear::create(['year' => (int) now()->format('Y'), 'start_date' => now()->startOfYear()->toDateString(), 'end_date' => now()->endOfYear()->toDateString(), 'status' => 'ouvert']);
        $ecriture = AccountingEntry::create(['fiscal_year_id' => $exercice->id, 'entry_date' => now()->toDateString(), 'reference' => 'TEST-1', 'is_active' => true]);
        AccountingEntryLine::create(['entry_id' => $ecriture->id, 'account_id' => $utilise['id'], 'debit' => 1000, 'credit' => 0]);

        $r = $this->envoyer($this->comptable, [array_merge($libre, ['is_active' => false]), array_merge($utilise, ['is_active' => false])])->assertOk();

        $this->assertSame([$libre['id']], $r->json('chart_of_accounts.accepted'));
        $this->assertSame("Impossible d'archiver : ce compte est déjà utilisé dans au moins une écriture comptable.", $r->json('chart_of_accounts.rejected.0.reason'));
        $this->assertFalse(ChartOfAccount::findOrFail($libre['id'])->is_active);
        $this->assertTrue(ChartOfAccount::findOrFail($utilise['id'])->is_active);

        // Un envoi « actif » ne réactive rien ; le renvoi de l'archivage ne laisse pas une seconde trace.
        $this->envoyer($this->comptable, [array_merge($libre, ['is_active' => true])])->assertOk();
        $this->envoyer($this->comptable, [array_merge($libre, ['is_active' => false])])->assertOk();
        $this->assertFalse(ChartOfAccount::findOrFail($libre['id'])->is_active);
        $this->assertSame(1, AuditLog::where('action', 'chart_of_account.archived')->count());
    }

    public function test_sans_droit_manage_comptabilite_tout_est_refuse_avec_une_raison(): void
    {
        $avant = ChartOfAccount::count();
        $r = $this->envoyer($this->lecteur, [$this->compte()])->assertOk();

        $this->assertStringContainsString('votre rôle ne permet pas', mb_strtolower($r->json('chart_of_accounts.rejected.0.reason')));
        $this->assertSame($avant, ChartOfAccount::count());
    }

    public function test_la_page_web_passe_par_le_meme_service(): void
    {
        $this->actingAs($this->comptable);

        Livewire::test(PlanComptable::class)
            ->call('newAccount')
            ->set('code', '6183')->set('label', 'Frais divers')->set('class', '6')
            ->call('saveAccount')
            ->assertHasNoErrors();

        $compte = ChartOfAccount::where('code', '6183')->firstOrFail();
        $this->assertSame(1, AuditLog::where('action', 'chart_of_account.created')->count());

        Livewire::test(PlanComptable::class)->call('archiveAccount', $compte->id);
        $this->assertFalse($compte->fresh()->is_active);
        $this->assertSame(1, AuditLog::where('action', 'chart_of_account.archived')->count());
    }
}
