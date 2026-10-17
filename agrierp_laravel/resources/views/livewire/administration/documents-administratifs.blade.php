<div class="mt-md space-y-md">
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">description</span>Documents Administratifs
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">Registre des modèles administratifs (attestations, correspondances).</p>
        </div>
        <button type="button" wire:click="newDocument" class="flex items-center justify-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full transition-all shadow-sm">
            <span class="material-symbols-outlined text-[18px]">add_circle</span>Enregistrer un Document
        </button>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md">
        <x-kpi-card label="Générés (mois)" icon="draft" color="emerald" :value="$this->kpis['generes_mois']" />
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="p-md flex flex-col md:flex-row items-stretch md:items-center justify-between gap-sm border-b border-outline-variant">
            <div class="relative flex-1 md:max-w-xs">
                <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
                <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
            </div>
            <select wire:model.live="statusFilter" class="border border-outline-variant rounded-lg text-xs px-sm py-2 bg-white w-full md:w-auto">
                <option value="">Tous les statuts</option>
                <option value="Signé">Signé</option>
                <option value="En attente">En attente</option>
            </select>
        </div>
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Document</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Type</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Bénéficiaire</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Statut</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->documents as $i => $document)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Document" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $document->title }}</td>
                            <td data-label="Type" class="px-md py-sm text-xs">{{ $document->type }}</td>
                            <td data-label="Bénéficiaire" class="px-md py-sm text-xs">{{ $document->beneficiary }}</td>
                            <td data-label="Date" class="px-md py-sm text-xs">{{ $document->doc_date->format('d/m/Y') }}</td>
                            <td data-label="Statut" class="px-md py-sm">
                                @if($document->status === 'signe')
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">Signé</span>
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-accent-yellow/20 text-brand-forest border-accent-yellow">En attente</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                <button type="button" wire:click="editDocument('{{ $document->id }}')" class="text-info-blue hover:text-blue-800 p-1" title="Modifier"><span class="material-symbols-outlined text-[18px]">edit</span></button>
                                <button type="button" x-on:click="$dispatch('open-modal', { name: 'archive-docadmin-{{ $document->id }}' })" class="text-error-deep hover:text-red-800 p-1" title="Archiver"><span class="material-symbols-outlined text-[18px]">archive</span></button>
                            </td>
                        </tr>
                        <x-modal-confirm-delete :name="'archive-docadmin-'.$document->id" :item-label="$document->title" :action="'archiveDocument(\''.$document->id.'\')'" />
                    @empty
                        <tr><td colspan="6" class="px-md py-lg text-center text-outline">Aucun document pour le moment.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal name="modal-create-documents-administratifs" max-width="md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ $editingId ? 'Modifier le Document' : 'Enregistrer un Document' }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-documents-administratifs' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveDocument" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Titre du document *</label>
                <input wire:model="title" type="text" placeholder="ex : Note de service" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('title') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('title') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Type *</label>
                <select wire:model="type" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('type') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    <option>Attestation</option>
                    <option>Certificat</option>
                    <option>Note interne</option>
                    <option>Correspondance</option>
                </select>
                @error('type') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Bénéficiaire *</label>
                <input wire:model="beneficiary" type="text" placeholder="ex : Tout le personnel" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('beneficiary') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('beneficiary') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div class="grid grid-cols-2 gap-sm">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date *</label>
                    <input wire:model="docDate" type="date" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Statut</label>
                    <select wire:model="status" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                        <option value="en_attente">En attente</option>
                        <option value="signe">Signé</option>
                    </select>
                </div>
            </div>
            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-documents-administratifs' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
            </div>
        </form>
    </x-modal>
</div>
