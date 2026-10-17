<?php

namespace App\Livewire\Elevage;

use App\Models\LivestockSpecies;
use App\Services\GrowthAnalysisService;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 14.9 (Sprint 14) — analyse-croissance.html → Livewire\Elevage\AnalyseCroissance
 * "Analyse des Croissances — GMQ. Gain Moyen Quotidien = (Poids actuel −
 * Poids précédent) ÷ Jours écoulés."
 *
 * Calcul délégué à `GrowthAnalysisService` — voir son docblock pour l'écart
 * réel entre les deux formules de GMQ coexistant dans le projet (celle-ci et
 * celle de `DashboardElevage`), signalé plutôt qu'harmonisé unilatéralement.
 *
 * ⚠️ KPI RÉELS, PAS LES CONSTANTES DU PROTOTYPE : le prototype affiche
 * « 18 g/j », « 42 g/j », « 380 g/j » et « 6 lots » écrits en dur. Ici tout
 * est moyenné sur les lots réellement pesés, et les objectifs viennent du
 * référentiel `growth_standards` (ticket 14.9) plutôt que d'être répétés dans
 * chaque ligne.
 *
 * ⚠️ GRAPHIQUE SVG NON REPRIS, comme sur `DashboardElevage` (ticket 3.13) :
 * le prototype trace une courbe dont les 8 points sont des coordonnées
 * écrites en dur, sans lien avec la moindre donnée. Aucune librairie de
 * graphiques n'est disponible côté Blade à ce stade ; un SVG aux points
 * inventés serait un graphique fictif. Le tableau réel, lui, porte
 * l'information — même arbitrage que celui déjà retenu et documenté au
 * ticket 3.13, jamais une décision nouvelle prise ici en silence.
 */
#[Layout('layouts.app')]
class AnalyseCroissance extends Component
{
    #[Url]
    public string $especeFilter = '';

    public function getSpeciesProperty()
    {
        return LivestockSpecies::where('is_enabled', true)->orderBy('label')->get();
    }

    public function getRowsProperty(): array
    {
        return app(GrowthAnalysisService::class)->rows($this->especeFilter ?: null);
    }

    public function getAveragesProperty(): array
    {
        return app(GrowthAnalysisService::class)->averagesBySpecies();
    }

    public function getTrackedCountProperty(): int
    {
        return count($this->rows);
    }

    public function exportAnalyseCroissancePdf()
    {
        $this->authorize('view-elevage');

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.analyse-croissance',
            ['rows' => $this->rows],
            'Analyse des Croissances — GMQ',
            'État au '.now()->format('d/m/Y')
        );

        return response()->streamDownload(
            fn () => print ($pdf->output()),
            'analyse-croissance-'.now()->format('Y-m-d').'.pdf'
        );
    }

    public function render()
    {
        return view('livewire.elevage.analyse-croissance', ['title' => 'Élevage > Analyse des Croissances']);
    }
}
