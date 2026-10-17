<?php

namespace App\Livewire\Administration;

use App\Models\ArchivedDocument;
use App\Services\ArchiveDocumentService;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * archivage-documents.html → Livewire\Administration\ArchivageDocuments
 * "Coffre-fort numérique des documents officiels de la ferme."
 *
 * Statut (Valide/Bientôt expiré/Expiré) dérivé de `expiry_date`
 * (`ArchivedDocument::getStatusAttribute()`) — jamais un champ stocké
 * séparément qui pourrait diverger de la vraie date d'expiration.
 */
class ArchivageDocuments extends Component
{
    #[Url]
    public string $search = '';

    #[Url]
    public string $statusFilter = '';

    public ?string $editingId = null;

    public string $title = '';

    public string $category = '';

    public string $archivedDate = '';

    public string $expiryDate = '';

    public function mount(): void
    {
        $this->archivedDate = now()->format('Y-m-d');
    }

    public function getKpisProperty(): array
    {
        $documents = ArchivedDocument::where('is_active', true)->get();

        return [
            'documents_archives' => $documents->count(),
            'expirant_30j' => $documents->filter(fn ($d) => $d->status === 'bientot_expire')->count(),
        ];
    }

    public function getDocumentsProperty()
    {
        $statusMap = ['Valide' => 'valide', 'Bientôt expiré' => 'bientot_expire', 'Expiré' => 'expire'];

        return ArchivedDocument::where('is_active', true)
            ->when($this->search, fn ($q) => $q->where('title', 'like', '%'.$this->search.'%'))
            ->orderByDesc('archived_date')
            ->get()
            ->when($this->statusFilter, fn ($rows) => $rows->filter(fn ($d) => $d->status === ($statusMap[$this->statusFilter] ?? $this->statusFilter)));
    }

    public function newDocument(): void
    {
        $this->reset(['editingId', 'title', 'category', 'expiryDate']);
        $this->archivedDate = now()->format('Y-m-d');
        $this->dispatch('open-modal', name: 'modal-create-archivage-documents');
    }

    public function editDocument(string $id): void
    {
        $document = ArchivedDocument::findOrFail($id);
        $this->editingId = $document->id;
        $this->title = $document->title;
        $this->category = $document->category;
        $this->archivedDate = $document->archived_date->format('Y-m-d');
        $this->expiryDate = $document->expiry_date?->format('Y-m-d') ?? '';
        $this->dispatch('open-modal', name: 'modal-create-archivage-documents');
    }

    public function saveDocument(): void
    {
        $this->authorize('manage-administration');

        // Ticket 15.24 : règles et écriture dans `ArchiveDocumentService`, partagé avec
        // /sync/push. Les clés d'erreur restent celles de la vue (`archivedDate`, `expiryDate`).
        $service = app(ArchiveDocumentService::class);
        $regles = $service->regles('archivedDate');

        $this->validate([
            'title' => $regles['title'],
            'category' => $regles['category'],
            'archivedDate' => $regles['archived_date'],
            'expiryDate' => $regles['expiry_date'],
        ]);

        $valides = [
            'title' => $this->title,
            'category' => $this->category,
            'archived_date' => $this->archivedDate,
            'expiry_date' => $this->expiryDate ?: null,
        ];

        if ($this->editingId) {
            $service->modifier(ArchivedDocument::findOrFail($this->editingId), $valides);
            $message = 'Modification enregistrée avec succès.';
        } else {
            $service->creer($valides);
            $message = 'Document archivé avec succès.';
        }

        $this->dispatch('close-modal', name: 'modal-create-archivage-documents');
        $this->dispatch('toast', message: $message, type: 'success');
    }

    public function deleteDocument(string $id): void
    {
        $this->authorize('manage-administration');

        app(ArchiveDocumentService::class)->archiver(ArchivedDocument::findOrFail($id));
        $this->dispatch('toast', message: 'Document retiré des archives.', type: 'warning');
    }

    public function render()
    {
        return view('livewire.administration.archivage-documents');
    }
}
