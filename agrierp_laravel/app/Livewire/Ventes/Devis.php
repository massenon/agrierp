<?php

namespace App\Livewire\Ventes;

use App\Actions\ConvertirDevisEnFactureAction;
use App\Actions\SaisieDevisAction;
use App\Exceptions\ConversionDevisRefuseeException;
use App\Models\Customer;
use App\Models\Quote;
use App\Services\Mecef\FacturationMecefService;
use Livewire\Attributes\Url;
use Illuminate\Validation\ValidationException;
use Livewire\Component;

/**
 * Ticket DEV — les gestes d'écriture (créer, modifier, avancer dans le cycle, archiver) passent par UN point de
 * passage, `SaisieDevisAction`, que le poste rejoue à l'envoi (`SyncController::pushQuotes`) : mêmes règles, mêmes
 * messages, même audit. Nouveautés du ticket, côté web d'abord : un devis daté d'un exercice CLOS est refusé (motif R4,
 * sous « Date du Devis », ou en toast pour un changement de statut ou un archivage) ; un changement de statut hors du
 * cycle `brouillon → envoyé → accepté | refusé` est refusé avec son motif ; un devis archivé ou facturé ne se modifie plus.
 *
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
 * 🔴→✅ TICKET DEV3 — « CONVERTIR EN FACTURE » CONSTRUIT (il n'affichait qu'un toast d'attente). Un devis accepté
 * devient une facture : une vente à crédit SANS ligne (un devis est une prestation libre, pas un produit du catalogue :
 * `sale_lines` exige un `product_id`, qu'on ne force pas), à son total TTC, avec sa créance et son écriture de vente,
 * liée au devis (`converted_sale_id`, statut `facture`). Voir `ConvertirDevisEnFactureAction` et le PRD § 11.
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
        return Quote::with(['customer', 'sale'])
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

        $saisie = app(SaisieDevisAction::class);

        try {
            if ($this->editingQuoteId) {
                $saisie->modifier($this->editingQuoteId, $payload);
                $message = 'Devis modifié avec succès.';
            } else {
                $saisie->creer($payload);
                $message = 'Devis créé avec succès.';
            }
        } catch (ValidationException $e) {
            // Exercice clos : sous « Date du Devis » (motif R4). Devis archivé ou facturé : toast d'erreur.
            if (isset($e->errors()['quoteDate'])) {
                $this->addError('quoteDate', $e->errors()['quoteDate'][0]);
            } else {
                $this->dispatch('toast', message: $e->validator->errors()->first(), type: 'error');
            }

            return;
        }

        $this->dispatch('close-modal', name: 'modal-create-devis');
        $this->dispatch('toast', message: $message, type: 'success');
    }

    public function markAsSent(string $id): void
    {
        $this->authorize('manage-ventes');
        $this->changerStatut($id, 'envoye', 'Devis marqué comme envoyé.', 'success');
    }

    public function markAsAccepted(string $id): void
    {
        $this->authorize('manage-ventes');
        $this->changerStatut($id, 'accepte', 'Devis marqué comme accepté.', 'success');
    }

    public function markAsRefused(string $id): void
    {
        $this->authorize('manage-ventes');
        $this->changerStatut($id, 'refuse', 'Devis marqué comme refusé.', 'warning');
    }

    /**
     * Ticket DEV3 — « Convertir en Facture » (DEV-Q1 close) : un devis ACCEPTÉ devient une facture (une vente à crédit
     * sans ligne, `ConvertirDevisEnFactureAction`, le point de passage que la demande du poste rejoue aussi). Droits :
     * `manage-ventes` ET `manage-facturation`. Refus : toast d'erreur avec le motif. Déjà converti : toast d'avertissement
     * et AUCUNE seconde facture. La facture normalisée suit le circuit de toute vente (`FacturationMecefService`, après la
     * transaction) ; un échec ne défait rien : « Erreur MeCeF », à retransmettre depuis Facturation & MeCeF.
     */
    public function convertToInvoice(string $id): void
    {
        $this->authorize('manage-ventes');
        $this->authorize('manage-facturation');

        try {
            $resultat = app(ConvertirDevisEnFactureAction::class)->execute($id);
        } catch (ConversionDevisRefuseeException $e) {
            $this->dispatch('toast', message: $e->getMessage(), type: 'error');

            return;
        }

        $vente = $resultat['vente'];

        if ($resultat['deja']) {
            $this->dispatch('toast', message: 'Ce devis est déjà facturé : facture '.$vente->numero_facture.'.', type: 'warning');

            return;
        }

        $facture = app(FacturationMecefService::class)->facturer($vente);

        $this->dispatch('toast', message: 'Devis converti en facture '.$vente->numero_facture.' avec succès.', type: 'success');

        if (! $facture['transmise']) {
            $this->dispatch('toast', message: 'Facture '.$vente->numero_facture.' créée — ATTENTION : facture normalisée MeCeF non transmise ('.$facture['message'].'). La facture reste à transmettre : retransmettez-la depuis Facturation & MeCeF.', type: 'warning');
        }
    }

    public function archiveQuote(string $id): void
    {
        $this->authorize('manage-ventes');

        try {
            $resultat = app(SaisieDevisAction::class)->archiver($id);
        } catch (ValidationException $e) {
            $this->dispatch('toast', message: $e->validator->errors()->first(), type: 'error');

            return;
        }

        if ($resultat === SaisieDevisAction::ARCHIVE_MAINTENANT) {
            $this->dispatch('toast', message: 'Devis archivé avec succès.', type: 'warning');
        }
    }

    private function changerStatut(string $id, string $statut, string $message, string $type): void
    {
        try {
            app(SaisieDevisAction::class)->changerStatut($id, $statut);
        } catch (ValidationException $e) {
            $this->dispatch('toast', message: $e->validator->errors()->first(), type: 'error');

            return;
        }

        $this->dispatch('toast', message: $message, type: $type);
    }

    public function render()
    {
        return view('livewire.ventes.devis');
    }
}
