<?php

namespace App\Livewire\Ventes;

use App\Actions\AdjustStockAction;
use App\Actions\RecordCreditNoteAccountingEntryAction;
use App\Models\AuditLog;
use App\Models\CreditNote;
use App\Models\Product;
use App\Models\Sale;
use Livewire\Component;

/**
 * Ticket 4.5 (Sprint 4) — retours-avoirs.html → Livewire\Ventes\RetoursAvoirs
 * DERNIER ONGLET DU HUB VENTES & DEVIS.
 *
 * TABLE `credit_notes` ÉTENDUE, ÉCART SIGNALÉ — voir docblock de la
 * migration : le prototype implémente un assistant en 5 étapes avec une
 * décision Réintégré/Réforme (impact stock réel) et un statut de
 * traitement, non représentables avec le schéma minimal documenté.
 *
 * SIMPLIFICATION DÉLIBÉRÉE : assistant en 5 étapes (Facture/Articles/
 * Motif/Inspection/Validation) du prototype reproduit ici comme un seul
 * formulaire structuré en sections plutôt qu'un stepper multi-écrans —
 * aucun composant "wizard" générique n'existe encore dans ce projet, et
 * en créer un pour ce seul écran aurait été disproportionné. Les mêmes
 * données réelles sont capturées (facture source, produit + quantité
 * retournée, motif, décision, notes d'inspection).
 *
 * Impact réel de la décision :
 *   - Réintégré : le produit retourné est remis en stock
 *     (`products.stock_qty` incrémenté de la quantité retournée).
 *   - Réforme : aucun impact stock (produit détruit/non récupérable,
 *     ex. mortalité d'un sujet vivant retourné) — traçabilité seule.
 *
 * 🔴→✅ TICKET 14.27 — DEUX DÉFAUTS CORRIGÉS ICI.
 *
 * 1. **Aucune écriture comptable n'était générée.** L'étape 5 du prototype
 *    promet pourtant « ✅ Écriture comptable inverse · ✅ Mise à jour CA et
 *    créances » : seuls l'avoir et le mouvement de stock l'étaient. Le chiffre
 *    d'affaires ne baissait jamais d'un retour, quel qu'en soit le montant.
 *    Confié à `RecordCreditNoteAccountingEntryAction` (débit 701 + 443,
 *    crédit 411) — le composant orchestre, l'Action exécute.
 *
 * 2. **Aucune autorisation n'était vérifiée.** `saveReturn()` et
 *    `markAsTreated()` n'appelaient aucun `authorize()`, et la route du hub
 *    ne porte que `can:view-ventes`. Un profil en lecture seule pouvait donc
 *    créer un avoir, réintégrer du stock et solder un retour. Le masquage de
 *    menu n'est pas une autorisation (Document 03 §RBAC) : la garde est posée
 *    sur les deux méthodes qui écrivent.
 *
 * ⚠️ LIMITE ASSUMÉE — LE REMBOURSEMENT N'EST PAS COMPTABILISÉ. L'avoir crédite
 * le compte client (411) : il constate une dette envers le client, pas un
 * décaissement. Le règlement effectif (débit 411 / crédit trésorerie) exigerait
 * de demander PAR QUEL compte le client est remboursé — question que cet écran
 * ne pose nulle part, dans le prototype comme ici. `markAsTreated()` reste donc
 * un statut de traitement, jamais un mouvement de trésorerie déguisé.
 */
class RetoursAvoirs extends Component
{
    public string $saleId = '';

    public string $productId = '';

    public ?float $qty = null;

    public ?float $amount = null;

    public string $reason = '';

    public string $decision = 'reintegre';

    public string $inspectionNotes = '';

    public function getKpisProperty(): array
    {
        $monthNotes = CreditNote::whereMonth('created_at', now()->month)->whereYear('created_at', now()->year);
        $monthSalesCount = Sale::where('status', 'validee')
            ->soldBetween(now()->startOfMonth(), now()->endOfMonth())
            ->count();

        return [
            'retours_mois' => (clone $monthNotes)->count(),
            'montant_avoirs' => (float) (clone $monthNotes)->sum('amount'),
            'produits_retournes' => (int) (clone $monthNotes)->whereNotNull('qty')->sum('qty'),
            'taux_retour' => $monthSalesCount > 0 ? round(((clone $monthNotes)->count() / $monthSalesCount) * 100, 1) : 0.0,
        ];
    }

    public function getRecentSalesProperty()
    {
        return Sale::with('customer')->where('status', 'validee')->orderByEffectiveDate()->limit(50)->get();
    }

    public function getSelectedSaleProperty(): ?Sale
    {
        return $this->saleId ? Sale::with('lines.product')->find($this->saleId) : null;
    }

    public function getCreditNotesProperty()
    {
        return CreditNote::with(['sale.customer', 'product'])->orderByDesc('created_at')->get();
    }

    public function updatedSaleId(): void
    {
        $this->productId = '';
        $this->qty = null;
        $this->amount = null;
    }

    public function updatedProductId(): void
    {
        if (! $this->selectedSale) {
            return;
        }

        $line = $this->selectedSale->lines->firstWhere('product_id', $this->productId);

        if ($line) {
            $this->qty = (float) $line->qty;
            $this->amount = (float) $line->manual_total_amount;
        }
    }

    public function newReturn(): void
    {
        $this->reset(['saleId', 'productId', 'qty', 'amount', 'reason', 'inspectionNotes']);
        $this->decision = 'reintegre';
        $this->dispatch('open-modal', name: 'modal-nouveau-retour');
    }

    public function saveReturn(): void
    {
        // ⚠️ Garde posée sur la méthode qui ÉCRIT : la route du hub ne porte
        // que `can:view-ventes`, et rien d'autre ne protégeait cette action.
        $this->authorize('manage-ventes');

        $this->validate([
            'saleId' => ['required', 'exists:sales,id'],
            'productId' => ['required', 'exists:products,id'],
            'qty' => ['required', 'numeric', 'min:0.01'],
            'amount' => ['required', 'numeric', 'min:0'],
            'reason' => ['required', 'string', 'max:255'],
            'decision' => ['required', 'in:reintegre,reforme'],
        ]);

        $creditNote = CreditNote::create([
            'credit_note_number' => CreditNote::generateCreditNoteNumber(),
            'sale_id' => $this->saleId,
            'product_id' => $this->productId,
            'qty' => $this->qty,
            'amount' => $this->amount,
            'reason' => $this->reason,
            'decision' => $this->decision,
            'inspection_notes' => $this->inspectionNotes ?: null,
            'status' => 'en_attente',
        ]);

        if ($this->decision === 'reintegre') {
            $product = Product::find($this->productId);
            if ($product) {
                app(AdjustStockAction::class)->execute($product, (float) $this->qty, 'credit_note', $creditNote->id);
            }
        }

        // Écriture comptable inverse — la conséquence que le prototype annonce
        // à l'étape 5 de l'assistant et qui n'était pas produite.
        $ecriture = null;

        try {
            $ecriture = app(RecordCreditNoteAccountingEntryAction::class)
                ->execute($creditNote->load('product'));
        } catch (\App\Exceptions\ClosedFiscalYearException|\App\Exceptions\NoOpenFiscalYearException $e) {
            // Le retour reste enregistré (le produit est physiquement revenu),
            // mais l'anomalie comptable est DITE, jamais avalée en silence.
            $this->dispatch('toast', message: 'Retour enregistré SANS écriture comptable : '.$e->getMessage(), type: 'error');
            $this->dispatch('close-modal', name: 'modal-nouveau-retour');

            return;
        }

        AuditLog::record('credit_note.created', 'ventes');
        $this->dispatch('close-modal', name: 'modal-nouveau-retour');
        $message = $this->decision === 'reintegre'
            ? 'Retour enregistré — produit réintégré au stock.'
            : 'Retour enregistré — produit réformé, aucun impact stock.';

        if (! $ecriture) {
            $message .= ' Attention : écriture comptable non générée (plan comptable incomplet).';
            $this->dispatch('toast', message: $message, type: 'error');

            return;
        }

        $this->dispatch('toast', message: $message.' Avoir comptabilisé (débit 701 / crédit 411).', type: 'success');
    }

    public function markAsTreated(string $id): void
    {
        $this->authorize('manage-ventes');

        CreditNote::findOrFail($id)->update(['status' => 'traite']);
        AuditLog::record('credit_note.treated', 'ventes');
        $this->dispatch('toast', message: 'Avoir marqué comme traité.', type: 'success');
    }

    public function render()
    {
        return view('livewire.ventes.retours-avoirs');
    }
}
