<?php

namespace App\Livewire\Ventes;

use App\Exceptions\ClosedFiscalYearException;
use App\Exceptions\NoOpenFiscalYearException;
use App\Models\Customer;
use App\Models\CustomerAdvance;
use App\Models\TreasuryAccount;
use App\Services\CustomerAdvanceService;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * 🔴→✅ ÉCRAN TROUVÉ ENTIÈREMENT PLACEHOLDER PAR VÉRIFICATION NIVEAU 2 —
 * même constat que `SuiviDettes` : l'onglet "Historique Avances"
 * affichait encore `<x-module-pending since="Sprint 4 — ticket dédié à
 * venir">` alors que `CustomerAdvance` est réel depuis longtemps. Sur
 * demande explicite : "surtout pas de CRUD décoratives" — chaque bouton
 * ci-dessous mute réellement la base.
 *
 * ⚠️⚠️ TICKET 15.19 — TOUTE LA LOGIQUE VIT DANS `CustomerAdvanceService`, partagé avec
 * `/api/sync/push`. Cette page ne fait plus que valider le formulaire, appeler le service et
 * rendre ses refus. Défauts corrigés (voir le ticket) :
 *   - réceptionner une avance n'entrait NI en trésorerie NI au grand livre (D2) ;
 *   - imputer réduisait la créance sans écriture : 411 restait débité (D3) ;
 *   - le montant d'une avance déjà entamée pouvait être réécrit (D4) ;
 *   - une avance avec un reste pouvait être archivée (D5) ;
 *   - `newAdvance`, `editAdvance`, `openImputationModal` n'exigeaient aucun droit (D11).
 *
 * "Imputer" = consommation réelle de l'avance contre une créance choisie : incrémente
 * `amount_used` (jamais au-delà du reste) ET réduit le solde de la créance ciblée.
 *
 * "Archiver" = archivage logique (`is_active = false`) — jamais un DELETE physique.
 */
class HistoriqueAvances extends Component
{
    #[Url]
    public string $search = '';

    #[Url]
    public string $statusFilter = '';

    public ?string $editingAdvanceId = null;

    public string $customerId = '';

    public ?float $amount = null;

    public string $advanceDate = '';

    public string $treasuryAccountId = '';

    public string $paymentMode = '';

    public string $motif = '';

    public string $imputationTargetId = '';

    public string $imputationReceivableId = '';

    public float $imputationMax = 0;

    public ?float $imputationMontant = null;

    public function getKpisProperty(): array
    {
        $active = CustomerAdvance::where('is_active', true)->get();
        $enCours = $active->filter(fn ($a) => $a->remaining > 0);

        return [
            'avances_en_cours' => (float) $enCours->sum(fn ($a) => $a->remaining),
            'clients_concernes' => $enCours->pluck('customer_id')->unique()->count(),
            'avances_soldees_mois' => CustomerAdvance::where('is_active', true)
                ->whereColumn('amount_used', '>=', 'amount')
                ->where('updated_at', '>=', now()->startOfMonth())
                ->count(),
        ];
    }

    public function getAdvancesProperty()
    {
        return CustomerAdvance::with('customer')
            ->where('is_active', true)
            ->when($this->search, fn ($q) => $q->whereHas('customer', fn ($q2) => $q2->where('name', 'like', '%'.$this->search.'%')))
            ->get()
            ->when($this->statusFilter === 'En cours', fn ($rows) => $rows->filter(fn ($a) => $a->remaining > 0))
            ->when($this->statusFilter === 'Soldée', fn ($rows) => $rows->filter(fn ($a) => $a->remaining <= 0))
            ->sortByDesc('advance_date')
            ->values();
    }

    public function getCustomersProperty()
    {
        return Customer::where('is_active', true)->orderBy('name')->get();
    }

    public function getTreasuryAccountsProperty()
    {
        return TreasuryAccount::where('is_active', true)->orderBy('label')->get();
    }

    /** L'avance en cours de modification, ou null (sert à griser les champs figés — D4). */
    public function getEditingAdvanceProperty(): ?CustomerAdvance
    {
        return $this->editingAdvanceId ? CustomerAdvance::find($this->editingAdvanceId) : null;
    }

    public function getImputationReceivablesProperty()
    {
        if (! $this->imputationTargetId) {
            return collect();
        }

        $advance = CustomerAdvance::find($this->imputationTargetId);

        if (! $advance) {
            return collect();
        }

        return \App\Models\Receivable::where('customer_id', $advance->customer_id)
            ->whereColumn('amount_paid', '<', 'amount')
            ->get();
    }

    public function newAdvance(): void
    {
        $this->authorize('manage-ventes');

        $this->reset(['editingAdvanceId', 'customerId', 'amount', 'treasuryAccountId', 'paymentMode', 'motif']);
        $this->advanceDate = now()->format('Y-m-d');
        $this->dispatch('open-modal', name: 'modal-create-avance');
    }

    public function editAdvance(string $id): void
    {
        $this->authorize('manage-ventes');

        $advance = CustomerAdvance::findOrFail($id);
        $this->editingAdvanceId = $advance->id;
        $this->customerId = $advance->customer_id;
        $this->amount = (float) $advance->amount;
        $this->advanceDate = $advance->advance_date->format('Y-m-d');
        $this->dispatch('open-modal', name: 'modal-create-avance');
    }

    public function saveAdvance(): void
    {
        $this->authorize('manage-ventes');

        $regles = [
            'customerId' => ['required', 'exists:customers,id'],
            'amount' => ['required', 'numeric', 'min:1'],
            'advanceDate' => ['required', 'date'],
        ];

        // Compte, mode et motif ne concernent que la RÉCEPTION : une avance déjà reçue ne change
        // plus de caisse (l'écriture est passée).
        if (! $this->editingAdvanceId) {
            $regles['treasuryAccountId'] = ['required', 'exists:treasury_accounts,id'];
            $regles['paymentMode'] = ['nullable', Rule::in(CustomerAdvanceService::MODES_PAIEMENT)];
            $regles['motif'] = ['nullable', 'string', 'max:255'];
        }

        $this->validate($regles);

        $service = app(CustomerAdvanceService::class);

        try {
            if ($this->editingAdvanceId) {
                $service->modifier(
                    CustomerAdvance::findOrFail($this->editingAdvanceId),
                    $this->customerId, (float) $this->amount, $this->advanceDate,
                );
                $message = 'Avance modifiée avec succès.';
            } else {
                $service->recevoir(
                    $this->customerId, (float) $this->amount, $this->treasuryAccountId,
                    $this->advanceDate, $this->paymentMode ?: null, $this->motif ?: null,
                );
                $message = 'Avance enregistrée avec succès.';
            }
        } catch (ValidationException $e) {
            $this->dispatch('toast', message: collect($e->errors())->flatten()->implode(' '), type: 'error');

            return;
        } catch (NoOpenFiscalYearException|ClosedFiscalYearException $e) {
            $this->dispatch('toast', message: $e->getMessage(), type: 'error');

            return;
        }

        $this->dispatch('close-modal', name: 'modal-create-avance');
        $this->dispatch('toast', message: $message, type: 'success');
    }

    public function openImputationModal(string $advanceId): void
    {
        $this->authorize('manage-ventes');

        $advance = CustomerAdvance::findOrFail($advanceId);
        $this->imputationTargetId = $advance->id;
        $this->imputationMax = $advance->remaining;
        $this->imputationReceivableId = '';
        $this->imputationMontant = null;
        $this->dispatch('open-modal', name: 'modal-imputation');
    }

    /**
     * Consommation réelle : incrémente `amount_used` sur l'avance, réduit le solde de la créance
     * ciblée ET passe l'écriture Débit 419 / Crédit 411 — le tout par le service partagé.
     */
    public function confirmImputation(): void
    {
        $this->authorize('manage-ventes');

        $this->validate([
            'imputationReceivableId' => ['required', 'exists:receivables,id'],
            'imputationMontant' => ['required', 'numeric', 'min:1'],
        ]);

        try {
            app(CustomerAdvanceService::class)->imputer(
                $this->imputationTargetId, $this->imputationReceivableId, (float) $this->imputationMontant,
            );
        } catch (ValidationException $e) {
            $this->dispatch('toast', message: collect($e->errors())->flatten()->implode(' '), type: 'error');

            return;
        } catch (NoOpenFiscalYearException|ClosedFiscalYearException $e) {
            $this->dispatch('toast', message: $e->getMessage(), type: 'error');

            return;
        }

        $this->dispatch('close-modal', name: 'modal-imputation');
        $this->dispatch('toast', message: 'Avance imputée avec succès.', type: 'success');
    }

    public function archiveAdvance(string $id): void
    {
        $this->authorize('manage-ventes');

        try {
            app(CustomerAdvanceService::class)->archiver(CustomerAdvance::findOrFail($id));
        } catch (ValidationException $e) {
            $this->dispatch('toast', message: collect($e->errors())->flatten()->implode(' '), type: 'error');

            return;
        }

        $this->dispatch('toast', message: 'Avance archivée avec succès.', type: 'warning');
    }

    /** Même schéma d'export déjà établi sur de nombreux écrans de ce projet. */
    public function exportAvancesPdf()
    {
        $this->authorize('export-ventes');

        $advances = $this->advances;

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.historique-avances',
            ['advances' => $advances],
            'Historique des Avances',
            'État au '.now()->format('d/m/Y')
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'avances-'.now()->format('Y-m-d').'.pdf');
    }

    public function render()
    {
        return view('livewire.ventes.historique-avances');
    }
}
