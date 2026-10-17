<?php

namespace App\Livewire\Rapports;

use App\Models\Product;
use App\Models\ProductCategory;
use App\Services\PdfExportService;
use Illuminate\Support\Facades\Response;
use Livewire\Attributes\On;
use Livewire\Component;

/**
 * Ticket 12.7 (Sprint 12, DERNIER ONGLET DU HUB RAPPORTS) —
 * rapport-stocks-synth.html → Livewire\Rapports\StocksSynth
 * "État consolidé des stocks et alertes."
 *
 * "Valeur Stock" = `stock_qty × Product::computePmp()` (extrait de
 * `GestionStocks`, ticket 6.2, dans ce même ticket vers `Product` —
 * un seul point de vérité, jamais une seconde implémentation du PMP).
 * Produits jamais achetés (PMP null) exclus de la valorisation plutôt
 * que comptés à zéro ou à une valeur inventée — signalé explicitement
 * dans la colonne plutôt que silencieusement absorbé dans le total.
 *
 * "Sous Seuil" = nombre de produits de la catégorie dont
 * `stock_qty <= alert_threshold` — même définition que `SeuilsAlerte`
 * (ticket 6.2), jamais recalculée différemment.
 *
 * ⚠️ Ce rapport est un ÉTAT (photographie du stock actuel), pas un
 * mouvement sur période — la période Du/Au partagée par le hub n'a pas
 * de sens ici (le stock n'a qu'une seule valeur : maintenant), fidèle au
 * prototype qui affiche les sélecteurs de date sans jamais les câbler à
 * un filtre réel. Recherche câblée sur le libellé de catégorie, fidèle
 * au champ de recherche du prototype.
 */
class StocksSynth extends Component
{
    public string $startDate;

    public string $endDate;

    public string $search = '';

    public function mount(string $startDate, string $endDate): void
    {
        $this->startDate = $startDate;
        $this->endDate = $endDate;
    }

    public function getRowsProperty()
    {
        return ProductCategory::where('is_active', true)
            ->when($this->search, fn ($q) => $q->where('label', 'like', '%'.$this->search.'%'))
            ->orderBy('label')
            ->get()
            ->map(function ($category) {
                $products = Product::where('category_id', $category->id)->where('is_active', true)->get();

                // Ticket 14.30 : plancher a zero — sans lui, un produit en stock
                // negatif reduisait la valeur de TOUTE sa categorie.
                $valeurStock = $products->sum(fn ($p) => $p->valeurStock() ?? 0);

                $sousSeuil = $products->filter(fn ($p) => $p->alert_threshold !== null && (float) $p->stock_qty <= (float) $p->alert_threshold)->count();

                $nonValorises = $products->filter(fn ($p) => $p->computePmp() === null && (float) $p->stock_qty > 0)->count();

                return [
                    'category' => $category,
                    'valeur_stock' => round($valeurStock, 2),
                    'sous_seuil' => $sousSeuil,
                    'non_valorises' => $nonValorises,
                    'negatifs' => $products->filter(fn ($p) => $p->stockEstNegatif())->count(),
                ];
            })
            ->filter(fn ($row) => $row['category']->products()->where('is_active', true)->exists());
    }

    #[On('export-report')]
    public function exportReport(string $format, string $startDate, string $endDate)
    {
        $this->authorize('export-rapports');

        $rows = $this->rows;

        if ($format === 'pdf') {
            $pdf = app(PdfExportService::class)->render(
                'exports.stocks-synth',
                ['rows' => $rows],
                'Rapport de Stocks — Synthèse',
                'État au '.now()->format('d/m/Y')
            );

            return response()->streamDownload(fn () => print($pdf->output()), 'rapport-stocks-'.now()->format('Y-m-d').'.pdf');
        }

        $csv = "Catégorie,Valeur Stock,Sous Seuil\n";
        foreach ($rows as $r) {
            $csv .= '"'.$r['category']->label.'",'.$r['valeur_stock'].','.$r['sous_seuil']."\n";
        }

        return Response::streamDownload(fn () => print($csv), 'rapport-stocks-'.now()->format('Y-m-d').'.csv', ['Content-Type' => 'text/csv']);
    }

    public function render()
    {
        return view('livewire.rapports.stocks-synth');
    }
}
