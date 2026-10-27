<?php

namespace App\Livewire\Ventes;

use App\Models\AuditLog;
use App\Models\CustomerAdvance;
use App\Models\CustomerReminder;
use App\Services\CustomerSettlementService;
use App\Models\Receivable;
use App\Models\TreasuryAccount;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * 🔴→✅ ÉCRAN TROUVÉ ENTIÈREMENT PLACEHOLDER PAR VÉRIFICATION NIVEAU 2
 * (lecture ligne par ligne) — ce n'était pas un simple bouton d'export
 * manquant comme trouvé au balayage Niveau 3 précédent : l'onglet entier
 * "Suivi des Dettes" (`creances-clients-hub.blade.php`) affichait encore
 * `<x-module-pending since="Sprint 4 — ticket dédié à venir">` alors que
 * `Receivable` (ticket 4.7) et le mécanisme de règlement de
 * `ProfileClient` (audit précédent) sont réels depuis longtemps. Sur
 * demande explicite : "surtout pas de CRUD décoratives" — chaque action
 * ci-dessous mute réellement la base, aucun bouton qui ouvre juste une
 * modale sans effet.
 *
 * "Ajouter un Recouvrement" réutilise EXACTEMENT la même logique de
 * règlement que `ProfileClient::confirmRegularisation()` (un seul point
 * de vérité pour "comment règle-t-on une créance dans ce projet"),
 * appliquée ici à une créance choisie depuis la liste plutôt que depuis
 * la fiche client.
 *
 * "Relancer" réutilise `CustomerReminder`, la même table que
 * `RelancesClients` (Sprint 4) — jamais une seconde table de relances.
 *
 * "Taux de Recouvrement" = montant réellement encaissé ce mois / montant
 * total facturé ce mois, sur les ventes à crédit — pas une valeur
 * inventée, calculée depuis `Receivable.amount_paid` réel.
 */
class SuiviDettes extends Component
{
    #[Url]
    public string $search = '';

    #[Url]
    public string $ancienneteFilter = '';

    public string $paymentTargetId = '';

    public string $paymentTargetLabel = '';

    public float $paymentSolde = 0;

    public ?float $paymentMontant = null;

    public string $paymentTreasuryId = '';

    public function getKpisProperty(): array
    {
        $activeReceivables = Receivable::whereColumn('amount_paid', '<', 'amount')->get();

        $encoursGlobal = (float) $activeReceivables->sum(fn ($r) => $r->balance);
        $echus30j = (float) $activeReceivables->filter(fn ($r) => $r->days_overdue > 30)->sum(fn ($r) => $r->balance);

        $monthStart = now()->startOfMonth();
        $facturesDuMois = Receivable::where('created_at', '>=', $monthStart)->get();
        $tauxRecouvrement = $facturesDuMois->sum('amount') > 0
            ? round(($facturesDuMois->sum('amount_paid') / $facturesDuMois->sum('amount')) * 100, 1)
            : 0.0;

        $acomptesRecus = (float) CustomerAdvance::where('is_active', true)->where('advance_date', '>=', $monthStart)->sum('amount');   // avance archivée exclue

        return [
            'encours_global' => $encoursGlobal,
            'echus_30j' => $echus30j,
            'taux_recouvrement' => $tauxRecouvrement,
            'acomptes_recus' => $acomptesRecus,
        ];
    }

    public function getDebtsProperty()
    {
        return Receivable::with('customer', 'sale')
            ->whereColumn('amount_paid', '<', 'amount')
            ->when($this->search, fn ($q) => $q->whereHas('customer', fn ($q2) => $q2->where('name', 'like', '%'.$this->search.'%')))
            ->get()
            ->when($this->ancienneteFilter === 'saine', fn ($rows) => $rows->filter(fn ($r) => $r->days_overdue < 15))
            ->when($this->ancienneteFilter === 'retard', fn ($rows) => $rows->filter(fn ($r) => $r->days_overdue >= 15 && $r->days_overdue <= 30))
            ->when($this->ancienneteFilter === 'litige', fn ($rows) => $rows->filter(fn ($r) => $r->days_overdue > 30))
            ->sortByDesc(fn ($r) => $r->days_overdue)
            ->values();
    }

    public function getTreasuryAccountsProperty()
    {
        return TreasuryAccount::where('is_active', true)->orderBy('label')->get();
    }

    public function openPaymentModal(string $receivableId): void
    {
        $receivable = Receivable::with('customer')->findOrFail($receivableId);
        $this->paymentTargetId = $receivable->id;
        $this->paymentTargetLabel = $receivable->customer?->name.' — '.strtoupper(substr($receivable->sale_id ?? $receivable->id, 0, 8));
        $this->paymentSolde = $receivable->balance;
        $this->paymentMontant = null;
        $this->dispatch('open-modal', name: 'modal-add-payment');
    }

    /**
     * Ticket VC-1 — l'encaissement passe par `CustomerSettlementService`, le point de passage unique partagé avec la fiche
     * client (`ProfileClient::confirmRegularisation`) ET l'envoi des postes (`SyncController::pushReceivablePayments`) :
     * créance, trésorerie (deux livres), écriture et audit dans UNE transaction. Exercice clos ou absent : motif en toast,
     * rien n'est écrit.
     */
    public function confirmPayment(): void
    {
        $this->authorize('manage-ventes');

        $this->validate([
            'paymentMontant' => ['required', 'numeric', 'min:1'],
            'paymentTreasuryId' => ['required', 'exists:treasury_accounts,id'],
        ]);

        $receivable = Receivable::findOrFail($this->paymentTargetId);

        try {
            app(CustomerSettlementService::class)->encaisser(
                $receivable->customer_id,
                (float) $this->paymentMontant,
                $this->paymentTreasuryId,
                $receivable->id,
            );
        } catch (\App\Exceptions\NoOpenFiscalYearException|\App\Exceptions\ClosedFiscalYearException $e) {
            $this->dispatch('toast', message: $e->getMessage(), type: 'error');

            return;
        } catch (\Illuminate\Validation\ValidationException $e) {
            $this->dispatch('toast', message: $e->validator->errors()->first(), type: 'error');

            return;
        }

        $this->dispatch('close-modal', name: 'modal-add-payment');
        $this->dispatch('toast', message: 'Règlement enregistré avec succès.', type: 'success');
    }

    public function sendReminder(string $receivableId): void
    {
        $this->authorize('manage-ventes');

        $receivable = Receivable::with('customer')->findOrFail($receivableId);

        if (! $receivable->customer?->phone) {
            $this->dispatch('toast', message: 'Ce client n\'a pas de numéro de téléphone enregistré.', type: 'error');

            return;
        }

        CustomerReminder::create([
            'customer_id' => $receivable->customer_id,
            'receivable_id' => $receivable->id,
            'channel' => 'whatsapp',
            'reminder_date' => now(),
            'message' => 'Relance — solde dû '.number_format($receivable->balance, 0, ',', ' ').' FCFA.',
        ]);

        AuditLog::record('customer.reminder_sent', 'ventes');
        $this->dispatch('toast', message: 'Relance envoyée à '.$receivable->customer->name.'.', type: 'success');
    }

    /** Même schéma d'export déjà établi sur de nombreux écrans de ce projet. */
    public function exportCreancesPdf()
    {
        $this->authorize('export-ventes');

        $debts = $this->debts;

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.suivi-dettes',
            ['debts' => $debts],
            'Suivi des Dettes Clients',
            'État au '.now()->format('d/m/Y')
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'suivi-dettes-'.now()->format('Y-m-d').'.pdf');
    }

    public function render()
    {
        return view('livewire.ventes.suivi-dettes');
    }
}
