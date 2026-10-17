<?php

namespace App\Livewire\Administration;

use App\Models\AdministrativeDocument;
use App\Services\DocumentAdministratifService;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * documents-administratifs.html → Livewire\Administration\DocumentsAdministratifs
 * "Génération de modèles administratifs (attestations,
 * correspondances)."
 *
 * ⚠️ Registre réel des documents (titre/type/bénéficiaire/date/statut),
 * PAS un générateur PDF de second niveau : les vraies attestations
 * certifiées avec aperçu live et PDF téléchargeable existent déjà via
 * `Livewire\RH\Attestations` (Sprint 8) — dupliquer un second générateur
 * ici aurait recréé exactement le piège déjà évité ailleurs dans ce
 * projet (un seul point de génération par type de document).
 */
class DocumentsAdministratifs extends Component
{
    #[Url]
    public string $search = '';

    #[Url]
    public string $statusFilter = '';

    public ?string $editingId = null;

    public string $title = '';

    public string $type = '';

    public string $beneficiary = '';

    public string $docDate = '';

    public string $status = 'en_attente';

    public function mount(): void
    {
        $this->docDate = now()->format('Y-m-d');
    }

    public function getKpisProperty(): array
    {
        $documents = AdministrativeDocument::where('is_active', true)->get();

        return [
            'generes_mois' => $documents->filter(fn ($d) => $d->doc_date->isSameMonth(now()) && $d->doc_date->isSameYear(now()))->count(),
        ];
    }

    public function getDocumentsProperty()
    {
        $statusMap = ['Signé' => 'signe', 'En attente' => 'en_attente'];

        return AdministrativeDocument::where('is_active', true)
            ->when($this->search, fn ($q) => $q->where(fn ($q2) => $q2->where('title', 'like', '%'.$this->search.'%')->orWhere('beneficiary', 'like', '%'.$this->search.'%')))
            ->when($this->statusFilter, fn ($q) => $q->where('status', $statusMap[$this->statusFilter] ?? $this->statusFilter))
            ->orderByDesc('doc_date')
            ->get();
    }

    public function newDocument(): void
    {
        $this->reset(['editingId', 'title', 'type', 'beneficiary']);
        $this->status = 'en_attente';
        $this->docDate = now()->format('Y-m-d');
        $this->dispatch('open-modal', name: 'modal-create-documents-administratifs');
    }

    public function editDocument(string $id): void
    {
        $document = AdministrativeDocument::findOrFail($id);
        $this->editingId = $document->id;
        $this->title = $document->title;
        $this->type = $document->type;
        $this->beneficiary = $document->beneficiary;
        $this->docDate = $document->doc_date->format('Y-m-d');
        $this->status = $document->status;
        $this->dispatch('open-modal', name: 'modal-create-documents-administratifs');
    }

    public function saveDocument(): void
    {
        $this->authorize('manage-administration');

        // Ticket 15.25 : règles et écriture dans `DocumentAdministratifService`, partagé avec
        // /sync/push. La clé d'erreur `docDate` reste celle de la vue.
        $service = app(DocumentAdministratifService::class);
        $regles = $service->regles();

        $this->validate([
            'title' => $regles['title'],
            'type' => $regles['type'],
            'beneficiary' => $regles['beneficiary'],
            'docDate' => $regles['doc_date'],
            'status' => $regles['status'],
        ]);

        $valides = [
            'title' => $this->title,
            'type' => $this->type,
            'beneficiary' => $this->beneficiary,
            'doc_date' => $this->docDate,
            'status' => $this->status,
        ];

        if ($this->editingId) {
            $service->modifier(AdministrativeDocument::findOrFail($this->editingId), $valides);
            $message = 'Modification enregistrée avec succès.';
        } else {
            $service->creer($valides);
            $message = 'Document enregistré avec succès.';
        }

        $this->dispatch('close-modal', name: 'modal-create-documents-administratifs');
        $this->dispatch('toast', message: $message, type: 'success');
    }

    public function archiveDocument(string $id): void
    {
        $this->authorize('manage-administration');

        app(DocumentAdministratifService::class)->archiver(AdministrativeDocument::findOrFail($id));
        $this->dispatch('toast', message: 'Document archivé avec succès.', type: 'warning');
    }

    public function render()
    {
        return view('livewire.administration.documents-administratifs');
    }
}
