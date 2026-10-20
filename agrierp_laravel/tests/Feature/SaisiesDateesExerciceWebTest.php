<?php

namespace Tests\Feature;

use App\Livewire\Achats\DettesFournisseurs;
use App\Livewire\Achats\ListeAchats;
use App\Livewire\Achats\ProfileFournisseur;
use App\Livewire\Achats\SaisieDepenses;
use App\Livewire\Stocks\GestionStocks;
use App\Livewire\Ventes\HistoriqueAvances;
use App\Livewire\Ventes\PosInterface;
use App\Models\AccountingEntry;
use App\Models\Payable;
use App\Models\Supplier;
use App\Models\SupplierPayment;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket EX6 (EF7 du PRD exercices comptables) — WEB D'ABORD (doctrine, article 5) : ce que le poste reprend doit
 * exister au web.
 *
 *  1. Le règlement fournisseur (« Dettes Fournisseurs ») n'attrapait pas `NoOpenFiscalYearException` /
 *     `ClosedFiscalYearException` : erreur 500 (EF6, oubli d'EX5). Le motif R4 va désormais sous « Date », comme la
 *     dépense et l'ajout de stock, et le Blade l'affiche.
 *  2. L'ajout de stock posait le motif R4 sous `addDate` (EX5) mais le Blade n'avait pas de `@error('addDate')` : le
 *     refus était INVISIBLE (rien d'écrit, modale muette).
 *  3. « Régulariser » depuis le profil fournisseur appelait une variable non définie (`$treasury`) APRÈS le règlement :
 *     erreur 500 à chaque règlement (le règlement passait, la page tombait), et le refus d'exercice n'était pas rattrapé.
 *  4. Les calendriers des saisies datées sont bornés aux exercices ouverts connus (EF7), comme la caisse (15.32) :
 *     début du plus ancien exercice OUVERT pour une saisie qui passe une écriture, lendemain du dernier exercice CLOS
 *     pour l'ajout de stock (`refusExerciceClos`).
 *
 * Décor : le 10/03/2027 ; 2024 clos, 2025 ouvert, 2026 ouvert (2025 pas encore clôturé, 2026 ouvert par le filet).
 */
class SaisiesDateesExerciceWebTest extends TestCase
{
    use PreparationExercices;
    use RefreshDatabase;

    private const CLOS_20_12_2024 = "L'exercice 2024 est clôturé : aucune saisie ne peut être datée du 20/12/2024.";

    private Supplier $fournisseur;

    protected function setUp(): void
    {
        parent::setUp();

        $this->preparerDecor('2027-03-10 09:30:00');
        $this->exercice(2024, 'cloture');
        $this->exercice(2025);
        $this->exercice(2026);

        $this->fournisseur = Supplier::create(['name' => 'Provenderie du Plateau', 'phone' => '97000011', 'is_active' => true]);
        Payable::create([
            'supplier_id' => $this->fournisseur->id, 'amount' => 90_000, 'amount_paid' => 0,
            'due_date' => '2025-06-30', 'status' => 'en_cours',
        ]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    /** Le champ date [$champ] du rendu porte `min="[$borne]"` (aucun `min` quand [$borne] est nul). */
    private function assertBorne($composant, string $champ, ?string $borne): void
    {
        $this->assertSame(1, preg_match('/<input wire:model="'.$champ.'" type="date"([^>]*)>/', $composant->html(), $m), "champ {$champ} introuvable");
        preg_match('/\bmin="([^"]*)"/', $m[1], $min);
        $this->assertSame($borne, $min[1] ?? null, "borne basse du champ {$champ}");
    }

    public function test_le_reglement_fournisseur_d_un_exercice_clos_affiche_le_motif_sous_la_date_sans_erreur_500(): void
    {
        $composant = Livewire::test(DettesFournisseurs::class)
            ->set('paymentSupplierId', $this->fournisseur->id)
            ->set('paymentAmount', 20_000)
            ->set('paymentDate', '2024-12-20')
            ->set('paymentTreasuryAccountId', $this->caisse->id)
            ->call('submitPaiementFournisseur');

        $this->assertErreurSousLeChamp($composant, 'paymentDate', self::CLOS_20_12_2024);
        $composant->assertSee(self::CLOS_20_12_2024);
        $this->assertEquals(0, (float) Payable::first()->amount_paid);
        $this->assertEquals(5_000_000, (float) $this->caisse->fresh()->balance);
        $this->assertSame(0, AccountingEntry::count());
    }

    public function test_le_reglement_fournisseur_d_un_jour_sans_exercice_affiche_le_motif_sous_la_date(): void
    {
        $composant = Livewire::test(DettesFournisseurs::class)
            ->set('paymentSupplierId', $this->fournisseur->id)
            ->set('paymentAmount', 20_000)
            ->set('paymentDate', '2023-06-15')
            ->set('paymentTreasuryAccountId', $this->caisse->id)
            ->call('submitPaiementFournisseur');

        $this->assertErreurSousLeChamp(
            $composant,
            'paymentDate',
            "Aucun exercice comptable ne couvre le 15/06/2023. Ouvrez l'exercice 2023 (Comptabilité › Clôture d'exercice).",
        );
        $this->assertEquals(0, (float) Payable::first()->amount_paid);
    }

    public function test_le_reglement_fournisseur_d_un_exercice_ouvert_passe_toujours(): void
    {
        Livewire::test(DettesFournisseurs::class)
            ->set('paymentSupplierId', $this->fournisseur->id)
            ->set('paymentAmount', 20_000)
            ->set('paymentDate', '2025-11-05')
            ->set('paymentTreasuryAccountId', $this->caisse->id)
            ->call('submitPaiementFournisseur')
            ->assertHasNoErrors()
            ->assertDispatched('toast', message: 'Règlement enregistré avec succès.', type: 'success');

        $this->assertEquals(20_000, (float) Payable::first()->amount_paid);
        $this->assertEquals(4_980_000, (float) $this->caisse->fresh()->balance);
        $this->assertSame('2025-11-05', AccountingEntry::first()->entry_date->format('Y-m-d'));
    }

    public function test_l_ajout_de_stock_d_un_exercice_clos_montre_le_motif_sous_la_date(): void
    {
        Livewire::test(GestionStocks::class)
            ->set('addDate', '2024-12-20')
            ->set('addProductId', $this->mais->id)
            ->set('addQty', 5)
            ->call('submitAjouterStock')
            ->assertSee(self::CLOS_20_12_2024);

        $this->assertEquals(0, (float) $this->mais->fresh()->stock_qty);
    }

    public function test_regulariser_depuis_le_profil_fournisseur_regle_une_fois_sans_erreur_500(): void
    {
        // Le règlement du profil est daté du jour (10/03/2027) : 2025 clôturé, 2027 ouvert.
        \App\Models\FiscalYear::where('year', 2025)->update(['status' => 'cloture']);
        $this->exercice(2027);

        Livewire::test(ProfileFournisseur::class, ['supplier' => $this->fournisseur])
            ->set('regularisationMontant', 30_000)
            ->set('regularisationTreasuryId', $this->caisse->id)
            ->call('confirmRegularisation')
            ->assertDispatched('toast', message: 'Règlement enregistré avec succès.', type: 'success');

        // Une seule sortie de caisse et UNE seule écriture 401 / 531 (le service la passe déjà).
        $this->assertEquals(30_000, (float) Payable::first()->amount_paid);
        $this->assertEquals(4_970_000, (float) $this->caisse->fresh()->balance);
        $this->assertSame(1, AccountingEntry::count());
        $this->assertSame(0, SupplierPayment::count());
    }

    public function test_regulariser_un_jour_sans_exercice_affiche_le_motif_en_toast_et_n_ecrit_rien(): void
    {
        // Le 10/03/2027 : 2025 et 2026 ouverts, 2027 ne peut pas s'ouvrir (deux exercices ouverts, R2).
        $attendu = "Aucun exercice comptable ne couvre le 10/03/2027. Ouvrez l'exercice 2027 (Comptabilité › Clôture d'exercice).";

        Livewire::test(ProfileFournisseur::class, ['supplier' => $this->fournisseur])
            ->set('regularisationMontant', 30_000)
            ->set('regularisationTreasuryId', $this->caisse->id)
            ->call('confirmRegularisation')
            ->assertDispatched('toast', message: $attendu, type: 'error');

        $this->assertEquals(0, (float) Payable::first()->amount_paid);
        $this->assertEquals(5_000_000, (float) $this->caisse->fresh()->balance);
        $this->assertSame(0, AccountingEntry::count());
    }

    public function test_les_calendriers_des_saisies_datees_sont_bornes_aux_exercices_ouverts(): void
    {
        // Saisies qui passent une écriture : début du plus ancien exercice OUVERT (2025).
        $this->assertBorne(Livewire::test(SaisieDepenses::class), 'expenseDate', '2025-01-01');
        $this->assertBorne(Livewire::test(DettesFournisseurs::class), 'paymentDate', '2025-01-01');
        $this->assertBorne(Livewire::test(ListeAchats::class), 'refundDate', '2025-01-01');
        $this->assertBorne(Livewire::test(HistoriqueAvances::class), 'advanceDate', '2025-01-01');
        // Ajout de stock (`refusExerciceClos`) : lendemain du dernier exercice CLOS (31/12/2024).
        $this->assertBorne(Livewire::test(GestionStocks::class), 'addDate', '2025-01-01');
        // La caisse garde sa borne (15.32), désormais lue au même point.
        $this->assertSame('2025-01-01', Livewire::test(PosInterface::class)->instance()->dateMin);
    }

    public function test_la_borne_de_l_ajout_de_stock_suit_le_dernier_exercice_clos_et_non_le_premier_ouvert(): void
    {
        // 2023 clos, 2024 ABSENT (reprise d'avant le logiciel), 2025 et 2026 ouverts : un ajout daté de 2024 est admis
        // par le serveur (aucun exercice ne le couvre), une dépense de 2024 ne l'est pas.
        \App\Models\FiscalYear::where('year', 2024)->delete();
        $this->exercice(2023, 'cloture');

        $this->assertBorne(Livewire::test(GestionStocks::class), 'addDate', '2024-01-01');
        $this->assertBorne(Livewire::test(SaisieDepenses::class), 'expenseDate', '2025-01-01');
    }

    public function test_sans_exercice_connu_aucun_calendrier_n_est_borne(): void
    {
        \App\Models\FiscalYear::query()->delete();

        $this->assertBorne(Livewire::test(SaisieDepenses::class), 'expenseDate', null);
        $this->assertBorne(Livewire::test(GestionStocks::class), 'addDate', null);
    }
}
