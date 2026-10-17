<?php

namespace App\Livewire\Elevage;

use App\Models\AuditLog;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
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
 * ⚠️ ÉCART DÉLIBÉRÉ TROUVÉ PAR L'AUDIT DE FIDÉLITÉ : le prototype affiche
 * "Statut" (badge redondant avec la colonne Origine — "Naissance" répété
 * tel quel) et "Actions" (Modifier/Archiver, `openModal(...)` de
 * démonstration sans logique réelle). Non repris ici, même raisonnement
 * que `GestionStocks` (Journal des Mouvements) : chaque ligne dérive
 * d'une écriture sur `livestock_daily_entries`, dont l'effectif de CHAQUE
 * jour suivant se calcule en cascade à partir du jour précédent (Document
 * 05, formule Effectif Final) — modifier ou archiver une entrée passée
 * romprait cette cascade pour tous les jours suivants de la bande
 * concernée. Retrait volontaire, même discipline que les outils de démo
 * retirés depuis le Sprint 0 — jamais un oubli.
 */
#[Layout('layouts.app')]
class EnregistrerSujets extends Component
{
    #[Url]
    public string $search = '';

    #[Url]
    public string $statut = '';

    public ?string $editingEntryId = null;

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
            'effectif_total' => (int) LivestockLot::where('status', 'actif')->sum('current_quantity'),
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
     */
    public function getEntriesProperty()
    {
        return LivestockDailyEntry::with('lot.species')
            ->where(fn ($q) => $q->where('achat', '>', 0)->orWhere('ne', '>', 0)->orWhere('don', '>', 0))
            ->when($this->search, fn ($q) => $q->whereHas('lot', fn ($q2) => $q2->where('code', 'like', '%'.$this->search.'%')))
            ->when($this->statut === 'Naissance', fn ($q) => $q->where('ne', '>', 0))
            ->when($this->statut === 'Achat', fn ($q) => $q->where('achat', '>', 0))
            ->latest('entry_date')
            ->limit(50)
            ->get();
    }

    public function newEntry(): void
    {
        $this->reset(['editingEntryId', 'species_id', 'lot_id', 'origine']);
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

        $lot = LivestockLot::findOrFail($this->lot_id);

        $field = match ($this->origine) {
            'Naissance' => 'ne',
            'Achat' => 'achat',
            'Don' => 'don',
        };

        $entry = LivestockDailyEntry::firstOrNew([
            'lot_id' => $this->lot_id,
            'entry_date' => $this->entry_date,
        ]);

        $previousEffectif = $entry->exists ? $entry->previousEffectif() : $lot->current_quantity;

        $entry->$field = ($entry->$field ?? 0) + $this->quantite;
        $entry->effectif_final = LivestockDailyEntry::computeEffectifFinal(
            $previousEffectif,
            $entry->achat ?? 0,
            $entry->ne ?? 0,
            $entry->mort ?? 0,
            $entry->vente ?? 0,
            $entry->don ?? 0,
        );
        $entry->save();

        $lot->increment('current_quantity', $this->quantite);

        AuditLog::record('livestock_entry.recorded', 'elevage');
        $this->dispatch('close-modal', name: 'modal-create-sujet');
        $this->dispatch('toast', message: 'Enregistrement effectué avec succès.', type: 'success');
        $this->reset(['species_id', 'lot_id', 'origine']);
        $this->quantite = 1;
    }

    public function render()
    {
        return view('livewire.elevage.enregistrer-sujets', ['title' => 'Élevage > Enregistrer des Sujets']);
    }
}
