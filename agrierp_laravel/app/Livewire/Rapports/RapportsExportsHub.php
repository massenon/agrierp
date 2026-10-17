<?php

namespace App\Livewire\Rapports;

use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 12.1 (Sprint 12, le dernier) — rapports-exports.html →
 * Livewire\Rapports\RapportsExportsHub
 * "Hub à en-tête unifié, 6 onglets" (Document 05 §Module 10, correction
 * du 29 juillet 2026 : un 7ᵉ onglet "Rapport Mensuel" retiré sur
 * directive explicite, ne jamais le porter — de même que
 * `rapport-recettes.html`/`rapport-depenses.html`, orphelins signalés
 * explicitement dans le plan d'exécution).
 *
 * ⚠️ ARCHITECTURE CENTRALE DE CE TICKET : "L'export n'est plus géré
 * onglet par onglet mais par un en-tête de filtres commun en tête de
 * page (période Du/Au + boutons Exporter PDF/Excel), qui déclenche
 * dynamiquement l'export du rapport actuellement affiché." Ce hub
 * possède SEUL l'état de période (`startDate`/`endDate`), transmis à
 * l'enfant actif comme propriété — jamais 6 sélecteurs de date
 * dupliqués un par onglet.
 *
 * Le déclenchement d'export cible l'enfant réellement affiché via le
 * ciblage d'événement Livewire v3 (`->to(ComponentClass::class)`) — le
 * hub ne connaît pas la structure de colonnes de chaque rapport (elle
 * diffère radicalement d'un onglet à l'autre, ex. 3 tableaux pour
 * Rapport Élevage vs une grille simple pour Trésorerie), chaque enfant
 * reste responsable de sa propre mise en page d'export. Le hub ne fait
 * que déclencher au bon endroit, jamais une logique d'export générique
 * qui essaierait de couvrir tous les cas.
 *
 * 🔴→✅ TROISIÈME DIMENSION RBAC DÉCOUVERTE PAR L'AUDIT (après
 * `view-X`/`manage-X` déjà traités sur 9 écrans de référence) :
 * `export-X` existe dans le seeder (`export-elevage`, `export-ventes`,
 * `export-rapports`...) mais n'était vérifiée NULLE PART dans le
 * projet — un rôle avec `view-rapports` mais sans `export-rapports`
 * aurait pu exporter des rapports PDF/Excel sans aucune restriction.
 * Corrigé ici ET dans les 6 composants enfants (`Dettes`, `Creances`,
 * `Tresorerie`, `RecettesDepenses`, `ElevageSynth`, `StocksSynth`) qui
 * partagent tous la même signature `exportReport()` — `$this->authorize('export-rapports')`
 * ajouté à chacun, boutons Exporter PDF/Excel masqués ici au niveau hub.
 */
#[Layout('layouts.app')]
class RapportsExportsHub extends Component
{
    #[Url]
    public string $tab = 'recettes-depenses';

    #[Url]
    public string $startDate = '';

    #[Url]
    public string $endDate = '';

    public function mount(): void
    {
        if (! $this->startDate) {
            $this->startDate = now()->startOfMonth()->format('Y-m-d');
        }
        if (! $this->endDate) {
            $this->endDate = now()->endOfMonth()->format('Y-m-d');
        }
    }

    /** Un seul point de correspondance onglet → classe du composant réellement affiché. */
    private function activeComponentClass(): string
    {
        return match ($this->tab) {
            'recettes-depenses' => RecettesDepenses::class,
            'tresorerie' => Tresorerie::class,
            'creances' => Creances::class,
            'dettes' => Dettes::class,
            'elevage-synth' => ElevageSynth::class,
            'stocks-synth' => StocksSynth::class,
            default => RecettesDepenses::class,
        };
    }

    public function exportPdf()
    {
        $this->dispatch('export-report', format: 'pdf', startDate: $this->startDate, endDate: $this->endDate)
            ->to($this->activeComponentClass());
    }

    public function exportExcel()
    {
        $this->dispatch('export-report', format: 'csv', startDate: $this->startDate, endDate: $this->endDate)
            ->to($this->activeComponentClass());
    }

    public function render()
    {
        return view('livewire.rapports.rapports-exports-hub', ['title' => 'Rapports & Exports']);
    }
}
