<?php

namespace App\Livewire\Ventes;

use App\Models\AuditLog;
use App\Models\Customer;
use App\Models\Quote;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 4.3 (Sprint 4) — devis.html → Livewire\Ventes\Devis
 * "Cycle de vie complet des devis : brouillon, envoi, acceptation et
 * conversion en facture."
 *
 * ⚠️ TABLE `quotes` AJOUTÉE, ABSENTE DU SCHÉMA DOCUMENTÉ — voir docblock
 * de la migration. Un devis y est une description libre + un montant
 * global, pas des lignes structurées de produits.
 *
 * Cycle de statut réel : Brouillon → Envoyé → Accepté/Refusé → Facturé.
 * Numérotation continue réelle (`Quote::generateQuoteNumber()`, même
 * principe que `LivestockLot::suggestNextCode()`, ticket 3.3).
 *
 * ⚠️ "CONVERTIR EN FACTURE" NON IMPLÉMENTÉ, SIGNALÉ EXPLICITEMENT : un
 * devis est une description libre sans lignes produit structurées,
 * contrairement à `sale_lines` qui exige un `product_id` réel. Convertir
 * un devis en vente nécessiterait soit de forcer une réconciliation
 * artificielle avec le catalogue produits, soit d'attendre le module
 * Facturation (Sprint 7) qui définira le bon mécanisme. Le bouton reste
 * visible pour un devis Accepté (fidélité au prototype) mais affiche un
 * message d'attente plutôt qu'une fausse conversion.
 *
 * 🔴→✅ TROUVÉ PAR COMPARAISON STRUCTURELLE RIGOUREUSE : le filtre
 * "Client" et le bouton "Exporter" de la barre d'outils étaient
 * totalement absents. Corrigés — `clientFilter` réutilise
 * `getCustomersProperty()` (déjà réel pour le formulaire Nouveau Devis),
 * `exportDevisPdf()` réutilise `PdfExportService`. Le champ de date
 * isolé du prototype et le bouton "Importer" restent volontairement non
 * ajoutés — le premier n'a aucune logique de filtrage claire même dans
 * le prototype source, le second nécessiterait une vraie fonctionnalité
 * d'import (voir même raisonnement documenté sur `GestionStocks`).
 */
class Devis extends Component
{
    #[Url]
    public string $search = '';

    #[Url]
    public string $statusFilter = '';

    // 🔴→✅ TROUVÉ ABSENT PAR COMPARAISON STRUCTURELLE RIGOUREUSE : le
    // filtre "Client" de la barre d'outils du prototype n'existait nulle
    // part — `getCustomersProperty()` était déjà réel (utilisé par le
    // formulaire Nouveau Devis) mais jamais réutilisé pour ce filtre.
    public string $clientFilter = '';

    public ?string $editingQuoteId = null;

    public string $customerId = '';

    public string $articlesDescription = '';

    public ?float $amount = null;

    public float $tvaRate = 18;

    public int $validityDays = 15;

    public string $quoteDate = '';

    public string $note = '';

    public function mount(): void
    {
        $this->quoteDate = now()->format('Y-m-d');
    }

    public function getKpisProperty(): array
    {
        $active = Quote::where('is_active', true)->whereIn('status', ['brouillon', 'envoye', 'accepte']);
        $totalMonth = Quote::where('is_active', true)->whereMonth('quote_date', now()->month)->whereYear('quote_date', now()->year);
        $accepted = (clone $totalMonth)->where('status', 'accepte')->count();
        $refusedOrAccepted = (clone $totalMonth)->whereIn('status', ['accepte', 'refuse'])->count();

        return [
            'devis_actifs' => (clone $active)->count(),
            'valeur_totale' => (float) (clone $active)->sum('amount'),
            'taux_conversion' => $refusedOrAccepted > 0 ? round(($accepted / $refusedOrAccepted) * 100) : 0,
            'en_attente_relance' => Quote::where('is_active', true)->where('status', 'envoye')->count(),
        ];
    }

    public function getCustomersProperty()
    {
        return Customer::where('is_active', true)->orderBy('name')->get();
    }

    public function getQuotesProperty()
    {
        return Quote::with('customer')
            ->where('is_active', true)
            ->when($this->search, fn ($q) => $q->where(fn ($q2) => $q2->where('quote_number', 'like', '%'.$this->search.'%')
                ->orWhereHas('customer', fn ($q3) => $q3->where('name', 'like', '%'.$this->search.'%'))))
            ->when($this->statusFilter, fn ($q) => $q->where('status', $this->statusFilter))
            ->when($this->clientFilter, fn ($q) => $q->where('customer_id', $this->clientFilter))
            ->orderByDesc('quote_date')
            ->get();
    }

    /**
     * 🔴→✅ TROUVÉ MANQUANT PAR COMPARAISON STRUCTURELLE RIGOUREUSE : le
     * bouton "Exporter" était totalement absent, alors que le prototype
     * le montre entre le filtre de date et "Nouveau Devis". Réutilise
     * `PdfExportService` (même pattern que `GestionStocks::exportStocksPdf()`).
     */
    public function exportDevisPdf()
    {
        $this->authorize('export-ventes');

        $quotes = $this->quotes;

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.devis',
            ['quotes' => $quotes],
            'Devis & Proforma',
            'État au '.now()->format('d/m/Y')
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'devis-'.now()->format('Y-m-d').'.pdf');
    }

    public function newQuote(): void
    {
        $this->reset(['editingQuoteId', 'customerId', 'articlesDescription', 'amount', 'note']);
        $this->tvaRate = 18;
        $this->validityDays = 15;
        $this->quoteDate = now()->format('Y-m-d');
        $this->dispatch('open-modal', name: 'modal-create-devis');
    }

    public function editQuote(string $id): void
    {
        $quote = Quote::findOrFail($id);
        $this->editingQuoteId = $quote->id;
        $this->customerId = (string) $quote->customer_id;
        $this->articlesDescription = $quote->articles_description;
        $this->amount = (float) $quote->amount;
        $this->tvaRate = (float) $quote->tva_rate;
        $this->validityDays = $quote->validity_days;
        $this->quoteDate = $quote->quote_date->format('Y-m-d');
        $this->note = (string) $quote->note;
        $this->dispatch('open-modal', name: 'modal-create-devis');
    }

    public function saveQuote(): void
    {
        $this->authorize('manage-ventes');
        $this->validate([
            'customerId' => ['required', 'exists:customers,id'],
            'articlesDescription' => ['required', 'string', 'max:2000'],
            'amount' => ['required', 'numeric', 'min:0'],
            'tvaRate' => ['required', 'numeric', 'min:0', 'max:100'],
            'validityDays' => ['required', 'integer', 'min:1'],
            'quoteDate' => ['required', 'date'],
        ]);

        $payload = [
            'customer_id' => $this->customerId,
            'articles_description' => $this->articlesDescription,
            'amount' => $this->amount,
            'tva_rate' => $this->tvaRate,
            'validity_days' => $this->validityDays,
            'quote_date' => $this->quoteDate,
            'note' => $this->note ?: null,
        ];

        if ($this->editingQuoteId) {
            Quote::findOrFail($this->editingQuoteId)->update($payload);
            AuditLog::record('quote.updated', 'ventes');
            $message = 'Devis modifié avec succès.';
        } else {
            $payload['quote_number'] = Quote::generateQuoteNumber();
            $payload['status'] = 'brouillon';
            $payload['is_active'] = true;
            Quote::create($payload);
            AuditLog::record('quote.created', 'ventes');
            $message = 'Devis créé avec succès.';
        }

        $this->dispatch('close-modal', name: 'modal-create-devis');
        $this->dispatch('toast', message: $message, type: 'success');
    }

    public function markAsSent(string $id): void
    {
        $this->authorize('manage-ventes');
        Quote::findOrFail($id)->update(['status' => 'envoye']);
        AuditLog::record('quote.sent', 'ventes');
        $this->dispatch('toast', message: 'Devis marqué comme envoyé.', type: 'success');
    }

    public function markAsAccepted(string $id): void
    {
        $this->authorize('manage-ventes');
        Quote::findOrFail($id)->update(['status' => 'accepte']);
        AuditLog::record('quote.accepted', 'ventes');
        $this->dispatch('toast', message: 'Devis marqué comme accepté.', type: 'success');
    }

    public function markAsRefused(string $id): void
    {
        $this->authorize('manage-ventes');
        Quote::findOrFail($id)->update(['status' => 'refuse']);
        AuditLog::record('quote.refused', 'ventes');
        $this->dispatch('toast', message: 'Devis marqué comme refusé.', type: 'warning');
    }

    public function convertToInvoice(string $id): void
    {
        $this->dispatch('toast', message: 'La conversion en facture réelle arrive avec le module Facturation (Sprint 7).', type: 'warning');
    }

    public function archiveQuote(string $id): void
    {
        $this->authorize('manage-ventes');
        Quote::findOrFail($id)->update(['is_active' => false]);
        AuditLog::record('quote.archived', 'ventes');
        $this->dispatch('toast', message: 'Devis archivé avec succès.', type: 'warning');
    }

    public function render()
    {
        return view('livewire.ventes.devis');
    }
}
