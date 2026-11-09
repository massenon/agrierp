<div>
    <div class="border-b border-outline-variant pb-md mb-lg flex flex-col sm:flex-row sm:items-center sm:justify-between gap-sm">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">inventory_2</span>Gestion des Stocks
            </h2>
            <p class="text-xs text-outline mt-xs">Espace unifié : inventaire, mouvements et ajustements.</p>
        </div>
        <a wire:navigate href="{{ route('stocks.seuils') }}" class="flex items-center gap-xs text-xs font-bold text-brand-forest hover:text-brand-emerald">
            <span class="material-symbols-outlined text-[16px]">notification_important</span>Configurer les Seuils d'Alerte
        </a>
    </div>

    <div class="grid grid-cols-2 md:grid-cols-4 gap-md mb-lg">
        <x-kpi-card label="Valorisation Stocks" icon="payments" color="emerald" :value="number_format($this->kpis['valorisation'], 0, ',', ' ').' FCFA'" caption="Basée sur le PMP réel (achats)" />
        <x-kpi-card label="Alertes de Seuil" icon="warning" color="red" :value="$this->kpis['alertes'].' réf.'" />
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
            <x-kpi-card label="Rotation du Stock" icon="sync" color="blue" :pending="true" pending-since="un stock valorisable non nul sur le mois" />
        @else
            <x-kpi-card label="Rotation du Stock" icon="sync" color="blue" :value="number_format($rotation['rotation'], 1, ',', ' ').' fois/mois'" :caption="$rotationLegende" />
        @endif
        <x-kpi-card label="Écarts d'Inventaire" icon="rule" color="maize" :value="number_format($this->kpis['ecarts'], 0, ',', ' ').' FCFA'" caption="Ajustements du mois" />
    </div>

    <div class="flex items-center gap-xs border-b border-outline-variant mb-md overflow-x-auto">
        <button type="button" wire:click="$set('tab', 'tableau')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap {{ $tab === 'tableau' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}">Tableau &amp; Valorisation</button>
        <button type="button" wire:click="$set('tab', 'mouvements')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap {{ $tab === 'mouvements' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}">Journal des Mouvements</button>
        <button type="button" wire:click="$set('tab', 'ajustements')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap {{ $tab === 'ajustements' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}">Ajustement / Correction</button>
    </div>

    @if($tab === 'tableau')
        <div>
            <div class="bg-white border border-outline-variant rounded-lg p-md mb-md flex flex-wrap items-center gap-sm">
                <div class="relative flex-1 min-w-[180px]">
                    <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
                    <input wire:model.live.debounce.300ms="search" type="text" placeholder="Désignation ou SKU..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
                </div>
                <select wire:model.live="categoryFilter" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
                    <option value="">Catégorie : Toutes</option>
                    @foreach($this->categories as $cat)
                        <option value="{{ $cat->id }}">{{ $cat->label }}</option>
                    @endforeach
                </select>
                <button type="button" wire:click="exportStocksPdf" wire:loading.attr="disabled" wire:target="exportStocksPdf" class="flex items-center gap-xs text-xs font-bold px-md py-2 rounded-lg border border-outline-variant hover:bg-surface-zebra disabled:opacity-50"><span class="material-symbols-outlined text-[16px]">picture_as_pdf</span>Exporter</button>
                @can('manage-stocks')
                <button @lectureSeule type="button" wire:click="openAddStockModal" class="flex items-center gap-xs text-xs font-bold px-md py-2 rounded-lg bg-brand-emerald text-white hover:bg-brand-forest"><span class="material-symbols-outlined text-[16px]">add_circle</span>Ajouter Stock</button>
                @endcan
            </div>
            <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
                <div class="overflow-x-auto">
                    <table class="w-full rtable">
                        <thead class="bg-surface-zebra border-b border-outline-variant">
                            <tr>
                                <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Code</th>
                                <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Désignation</th>
                                <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Catégorie</th>
                                <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Stock</th>
                                <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">PMP Unit.</th>
                                <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Valeur</th>
                                <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Urgence</th>
                                <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            @forelse($this->stockRows as $i => $row)
                                <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                                    <td data-label="Code" class="px-md py-sm text-xs font-mono">{{ $row['product']->sku }}</td>
                                    <td data-label="Désignation" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $row['product']->name }}</td>
                                    <td data-label="Catégorie" class="px-md py-sm text-xs">{{ $row['product']->category?->label }}</td>
                                    <td data-label="Stock" class="px-md py-sm text-xs text-right {{ $row['stock_negatif'] ? 'text-error-deep font-bold' : '' }}">
                                        {{ rtrim(rtrim(number_format($row['product']->stock_qty, 2, '.', ''), '0'), '.') }} {{ $row['product']->unit }}
                                        @if($row['stock_negatif'])
                                            <span class="block text-[10px] font-bold uppercase">Entrée non saisie</span>
                                        @endif
                                    </td>
                                    <td data-label="PMP" class="px-md py-sm text-xs text-right">{{ $row['pmp'] !== null ? number_format($row['pmp'], 0, ',', ' ') : '—' }}</td>
                                    <td data-label="Valeur" class="px-md py-sm text-xs text-right font-bold">{{ $row['valeur'] !== null ? number_format($row['valeur'], 0, ',', ' ') : '—' }}</td>
                                    <td data-label="Urgence" class="px-md py-sm">
                                        @if($row['urgence'])
                                            <span class="inline-flex items-center gap-1 px-sm py-[2px] rounded-full text-[11px] font-bold border bg-error-red text-white border-error-red animate-pulse">
                                                <span class="material-symbols-outlined text-[13px]">priority_high</span>Critique
                                            </span>
                                        @else
                                            <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">Normal</span>
                                        @endif
                                    </td>
                                    <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                        @can('manage-stocks')
                                            <a wire:navigate href="{{ route('stocks.produits.modifier', $row['product']->id) }}" class="text-outline hover:text-brand-forest p-1 inline-block" title="Modifier le produit"><span class="material-symbols-outlined text-[16px]">edit</span></a>
                                        @endcan
                                    </td>
                                </tr>
                            @empty
                                <tr><td colspan="8" class="px-md py-lg text-center text-outline">Aucun produit pour le moment.</td></tr>
                            @endforelse
                        </tbody>
                    </table>
                </div>
            </div>
        </div>

        <x-modal name="modal-ajouter-stock" max-width="sm">
            <div class="flex items-center justify-between mb-md">
                <h3 class="font-bold text-lg text-brand-forest">Ajouter Stock</h3>
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-ajouter-stock' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
            </div>
            <form wire:submit="submitAjouterStock" class="space-y-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date du Nouveau Stock *</label>
                    <input wire:model="addDate" type="date" @if($this->dateMinHorsExerciceClos) min="{{ $this->dateMinHorsExerciceClos }}" @endif class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('addDate') ? 'is-invalid' : 'border-outline-variant' }}">
                    {{-- 🔴→✅ Ticket EX6 — le motif R4 posé sous « Date » par EX5 n'était affiché nulle part : refus muet. --}}
                    @error('addDate') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Produit *</label>
                    <select wire:model="addProductId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('addProductId') ? 'is-invalid' : 'border-outline-variant' }}">
                        <option value="">-- Sélectionner un produit --</option>
                        @foreach($this->products as $product)
                            <option value="{{ $product->id }}">{{ $product->name }}</option>
                        @endforeach
                    </select>
                    @error('addProductId') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Quantité Ajoutée *</label>
                    <input wire:model="addQty" type="number" min="1" placeholder="ex : 20" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('addQty') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('addQty') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                    <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-ajouter-stock' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                    <button @lectureSeule type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
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
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date / Heure</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Référence</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Produit</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Type</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Motif</th>
                            <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Quantité</th>
                            <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Valeur</th>
                        </tr>
                    </thead>
                    <tbody>
                        @forelse($this->movements as $i => $movement)
                            <tr class="border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                                <td data-label="Date / Heure" class="px-md py-sm text-xs">{{ $movement->movement_date->format('d/m/Y H:i') }}</td>
                                <td data-label="Référence" class="px-md py-sm text-xs font-mono">{{ $movement->reference_id ? strtoupper(substr($movement->reference_id, 0, 8)) : '—' }}</td>
                                <td data-label="Produit" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $movement->product?->name }}</td>
                                <td data-label="Type" class="px-md py-sm text-xs">
                                    @if($movement->type === 'entree')
                                        <span class="text-brand-emerald font-bold">Entrée</span>
                                    @elseif($movement->type === 'sortie')
                                        <span class="text-error-red font-bold">Sortie</span>
                                    @else
                                        <span class="text-accent-yellow font-bold">Ajustement</span>
                                    @endif
                                </td>
                                <td data-label="Motif" class="px-md py-sm text-xs">{{ $this->referenceLabel($movement->reference_type) }}{{ $movement->reason ? ' — '.$movement->reason : '' }}</td>
                                <td data-label="Quantité" class="px-md py-sm text-xs text-right {{ $movement->type === 'sortie' ? 'text-error-red' : 'text-brand-emerald' }} font-bold">{{ $movement->type === 'sortie' ? '-' : '+' }}{{ rtrim(rtrim(number_format($movement->quantity, 2, '.', ''), '0'), '.') }}</td>
                                @php $movPmp = $movement->product?->computePmp(); @endphp
                                <td data-label="Valeur" class="px-md py-sm text-xs text-right">{{ $movPmp !== null ? number_format(abs($movement->quantity) * $movPmp, 0, ',', ' ').' FCFA' : '—' }}</td>
                            </tr>
                        @empty
                            <tr><td colspan="7" class="px-md py-lg text-center text-outline">Aucun mouvement enregistré pour le moment.</td></tr>
                        @endforelse
                    </tbody>
                </table>
            </div>
            <x-pagination :paginator="$this->movements" />
        </div>
    @endif

    @if($tab === 'ajustements')
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-lg max-w-xl">
            <h3 class="text-sm font-bold text-brand-forest mb-md">Saisir un ajustement d'inventaire</h3>
            <div class="space-y-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Produit</label>
                    <select wire:model.live="adjProductId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('adjProductId') ? 'is-invalid' : 'border-outline-variant' }}">
                        <option value="">-- Sélectionner --</option>
                        @foreach($this->products as $product)
                            <option value="{{ $product->id }}">{{ $product->name }} (Théorique : {{ rtrim(rtrim(number_format($product->stock_qty, 2, '.', ''), '0'), '.') }})</option>
                        @endforeach
                    </select>
                    @error('adjProductId') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div class="grid grid-cols-2 gap-md">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Stock théorique</label>
                        <div class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra flex items-center">{{ $this->adjSelectedProduct ? rtrim(rtrim(number_format($this->adjSelectedProduct->stock_qty, 2, '.', ''), '0'), '.') : '—' }}</div>
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Stock physique constaté</label>
                        <input wire:model.live="adjPhysical" type="number" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('adjPhysical') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('adjPhysical') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                </div>
                <div class="bg-surface-zebra rounded-lg p-sm text-center">
                    <span class="text-[10px] text-outline uppercase font-bold">Écart calculé</span>
                    <p class="text-xl font-extrabold {{ $this->adjDiff < 0 ? 'text-error-deep' : ($this->adjDiff > 0 ? 'text-brand-emerald' : 'text-brand-forest') }}">{{ $this->adjDiff > 0 ? '+' : '' }}{{ $this->adjDiff }}</p>
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Motif de l'écart</label>
                    <select wire:model="adjReason" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                        <option value="">-- Sélectionner selon le sens de l'écart --</option>
                        <optgroup label="Écart négatif (perte)">
                            <option>Casse de matériel</option>
                            <option>Vol / Disparition</option>
                            <option>Mortalité non déclarée</option>
                            <option>Erreur de pesée d'approvisionnement</option>
                            <option>Péremption dépassée</option>
                        </optgroup>
                        <optgroup label="Écart positif (surplus)">
                            <option>Naissance non répertoriée</option>
                            <option>Surplus de livraison</option>
                            <option>Erreur d'inventaire antérieur</option>
                        </optgroup>
                    </select>
                </div>
                <button @lectureSeule type="button" wire:click="validateAdjustment" class="w-full py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs">Valider l'ajustement</button>
                {{-- Ticket U11 : l'aide annonçait l'écriture « pas encore active » ; elle l'est depuis le ticket 14.41
                     (`RecordStockAdjustmentEntryAction`). Même texte au poste (`gestion_stocks_screen.dart`). --}}
                <p class="text-[10px] text-outline">Si l'écart est négatif, une écriture de charge exceptionnelle (compte 657) est générée automatiquement, valorisée au PMP.</p>
            </div>
        </div>
    @endif
</div>
