<?php

namespace App\Livewire\Achats;

use App\Models\Payable;
use App\Models\Purchase;
use App\Models\PurchaseOrder;
use App\Models\Supplier;
use App\Models\TreasuryAccount;
use App\Services\SupplierSettlementService;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * ÉCRAN TROUVÉ NON-FIDÈLE PAR L'AUDIT DE FIDÉLITÉ (cross-check
 * systématique, sur demande explicite). profile-fournisseur.html →
 * Livewire\Achats\ProfileFournisseur
 *
 * 🔴→✅ Le prototype est une page STANDALONE à 3 onglets (Achats /
 * Dettes / Commandes, mise en page 35%/65% identique à Profil Client) —
 * PAS un simple tiroir d'analyse comme l'implémentait jusqu'ici
 * `FichesFournisseurs::view()`/`closeDrawer()`. Reconstruit fidèlement
 * en écran standalone, symétrique exact de `Livewire\Ventes\ProfileClient`
 * (même écran trouvé manquant lors d'une passe d'audit précédente).
 * `FichesFournisseurs` (le tiroir léger existant) n'est pas supprimé —
 * il reste utile comme aperçu rapide depuis la liste des fournisseurs —
 * mais ce n'est plus la seule façon d'atteindre le profil complet.
 *
 * "Enregistrer un règlement" réutilise EXACTEMENT la même logique FIFO
 * que `DettesFournisseurs::submitPaiementFournisseur()` (ticket 5.7) —
 * jamais une seconde implémentation du règlement fournisseur qui
 * pourrait diverger.
 */
#[Layout('layouts.app')]
class ProfileFournisseur extends Component
{
    public Supplier $supplier;

    #[Url]
    public string $tab = 'achats';

    public ?float $regularisationMontant = null;

    public string $regularisationTreasuryId = '';

    public function mount(Supplier $supplier): void
    {
        $this->supplier = $supplier;
    }

    public function getPurchasesProperty()
    {
        return Purchase::where('supplier_id', $this->supplier->id)->with('lines.product')->latest('purchase_date')->limit(20)->get();
    }

    public function getDebtsProperty()
    {
        return Payable::where('supplier_id', $this->supplier->id)
            ->whereColumn('amount_paid', '<', 'amount')
            ->orderBy('due_date')
            ->get();
    }

    public function getOrdersProperty()
    {
        return PurchaseOrder::where('supplier_id', $this->supplier->id)->latest()->limit(20)->get();
    }

    public function getSoldeGlobalProperty(): float
    {
        return round((float) $this->debts->sum(fn ($d) => $d->balance), 2);
    }

    public function getTreasuryAccountsProperty()
    {
        return TreasuryAccount::where('is_active', true)->orderBy('label')->get();
    }

    public function openRegularisation(): void
    {
        $this->regularisationMontant = null;
        $this->regularisationTreasuryId = '';
        $this->dispatch('open-modal', name: 'modal-regularisation-fournisseur');
    }

    /**
     * Même logique FIFO que DettesFournisseurs::submitPaiementFournisseur()
     * (ticket 5.7) — un seul point de vérité pour le règlement fournisseur.
     */
    public function confirmRegularisation(): void
    {
        $this->authorize('manage-achats');

        $this->validate([
            'regularisationMontant' => ['required', 'numeric', 'min:1'],
            'regularisationTreasuryId' => ['required', 'exists:treasury_accounts,id'],
        ]);

        // ⚠️ TICKET 15.16 — MÊME SERVICE QUE `DettesFournisseurs`. Cette copie retirait
        // de la trésorerie, et écrivait au journal, le montant SAISI en entier même
        // s'il dépassait les dettes ; seule la part imputée sort désormais.
        //
        // 🔴→✅ Ticket EX6 — le service passe DÉJÀ l'écriture 401 / 5xx et la ligne d'audit `payable.payment_recorded`
        // (15.16). Le bloc qui les refaisait ici appelait une variable non définie (`$treasury`) : chaque règlement
        // depuis le profil finissait en erreur 500 APRÈS avoir été enregistré (caisse débitée, page en erreur). Retiré.
        // Exercice clos ou absent (le règlement est daté du jour) : motif R4 en toast, rien n'est écrit (EF6).
        try {
            app(SupplierSettlementService::class)->regler(
                $this->supplier->id,
                (float) $this->regularisationMontant,
                $this->regularisationTreasuryId,
            );
        } catch (\App\Exceptions\NoOpenFiscalYearException|\App\Exceptions\ClosedFiscalYearException $e) {
            $this->dispatch('toast', message: $e->getMessage(), type: 'error');

            return;
        }

        // 🔴→✅ TICKET 14.3 — même défaut que `ProfileClient::confirmRegularisation`,
        // côté achats : `debts` ne retient que les dettes non soldées et a été
        // lue plus haut pour le règlement FIFO, donc mémoïsée. Une dette
        // intégralement réglée restait affichée, `soldeGlobal` avec elle.
        unset($this->debts, $this->soldeGlobal);

        $this->dispatch('close-modal', name: 'modal-regularisation-fournisseur');
        $this->dispatch('toast', message: 'Règlement enregistré avec succès.', type: 'success');
    }

    public function render()
    {
        return view('livewire.achats.profile-fournisseur', ['title' => 'Profil Fournisseur']);
    }
}
