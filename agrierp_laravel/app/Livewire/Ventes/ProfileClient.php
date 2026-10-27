<?php

namespace App\Livewire\Ventes;

use App\Models\AuditLog;
use App\Models\Customer;
use App\Models\CustomerAdvance;
use App\Models\CustomerReminder;
use App\Actions\RecordSettlementAccountingEntryAction;
use App\Models\Receivable;
use App\Models\TreasuryAccount;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * ÉCRAN TROUVÉ MANQUANT PAR L'AUDIT DE FIDÉLITÉ (cross-check systématique
 * des 94 écrans prototype vs vues Blade livrées, sur demande explicite).
 * profile-client.html → Livewire\Ventes\ProfileClient
 * "Fiche complète, historique et créances du tiers."
 *
 * N'était référencé par AUCUN hub comme onglet (contrairement à la
 * plupart des écrans "profile-*" de ce projet) — atteint depuis 4 écrans
 * différents (`devis.html`, `historique-avances.html`,
 * `relances-clients.html`, `suivi-dettes.html`) qui pointent tous vers
 * lui par lien direct. Construit ici comme route standalone
 * `/clients/{customer}/profil`, fidèle à cette réalité — jamais forcé
 * dans un tiroir/drawer comme le profil fournisseur (`FichesFournisseurs`),
 * ce dernier ayant une structure et un usage réellement différents.
 *
 * ⚠️ PREMIÈRE IMPLÉMENTATION RÉELLE DU RÈGLEMENT DE CRÉANCE CLIENT dans
 * tout ce projet — explicitement documentée comme "n'existe pas encore"
 * dans le docblock de `RelancesClients` (Sprint 4). `confirmRegularisation()`
 * incrémente réellement `receivables.amount_paid` (jamais au-delà du
 * solde dû) ET décrémente le compte de trésorerie choisi — même
 * discipline que chaque autre mouvement de trésorerie de ce projet
 * (jamais une case à cocher cosmétique).
 *
 * ⚠️ ÉCART DE SCHÉMA HONNÊTEMENT SIGNALÉ : le badge "Particulier" du
 * prototype suppose un champ de typologie client (Particulier/
 * Professionnel) qui n'existe pas dans `customers` (`name`, `phone`,
 * `email`, `city`, `credit_limit`, `is_active` uniquement) — omis
 * plutôt qu'une valeur inventée à chaque affichage.
 *
 * "Relance rapide" réutilise `CustomerReminder::create()`, la même table
 * que `RelancesClients` (Sprint 4) — un seul point de vérité pour la
 * traçabilité des relances, jamais une seconde table parallèle.
 */
#[Layout('layouts.app')]
class ProfileClient extends Component
{
    public Customer $customer;

    #[Url]
    public string $tab = 'ventes';

    public string $regularisationTarget = '';

    public string $regularisationLabel = '';

    public float $regularisationSolde = 0;

    public ?float $regularisationMontant = null;

    public string $regularisationTreasuryId = '';

    public function mount(Customer $customer): void
    {
        $this->customer = $customer;
    }

    public function getSalesProperty()
    {
        return $this->customer->sales()->with('lines.product')->orderByEffectiveDate()->limit(20)->get();
    }

    public function getReceivablesProperty()
    {
        return Receivable::where('customer_id', $this->customer->id)
            ->whereColumn('amount_paid', '<', 'amount')
            ->orderBy('due_date')
            ->get();
    }

    public function getAdvancesProperty()
    {
        return CustomerAdvance::where('customer_id', $this->customer->id)->latest('advance_date')->get();
    }

    public function getRemindersProperty()
    {
        return CustomerReminder::where('customer_id', $this->customer->id)->latest('reminder_date')->get();
    }

    public function getSoldeGlobalProperty(): float
    {
        return round((float) $this->receivables->sum(fn ($r) => $r->balance), 2);
    }

    public function getTreasuryAccountsProperty()
    {
        return TreasuryAccount::where('is_active', true)->orderBy('label')->get();
    }

    /** "Enregistrer un règlement" (solde global) — pas de créance précise ciblée. */
    public function openGlobalRegularisation(): void
    {
        $this->regularisationTarget = '';
        $this->regularisationLabel = 'Solde global';
        $this->regularisationSolde = $this->soldeGlobal;
        $this->regularisationMontant = null;
        $this->dispatch('open-modal', name: 'modal-regularisation');
    }

    /** "Régler" depuis l'onglet Créances — cible une facture précise. */
    public function openReceivableRegularisation(string $receivableId): void
    {
        $receivable = Receivable::findOrFail($receivableId);
        $this->regularisationTarget = $receivable->id;
        $this->regularisationLabel = strtoupper(substr($receivable->sale_id ?? $receivable->id, 0, 8));
        $this->regularisationSolde = $receivable->balance;
        $this->regularisationMontant = null;
        $this->dispatch('open-modal', name: 'modal-regularisation');
    }

    /**
     * Ticket VC-1 — l'encaissement passe par `CustomerSettlementService` (une créance précise, ou le solde global en
     * FIFO), comme « Ajouter un Recouvrement » et l'envoi des postes.
     */
    public function confirmRegularisation(): void
    {
        $this->authorize('manage-ventes');

        $this->validate([
            'regularisationMontant' => ['required', 'numeric', 'min:1'],
            'regularisationTreasuryId' => ['required', 'exists:treasury_accounts,id'],
        ]);

        try {
            app(\App\Services\CustomerSettlementService::class)->encaisser(
                $this->customer->id,
                (float) $this->regularisationMontant,
                $this->regularisationTreasuryId,
                $this->regularisationTarget !== '' ? $this->regularisationTarget : null,
            );
        } catch (\App\Exceptions\NoOpenFiscalYearException|\App\Exceptions\ClosedFiscalYearException $e) {
            $this->dispatch('toast', message: $e->getMessage(), type: 'error');

            return;
        } catch (\Illuminate\Validation\ValidationException $e) {
            $this->dispatch('toast', message: $e->validator->errors()->first(), type: 'error');

            return;
        }

        // 🔴→✅ TICKET 14.3 — `receivables` ne retient que les créances NON soldées : mémoïsée pour la requête, elle
        // restait affichée après un règlement complet, `soldeGlobal` avec elle.
        unset($this->receivables, $this->soldeGlobal);

        $this->dispatch('close-modal', name: 'modal-regularisation');
        $this->dispatch('toast', message: 'Règlement enregistré avec succès.', type: 'success');
    }

    public function sendQuickReminder(): void
    {
        $this->authorize('manage-ventes');

        if (! $this->customer->phone) {
            $this->dispatch('toast', message: 'Ce client n\'a pas de numéro de téléphone enregistré.', type: 'error');

            return;
        }

        CustomerReminder::create([
            'customer_id' => $this->customer->id,
            'channel' => 'whatsapp',
            'reminder_date' => now(),
            'message' => 'Relance rapide — solde dû '.number_format($this->soldeGlobal, 0, ',', ' ').' FCFA.',
        ]);

        AuditLog::record('customer.quick_reminder_sent', 'ventes');
        $this->dispatch('toast', message: 'Relance rapide enregistrée.', type: 'success');
    }

    public function render()
    {
        return view('livewire.ventes.profile-client', ['title' => 'Profil Client']);
    }
}
