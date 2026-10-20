<?php

namespace App\Livewire\Comptabilite;

use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\FixedAsset;
use App\Models\Product;
use App\Services\FinancialReportService;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 14.6 (Sprint 14) — etats-financiers.html → Livewire\Comptabilite\EtatsFinanciers
 * "Bilan, Compte de Résultat, Tableau des Flux de Trésorerie et Notes
 * Annexes — conformité SYSCOHADA." 4 onglets réels.
 *
 * 3e écran comptable réellement construit de la série. Comme le Grand Livre
 * et la Balance Générale, décrit comme livré au log mais absent des 4
 * installations du poste (audit du ticket 14.5).
 *
 * ONGLETS ADOSSÉS À UN SEUL POINT DE VÉRITÉ, JAMAIS 3 CALCULS PARALLÈLES :
 *   - Bilan → `FinancialReportService::bilan()` (ticket 10.5, inchangé)
 *   - Compte de Résultat → `compteResultat()` (même fenêtre que `bilan()`,
 *     donc Résultat Net strictement identique par construction — exigence
 *     explicite du prototype)
 *   - Flux de Trésorerie → `tafire()`, qui consomme les deux précédents
 *
 * 🔴→✅ LIMITE LEVÉE AU TICKET 14.26 — Note 2 (Immobilisations). Cet écran a
 * longtemps porté une limite assumée : le prototype ventile les
 * immobilisations par nature (Bâtiments / Cages / Broyeurs) et impute
 * l'intégralité de l'amortissement aux Broyeurs, en le disant lui-même
 * « hypothèse retenue », alors que le plan comptable ne traçait les
 * immobilisations qu'au niveau agrégé de la classe 2. Le REGISTRE DES
 * IMMOBILISATIONS (ticket 14.26) fournit désormais la ventilation réelle :
 * la Note 2 la lit et n'affiche plus une hypothèse.
 *
 * ⚠️ La note reste adossée au GRAND LIVRE pour son total : la valeur nette de
 * la Note 2 est celle du Bilan (`total_immo`), et l'écart éventuel avec le
 * registre — des biens saisis en reprise d'antériorité, jamais entrés à
 * l'actif — est AFFICHÉ, jamais absorbé en silence. Deux totaux qui
 * divergeraient sans le dire seraient pires qu'une note approximative.
 *
 * ⚠️ Note 3 (Stocks) : la valorisation PMP provient de `Product::computePmp()`
 * (ticket 12.7), déjà le point de vérité partagé avec `GestionStocks` et
 * `StocksSynth` — jamais un troisième calcul de PMP.
 */
#[Layout('layouts.app')]
class EtatsFinanciers extends Component
{
    #[Url]
    public string $tab = 'bilan';

    public function getFiscalYearProperty(): ?FiscalYear
    {
        return FiscalYear::current();
    }

    private function asOfDate(): string
    {
        $year = $this->fiscalYear;

        // Arrêté à aujourd'hui, jamais au-delà de la fin de l'exercice ouvert.
        if ($year && now()->greaterThan($year->end_date)) {
            return $year->end_date->format('Y-m-d');
        }

        return now()->format('Y-m-d');
    }

    private function startDate(): string
    {
        return $this->fiscalYear?->start_date->format('Y-m-d')
            ?? now()->startOfYear()->format('Y-m-d');
    }

    public function getBilanProperty(): array
    {
        return app(FinancialReportService::class)->bilan($this->asOfDate());
    }

    public function getResultatProperty(): array
    {
        return app(FinancialReportService::class)->compteResultat($this->asOfDate());
    }

    public function getTafireProperty(): array
    {
        return app(FinancialReportService::class)->tafire($this->startDate(), $this->asOfDate());
    }

    public function getSituationLabelProperty(): string
    {
        return 'Situation au '.\Carbon\Carbon::parse($this->asOfDate())->format('d/m/Y')
            .' — Exercice '.($this->fiscalYear?->year ?? now()->year);
    }

    /**
     * Note 3 — valorisation réelle du stock au PMP, calculée depuis
     * `Product::computePmp()`. Les produits sans historique d'achat (sujets
     * nés à la ferme, œufs) n'ont pas de PMP calculable et sont exclus de la
     * valorisation plutôt que remplacés par une estimation inventée — même
     * règle que `GestionStocks` (ticket 6.2).
     */
    public function getStockValuationProperty(): array
    {
        $products = Product::where('is_active', true)->get();

        $valorises = $products->filter(fn ($p) => $p->computePmp() !== null);

        // 🔴→✅ TICKET 14.30 — PLANCHER A ZERO. `stock_qty * computePmp()`
        // produisait une valeur NEGATIVE pour un produit en stock negatif, qui
        // venait en deduction du total : un seul produit en anomalie faisait
        // mecaniquement baisser la valorisation de tous les autres, et l'actif
        // du Bilan avec. Un actif ne peut pas etre negatif. Plancher pose dans
        // `Product::valeurStock()`, point de verite unique des 3 ecrans qui
        // valorisent.
        $enAnomalie = $products->filter(fn ($p) => $p->stockEstNegatif());

        return [
            'valeur' => round($valorises->sum(fn ($p) => $p->valeurStock()), 2),
            'nb_valorises' => $valorises->count(),
            'nb_sans_pmp' => $products->count() - $valorises->count(),
            // Ecart AFFICHE, jamais absorbe en silence : le plancher corrige la
            // valorisation mais ne regularise rien — l'entree manquante reste a
            // saisir. Meme principe que le « hors comptabilite » des
            // Immobilisations (ticket 14.26).
            'nb_negatifs' => $enAnomalie->count(),
            'qte_manquante' => round($enAnomalie->sum(fn ($p) => $p->quantiteManquante()), 2),
        ];
    }

    public function switchTab(string $tab): void
    {
        $this->tab = in_array($tab, ['bilan', 'resultat', 'tafire', 'notes'], true) ? $tab : 'bilan';
    }

    /**
     * Le prototype exporte « l'onglet actif » — comportement conservé : le PDF
     * porte sur l'onglet réellement consulté, pas sur les 4 à la fois.
     */
    public function exportEtatActifPdf()
    {
        $this->authorize('view-comptabilite');

        $titres = [
            'bilan' => 'États Financiers — Bilan',
            'resultat' => 'États Financiers — Compte de Résultat',
            'tafire' => 'États Financiers — Flux de Trésorerie (TAFIRE)',
            'notes' => 'États Financiers — Notes Annexes',
        ];

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.etats-financiers',
            [
                'tab' => $this->tab,
                'bilan' => $this->bilan,
                'resultat' => $this->resultat,
                'tafire' => $this->tafire,
                'stockValuation' => $this->stockValuation,
            ],
            $titres[$this->tab] ?? 'États Financiers',
            // Ticket EX2 — l'ouverture calculée (exercice précédent encore ouvert) est dite sur le document aussi.
            $this->situationLabel.($this->bilan['ouverture']['provisoire'] ? ' — À-nouveaux provisoires' : '')
        );

        return response()->streamDownload(
            fn () => print ($pdf->output()),
            'etats-financiers-'.$this->tab.'-'.now()->format('Y-m-d').'.pdf'
        );
    }

    /**
     * Ventilation des immobilisations par nature d'actif, lue au REGISTRE
     * (ticket 14.26) — la donnée que la Note 2 ne pouvait pas produire tant
     * que la classe 2 n'était suivie qu'en agrégé.
     *
     * `hors_compta` isole les biens jamais portés à l'actif (reprises
     * d'antériorité) : c'est exactement ce qui explique un écart entre le
     * registre et l'Actif Immobilisé du Bilan.
     *
     * @return array{lignes: array<int, array<string, mixed>>, brut: float, amortissement: float, net: float, hors_compta: float}
     */
    public function getRegistreImmobilisationsProperty(): array
    {
        $biens = FixedAsset::active()->inService()->get();
        $libelles = ChartOfAccount::where('class', 2)->pluck('label', 'code');

        $lignes = [];

        foreach ($biens->groupBy('account_code') as $compte => $groupe) {
            $brut = round($groupe->sum(fn ($b) => (float) $b->acquisition_value), 2);
            $amortissement = round($groupe->sum(fn ($b) => $b->cumulAmortissement($this->asOfDate())), 2);

            $lignes[] = [
                'code' => $compte,
                'label' => $libelles[$compte] ?? $compte,
                'brut' => $brut,
                'amortissement' => $amortissement,
                'net' => round($brut - $amortissement, 2),
            ];
        }

        usort($lignes, fn ($a, $b) => strcmp($a['code'], $b['code']));

        return [
            'lignes' => $lignes,
            'brut' => round(array_sum(array_column($lignes, 'brut')), 2),
            'amortissement' => round(array_sum(array_column($lignes, 'amortissement')), 2),
            'net' => round(array_sum(array_column($lignes, 'net')), 2),
            'hors_compta' => round($biens->where('is_capitalized', false)->sum(fn ($b) => (float) $b->acquisition_value), 2),
        ];
    }

    public function render()
    {
        return view('livewire.comptabilite.etats-financiers', ['title' => 'Comptabilité > États Financiers']);
    }
}
