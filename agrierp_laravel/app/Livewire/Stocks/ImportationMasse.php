<?php

namespace App\Livewire\Stocks;

use App\Models\ImportBatch;
use App\Services\Import\ImportMasseService;
use App\Services\Import\ImportRefuse;
use App\Services\Import\ModeleXlsxService;
use App\Services\Import\ModuleImport;
use Livewire\Attributes\Layout;
use Livewire\Component;
use Livewire\WithFileUploads;

/**
 * Ticket IMPORT-1 — « Importation en masse » (décision du client du 08/11/2026 : « très important »).
 *
 * Écran à six étapes : 1 choisir le module · 2 télécharger le modèle · 3 déposer le fichier · 4 aperçu avec validation ligne par
 * ligne (AUCUNE écriture) · 5 confirmer · 6 rapport. TOUTE la règle vit dans `App\Services\Import\*` : ce composant ne fait
 * qu'orchestrer et afficher, comme le poste (`agrierp_flutter/lib/features/importation/`), qui reprend les mêmes libellés.
 *
 * ⚠️ Hors maquette : cet écran n'existe pas dans le prototype HTML (ajout demandé par le client) ; ses libellés sont ceux d'ici
 * et le poste les lit dans cette vue (`importation_parite_web_test.dart`).
 *
 * ⚠️ `$lotId` et `$module` viennent du navigateur : le lot est toujours relu AVEC l'identifiant de l'utilisateur, le module
 * toujours revérifié contre ses droits (`ImportMasseService::moduleAutorise`).
 */
#[Layout('layouts.app')]
class ImportationMasse extends Component
{
    use WithFileUploads;

    public const PAR_PAGE = 25;

    public string $module = '';

    /** 1 module · 2 modèle · 3 fichier · 4 aperçu · 6 rapport (5, la confirmation, est la modale de l'étape 4). */
    public int $etape = 1;

    public $fichier = null;

    public ?string $lotId = null;

    public string $filtre = 'tous';

    public int $page = 1;

    public ?string $erreurFichier = null;

    public function mount(): void
    {
        abort_unless(count(app(ImportMasseService::class)->modulesAutorises(auth()->user())) > 0, 403);
    }

    /** @return array<string, ModuleImport> */
    public function getModulesProperty(): array
    {
        return app(ImportMasseService::class)->modulesAutorises(auth()->user());
    }

    public function getModuleChoisiProperty(): ?ModuleImport
    {
        return $this->module !== '' ? ($this->modules[$this->module] ?? null) : null;
    }

    public function getLotProperty(): ?ImportBatch
    {
        return $this->lotId === null ? null : ImportBatch::where('id', $this->lotId)->where('user_id', auth()->id())->first();
    }

    /** @return array<int, array<string, mixed>> les lignes du lot selon le filtre */
    public function getLignesFiltreesProperty(): array
    {
        $lignes = $this->lot?->lignes ?? [];
        if ($this->filtre === 'tous') {
            return $lignes;
        }

        return array_values(array_filter($lignes, fn ($l) => $l['statut'] === $this->filtre));
    }

    /** @return array<int, array<string, mixed>> */
    public function getLignesDeLaPageProperty(): array
    {
        return array_slice($this->lignesFiltrees, ($this->page - 1) * self::PAR_PAGE, self::PAR_PAGE);
    }

    public function getDernierePageProperty(): int
    {
        return max(1, (int) ceil(count($this->lignesFiltrees) / self::PAR_PAGE));
    }

    public function getBloquantProperty(): ?string
    {
        return $this->lot?->rapport['bloquant'] ?? null;
    }

    public function choisirModule(string $cle): void
    {
        abort_unless(isset($this->modules[$cle]), 403);

        $this->reinitialiser();
        $this->module = $cle;
        $this->etape = 2;
    }

    public function versEtape(int $etape): void
    {
        abort_unless($this->moduleChoisi !== null || $etape === 1, 403);

        if ($etape === 1) {
            $this->reinitialiser();
        } elseif (in_array($etape, [2, 3], true)) {
            $this->etape = $etape;
            $this->erreurFichier = null;
        }
    }

    public function telechargerModele()
    {
        $module = $this->moduleChoisi;
        abort_unless($module !== null && auth()->user()->can($module->permission()), 403);

        $service = app(ModeleXlsxService::class);
        $chemin = $service->fichier($module);

        return response()->streamDownload(function () use ($chemin) {
            readfile($chemin);
            @unlink($chemin);
        }, $service->nomDeFichier($module), ['Content-Type' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']);
    }

    /** Le fichier déposé est lu et validé tout de suite : l'aperçu n'écrit RIEN. */
    public function updatedFichier(): void
    {
        $module = $this->moduleChoisi;
        abort_unless($module !== null && auth()->user()->can($module->permission()), 403);

        $this->erreurFichier = null;
        $this->lotId = null;

        if ($this->fichier === null) {
            return;
        }

        try {
            $lot = app(ImportMasseService::class)->analyser(
                $module->cle(),
                $this->fichier->getRealPath(),
                $this->fichier->getClientOriginalName(),
                auth()->user(),
            );
            $this->lotId = $lot->id;
            $this->filtre = 'tous';
            $this->page = 1;
            $this->etape = 4;
        } catch (ImportRefuse $e) {
            $this->erreurFichier = $e->getMessage();
        } finally {
            $this->fichier = null;
        }
    }

    public function filtrer(string $filtre): void
    {
        abort_unless($this->lot !== null && in_array($filtre, ['tous', 'valide', 'ignoree', 'refusee', 'creee'], true), 403);

        $this->filtre = $filtre;
        $this->page = 1;
    }

    public function pagePrecedente(): void
    {
        abort_unless($this->lot !== null, 403);
        $this->page = max(1, $this->page - 1);
    }

    public function pageSuivante(): void
    {
        abort_unless($this->lot !== null, 403);
        $this->page = min($this->dernierePage, $this->page + 1);
    }

    /** Étape 5 : la confirmation écrit les lignes valides, une par une, par les points de passage uniques. */
    public function confirmer(): void
    {
        $lot = $this->lot;
        abort_unless($lot !== null && $this->moduleChoisi !== null, 403);
        $this->authorize($this->moduleChoisi->permission());

        try {
            app(ImportMasseService::class)->importer($lot, auth()->user());
        } catch (ImportRefuse $e) {
            $this->dispatch('close-modal', name: 'modal-confirmer-import');
            $this->dispatch('toast', message: $e->getMessage(), type: 'error');

            return;
        }

        $this->dispatch('close-modal', name: 'modal-confirmer-import');
        $this->filtre = 'tous';
        $this->page = 1;
        $this->etape = 6;
        $this->dispatch('toast', message: 'Importation terminée : le rapport est affiché.', type: 'success');
    }

    public function telechargerRapport()
    {
        $lot = $this->lot;
        abort_unless($lot !== null && $this->moduleChoisi !== null, 403);
        $this->authorize($this->moduleChoisi->permission());

        $service = app(ImportMasseService::class);
        $chemin = $service->rapportXlsx($lot);

        return response()->streamDownload(function () use ($chemin) {
            readfile($chemin);
            @unlink($chemin);
        }, $service->nomDuRapport($lot), ['Content-Type' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']);
    }

    /** « Corriger le fichier puis ré-importer » : même module, retour au dépôt du fichier. */
    public function corriger(): void
    {
        abort_unless($this->moduleChoisi !== null, 403);

        $module = $this->module;
        $this->reinitialiser();
        $this->module = $module;
        $this->etape = 3;
    }

    /** Abandonne l'aperçu (rien n'a été écrit) et revient au choix du module. */
    public function recommencer(): void
    {
        if ($this->lot !== null && $this->moduleChoisi !== null) {
            $this->authorize($this->moduleChoisi->permission());
            app(ImportMasseService::class)->annuler($this->lot, auth()->user());
        }

        $this->reinitialiser();
    }

    private function reinitialiser(): void
    {
        $this->reset(['module', 'fichier', 'lotId', 'filtre', 'page', 'erreurFichier']);
        $this->etape = 1;
    }

    public function render()
    {
        return view('livewire.stocks.importation-masse', [
            'title' => 'Stocks & Produits > Importation en masse',
        ]);
    }
}
