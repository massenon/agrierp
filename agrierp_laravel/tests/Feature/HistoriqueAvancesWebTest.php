<?php

namespace Tests\Feature;

use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\Customer;
use App\Models\CustomerAdvance;
use App\Models\FiscalYear;
use App\Models\Permission;
use App\Models\Receivable;
use App\Models\Role;
use App\Models\TreasuryAccount;
use App\Models\User;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.19 — LA PAGE WEB « HISTORIQUE DES AVANCES », DE BOUT EN BOUT.
 *
 * Aucun test n'existait pour cette page avant 15.19. Les tests « baseline » (premier
 * bloc) ont été écrits ET exécutés contre l'ANCIEN code avant tout changement : ils
 * décrivent ce que la page faisait et qui doit rester vrai. Le second bloc verrouille
 * les défauts corrigés par ce ticket (autorisations, trésorerie, écritures, plafonds).
 */
class HistoriqueAvancesWebTest extends TestCase
{
    use RefreshDatabase;

    private User $vendeur;

    private User $lecteur;

    private Customer $client;

    private TreasuryAccount $caisse;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-ventes', 'manage-ventes'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('vendeur', 'web')->givePermissionTo(['view-ventes', 'manage-ventes']);
        Role::findOrCreate('lecteur', 'web')->givePermissionTo(['view-ventes']);

        $this->vendeur = $this->utilisateur('vendeur');
        $this->lecteur = $this->utilisateur('lecteur');

        $this->client = Customer::create(['name' => 'AMOUSSOU Régis', 'phone' => '97123456', 'is_active' => true]);

        $this->caisse = TreasuryAccount::create([
            'label' => 'Caisse Physique', 'account_code' => '531',
            'type' => 'caisse', 'balance' => 100000, 'is_active' => true,
        ]);

        FiscalYear::create([
            'year' => (int) now()->format('Y'),
            'start_date' => now()->startOfYear()->toDateString(),
            'end_date' => now()->endOfYear()->toDateString(),
            'status' => 'ouvert',
        ]);

        foreach ([['411', 'Clients', 4], ['419', 'Avances et acomptes reçus', 4], ['531', 'Caisse', 5]] as [$code, $libelle, $classe]) {
            ChartOfAccount::firstOrCreate(['code' => $code], [
                'label' => $libelle, 'class' => $classe, 'is_active' => true,
            ]);
        }
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

    private function avance(float $montant, float $utilise = 0, array $plus = []): CustomerAdvance
    {
        return CustomerAdvance::create(array_merge([
            'customer_id' => $this->client->id,
            'amount' => $montant, 'amount_used' => $utilise,
            'advance_date' => now()->toDateString(), 'is_active' => true,
        ], $plus));
    }

    private function creance(float $montant, float $paye = 0): Receivable
    {
        return Receivable::create([
            'customer_id' => $this->client->id,
            'amount' => $montant, 'amount_paid' => $paye,
            'due_date' => now()->addDays(10)->toDateString(), 'status' => 'en_cours',
        ]);
    }

    // ---------------------------------------------------------------------
    // BASELINE — exécutés contre l'ancien code, doivent rester verts.
    // ---------------------------------------------------------------------

    public function test_baseline_l_imputation_est_plafonnee_au_solde_de_la_creance(): void
    {
        $avance = $this->avance(50000);
        $creance = $this->creance(30000);

        Livewire::actingAs($this->vendeur)->test(\App\Livewire\Ventes\HistoriqueAvances::class)
            ->call('openImputationModal', $avance->id)
            ->set('imputationReceivableId', $creance->id)
            ->set('imputationMontant', 40000)
            ->call('confirmImputation');

        $this->assertEquals(30000, $avance->fresh()->amount_used);
        $this->assertEquals(30000, $creance->fresh()->amount_paid);
    }

    public function test_baseline_l_imputation_est_plafonnee_au_reste_de_l_avance(): void
    {
        $avance = $this->avance(20000, 5000);
        $creance = $this->creance(90000);

        Livewire::actingAs($this->vendeur)->test(\App\Livewire\Ventes\HistoriqueAvances::class)
            ->call('openImputationModal', $avance->id)
            ->set('imputationReceivableId', $creance->id)
            ->set('imputationMontant', 80000)
            ->call('confirmImputation');

        $this->assertEquals(20000, $avance->fresh()->amount_used);
        $this->assertEquals(15000, $creance->fresh()->amount_paid);
    }

    public function test_baseline_une_creance_soldee_ne_recoit_rien(): void
    {
        $avance = $this->avance(20000);
        $creance = $this->creance(10000, 10000);

        Livewire::actingAs($this->vendeur)->test(\App\Livewire\Ventes\HistoriqueAvances::class)
            ->call('openImputationModal', $avance->id)
            ->set('imputationReceivableId', $creance->id)
            ->set('imputationMontant', 5000)
            ->call('confirmImputation')
            ->assertDispatched('toast');

        $this->assertEquals(0, $avance->fresh()->amount_used);
        $this->assertEquals(10000, $creance->fresh()->amount_paid);
    }

    public function test_baseline_les_indicateurs_et_les_filtres(): void
    {
        $this->avance(50000, 20000);                 // en cours, reste 30 000
        $this->avance(10000, 10000);                 // soldée

        $page = Livewire::actingAs($this->vendeur)->test(\App\Livewire\Ventes\HistoriqueAvances::class);

        $this->assertEquals(30000, $page->instance()->kpis['avances_en_cours']);
        $this->assertSame(1, $page->instance()->kpis['clients_concernes']);
        $this->assertSame(1, $page->instance()->kpis['avances_soldees_mois']);

        $this->assertCount(1, $page->set('statusFilter', 'En cours')->instance()->advances);
        $this->assertCount(1, $page->set('statusFilter', 'Soldée')->instance()->advances);
        $this->assertCount(2, $page->set('statusFilter', '')->instance()->advances);
    }

    public function test_baseline_archiver_une_avance_soldee_la_desactive_sans_la_supprimer(): void
    {
        $avance = $this->avance(10000, 10000);

        Livewire::actingAs($this->vendeur)->test(\App\Livewire\Ventes\HistoriqueAvances::class)
            ->call('archiveAdvance', $avance->id);

        $this->assertFalse($avance->fresh()->is_active);
        $this->assertNotNull(CustomerAdvance::find($avance->id));
    }

    public function test_baseline_la_validation_du_formulaire_refuse_un_montant_nul_et_un_client_absent(): void
    {
        Livewire::actingAs($this->vendeur)->test(\App\Livewire\Ventes\HistoriqueAvances::class)
            ->call('newAdvance')
            ->set('customerId', '')
            ->set('amount', 0)
            ->call('saveAdvance')
            ->assertHasErrors(['customerId', 'amount']);

        $this->assertSame(0, CustomerAdvance::count());
    }

    public function test_baseline_un_droit_de_lecture_ne_suffit_ni_a_enregistrer_ni_a_imputer_ni_a_archiver(): void
    {
        $avance = $this->avance(20000);
        $creance = $this->creance(10000);
        // Un composant neuf par tentative : après un 403 l'instantané de test est mort.
        $page = fn () => Livewire::actingAs($this->lecteur)->test(\App\Livewire\Ventes\HistoriqueAvances::class);

        foreach ([
            fn () => $page()->set('customerId', $this->client->id)->set('amount', 1000)
                ->set('advanceDate', now()->toDateString())->call('saveAdvance'),
            fn () => $page()->set('imputationTargetId', $avance->id)->set('imputationReceivableId', $creance->id)
                ->set('imputationMontant', 1000)->call('confirmImputation'),
            fn () => $page()->call('archiveAdvance', $avance->id),
        ] as $action) {
            $action()->assertForbidden();
        }

        $this->assertEquals(0, $avance->fresh()->amount_used);
        $this->assertTrue($avance->fresh()->is_active);
    }

    // ---------------------------------------------------------------------
    // DÉFAUTS CORRIGÉS PAR 15.19 (D1 à D5, D11)
    // ---------------------------------------------------------------------

    /** Recalcul INDÉPENDANT d'un solde du grand livre : Σ débits − Σ crédits des lignes du compte. */
    private function soldeGrandLivre(string $code): float
    {
        $compte = ChartOfAccount::where('code', $code)->firstOrFail();

        return round(
            (float) \App\Models\AccountingEntryLine::where('account_id', $compte->id)->sum('debit')
            - (float) \App\Models\AccountingEntryLine::where('account_id', $compte->id)->sum('credit'),
            2
        );
    }

    private function recevoirParLaPage(float $montant, array $plus = []): \Livewire\Features\SupportTesting\Testable
    {
        $page = Livewire::actingAs($this->vendeur)->test(\App\Livewire\Ventes\HistoriqueAvances::class)
            ->call('newAdvance')
            ->set('customerId', $this->client->id)
            ->set('amount', $montant)
            ->set('treasuryAccountId', $this->caisse->id);

        foreach ($plus as $propriete => $valeur) {
            $page->set($propriete, $valeur);
        }

        return $page->call('saveAdvance');
    }

    /** D2 — l'argent d'un acompte entre en caisse ET au grand livre, ensemble. */
    public function test_recevoir_une_avance_fait_entrer_l_argent_dans_les_deux_livres(): void
    {
        $this->recevoirParLaPage(25000, ['paymentMode' => 'mobile_money', 'motif' => 'Réservation 50 poussins'])
            ->assertHasNoErrors();

        $avance = CustomerAdvance::firstOrFail();
        $this->assertEquals(25000, $avance->amount);
        $this->assertEquals(0, $avance->amount_used);
        $this->assertSame($this->caisse->id, $avance->treasury_account_id);
        $this->assertSame('mobile_money', $avance->payment_mode);
        $this->assertSame('Réservation 50 poussins', $avance->motif);

        // Livre 1 : le solde du compte (100 000 avant).
        $this->assertEquals(125000, $this->caisse->fresh()->balance);
        // Livre 2 : classe 5 du grand livre — même variation, recalculée depuis les lignes.
        $this->assertEquals(25000.0, $this->soldeGrandLivre('531'));
        // Contrepartie : 419 créditeur, ni 701 ni 411.
        $this->assertEquals(-25000.0, $this->soldeGrandLivre('419'));
        $this->assertEquals(0.0, $this->soldeGrandLivre('411'));

        $ecriture = AccountingEntry::where('source_type', 'customer_advance')->sole();
        $this->assertSame($avance->id, $ecriture->source_id);
        $this->assertSame(now()->toDateString(), $ecriture->entry_date->toDateString());
    }

    public function test_l_ecriture_est_datee_du_jour_de_l_encaissement_pas_de_la_saisie(): void
    {
        $jour = now()->startOfYear()->addDays(3)->toDateString();

        $this->recevoirParLaPage(10000, ['advanceDate' => $jour]);

        $this->assertSame($jour, AccountingEntry::where('source_type', 'customer_advance')->sole()->entry_date->toDateString());
    }

    public function test_sans_compte_de_tresorerie_aucune_avance_n_est_creee(): void
    {
        Livewire::actingAs($this->vendeur)->test(\App\Livewire\Ventes\HistoriqueAvances::class)
            ->call('newAdvance')
            ->set('customerId', $this->client->id)
            ->set('amount', 5000)
            ->call('saveAdvance')
            ->assertHasErrors(['treasuryAccountId']);

        $this->assertSame(0, CustomerAdvance::count());
        $this->assertEquals(100000, $this->caisse->fresh()->balance);
    }

    public function test_un_exercice_clos_refuse_l_avance_sans_toucher_la_caisse(): void
    {
        FiscalYear::query()->update(['status' => 'cloture']);

        $this->recevoirParLaPage(5000)->assertDispatched('toast', type: 'error');

        $this->assertSame(0, CustomerAdvance::count(), "transaction annulée : pas d'avance sans écriture");
        $this->assertEquals(100000, $this->caisse->fresh()->balance);
        $this->assertSame(0, AccountingEntry::count());
    }

    public function test_sans_compte_419_l_argent_n_entre_pas_en_caisse(): void
    {
        ChartOfAccount::where('code', '419')->delete();

        $this->recevoirParLaPage(5000)->assertDispatched('toast', type: 'error');

        $this->assertSame(0, CustomerAdvance::count());
        $this->assertEquals(100000, $this->caisse->fresh()->balance);
    }

    /** D3 — l'imputation passe Débit 419 / Crédit 411, jamais de trésorerie, jamais à zéro. */
    public function test_imputer_passe_419_contre_411_sans_toucher_la_tresorerie(): void
    {
        $this->recevoirParLaPage(50000);
        $avance = CustomerAdvance::firstOrFail();
        $creance = $this->creance(30000);
        $caisseApres = $this->caisse->fresh()->balance;
        $ligne531Avant = $this->soldeGrandLivre('531');

        Livewire::actingAs($this->vendeur)->test(\App\Livewire\Ventes\HistoriqueAvances::class)
            ->call('openImputationModal', $avance->id)
            ->set('imputationReceivableId', $creance->id)
            ->set('imputationMontant', 40000)          // demandé 40 000, la créance n'en vaut que 30 000
            ->call('confirmImputation');

        $this->assertEquals(30000, $creance->fresh()->amount_paid);
        $this->assertEquals(30000, $avance->fresh()->amount_used);

        // L'écriture porte la part IMPUTÉE (30 000), pas la demande (40 000).
        $ecriture = AccountingEntry::where('source_type', 'advance_imputation')->sole();
        $this->assertEquals(30000, $ecriture->lines()->sum('debit'));
        $this->assertEquals(30000, $ecriture->lines()->sum('credit'));
        $this->assertEquals(-20000.0, $this->soldeGrandLivre('419'), '419 : 50 000 crédités, 30 000 débités');
        $this->assertEquals(-30000.0, $this->soldeGrandLivre('411'));

        // Aucune trésorerie : ni le solde du compte ni la classe 5 ne bougent.
        $this->assertEquals($caisseApres, $this->caisse->fresh()->balance);
        $this->assertEquals($ligne531Avant, $this->soldeGrandLivre('531'));
    }

    public function test_une_imputation_refusee_ne_laisse_aucune_ecriture_a_zero(): void
    {
        $avance = $this->avance(20000);
        $creance = $this->creance(10000, 10000);

        Livewire::actingAs($this->vendeur)->test(\App\Livewire\Ventes\HistoriqueAvances::class)
            ->call('openImputationModal', $avance->id)
            ->set('imputationReceivableId', $creance->id)
            ->set('imputationMontant', 5000)
            ->call('confirmImputation');

        $this->assertSame(0, AccountingEntry::count());
        $this->assertSame(0, \App\Models\AdvanceImputation::count());
    }

    /** D4 — le montant d'une avance entamée ou comptabilisée est figé. */
    public function test_le_montant_d_une_avance_entamee_ne_se_modifie_plus(): void
    {
        $avance = $this->avance(50000, 10000);   // entamée, non comptabilisée (ancienne)

        Livewire::actingAs($this->vendeur)->test(\App\Livewire\Ventes\HistoriqueAvances::class)
            ->call('editAdvance', $avance->id)
            ->set('amount', 99000)
            ->call('saveAdvance')
            ->assertDispatched('toast', type: 'error');

        $this->assertEquals(50000, $avance->fresh()->amount);
    }

    public function test_le_montant_d_une_avance_comptabilisee_ne_se_modifie_plus(): void
    {
        $this->recevoirParLaPage(50000);
        $avance = CustomerAdvance::firstOrFail();

        Livewire::actingAs($this->vendeur)->test(\App\Livewire\Ventes\HistoriqueAvances::class)
            ->call('editAdvance', $avance->id)
            ->set('amount', 60000)
            ->call('saveAdvance')
            ->assertDispatched('toast', type: 'error');

        $this->assertEquals(50000, $avance->fresh()->amount);
        $this->assertEquals(-50000.0, $this->soldeGrandLivre('419'), "l'écriture n'a pas divergé du montant");
    }

    public function test_une_ancienne_avance_intacte_reste_modifiable_comme_avant(): void
    {
        $avance = $this->avance(50000);          // ni entamée ni comptabilisée

        Livewire::actingAs($this->vendeur)->test(\App\Livewire\Ventes\HistoriqueAvances::class)
            ->call('editAdvance', $avance->id)
            ->set('amount', 60000)
            ->call('saveAdvance')
            ->assertDispatched('toast', type: 'success');

        $this->assertEquals(60000, $avance->fresh()->amount);
    }

    /** D5 — pas d'archivage tant qu'il reste quelque chose à imputer. */
    public function test_archiver_une_avance_avec_un_reste_est_refuse(): void
    {
        $avance = $this->avance(50000, 20000);   // reste 30 000

        Livewire::actingAs($this->vendeur)->test(\App\Livewire\Ventes\HistoriqueAvances::class)
            ->call('archiveAdvance', $avance->id)
            ->assertDispatched('toast', type: 'error');

        $this->assertTrue($avance->fresh()->is_active);
    }

    /** D11 — les trois méthodes qui n'exigeaient aucun droit l'exigent maintenant. */
    public function test_ouvrir_les_formulaires_exige_le_droit_manage_ventes(): void
    {
        $avance = $this->avance(20000);
        $page = fn () => Livewire::actingAs($this->lecteur)->test(\App\Livewire\Ventes\HistoriqueAvances::class);

        $page()->call('newAdvance')->assertForbidden();
        $page()->call('editAdvance', $avance->id)->assertForbidden();
        $page()->call('openImputationModal', $avance->id)->assertForbidden();
    }

    /** Sans le droit, rien ne bouge même si l'on contourne le formulaire. */
    public function test_un_droit_de_lecture_ne_recoit_pas_d_avance_meme_en_forcant_les_champs(): void
    {
        Livewire::actingAs($this->lecteur)->test(\App\Livewire\Ventes\HistoriqueAvances::class)
            ->set('customerId', $this->client->id)->set('amount', 5000)
            ->set('treasuryAccountId', $this->caisse->id)->set('advanceDate', now()->toDateString())
            ->call('saveAdvance')
            ->assertForbidden();

        $this->assertSame(0, CustomerAdvance::count());
        $this->assertEquals(100000, $this->caisse->fresh()->balance);
    }

    /**
     * La page ne PROPOSE que les créances du client de l'avance, mais le champ se poste : avant
     * 15.19, `exists:receivables,id` suffisait à imputer l'acompte de l'un sur la dette d'un autre.
     */
    public function test_une_avance_ne_solde_pas_la_creance_d_un_autre_client(): void
    {
        $autre = Customer::create(['name' => 'TOSSOU Marcel', 'is_active' => true]);
        $avance = $this->avance(20000);
        $creanceAutre = Receivable::create([
            'customer_id' => $autre->id, 'amount' => 10000, 'amount_paid' => 0,
            'due_date' => now()->addDays(10)->toDateString(), 'status' => 'en_cours',
        ]);

        Livewire::actingAs($this->vendeur)->test(\App\Livewire\Ventes\HistoriqueAvances::class)
            ->call('openImputationModal', $avance->id)
            ->set('imputationReceivableId', $creanceAutre->id)
            ->set('imputationMontant', 10000)
            ->call('confirmImputation')
            ->assertDispatched('toast', type: 'error');

        $this->assertEquals(0, $creanceAutre->fresh()->amount_paid);
        $this->assertEquals(0, $avance->fresh()->amount_used);
    }

    /** Une ancienne avance (jamais comptabilisée) s'impute quand même : 411 doit être soldé. */
    public function test_une_ancienne_avance_non_comptabilisee_s_impute_avec_son_ecriture(): void
    {
        $avance = $this->avance(20000);
        $creance = $this->creance(20000);

        Livewire::actingAs($this->vendeur)->test(\App\Livewire\Ventes\HistoriqueAvances::class)
            ->call('openImputationModal', $avance->id)
            ->set('imputationReceivableId', $creance->id)
            ->set('imputationMontant', 20000)
            ->call('confirmImputation');

        $this->assertEquals(20000, $creance->fresh()->amount_paid);
        $this->assertEquals(-20000.0, $this->soldeGrandLivre('411'));
    }
}
