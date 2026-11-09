<div class="mt-md space-y-md">
    <div class="border-b border-outline-variant pb-md flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">contact_page</span>Fiches Fournisseurs
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">Fiches détaillées des fournisseurs et historique des transactions.</p>
        </div>
        <button type="button" wire:click="exportFournisseursPdf" wire:loading.attr="disabled" wire:target="exportFournisseursPdf" class="flex items-center gap-xs bg-white border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full disabled:opacity-50">
            <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Exporter PDF
        </button>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md">
        <x-kpi-card label="Fournisseurs actifs" icon="local_shipping" color="emerald" :value="$this->kpis['fournisseurs_actifs']" />
        <x-kpi-card label="Volume d'achat (mois)" icon="payments" color="blue" :value="number_format($this->kpis['volume_achat_mois'], 0, ',', ' ').' FCFA'" />
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
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Catégorie</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Total Achats (Année)</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Dernière commande</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Statut</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->suppliers as $i => $supplier)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Nom" class="px-md py-sm text-xs"><button type="button" wire:click="view('{{ $supplier->id }}')" class="text-brand-emerald hover:underline font-bold">{{ $supplier->name }}</button></td>
                            <td data-label="Catégorie" class="px-md py-sm text-xs">{{ $supplier->category }}</td>
                            <td data-label="Total Achats" class="px-md py-sm text-xs">{{ number_format($supplier->total_achats_annee, 0, ',', ' ') }}</td>
                            <td data-label="Dernière commande" class="px-md py-sm text-xs">{{ $supplier->derniere_commande?->format('d/m/Y') ?? '—' }}</td>
                            <td data-label="Statut" class="px-md py-sm">
                                @if($supplier->is_active)
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">Actif</span>
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-surface-zebra text-outline border-outline-variant">Inactif</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                <button type="button" wire:click="view('{{ $supplier->id }}')" class="text-info-blue hover:text-blue-800 p-1" title="Voir la fiche"><span class="material-symbols-outlined text-[18px]">visibility</span></button>
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="6" class="px-md py-lg text-center text-outline">Aucun fournisseur pour le moment.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    @if($this->viewingSupplier)
        <div x-data x-on:keydown.escape.window="$wire.closeDrawer()" class="fixed inset-0 bg-black/40 z-[105]" wire:click="closeDrawer"></div>
        <div class="fixed top-0 right-0 h-full w-full sm:w-96 bg-white z-[106] shadow-2xl overflow-y-auto">
            <div class="flex items-center justify-between px-lg py-md border-b border-outline-variant bg-brand-forest">
                <span class="text-white font-bold text-sm">{{ $this->viewingSupplier->name }}</span>
                <button type="button" wire:click="closeDrawer" class="text-white/80 hover:text-white"><span class="material-symbols-outlined">close</span></button>
            </div>
            <div class="p-lg space-y-md">
                <a wire:navigate href="{{ route('achats.profile-fournisseur', $this->viewingSupplier) }}" class="flex items-center justify-center gap-xs w-full py-sm rounded-lg bg-brand-emerald text-white text-xs font-bold hover:bg-brand-forest">
                    <span class="material-symbols-outlined text-[16px]">open_in_full</span>Voir le Profil Complet
                </a>
                <div class="bg-surface-zebra rounded-lg p-md text-xs space-y-1">
                    <div class="flex justify-between"><span class="text-outline">Catégorie</span><span class="font-bold">{{ $this->viewingSupplier->category }}</span></div>
                    <div class="flex justify-between"><span class="text-outline">Téléphone</span><span class="font-bold">{{ $this->viewingSupplier->phone }}</span></div>
                    @if($this->viewingSupplier->address)
                        <div class="flex justify-between"><span class="text-outline">Adresse</span><span class="font-bold text-right">{{ $this->viewingSupplier->address }}</span></div>
                    @endif
                    <div class="flex justify-between border-t border-outline-variant pt-xs mt-xs"><span class="text-outline">Statut</span><span class="font-bold">{{ $this->viewingSupplier->is_active ? 'Actif' : 'Inactif' }}</span></div>
                </div>

                <div class="border-t border-outline-variant pt-md">
                    <p class="text-xs font-bold text-brand-forest uppercase mb-sm">Historique des Achats</p>
                    <div class="space-y-xs">
                        @forelse($this->viewingPurchases as $purchase)
                            <div class="flex justify-between text-xs border-b border-outline-variant/50 pb-1">
                                <span>{{ $purchase->purchase_date->format('d/m/Y') }} — {{ $purchase->lines->count() }} article(s)</span>
                                <span class="font-bold">{{ number_format($purchase->total, 0, ',', ' ') }} FCFA</span>
                            </div>
                        @empty
                            <p class="text-xs text-outline text-center py-md">Aucun achat enregistré pour ce fournisseur.</p>
                        @endforelse
                    </div>
                </div>
            </div>
        </div>
    @endif
</div>
