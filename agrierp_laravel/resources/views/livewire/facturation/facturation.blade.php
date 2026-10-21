<div>
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">receipt_long</span>Facturation &amp; MeCeF
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">Émission de factures normalisées et transmission au système MeCeF (DGI Bénin).</p>
        </div>
        <a href="{{ route('ventes.devis-hub') }}" class="flex items-center justify-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full transition-all shadow-sm">
            <span class="material-symbols-outlined text-[18px]">add_circle</span>Nouvelle Facture
        </a>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md mb-lg">
        <x-kpi-card label="Factures (mois)" icon="receipt_long" color="emerald" :value="$this->kpis['factures_mois']" />
        <x-kpi-card label="Transmises MeCeF" icon="cloud_done" color="blue" :value="$this->kpis['transmises']" />
        <x-kpi-card label="En attente" icon="cloud_sync" color="maize" :value="$this->kpis['en_attente']" />
        <x-kpi-card label="Erreurs MeCeF" icon="cloud_off" color="red" :value="$this->kpis['erreurs']" />
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="p-md flex flex-col md:flex-row items-stretch md:items-center justify-between gap-sm border-b border-outline-variant">
            <div class="relative flex-1 md:max-w-xs">
                <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
                <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
            </div>
            <select wire:model.live="statusFilter" class="border border-outline-variant rounded-lg text-xs px-sm py-2 bg-white w-full md:w-auto">
                <option value="">Tous les statuts</option>
                <option value="Transmise">Transmise</option>
                <option value="En attente">En attente</option>
                <option value="Erreur MeCeF">Erreur MeCeF</option>
            </select>
        </div>
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">N° Facture</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Client</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Montant TTC</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Statut MeCeF</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->sales as $i => $sale)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="N° Facture" class="px-md py-sm text-xs font-mono font-bold text-brand-emerald">{{ $sale->numero_facture }}</td>
                            <td data-label="Client" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $sale->customer?->name ?? 'Client Anonyme' }}</td>
                            <td data-label="Date" class="px-md py-sm text-xs">{{ $sale->date_effective->format('d/m/Y') }}</td>
                            <td data-label="Montant TTC" class="px-md py-sm text-xs">{{ number_format($sale->total, 0, ',', ' ') }}</td>
                            <td data-label="Statut MeCeF" class="px-md py-sm">
                                @if($sale->mecef_status === 'transmise')
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">Transmise</span>
                                @elseif($sale->mecef_status === 'erreur')
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-error-bg text-error-deep border-error-deep/30">Erreur MeCeF</span>
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-accent-yellow/20 text-brand-forest border-accent-yellow">En attente</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                @if($sale->mecef_qr_ref)
                                    <button type="button" wire:click="showMecef('{{ $sale->id }}')" class="text-brand-emerald hover:text-brand-forest p-1" title="Facture normalisée MeCeF"><span class="material-symbols-outlined text-[18px]">qr_code_2</span></button>
                                @endif
                                @if($sale->mecef_status === 'erreur')
                                    <button type="button" wire:click="retryMecef('{{ $sale->id }}')" class="text-error-deep hover:text-red-800 p-1" title="Retransmettre au MeCeF"><span class="material-symbols-outlined text-[18px]">refresh</span></button>
                                @endif
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="6" class="px-md py-lg text-center text-outline">Aucune facture pour le moment.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
        <x-pagination :paginator="$this->sales" />
    </div>

    <x-modal name="modal-mecef" max-width="sm">
        <div class="text-center">
            <h3 class="font-bold text-lg text-brand-forest mb-md">Facture Normalisée MeCeF</h3>
            @if($this->qrSvg)
                <div class="bg-white border border-outline-variant rounded-lg p-md inline-block">
                    {!! $this->qrSvg !!}
                </div>
                <p class="text-[11px] font-mono text-outline mt-md break-all">{{ $this->viewingSale->mecef_qr_ref }}</p>
            @else
                <p class="text-xs text-outline py-lg">Aucune référence MeCeF disponible pour cette facture.</p>
            @endif
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-mecef' })" class="mt-md px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Fermer</button>
        </div>
    </x-modal>
</div>
