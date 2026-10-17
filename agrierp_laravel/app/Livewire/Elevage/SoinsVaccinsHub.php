<?php

namespace App\Livewire\Elevage;

use App\Actions\RecordVeterinaryCareAction;
use App\Models\AuditLog;
use App\Models\InfirmaryRecord;
use App\Models\LivestockLot;
use App\Models\VeterinaryCalendarEvent;
use App\Models\VeterinaryRecord;
use App\Models\VeterinaryWithdrawalPeriod;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 3.11 (Sprint 3) — soins-vaccins-hub.html → Livewire\Elevage\SoinsVaccinsHub
 * Hub à 3 onglets (le prototype charge 3 iframes — vms-registre.html,
 * vms-calendrier.html, vms-suivi.html — converties en sections d'un seul
 * composant, Document 02 §4, même traitement qu'au ticket 2.3).
 *
 * ⚠️ MÉCANISME RÉEL DE LA RÉMANENCE (règle URGENTE, message de lancement
 * du projet) : `saveSoin()` crée une `VeterinaryWithdrawalPeriod` dès que
 * le délai saisi est > 0 — exactement le comportement décrit dans le
 * prototype ("Si > 0, la bande sera automatiquement bloquée à la vente").
 * Le blocage RÉEL au moment de la vente est du ressort du POS (Sprint 4),
 * mais `VeterinaryWithdrawalPeriod::isLotBlocked()` est déjà prête à être
 * appelée à ce moment-là — un seul point de vérité pour cette règle.
 *
 * ⚠️ CE TICKET DÉBLOQUE ENFIN LE "MOTEUR AUTOMATIQUE DE PROPHYLAXIE" laissé
 * en bandeau d'attente sur les 5 fiches espèces (tickets 3.5-3.9) — non
 * reconnecté automatiquement ici (portée de CE ticket = le hub lui-même) ;
 * le calendrier réel existe désormais, la connexion des fiches au calendrier
 * reste un ticket de câblage distinct, à faire dans une session dédiée
 * plutôt qu'ajoutée en fin de ticket déjà dense.
 *
 * Boutons de démonstration retirés (Document AVOID_INSTRUCTIONS.md) :
 * "Tester Rémanence" (vms-registre.html). Import CSV/Excel du registre
 * différé (fonctionnalité indépendante substantielle, hors périmètre de
 * ce ticket déjà dense — à trancher comme ticket séparé si prioritaire).
 */
#[Layout('layouts.app')]
class SoinsVaccinsHub extends Component
{
    #[Url]
    public string $tab = 'registre';

    // --- Nouveau Soin ---
    public string $soinLotId = '';

    public string $soinDate = '';

    public string $soinType = '';

    public string $soinProduit = '';

    public string $soinDose = '';

    public int $soinRemanence = 0;

    public string $soinVeterinaire = '';

    public string $soinSymptomes = '';

    public ?int $soinCout = null;

    // --- Planifier une Intervention ---
    public string $planLotId = '';

    public string $planTaskType = '';

    public string $planDate = '';

    // --- Nouvelle Entrée Infirmerie ---
    public string $infLotId = '';

    public string $infSujetRef = '';

    public string $infMotif = '';

    public string $infIsolation = '';

    public string $infDate = '';

    public function mount(): void
    {
        $today = now()->format('Y-m-d');
        $this->soinDate = $today;
        $this->planDate = $today;
        $this->infDate = $today;
    }

    public function getActiveLotsProperty()
    {
        return LivestockLot::with('species')->where('status', 'actif')->where('is_active', true)->get();
    }

    // ===================== REGISTRE =====================
    public function getKpisRegistreProperty(): array
    {
        $monthRecords = VeterinaryRecord::whereMonth('record_date', now()->month)->whereYear('record_date', now()->year);

        return [
            'interventions_mois' => (clone $monthRecords)->count(),
            'vaccinations_planifiees' => VeterinaryCalendarEvent::where('status', 'planned')->count(),
            'en_quarantaine' => InfirmaryRecord::where('status', 'en_cours')->count(),
            'cout_sanitaire_mois' => (float) (clone $monthRecords)->sum('cost'),
        ];
    }

    public function getVeterinaryRecordsProperty()
    {
        return VeterinaryRecord::with('lot.species')->where('is_active', true)->orderByDesc('record_date')->limit(50)->get();
    }

    public function newSoin(): void
    {
        $this->reset(['soinLotId', 'soinType', 'soinProduit', 'soinDose', 'soinVeterinaire', 'soinSymptomes', 'soinCout']);
        $this->soinRemanence = 0;
        $this->soinDate = now()->format('Y-m-d');
        $this->dispatch('open-modal', name: 'modal-nouveau-soin');
    }

    public function saveSoin(): void
    {
        $this->validate([
            'soinLotId' => ['required', 'exists:livestock_lots,id'],
            'soinDate' => ['required', 'date'],
            'soinType' => ['required', 'string'],
        ]);

        // ⚠️ TICKET 14.54 — LA RÈGLE A ÉTÉ EXTRAITE dans
        // `RecordVeterinaryCareAction`. Elle vivait ici, donc inatteignable
        // depuis la synchronisation : un soin administré hors ligne créait le
        // registre SANS sa période de rémanence, et la bande restait vendable.
        // Une protection sanitaire ne doit exister qu'en un seul exemplaire.
        app(RecordVeterinaryCareAction::class)->execute([
            'lot_id' => $this->soinLotId,
            'action_type' => $this->soinType,
            'product_used' => $this->soinProduit ?: null,
            'dose' => $this->soinDose ?: null,
            'vet_name' => $this->soinVeterinaire ?: null,
            'symptomes' => $this->soinSymptomes ?: null,
            'cost' => $this->soinCout,
            'record_date' => $this->soinDate,
        ], (int) $this->soinRemanence);

        AuditLog::record('veterinary_record.created', 'elevage');
        $this->dispatch('close-modal', name: 'modal-nouveau-soin');
        $message = $this->soinRemanence > 0
            ? "Soin enregistré — bande bloquée à la vente pendant {$this->soinRemanence} jour(s)."
            : 'Soin enregistré avec succès.';
        $this->dispatch('toast', message: $message, type: 'success');
    }

    public function archiveSoin(string $id): void
    {
        $this->authorize('manage-elevage');

        VeterinaryRecord::findOrFail($id)->update(['is_active' => false]);
        AuditLog::record('veterinary_record.archived', 'elevage');
        $this->dispatch('toast', message: 'Fiche archivée avec succès.', type: 'warning');
    }

    // ===================== CALENDRIER (Gantt 14 jours) =====================
    public function getGanttDaysProperty(): array
    {
        return collect(range(0, 13))->map(fn ($i) => now()->addDays($i)->format('Y-m-d'))->all();
    }

    public function getGanttRowsProperty()
    {
        $days = $this->ganttDays;

        return $this->activeLots->map(function ($lot) use ($days) {
            $events = VeterinaryCalendarEvent::where('lot_id', $lot->id)
                ->whereIn('scheduled_date', $days)
                ->get()
                ->keyBy(fn ($e) => $e->scheduled_date->format('Y-m-d'));

            return ['lot' => $lot, 'events' => $events];
        });
    }

    public function newIntervention(): void
    {
        $this->reset(['planLotId', 'planTaskType']);
        $this->planDate = now()->format('Y-m-d');
        $this->dispatch('open-modal', name: 'modal-planifier-intervention');
    }

    public function savePlan(): void
    {
        $this->authorize('manage-elevage');

        $this->validate([
            'planLotId' => ['required', 'exists:livestock_lots,id'],
            'planTaskType' => ['required', 'string', 'max:100'],
            'planDate' => ['required', 'date'],
        ]);

        VeterinaryCalendarEvent::create([
            'lot_id' => $this->planLotId,
            'task_type' => $this->planTaskType,
            'scheduled_date' => $this->planDate,
            'status' => 'planned',
        ]);

        AuditLog::record('veterinary_calendar_event.created', 'elevage');
        $this->dispatch('close-modal', name: 'modal-planifier-intervention');
        $this->dispatch('toast', message: 'Intervention planifiée avec succès.', type: 'success');
    }

    public function confirmAdministration(string $id): void
    {
        $this->authorize('manage-elevage');

        VeterinaryCalendarEvent::findOrFail($id)->update(['status' => 'done']);
        AuditLog::record('veterinary_calendar_event.confirmed', 'elevage');
        $this->dispatch('toast', message: 'Administration confirmée avec succès.', type: 'success');
    }

    // ===================== SUIVI SANITAIRE (Infirmerie) =====================
    public function getKpisInfirmerieProperty(): array
    {
        $monthRecords = InfirmaryRecord::whereMonth('entry_date', now()->month)->whereYear('entry_date', now()->year);
        $effectifTotal = LivestockLot::where('status', 'actif')->sum('current_quantity');
        $enCours = InfirmaryRecord::where('status', 'en_cours')->count();

        return [
            'en_quarantaine' => $enCours,
            'gueris_mois' => (clone $monthRecords)->where('status', 'reintegre')->count(),
            'sous_traitement' => $enCours,
            'deces_mois' => (clone $monthRecords)->where('status', 'deces')->count(),
            'taux_infirmerie' => $effectifTotal > 0 ? round(($enCours / $effectifTotal) * 100, 1) : 0.0,
        ];
    }

    public function getInfirmaryRecordsProperty()
    {
        return InfirmaryRecord::with('lot')->orderByDesc('entry_date')->limit(50)->get();
    }

    public function newInfirmaryEntry(): void
    {
        $this->reset(['infLotId', 'infSujetRef', 'infMotif', 'infIsolation']);
        $this->infDate = now()->format('Y-m-d');
        $this->dispatch('open-modal', name: 'modal-nouvelle-entree-infirmerie');
    }

    public function saveInfirmaryEntry(): void
    {
        $this->authorize('manage-elevage');

        $this->validate([
            'infLotId' => ['required', 'exists:livestock_lots,id'],
            'infMotif' => ['required', 'string', 'max:255'],
            'infIsolation' => ['required', 'string'],
            'infDate' => ['required', 'date'],
        ]);

        InfirmaryRecord::create([
            'lot_id' => $this->infLotId,
            'sujet_ref' => $this->infSujetRef ?: null,
            'motif' => $this->infMotif,
            'isolation_level' => $this->infIsolation,
            'entry_date' => $this->infDate,
            'status' => 'en_cours',
        ]);

        AuditLog::record('infirmary_record.created', 'elevage');
        $this->dispatch('close-modal', name: 'modal-nouvelle-entree-infirmerie');
        $this->dispatch('toast', message: 'Entrée infirmerie enregistrée avec succès.', type: 'success');
    }

    public function reintegrer(string $id): void
    {
        $this->authorize('manage-elevage');

        InfirmaryRecord::findOrFail($id)->update(['status' => 'reintegre']);
        AuditLog::record('infirmary_record.reintegrated', 'elevage');
        $this->dispatch('toast', message: 'Sujet réintégré avec succès.', type: 'success');
    }

    public function declarerDeces(string $id): void
    {
        $this->authorize('manage-elevage');

        InfirmaryRecord::findOrFail($id)->update(['status' => 'deces']);
        AuditLog::record('infirmary_record.death_declared', 'elevage');
        $this->dispatch('toast', message: 'Décès déclaré.', type: 'warning');
    }

    public function render()
    {
        return view('livewire.elevage.soins-vaccins-hub', ['title' => 'Élevage > Soins et Vaccins']);
    }
}
