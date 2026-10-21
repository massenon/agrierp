<?php

namespace App\Livewire\Ventes;

use App\Exceptions\AvoirClientRefuseException;
use App\Models\CreditNote;
use App\Models\Sale;
use App\Services\AvoirClientService;
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
 * 🔴→✅ TICKET AV1 — `saveReturn()` délègue à `AvoirClientService` (voir son docblock) : quantité bornée au vendu moins le
 * déjà retourné, montant borné à la ligne moins le déjà crédité, exercice clos ou plan incomplet refusés AVANT toute
 * écriture (le retour n'est plus « enregistré SANS écriture »), une seule transaction. Le même service reçoit les
 * demandes de retour des postes (`SyncController::pushCreditNotes`).
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

        // 🔴→✅ TICKET AV1 — UN SEUL POINT DE PASSAGE (`AvoirClientService`), partagé avec l'envoi d'un poste : mêmes
        // refus (quantité au-delà du vendu, montant au-delà de la ligne, exercice clos, plan comptable incomplet), mêmes
        // effets (avoir, stock si réintégré, écriture inverse 701/443/411), une seule transaction — un refus n'écrit rien.
        try {
            app(AvoirClientService::class)->enregistrer([
                'sale_id' => $this->saleId,
                'product_id' => $this->productId,
                'qty' => $this->qty,
                'amount' => $this->amount,
                'reason' => $this->reason,
                'decision' => $this->decision,
                'inspection_notes' => $this->inspectionNotes,
            ]);
        } catch (\App\Exceptions\ClosedFiscalYearException|\App\Exceptions\NoOpenFiscalYearException|AvoirClientRefuseException $e) {
            // Refus dit, jamais avalé : rien n'a été écrit (ni avoir, ni stock, ni écriture).
            $this->dispatch('toast', message: 'Retour refusé : '.$e->getMessage(), type: 'error');
            $this->dispatch('close-modal', name: 'modal-nouveau-retour');

            return;
        }

        $this->dispatch('close-modal', name: 'modal-nouveau-retour');
        $message = $this->decision === 'reintegre'
            ? 'Retour enregistré — produit réintégré au stock.'
            : 'Retour enregistré — produit réformé, aucun impact stock.';

        $this->dispatch('toast', message: $message.((float) $this->amount > 0
            ? ' Avoir comptabilisé (débit 701 / crédit 411).'
            : ' Avoir de montant nul : aucune écriture comptable.'), type: 'success');
    }

    public function markAsTreated(string $id): void
    {
        $this->authorize('manage-ventes');

        app(AvoirClientService::class)->marquerTraite(CreditNote::findOrFail($id));
        $this->dispatch('toast', message: 'Avoir marqué comme traité.', type: 'success');
    }

    public function render()
    {
        return view('livewire.ventes.retours-avoirs');
    }
}
