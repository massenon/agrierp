<?php

namespace App\Livewire\Administration;

use App\Models\Correspondence;
use App\Services\CourrierService;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * gestion-courriers.html → Livewire\Administration\GestionCourriers
 * "Enregistrement et suivi du courrier entrant et sortant de la ferme."
 * CRUD complet réel, numérotation `CR-{annee}-{sequence}` (même
 * convention que `Quote::generateQuoteNumber()`, ticket 4.3).
 *
 * 🔴→✅ EXTENSION DU PATTERN RBAC CRUD AU NIVEAU ACTION (référence
 * initiale : `PlanComptable`) — `$this->authorize('manage-administration')`
 * sur les 4 actions mutantes.
 */
class GestionCourriers extends Component
{
    #[Url]
    public string $search = '';

    public ?string $editingId = null;

    public string $type = '';

    public string $subject = '';

    public string $party = '';

    public string $mailDate = '';

    public function mount(): void
    {
        $this->mailDate = now()->format('Y-m-d');
    }

    public function getKpisProperty(): array
    {
        $monthMails = Correspondence::where('is_active', true)->whereMonth('mail_date', now()->month)->whereYear('mail_date', now()->year);

        return [
            'recus' => (clone $monthMails)->where('type', 'entrant')->count(),
            'envoyes' => (clone $monthMails)->where('type', 'sortant')->count(),
        ];
    }

    public function getMailsProperty()
    {
        return Correspondence::where('is_active', true)
            ->when($this->search, fn ($q) => $q->where(fn ($q2) => $q2->where('subject', 'like', '%'.$this->search.'%')->orWhere('party', 'like', '%'.$this->search.'%')->orWhere('reference', 'like', '%'.$this->search.'%')))
            ->orderByDesc('mail_date')
            ->get();
    }

    public function newMail(): void
    {
        $this->authorize('manage-administration');

        $this->reset(['editingId', 'type', 'subject', 'party']);
        $this->mailDate = now()->format('Y-m-d');
        $this->dispatch('open-modal', name: 'modal-create-gestion-courriers');
    }

    public function editMail(string $id): void
    {
        $this->authorize('manage-administration');

        $mail = Correspondence::findOrFail($id);
        $this->editingId = $mail->id;
        $this->type = $mail->type;
        $this->subject = $mail->subject;
        $this->party = $mail->party;
        $this->mailDate = $mail->mail_date->format('Y-m-d');
        $this->dispatch('open-modal', name: 'modal-create-gestion-courriers');
    }

    public function saveMail(): void
    {
        $this->authorize('manage-administration');

        // Ticket 15.23 : règles et écriture dans `CourrierService`, partagé avec /sync/push.
        // Les clés d'erreur restent celles de la vue (`mailDate`).
        $service = app(CourrierService::class);
        $regles = $service->regles();

        $this->validate([
            'type' => $regles['type'],
            'subject' => $regles['subject'],
            'party' => $regles['party'],
            'mailDate' => $regles['mail_date'],
        ]);

        $valides = ['type' => $this->type, 'subject' => $this->subject, 'party' => $this->party, 'mail_date' => $this->mailDate];

        if ($this->editingId) {
            $service->modifier(Correspondence::findOrFail($this->editingId), $valides);
            $message = 'Modification enregistrée avec succès.';
        } else {
            $service->creer($valides);
            $message = 'Enregistrement effectué avec succès.';
        }

        $this->dispatch('close-modal', name: 'modal-create-gestion-courriers');
        $this->dispatch('toast', message: $message, type: 'success');
    }

    public function archiveMail(string $id): void
    {
        $this->authorize('manage-administration');

        app(CourrierService::class)->archiver(Correspondence::findOrFail($id));
        $this->dispatch('toast', message: 'Courrier archivé avec succès.', type: 'warning');
    }

    public function render()
    {
        return view('livewire.administration.gestion-courriers');
    }
}
