<?php

namespace App\Livewire\Elevage;

use App\Actions\SaisieReproducteurAction;
use App\Models\Animal;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use Illuminate\Validation\ValidationException;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 14.17 (Sprint 14) — Registre des Reproducteurs.
 *
 * Complète le ticket 14.16 : `AnimalDetails` savait AFFICHER un sujet, mais
 * rien ne permettait d'en enregistrer un depuis l'interface. Cet écran ferme
 * la boucle enregistrer → lister → consulter.
 *
 * ⚠️ RÈGLE MÉTIER STRUCTURANTE — L'ENREGISTREMENT N'AJOUTE AUCUN ANIMAL.
 * Un reproducteur est déjà compté dans `livestock_lots.current_quantity` :
 * l'enregistrer individuellement ne fait que lui donner une identité
 * (boucle, race, généalogie). `current_quantity` n'est donc JAMAIS incrémenté
 * ici — le faire créerait un double comptage silencieux entre le suivi par
 * bande et le suivi individuel, avec un effectif qui gonflerait à chaque
 * identification.
 *
 * C'est la différence de fond avec `EnregistrerSujets` (ticket 3.4), qui lui
 * enregistre une véritable ENTRÉE (naissance, achat, don) et incrémente donc
 * l'effectif. Les deux écrans coexistent sans se recouvrir : l'un compte,
 * l'autre nomme.
 *
 * ⚠️ La SORTIE d'un reproducteur (réforme, vente, mort) n'est pas traitée ici
 * non plus : c'est le mouvement d'effectif de la fiche journalière qui en
 * fait foi. Cet écran ne fait qu'enregistrer le STATUT du sujet nommé, pour
 * que sa fiche cesse de le présenter comme présent — sans toucher aux
 * quantités, qui restent la vérité de la bande.
 */
#[Layout('layouts.app')]
class RegistreReproducteurs extends Component
{
    #[Url]
    public string $search = '';

    #[Url]
    public string $speciesFilter = '';

    #[Url]
    public string $statusFilter = '';

    // --- Formulaire ---
    public ?string $editingId = null;

    public string $identifier = '';

    public string $species_id = '';

    public string $lot_id = '';

    public string $sex = 'F';

    public string $breed = '';

    public string $birth_date = '';

    public string $entry_date = '';

    public string $origin = '';

    public string $cage = '';

    // --- Sortie (réforme / vente / mort) ---
    public ?string $exitingId = null;

    public string $exitStatus = 'reforme';

    public string $exit_date = '';

    public string $exit_reason = '';

    public function mount(): void
    {
        $this->entry_date = now()->format('Y-m-d');
        $this->exit_date = now()->format('Y-m-d');
    }

    /**
     * Décision BS-Q12 (21/10/2026) — LES ESPÈCES PROPOSÉES SONT LES MODULES ACTIFS (`modules_config`), comme partout
     * ailleurs et comme le tirage du poste (`LivestockSpecies::enabled()`). Cet écran filtrait sur
     * `livestock_species.is_enabled`, un indicateur que « Modules actifs » ne pilote pas : un module activé n'y
     * apparaissait pas, un module éteint y restait proposé.
     */
    public function getSpeciesOptionsProperty()
    {
        return LivestockSpecies::enabled()->orderBy('label')->get();
    }

    /**
     * Les espèces de la MODALE : les modules actifs ; en modification, l'espèce PROPRE du sujet s'y ajoute même si son
     * module vient d'être éteint (sinon le champ s'afficherait vide alors que le sujet a une espèce : la modification
     * d'une cage ne doit pas dépendre de « Modules actifs »). Les filtres du tableau gardent les modules actifs seuls.
     */
    public function getSpeciesFormOptionsProperty()
    {
        $propre = $this->editingId ? Animal::whereKey($this->editingId)->value('species_id') : null;

        return LivestockSpecies::where(function ($q) use ($propre) {
            $q->enabled();
            if ($propre) {
                $q->orWhere('id', $propre);
            }
        })->orderBy('label')->get();
    }

    public function getLotOptionsProperty()
    {
        return LivestockLot::with('species')
            ->where('status', 'actif')
            ->where('is_active', true)
            ->when($this->species_id, fn ($q) => $q->where('species_id', $this->species_id))
            ->orderBy('code')
            ->get();
    }

    public function getAnimalsProperty()
    {
        return Animal::with(['species', 'lot'])
            ->breeders()
            ->active()
            ->when($this->search, fn ($q) => $q->where(fn ($sub) => $sub
                ->where('identifier', 'like', '%'.$this->search.'%')
                ->orWhere('breed', 'like', '%'.$this->search.'%')))
            ->when($this->speciesFilter, fn ($q) => $q->where('species_id', $this->speciesFilter))
            ->when($this->statusFilter, fn ($q) => $q->where('status', $this->statusFilter))
            ->orderBy('identifier')
            ->get();
    }

    public function getKpisProperty(): array
    {
        $tous = Animal::breeders()->active()->get();

        return [
            'total' => $tous->count(),
            'presents' => $tous->where('status', 'actif')->count(),
            'femelles' => $tous->where('status', 'actif')->where('sex', 'F')->count(),
            'males' => $tous->where('status', 'actif')->where('sex', 'M')->count(),
        ];
    }

    public function newAnimal(): void
    {
        $this->authorize('manage-elevage');

        $this->reset(['editingId', 'identifier', 'species_id', 'lot_id', 'breed', 'birth_date', 'origin', 'cage']);
        $this->sex = 'F';
        $this->entry_date = now()->format('Y-m-d');
        $this->dispatch('open-modal', name: 'modal-reproducteur');
    }

    public function editAnimal(string $id): void
    {
        $this->authorize('manage-elevage');

        $animal = Animal::findOrFail($id);

        $this->editingId = $animal->id;
        $this->identifier = $animal->identifier;
        $this->species_id = $animal->species_id;
        $this->lot_id = (string) ($animal->lot_id ?? '');
        $this->sex = $animal->sex;
        $this->breed = (string) $animal->breed;
        $this->birth_date = $animal->birth_date?->format('Y-m-d') ?? '';
        $this->entry_date = $animal->entry_date->format('Y-m-d');
        $this->origin = (string) $animal->origin;
        $this->cage = (string) $animal->cage;

        $this->dispatch('open-modal', name: 'modal-reproducteur');
    }

    public function saveAnimal(): void
    {
        $this->authorize('manage-elevage');

        $this->validate([
            // L'identifiant est la clé lisible portée par la boucle du sujet :
            // un doublon rendrait tout l'historique de reproduction ambigu,
            // puisque les événements s'y rattachent par correspondance.
            'identifier' => ['required', 'string', 'max:50', 'unique:animals,identifier'.($this->editingId ? ','.$this->editingId : '')],
            'species_id' => ['required', 'exists:livestock_species,id'],
            'lot_id' => ['nullable', 'exists:livestock_lots,id'],
            'sex' => ['required', 'in:M,F'],
            'breed' => ['nullable', 'string', 'max:100'],
            'birth_date' => ['nullable', 'date', 'before_or_equal:today'],
            'entry_date' => ['required', 'date', 'before_or_equal:today'],
            'origin' => ['nullable', 'string', 'max:150'],
            'cage' => ['nullable', 'string', 'max:30'],
        ], [], [
            'identifier' => 'identifiant',
            'species_id' => 'espèce',
            'lot_id' => 'bande',
            'entry_date' => "date d'entrée",
        ]);

        // Ticket BS3 — le point de passage unique du registre (le poste envoie les siens par le même).
        $donnees = [
            'identifier' => $this->identifier,
            'species_id' => $this->species_id,
            'lot_id' => $this->lot_id ?: null,
            'sex' => $this->sex,
            'breed' => $this->breed ?: null,
            'birth_date' => $this->birth_date ?: null,
            'entry_date' => $this->entry_date,
            'origin' => $this->origin ?: null,
            'cage' => $this->cage ?: null,
        ];

        try {
            if ($this->editingId) {
                app(SaisieReproducteurAction::class)->modifier($this->editingId, $donnees);
                $message = 'Reproducteur mis à jour.';
            } else {
                app(SaisieReproducteurAction::class)->enregistrer($donnees);
                $message = 'Reproducteur enregistré — l\'effectif de la bande est inchangé, ce sujet y était déjà compté.';
            }
        } catch (ValidationException $e) {
            // Chaque refus sous SON champ : « Identifiant » (BS-Q13, formulaire forgé) ou « Date de Naissance ».
            foreach ($e->errors() as $champ => $messages) {
                $this->addError($champ, $messages[0]);
            }

            return;
        }

        $this->dispatch('close-modal', name: 'modal-reproducteur');
        $this->dispatch('toast', message: $message, type: 'success');
    }

    public function openExit(string $id): void
    {
        $this->authorize('manage-elevage');

        $this->exitingId = $id;
        $this->exitStatus = 'reforme';
        $this->exit_date = now()->format('Y-m-d');
        $this->exit_reason = '';
        $this->dispatch('open-modal', name: 'modal-sortie-reproducteur');
    }

    public function confirmExit(): void
    {
        $this->authorize('manage-elevage');

        $this->validate([
            'exitStatus' => ['required', 'in:reforme,vendu,mort'],
            'exit_date' => ['required', 'date', 'before_or_equal:today'],
            'exit_reason' => ['nullable', 'string', 'max:150'],
        ], [], ['exit_date' => 'date de sortie', 'exit_reason' => 'motif']);

        try {
            app(SaisieReproducteurAction::class)->sortir($this->exitingId, [
                'status' => $this->exitStatus,
                'exit_date' => $this->exit_date,
                'exit_reason' => $this->exit_reason ?: null,
            ]);
        } catch (ValidationException $e) {
            // La sortie avant l'entrée : sous « Date de sortie » ; un sujet déjà sorti : sous « Motif de sortie ».
            $erreurs = $e->errors();
            isset($erreurs['exit_date'])
                ? $this->addError('exit_date', $erreurs['exit_date'][0])
                : $this->addError('exitStatus', $erreurs['status'][0]);

            return;
        }

        $this->dispatch('close-modal', name: 'modal-sortie-reproducteur');
        $this->dispatch('toast', message: "Sortie enregistrée. L'effectif de la bande doit être ajusté depuis la fiche journalière — c'est elle qui fait foi sur les quantités.", type: 'warning');
    }

    public function render()
    {
        return view('livewire.elevage.registre-reproducteurs', ['title' => 'Élevage > Registre des Reproducteurs']);
    }
}
