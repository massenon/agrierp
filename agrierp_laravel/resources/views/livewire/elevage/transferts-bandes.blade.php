<div>
    <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">swap_horiz</span>Transferts entre Bandes
            </h2>
            <p class="text-xs text-outline mt-xs">Sujets passés d'une bande à une autre le même jour : sortie de la bande source, entrée dans la bande cible, effectifs recalculés.</p>
        </div>
        @can('manage-elevage')
        <button @lectureSeule type="button" wire:click="nouveauTransfert" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
            <span class="material-symbols-outlined text-[18px]">add_circle</span>Nouveau Transfert
        </button>
        @endcan
    </div>

    <x-kpi-accordion title="Indicateurs des transferts">
        <x-kpi-card label="Transferts du Mois" icon="swap_horiz" color="emerald" :value="$this->kpis['transferts_mois']" caption="Transferts actifs datés de ce mois" />
        <x-kpi-card label="Sujets Transférés" icon="pets" color="blue" :value="number_format($this->kpis['sujets_mois'], 0, ',', ' ')" caption="Cumul des sujets transférés ce mois" />
        <x-kpi-card label="Bandes Rattachées" icon="link" color="maize" :value="$this->kpis['bandes_rattachees']" caption="Bandes reliées à leur bande d'origine" />
        <x-kpi-card label="Bandes à Vérifier" icon="warning" color="red" :value="$this->kpis['a_verifier']" caption="Bandes peut-être issues d'une autre, sans origine renseignée" />
    </x-kpi-accordion>

    @if($this->bandesARattacher->isNotEmpty())
        <div class="bg-white border border-outline-variant rounded-lg p-md mb-md">
            <p class="text-xs font-bold text-brand-forest uppercase mb-xs flex items-center gap-xs"><span class="material-symbols-outlined text-[18px] text-accent-yellow">warning</span>Bandes à vérifier : double comptage possible</p>
            <p class="text-[11px] text-outline mb-sm">Une bande créée pour accueillir une portée a un effectif initial qui compte déjà ces sujets ; s'ils sont aussi nés dans la bande mère, ils y sont encore comptés. Rattachez chaque bande concernée à sa bande d'origine : la sortie est inscrite dans la bande mère au jour de création, rien n'est ajouté à la bande rattachée. Une bande achetée ou constituée d'animaux extérieurs ne se rattache pas.</p>
            <div class="overflow-x-auto">
                <table class="w-full rtable">
                    <thead class="bg-surface-zebra border-b border-outline-variant">
                        <tr>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Code Bande</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Espèce</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date Création</th>
                            <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Effectif Initial</th>
                            <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach($this->bandesARattacher as $lot)
                            <tr wire:key="rattacher-{{ $lot->id }}" class="border-b border-outline-variant last:border-0">
                                <td data-label="Code Bande" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $lot->code }}</td>
                                <td data-label="Espèce" class="px-md py-sm text-xs">{{ $lot->species?->label }}</td>
                                <td data-label="Date Création" class="px-md py-sm text-xs">{{ $lot->created_date->format('d/m/Y') }}</td>
                                <td data-label="Effectif Initial" class="px-md py-sm text-xs text-right">{{ number_format($lot->initial_quantity, 0, ',', ' ') }}</td>
                                <td data-label="Actions" class="px-md py-sm text-right">
                                    @can('manage-elevage')
                                    <button @lectureSeule type="button" wire:click="rattacher('{{ $lot->id }}')" class="text-xs font-bold text-brand-emerald hover:text-brand-forest">Rattacher à sa bande d'origine</button>
                                    @endcan
                                </td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
        </div>
    @endif

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Bande Source</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Bande Cible</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Sujets</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Catégorie</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Type</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Motif</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Statut</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @php
                        $libellesCategories = ['repro' => 'Reproducteur', 'sevre' => 'Sous-mères / Porcelet', 'jeune' => 'Jeune / Porc Marchand'];
                    @endphp
                    @forelse($this->transferts as $transfert)
                        <tr wire:key="transfert-{{ $transfert->id }}" class="border-b border-outline-variant last:border-0 {{ $transfert->is_active ? '' : 'opacity-60' }}">
                            <td data-label="Date" class="px-md py-sm text-xs">{{ $transfert->transfer_date->format('d/m/Y') }}</td>
                            <td data-label="Bande Source" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $transfert->source?->code }}</td>
                            <td data-label="Bande Cible" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $transfert->cible?->code }}</td>
                            <td data-label="Sujets" class="px-md py-sm text-xs text-right">{{ number_format($transfert->quantity, 0, ',', ' ') }}</td>
                            <td data-label="Catégorie" class="px-md py-sm text-xs">{{ $libellesCategories[$transfert->categorie] ?? '—' }}</td>
                            <td data-label="Type" class="px-md py-sm text-xs">{{ $transfert->constitution ? 'Constitution de bande' : 'Transfert' }}</td>
                            <td data-label="Motif" class="px-md py-sm text-xs">{{ $transfert->motif ?: '—' }}</td>
                            <td data-label="Statut" class="px-md py-sm text-xs">
                                @if($transfert->is_active)
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">Actif</span>
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-surface-zebra text-outline border-outline-variant">Annulé</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right">
                                @can('manage-elevage')
                                    @if($transfert->is_active)
                                        <button @lectureSeule type="button" wire:click="annuler('{{ $transfert->id }}')" wire:confirm="Annuler ce transfert ? Les deux bandes seront recalculées." class="text-xs font-bold text-error-deep hover:underline">Annuler</button>
                                    @endif
                                @endcan
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="9" class="px-md py-lg text-center text-xs text-outline">Aucun transfert enregistré.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
        <x-pagination :paginator="$this->transferts" />
    </div>

    <x-modal name="modal-transfert" max-width="md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ $constitution ? 'Rattacher une Bande à sa Bande d\'Origine' : 'Nouveau Transfert' }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-transfert' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="enregistrer" class="space-y-md">
            @error('transfert')
                <div class="bg-error-bg border border-error-deep/30 rounded-lg p-sm text-xs text-error-deep" role="alert">{{ $message }}</div>
            @enderror
            @if($constitution)
                <p class="text-[11px] text-outline bg-surface-zebra rounded-lg p-sm">Les sujets de la bande rattachée sont retirés de la bande d'origine au jour de création ({{ \Illuminate\Support\Carbon::parse($transfer_date)->format('d/m/Y') }}). L'effectif de la bande rattachée ne change pas : il les comptait déjà.</p>
            @endif
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-md">
                <div>
                    <label for="transfert-source" class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ $constitution ? 'Bande d\'Origine *' : 'Bande Source *' }}</label>
                    <select id="transfert-source" wire:model.live="source_lot_id" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('source_lot_id') ? 'is-invalid' : 'border-outline-variant' }}">
                        <option value="">Choisir une bande</option>
                        @foreach($this->sources as $lot)
                            <option value="{{ $lot->id }}">{{ $lot->code }} — {{ $lot->species?->label }} ({{ number_format($lot->current_quantity, 0, ',', ' ') }})</option>
                        @endforeach
                    </select>
                    @error('source_lot_id') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label for="transfert-cible" class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ $constitution ? 'Bande Rattachée' : 'Bande Cible *' }}</label>
                    @if($constitution)
                        <input id="transfert-cible" type="text" disabled value="{{ $this->lots->firstWhere('id', $target_lot_id)?->code }}" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra text-outline">
                    @else
                        <select id="transfert-cible" wire:model="target_lot_id" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('target_lot_id') ? 'is-invalid' : 'border-outline-variant' }}">
                            <option value="">{{ $source_lot_id ? 'Choisir une bande de la même espèce' : 'Choisir d\'abord la bande source' }}</option>
                            @foreach($this->cibles as $lot)
                                <option value="{{ $lot->id }}">{{ $lot->code }} ({{ number_format($lot->current_quantity, 0, ',', ' ') }})</option>
                            @endforeach
                        </select>
                        @error('target_lot_id') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    @endif
                </div>
                <div>
                    <label for="transfert-date" class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date du Transfert *</label>
                    <input id="transfert-date" wire:model="transfer_date" type="date" max="{{ now()->format('Y-m-d') }}" @disabled($constitution) class="w-full h-11 px-md border rounded-lg text-sm {{ $constitution ? 'bg-surface-zebra text-outline' : 'bg-white' }} {{ $errors->has('transfer_date') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('transfer_date') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                <div>
                    <label for="transfert-quantite" class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Nombre de Sujets *</label>
                    <input id="transfert-quantite" wire:model="quantity" type="number" min="1" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('quantity') ? 'is-invalid' : 'border-outline-variant' }}">
                    @error('quantity') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>
                @if(count($this->categories) > 0)
                    <div class="sm:col-span-2">
                        <label for="transfert-categorie" class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Catégorie des Sujets *</label>
                        <select id="transfert-categorie" wire:model="categorie" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('categorie') ? 'is-invalid' : 'border-outline-variant' }}">
                            <option value="">Choisir une catégorie</option>
                            @foreach($this->categories as $cle => $libelle)
                                <option value="{{ $cle }}">{{ $libelle }}</option>
                            @endforeach
                        </select>
                        <p class="text-[10px] text-outline mt-xs">Les sujets gardent leur catégorie dans la bande cible : un changement de bande n'est pas un changement de stade.</p>
                    </div>
                @endif
                <div class="sm:col-span-2">
                    <label for="transfert-motif" class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Motif</label>
                    <input id="transfert-motif" wire:model="motif" type="text" maxlength="255" placeholder="Ex. : sevrage de la portée de la lapine L-12" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                </div>
            </div>
            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-transfert' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button @lectureSeule type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">{{ $constitution ? 'Rattacher' : 'Enregistrer le Transfert' }}</button>
            </div>
        </form>
    </x-modal>
</div>
