<?php

namespace App\Livewire\Comptabilite;

use App\Services\VatDeclarationService;
use Carbon\Carbon;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 14.7 (Sprint 14) — declaration-tva.html → Livewire\Comptabilite\DeclarationTva
 * "TVA Collectée (4431) et TVA Déductible (4452) — taux 18% (transformés/
 * services) ou 0% (produits bruts, exonéré)."
 *
 * **Module M14, exigence impérative** (articles 162 bis et 1084-40 du CGI
 * Bénin, en vigueur depuis le 01/07/2021). 4e écran comptable réellement
 * construit de la série ; comme les précédents, absent des 4 installations.
 *
 * Le calcul est délégué à `VatDeclarationService` — voir son docblock pour
 * les deux règles structurantes : convention TTC → HT reprise du prototype,
 * et filtre `mecef_status = 'transmise'` (une facture en erreur MeCeF n'a pas
 * été transmise à la DGI, elle ne peut donc pas être déclarée).
 *
 * ⚠️ ÉCART DE PLAN COMPTABLE SIGNALÉ, NON CORRIGÉ SEUL : le prototype cite
 * les comptes `4431` (TVA collectée) et `4452` (TVA déductible), là où
 * `ChartOfAccountsSeeder` porte `443` (TVA facturée) et `445` (TVA
 * récupérable). Même famille d'écart que `661`/`65` (comblé au ticket 14.6),
 * mais celui-ci touche la nomenclature fiscale déclarée à la DGI : à trancher
 * avec la Direction avant mise en production, jamais harmonisé
 * unilatéralement. Cet écran n'écrit aucune écriture comptable — il lit et
 * totalise —, l'écart n'a donc aucun effet sur les données à ce stade.
 *
 * ⚠️ HYPOTHÈSE DU PROTOTYPE **NON REPRISE** : le prototype assigne un taux de
 * TVA à chaque facture « par hypothèse de travail », faute de taux ligne par
 * ligne dans sa source, et l'affiche dans un bandeau. Ici le taux vient du
 * champ réel `products.tva_rate` — l'hypothèse n'a plus lieu d'être et le
 * bandeau n'est pas recopié. Ce qui reste vrai en revanche, et qui est
 * affiché : une facture peut mélanger des lignes à 0% et à 18%, auquel cas le
 * taux est présenté comme « mixte » plutôt que réduit arbitrairement à celui
 * de la première ligne.
 */
#[Layout('layouts.app')]
class DeclarationTva extends Component
{
    /** Période déclarée, au format `YYYY-MM`. */
    #[Url]
    public string $periode = '';

    public function mount(): void
    {
        // Ticket EX7 (EF9) — le mois du jour s'il est dans l'exercice affiché, sinon son dernier mois.
        $this->periode = \App\Support\ExerciceChoisi::bornerMois($this->periode !== '' ? $this->periode : now()->format('Y-m'));
    }

    public function updatedPeriode(): void
    {
        $this->periode = \App\Support\ExerciceChoisi::bornerMois($this->periode);
    }

    /**
     * Ticket EX7 (EF9) — les mois de l'exercice AFFICHÉ, du plus récent au plus ancien (jusqu'au mois du jour) ; avant :
     * les 12 derniers mois glissants, à cheval sur deux exercices.
     */
    public function getPeriodesProperty(): array
    {
        return \App\Support\ExerciceChoisi::moisDeLExercice();
    }

    private function bounds(): array
    {
        $start = Carbon::createFromFormat('Y-m-d', $this->periode.'-01')->startOfMonth();

        return [$start->format('Y-m-d'), $start->copy()->endOfMonth()->format('Y-m-d')];
    }

    /** Échéance de dépôt : le 15 du mois suivant (DGI Bénin). */
    public function getEcheanceProperty(): string
    {
        [$start] = $this->bounds();

        return Carbon::parse($start)->addMonthNoOverflow()->day(15)->format('d/m/Y');
    }

    public function getDeclarationProperty(): array
    {
        [$start, $end] = $this->bounds();

        return app(VatDeclarationService::class)->declaration($start, $end);
    }

    public function getPeriodeLabelProperty(): string
    {
        return $this->periodes[$this->periode] ?? $this->periode;
    }

    public function exportDeclarationTvaPdf()
    {
        $this->authorize('view-comptabilite');

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.declaration-tva',
            ['declaration' => $this->declaration],
            'Déclaration TVA',
            $this->periodeLabel.' — échéance de dépôt le '.$this->echeance
        );

        return response()->streamDownload(
            fn () => print ($pdf->output()),
            'declaration-tva-'.$this->periode.'.pdf'
        );
    }

    public function render()
    {
        return view('livewire.comptabilite.declaration-tva', ['title' => 'Comptabilité > Déclaration TVA']);
    }
}
