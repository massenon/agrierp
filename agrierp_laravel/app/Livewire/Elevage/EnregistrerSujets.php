<?php

namespace App\Livewire\Elevage;

use App\Actions\SaisieSujetAction;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use Illuminate\Validation\ValidationException;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 3.4 (Sprint 3) — enregistrer-sujets.html → Livewire\Elevage\EnregistrerSujets
 * "Journal des ENTRÉES (Phase 1 du cycle)... chaque entrée valide alimente
 * ensuite une Bande/Lot" (copie exacte du prototype).
 *
 * ⚠️ CHAMP AJOUTÉ AU-DELÀ DU PROTOTYPE, DOCUMENTÉ : le formulaire source
 * (gabarit CRUD générique, identique dans sa structure à `ajouter-produit.html`)
 * demande Espèce/Origine/Quantité/Date mais ne précise JAMAIS à quelle
 * Bande/Lot l'entrée doit être rattachée — alors que sa propre description
 * affirme que chaque entrée "alimente une Bande/Lot". Ajout d'un champ
 * "Bande" (obligatoire, filtré par espèce choisie), sans lequel la donnée
 * saisie ne pourrait jamais réellement alimenter le lot annoncé — même
 * nature d'incomplétude déjà rencontrée et corrigée sur `ajouter-produit.html`
 * (ticket 2.4).
 *
 * Chaque entrée validée crée/complète une ligne `livestock_daily_entries`
 * (contrainte unique `lot_id`+`entry_date` du schéma — les quantités
 * s'additionnent si une entrée existe déjà ce jour-là pour cette bande,
 * jamais un doublon) et incrémente `livestock_lots.current_quantity` selon
 * la formule Document 05 (Effectif Final = Effectif(J-1) + Achats + Nés −
 * (Morts + Ventes + Dons) — ce journal ne couvrant que les ENTRÉES, morts
 * et ventes valent 0 ici).
 *
 * Le suivi individuel par sujet (case à cocher côté ticket 3.3) n'est pas
 * persisté dans une table dédiée : le schéma documenté ne réserve aucune
 * table "sujets individuels" (`livestock_reproduction_events.mother_ref`/
 * `sire_ref` restent des chaînes libres, jamais une clé étrangère vers un
 * registre de sujets) — cohérent avec ce choix de modélisation déjà acté,
 * pas une omission de ce ticket.
 *
 * 🔴→✅ TICKET BS2 — MODIFIER ET ARCHIVER. Le prototype affiche « Actions » (Modifier / Archiver) ; ils avaient été
 * retirés parce qu'une entrée passée « romprait la cascade » des effectifs. Depuis A1 la cascade unique
 * (`RecordSaleOnFicheElevageAction::recalculerEnCascade`) sait corriger un jour passé : les trois gestes (Nouveau,
 * Modifier, Archiver) passent par `SaisieSujetAction`, qui la fait jouer. Une ligne du journal est UNE ORIGINE d'une
 * fiche du jour ; archiver la retire du journal (colonne remise à 0, fiche gardée, trace à l'audit). Droits :
 * `manage-elevage` (nouveau, modifier) et `archive-elevage` (archiver) ; le poste a les mêmes.
 */
#[Layout('layouts.app')]
class EnregistrerSujets extends Component
{
    #[Url]
    public string $search = '';

    #[Url]
    public string $statut = '';

    public ?string $editingEntryId = null;

    /** Jour et origine de la ligne en cours de modification (sa clé dans le journal). */
    public string $editingDate = '';

    public string $editingOrigine = '';

    public string $species_id = '';

    public string $lot_id = '';

    public string $origine = '';

    public int $quantite = 1;

    public string $entry_date = '';

    public function mount(): void
    {
        $this->entry_date = now()->format('Y-m-d');
    }

    public function updatedSpeciesId(): void
    {
        $this->lot_id = '';
    }

    public function getKpisProperty(): array
    {
        $entries = LivestockDailyEntry::whereBetween('entry_date', [now()->startOfMonth(), now()->endOfMonth()]);

        return [
            'naissances_mois' => (int) (clone $entries)->sum('ne'),
            'acquisitions_mois' => (int) (clone $entries)->sum('achat'),
            'effectif_total' => (int) LivestockLot::vivantes()->sum('current_quantity'),   // Bandes VIVANTES : une bande archivée ne compte plus (LivestockLot::vivantes).
        ];
    }

    public function getSpeciesOptionsProperty()
    {
        return LivestockSpecies::enabled()->orderBy('label')->get();
    }

    public function getLotOptionsProperty()
    {
        if (! $this->species_id) {
            return collect();
        }

        return LivestockLot::where('species_id', $this->species_id)
            ->where('status', 'actif')
            ->where('is_active', true)
            ->orderBy('code')
            ->get();
    }

    /**
     * Journal affiché = les entrées récentes portant achat, naissance ou
     * don > 0 (les "entrées" au sens de cet écran) sur les bandes
     * actives — un seul point de vérité (`livestock_daily_entries`),
     * jamais une table dupliquée localement pour ce journal.
     *
     * 🔴→✅ BS2 : UNE LIGNE PAR ORIGINE. Une fiche qui porte une naissance ET un achat donnait une seule ligne (la
     * naissance), l'achat restait invisible et ne pouvait ni se modifier ni s'archiver. Chaque origine > 0 a
     * maintenant sa ligne, avec ses propres actions.
     *
     * @return \Illuminate\Support\Collection<int, object{entry: LivestockDailyEntry, origine: string, quantite: int}>
     */
    public function getEntriesProperty()
    {
        $fiches = LivestockDailyEntry::with('lot.species')
            ->where(fn ($q) => $q->where('achat', '>', 0)->orWhere('ne', '>', 0)->orWhere('don', '>', 0))
            ->when($this->search, fn ($q) => $q->whereHas('lot', fn ($q2) => $q2->where('code', 'like', '%'.$this->search.'%')))
            ->when($this->statut === 'Naissance', fn ($q) => $q->where('ne', '>', 0))
            ->when($this->statut === 'Achat', fn ($q) => $q->where('achat', '>', 0))
            ->latest('entry_date')
            ->orderBy('id')   // ordre stable à date égale (le poste départage de la même façon)
            ->limit(50)
            ->get();

        return $fiches->flatMap(function (LivestockDailyEntry $fiche) {
            $lignes = collect();
            foreach (SaisieSujetAction::ORIGINES as $origine => $colonne) {
                if ((int) $fiche->{$colonne} > 0 && ($this->statut === '' || $this->statut === $origine)) {
                    $lignes->push((object) ['entry' => $fiche, 'origine' => $origine, 'quantite' => (int) $fiche->{$colonne}]);
                }
            }

            return $lignes;
        })->values();
    }

    public function newEntry(): void
    {
        $this->authorize('manage-elevage');

        $this->reset(['editingEntryId', 'editingDate', 'editingOrigine', 'species_id', 'lot_id', 'origine']);
        $this->quantite = 1;
        $this->entry_date = now()->format('Y-m-d');
        $this->dispatch('open-modal', name: 'modal-create-sujet');
    }

    public function saveEntry(): void
    {
        $this->authorize('manage-elevage');

        $this->validate([
            'species_id' => ['required', 'exists:livestock_species,id'],
            'lot_id' => ['required', 'exists:livestock_lots,id'],
            'origine' => ['required', 'in:Naissance,Achat,Don'],
            'quantite' => ['required', 'integer', 'min:1'],
            'entry_date' => ['required', 'date'],
        ]);

        try {
            app(SaisieSujetAction::class)->ajouter($this->lot_id, $this->origine, $this->quantite, $this->entry_date);
        } catch (ValidationException $e) {
            $this->afficherLeRefus($e);

            return;
        }

        $this->dispatch('close-modal', name: 'modal-create-sujet');
        $this->dispatch('toast', message: 'Enregistrement effectué avec succès.', type: 'success');
        $this->reset(['species_id', 'lot_id', 'origine']);
        $this->quantite = 1;
    }

    /** Ouvre « Modifier le Sujet » sur la ligne (fiche, origine) du journal. */
    public function editEntry(string $entryId, string $origine): void
    {
        $this->authorize('manage-elevage');

        $fiche = LivestockDailyEntry::with('lot.species')->findOrFail($entryId);
        $colonne = SaisieSujetAction::ORIGINES[$origine] ?? null;
        if ($colonne === null || (int) $fiche->{$colonne} <= 0) {
            $this->dispatch('toast', message: SaisieSujetAction::MESSAGE_INTROUVABLE, type: 'error');

            return;
        }

        $this->resetErrorBag();
        $this->editingEntryId = $fiche->id;
        $this->editingDate = $fiche->entry_date->format('Y-m-d');
        $this->editingOrigine = $origine;
        $this->species_id = (string) $fiche->lot->species_id;
        $this->lot_id = $fiche->lot_id;
        $this->origine = $origine;
        $this->quantite = (int) $fiche->{$colonne};
        $this->entry_date = $this->editingDate;
        $this->dispatch('open-modal', name: 'modal-edit-sujet');
    }

    public function updateEntry(): void
    {
        $this->authorize('manage-elevage');

        $this->validate([
            'origine' => ['required', 'in:Naissance,Achat,Don'],
            'quantite' => ['required', 'integer', 'min:1'],
            'entry_date' => ['required', 'date'],
        ]);

        try {
            app(SaisieSujetAction::class)->modifier($this->lot_id, $this->editingDate, $this->editingOrigine, $this->origine, $this->quantite, $this->entry_date);
        } catch (ValidationException $e) {
            $this->afficherLeRefus($e);

            return;
        }

        $this->dispatch('close-modal', name: 'modal-edit-sujet');
        $this->dispatch('toast', message: 'Modification enregistrée avec succès.', type: 'success');
        $this->reset(['editingEntryId', 'editingDate', 'editingOrigine', 'species_id', 'lot_id', 'origine']);
        $this->quantite = 1;
    }

    /** Archive la ligne (fiche, origine) : l'entrée quitte le journal, la fiche est gardée. */
    public function archiveEntry(string $entryId, string $origine): void
    {
        $this->authorize('archive-elevage');

        $fiche = LivestockDailyEntry::findOrFail($entryId);

        try {
            app(SaisieSujetAction::class)->archiver($fiche->lot_id, $fiche->entry_date->format('Y-m-d'), $origine);
        } catch (ValidationException $e) {
            // Pas de modale ouverte : le refus se lit aussi en toast.
            $this->afficherLeRefus($e, true);

            return;
        }

        $this->dispatch('toast', message: 'Entrée archivée avec succès.', type: 'warning');
    }

    /**
     * Le refus de l'Action : la date (exercice clos) et la quantité (effectif négatif) se lisent sous leur champ — dans
     * la modale ouverte — ; une entrée introuvable est un toast d'erreur.
     */
    private function afficherLeRefus(ValidationException $e, bool $enToast = false): void
    {
        $erreurs = $e->errors();

        foreach (['entry_date', 'quantite'] as $champ) {
            if (isset($erreurs[$champ])) {
                $this->addError($champ, $erreurs[$champ][0]);
                if ($enToast) {
                    $this->dispatch('toast', message: $erreurs[$champ][0], type: 'error');
                }

                return;
            }
        }

        $this->dispatch('toast', message: collect($erreurs)->flatten()->first(), type: 'error');
    }

    public function render()
    {
        return view('livewire.elevage.enregistrer-sujets', ['title' => 'Élevage > Enregistrer des Sujets']);
    }
}
