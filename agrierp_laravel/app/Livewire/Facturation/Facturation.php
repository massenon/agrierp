<?php

namespace App\Livewire\Facturation;

use App\Models\AuditLog;
use App\Models\Sale;
use App\Services\Mecef\FacturationMecefService;
use App\Support\ExerciceChoisi;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;
use Livewire\WithPagination;
use SimpleSoftwareIO\QrCode\Facades\QrCode;

/**
 * Ticket 7.1 (Sprint 7) — facturation.html → Livewire\Facturation\Facturation
 * "Émission de factures normalisées et transmission au système MeCeF
 * (DGI Bénin)."
 *
 * Un seul point de vérité : chaque vente validée (`sales`, réelle depuis
 * le ticket 4.2) EST une facture — jamais une table `invoices` parallèle
 * inventée. `mecef_status`/`mecef_qr_ref` (ticket 7.1) portent le statut
 * de transmission réel, alimenté par `MecefGatewayInterface` (voir
 * `PosInterface::validateSale()`, câblé dans ce même ticket).
 *
 * ⚠️ "NOUVELLE FACTURE" NON DUPLIQUÉE : le prototype propose un formulaire
 * de création indépendant (Client + Montant HT + TVA, sans article ni
 * produit), ce qui créerait une facture déconnectée de toute vente et de
 * tout stock — en contradiction directe avec la règle "vente à la pièce"
 * et le suivi produit par produit déjà appliqués partout ailleurs dans ce
 * projet (Document 01 §6.7). Le bouton redirige vers le POS (ticket 4.2),
 * seul point d'entrée réel pour créer une vente/facture.
 *
 * QR code réel (`simplesoftwareio/simple-qrcode`, Document 06 §7),
 * encodant `mecef_qr_ref` (NIM + signature).
 *
 * "Modifier" une facture non implémenté : une facture EST une vente déjà
 * validée, potentiellement déjà transmise à la DGI — la modifier après
 * coup romprait l'intégrité fiscale, contrairement à l'annulation déjà
 * réelle (`HistoriqueVentes::cancelSale()`, ticket 4.4).
 */
#[Layout('layouts.app')]
class Facturation extends Component
{
    use WithPagination;

    #[Url]
    public string $search = '';

    #[Url]
    public string $statusFilter = '';

    public ?string $viewingSaleId = null;

    /** Ticket VC-5 : le module MeCeF (transmission DGI) est-il activé ? Sinon la page est un registre de factures simple. */
    public function getMecefActifProperty(): bool
    {
        return (bool) config('mecef.actif');
    }

    public function getKpisProperty(): array
    {
        // Ticket EX7 — le mois de référence de l'exercice affiché (le mois du jour, ou le dernier mois de 2026 lu en 2027).
        $mois = ExerciceChoisi::moisDeReference();
        $monthSales = Sale::where('status', 'validee')
            ->soldBetween($mois, $mois->copy()->endOfMonth());

        if (! $this->mecefActif) {
            return [
                'factures_mois' => (clone $monthSales)->count(),
                'montant_mois' => (float) (clone $monthSales)->sum('total'),
                'clients_mois' => (clone $monthSales)->whereNotNull('customer_id')->distinct('customer_id')->count('customer_id'),
            ];
        }

        return [
            'factures_mois' => (clone $monthSales)->count(),
            'transmises' => (clone $monthSales)->where('mecef_status', 'transmise')->count(),
            'en_attente' => (clone $monthSales)->where('mecef_status', 'en_attente')->count(),
            'erreurs' => (clone $monthSales)->where('mecef_status', 'erreur')->count(),
        ];
    }

    /** Ticket EX7 (EF9) — les factures de l'exercice AFFICHÉ, PAGINÉES (25 par page), au lieu des 100 dernières. */
    public function getSalesProperty()
    {
        $statusMap = ['Transmise' => 'transmise', 'En attente' => 'en_attente', 'Erreur MeCeF' => 'erreur'];
        [$debut, $fin] = ExerciceChoisi::bornes();

        return Sale::with('customer')
            ->where('status', 'validee')
            ->soldBetween($debut, $fin)
            ->when($this->search, fn ($q) => $q->where(fn ($q2) => $q2->where('id', 'like', '%'.$this->search.'%')
                ->orWhereHas('customer', fn ($q3) => $q3->where('name', 'like', '%'.$this->search.'%'))))
            ->when($this->statusFilter, fn ($q) => $q->where('mecef_status', $statusMap[$this->statusFilter] ?? $this->statusFilter))
            ->orderByEffectiveDate()
            ->orderByDesc('id')
            ->paginate(ExerciceChoisi::PAR_PAGE, pageName: 'pageFactures');
    }

    /** Un filtre change : retour à la première page. */
    public function updating(string $propriete): void
    {
        if (in_array($propriete, ['search', 'statusFilter'], true)) {
            $this->resetPage('pageFactures');
        }
    }

    public function getViewingSaleProperty(): ?Sale
    {
        return $this->viewingSaleId ? Sale::with('customer')->find($this->viewingSaleId) : null;
    }

    public function getQrSvgProperty(): ?string
    {
        if (! $this->viewingSale || ! $this->viewingSale->mecef_qr_ref) {
            return null;
        }

        return QrCode::size(220)->generate($this->viewingSale->mecef_qr_ref);
    }

    public function showMecef(string $id): void
    {
        $this->viewingSaleId = $id;
        $this->dispatch('open-modal', name: 'modal-mecef');
    }

    /** Facture d'une vente en PDF — avec ou sans certification MeCeF. */
    public function imprimerFacture(string $id)
    {
        $this->authorize('view-facturation');

        $sale = Sale::with(['customer', 'lines.product'])->findOrFail($id);
        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.facture-vente',
            ['sale' => $sale],
            'Facture '.$sale->numero_facture,
            'Du '.$sale->date_effective->format('d/m/Y'),
            'portrait',
        );

        return response()->streamDownload(fn () => print ($pdf->output()), 'facture-'.$sale->numero_facture.'.pdf');
    }

    public function retryMecef(string $id): void
    {
        $this->authorize('manage-facturation');

        if (! $this->mecefActif) {
            $this->dispatch('toast', message: "Le module MeCeF n'est pas activé : aucune transmission possible.", type: 'warning');

            return;
        }

        $sale = Sale::findOrFail($id);

        // Ticket S-T13 — par le MÊME point que la caisse et l'envoi des postes : une vente déjà transmise (double
        // clic, page restée ouverte, deux retransmissions simultanées) ne l'est jamais une seconde fois.
        $result = app(FacturationMecefService::class)->facturer($sale);

        if ($result['deja']) {
            $this->dispatch('toast', message: $result['message'], type: 'warning');

            return;
        }

        AuditLog::record('sale.mecef_retried', 'facturation');
        $this->dispatch('toast', message: $result['message'], type: $result['transmise'] ? 'success' : 'error');
    }

    public function render()
    {
        // Ticket VC-5 : la facturation vit avec ou sans MeCeF ; le titre suit le module.
        return view('livewire.facturation.facturation', ['title' => $this->mecefActif ? 'Facturation & MeCeF' : 'Facturation']);
    }
}
