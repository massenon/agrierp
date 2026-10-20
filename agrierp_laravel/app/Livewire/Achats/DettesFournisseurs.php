<?php

namespace App\Livewire\Achats;

use App\Models\AuditLog;
use App\Services\SupplierSettlementService;
use App\Models\Payable;
use App\Models\Supplier;
use App\Models\TreasuryAccount;
use Illuminate\Support\Facades\DB;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 5.7 (Sprint 5) — dettes-fournisseurs.html → Livewire\Achats\DettesFournisseurs
 * DERNIER TICKET CONFIRMÉ DU SPRINT 5.
 * "Suivi des sommes dues aux fournisseurs et de leurs échéances."
 *
 * Un seul point de vérité : interroge directement `payables`, alimentée
 * réellement par `EnregistrerAchat` (5.2) et `BonsCommande` (5.5) —
 * aucune dette dupliquée ou ressaisie ici.
 *
 * "Statut" (À échoir / En retard / Réglé) utilise
 * `Payable::display_status` (même mécanisme que `Receivable`, ticket
 * 4.7) — jamais recalculé différemment.
 *
 * ⚠️ "ENREGISTRER UN RÈGLEMENT" — le formulaire source ne cible pas une
 * dette précise (juste Fournisseur + Montant + Date), ce qui implique une
 * allocation automatique. Implémentée en FIFO réel : le montant réglé est
 * appliqué aux dettes les plus anciennes du fournisseur d'abord
 * (`amount_paid` incrémenté jusqu'à épuisement du montant ou solde total
 * des dettes atteint), passant chaque dette soldée à `status = soldee`.
 *
 * ⚠️ CHAMP AJOUTÉ AU FORMULAIRE, JUSTIFIÉ : "Compte de Trésorerie" — le
 * prototype ne le demande pas, mais un règlement fait réellement sortir
 * de l'argent de la ferme ; sans ce champ, `treasury_accounts.balance`
 * n'aurait aucune source pour être décrémenté, contrairement à
 * `EnregistrerAchat` (5.2) et "Ajouter Remboursement" (5.4) qui l'exigent
 * déjà tous les deux pour la même raison.
 *
 * Édition/archivage d'une dette individuelle non implémentés : une
 * `Payable` est générée automatiquement par un achat ou une réception de
 * bon de commande — l'éditer ou l'archiver manuellement romprait le lien
 * avec sa source réelle sans bénéfice clair, contrairement à un
 * enregistrement saisi directement par l'utilisateur.
 */
class DettesFournisseurs extends Component
{
    use \App\Livewire\Concerns\BornesCalendrierExercice;

    #[Url]
    public string $search = '';

    #[Url]
    public string $statusFilter = '';

    public string $paymentSupplierId = '';

    public ?float $paymentAmount = null;

    public string $paymentDate = '';

    public string $paymentTreasuryAccountId = '';

    public function mount(): void
    {
        $this->paymentDate = now()->format('Y-m-d');
        $this->paymentTreasuryAccountId = (string) (TreasuryAccount::where('is_active', true)->first()?->id ?? '');
    }

    public function getKpisProperty(): array
    {
        $active = Payable::where('status', '!=', 'soldee')->get();
        $enRetard = $active->filter(fn ($p) => $p->display_status === 'en_retard');

        return [
            'dettes_totales' => (float) $active->sum('balance'),
            'en_retard' => (float) $enRetard->sum('balance'),
            'fournisseurs_concernes' => $active->pluck('supplier_id')->unique()->count(),
        ];
    }

    public function getDebtsProperty()
    {
        return Payable::with('supplier')
            ->when($this->search, fn ($q) => $q->whereHas('supplier', fn ($q2) => $q2->where('name', 'like', '%'.$this->search.'%')))
            ->orderByDesc('created_at')
            ->get()
            ->when($this->statusFilter === 'A echoir', fn ($rows) => $rows->filter(fn ($p) => $p->display_status === 'en_cours'))
            ->when($this->statusFilter === 'En retard', fn ($rows) => $rows->filter(fn ($p) => $p->display_status === 'en_retard'))
            ->when($this->statusFilter === 'Regle', fn ($rows) => $rows->filter(fn ($p) => $p->display_status === 'soldee'));
    }

    /**
     * 🔴→✅ TROUVÉ MANQUANT PAR COMPARAISON STRUCTURELLE RIGOUREUSE : le
     * bouton "Exporter PDF" était totalement absent — même schéma déjà
     * trouvé sur de nombreux écrans (Devis, GestionStocks, ListeAchats,
     * RegistreEmployes, FeuillePointage, GestionPaie).
     */
    public function exportDettesFournisseursPdf()
    {
        $this->authorize('view-achats');

        $debts = $this->debts;

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.dettes-fournisseurs',
            ['debts' => $debts],
            'Dettes Fournisseurs',
            'État au '.now()->format('d/m/Y')
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'dettes-fournisseurs-'.now()->format('Y-m-d').'.pdf');
    }

    public function getSuppliersProperty()
    {
        return Supplier::where('is_active', true)->orderBy('name')->get();
    }

    public function getTreasuryAccountsProperty()
    {
        return TreasuryAccount::where('is_active', true)->orderBy('label')->get();
    }

    public function openPaymentModal(): void
    {
        $this->reset(['paymentSupplierId', 'paymentAmount']);
        $this->paymentDate = now()->format('Y-m-d');
        $this->dispatch('open-modal', name: 'modal-create-dettes-fournisseurs');
    }

    public function submitPaiementFournisseur(): void
    {
        $this->authorize('manage-achats');
        $this->validate([
            'paymentSupplierId' => ['required', 'exists:suppliers,id'],
            'paymentAmount' => ['required', 'numeric', 'min:1'],
            'paymentDate' => ['required', 'date'],
            'paymentTreasuryAccountId' => ['required', 'exists:treasury_accounts,id'],
        ]);

        // ⚠️ TICKET 15.16 — L'IMPUTATION, LA TRÉSORERIE ET L'ÉCRITURE VIVENT DANS
        // `SupplierSettlementService`, partagé avec ProfileFournisseur et le poste.
        // 🔴→✅ Ticket EX6 (EF6, oubli d'EX5) — exercice clos ou absent : erreur 500. Le motif R4 va sous « Date », comme
        // la dépense et l'ajout de stock ; la transaction du service annulée, rien n'a bougé.
        try {
            app(SupplierSettlementService::class)->regler(
                $this->paymentSupplierId,
                (float) $this->paymentAmount,
                $this->paymentTreasuryAccountId,
                $this->paymentDate,
            );
        } catch (\App\Exceptions\NoOpenFiscalYearException|\App\Exceptions\ClosedFiscalYearException $e) {
            $this->addError('paymentDate', $e->getMessage());

            return;
        }

        $this->dispatch('close-modal', name: 'modal-create-dettes-fournisseurs');
        $this->dispatch('toast', message: 'Règlement enregistré avec succès.', type: 'success');
    }

    public function render()
    {
        return view('livewire.achats.dettes-fournisseurs');
    }
}
