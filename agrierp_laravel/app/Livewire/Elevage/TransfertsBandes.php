<?php

namespace App\Livewire\Elevage;

use App\Actions\TransferBetweenLotsAction;
use App\Models\AuditLog;
use App\Models\LivestockLot;
use App\Models\LivestockTransfer;
use App\Services\EffectifParCategorieService;
use App\Support\ExerciceChoisi;
use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\ValidationException;
use Livewire\Attributes\Layout;
use Livewire\Component;
use Livewire\WithPagination;

/**
 * Ticket 15.46 — ÉCRAN DÉDIÉ « TRANSFERTS ENTRE BANDES » (A2, décision client du 17/10/2026).
 *
 * ⚠️ Écran ABSENT du prototype HTML : construit d'abord sur le web (Doctrine, article 0), avec les composants
 * partagés (`x-kpi-card`, `x-modal`, tableau `rtable`) et les jetons existants, puis porté sur le poste.
 *
 * Trois usages :
 *  1. transférer des sujets d'une bande à une autre (portée sevrée, regroupement, tri par catégorie) ;
 *  2. RATTACHER une bande existante à sa bande d'origine (constitution) : corrige le double comptage des
 *     bandes créées pour une portée déjà comptée dans la bande mère ;
 *  3. consulter et annuler un transfert (jamais supprimé).
 * Tous les calculs passent par `TransferBetweenLotsAction` : l'écran n'en refait aucun.
 */
#[Layout('layouts.app')]
class TransfertsBandes extends Component
{
    use WithPagination;

    public string $source_lot_id = '';

    public string $target_lot_id = '';

    public string $transfer_date = '';

    public int $quantity = 1;

    public string $categorie = '';

    public bool $constitution = false;

    public string $motif = '';

    public function mount(): void
    {
        $this->transfer_date = now()->format('Y-m-d');
    }

    public function getLotsProperty()
    {
        return LivestockLot::with('species')->where('is_active', true)->orderBy('code')->get();
    }

    public function getSourceProperty(): ?LivestockLot
    {
        return $this->lots->firstWhere('id', $this->source_lot_id);
    }

    /** Bandes de la même espèce que la source, la source exclue. */
    public function getCiblesProperty()
    {
        $source = $this->source;

        return $source === null
            ? collect()
            : $this->lots->filter(fn ($l) => $l->species_id === $source->species_id && $l->id !== $source->id)->values();
    }

    /** Catégories proposées pour la source : libellés du glossaire du 17/10/2026 (lapins) et des porcs. */
    public function getCategoriesProperty(): array
    {
        $source = $this->source;
        $espece = $source ? EffectifParCategorieService::especeDuLot($source) : null;

        return match ($espece) {
            EffectifParCategorieService::LAPINS => ['repro' => 'Reproducteur', 'sevre' => 'Sous-mères', 'jeune' => 'Jeune'],
            EffectifParCategorieService::PORCS => ['repro' => 'Reproducteur', 'sevre' => 'Porcelet', 'jeune' => 'Porc Marchand'],
            default => [],
        };
    }

    /**
     * Ticket EX7 (EF9) — les transferts de l'exercice AFFICHÉ, PAGINÉS (25 par page), au lieu des 100 derniers toutes
     * années confondues.
     */
    public function getTransfertsProperty()
    {
        [$debut, $fin] = ExerciceChoisi::bornes();

        return LivestockTransfer::with(['source', 'cible', 'user'])
            ->whereDate('transfer_date', '>=', $debut)
            ->whereDate('transfer_date', '<=', $fin)
            ->orderByDesc('transfer_date')->orderByDesc('created_at')->orderByDesc('id')
            ->paginate(ExerciceChoisi::PAR_PAGE, pageName: 'pageTransferts');
    }

    /**
     * Bandes vivantes sans bande d'origine, qui ont au moins une autre bande vivante de la même espèce créée
     * AVANT elles : seules celles-là peuvent être issues d'une autre. Le rattachement reste une décision de
     * l'exploitant : l'écran ne devine aucune filiation.
     */
    public function getBandesARattacherProperty()
    {
        $lots = $this->lots;

        return $lots->filter(function (LivestockLot $lot) use ($lots) {
            if ($lot->lot_source_id !== null || $lot->created_date === null) {
                return false;
            }

            return $lots->contains(fn (LivestockLot $autre) => $autre->id !== $lot->id
                && $autre->species_id === $lot->species_id
                && $autre->created_date !== null
                && $autre->created_date->lt($lot->created_date));
        })->values();
    }

    public function getKpisProperty(): array
    {
        // Ticket EX7 — le mois de référence de l'exercice affiché (le mois du jour, ou le dernier mois de 2026 lu en 2027).
        $mois = ExerciceChoisi::moisDeReference();
        $duMois = LivestockTransfer::actifs()
            ->whereBetween('transfer_date', [$mois->toDateString(), $mois->copy()->endOfMonth()->toDateString()]);

        return [
            'transferts_mois' => (clone $duMois)->count(),
            'sujets_mois' => (int) (clone $duMois)->sum('quantity'),
            'bandes_rattachees' => LivestockLot::where('is_active', true)->whereNotNull('lot_source_id')->count(),
            'a_verifier' => $this->bandesARattacher->count(),
        ];
    }

    /** Rattachement : bandes de la même espèce créées au plus tard le jour de la bande à rattacher. */
    public function getSourcesProperty()
    {
        $cible = $this->constitution ? $this->lots->firstWhere('id', $this->target_lot_id) : null;

        return $cible === null
            ? $this->lots
            : $this->lots->filter(fn ($l) => $l->id !== $cible->id
                && $l->species_id === $cible->species_id
                && $l->created_date !== null
                && $l->created_date->lte($cible->created_date))->values();
    }

    public function updatedSourceLotId(): void
    {
        // En rattachement, la bande cible est fixée par le bouton « Rattacher » : seule la source se choisit.
        if (! $this->constitution) {
            $this->target_lot_id = '';
            $this->categorie = '';
        }
    }

    public function nouveauTransfert(): void
    {
        $this->authorize('manage-elevage');

        $this->resetErrorBag();
        $this->reset(['source_lot_id', 'target_lot_id', 'categorie', 'motif']);
        $this->constitution = false;
        $this->quantity = 1;
        $this->transfer_date = now()->format('Y-m-d');
        $this->dispatch('open-modal', name: 'modal-transfert');
    }

    /** Prépare le rattachement d'une bande à sa bande d'origine : date et effectif de création de la bande. */
    public function rattacher(string $lotId): void
    {
        $this->authorize('manage-elevage');

        $lot = LivestockLot::findOrFail($lotId);
        $this->resetErrorBag();
        $this->reset(['source_lot_id', 'motif']);
        $this->target_lot_id = $lot->id;
        $this->constitution = true;
        $this->quantity = (int) $lot->initial_quantity;
        $this->transfer_date = $lot->created_date->format('Y-m-d');
        $this->categorie = EffectifParCategorieService::categorieDuStade($lot->stage) ?? '';
        $this->dispatch('open-modal', name: 'modal-transfert');
    }

    public function enregistrer(): void
    {
        $this->authorize('manage-elevage');

        $this->validate([
            'source_lot_id' => ['required', 'exists:livestock_lots,id'],
            'target_lot_id' => ['required', 'exists:livestock_lots,id', 'different:source_lot_id'],
            'transfer_date' => ['required', 'date', 'before_or_equal:today'],
            'quantity' => ['required', 'integer', 'min:1'],
            'categorie' => ['nullable', 'in:repro,sevre,jeune'],
            'motif' => ['nullable', 'string', 'max:255'],
        ], [], [
            'source_lot_id' => 'bande source', 'target_lot_id' => 'bande cible',
            'transfer_date' => 'date du transfert', 'quantity' => 'nombre de sujets',
        ]);

        try {
            app(TransferBetweenLotsAction::class)->execute([
                'source_lot_id' => $this->source_lot_id,
                'target_lot_id' => $this->target_lot_id,
                'transfer_date' => $this->transfer_date,
                'quantity' => $this->quantity,
                'categorie' => $this->categorie ?: null,
                'constitution' => $this->constitution,
                'motif' => $this->motif ?: null,
            ], Auth::user());
        } catch (ValidationException $e) {
            $this->addError('transfert', collect($e->errors())->flatten()->first());

            return;
        }

        AuditLog::record($this->constitution ? 'livestock_transfer.constitution' : 'livestock_transfer.created', 'elevage');
        $this->dispatch('close-modal', name: 'modal-transfert');
        $this->dispatch('toast', message: $this->constitution
            ? 'Bande rattachée à sa bande d\'origine : les sujets ne sont plus comptés deux fois.'
            : 'Transfert enregistré : les deux bandes sont recalculées.', type: 'success');
    }

    public function annuler(string $id): void
    {
        $this->authorize('manage-elevage');

        try {
            app(TransferBetweenLotsAction::class)->annuler(LivestockTransfer::findOrFail($id));
        } catch (ValidationException $e) {
            $this->dispatch('toast', message: collect($e->errors())->flatten()->first(), type: 'error');

            return;
        }

        AuditLog::record('livestock_transfer.cancelled', 'elevage');
        $this->dispatch('toast', message: 'Transfert annulé : les deux bandes sont recalculées.', type: 'warning');
    }

    public function render()
    {
        return view('livewire.elevage.transferts-bandes', ['title' => 'Élevage > Transferts entre Bandes']);
    }
}
