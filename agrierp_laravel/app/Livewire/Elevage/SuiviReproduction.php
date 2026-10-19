<?php

namespace App\Livewire\Elevage;

use App\Models\Animal;
use App\Models\AuditLog;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockReproductionEvent;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 3.10 (Sprint 3) — suivi-reproduction.html → Livewire\Elevage\SuiviReproduction
 *
 * ⚠️ NON-DUPLICATION DÉLIBÉRÉE (piège déjà rencontré, cf. ticket 2.3) :
 * les panneaux "Volailles" et "Escargots" du prototype (workflow
 * Incubation/Couvoir/Éclosion) recouvrent EXACTEMENT ce que
 * `Livewire\Elevage\FicheReproducteurs` (ticket 3.7) et
 * `Livewire\Elevage\FicheEscargots` (ticket 3.9) implémentent déjà
 * réellement (`ponte_total`/`ne` sur `livestock_daily_entries`). Les
 * reconstruire ici créerait deux formulaires de saisie distincts pour la
 * même donnée — précisément le piège que ce projet a déjà rencontré.
 * Ces deux onglets affichent donc un résumé RÉEL (agrégats du mois, mêmes
 * requêtes que les fiches concernées) et renvoient vers l'écran de saisie
 * réel plutôt que de dupliquer un formulaire.
 *
 * Lapins et Porcs sont, eux, réellement fonctionnels ici : c'est le seul
 * endroit du système qui suit le cycle de reproduction PAR FEMELLE NOMMÉE
 * (R1, R2... / T1, T2...) — les fiches journalières (3.5, 3.8) ne
 * suivent que des agrégats de bande, jamais une femelle individuelle.
 * `livestock_reproduction_events` (créée au ticket 3.1, inutilisée
 * jusqu'ici) trouve enfin son usage réel.
 *
 * Échéances calculées (Document 05) :
 *   Lapins : Palpation J+14, Mise bas J+30, Sevrage J+60
 *   Porcs  : Retour chaleur J+21, Mise bas J+114, Sevrage J+42
 * "Boîte à nid J+28" (lapins) reste informative dans l'aperçu de saisie,
 * non persistée (aucune colonne dédiée, simple jalon intermédiaire sans
 * action de suivi propre).
 *
 * "Cages Occupées" du prototype non repris — aucune table ne modélise de
 * sous-division "cage" (même constat qu'au ticket 3.5, non tranché avec
 * vous à ce stade).
 *
 * ⚠️ TICKET H11 (décision client D-H-maquette du 19/10/2026) — les ajouts du poste
 * (`agrierp_flutter/lib/features/elevage/suivi_reproduction_screen.dart`) sont construits ici, APRÈS ce que le
 * Blade affichait, avec les mêmes calculs et libellés :
 * - ligne annexe « Boîte à nid J+28 » sous le rappel du cycle lapin ;
 * - colonnes après les neuf du Blade — Lapins : Sevrés (M/F) « — », Morts S/Mère (`nes_morts`), Poids Moyen (g) « — »,
 *   Cages « — » (le cycle ne porte ni sevrés, ni ventilation M/F, ni pesée, ni cage) ; Porcs : Sevrage (J+42) =
 *   date stockée, sinon mise bas réelle + 42 j ;
 * - carte « Bandes suivies » et bandeau « Rappel du cycle » Volailles / Escargots ;
 * - modale lapin : champ « Cages Occupées » DÉSACTIVÉ (toujours aucun référentiel de cage pour le porter) et aperçu
 *   « Ligne du temps automatique calculée » ;
 * - N° de femelle / de mâle : lien vers la fiche du sujet (`elevage.animal-details`) quand un sujet porte ce nom.
 * Le bandeau « lecture seule » du poste n'est pas repris : il dit ce qui reste réservé au web.
 */
#[Layout('layouts.app')]
class SuiviReproduction extends Component
{
    #[Url]
    public string $tab = 'lapins';

    // --- Déclaration de saillie ---
    public string $lotId = '';

    public string $motherRef = '';

    public string $sireRef = '';

    public string $saillieDate = '';

    // --- Enregistrement mise bas ---
    public ?string $miseBasEventId = null;

    public int $nesVivants = 0;

    public int $nesMorts = 0;

    public function mount(): void
    {
        $this->saillieDate = now()->format('Y-m-d');
    }

    private function speciesCodeForTab(string $tab): ?string
    {
        return match ($tab) {
            'lapins' => 'cuniculture',
            'porcs' => 'porciculture',
            default => null,
        };
    }

    public function getKpisProperty(): array
    {
        $activeEvents = LivestockReproductionEvent::whereHas('lot.species', fn ($q) => $q->whereIn('code', ['cuniculture', 'porciculture']))
            ->where('status', 'en_cours')
            ->get();

        $gestantes = $activeEvents->whereNull('mise_bas_date_actual')->count();
        $palpationsDues = $activeEvents->filter(fn ($e) => $e->palpation_date === null && $e->saillie_date && now()->gte($e->saillie_date->copy()->addDays(14)))->count();
        $misesBasMois = LivestockReproductionEvent::whereBetween('mise_bas_date_actual', [now()->startOfMonth(), now()->endOfMonth()])->count();
        // 🔴→✅ Ticket U13 — « Échecs (mois) » : le mois de l'ANNÉE courante. `whereMonth` seul comptait aussi les échecs
        // d'octobre 2025, 2024… dans « octobre » (le poste, lui, vérifiait déjà l'année).
        $echecs = LivestockReproductionEvent::where('status', 'echec')
            ->whereYear('updated_at', now()->year)
            ->whereMonth('updated_at', now()->month)
            ->count();

        return [
            'gestantes' => $gestantes,
            'palpations_dues' => $palpationsDues,
            'mises_bas_mois' => $misesBasMois,
            'echecs' => $echecs,
        ];
    }

    public function getLotsForTabProperty()
    {
        $speciesCode = $this->speciesCodeForTab($this->tab);

        if (! $speciesCode) {
            return collect();
        }

        return LivestockLot::whereHas('species', fn ($q) => $q->where('code', $speciesCode))
            ->where('status', 'actif')->where('is_active', true)->get();
    }

    public function getEventsForTabProperty()
    {
        $speciesCode = $this->speciesCodeForTab($this->tab);

        if (! $speciesCode) {
            return collect();
        }

        return LivestockReproductionEvent::with('lot')
            ->whereHas('lot.species', fn ($q) => $q->where('code', $speciesCode))
            ->orderByDesc('saillie_date')
            ->get();
    }

    /** Résumé réel Volailles/Escargots — mêmes données que les fiches dédiées (3.7/3.9), jamais dupliquées. */
    public function getIncubationSummaryProperty(): array
    {
        $speciesCode = $this->tab === 'volailles' ? 'aviculture' : ($this->tab === 'escargots' ? 'helico' : null);

        if (! $speciesCode) {
            return [];
        }

        $lots = LivestockLot::whereHas('species', fn ($q) => $q->where('code', $speciesCode))->where('is_active', true)->get();
        $entries = LivestockDailyEntry::whereIn('lot_id', $lots->pluck('id'))
            ->whereBetween('entry_date', [now()->startOfMonth(), now()->endOfMonth()])
            ->get();

        $couves = $entries->sum('ponte_total');
        $nes = $entries->sum('ne');

        return [
            'couves' => (int) $couves,
            'nes' => (int) $nes,
            // 🔴→✅ Ticket U14 — sans un œuf couvé dans le mois, le taux est INCONNU (« — »), jamais « 0,0 % ».
            'taux_eclosion' => $couves > 0 ? round(($nes / $couves) * 100, 1) : null,
            // Ticket H11 — carte « Bandes suivies » du poste : les bandes NON ARCHIVÉES de l'espèce (`ResumeCouvoir.lots`).
            'lots' => $lots->count(),
        ];
    }

    /**
     * Ticket H11 — cellules des colonnes ajoutées du poste, par cycle de l'onglet, dans l'ordre des en-têtes.
     *
     * @return array<string, array<int, string>>
     */
    public function getColonnesPosteProperty(): array
    {
        $cellules = [];

        foreach ($this->eventsForTab as $event) {
            $cellules[$event->id] = $this->tab === 'porcs'
                // Sevrage : stocké, sinon déduit de la mise bas réelle (J+42), sinon inconnu.
                ? [$event->sevrage_date_expected?->format('d/m/Y')
                    ?? $event->mise_bas_date_actual?->copy()->addDays(42)->format('d/m/Y')
                    ?? '—']
                : ['—', $event->nes_morts === null ? '—' : (string) $event->nes_morts, '—', '—'];
        }

        return $cellules;
    }

    /**
     * Ticket H11 — sujets enregistrés (`identifier → id`) : une référence de femelle ou de mâle n'est un LIEN que si un
     * sujet porte ce nom (« R1 » peut aussi être une lapine jamais enregistrée ; un lien vers une fiche inexistante
     * serait pire que du texte).
     *
     * @return array<string, string>
     */
    public function getSujetsConnusProperty(): array
    {
        return Animal::pluck('id', 'identifier')->all();
    }

    public function newDeclaration(): void
    {
        $this->reset(['lotId', 'motherRef', 'sireRef']);
        $this->saillieDate = now()->format('Y-m-d');
        $this->dispatch('open-modal', name: 'modal-saillie');
    }

    public function saveDeclaration(): void
    {
        $this->authorize('manage-elevage');

        $this->validate([
            'lotId' => ['required', 'exists:livestock_lots,id'],
            'motherRef' => ['required', 'string', 'max:50'],
            'sireRef' => ['nullable', 'string', 'max:50'],
            'saillieDate' => ['required', 'date'],
        ]);

        // 🔴→✅ TICKET 14.73 — UN SEUL CYCLE EN COURS PAR FEMELLE.
        //
        // ⚠️ Ce garde-fou MANQUAIT. Deux saillies declarees sur R1 — deux
        // clics, ou le poste et le bureau le meme jour — produisaient deux
        // gestations concurrentes sur le meme animal : l'ecran les affichait
        // toutes deux, le KPI « gestantes » comptait double, et rien ne
        // signalait laquelle etait la bonne. Trouve en ouvrant le canal
        // d'envoi, ou la meme regle devait etre posee.
        $dejaEnCours = LivestockReproductionEvent::where('lot_id', $this->lotId)
            ->where('mother_ref', $this->motherRef)
            ->where('status', 'en_cours')
            ->exists();

        if ($dejaEnCours) {
            $this->addError('motherRef', "Un cycle est deja en cours pour {$this->motherRef} sur cette bande.");

            return;
        }

        LivestockReproductionEvent::create([
            'lot_id' => $this->lotId,
            'mother_ref' => $this->motherRef,
            'sire_ref' => $this->sireRef ?: null,
            'saillie_date' => $this->saillieDate,
            'status' => 'en_cours',
        ]);

        AuditLog::record('reproduction_event.created', 'elevage');
        $this->dispatch('close-modal', name: 'modal-saillie');
        $this->dispatch('toast', message: 'Saillie enregistrée avec succès.', type: 'success');
    }

    public function recordPalpation(string $id, bool $positive): void
    {
        $this->authorize('manage-elevage');

        LivestockReproductionEvent::findOrFail($id)->update([
            'palpation_date' => now()->format('Y-m-d'),
            'status' => $positive ? 'en_cours' : 'echec',
        ]);

        AuditLog::record('reproduction_event.palpation_recorded', 'elevage');
        $this->dispatch('toast', message: 'Palpation enregistrée avec succès.', type: 'success');
    }

    public function openMiseBasModal(string $id): void
    {
        $this->miseBasEventId = $id;
        $this->nesVivants = 0;
        $this->nesMorts = 0;
        $this->dispatch('open-modal', name: 'modal-misebas');
    }

    public function saveMiseBas(): void
    {
        $this->authorize('manage-elevage');

        $this->validate([
            'nesVivants' => ['required', 'integer', 'min:0'],
            'nesMorts' => ['required', 'integer', 'min:0'],
        ]);

        LivestockReproductionEvent::findOrFail($this->miseBasEventId)->update([
            'mise_bas_date_actual' => now()->format('Y-m-d'),
            'nes_vivants' => $this->nesVivants,
            'nes_morts' => $this->nesMorts,
        ]);

        AuditLog::record('reproduction_event.misebas_recorded', 'elevage');
        $this->dispatch('close-modal', name: 'modal-misebas');
        $this->dispatch('toast', message: 'Mise bas enregistrée avec succès.', type: 'success');
    }

    public function closeCycle(string $id): void
    {
        $this->authorize('manage-elevage');

        LivestockReproductionEvent::findOrFail($id)->update(['status' => 'termine']);
        AuditLog::record('reproduction_event.closed', 'elevage');
        $this->dispatch('toast', message: 'Cycle clôturé (sevrage effectué).', type: 'success');
    }

    public function render()
    {
        return view('livewire.elevage.suivi-reproduction', ['title' => 'Élevage > Suivi Reproduction']);
    }
}
