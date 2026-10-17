<div class="mt-md space-y-md">
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">archive</span>Archivage des Documents
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">Coffre-fort numérique des documents officiels de la ferme.</p>
        </div>
        <button type="button" wire:click="newDocument" class="flex items-center justify-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full transition-all shadow-sm">
            <span class="material-symbols-outlined text-[18px]">add_circle</span>Archiver un Document
        </button>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md">
        <x-kpi-card label="Documents archivés" icon="folder" color="emerald" :value="$this->kpis['documents_archives']" />
        <x-kpi-card label="Expirant sous 30j" icon="event_busy" color="maize" :value="$this->kpis['expirant_30j']" />
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="p-md flex flex-col md:flex-row items-stretch md:items-center justify-between gap-sm border-b border-outline-variant">
            <div class="relative flex-1 md:max-w-xs">
                <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
                <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
            </div>
            <select wire:model.live="statusFilter" class="border border-outline-variant rounded-lg text-xs px-sm py-2 bg-white w-full md:w-auto">
                <option value="">Tous les statuts</option>
                <option value="Valide">Valide</option>
                <option value="Bientôt expiré">Bientôt expiré</option>
                <option value="Expiré">Expiré</option>
            </select>
        </div>
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Document</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Catégorie</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date Archivage</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Expiration</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Statut</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->documents as $i => $document)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Document" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $document->title }}</td>
                            <td data-label="Catégorie" class="px-md py-sm text-xs">{{ $document->category }}</td>
                            <td data-label="Archivage" class="px-md py-sm text-xs">{{ $document->archived_date->format('d/m/Y') }}</td>
                            <td data-label="Expiration" class="px-md py-sm text-xs">{{ $document->expiry_date?->format('d/m/Y') ?? '—' }}</td>
                            <td data-label="Statut" class="px-md py-sm">
                                @if($document->status === 'valide')
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">Valide</span>
                                @elseif($document->status === 'bientot_expire')
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-accent-yellow/20 text-brand-forest border-accent-yellow">Bientôt expiré</span>
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-error-bg text-error-deep border-error-deep/30">Expiré</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                <button type="button" wire:click="editDocument('{{ $document->id }}')" class="text-info-blue hover:text-blue-800 p-1" title="Modifier"><span class="material-symbols-outlined text-[18px]">edit</span></button>
                                <button type="button" x-on:click="$dispatch('open-modal', { name: 'archive-doc-{{ $document->id }}' })" class="text-error-deep hover:text-red-800 p-1" title="Retirer"><span class="material-symbols-outlined text-[18px]">archive</span></button>
                            </td>
                        </tr>
                        <x-modal-confirm-delete :name="'archive-doc-'.$document->id" :item-label="$document->title" :action="'deleteDocument(\''.$document->id.'\')'" />
                    @empty
                        <tr><td colspan="6" class="px-md py-lg text-center text-outline">Aucun document archivé pour le moment.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal name="modal-create-archivage-documents" max-width="md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ $editingId ? 'Modifier le Document' : 'Archiver un Document' }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-archivage-documents' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveDocument" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Titre du document *</label>
                <input wire:model="title" type="text" placeholder="ex : Registre du Commerce (RCCM)" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('title') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('title') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Catégorie *</label>
                <select wire:model="category" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('category') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    <option>Juridique</option>
                    <option>Fiscal</option>
                    <option>Sanitaire</option>
                    <option>Foncier</option>
                    <option>Autre</option>
                </select>
                @error('category') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div class="grid grid-cols-2 gap-sm">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date d'archivage *</label>
                    <input wire:model="archivedDate" type="date" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date d'expiration</label>
                    <input wire:model="expiryDate" type="date" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('expiryDate') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('expiryDate') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
            </div>
            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-archivage-documents' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
            </div>
        </form>
    </x-modal>
</div>
