<?php

namespace App\Livewire\Elevage;

use App\Models\AuditLog;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 3.3 (Sprint 3) — gestion-bandes.html → Livewire\Elevage\GestionBandes
 * "Numérotation continue inter-bandes" (Document 05).
 *
 * ⚠️ RÉCONCILIATION DOCUMENTÉE : le champ "Code Unique de la Bande" du
 * prototype est un texte libre pré-rempli par l'utilisateur lui-même, sans
 * continuité réelle possible dans une maquette statique sans backend.
 * `LivestockLot::suggestNextCode()` (nouveau, ticket 3.3) pré-remplit le
 * champ avec le prochain code réellement disponible pour l'espèce choisie
 * (dérivé des préfixes configurés au ticket 2.8), tout en laissant le
 * champ modifiable — fidèle au comportement du champ texte du prototype,
 * tout en honorant réellement l'exigence de continuité du ticket.
 *
 * ⚠️ ÉCART DE SCHÉMA : la modale d'édition du prototype propose 3 statuts
 * ("Actif", "Vendu", "Clôturé") alors que `livestock_lots.status` (schéma
 * documenté, `FULL_MIGRATIONS_DATABASE.md` §6) n'admet que 2 valeurs
 * (`actif`, `cloture`). "Vendu" n'est pas un statut de bande mais une
 * CAUSE de clôture — conservé comme tel : le formulaire propose Actif/
 * Clôturé uniquement, conforme au schéma documenté, sans inventer une 3e
 * valeur d'enum non spécifiée ailleurs.
 *
 * ⚠️ PÉRIMÈTRE DU TIROIR DE DÉTAIL : "Autonomie Alimentaire" reste en
 * attente (aucune table ne suit de stock d'aliment réel avant le Sprint 6,
 * même constat qu'au ticket 3.2). Le résumé de reproduction et les
 * alertes sanitaires restent en attente des tickets 3.10/3.12 — un
 * tiroir affichant les informations réelles de la bande, sans tenter de
 * reconstruire en avance des écrans qui ont leur propre ticket dédié.
 *
 * 🔴→✅ EXTENSION DU PATTERN RBAC CRUD AU NIVEAU ACTION (référence
 * initiale : `PlanComptable`) — `$this->authorize('manage-elevage')` sur
 * les 5 actions mutantes (`newLot`, `saveLot`, `editLot`, `updateLot`,
 * `archiveLot`). Écran pertinent aussi pour la bascule papier→numérique
 * (`STRATEGIE_BASCULE_PAPIER_NUMERIQUE.md`) : c'est ici que l'effectif de
 * départ de chaque bande est saisi au jour J, une action qui doit rester
 * réservée aux rôles habilités.
 */
#[Layout('layouts.app')]
class GestionBandes extends Component
{
    #[Url]
    public string $search = '';

    #[Url]
    public string $filiere = '';

    public ?string $editingLotId = null;

    public ?string $viewingLotId = null;

    // --- Formulaire création/édition ---
    public string $code = '';

    public string $species_id = '';

    public string $stage = 'Reproduction';

    public string $created_date = '';

    public int $quantity = 0;

    public ?int $acquisition_cost = null;

    /**
     * Produit vendable issu de cette bande (ticket 14.37).
     *
     * ⚠️ FACULTATIF. Une bande sans produit rattaché ne génère aucun mouvement
     * de stock — l'exploitation reste libre de ne pas s'en servir, et les
     * bandes déjà créées ne deviennent pas invalides.
     */
    public string $product_id = '';

    public string $status = 'actif';

    /**
     * Produits candidats pour la bande sélectionnée.
     *
     * ⚠️ Restreints à l'ESPÈCE choisie, et les intrants écartés : on ne produit
     * pas de la provende avec un élevage. Sans espèce sélectionnée, la liste
     * reste vide plutôt que de proposer tout le catalogue.
     */
    public function getProduitsCandidatsProperty()
    {
        if (! $this->species_id) {
            return collect();
        }

        return \App\Models\Product::where('is_active', true)
            ->where('species_id', $this->species_id)
            ->where('sku', 'not like', 'ALI-%')
            ->where('sku', 'not like', 'MED-%')
            ->orderBy('name')
            ->get();
    }

    public function getKpisProperty(): array
    {
        $actives = LivestockLot::where('status', 'actif');

        return [
            'bandes_actives' => (clone $actives)->count(),
            'en_reproduction' => (clone $actives)->where('stage', 'reproduction')->count(),
            'effectif_total' => (int) (clone $actives)->sum('current_quantity'),
            // 🔴→✅ TROUVÉ ENCORE "EN ATTENTE (Sprint 3.12)" ALORS QUE LE
            // MODULE EST RÉEL DEPUIS LONGTEMPS — même gap systémique que
            // le Tableau de Bord (`Schema::hasTable` correct mais valeur
            // jamais branchée). `VeterinaryWithdrawalPeriod` (ticket 3.12)
            // et le calendrier de soins existent réellement — compte les
            // bandes actives sous rémanence en cours aujourd'hui.
            'alertes_sanitaires' => \App\Models\VeterinaryWithdrawalPeriod::where('end_date', '>=', now()->toDateString())
                ->whereHas('lot', fn ($q) => $q->where('status', 'actif'))
                ->distinct('lot_id')
                ->count('lot_id'),
        ];
    }

    public function getSpeciesOptionsProperty()
    {
        return LivestockSpecies::enabled()->orderBy('label')->get();
    }

    public function getLotsProperty()
    {
        return LivestockLot::with('species')
            ->where('is_active', true)
            ->when($this->search, fn ($q) => $q->where('code', 'like', '%'.$this->search.'%'))
            ->when($this->filiere, fn ($q) => $q->whereHas('species', fn ($q2) => $q2->where('code', $this->filiere)))
            ->orderByDesc('created_date')
            ->get();
    }

    /**
     * 🔴→✅ TROUVÉ MANQUANT PAR BALAYAGE STRUCTUREL SYSTÉMATIQUE : bouton
     * "Exporter PDF" absent — même schéma déjà trouvé sur de nombreux
     * écrans de ce projet.
     */
    public function exportBandesPdf()
    {
        $this->authorize('view-elevage');

        $lots = $this->lots;

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.gestion-bandes',
            ['lots' => $lots],
            'Gestion des Bandes',
            'État au '.now()->format('d/m/Y')
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'bandes-'.now()->format('Y-m-d').'.pdf');
    }

    public function getViewingLotProperty(): ?LivestockLot
    {
        return $this->viewingLotId ? LivestockLot::with('species')->find($this->viewingLotId) : null;
    }

    public function view(string $id): void
    {
        $this->viewingLotId = $id;
    }

    public function closeDrawer(): void
    {
        $this->viewingLotId = null;
    }

    public function updatedSpeciesId(): void
    {
        $species = LivestockSpecies::find($this->species_id);

        if ($species) {
            $this->code = LivestockLot::suggestNextCode($species->code);
        }
    }

    public function newLot(): void
    {
        $this->authorize('manage-elevage');

        $this->reset(['editingLotId', 'code', 'species_id', 'acquisition_cost']);
        $this->stage = 'Reproduction';
        $this->created_date = now()->format('Y-m-d');
        $this->quantity = 0;
        $this->dispatch('open-modal', name: 'modal-create-bande');
    }

    public function saveLot(): void
    {
        $this->authorize('manage-elevage');

        $this->validate([
            'code' => ['required', 'string', 'max:50', 'unique:livestock_lots,code'],
            'species_id' => ['required', 'exists:livestock_species,id'],
            'stage' => ['required', 'in:Reproduction,Croissance,Ponte,Engraissement'],
            'created_date' => ['required', 'date'],
            'quantity' => ['required', 'integer', 'min:1'],
            'product_id' => ['nullable', 'exists:products,id'],
        ]);

        $stageMap = ['Reproduction' => 'reproduction', 'Croissance' => 'croissance', 'Ponte' => 'ponte', 'Engraissement' => 'engraissement'];

        LivestockLot::create([
            'code' => $this->code,
            'species_id' => $this->species_id,
            // Ticket 14.37 : ce que la bande produit, décidé par l'exploitant.
            'product_id' => $this->product_id ?: null,
            'stage' => $stageMap[$this->stage],
            'initial_quantity' => $this->quantity,
            'current_quantity' => $this->quantity,
            'created_date' => $this->created_date,
            'acquisition_cost' => $this->acquisition_cost,
            'status' => 'actif',
            'is_active' => true,
        ]);

        AuditLog::record('livestock_lot.created', 'elevage');
        $this->dispatch('close-modal', name: 'modal-create-bande');
        $this->dispatch('toast', message: 'Bande créée avec succès.', type: 'success');
        $this->reset(['code', 'species_id', 'quantity', 'acquisition_cost', 'product_id']);
    }

    public function editLot(string $id): void
    {
        $this->authorize('manage-elevage');

        $lot = LivestockLot::findOrFail($id);
        $this->editingLotId = $lot->id;
        $this->code = $lot->code;
        $this->stage = ucfirst($lot->stage);
        $this->quantity = $lot->current_quantity;
        $this->status = $lot->status;
        $this->dispatch('open-modal', name: 'modal-edit-bande');
    }

    public function updateLot(): void
    {
        $this->authorize('manage-elevage');

        $this->validate([
            'stage' => ['required', 'in:Reproduction,Croissance,Ponte,Engraissement'],
            'quantity' => ['required', 'integer', 'min:0'],
            'status' => ['required', 'in:actif,cloture'],
        ]);

        $stageMap = ['Reproduction' => 'reproduction', 'Croissance' => 'croissance', 'Ponte' => 'ponte', 'Engraissement' => 'engraissement'];

        LivestockLot::findOrFail($this->editingLotId)->update([
            'stage' => $stageMap[$this->stage],
            'current_quantity' => $this->quantity,
            'status' => $this->status,
        ]);

        AuditLog::record('livestock_lot.updated', 'elevage');
        $this->dispatch('close-modal', name: 'modal-edit-bande');
        $this->dispatch('toast', message: 'Bande modifiée avec succès.', type: 'success');
    }

    public function archiveLot(string $id): void
    {
        $this->authorize('manage-elevage');

        LivestockLot::findOrFail($id)->update(['is_active' => false]);
        AuditLog::record('livestock_lot.archived', 'elevage');
        $this->dispatch('toast', message: 'Bande archivée avec succès.', type: 'warning');
    }

    public function render()
    {
        return view('livewire.elevage.gestion-bandes', ['title' => 'Élevage > Bandes & Sujets']);
    }
}
