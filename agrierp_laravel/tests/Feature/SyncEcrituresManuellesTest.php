<?php

namespace Tests\Feature;

use App\Livewire\Comptabilite\JournalComptable;
use App\Models\AccountingEntry;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\PeriodicClosure;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket CP-2 — L'ÉCRITURE MANUELLE (opération diverse) SE DEMANDE AU POSTE.
 *
 * Le poste n'écrit pas l'écriture : il envoie la demande (créer, modifier, archiver) ; `SaisieEcritureManuelleAction`,
 * partagée avec `JournalComptable`, la joue avec les mêmes refus. Le numéro `OD-AAAA-NNNN` est attribué par le serveur.
 */
class SyncEcrituresManuellesTest extends TestCase
{
    use RefreshDatabase;

    private User $comptable;

    private User $lecteur;

    private ChartOfAccount $caisse;

    private ChartOfAccount $ventes;

    protected function setUp(): void
    {
        parent::setUp();

        Permission::findOrCreate('manage-comptabilite', 'web');
        Permission::findOrCreate('view-comptabilite', 'web');
        Role::findOrCreate('comptable', 'web')->givePermissionTo(['manage-comptabilite', 'view-comptabilite']);
        Role::findOrCreate('lecteur', 'web')->givePermissionTo('view-comptabilite');
        $this->comptable = $this->utilisateur('comptable');
        $this->lecteur = $this->utilisateur('lecteur');

        FiscalYear::create([
            'year' => (int) now()->format('Y'), 'start_date' => now()->startOfYear()->toDateString(),
            'end_date' => now()->endOfYear()->toDateString(), 'status' => 'ouvert',
        ]);
        $this->caisse = ChartOfAccount::firstOrCreate(['code' => '531'], ['label' => 'Caisse', 'class' => 5, 'is_active' => true]);
        $this->ventes = ChartOfAccount::firstOrCreate(['code' => '701'], ['label' => 'Ventes', 'class' => 7, 'is_active' => true]);
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
    private function demande(array $remplace = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(), 'action' => 'creer', 'entry_date' => now()->toDateString(),
            'label' => 'Régularisation de caisse', 'debit_account_id' => $this->caisse->id,
            'credit_account_id' => $this->ventes->id, 'amount' => 25000,
        ], $remplace);
    }

    private function envoyer(User $u, array $demandes)
    {
        return $this->actingAs($u, 'sanctum')->postJson('/api/sync/push', ['device_id' => 'poste-test', 'manual_entry_requests' => $demandes]);
    }

    public function test_une_creation_du_poste_produit_une_ecriture_numerotee_par_le_serveur_et_se_rejoue_sans_doublon(): void
    {
        $d = $this->demande();

        $this->envoyer($this->comptable, [$d])->assertOk()->assertJsonPath('manual_entry_requests.accepted.0', $d['id']);
        $this->envoyer($this->comptable, [$d])->assertOk()->assertJsonPath('manual_entry_requests.accepted.0', $d['id']);

        $this->assertSame(1, AccountingEntry::where('source_type', 'manual')->count());
        $ecriture = AccountingEntry::with('lines')->where('source_id', $d['id'])->firstOrFail();
        $this->assertMatchesRegularExpression('/^OD-\d{4}-\d+ — Régularisation de caisse$/', $ecriture->reference);
        $this->assertSame(25000.0, (float) $ecriture->lines->sum('debit'));
        $this->assertSame($this->caisse->id, $ecriture->lines->firstWhere('debit', '>', 0)->account_id);
        $this->assertSame($this->ventes->id, $ecriture->lines->firstWhere('credit', '>', 0)->account_id);
        $this->assertSame(1, AuditLog::where('action', 'accounting_entry.created')->count());
    }

    public function test_modifier_remplace_les_lignes_et_garde_le_numero_archiver_est_idempotent(): void
    {
        $d = $this->demande();
        $this->envoyer($this->comptable, [$d]);
        $ecriture = AccountingEntry::where('source_id', $d['id'])->firstOrFail();
        $numero = trim(explode('—', $ecriture->reference)[0]);

        $this->envoyer($this->comptable, [[
            'id' => (string) Str::uuid(), 'action' => 'modifier', 'entry_id' => $ecriture->id, 'entry_date' => now()->toDateString(),
            'label' => 'Correction', 'debit_account_id' => $this->ventes->id, 'credit_account_id' => $this->caisse->id, 'amount' => 30000,
        ]])->assertOk();

        $ecriture->refresh()->load('lines');
        $this->assertSame($numero.' — Correction', $ecriture->reference);
        $this->assertSame(30000.0, (float) $ecriture->lines->sum('debit'));
        $this->assertSame($this->ventes->id, $ecriture->lines->firstWhere('debit', '>', 0)->account_id);

        $arch = ['id' => (string) Str::uuid(), 'action' => 'archiver', 'entry_id' => $ecriture->id];
        $this->envoyer($this->comptable, [$arch])->assertOk()->assertJsonPath('manual_entry_requests.accepted.0', $arch['id']);
        $this->envoyer($this->comptable, [array_merge($arch, ['id' => (string) Str::uuid()])])->assertOk();
        $this->assertFalse($ecriture->fresh()->is_active);
        $this->assertSame(1, AuditLog::where('action', 'accounting_entry.archived')->count());
    }

    public function test_les_refus_du_web_sont_les_memes_avec_leur_motif(): void
    {
        $avant = AccountingEntry::count();

        $memeCompte = $this->envoyer($this->comptable, [$this->demande(['credit_account_id' => $this->caisse->id])])->assertOk();
        $this->assertSame('Le compte à créditer doit être différent du compte à débiter.', $memeCompte->json('manual_entry_requests.rejected.0.reason'));

        PeriodicClosure::create(['period' => now()->format('Y-m'), 'closed_at' => now()]);
        $mois = $this->envoyer($this->comptable, [$this->demande()])->assertOk();
        $this->assertStringContainsString('Ce mois est clôturé', $mois->json('manual_entry_requests.rejected.0.reason'));

        foreach ([['amount' => 0], ['label' => ''], ['debit_account_id' => (string) Str::uuid()]] as $mauvais) {
            $r = $this->envoyer($this->comptable, [$this->demande($mauvais)])->assertOk();
            $this->assertNotEmpty($r->json('manual_entry_requests.rejected.0.reason'), json_encode($mauvais));
        }

        $this->assertSame($avant, AccountingEntry::count());
    }

    public function test_une_ecriture_verrouillee_ne_se_modifie_ni_ne_s_archive_depuis_le_poste(): void
    {
        $d = $this->demande();
        $this->envoyer($this->comptable, [$d]);
        $ecriture = AccountingEntry::where('source_id', $d['id'])->firstOrFail();
        $ecriture->update(['is_locked' => true]);

        $r = $this->envoyer($this->comptable, [['id' => (string) Str::uuid(), 'action' => 'archiver', 'entry_id' => $ecriture->id]])->assertOk();

        $this->assertStringContainsString('verrouillée', $r->json('manual_entry_requests.rejected.0.reason'));
        $this->assertTrue($ecriture->fresh()->is_active);
    }

    public function test_sans_droit_manage_comptabilite_tout_est_refuse_avec_une_raison(): void
    {
        $avant = AccountingEntry::count();
        $r = $this->envoyer($this->lecteur, [$this->demande()])->assertOk();

        $this->assertStringContainsString('votre rôle ne permet pas', mb_strtolower($r->json('manual_entry_requests.rejected.0.reason')));
        $this->assertSame($avant, AccountingEntry::count());
    }

    public function test_la_page_web_passe_par_la_meme_action(): void
    {
        $this->actingAs($this->comptable);

        Livewire::test(JournalComptable::class)
            ->call('newEntry')
            ->set('entryDate', now()->toDateString())->set('label', 'Saisie web')
            ->set('debitAccountId', $this->caisse->id)->set('creditAccountId', $this->ventes->id)->set('amount', 1000)
            ->call('saveEntry')->assertHasNoErrors();

        $ecriture = AccountingEntry::where('source_type', 'manual')->firstOrFail();
        $this->assertStringEndsWith('— Saisie web', $ecriture->reference);

        Livewire::test(JournalComptable::class)
            ->call('newEntry')
            ->set('entryDate', now()->toDateString())->set('label', 'Même compte')
            ->set('debitAccountId', $this->caisse->id)->set('creditAccountId', $this->caisse->id)->set('amount', 1000)
            ->call('saveEntry')->assertHasErrors(['creditAccountId']);

        Livewire::test(JournalComptable::class)->call('archiveEntry', $ecriture->id);
        $this->assertFalse($ecriture->fresh()->is_active);
        $this->assertSame(1, AuditLog::where('action', 'accounting_entry.archived')->count());
    }
}
