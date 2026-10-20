<div>
    <x-tab-page
        :tabs="[
            ['key' => 'rationnement', 'label' => 'Fiche de Rationnement (g/j)', 'icon' => 'restaurant'],
            ['key' => 'prophylaxie', 'label' => 'Calendriers de Prophylaxie', 'icon' => 'event_repeat'],
            ['key' => 'provende', 'label' => 'Types de Provende', 'icon' => 'inventory_2'],
            ['key' => 'numerotation', 'label' => 'Numérotation Bandes & Sujets', 'icon' => 'tag'],
        ]"
        :active="$tab">

        @if($tab === 'rationnement')
            <div class="space-y-md">
                <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm">
                    <div>
                        <h2 class="text-lg lg:text-xl font-bold flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald">restaurant</span>Fiche de Rationnement des Animaux</h2>
                        <p class="text-xs text-outline mt-xs">Consommation journalière théorique par tête exprimée en <strong>Grammes (g/j)</strong>.</p>
                    </div>
                    <button type="button" wire:click="newRation" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
                        <span class="material-symbols-outlined text-[18px]">add_circle</span>Ajouter une Ration
                    </button>
                </div>
                <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
                    <div class="overflow-x-auto">
                        <table class="w-full rtable text-xs">
                            <thead class="bg-surface-zebra border-b border-outline-variant">
                                <tr>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Espèce</th>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Stade Physiologique / Tranche d'Âge</th>
                                    <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Ration (g/tête/jour)</th>
                                    <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                @foreach($this->rations as $i => $r)
                                    <tr class="rrow border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                                        <td data-label="Espèce" class="px-md py-sm font-semibold capitalize">{{ $r->species_code }}</td>
                                        <td data-label="Stade" class="px-md py-sm">{{ $r->stage_label }}</td>
                                        <td data-label="Ration" class="px-md py-sm text-right font-bold text-brand-emerald">{{ $r->ration_g_per_day }} g</td>
                                        <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                            <button type="button" wire:click="editRation('{{ $r->id }}')" class="text-info-blue hover:text-blue-800 p-1" title="Modifier"><span class="material-symbols-outlined text-[18px]">edit</span></button>
                                            <button type="button" x-on:click="$dispatch('open-modal', { name: 'delete-ration-{{ $r->id }}' })" class="text-error-deep hover:text-red-800 p-1" title="Supprimer"><span class="material-symbols-outlined text-[18px]">delete</span></button>
                                        </td>
                                    </tr>
                                    <x-modal-confirm-permanent-delete :name="'delete-ration-'.$r->id" :item-label="$r->stage_label" :action="'deleteRation(\''.$r->id.'\')'" />
                                @endforeach
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>

            <x-modal name="modal-ration" max-width="sm">
                <div class="flex items-center justify-between mb-md">
                    <h3 class="font-bold text-lg text-brand-forest">{{ $editingRationId ? 'Modifier la Ration' : 'Saisir une Ration' }}</h3>
                    <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-ration' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
                </div>
                <form wire:submit="saveRation" class="space-y-md">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Espèce *</label>
                        <select wire:model="ration_species_code" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                            <option value="aviculture">Aviculture (Volailles)</option>
                            <option value="cuniculture">Cuniculture (Lapins)</option>
                            <option value="porciculture">Porciculture (Porcs)</option>
                        </select>
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Stade Physiologique / Tranche d'Âge *</label>
                        <input wire:model="ration_stage_label" type="text" placeholder="ex : Poussin ponte (0 à 2 mois)" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('ration_stage_label') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('ration_stage_label') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Ration Normative (g/tête/jour) *</label>
                        <input wire:model="ration_grammes" type="number" min="1" step="1" placeholder="ex : 30" class="w-full h-11 px-md border rounded-lg text-sm font-bold text-brand-emerald bg-white {{ $errors->has('ration_grammes') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('ration_grammes') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                        <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-ration' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                        <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
                    </div>
                </form>
            </x-modal>
        @endif

        @if($tab === 'prophylaxie')
            <div class="space-y-md">
                <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm">
                    <div>
                        <h2 class="text-lg lg:text-xl font-bold flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald">event_repeat</span>Calendriers de Prophylaxie &amp; Traitements Récurrents</h2>
                        <p class="text-xs text-outline mt-xs">Programme médical type par espèce.</p>
                    </div>
                    <button type="button" wire:click="newProphy" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
                        <span class="material-symbols-outlined text-[18px]">add_circle</span>Ajouter une Échéance
                    </button>
                </div>

                {{-- Règle R-SOINS-01 : délai du rappel des soins planifiés, réglé par l'exploitant. --}}
                <form wire:submit="saveRappelSoins" class="bg-white border border-outline-variant rounded-lg px-md py-sm flex flex-col sm:flex-row sm:items-end gap-sm">
                    <div class="flex-1">
                        <label for="rappel-soins" class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Rappel des soins planifiés (jours avant la date)</label>
                        <p class="text-xs text-outline">La cloche signale un soin « à venir » quand il reste ce nombre de jours ou moins, puis « en retard » une fois la date dépassée. 0 : le jour même.</p>
                    </div>
                    <input id="rappel-soins" wire:model="rappelSoinsJours" type="number" min="0" max="30" class="w-24 h-11 px-md border border-outline-variant rounded-lg text-sm font-bold text-brand-forest">
                    <button type="submit" class="bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full">Enregistrer</button>
                    @error('rappelSoinsJours') <p class="text-xs text-error-deep">{{ $message }}</p> @enderror
                </form>

                <div class="flex items-center gap-xs border-b border-outline-variant bg-white px-md py-2 rounded-lg">
                    <button type="button" wire:click="$set('prophySpecies', 'cuniculture')" @class(['px-sm py-1 text-xs font-bold rounded-full', 'bg-brand-emerald text-white' => $prophySpecies === 'cuniculture', 'border border-outline-variant text-outline' => $prophySpecies !== 'cuniculture'])>🐰 Cuniculture (Lapins)</button>
                    <button type="button" wire:click="$set('prophySpecies', 'aviculture')" @class(['px-sm py-1 text-xs font-bold rounded-full', 'bg-brand-emerald text-white' => $prophySpecies === 'aviculture', 'border border-outline-variant text-outline' => $prophySpecies !== 'aviculture'])>🐔 Aviculture (Volailles)</button>
                    <button type="button" wire:click="$set('prophySpecies', 'porciculture')" @class(['px-sm py-1 text-xs font-bold rounded-full', 'bg-brand-emerald text-white' => $prophySpecies === 'porciculture', 'border border-outline-variant text-outline' => $prophySpecies !== 'porciculture'])>🐖 Porciculture (Porcs)</button>
                </div>

                <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
                    <div class="overflow-x-auto">
                        <table class="w-full rtable text-xs">
                            <thead class="bg-surface-zebra border-b border-outline-variant">
                                <tr>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Jour / Période</th>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Traitement Prévu</th>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Produit Conseillé</th>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Posologie</th>
                                    <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Délai Rémanence</th>
                                    <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                @forelse($this->prophylaxies as $i => $p)
                                    <tr class="rrow border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                                        <td data-label="Jour" class="px-md py-sm font-semibold whitespace-nowrap">{{ $p->period_label }}</td>
                                        <td data-label="Traitement" class="px-md py-sm">{{ $p->treatment }}</td>
                                        <td data-label="Produit" class="px-md py-sm">{{ $p->product_recommended }}</td>
                                        <td data-label="Posologie" class="px-md py-sm">{{ $p->dosage }}</td>
                                        <td data-label="Rémanence" class="px-md py-sm text-right {{ $p->withdrawal_days > 0 ? 'text-error-deep font-bold' : '' }}">{{ $p->withdrawal_days }} j</td>
                                        <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                            <button type="button" wire:click="editProphy('{{ $p->id }}')" class="text-info-blue hover:text-blue-800 p-1" title="Modifier"><span class="material-symbols-outlined text-[18px]">edit</span></button>
                                            <button type="button" x-on:click="$dispatch('open-modal', { name: 'delete-prophy-{{ $p->id }}' })" class="text-error-deep hover:text-red-800 p-1" title="Supprimer"><span class="material-symbols-outlined text-[18px]">delete</span></button>
                                        </td>
                                    </tr>
                                    <x-modal-confirm-permanent-delete :name="'delete-prophy-'.$p->id" :item-label="$p->treatment" :action="'deleteProphy(\''.$p->id.'\')'" />
                                @empty
                                    <tr><td colspan="6" class="px-md py-lg text-center text-outline">Aucune échéance pour cette espèce pour le moment.</td></tr>
                                @endforelse
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>

            <x-modal name="modal-prophylaxie" max-width="sm">
                <div class="flex items-center justify-between mb-md">
                    <h3 class="font-bold text-lg text-brand-forest">{{ $editingProphyId ? "Modifier l'Échéance" : 'Échéance de Prophylaxie' }}</h3>
                    <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-prophylaxie' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
                </div>
                <form wire:submit="saveProphy" class="space-y-md">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Jour / Âge *</label>
                        <input wire:model="prophy_period_label" type="text" placeholder="ex : Le 1er du mois OU J+14" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('prophy_period_label') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('prophy_period_label') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Traitement Prévu *</label>
                        <input wire:model="prophy_treatment" type="text" placeholder="ex : Vaccination Newcastle" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('prophy_treatment') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('prophy_treatment') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div class="grid grid-cols-2 gap-sm">
                        <div>
                            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Produit Conseillé *</label>
                            <input wire:model="prophy_product" type="text" placeholder="ex : Superhypracox" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('prophy_product') ? 'is-invalid' : 'border-outline-variant' }}">
                            @error('prophy_product') <p class="invalid-feedback">{{ $message }}</p> @enderror
                        </div>
                        <div>
                            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Dose *</label>
                            <input wire:model="prophy_dosage" type="text" placeholder="ex : 1C / 5L d'eau" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('prophy_dosage') ? 'is-invalid' : 'border-outline-variant' }}">
                            @error('prophy_dosage') <p class="invalid-feedback">{{ $message }}</p> @enderror
                        </div>
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Délai de Rémanence (Jours d'attente)</label>
                        <input wire:model="prophy_withdrawal_days" type="number" min="0" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm font-bold text-error-deep bg-white">
                    </div>
                    <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                        <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-prophylaxie' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                        <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
                    </div>
                </form>
            </x-modal>
        @endif

        @if($tab === 'provende')
            <div class="space-y-md">
                <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm">
                    <div>
                        <h2 class="text-lg lg:text-xl font-bold flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald">inventory_2</span>Catalogue des Types de Provende</h2>
                        <p class="text-xs text-outline mt-xs">Gestion des types d'aliments servis en ferme avec conditionnement et prix indicatif au Kilogramme.</p>
                    </div>
                    <button type="button" wire:click="newProvende" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
                        <span class="material-symbols-outlined text-[18px]">add_circle</span>Ajouter un Type
                    </button>
                </div>
                <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
                    <div class="overflow-x-auto">
                        <table class="w-full rtable text-xs">
                            <thead class="bg-surface-zebra border-b border-outline-variant">
                                <tr>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Nom du Type d'Aliment</th>
                                    <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Espèce Cible</th>
                                    <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Poids Sac Standard (Kg)</th>
                                    <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Prix Indicatif (FCFA/Kg)</th>
                                    <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                @forelse($this->provendes as $i => $p)
                                    <tr class="rrow border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                                        <td data-label="Nom" class="px-md py-sm font-semibold">{{ $p->name }}</td>
                                        <td data-label="Espèce" class="px-md py-sm">{{ $p->species?->label }}</td>
                                        <td data-label="Sac" class="px-md py-sm text-right">{{ rtrim(rtrim(number_format($p->standard_bag_weight_kg, 2, '.', ''), '0'), '.') }} Kg</td>
                                        <td data-label="Prix" class="px-md py-sm text-right font-bold text-brand-emerald">{{ number_format($p->price_per_kg, 0, ',', ' ') }} FCFA</td>
                                        <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                            <button type="button" wire:click="editProvende('{{ $p->id }}')" class="text-info-blue hover:text-blue-800 p-1" title="Modifier"><span class="material-symbols-outlined text-[18px]">edit</span></button>
                                            <button type="button" x-on:click="$dispatch('open-modal', { name: 'delete-provende-{{ $p->id }}' })" class="text-error-deep hover:text-red-800 p-1" title="Supprimer"><span class="material-symbols-outlined text-[18px]">delete</span></button>
                                        </td>
                                    </tr>
                                    <x-modal-confirm-permanent-delete :name="'delete-provende-'.$p->id" :item-label="$p->name" :action="'deleteProvende(\''.$p->id.'\')'" />
                                @empty
                                    <tr><td colspan="5" class="px-md py-lg text-center text-outline">Aucun type de provende pour le moment.</td></tr>
                                @endforelse
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>

            <x-modal name="modal-provende" max-width="sm">
                <div class="flex items-center justify-between mb-md">
                    <h3 class="font-bold text-lg text-brand-forest">{{ $editingProvendeId ? 'Modifier le Type de Provende' : 'Type de Provende' }}</h3>
                    <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-provende' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
                </div>
                <form wire:submit="saveProvende" class="space-y-md">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Nom du Type d'Aliment *</label>
                        <input wire:model="provende_name" type="text" placeholder="ex : Aliment Ponte" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('provende_name') ? 'is-invalid' : 'border-outline-variant' }}">
                        @error('provende_name') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Espèce Cible *</label>
                        <select wire:model="provende_species_id" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('provende_species_id') ? 'is-invalid' : 'border-outline-variant' }}">
                            <option value="">-- Sélectionner --</option>
                            @foreach($this->speciesOptions as $sp)
                                <option value="{{ $sp->id }}">{{ $sp->label }}</option>
                            @endforeach
                        </select>
                        @error('provende_species_id') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div class="grid grid-cols-2 gap-sm">
                        <div>
                            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Poids Sac Standard (Kg) *</label>
                            <input wire:model="provende_bag_kg" type="number" min="1" step="0.5" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white font-bold">
                        </div>
                        <div>
                            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Prix Indicatif (FCFA/Kg) *</label>
                            <input wire:model="provende_price_kg" type="number" min="0" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white font-bold text-brand-emerald">
                        </div>
                    </div>
                    <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                        <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-provende' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                        <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
                    </div>
                </form>
            </x-modal>
        @endif

        @if($tab === 'numerotation')
            <div>
                <h2 class="text-lg lg:text-xl font-bold flex items-center gap-xs">
                    <span class="material-symbols-outlined text-brand-emerald">tag</span>Numérotation des Bandes &amp; Sujets Par Espèce
                </h2>
                <p class="text-xs text-outline mt-xs">Formatage des identifiants générés sur le terrain et préfixes individuels par catégorie d'animaux.</p>
            </div>

            <form wire:submit="saveNumbering" class="bg-white rounded-lg border border-outline-variant shadow-sm p-lg space-y-lg max-w-3xl mt-md">
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Format d'Affichage du Nom de Bande (Terrain / Toutes Espèces)</label>
                    <input wire:model="numbering.bande_format" type="text" class="w-full sm:w-64 h-11 px-md border border-outline-variant rounded-lg text-sm font-bold text-brand-forest">
                </div>

                <div class="border-t border-outline-variant pt-md">
                    <p class="text-xs font-bold text-brand-emerald uppercase tracking-wider mb-sm flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">cruelty_free</span>Cuniculture (Lapins)</p>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-md">
                        <div>
                            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Lapines Reproductrices</label>
                            <input wire:model="numbering.lapine_prefix" type="text" maxlength="4" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm font-mono font-bold text-brand-emerald">
                        </div>
                        <div>
                            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Mâles Saillisseurs</label>
                            <input wire:model="numbering.male_prefix" type="text" maxlength="4" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm font-mono font-bold">
                        </div>
                    </div>
                </div>

                <div class="border-t border-outline-variant pt-md">
                    <p class="text-xs font-bold text-brand-emerald uppercase tracking-wider mb-sm flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">pets</span>Porciculture (Porcs)</p>
                    <div class="grid grid-cols-1 sm:grid-cols-3 gap-md">
                        <div>
                            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Truies Reproductrices</label>
                            <input wire:model="numbering.truie_prefix" type="text" maxlength="4" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm font-mono font-bold text-brand-emerald">
                        </div>
                        <div>
                            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Verrats Reproducteurs</label>
                            <input wire:model="numbering.verrat_prefix" type="text" maxlength="4" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm font-mono font-bold">
                        </div>
                        <div>
                            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Portées de Porcelets</label>
                            <input wire:model="numbering.portee_prefix" type="text" maxlength="4" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm font-mono font-bold">
                        </div>
                    </div>
                </div>

                <div class="border-t border-outline-variant pt-md">
                    <p class="text-xs font-bold text-brand-emerald uppercase tracking-wider mb-sm flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">egg</span>Aviculture (Volailles &amp; Pondeuses)</p>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-md">
                        <div>
                            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Préfixe Lots Volailles / Pondeuses</label>
                            <input wire:model="numbering.volaille_prefix" type="text" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm font-mono font-bold">
                        </div>
                        <div>
                            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Préfixe Bâtiments / Parcs Volailles</label>
                            <input wire:model="numbering.parc_prefix" type="text" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm font-mono font-bold">
                        </div>
                    </div>
                </div>

                <div class="border-t border-outline-variant pt-md">
                    <p class="text-xs font-bold text-brand-emerald uppercase tracking-wider mb-sm flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">bug_report</span>Héliciculture (Escargots)</p>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Préfixe Parcs / Fosses Escargots</label>
                        <input wire:model="numbering.escargot_prefix" type="text" class="w-full sm:w-64 h-11 px-md border border-outline-variant rounded-lg text-sm font-mono font-bold">
                    </div>
                </div>

                <div class="border-t border-outline-variant pt-md">
                    <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white text-xs font-bold transition-all shadow-sm flex items-center gap-xs">
                        <span class="material-symbols-outlined text-[18px]">save</span>Enregistrer Tous les Formats de Numérotation
                    </button>
                </div>
            </form>
        @endif
    </x-tab-page>
</div>
