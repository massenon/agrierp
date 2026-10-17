<div>
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">restaurant</span>Bon d'Abattage &amp; Transformation
        </h2>
        <p class="text-xs text-outline mt-xs">Convertit des sujets vivants en produits finis vendables au POS — impact automatique sur le cheptel et le stock.</p>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-3 gap-md mb-lg">
        <x-kpi-card label="Transformations (mois)" icon="restaurant" color="emerald" :value="$this->kpis['transformations_mois']" />
        <x-kpi-card label="Sujets Transformés" icon="pets" color="blue" :value="$this->kpis['sujets_transformes']" />
        <x-kpi-card label="Valeur Stock Produit Fini" icon="inventory_2" color="maize" :pending="true" pending-since="Sprint 6 (Stocks) — valorisation de stock réelle" />
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-[55%_45%] gap-md mb-xl">
        <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md">
            <p class="text-xs font-bold text-brand-forest uppercase">1. Sélection de la Bande Source</p>
            <form wire:submit="validateTransformation" class="space-y-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Lot / Bande d'Élevage *</label>
                    <select wire:model.live="lotId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('lotId') ? 'is-invalid' : 'border-outline-variant' }}">
                        <option value="">-- Sélectionner --</option>
                        @foreach($this->lots as $lot)
                            <option value="{{ $lot->id }}">{{ $lot->code }} — {{ $lot->current_quantity }} sujets ({{ $lot->species?->label }})</option>
                        @endforeach
                    </select>
                    <p class="text-[10px] text-outline mt-xs">
                        @if($this->selectedLot)
                            Effectif disponible : <strong class="text-brand-emerald">{{ $this->selectedLot->current_quantity }}</strong> sujets.
                        @else
                            Sélectionnez une bande pour voir son effectif disponible.
                        @endif
                    </p>
                    @error('lotId') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>

                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Nombre de Sujets à Abattre *</label>
                    <input wire:model="qtyAnimals" type="number" min="1" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('qtyAnimals') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('qtyAnimals') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>

                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Produit Fini Cible *</label>
                    <select wire:model="productId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('productId') ? 'is-invalid' : 'border-outline-variant' }}" @if(!$lotId) disabled @endif>
                        <option value="">-- Choisir un produit --</option>
                        @foreach($this->eligibleProducts as $product)
                            <option value="{{ $product->id }}">{{ $product->name }}</option>
                        @endforeach
                    </select>
                    @error('productId') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>

                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Quantité Produite (Unités / Kg)</label>
                    <input wire:model="qtyProduced" type="number" min="0" step="0.01" placeholder="ex : 10" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('qtyProduced') ? 'is-invalid' : 'border-outline-variant' }}">
                    <p class="text-[10px] text-outline mt-xs">Rendement libre — saisie manuelle sans calcul automatique (poids variable selon transformation).</p>
                    @error('qtyProduced') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>

                <div class="grid grid-cols-2 gap-sm">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date de Transaction</label>
                        <input wire:model="transformationDate" type="date" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Opérateur</label>
                        <div class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra flex items-center text-outline">{{ auth()->user()->name }}</div>
                    </div>
                </div>

                <button type="submit" wire:loading.attr="disabled" wire:target="validateTransformation" class="w-full py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-sm flex items-center justify-center gap-xs disabled:opacity-50">
                    <span class="material-symbols-outlined text-[18px]">check_circle</span>Valider la Transformation
                </button>
            </form>
        </div>

        <div class="bg-white border border-outline-variant rounded-lg p-md">
            <p class="text-xs font-bold text-brand-forest uppercase mb-md">Impact Automatique Prévisualisé</p>
            <div class="space-y-sm">
                <div class="flex items-start gap-sm p-sm bg-error-bg border border-error-deep/20 rounded-lg">
                    <span class="material-symbols-outlined text-error-deep text-[18px] flex-shrink-0">trending_down</span>
                    <div class="text-xs"><p class="font-bold text-error-deep">Élevage — Décrémentation</p><p class="text-outline">L'effectif vivant de la bande sera réduit du nombre de sujets abattus.</p></div>
                </div>
                <div class="flex items-start gap-sm p-sm bg-brand-emerald/10 border border-brand-emerald/20 rounded-lg">
                    <span class="material-symbols-outlined text-brand-emerald text-[18px] flex-shrink-0">trending_up</span>
                    <div class="text-xs"><p class="font-bold text-brand-emerald">Stock Produits Finis — Incrémentation</p><p class="text-outline">Le stock du produit fini choisi sera augmenté de la quantité produite saisie.</p></div>
                </div>
                <div class="flex items-start gap-sm p-sm bg-surface-zebra border border-outline-variant rounded-lg">
                    <span class="material-symbols-outlined text-outline text-[18px] flex-shrink-0">account_balance</span>
                    <div class="text-xs"><p class="font-bold text-outline">Comptabilité — Variation de Stock</p><p class="text-outline">Écriture automatique (Débit 313 / Crédit 73) en attente du Sprint 10 (journal comptable) — non générée pour le moment.</p></div>
                </div>
                <div class="flex items-start gap-sm p-sm bg-accent-yellow/10 border border-accent-yellow/30 rounded-lg">
                    <span class="material-symbols-outlined text-brand-forest text-[18px] flex-shrink-0">point_of_sale</span>
                    <div class="text-xs"><p class="font-bold text-brand-forest">Vente au POS</p><p class="text-outline">Le produit est immédiatement disponible au catalogue (stock déjà incrémenté). L'imputation au centre analytique arrive avec la comptabilité (Sprint 10).</p></div>
                </div>
            </div>
        </div>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="px-md py-sm border-b border-outline-variant"><h3 class="text-sm font-bold text-brand-forest">Historique des Transformations</h3></div>
        <div class="overflow-x-auto">
            <table class="w-full text-xs">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Bande Source</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Sujets Abattus</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Produit Fini</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Qté Produite</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Statut</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->history as $i => $t)
                        <tr class="border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td class="px-md py-sm">{{ $t->transformation_date->format('d/m/Y') }}</td>
                            <td class="px-md py-sm font-bold text-brand-forest">{{ $t->lot?->code }}</td>
                            <td class="px-md py-sm text-right">{{ $t->qty_animals }}</td>
                            <td class="px-md py-sm">{{ $t->product?->name }}</td>
                            <td class="px-md py-sm text-right">{{ rtrim(rtrim(number_format($t->qty_produced, 2, '.', ''), '0'), '.') }}</td>
                            <td class="px-md py-sm"><span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-surface-zebra text-outline border-outline-variant">Non comptabilisé</span></td>
                        </tr>
                    @empty
                        <tr><td colspan="6" class="px-md py-lg text-center text-outline">Aucune transformation enregistrée pour le moment.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>
</div>
