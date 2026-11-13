<div>
    <div class="border-b border-outline-variant pb-md mb-lg flex flex-col sm:flex-row sm:items-center sm:justify-between gap-sm">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">inventory_2</span>{{ __('stocks.titre_gestion_stocks') }}
            </h2>
            <p class="text-xs text-outline mt-xs">{{ __('stocks.desc_gestion_stocks') }}</p>
        </div>
        <a wire:navigate href="{{ route('stocks.seuils') }}" class="flex items-center gap-xs text-xs font-bold text-brand-forest hover:text-brand-emerald">
            <span class="material-symbols-outlined text-[16px]">notification_important</span>{{ __('stocks.lien_configurer_seuils') }}
        </a>
    </div>

    <div class="grid grid-cols-2 md:grid-cols-4 gap-md mb-lg">
        <x-kpi-card :label="__('stocks.kpi_valorisation')" icon="payments" color="emerald" :value="number_format($this->kpis['valorisation'], 0, ',', ' ').' FCFA'" :caption="__('stocks.kpi_valorisation_caption')" />
        <x-kpi-card :label="__('stocks.kpi_alertes')" icon="warning" color="red" :value="$this->kpis['alertes'].' réf.'" />
        @php
            $rotation = $this->kpis['rotation'];
            // Legende construite ici, pas dans l'attribut : le perimetre du
            // ratio doit se lire en meme temps que le ratio lui-meme.
            $rotationLegende = ($rotation['couverture'] !== null
                    ? 'Couvre '.number_format($rotation['couverture'], 0, ',', ' ').' % des ventes du mois — '
                    : '')
                ."les marchandises produites à la ferme n'ont pas de coût d'achat";
        @endphp
        @if($rotation['rotation'] === null)
            <x-kpi-card :label="__('stocks.kpi_rotation')" icon="sync" color="blue" :pending="true" :pending-since="__('stocks.kpi_rotation_pending')" />
        @else
            <x-kpi-card :label="__('stocks.kpi_rotation')" icon="sync" color="blue" :value="number_format($rotation['rotation'], 1, ',', ' ').' fois/mois'" :caption="$rotationLegende" />
        @endif
        <x-kpi-card :label="__('stocks.kpi_ecarts')" icon="rule" color="maize" :value="number_format($this->kpis['ecarts'], 0, ',', ' ').' FCFA'" :caption="__('stocks.kpi_ecarts_caption')" />
    </div>

    <div class="flex items-center gap-xs border-b border-outline-variant mb-md overflow-x-auto">
        <button type="button" wire:click="$set('tab', 'tableau')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap {{ $tab === 'tableau' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}">{{ __('stocks.tab_tableau') }}</button>
        <button type="button" wire:click="$set('tab', 'mouvements')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap {{ $tab === 'mouvements' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}">{{ __('stocks.tab_mouvements') }}</button>
        <button type="button" wire:click="$set('tab', 'ajustements')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap {{ $tab === 'ajustements' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}">{{ __('stocks.tab_ajustements') }}</button>
    </div>

    @if($tab === 'tableau')
        <div>
            <div class="bg-white border border-outline-variant rounded-lg p-md mb-md flex flex-wrap items-center gap-sm">
                <div class="relative flex-1 min-w-[180px]">
                    <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
                    <input wire:model.live.debounce.300ms="search" type="text" placeholder="{{ __('stocks.placeholder_designation_sku') }}" class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
                </div>
                <select wire:model.live="categoryFilter" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
                    <option value="">{{ __('stocks.filtre_categorie_toutes') }}</option>
                    @foreach($this->categories as $cat)
                        <option value="{{ $cat->id }}">{{ $cat->label }}</option>
                    @endforeach
                </select>
                <button type="button" wire:click="exportStocksPdf" wire:loading.attr="disabled" wire:target="exportStocksPdf" class="flex items-center gap-xs text-xs font-bold px-md py-2 rounded-lg border border-outline-variant hover:bg-surface-zebra disabled:opacity-50"><span class="material-symbols-outlined text-[16px]">picture_as_pdf</span>{{ __('stocks.bouton_exporter') }}</button>
                @can('manage-stocks')
                <button @lectureSeule type="button" wire:click="openAddStockModal" class="flex items-center gap-xs text-xs font-bold px-md py-2 rounded-lg bg-brand-emerald text-white hover:bg-brand-forest"><span class="material-symbols-outlined text-[16px]">add_circle</span>{{ __('stocks.bouton_ajouter_stock') }}</button>
                @endcan
            </div>
            <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
                <div class="overflow-x-auto">
                    <table class="w-full rtable">
                        <thead class="bg-surface-zebra border-b border-outline-variant">
                            <tr>
                                <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('stocks.col_code') }}</th>
                                <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('stocks.col_designation') }}</th>
                                <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('stocks.col_categorie') }}</th>
                                <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('stocks.col_stock') }}</th>
                                <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('stocks.col_pmp') }}</th>
                                <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('stocks.col_valeur') }}</th>
                                <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('stocks.col_urgence') }}</th>
                                <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('stocks.col_actions') }}</th>
                            </tr>
                        </thead>
                        <tbody>
                            @forelse($this->stockRows->items() as $i => $row)
                                <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                                    <td data-label="{{ __('stocks.col_code') }}" class="px-md py-sm text-xs font-mono">{{ $row['product']->sku }}</td>
                                    <td data-label="{{ __('stocks.col_designation') }}" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $row['product']->name }}</td>
                                    <td data-label="{{ __('stocks.col_categorie') }}" class="px-md py-sm text-xs">{{ $row['product']->category?->label }}</td>
                                    <td data-label="{{ __('stocks.col_stock') }}" class="px-md py-sm text-xs text-right {{ $row['stock_negatif'] ? 'text-error-deep font-bold' : '' }}">
                                        {{ rtrim(rtrim(number_format($row['product']->stock_qty, 2, '.', ''), '0'), '.') }} {{ $row['product']->unit }}
                                        @if($row['stock_negatif'])
                                            <span class="block text-[10px] font-bold uppercase">{{ __('stocks.badge_entree_non_saisie') }}</span>
                                        @endif
                                    </td>
                                    <td data-label="{{ __('stocks.col_pmp') }}" class="px-md py-sm text-xs text-right">{{ $row['pmp'] !== null ? number_format($row['pmp'], 0, ',', ' ') : '—' }}</td>
                                    <td data-label="{{ __('stocks.col_valeur') }}" class="px-md py-sm text-xs text-right font-bold">{{ $row['valeur'] !== null ? number_format($row['valeur'], 0, ',', ' ') : '—' }}</td>
                                    <td data-label="{{ __('stocks.col_urgence') }}" class="px-md py-sm">
                                        @if($row['urgence'])
                                            <span class="inline-flex items-center gap-1 px-sm py-[2px] rounded-full text-[11px] font-bold border bg-error-red text-white border-error-red animate-pulse">
                                                <span class="material-symbols-outlined text-[13px]">priority_high</span>{{ __('stocks.badge_critique') }}
                                            </span>
                                        @else
                                            <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">{{ __('stocks.badge_normal') }}</span>
                                        @endif
                                    </td>
                                    <td data-label="{{ __('stocks.col_actions') }}" class="px-md py-sm text-right whitespace-nowrap">
                                        @can('manage-stocks')
                                            <a wire:navigate href="{{ route('stocks.produits.modifier', $row['product']->id) }}" class="text-outline hover:text-brand-forest p-1 inline-block" title="Modifier le produit"><span class="material-symbols-outlined text-[16px]">edit</span></a>
                                        @endcan
                                    </td>
                                </tr>
                            @empty
                                <tr><td colspan="8" class="px-md py-lg text-center text-outline">{{ __('stocks.msg_aucun_produit_catalogue') }}</td></tr>
                            @endforelse
                        </tbody>
                    </table>
                </div>
                {{-- Ticket E2 — pied de pagination standard (10 ou 25 lignes, sélecteur « Par page »). --}}
                <x-pagination :paginator="$this->stockRows" :per-page="$perPage" />
            </div>
        </div>

        <x-modal name="modal-ajouter-stock" max-width="sm">
            <div class="flex items-center justify-between mb-md">
                <h3 class="font-bold text-lg text-brand-forest">{{ __('stocks.modal_titre_ajouter_stock') }}</h3>
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-ajouter-stock' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
            </div>
            <form wire:submit="submitAjouterStock" class="space-y-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('stocks.label_date_nouveau_stock') }}</label>
                    <input wire:model="addDate" type="date" @if($this->dateMinHorsExerciceClos) min="{{ $this->dateMinHorsExerciceClos }}" @endif class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('addDate') ? 'is-invalid' : 'border-outline-variant' }}">
                    {{-- 🔴→✅ Ticket EX6 — le motif R4 posé sous « Date » par EX5 n'était affiché nulle part : refus muet. --}}
                    @error('addDate') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('stocks.label_produit') }}</label>
                    <select wire:model="addProductId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('addProductId') ? 'is-invalid' : 'border-outline-variant' }}">
                        <option value="">{{ __('stocks.select_produit') }}</option>
                        @foreach($this->products as $product)
                            <option value="{{ $product->id }}">{{ $product->name }}</option>
                        @endforeach
                    </select>
                    @error('addProductId') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('stocks.label_quantite_ajoutee') }}</label>
                    <input wire:model="addQty" type="number" min="1" placeholder="{{ __('stocks.placeholder_quantite') }}" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('addQty') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('addQty') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                    <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-ajouter-stock' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">{{ __('stocks.bouton_annuler') }}</button>
                    <button @lectureSeule type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">{{ __('stocks.bouton_enregistrer') }}</button>
                </div>
            </form>
        </x-modal>
    @endif

    @if($tab === 'mouvements')
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
            <div class="overflow-x-auto">
                <table class="w-full rtable">
                    <thead class="bg-surface-zebra border-b border-outline-variant">
                        <tr>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('stocks.col_date_heure') }}</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('stocks.col_reference') }}</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('stocks.col_produit') }}</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('stocks.col_type') }}</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('stocks.col_motif') }}</th>
                            <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('stocks.col_quantite') }}</th>
                            <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('stocks.col_valeur') }}</th>
                        </tr>
                    </thead>
                    <tbody>
                        @forelse($this->movements as $i => $movement)
                            <tr class="border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                                <td data-label="{{ __('stocks.col_date_heure') }}" class="px-md py-sm text-xs">{{ $movement->movement_date->format('d/m/Y H:i') }}</td>
                                <td data-label="{{ __('stocks.col_reference') }}" class="px-md py-sm text-xs font-mono">{{ $movement->reference_id ? strtoupper(substr($movement->reference_id, 0, 8)) : '—' }}</td>
                                <td data-label="{{ __('stocks.col_produit') }}" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $movement->product?->name }}</td>
                                <td data-label="{{ __('stocks.col_type') }}" class="px-md py-sm text-xs">
                                    @if($movement->type === 'entree')
                                        <span class="text-brand-emerald font-bold">{{ __('stocks.type_entree') }}</span>
                                    @elseif($movement->type === 'sortie')
                                        <span class="text-error-red font-bold">{{ __('stocks.type_sortie') }}</span>
                                    @else
                                        <span class="text-accent-yellow font-bold">{{ __('stocks.type_ajustement') }}</span>
                                    @endif
                                </td>
                                <td data-label="{{ __('stocks.col_motif') }}" class="px-md py-sm text-xs">{{ $this->referenceLabel($movement->reference_type) }}{{ $movement->reason ? ' — '.$movement->reason : '' }}</td>
                                <td data-label="{{ __('stocks.col_quantite') }}" class="px-md py-sm text-xs text-right {{ $movement->type === 'sortie' ? 'text-error-red' : 'text-brand-emerald' }} font-bold">{{ $movement->type === 'sortie' ? '-' : '+' }}{{ rtrim(rtrim(number_format($movement->quantity, 2, '.', ''), '0'), '.') }}</td>
                                @php $movPmp = $movement->product?->computePmp(); @endphp
                                <td data-label="{{ __('stocks.col_valeur') }}" class="px-md py-sm text-xs text-right">{{ $movPmp !== null ? number_format(abs($movement->quantity) * $movPmp, 0, ',', ' ').' FCFA' : '—' }}</td>
                            </tr>
                        @empty
                            <tr><td colspan="7" class="px-md py-lg text-center text-outline">{{ __('stocks.msg_aucun_mouvement') }}</td></tr>
                        @endforelse
                    </tbody>
                </table>
            </div>
            <x-pagination :paginator="$this->movements" />
        </div>
    @endif

    @if($tab === 'ajustements')
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-lg max-w-xl">
            <h3 class="text-sm font-bold text-brand-forest mb-md">{{ __('stocks.titre_saisir_ajustement') }}</h3>
            <div class="space-y-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('stocks.label_produit') }}</label>
                    <select wire:model.live="adjProductId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('adjProductId') ? 'is-invalid' : 'border-outline-variant' }}">
                        <option value="">{{ __('stocks.select_selectionner') }}</option>
                        @foreach($this->products as $product)
                            <option value="{{ $product->id }}">{{ $product->name }} ({{ __('stocks.label_theorique') }} : {{ rtrim(rtrim(number_format($product->stock_qty, 2, '.', ''), '0'), '.') }})</option>
                        @endforeach
                    </select>
                    @error('adjProductId') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div class="grid grid-cols-2 gap-md">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('stocks.label_stock_theorique') }}</label>
                        <div class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra flex items-center">{{ $this->adjSelectedProduct ? rtrim(rtrim(number_format($this->adjSelectedProduct->stock_qty, 2, '.', ''), '0'), '.') : '—' }}</div>
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('stocks.label_stock_physique') }}</label>
                        <input wire:model.live="adjPhysical" type="number" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('adjPhysical') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('adjPhysical') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                </div>
                <div class="bg-surface-zebra rounded-lg p-sm text-center">
                    <span class="text-[10px] text-outline uppercase font-bold">{{ __('stocks.label_ecart_calcule') }}</span>
                    <p class="text-xl font-extrabold {{ $this->adjDiff < 0 ? 'text-error-deep' : ($this->adjDiff > 0 ? 'text-brand-emerald' : 'text-brand-forest') }}">{{ $this->adjDiff > 0 ? '+' : '' }}{{ $this->adjDiff }}</p>
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('stocks.label_motif_ecart') }}</label>
                    <select wire:model="adjReason" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                        <option value="">{{ __('stocks.select_motif_ecart') }}</option>
                        <optgroup label="{{ __('stocks.optgroup_ecart_negatif') }}">
                            <option>{{ __('stocks.motif_casse') }}</option>
                            <option>{{ __('stocks.motif_vol') }}</option>
                            <option>{{ __('stocks.motif_mortalite') }}</option>
                            <option>{{ __('stocks.motif_erreur_pesee') }}</option>
                            <option>{{ __('stocks.motif_peremption') }}</option>
                        </optgroup>
                        <optgroup label="{{ __('stocks.optgroup_ecart_positif') }}">
                            <option>{{ __('stocks.motif_naissance') }}</option>
                            <option>{{ __('stocks.motif_surplus') }}</option>
                            <option>{{ __('stocks.motif_erreur_inventaire') }}</option>
                        </optgroup>
                    </select>
                </div>
                <button @lectureSeule type="button" wire:click="validateAdjustment" class="w-full py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs">{{ __('stocks.bouton_valider_ajustement') }}</button>
                {{-- Ticket U11 : l'aide annonçait l'écriture « pas encore active » ; elle l'est depuis le ticket 14.41
                     (`RecordStockAdjustmentEntryAction`). Même texte au poste (`gestion_stocks_screen.dart`). --}}
                <p class="text-[10px] text-outline">{{ __('stocks.info_ecriture_charge') }}</p>
            </div>
        </div>
    @endif
</div>
