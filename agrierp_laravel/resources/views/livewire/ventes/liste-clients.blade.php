<div class="mt-md space-y-md">
    <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm border-b border-outline-variant pb-md">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">groups</span>Liste des Clients
            </h2>
            <p class="text-xs text-outline mt-xs">Répertoire des clients de la ferme et de leur situation commerciale.</p>
        </div>
        <div class="flex items-center gap-xs">
            <button type="button" wire:click="exportClientsPdf" wire:loading.attr="disabled" wire:target="exportClientsPdf" class="flex items-center gap-xs bg-white border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>PDF
            </button>
            <button type="button" wire:click="newCustomer" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
                <span class="material-symbols-outlined text-[18px]">add_circle</span>Nouveau Client
            </button>
        </div>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-3 gap-md">
        <div class="bg-white p-md rounded-lg border border-outline-variant border-l-4 border-l-brand-emerald shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">Clients actifs</span><span class="material-symbols-outlined text-[18px] text-brand-emerald">groups</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ $this->kpis['clients_actifs'] }}</span>
        </div>
        <div class="bg-white p-md rounded-lg border border-outline-variant border-l-4 border-l-info-blue shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">Nouveaux (mois)</span><span class="material-symbols-outlined text-[18px] text-info-blue">person_add</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ $this->kpis['nouveaux_mois'] }}</span>
        </div>
        <div class="bg-white p-md rounded-lg border border-outline-variant border-l-4 border-l-error-red shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">Solde créances</span><span class="material-symbols-outlined text-[18px] text-error-red">payments</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ number_format($this->kpis['solde_creances'], 0, ',', ' ') }} <small class="text-xs font-normal">FCFA</small></span>
        </div>
    </div>

    @if(count($selectedIds) > 0)
        <div class="bg-error-bg border border-error-deep/30 rounded-lg p-sm flex items-center justify-between">
            <span class="text-xs font-bold text-error-deep">{{ count($selectedIds) }} client(s) sélectionné(s)</span>
            <button type="button" wire:click="openBulkArchiveModal" class="text-xs font-bold bg-error-red text-white px-md py-1.5 rounded-lg hover:bg-red-800">Supprimer la sélection</button>
        </div>
    @endif

    <div class="bg-white border border-outline-variant rounded-lg p-md flex flex-wrap items-center gap-sm">
        <div class="relative flex-1 min-w-[180px]">
            <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
            <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher un client..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
        </div>
        <select wire:model.live="statusFilter" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <option value="">Statut : Tous</option>
            <option value="Actif">Actif</option>
            <option value="Créance en retard">Créance en retard</option>
        </select>
        <select wire:model.live="cityFilter" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <option value="">Ville : Toutes</option>
            @foreach($this->cities as $city)
                <option value="{{ $city }}">{{ $city }}</option>
            @endforeach
        </select>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm w-8"><input type="checkbox" wire:click="toggleSelectAll" @if(count($this->customersWithBalance) > 0 && count($selectedIds) === count($this->customersWithBalance)) checked @endif></th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Nom</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Téléphone</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Ville</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Total Achats</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Solde Dû</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Statut</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->customersWithBalance as $i => $row)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td class="px-md py-sm"><input type="checkbox" wire:model.live="selectedIds" value="{{ $row['customer']->id }}"></td>
                            <td data-label="Nom" class="px-md py-sm text-xs font-bold text-brand-forest"><a href="{{ route('ventes.profile-client', $row['customer']) }}" class="hover:underline hover:text-brand-emerald">{{ $row['customer']->name }}</a></td>
                            <td data-label="Téléphone" class="px-md py-sm text-xs">{{ $row['customer']->phone ?? '—' }}</td>
                            <td data-label="Ville" class="px-md py-sm text-xs">{{ $row['customer']->city ?? '—' }}</td>
                            <td data-label="Total Achats" class="px-md py-sm text-xs text-right">{{ number_format($row['total_achats'], 0, ',', ' ') }} FCFA</td>
                            <td data-label="Solde Dû" class="px-md py-sm text-right font-bold {{ $row['solde_du'] > 0 ? 'text-error-deep' : 'text-brand-emerald' }}">{{ number_format($row['solde_du'], 0, ',', ' ') }} FCFA</td>
                            <td data-label="Statut" class="px-md py-sm">
                                @if($row['statut'] === 'Créance en retard')
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-error-bg text-error-deep border-error-deep/30">Créance en retard</span>
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">Actif</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                <button type="button" wire:click="editCustomer('{{ $row['customer']->id }}')" class="text-info-blue hover:text-blue-800 p-1" title="Modifier"><span class="material-symbols-outlined text-[18px]">edit</span></button>
                                <a href="{{ route('ventes.devis-hub', ['tab' => 'historique']) }}" class="text-brand-emerald hover:text-brand-forest p-1 inline-block" title="Historique d'achat"><span class="material-symbols-outlined text-[18px]">receipt_long</span></a>
                                <button type="button" x-on:click="$dispatch('open-modal', { name: 'archive-client-{{ $row['customer']->id }}' })" class="text-outline hover:text-error-deep p-1" title="Archiver"><span class="material-symbols-outlined text-[18px]">delete</span></button>
                            </td>
                        </tr>
                        <x-modal-confirm-delete :name="'archive-client-'.$row['customer']->id" :item-label="$row['customer']->name" :action="'archiveCustomer(\''.$row['customer']->id.'\')'" />
                    @empty
                        <tr><td colspan="8" class="px-md py-lg text-center text-outline">Aucun client pour le moment.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal-confirm-delete name="modal-bulk-archive-clients" :item-label="count($selectedIds).' client(s) sélectionné(s)'" action="bulkArchiveCustomers" />

    <x-modal name="modal-create-client" max-width="sm">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ $editingCustomerId ? 'Modifier le Client' : 'Nouveau Client' }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-client' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveCustomer" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Nom complet *</label>
                <input wire:model="name" type="text" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('name') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('name') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Téléphone</label>
                <input wire:model="phone" type="tel" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Ville</label>
                <input wire:model="city" type="text" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Email</label>
                <input wire:model="email" type="email" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('email') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('email') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-client' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
            </div>
        </form>
    </x-modal>
</div>
