<?php

namespace Tests\Feature;

use App\Actions\RecordTreasuryTransferAction;
use App\Livewire\Parametres\ModesPaiement;
use App\Models\AccountingEntry;
use App\Models\AccountingEntryLine;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\Permission;
use App\Models\Role;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Services\FinancialReportService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.35 (Sprint 14) — VIREMENT INTERNE entre comptes de trésorerie.
 *
 * Fonction absente du prototype et du CDC, ajoutée parce que son manque est
 * structurel : la ferme encaisse en espèces et par Mobile Money mais règle ses
 * gros postes par la banque, sans pouvoir y déposer quoi que ce soit.
 *
 * Les deux propriétés qui comptent : le virement ne crée NI produit NI charge
 * (la richesse est inchangée), et il est REFUSÉ si les fonds manquent — à
 * l'inverse délibéré de la règle du stock (14.30), parce qu'un virement
 * n'entérine aucun fait déjà accompli.
 */
class VirementInterneTest extends TestCase
{
    use RefreshDatabase;

    private TreasuryAccount $caisse;

    private TreasuryAccount $banque;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-parametres', 'view-comptabilite', 'manage-comptabilite'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('comptable', 'web');
        $role->givePermissionTo(['view-parametres', 'view-comptabilite', 'manage-comptabilite']);

        $user = User::create([
            'name' => 'Comptable', 'email' => 'virement@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'),
        ]);
        $user->assignRole($role);
        $this->actingAs($user);

        FiscalYear::create([
            'year' => now()->year,
            'start_date' => now()->startOfYear()->format('Y-m-d'),
            'end_date' => now()->endOfYear()->format('Y-m-d'),
            'status' => 'ouvert',
        ]);

        foreach ([['531', 'Caisse'], ['521101', 'Banque']] as [$code, $label]) {
            ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => 5, 'is_active' => true]);
        }

        $this->caisse = TreasuryAccount::create([
            'type' => 'caisse', 'label' => 'Caisse Principale',
            'account_code' => '531', 'balance' => 1_000_000, 'is_active' => true,
        ]);

        $this->banque = TreasuryAccount::create([
            'type' => 'banque', 'label' => 'Compte Bancaire',
            'account_code' => '521101', 'balance' => 200_000, 'is_active' => true,
        ]);
    }

    private function soldeCompte(string $code): float
    {
        $compte = ChartOfAccount::where('code', $code)->firstOrFail();

        return round(
            (float) AccountingEntryLine::where('account_id', $compte->id)->sum('debit')
            - (float) AccountingEntryLine::where('account_id', $compte->id)->sum('credit'),
            2
        );
    }

    private function virer(float $montant, ?TreasuryAccount $source = null, ?TreasuryAccount $dest = null)
    {
        return Livewire::test(ModesPaiement::class)
            ->call('openTransfer')
            ->set('transferFromId', ($source ?? $this->caisse)->id)
            ->set('transferToId', ($dest ?? $this->banque)->id)
            ->set('transferAmount', $montant)
            ->set('transferReason', 'Dépôt des recettes de la semaine')
            ->call('submitTransfer');
    }

    /** Les deux soldes bougent, et le grand livre suit. */
    public function test_a_transfer_moves_both_balances_and_the_ledger(): void
    {
        $this->virer(600_000)->assertHasNoErrors();

        $this->assertEquals(400_000, (float) $this->caisse->fresh()->balance);
        $this->assertEquals(800_000, (float) $this->banque->fresh()->balance);

        $this->assertEquals(-600_000, $this->soldeCompte('531'), 'Le compte source est credite.');
        $this->assertEquals(600_000, $this->soldeCompte('521101'), 'Le destinataire est debite.');
        $this->assertEquals(1, AccountingEntry::where('source_type', 'treasury_transfer')->count());
    }

    /**
     * LA PROPRIÉTÉ CENTRALE : un virement ne crée ni produit ni charge.
     * L'argent change de poche, la richesse est inchangée.
     */
    public function test_a_transfer_creates_neither_income_nor_expense(): void
    {
        $reports = app(FinancialReportService::class);
        $avant = $reports->compteResultat(now()->format('Y-m-d'));
        $bilanAvant = $reports->bilan(now()->format('Y-m-d'));

        $this->virer(500_000);

        $apres = app(FinancialReportService::class)->compteResultat(now()->format('Y-m-d'));
        $bilanApres = app(FinancialReportService::class)->bilan(now()->format('Y-m-d'));

        $this->assertEquals($avant['resultat_net'], $apres['resultat_net'], 'Le resultat ne doit pas bouger.');
        $this->assertEquals($bilanAvant['total_tresorerie'], $bilanApres['total_tresorerie'],
            'Le total de tresorerie est inchange : l argent a seulement change de compte.');
        $this->assertTrue($bilanApres['is_balanced']);
    }

    /** Le total de trésorerie de la table est lui aussi conservé. */
    public function test_the_total_treasury_is_preserved(): void
    {
        $avant = (float) TreasuryAccount::sum('balance');

        $this->virer(750_000);

        $this->assertEquals($avant, (float) TreasuryAccount::sum('balance'));
    }

    /**
     * ⚠️ REFUS SI LES FONDS MANQUENT — l'inverse délibéré de la règle du stock.
     * Un virement n'entérine aucun fait accompli : rien n'oblige à
     * l'enregistrer.
     */
    public function test_a_transfer_beyond_the_available_balance_is_refused(): void
    {
        $this->virer(1_500_000)->assertHasErrors(['transferAmount']);

        $this->assertEquals(1_000_000, (float) $this->caisse->fresh()->balance, 'Rien ne doit bouger.');
        $this->assertEquals(200_000, (float) $this->banque->fresh()->balance);
        $this->assertEquals(0, AccountingEntry::count());
    }

    /** Virer un compte vers lui-même n'a aucun sens. */
    public function test_a_transfer_to_the_same_account_is_refused(): void
    {
        $this->virer(100_000, $this->caisse, $this->caisse)->assertHasErrors(['transferToId']);

        $this->assertEquals(0, AccountingEntry::count());
    }

    public function test_a_zero_or_negative_amount_is_refused(): void
    {
        $this->virer(0)->assertHasErrors(['transferAmount']);

        $this->assertEquals(0, AccountingEntry::count());
    }

    /**
     * ⚠️ ATOMICITÉ : soldes et écriture dans la même transaction. Un virement à
     * moitié appliqué ferait disparaître de l'argent — l'anomalie la plus
     * difficile à retrouver ensuite. Exercice comptable clos ⇒ rien ne bouge.
     */
    public function test_nothing_moves_when_the_entry_cannot_be_posted(): void
    {
        FiscalYear::query()->update(['status' => 'cloture']);

        $this->virer(300_000)->assertHasErrors(['transferAmount']);

        $this->assertEquals(1_000_000, (float) $this->caisse->fresh()->balance, 'Aucun solde ne doit avoir bouge.');
        $this->assertEquals(200_000, (float) $this->banque->fresh()->balance);
        $this->assertEquals(0, AccountingEntry::count());
    }

    /** Un profil sans droit comptable ne déplace pas d'argent. */
    public function test_a_user_without_accounting_rights_cannot_transfer(): void
    {
        $lecteur = User::create([
            'name' => 'Observateur', 'email' => 'lecture-param@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'),
        ]);
        $lectureSeule = Role::findOrCreate('observateur', 'web');
        $lectureSeule->givePermissionTo(['view-parametres', 'view-comptabilite']);
        $lecteur->assignRole($lectureSeule);

        $this->actingAs($lecteur);

        Livewire::test(ModesPaiement::class)
            ->set('transferFromId', $this->caisse->id)
            ->set('transferToId', $this->banque->id)
            ->set('transferAmount', 100_000)
            ->call('submitTransfer')
            ->assertForbidden();

        $this->assertEquals(1_000_000, (float) $this->caisse->fresh()->balance);
    }

    /** L'Action refuse elle-même les cas absurdes, sans dépendre de l'écran. */
    public function test_the_action_guards_itself(): void
    {
        $action = app(RecordTreasuryTransferAction::class);

        $this->expectException(\InvalidArgumentException::class);
        $action->execute($this->caisse, $this->caisse, 1_000);
    }
}
