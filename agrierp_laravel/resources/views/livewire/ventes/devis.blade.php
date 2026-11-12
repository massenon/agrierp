<div class="mt-md space-y-md">
    <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">request_quote</span>{{ __('ventes.titre_devis_proforma') }}
            </h2>
            <p class="text-xs text-outline mt-xs">{{ __('ventes.desc_devis') }}</p>
        </div>
        <div class="flex flex-wrap items-center gap-xs">
            <button type="button" wire:click="exportDevisPdf" wire:loading.attr="disabled" wire:target="exportDevisPdf" class="flex items-center gap-xs bg-white border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full disabled:opacity-50"><span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>{{ __('ventes.btn_exporter') }}</button>
            <button type="button" wire:click="newQuote" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
                <span class="material-symbols-outlined text-[18px]">add_circle</span>{{ __('ventes.btn_nouveau_devis') }}
            </button>
        </div>
    </div>

    <x-kpi-accordion title="Indicateurs de performance">
        <x-kpi-card label="{{ __('ventes.kpi_devis_actifs') }}" icon="request_quote" color="emerald" :value="$this->kpis['devis_actifs']" />
        <x-kpi-card label="{{ __('ventes.kpi_valeur_totale') }}" icon="payments" color="blue" :value="number_format($this->kpis['valeur_totale'], 0, ',', ' ').' FCFA'" />
        <x-kpi-card label="{{ __('ventes.kpi_taux_conversion') }}" icon="trending_up" color="maize" :value="$this->kpis['taux_conversion'].' %'" />
        <x-kpi-card label="{{ __('ventes.kpi_en_attente_relance') }}" icon="pending_actions" color="red" :value="$this->kpis['en_attente_relance']" />
    </x-kpi-accordion>

    <div class="bg-white border border-outline-variant rounded-lg p-md flex flex-wrap items-center gap-sm">
        <div class="relative flex-1 min-w-[180px]">
            <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
            <input wire:model.live.debounce.300ms="search" type="text" placeholder="N° devis, client..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
        </div>
        <select wire:model.live="statusFilter" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <option value="">{{ __('ventes.filtre_statut_tous') }}</option>
            <option value="brouillon">{{ __('ventes.statut_brouillon') }}</option>
            <option value="envoye">{{ __('ventes.statut_envoye') }}</option>
            <option value="accepte">{{ __('ventes.statut_accepte') }}</option>
            <option value="refuse">{{ __('ventes.statut_refuse') }}</option>
            <option value="facture">{{ __('ventes.statut_facture') }}</option>
        </select>
        <select wire:model.live="clientFilter" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <option value="">{{ __('ventes.filtre_client_tous') }}</option>
            @foreach($this->customers as $customer)
                <option value="{{ $customer->id }}">{{ $customer->name }}</option>
            @endforeach
        </select>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_num_devis') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_client') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_date') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_validite') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_montant') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('ventes.col_statut') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->quotes as $i => $quote)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="{{ __('ventes.col_num_devis') }}" class="px-md py-sm text-xs font-bold text-brand-emerald">{{ $quote->quote_number }}</td>
                            <td data-label="{{ __('ventes.col_client') }}" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $quote->customer?->name }}</td>
                            <td data-label="{{ __('ventes.col_date') }}" class="px-md py-sm text-xs">{{ $quote->quote_date->format('d/m/Y') }}</td>
                            <td data-label="{{ __('ventes.col_validite') }}" class="px-md py-sm text-xs">{{ $quote->valid_until->format('d/m/Y') }}</td>
                            <td data-label="{{ __('ventes.col_montant') }}" class="px-md py-sm text-xs text-right font-bold">{{ number_format($quote->amount, 0, ',', ' ') }} FCFA</td>
                            <td data-label="{{ __('ventes.col_statut') }}" class="px-md py-sm">
                                @php
                                    $statusStyles = [
                                        'brouillon' => 'bg-surface-zebra text-outline border-outline-variant',
                                        'envoye' => 'bg-info-blue/10 text-info-blue border-info-blue/30',
                                        'accepte' => 'bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30',
                                        'refuse' => 'bg-error-bg text-error-deep border-error-deep/30',
                                        'facture' => 'bg-surface-zebra text-outline border-outline-variant',
                                    ];
                                    $statusLabels = [
                                        'brouillon' => __('ventes.statut_brouillon'),
                                        'envoye'    => __('ventes.statut_envoye'),
                                        'accepte'   => __('ventes.statut_accepte'),
                                        'refuse'    => __('ventes.statut_refuse'),
                                        'facture'   => __('ventes.statut_facture'),
                                    ];
                                @endphp
                                <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border {{ $statusStyles[$quote->status] }}">{{ $statusLabels[$quote->status] }}</span>
                                @if($quote->status === 'facture' && $quote->sale)
                                    <span class="block text-[10px] font-mono text-outline mt-[2px]">{{ $quote->numero_facture }}</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                @if($quote->status === 'brouillon')
                                    <button type="button" wire:click="markAsSent('{{ $quote->id }}')" class="text-info-blue hover:text-blue-800 p-1" title="{{ __('ventes.statut_envoye') }}"><span class="material-symbols-outlined text-[18px]">send</span></button>
                                @endif
                                @if($quote->status === 'envoye')
                                    <button type="button" wire:click="markAsAccepted('{{ $quote->id }}')" class="text-brand-emerald hover:text-brand-forest p-1" title="{{ __('ventes.statut_accepte') }}"><span class="material-symbols-outlined text-[18px]">check_circle</span></button>
                                    <button type="button" wire:click="markAsRefused('{{ $quote->id }}')" class="text-error-deep hover:text-red-800 p-1" title="{{ __('ventes.statut_refuse') }}"><span class="material-symbols-outlined text-[18px]">cancel</span></button>
                                @endif
                                @if($quote->status === 'accepte' && auth()->user()?->can('manage-ventes') && auth()->user()?->can('manage-facturation'))
                                    <button type="button" wire:click="convertToInvoice('{{ $quote->id }}')" class="text-brand-emerald hover:text-brand-forest p-1" title="{{ __('ventes.statut_facture') }}"><span class="material-symbols-outlined text-[18px]">receipt_long</span></button>
                                @endif
                                @if($quote->status === 'facture' && $quote->sale && auth()->user()?->can('view-facturation'))
                                    <a wire:navigate href="{{ route('facturation.index', ['search' => $quote->sale->id]) }}" class="text-brand-emerald hover:text-brand-forest p-1 inline-block" title="{{ __('ventes.statut_facture') }}"><span class="material-symbols-outlined text-[18px]">visibility</span></a>
                                @endif
                                @can('export-ventes')
                                    <button type="button" wire:click="imprimerDevis('{{ $quote->id }}')" wire:loading.attr="disabled" wire:target="imprimerDevis" class="text-brand-forest hover:text-brand-emerald p-1" title="Imprimer le devis"><span class="material-symbols-outlined text-[18px]">print</span></button>
                                @endcan
                                <button type="button" wire:click="editQuote('{{ $quote->id }}')" class="text-brand-emerald hover:text-brand-forest p-1" title="{{ __('ventes.titre_modifier_devis') }}"><span class="material-symbols-outlined text-[18px]">edit</span></button>
                                <button type="button" x-on:click="$dispatch('open-modal', { name: 'archive-devis-{{ $quote->id }}' })" class="text-outline hover:text-error-deep p-1" title="Archiver"><span class="material-symbols-outlined text-[18px]">delete</span></button>
                            </td>
                        </tr>
                        <x-modal-confirm-delete :name="'archive-devis-'.$quote->id" :item-label="$quote->quote_number" :action="'archiveQuote(\''.$quote->id.'\')'" />
                    @empty
                        <tr><td colspan="7" class="px-md py-lg text-center text-outline">{{ __('ventes.msg_aucun_devis') }}</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal name="modal-create-devis" max-width="md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ $editingQuoteId ? __('ventes.titre_modifier_devis') : __('ventes.titre_nouveau_devis') }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-devis' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveQuote" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_client_requis') }}</label>
                <select wire:model="customerId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('customerId') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">{{ __('ventes.select_selectionner') }}</option>
                    @foreach($this->customers as $customer)
                        <option value="{{ $customer->id }}">{{ $customer->name }}</option>
                    @endforeach
                </select>
                @error('customerId') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_articles_prestations') }}</label>
                <textarea wire:model="articlesDescription" rows="3" placeholder="ex : 2 cages galvanisées 6 compartiments sur mesure" class="w-full px-md py-sm border rounded-lg text-sm {{ $errors->has('articlesDescription') ? 'is-invalid' : 'border-outline-variant' }}"></textarea>
                @error('articlesDescription') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div class="grid grid-cols-3 gap-sm">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_montant_ht') }}</label>
                    <input wire:model="amount" type="number" min="0" class="w-full h-11 px-md border rounded-lg text-sm font-bold {{ $errors->has('amount') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('amount') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_tva') }}</label>
                    <select wire:model="tvaRate" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('tvaRate') ? 'is-invalid' : 'border-outline-variant' }}">
                        <option value="0">0 %</option>
                        <option value="18">18 %</option>
                    </select>
                    @error('tvaRate') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_validite_jours') }}</label>
                    <input wire:model="validityDays" type="number" min="1" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('validityDays') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('validityDays') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_date_devis') }}</label>
                <input wire:model="quoteDate" type="date" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('quoteDate') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('quoteDate') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_note_optionnel') }}</label>
                <textarea wire:model="note" rows="2" class="w-full px-md py-sm border border-outline-variant rounded-lg text-sm"></textarea>
            </div>
            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-devis' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">{{ __('ventes.btn_annuler') }}</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">{{ __('ventes.btn_enregistrer') }}</button>
            </div>
        </form>
    </x-modal>
</div>
