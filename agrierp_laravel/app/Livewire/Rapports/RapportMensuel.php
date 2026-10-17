<?php

namespace App\Livewire\Rapports;

use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Services\FinancialReportService;
use App\Services\VatDeclarationService;
use Carbon\Carbon;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 14.10 (Sprint 14) — rapport-mensuel.html → Livewire\Rapports\RapportMensuel
 * "Vue consolidée mensuelle des indicateurs clés."
 *
 * Écran en LECTURE SEULE, fidèle au prototype qui l'indique lui-même sur
 * chaque ligne : « Ce rapport est généré à partir des données réelles ; il ne
 * peut pas être modifié ici. » Aucune action mutante n'est donc exposée.
 *
 * ⚠️ AUCUN CALCUL PROPRE À CET ÉCRAN — chaque indicateur est délégué au point
 * de vérité qui le possède déjà :
 *   • Chiffre d'affaires  → `FinancialReportService::produitsPeriode()`
 *   • Charges             → `FinancialReportService::chargesPeriode()`
 *   • Trésorerie          → `FinancialReportService::bilan()`
 *   • TVA nette           → `VatDeclarationService::declaration()`
 *   • Effectif / mortalité → `livestock_lots` / `livestock_daily_entries`
 * Un rapport de synthèse est précisément l'écran où une seconde
 * implémentation d'un calcul finirait par contredire l'écran d'origine.
 *
 * ⚠️ LES 2 LIGNES DU PROTOTYPE SONT DES DONNÉES DE DÉMONSTRATION
 * (« Chiffre d'affaires 850 000 / 790 000 », « Résultat net 240 000 /
 * -190 000 ») écrites en dur dans le HTML. La STRUCTURE est conservée à
 * l'identique — colonnes Indicateur / mois courant / mois précédent /
 * Actions en lecture seule — mais le jeu de lignes devient l'ensemble des
 * indicateurs réellement calculables. Conserver exactement 2 lignes aurait
 * figé une limite de maquette dans un rapport de direction.
 */
#[Layout('layouts.app')]
class RapportMensuel extends Component
{
    /** Mois de référence, au format `YYYY-MM`. */
    #[Url]
    public string $periode = '';

    #[Url]
    public string $search = '';

    public function mount(): void
    {
        if ($this->periode === '') {
            $this->periode = now()->format('Y-m');
        }
    }

    public function getPeriodesProperty(): array
    {
        return collect(range(0, 11))
            ->mapWithKeys(function ($i) {
                $date = now()->startOfMonth()->subMonths($i);

                return [$date->format('Y-m') => ucfirst($date->translatedFormat('F Y'))];
            })
            ->all();
    }

    private function mois(int $decalage = 0): Carbon
    {
        return Carbon::createFromFormat('Y-m-d', $this->periode.'-01')
            ->startOfMonth()
            ->subMonths($decalage);
    }

    public function getMoisCourantLabelProperty(): string
    {
        return ucfirst($this->mois()->translatedFormat('F Y'));
    }

    public function getMoisPrecedentLabelProperty(): string
    {
        return ucfirst($this->mois(1)->translatedFormat('F Y'));
    }

    /**
     * Indicateurs du mois demandé, comparés au mois précédent.
     *
     * @return array<int, array{label: string, unite: string, courant: float, precedent: float, sens: string}>
     */
    public function getIndicateursProperty(): array
    {
        $lignes = [];

        foreach ([0 => 'courant', 1 => 'precedent'] as $decalage => $cle) {
            $debut = $this->mois($decalage)->format('Y-m-d');
            $fin = $this->mois($decalage)->endOfMonth()->format('Y-m-d');

            $reports = app(FinancialReportService::class);

            $ca = $reports->produitsPeriode($debut, $fin);
            $charges = $reports->chargesPeriode($debut, $fin);

            $valeurs[$cle] = [
                'ca' => $ca,
                'charges' => $charges,
                'resultat' => round($ca - $charges, 2),
                'tresorerie' => $reports->bilan($fin)['total_tresorerie'],
                'tva_nette' => app(VatDeclarationService::class)->declaration($debut, $fin)['tva_nette'],
                'effectif' => $this->effectifFinMois($fin),
                'mortalite' => $this->tauxMortalite($debut, $fin),
            ];
        }

        $definitions = [
            ['cle' => 'ca',          'label' => "Chiffre d'affaires",        'unite' => 'FCFA', 'sens' => 'hausse_bonne'],
            ['cle' => 'charges',     'label' => 'Charges',                   'unite' => 'FCFA', 'sens' => 'baisse_bonne'],
            ['cle' => 'resultat',    'label' => 'Résultat net',              'unite' => 'FCFA', 'sens' => 'hausse_bonne'],
            ['cle' => 'tresorerie',  'label' => 'Trésorerie (fin de mois)',  'unite' => 'FCFA', 'sens' => 'hausse_bonne'],
            ['cle' => 'tva_nette',   'label' => 'TVA nette',                 'unite' => 'FCFA', 'sens' => 'neutre'],
            ['cle' => 'effectif',    'label' => 'Effectif élevage',          'unite' => 'sujets', 'sens' => 'hausse_bonne'],
            ['cle' => 'mortalite',   'label' => 'Taux de mortalité',         'unite' => '%',    'sens' => 'baisse_bonne'],
        ];

        foreach ($definitions as $d) {
            $ligne = [
                'label' => $d['label'],
                'unite' => $d['unite'],
                'courant' => $valeurs['courant'][$d['cle']],
                'precedent' => $valeurs['precedent'][$d['cle']],
                'sens' => $d['sens'],
            ];

            if ($this->search === '' || str_contains(mb_strtolower($ligne['label']), mb_strtolower($this->search))) {
                $lignes[] = $ligne;
            }
        }

        return $lignes;
    }

    /** Effectif des bandes actives — photographié à la fin du mois demandé. */
    private function effectifFinMois(string $fin): float
    {
        // L'effectif final réellement persisté par bande à la dernière fiche
        // journalière du mois ; repli sur `current_quantity` pour les bandes
        // sans fiche sur la période, jamais un zéro trompeur.
        $lots = LivestockLot::where('is_active', true)->get();

        $total = 0;

        foreach ($lots as $lot) {
            $derniere = LivestockDailyEntry::where('lot_id', $lot->id)
                ->whereDate('entry_date', '<=', $fin)
                ->orderByDesc('entry_date')
                ->first();

            $total += $derniere?->effectif_final ?? $lot->current_quantity;
        }

        return (float) $total;
    }

    /**
     * Taux de mortalité du mois — même formule que partout ailleurs dans le
     * projet (morts ÷ effectif de départ × 100, `LivestockDailyEntry`),
     * agrégée sur le mois plutôt que sur 7 jours comme le tableau de bord.
     */
    private function tauxMortalite(string $debut, string $fin): float
    {
        $entrees = LivestockDailyEntry::whereDate('entry_date', '>=', $debut)
            ->whereDate('entry_date', '<=', $fin)
            ->get();

        $morts = $entrees->sum('mort');
        $effectifDepart = $entrees->sum(fn ($e) => $e->previousEffectif());

        return $effectifDepart > 0 ? round(($morts / $effectifDepart) * 100, 1) : 0.0;
    }

    public function exportRapportMensuelPdf()
    {
        $this->authorize('view-rapports');

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.rapport-mensuel',
            [
                'indicateurs' => $this->indicateurs,
                'moisCourant' => $this->moisCourantLabel,
                'moisPrecedent' => $this->moisPrecedentLabel,
            ],
            'Rapport Mensuel de Synthèse',
            $this->moisCourantLabel.' — comparé à '.$this->moisPrecedentLabel
        );

        return response()->streamDownload(
            fn () => print ($pdf->output()),
            'rapport-mensuel-'.$this->periode.'.pdf'
        );
    }

    public function render()
    {
        return view('livewire.rapports.rapport-mensuel', ['title' => 'Rapports > Rapport Mensuel']);
    }
}
