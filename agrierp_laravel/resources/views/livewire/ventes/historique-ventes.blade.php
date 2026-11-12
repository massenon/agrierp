<div class="mt-md space-y-md">
    <div class="flex flex-col gap-md border-b border-outline-variant pb-md">
        <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm">
            <div>
                <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                    <span class="material-symbols-outlined text-brand-emerald text-[26px]">receipt_long</span>{{ __('ventes.titre_historique_ventes') }}
                </h2>
                <p class="text-xs text-outline mt-xs">{{ __('ventes.desc_historique_ventes') }}</p>
            </div>
            <a wire:navigate href="{{ route('ventes.devis-hub') }}" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
                <span class="material-symbols-outlined text-[18px]">add_circle</span>{{ __('ventes.btn_nouvelle_vente') }}
            </a>
        </div>
        <div class="flex items-center gap-xs bg-white border border-outline-variant rounded-lg p-sm w-fit">
            <span class="material-symbols-outlined text-outline text-[18px]">calendar_month</span>
            <input wire:model.live="dateFrom" type="date" min="{{ \App\Support\ExerciceChoisi::bornes()[0] }}" max="{{ \App\Support\ExerciceChoisi::bornes()[1] }}" class="text-xs border border-outline-variant rounded-lg px-sm py-1.5">
            <span class="text-outline text-xs">au</span>
            <input wire:model.live="dateTo" type="date" min="{{ \App\Support\ExerciceChoisi::bornes()[0] }}" max="{{ \App\Support\ExerciceChoisi::bornes()[1] }}" class="text-xs border border-outline-variant rounded-lg px-sm py-1.5">
        </div>
    </div>

    <div class="grid grid-cols-2 md:grid-cols-4 gap-md">
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-brand-emerald shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">{{ __('ventes.kpi_ca') }}</span><span class="material-symbols-outlined text-[18px] text-brand-emerald">payments</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ number_format($this->kpis['ca'], 0, ',', ' ') }} <small class="text-xs font-normal">FCFA</small></span>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-info-blue shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">{{ __('ventes.kpi_transactions') }}</span><span class="material-symbols-outlined text-[18px] text-info-blue">receipt</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ $this->kpis['transactions'] }}</span>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-accent-yellow shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">{{ __('ventes.kpi_panier_moyen') }}</span><span class="material-symbols-outlined text-[18px] text-brand-forest">shopping_cart</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ number_format($this->kpis['panier_moyen'], 0, ',', ' ') }} <small class="text-xs font-normal">FCFA</small></span>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-error-red shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">{{ __('ventes.kpi_encours_creances') }}</span><span class="material-symbols-outlined text-[18px] text-error-red">request_quote</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ number_format($this->kpis['encours_creances'], 0, ',', ' ') }} <small class="text-xs font-normal">FCFA</small></span>
        </div>
    </div>

    <div class="bg-white border border-outline-variant rounded-lg p-md flex flex-wrap items-center gap-sm">
        <div class="relative flex-1 min-w-[180px]">
            <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
            <input wire:model.live.debounce.300ms="search" type="text" placeholder="Facture, client..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
        </div>
        <select wire:model.live="statusFilter" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <option value="">{{ __('ventes.filtre_statut_toutes') }}</option>
            <option value="payee">{{ __('ventes.statut_payee') }}</option>
            <option value="attente">{{ __('ventes.statut_en_attente') }}</option>
            <option value="annulee">{{ __('ventes.statut_annulee') }}</option>
        </select>
        <select wire:model.live="modeFilter" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <option value="">{{ __('ventes.filtre_mode_tous') }}</option>
            <option value="especes">{{ __('ventes.mode_especes') }}</option>
            <option value="mobile_money">{{ __('ventes.mode_mobile_money') }}</option>
            <option value="virement">{{ __('ventes.mode_virement') }}</option>
            <option value="credit">{{ __('ventes.mode_credit_client') }}</option>
            <option value="avance">{{ __('ventes.mode_avance') }}</option>
        </select>
        <select wire:model.live="customerFilter" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <option value="">{{ __('ventes.filtre_client_tous') }}</option>
            @foreach($this->customers as $customer)
                <option value="{{ $customer->id }}">{{ $customer->name }}</option>
            @endforeach
        </select>
        <button type="button" wire:click="resetFilters" class="flex items-center gap-xs text-xs font-bold text-outline hover:text-brand-forest px-sm py-2"><span class="material-symbols-outlined text-[16px]">restart_alt</span>{{ __('ventes.btn_reinitialiser') }}</button>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_facture') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_client') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_date') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_articles') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_remise') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_total_ttc') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_paye') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_reste') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_mode') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_statut') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->sales as $i => $sale)
                        @php
                            $reste = $sale->status === 'annulee' ? 0 : ($sale->receivable?->balance ?? 0);
                            $paye = $sale->status === 'annulee' ? 0 : $sale->total - $reste;
                        @endphp
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }} {{ $sale->status === 'annulee' ? 'opacity-50' : '' }}">
                            <td data-label="{{ __('ventes.col_facture') }}" class="px-md py-sm text-xs"><button type="button" wire:click="view('{{ $sale->id }}')" class="text-brand-emerald hover:underline font-bold font-mono">{{ strtoupper(substr($sale->id, 0, 8)) }}</button></td>
                            <td data-label="{{ __('ventes.col_client') }}" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $sale->customer?->name ?? __('ventes.client_anonyme') }}</td>
                            <td data-label="{{ __('ventes.col_date') }}" class="px-md py-sm text-xs">{{ $sale->date_effective->format('d/m/Y H:i') }}</td>
                            <td data-label="{{ __('ventes.col_articles') }}" class="px-md py-sm text-xs text-right">{{ $sale->lines->count() }}</td>
                            <td data-label="{{ __('ventes.col_remise') }}" class="px-md py-sm text-xs text-right">{{ number_format($sale->discount, 0, ',', ' ') }}</td>
                            <td data-label="{{ __('ventes.col_total_ttc') }}" class="px-md py-sm text-xs text-right font-bold">{{ number_format($sale->total, 0, ',', ' ') }} FCFA</td>
                            <td data-label="{{ __('ventes.col_paye') }}" class="px-md py-sm text-xs text-right text-brand-emerald">{{ number_format($paye, 0, ',', ' ') }}</td>
                            <td data-label="{{ __('ventes.col_reste') }}" class="px-md py-sm text-xs text-right {{ $reste > 0 ? 'text-error-deep font-bold' : '' }}">{{ number_format($reste, 0, ',', ' ') }}</td>
                            <td data-label="{{ __('ventes.col_mode') }}" class="px-md py-sm text-xs">{{ \App\Support\ModePaiement::libelle($sale->payment_mode) }}</td>
                            <td data-label="{{ __('ventes.col_statut') }}" class="px-md py-sm">
                                @if($sale->status === 'annulee')
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-error-bg text-error-deep border-error-deep/30">{{ __('ventes.statut_annulee') }}</span>
                                @elseif($reste > 0)
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-accent-yellow/20 text-brand-forest border-accent-yellow">{{ __('ventes.statut_en_attente') }}</span>
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">{{ __('ventes.statut_payee') }}</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                <button type="button" wire:click="view('{{ $sale->id }}')" class="text-info-blue hover:text-blue-800 p-1" title="Voir"><span class="material-symbols-outlined text-[18px]">visibility</span></button>
                                @if($sale->status !== 'annulee')
                                    @if($sale->estNormalisee())
                                        {{-- MECEF-1 — facture normalisée : ni annulation ni modification, un avoir la corrige. --}}
                                        <span class="text-outline p-1 inline-flex opacity-50 cursor-not-allowed" title="Facture normalisée : corrigez-la par un avoir."><span class="material-symbols-outlined text-[18px]">lock</span></span>
                                    @else
                                        {{-- CONF-4 : l'annulation d'une vente reste à `manage-ventes` (le comptable corrige par l'avoir). --}}
                                        @can('manage-ventes')
                                        <button @lectureSeule type="button" wire:click="confirmCancel('{{ $sale->id }}')" class="text-error-deep hover:text-red-800 p-1" title="{{ __('ventes.statut_annulee') }}"><span class="material-symbols-outlined text-[18px]">delete</span></button>
                                        @endcan
                                    @endif
                                @endif
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="11" class="px-md py-lg text-center text-outline">{{ __('ventes.msg_aucune_vente') }}</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
        <x-pagination :paginator="$this->sales" />
    </div>

    <x-modal name="modal-cancel-sale" max-width="sm">
        <div class="text-center">
            <div class="w-12 h-12 bg-error-bg rounded-full flex items-center justify-center mx-auto mb-md">
                <span class="material-symbols-outlined text-error-deep text-[28px]">warning</span>
            </div>
            <h3 class="font-bold text-lg text-brand-forest mb-xs">{{ __('ventes.titre_annuler_vente') }}</h3>
            <p class="text-xs text-outline mb-lg">{{ __('ventes.aide_annulation_reinsertion') }}</p>
            <div class="flex justify-center gap-sm">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-cancel-sale' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">{{ __('ventes.btn_annuler') }}</button>
                <button @lectureSeule type="button" wire:click="cancelSale" class="px-md py-sm rounded-lg bg-error-deep text-white text-sm font-bold hover:bg-red-800">{{ __('ventes.btn_confirmer_annulation') }}</button>
            </div>
        </div>
    </x-modal>

    @if($this->viewingSale)
        <div x-data x-on:keydown.escape.window="$wire.closeDrawer()" class="fixed inset-0 bg-black/40 z-[105]" wire:click="closeDrawer"></div>
        <div class="fixed top-0 right-0 h-full w-full sm:w-96 bg-white z-[106] shadow-2xl overflow-y-auto">
            <div class="flex items-center justify-between px-lg py-md border-b border-outline-variant bg-brand-forest">
                <span class="text-white font-bold text-sm font-mono">{{ strtoupper(substr($this->viewingSale->id, 0, 8)) }}</span>
                <button type="button" wire:click="closeDrawer" class="text-white/80 hover:text-white"><span class="material-symbols-outlined">close</span></button>
            </div>
            <div class="p-lg space-y-md">
                <div class="grid grid-cols-2 gap-sm text-xs">
                    <div><span class="text-outline block">{{ __('ventes.col_client') }}</span><span class="font-bold">{{ $this->viewingSale->customer?->name ?? __('ventes.client_anonyme') }}</span></div>
                    <div><span class="text-outline block">{{ __('ventes.col_date') }}</span><span class="font-bold">{{ $this->viewingSale->date_effective->format('d/m/Y H:i') }}</span></div>
                </div>
                <div class="border-t border-outline-variant pt-md">
                    <p class="text-xs font-bold text-brand-forest uppercase mb-sm">{{ __('ventes.col_articles') }}</p>
                    <div class="space-y-xs">
                        @foreach($this->viewingSale->lines as $line)
                            <div class="flex justify-between text-xs border-b border-outline-variant/50 pb-1">
                                <span>{{ $line->product?->name }} × {{ rtrim(rtrim(number_format($line->qty, 2, '.', ''), '0'), '.') }}</span>
                                <span class="font-bold">{{ number_format($line->manual_total_amount, 0, ',', ' ') }} FCFA</span>
                            </div>
                        @endforeach
                    </div>
                </div>
                <div class="border-t border-outline-variant pt-md space-y-1 text-xs">
                    <div class="flex justify-between"><span class="text-outline">{{ __('ventes.label_sous_total') }}</span><span>{{ number_format($this->viewingSale->subtotal, 0, ',', ' ') }} FCFA</span></div>
                    <div class="flex justify-between"><span class="text-outline">{{ __('ventes.col_remise') }}</span><span>{{ number_format($this->viewingSale->discount, 0, ',', ' ') }} FCFA</span></div>
                    <div class="flex justify-between font-bold text-brand-emerald text-sm"><span>{{ __('ventes.label_total') }}</span><span>{{ number_format($this->viewingSale->total, 0, ',', ' ') }} FCFA</span></div>
                </div>
            </div>
            <div class="p-lg border-t border-outline-variant flex justify-center gap-sm">
                <button type="button" wire:click="exportSaleTicketPdf('{{ $this->viewingSale->id }}')" wire:loading.attr="disabled" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest flex items-center gap-xs disabled:opacity-50"><span class="material-symbols-outlined text-[16px]">download</span>{{ __('ventes.btn_telecharger_pdf') }}</button>
                <button type="button" wire:click="closeDrawer" class="px-md py-sm rounded-lg border border-outline-variant text-outline text-sm font-bold hover:bg-surface-zebra">{{ __('ventes.btn_fermer') }}</button>
            </div>
        </div>
    @endif
</div>
