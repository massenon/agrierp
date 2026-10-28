<div>
    <div class="flex flex-col xl:flex-row xl:items-center xl:justify-between gap-sm border-b border-outline-variant pb-md mb-lg">
        <div class="min-w-0">
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">layers</span>Bandes &amp; Sujets
            </h2>
            <p class="text-xs text-outline mt-xs">Effectif vivant en temps réel, stade physiologique et statut, par bande.</p>
        </div>
        <div class="flex flex-wrap xl:flex-nowrap items-center gap-sm xl:shrink-0">
            <a wire:navigate href="{{ route('elevage.enregistrer-sujets') }}" class="flex items-center whitespace-nowrap gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full">
                <span class="material-symbols-outlined text-[18px]">pets</span>Enregistrer des Sujets
            </a>
            <a wire:navigate href="{{ route('elevage.reproducteurs') }}" class="flex items-center whitespace-nowrap gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full">
                <span class="material-symbols-outlined text-[18px]">badge</span>Registre des Reproducteurs
            </a>
            @can('manage-elevage')
            <button type="button" wire:click="newLot" class="flex items-center whitespace-nowrap gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
                <span class="material-symbols-outlined text-[18px]">add_circle</span>Nouvelle Bande
            </button>
            @endcan
        </div>
    </div>

    @if($this->doublonsDeCodes > 0)
    <div data-doublons-codes class="flex items-start gap-sm bg-accent-yellow/20 border border-accent-yellow text-brand-forest rounded-lg px-md py-sm mb-md text-xs">
        <span class="material-symbols-outlined text-[18px]">warning</span>
        <p><span class="font-bold">{{ $this->doublonsDeCodes }} {{ $this->doublonsDeCodes === 1 ? 'doublon de code détecté' : 'doublons de code détectés' }} — à renommer.</span> Des bandes portent le même code : cliquez sur « Modifier » pour corriger le code de l'une d'elles. Rien n'est supprimé ni modifié automatiquement.</p>
    </div>
    @endif

    <x-kpi-accordion title="Indicateurs de performance">
        <x-kpi-card label="Bandes Actives" icon="layers" color="emerald" :value="$this->kpis['bandes_actives']" caption="Lots au statut « Actif », toutes espèces" />
        <x-kpi-card label="En Reproduction" icon="favorite" color="blue" :value="$this->kpis['en_reproduction']" caption="Bandes au stade Reproduction" />
        <x-kpi-card label="Effectif Total Vivant" icon="pets" color="maize" :value="number_format($this->kpis['effectif_total'], 0, ',', ' ')" caption="Cumul de toutes les bandes actives" />
        <x-kpi-card label="Alertes Sanitaires" icon="warning" color="red" :value="$this->kpis['alertes_sanitaires']" caption="Bandes sous rémanence ou soin actif" />
    </x-kpi-accordion>

    <div class="flex justify-end mb-sm">
        <button type="button" wire:click="exportBandesPdf" wire:loading.attr="disabled" wire:target="exportBandesPdf" class="flex items-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full disabled:opacity-50">
            <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Exporter PDF
        </button>
    </div>

    <div class="bg-white border border-outline-variant rounded-lg p-md mb-md flex flex-wrap items-center gap-sm">
        <div class="relative flex-1 min-w-[180px]">
            <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
            <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher un code de bande..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
        </div>
        <select wire:model.live="filiere" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <option value="">Espèce : Toutes</option>
            <option value="cuniculture">Cuniculture</option>
            <option value="aviculture">Aviculture</option>
            <option value="porciculture">Porciculture</option>
            <option value="helico">Héliciculture</option>
        </select>
        <select wire:model.live="affichage" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <option value="">Bandes en cours</option>
            <option value="archivees">Bandes archivées</option>
        </select>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Code Bande</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Espèce</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Stade</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date Création</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Effectif Initial</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Effectif Actuel</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Mortalité</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Statut</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->lots as $i => $lot)
                        @php
                            $mortaliteRate = $lot->initial_quantity > 0 ? round((($lot->initial_quantity - $lot->current_quantity) / $lot->initial_quantity) * 100, 1) : null;   // effectif initial 0 : mortalité INCONNUE (« — »), jamais 0 %
                        @endphp
                        <tr wire:click="view('{{ $lot->id }}')" class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 cursor-pointer {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Code Bande" class="px-md py-sm text-xs font-bold text-brand-emerald">{{ $lot->code }}</td>
                            <td data-label="Espèce" class="px-md py-sm text-xs">{{ $lot->species?->label }}</td>
                            <td data-label="Stade" class="px-md py-sm"><span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-accent-yellow/20 text-brand-forest border-accent-yellow">{{ $lot->libelleStade() }}</span></td>
                            <td data-label="Date Création" class="px-md py-sm text-xs">{{ $lot->created_date->format('d/m/Y') }}</td>
                            <td data-label="Effectif Initial" class="px-md py-sm text-xs text-right">{{ $lot->initial_quantity }}</td>
                            <td data-label="Effectif Actuel" class="px-md py-sm text-xs text-right font-bold">{{ $lot->current_quantity }}</td>
                            <td data-label="Mortalité" class="px-md py-sm text-xs text-right {{ ($mortaliteRate ?? 0) > 0 ? 'text-error-deep font-bold' : 'text-outline' }}">{{ $mortaliteRate === null ? '—' : $mortaliteRate.'%' }}</td>
                            <td data-label="Statut" class="px-md py-sm">
                                @if($lot->status === 'actif')
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">Actif</span>
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-surface-zebra text-outline border-outline-variant">Clôturé</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap" wire:click.stop>
                                @can('manage-elevage')
                                @if($affichage === 'archivees')
                                <button type="button" wire:click="restoreLot('{{ $lot->id }}')" class="text-brand-emerald hover:text-brand-forest p-1" title="Restaurer"><span class="material-symbols-outlined text-[16px]">restore_from_trash</span></button>
                                @else
                                <button type="button" wire:click="editLot('{{ $lot->id }}')" class="text-info-blue hover:text-brand-forest p-1" title="Modifier"><span class="material-symbols-outlined text-[16px]">edit</span></button>
                                <button type="button" x-on:click="$dispatch('open-modal', { name: 'archive-bande-{{ $lot->id }}' })" class="text-error-deep hover:text-error-deep/70 p-1" title="Archiver"><span class="material-symbols-outlined text-[16px]">delete</span></button>
                                @endif
                                @else
                                <span class="text-outline text-[10px] italic">Lecture seule</span>
                                @endcan
                            </td>
                        </tr>
                        @if($affichage !== 'archivees')
                        <x-modal-confirm-delete :name="'archive-bande-'.$lot->id" :item-label="$lot->code" :action="'archiveLot(\''.$lot->id.'\')'" />
                        @endif
                    @empty
                        <tr><td colspan="9" class="px-md py-xl text-center text-outline">{{ $affichage === 'archivees' ? 'Aucune bande archivée.' : 'Aucune bande pour le moment. Cliquez sur « Nouvelle Bande » pour commencer.' }}</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal name="modal-create-bande" max-width="sm">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">Nouvelle Bande</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-bande' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveLot" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Espèce *</label>
                <select wire:model.live="species_id" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('species_id') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    @foreach($this->speciesOptions as $sp)
                        <option value="{{ $sp->id }}">{{ $sp->label }}</option>
                    @endforeach
                </select>
                @error('species_id') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Code Unique de la Bande *</label>
                <input wire:model="code" type="text" placeholder="ex : LOT-LAP-7" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('code') ? 'is-invalid' : 'border-outline-variant' }}">
                <p class="text-[10px] text-outline mt-xs">Numérotation continue suggérée automatiquement — modifiable si besoin.</p>
                @error('code') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Stade Initial</label>
                <select wire:model="stage" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                    @foreach($this->stades as $valeurStade => $libelleStade)
                        <option value="{{ $valeurStade }}">{{ $libelleStade }}</option>
                    @endforeach
                </select>
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date de Création</label>
                <input wire:model="created_date" type="date" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('created_date') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('created_date') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Quantité Initiale (Effectif) *</label>
                <input wire:model="quantity" type="number" min="1" placeholder="ex : 27" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('quantity') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('quantity') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Coût d'Acquisition (FCFA)</label>
                <input wire:model="acquisition_cost" type="number" min="0" placeholder="ex : 135000" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Produit issu de cette bande</label>
                <select wire:model="product_id" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                    <option value="">-- Aucun (pas de mouvement de stock) --</option>
                    @foreach($this->produitsCandidats as $produit)
                        <option value="{{ $produit->id }}">{{ $produit->sku }} — {{ $produit->name }}</option>
                    @endforeach
                </select>
                @error('product_id') <p class="invalid-feedback">{{ $message }}</p> @enderror
                <p class="text-[10px] text-outline mt-xs">Les naissances entreront en stock sur ce produit ; mortalité et dons l'en retireront. Sélectionnez d'abord la filière.</p>
            </div>
            <div>
                <label for="bande-origine" class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Bande d'Origine</label>
                <select id="bande-origine" wire:model="lot_origine_id" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('lot_origine_id') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Aucune (achat, animaux extérieurs) --</option>
                    @foreach($this->bandesOriginePossibles as $origine)
                        <option value="{{ $origine->id }}">{{ $origine->code }} ({{ number_format($origine->current_quantity, 0, ',', ' ') }})</option>
                    @endforeach
                </select>
                @error('lot_origine_id') <p class="invalid-feedback">{{ $message }}</p> @enderror
                <p class="text-[10px] text-outline mt-xs">Portée ou sevrés déjà comptés dans une autre bande : ils en sortent le jour de création, pour n'être comptés qu'une fois.</p>
            </div>
            <p class="text-[10px] text-outline bg-surface-zebra rounded-lg p-sm">Le suivi individuel par sujet (N° Lapine, etc.) se paramètre depuis Enregistrer Sujets, une fois la bande créée.</p>
            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-bande' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Créer la Bande</button>
            </div>
        </form>
    </x-modal>

    <x-modal name="modal-edit-bande" max-width="sm">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">Modifier la Bande</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-edit-bande' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="updateLot" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Code Unique de la Bande</label>
                @if($codeEnDoublon)
                <input wire:model="code" type="text" maxlength="50" data-code-en-doublon class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('code') ? 'is-invalid' : 'border-outline-variant' }}">
                <p class="text-[10px] text-outline mt-xs">Ce code est partagé avec une autre bande : corrigez-le (il redeviendra non modifiable ensuite).</p>
                @error('code') <p class="invalid-feedback">{{ $message }}</p> @enderror
                @else
                <input value="{{ $code }}" type="text" disabled class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra text-outline">
                <p class="text-[10px] text-outline mt-xs">L'identifiant technique unique n'est jamais modifiable après création.</p>
                @endif
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Stade *</label>
                <select wire:model="stage" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                    @foreach($this->stades as $valeurStade => $libelleStade)
                        <option value="{{ $valeurStade }}">{{ $libelleStade }}</option>
                    @endforeach
                </select>
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Effectif Actuel *</label>
                @if($effectifVerrouille)
                <input wire:model="quantity" type="number" min="0" disabled data-effectif-verrouille title="{{ \App\Actions\SaisieBandeAction::INFOBULLE_EFFECTIF_PAR_LES_FICHES }}" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra text-outline cursor-not-allowed">
                <p class="text-[10px] text-outline mt-xs">{{ \App\Actions\SaisieBandeAction::INFOBULLE_EFFECTIF_PAR_LES_FICHES }}</p>
                @else
                <input wire:model="quantity" type="number" min="0" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('quantity') ? 'is-invalid' : 'border-outline-variant' }}">
                @endif
                @error('quantity') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Statut *</label>
                <select wire:model="status" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                    <option value="actif">Actif</option>
                    <option value="cloture">Clôturé</option>
                </select>
            </div>
            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-edit-bande' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer les Modifications</button>
            </div>
        </form>
    </x-modal>

    @if($this->viewingLot)
        <div x-data x-on:keydown.escape.window="$wire.closeDrawer()" class="fixed inset-0 bg-black/40 z-[105]" wire:click="closeDrawer"></div>
        <div class="fixed top-0 right-0 h-full w-full sm:w-96 bg-white z-[106] shadow-2xl overflow-y-auto">
            <div class="flex items-center justify-between px-lg py-md border-b border-outline-variant bg-brand-forest">
                <span class="text-white font-bold text-sm">{{ $this->viewingLot->code }}</span>
                <button type="button" wire:click="closeDrawer" class="text-white/80 hover:text-white"><span class="material-symbols-outlined">close</span></button>
            </div>
            <div class="p-lg space-y-md">
                <div class="grid grid-cols-2 gap-sm text-xs">
                    <div><span class="text-outline block">Espèce</span><span class="font-bold">{{ $this->viewingLot->species?->label }}</span></div>
                    <div><span class="text-outline block">Stade</span><span class="font-bold">{{ $this->viewingLot->libelleStade() }}</span></div>
                    <div><span class="text-outline block">Date Création</span><span class="font-bold">{{ $this->viewingLot->created_date->format('d/m/Y') }}</span></div>
                    <div><span class="text-outline block">Statut</span><span class="font-bold">{{ $this->viewingLot->status === 'actif' ? 'Actif' : 'Clôturé' }}</span></div>
                    <div><span class="text-outline block">Effectif Initial</span><span class="font-bold">{{ $this->viewingLot->initial_quantity }}</span></div>
                    <div><span class="text-outline block">Effectif Actuel</span><span class="font-bold">{{ $this->viewingLot->current_quantity }}</span></div>
                </div>
                @php $autonomie = $this->autonomieBande; $sanitaire = $this->suiviSanitaireBande; @endphp
                <div class="border-t border-outline-variant pt-md space-y-xs">
                    <p class="text-xs font-bold text-brand-forest uppercase mb-xs">Autonomie Alimentaire</p>
                    <x-autonomie-alimentaire :autonomie="$autonomie['filiere'] ?? null" :filiere="'de la filière '.($this->viewingLot->species?->label ?? '')" />
                    <p class="text-[11px] text-outline">
                        Provende servie à cette bande :
                        <strong class="text-brand-forest">{{ ($autonomie['provende_bande_kg'] ?? null) === null ? '—' : number_format($autonomie['provende_bande_kg'], 2, ',', ' ').' Kg/j' }}</strong>
                        @if($autonomie['date_fiche'] ?? null)
                            (fiche du {{ $autonomie['date_fiche']->format('d/m/Y') }})
                        @endif
                    </p>
                </div>
                <div class="border-t border-outline-variant pt-md space-y-xs text-xs">
                    <p class="text-xs font-bold text-brand-forest uppercase mb-xs">Suivi Sanitaire</p>
                    @if($sanitaire['remanence'] ?? null)
                        <div class="bg-error-bg border border-error-deep/30 rounded-lg p-sm text-error-deep" role="alert">
                            <p class="font-bold flex items-center gap-xs"><span class="material-symbols-outlined text-[16px]">block</span>Délai d'attente en cours</p>
                            <p>{{ $sanitaire['remanence']->product_used }} — vente interdite jusqu'au {{ $sanitaire['remanence']->end_date->format('d/m/Y') }}.</p>
                        </div>
                    @else
                        <p class="text-brand-emerald font-semibold">Aucun délai d'attente en cours : vente autorisée.</p>
                    @endif
                    <div class="grid grid-cols-2 gap-sm">
                        <div><span class="text-outline block">En infirmerie</span><span class="font-bold">{{ $sanitaire['infirmerie'] ?? 0 }} sujet(s)</span></div>
                        <div><span class="text-outline block">Mortalité 7 jours</span><span class="font-bold">{{ $sanitaire['morts_7j'] ?? 0 }} mort(s){{ ($sanitaire['mortalite_7j'] ?? null) === null ? '' : ' — '.number_format($sanitaire['mortalite_7j'], 1, ',', ' ').' %' }}</span></div>
                    </div>
                    <div>
                        <span class="text-outline block mb-xs">Derniers soins</span>
                        @forelse($sanitaire['derniers_soins'] ?? [] as $soin)
                            <p>{{ $soin->record_date->format('d/m/Y') }} — {{ $soin->action_type }}{{ $soin->product_used ? ' ('.$soin->product_used.')' : '' }}</p>
                        @empty
                            <p class="text-outline">—</p>
                        @endforelse
                    </div>
                </div>
            </div>
        </div>
    @endif
</div>
