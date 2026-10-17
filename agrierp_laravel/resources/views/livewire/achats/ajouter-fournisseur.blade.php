<div class="mt-md space-y-md">
    <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm border-b border-outline-variant pb-md">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">person_add</span>Fournisseurs — Ajout
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">Enregistrement d'un nouveau partenaire fournisseur de la ferme.</p>
        </div>
        <button type="button" wire:click="newSupplier" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
            <span class="material-symbols-outlined text-[18px]">add_circle</span>Nouveau Fournisseur
        </button>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md">
        <x-kpi-card label="Fournisseurs actifs" icon="local_shipping" color="emerald" :value="$this->kpis['fournisseurs_actifs']" />
        <x-kpi-card label="Nouveaux (mois)" icon="person_add" color="blue" :value="$this->kpis['nouveaux_mois']" />
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="p-md flex flex-col md:flex-row items-stretch md:items-center justify-between gap-sm border-b border-outline-variant">
            <div class="relative flex-1 md:max-w-xs">
                <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
                <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
            </div>
            <select wire:model.live="statusFilter" class="border border-outline-variant rounded-lg text-xs px-sm py-2 bg-white w-full md:w-auto">
                <option value="">Tous les statuts</option>
                <option value="Actif">Actif</option>
                <option value="Inactif">Inactif</option>
            </select>
        </div>
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Nom</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Contact</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Catégorie</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Statut</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->suppliers as $i => $supplier)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Nom" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $supplier->name }}</td>
                            <td data-label="Contact" class="px-md py-sm text-xs">{{ $supplier->phone }}</td>
                            <td data-label="Catégorie" class="px-md py-sm text-xs">{{ $supplier->category }}</td>
                            <td data-label="Statut" class="px-md py-sm">
                                @if($supplier->is_active)
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">Actif</span>
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-surface-zebra text-outline border-outline-variant">Inactif</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                <button type="button" wire:click="editSupplier('{{ $supplier->id }}')" class="text-info-blue hover:text-blue-800 p-1" title="Modifier"><span class="material-symbols-outlined text-[18px]">edit</span></button>
                                @if($supplier->is_active)
                                    <button type="button" x-on:click="$dispatch('open-modal', { name: 'archive-fournisseur-{{ $supplier->id }}' })" class="text-error-deep hover:text-red-800 p-1" title="Archiver"><span class="material-symbols-outlined text-[18px]">archive</span></button>
                                @endif
                            </td>
                        </tr>
                        <x-modal-confirm-delete :name="'archive-fournisseur-'.$supplier->id" :item-label="$supplier->name" :action="'archiveSupplier(\''.$supplier->id.'\')'" />
                    @empty
                        <tr><td colspan="5" class="px-md py-lg text-center text-outline">Aucun fournisseur pour le moment.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal name="modal-create-fournisseur" max-width="md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ $editingSupplierId ? 'Modifier — Fournisseurs — Ajout' : 'Nouveau Fournisseur' }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-fournisseur' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveSupplier" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Nom du fournisseur *</label>
                <input wire:model="name" type="text" placeholder="ex : Provenderie du Plateau" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('name') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('name') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Téléphone *</label>
                <input wire:model="phone" type="tel" placeholder="+229 .." class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('phone') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('phone') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Catégorie *</label>
                <select wire:model="category" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('category') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    <option>Aliments</option>
                    <option>Produits vétérinaires</option>
                    <option>Intrants agricoles</option>
                    <option>Matériel</option>
                    <option>Autre</option>
                </select>
                @error('category') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Adresse</label>
                <input wire:model="address" type="text" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-fournisseur' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
            </div>
        </form>
    </x-modal>
</div>
