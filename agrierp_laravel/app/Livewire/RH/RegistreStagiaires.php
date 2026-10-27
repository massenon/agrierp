<?php

namespace App\Livewire\RH;

use App\Models\AuditLog;
use App\Models\Internship;
use App\Models\InternshipAbsence;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * registre-stagiaires.html → Livewire\RH\RegistreStagiaires
 * "Suivi des stagiaires, frais de formation, absences et attestations —
 * distinct du personnel permanent."
 *
 * "Nom complet" (un seul champ dans le prototype) scindé en Prénom/Nom,
 * même traitement que `RegistreEmployes` (ticket 8.2) pour respecter le
 * schéma réel.
 *
 * "Statut" (En cours/Terminé) dérivé de `Internship::is_active`
 * (accessor déjà réel depuis le ticket 8.1, comparaison à `end_date`) —
 * jamais un second champ statut stocké séparément qui pourrait diverger
 * de la date de fin réelle.
 *
 * Gestion des absences réelle (`internship_absences`, ticket 8.1) —
 * ajout/suppression d'une date d'absence par stagiaire.
 *
 * "Générer attestation" : renvoie vers l'onglet Attestations du hub
 * (ticket 8.8, terminé) plutôt que de dupliquer un mini-générateur PDF
 * ici — un seul point de génération, pas deux.
 *
 * 🔴→✅ 4e CARTE KPI ("Attestations Émises") TROUVÉE MANQUANTE PAR
 * COMPARAISON STRUCTURELLE RIGOUREUSE — réutilise `AuditLog`, déjà
 * réellement alimentée par `Attestations::generateAttestation()`
 * (ticket 8.8) à chaque génération réussie, jamais une table de
 * comptage dédiée inventée pour ce seul KPI. L'action tracée a été
 * affinée en `attestation.generated.stagiaire`/`.employe` (au lieu
 * d'un seul `attestation.generated` générique) pour permettre ce
 * comptage filtré par type de personne.
 */
class RegistreStagiaires extends Component
{
    #[Url]
    public string $search = '';

    #[Url]
    public string $statusFilter = '';

    public ?string $editingInternshipId = null;

    public string $firstName = '';

    public string $lastName = '';

    public string $school = '';

    public string $startDate = '';

    public string $endDate = '';

    public ?float $monthlyFee = null;

    public bool $feePaid = false;

    public ?string $absenceInternshipId = null;

    public string $absenceDate = '';

    public string $absenceReason = '';

    public function mount(): void
    {
        $this->startDate = now()->format('Y-m-d');
    }

    public function getKpisProperty(): array
    {
        $internships = Internship::all();
        $active = $internships->filter(fn ($i) => $i->is_active);

        return [
            'stagiaires_actifs' => $active->count(),
            'frais_collectes' => (float) $internships->where('fee_paid', true)->sum('monthly_fee'),
            'frais_en_attente' => (float) $internships->where('fee_paid', false)->sum('monthly_fee'),
            // 🔴→✅ TROUVÉ MANQUANT PAR COMPARAISON STRUCTURELLE RIGOUREUSE
            // (4e carte KPI du prototype absente) — réutilise `AuditLog`,
            // déjà réellement alimentée à chaque génération d'attestation
            // (ticket 8.8), jamais une table de comptage dédiée inventée
            // pour ce seul KPI.
            'attestations_emises' => AuditLog::where('action', 'attestation.generated.stagiaire')->count(),
        ];
    }

    public function getInternshipsProperty()
    {
        return Internship::when($this->search, fn ($q) => $q->where(fn ($q2) => $q2->where('first_name', 'like', '%'.$this->search.'%')->orWhere('last_name', 'like', '%'.$this->search.'%')))
            ->orderByDesc('start_date')
            ->get()
            ->when($this->statusFilter === 'En cours', fn ($rows) => $rows->filter(fn ($i) => $i->is_active))
            ->when($this->statusFilter === 'Terminé', fn ($rows) => $rows->filter(fn ($i) => ! $i->is_active));
    }

    public function newInternship(): void
    {
        $this->reset(['editingInternshipId', 'firstName', 'lastName', 'school', 'endDate', 'monthlyFee']);
        $this->feePaid = false;
        $this->startDate = now()->format('Y-m-d');
        $this->dispatch('open-modal', name: 'modal-create-stagiaire');
    }

    public function editInternship(string $id): void
    {
        $internship = Internship::findOrFail($id);
        $this->editingInternshipId = $internship->id;
        $this->firstName = $internship->first_name;
        $this->lastName = $internship->last_name;
        $this->school = (string) $internship->school;
        $this->startDate = $internship->start_date->format('Y-m-d');
        $this->endDate = $internship->end_date?->format('Y-m-d') ?? '';
        $this->monthlyFee = $internship->monthly_fee ? (float) $internship->monthly_fee : null;
        $this->feePaid = $internship->fee_paid;
        $this->dispatch('open-modal', name: 'modal-create-stagiaire');
    }

    public function saveInternship(): void
    {
        $this->authorize('manage-rh');

        $this->validate([
            'firstName' => ['required', 'string', 'max:100'],
            'lastName' => ['required', 'string', 'max:100'],
            'school' => ['required', 'string', 'max:150'],
            'startDate' => ['required', 'date'],
            'endDate' => ['nullable', 'date', 'after_or_equal:startDate'],
            'monthlyFee' => ['nullable', 'numeric', 'min:0'],
        ]);

        // Ticket RH-2 — le point de passage unique, partagé avec l'envoi du poste (`SyncController::pushInternships`).
        $payload = [
            'first_name' => $this->firstName,
            'last_name' => $this->lastName,
            'school' => $this->school,
            'start_date' => $this->startDate,
            'end_date' => $this->endDate ?: null,
            'monthly_fee' => $this->monthlyFee,
            'fee_paid' => $this->feePaid,
        ];
        $saisie = app(\App\Actions\SaisieStagiaireAction::class);

        if ($this->editingInternshipId) {
            $saisie->modifier($this->editingInternshipId, $payload);
            $message = 'Modification enregistrée avec succès.';
        } else {
            $saisie->creer($payload);
            $message = 'Enregistrement effectué avec succès.';
        }

        $this->dispatch('close-modal', name: 'modal-create-stagiaire');
        $this->dispatch('toast', message: $message, type: 'success');
    }

    public function openAbsenceModal(string $id): void
    {
        $this->absenceInternshipId = $id;
        $this->absenceDate = now()->format('Y-m-d');
        $this->absenceReason = '';
        $this->dispatch('open-modal', name: 'modal-absence-stagiaire');
    }

    public function getAbsenceInternshipProperty(): ?Internship
    {
        return $this->absenceInternshipId ? Internship::find($this->absenceInternshipId) : null;
    }

    public function getAbsencesProperty()
    {
        return $this->absenceInternshipId
            ? InternshipAbsence::where('is_active', true)
                ->where('internship_id', $this->absenceInternshipId)
                ->orderByDesc('absence_date')->get()
            : collect();
    }

    public function saveAbsence(): void
    {
        $this->authorize('manage-rh');

        $this->validate([
            'absenceDate' => ['required', 'date'],
            'absenceReason' => ['nullable', 'string', 'max:255'],
        ]);

        app(\App\Actions\SaisieStagiaireAction::class)->absence([
            'internship_id' => $this->absenceInternshipId,
            'absence_date' => $this->absenceDate,
            'reason' => $this->absenceReason ?: null,
        ]);
        $this->dispatch('toast', message: 'Absence enregistrée avec succès.', type: 'success');
        $this->absenceDate = now()->format('Y-m-d');
        $this->absenceReason = '';
    }

    public function deleteAbsence(string $id): void
    {
        $this->authorize('manage-rh');

        // 🔴→✅ TICKET 14.55 — UNE ABSENCE SUPPRIMÉE EST UNE TRACE EFFACÉE.
        // Le registre sert à délivrer des attestations : effacer une absence
        // modifie rétroactivement ce que l'école atteste, sans que rien ne le
        // montre. Archivée, elle reste restaurable.
        app(\App\Actions\SaisieStagiaireAction::class)->archiverAbsence($id);
        $this->dispatch('toast', message: 'Absence archivée — restaurable depuis Paramètres > Restauration.', type: 'warning');
    }

    public function render()
    {
        return view('livewire.rh.registre-stagiaires');
    }
}
