{{-- RELEVES-1 — champs d'un relevé de terrain, selon `$releveType` (les valeurs parlent du TYPE, jamais d'un état d'ouverture de la modale). --}}
@php
    $champ = 'w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white';
    $etiquette = 'block text-[10px] text-brand-forest font-bold uppercase mb-xs';
    $modes = \App\Services\Elevage\ReleveTerrainService::MODES;
    $modesDelai = \App\Services\Elevage\ReleveTerrainService::MODES_DELAI;
@endphp
<div class="grid grid-cols-1 sm:grid-cols-2 gap-md">
    <div class="sm:col-span-2">
        <label class="{{ $etiquette }}">{{ $releveType === 'incubation_lot' ? 'Code du lot *' : 'Libellé *' }}</label>
        <input wire:model="releveForm.label" type="text" maxlength="150" class="{{ $champ }}">
        @error('releveForm.label') <p class="invalid-feedback">{{ $message }}</p> @enderror
    </div>

    @if($releveType === 'incubation_regle' || $releveType === 'incubation_lot')
        <div>
            <label class="{{ $etiquette }}">Espèce *</label>
            <input wire:model="releveForm.species_code" type="text" maxlength="40" placeholder="ex : pintade" class="{{ $champ }}" @if($releveType === 'incubation_regle' && $releveId) readonly @endif>
            @error('releveForm.species_code') <p class="invalid-feedback">{{ $message }}</p> @enderror
        </div>
    @endif

    @if($releveType === 'incubation_regle')
        <div><label class="{{ $etiquette }}">Durée d'incubation (jours) *</label><input wire:model="releveForm.data.duree_jours" type="text" inputmode="numeric" class="{{ $champ }}">@error('releveForm.data.duree_jours') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
        <div><label class="{{ $etiquette }}">Éclosion possible dès le jour *</label><input wire:model="releveForm.data.eclosion_min" type="text" inputmode="numeric" class="{{ $champ }}">@error('releveForm.data.eclosion_min') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
        <div><label class="{{ $etiquette }}">Éclosion possible jusqu'au jour *</label><input wire:model="releveForm.data.eclosion_max" type="text" inputmode="numeric" class="{{ $champ }}">@error('releveForm.data.eclosion_max') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
        <div>
            <label class="{{ $etiquette }}">Mode par défaut *</label>
            <select wire:model="releveForm.data.mode" class="{{ $champ }}">
                @foreach($modes as $cle => $libelle)<option value="{{ $cle }}">{{ $libelle }}</option>@endforeach
            </select>
            @error('releveForm.data.mode') <p class="invalid-feedback">{{ $message }}</p> @enderror
        </div>
        <div><label class="{{ $etiquette }}">Jours de mirage *</label><input wire:model="releveForm.data.mirages" type="text" placeholder="ex : 7, 14" class="{{ $champ }}">@error('releveForm.data.mirages') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
        <div><label class="{{ $etiquette }}">Jour de transfert à l'éclosoir</label><input wire:model="releveForm.data.transfert_jour" type="text" inputmode="numeric" placeholder="vide = aucun" class="{{ $champ }}">@error('releveForm.data.transfert_jour') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
        <div><label class="{{ $etiquette }}">Conservation maximale des œufs (jours) *</label><input wire:model="releveForm.data.conservation_max_jours" type="text" inputmode="numeric" class="{{ $champ }}">@error('releveForm.data.conservation_max_jours') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
    @endif

    @if($releveType === 'incubation_lot')
        <div><label class="{{ $etiquette }}">Date de mise en incubation *</label><input wire:model="releveForm.data.mise_date" type="date" class="{{ $champ }}">@error('releveForm.data.mise_date') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
        <div>
            <label class="{{ $etiquette }}">Mode *</label>
            <select wire:model="releveForm.data.mode" class="{{ $champ }}">
                @foreach($modes as $cle => $libelle)<option value="{{ $cle }}">{{ $libelle }}</option>@endforeach
            </select>
            @error('releveForm.data.mode') <p class="invalid-feedback">{{ $message }}</p> @enderror
        </div>
        <div><label class="{{ $etiquette }}">Œufs mis</label><input wire:model="releveForm.data.oeufs_mis" type="text" inputmode="numeric" class="{{ $champ }}">@error('releveForm.data.oeufs_mis') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
        <div><label class="{{ $etiquette }}">Œufs fertiles</label><input wire:model="releveForm.data.oeufs_fertiles" type="text" inputmode="numeric" class="{{ $champ }}">@error('releveForm.data.oeufs_fertiles') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
        <div><label class="{{ $etiquette }}">Œufs éclos</label><input wire:model="releveForm.data.oeufs_eclos" type="text" inputmode="numeric" class="{{ $champ }}">@error('releveForm.data.oeufs_eclos') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
        <div><label class="{{ $etiquette }}">Date du premier éclos</label><input wire:model="releveForm.data.premier_eclos_date" type="date" class="{{ $champ }}">@error('releveForm.data.premier_eclos_date') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
        <div><label class="{{ $etiquette }}">Date du dernier éclos</label><input wire:model="releveForm.data.dernier_eclos_date" type="date" class="{{ $champ }}">@error('releveForm.data.dernier_eclos_date') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
    @endif

    @if($releveType === 'delai_regle')
        <div class="sm:col-span-2">
            <label class="{{ $etiquette }}">Seuils *</label>
            <select wire:model="releveForm.data.mode" class="{{ $champ }}">
                @foreach($modesDelai as $cle => $libelle)<option value="{{ $cle }}">{{ $libelle }}</option>@endforeach
            </select>
            @error('releveForm.data.mode') <p class="invalid-feedback">{{ $message }}</p> @enderror
        </div>
        <div><label class="{{ $etiquette }}">Délai critique de départ / saisi (jours) *</label><input wire:model="releveForm.data.critique_jours" type="text" inputmode="numeric" class="{{ $champ }}">@error('releveForm.data.critique_jours') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
        <div><label class="{{ $etiquette }}">Délai d'alerte de départ / saisi (jours) *</label><input wire:model="releveForm.data.alerte_jours" type="text" inputmode="numeric" class="{{ $champ }}">@error('releveForm.data.alerte_jours') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
        <div><label class="{{ $etiquette }}">Marge de sécurité (jours) *</label><input wire:model="releveForm.data.marge_jours" type="text" inputmode="numeric" class="{{ $champ }}">@error('releveForm.data.marge_jours') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
    @endif

    @if($releveType === 'poisson_marque')
        <div class="sm:col-span-2"><label class="{{ $etiquette }}">Marque de granulés</label><input wire:model="releveForm.data.marque" type="text" maxlength="100" class="{{ $champ }}">@error('releveForm.data.marque') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
    @endif

    @if($releveType === 'poisson_bareme')
        <div><label class="{{ $etiquette }}">Poids minimal (g) *</label><input wire:model="releveForm.data.poids_min_g" type="text" inputmode="decimal" class="{{ $champ }}">@error('releveForm.data.poids_min_g') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
        <div><label class="{{ $etiquette }}">Poids maximal (g)</label><input wire:model="releveForm.data.poids_max_g" type="text" inputmode="decimal" placeholder="vide = sans limite" class="{{ $champ }}">@error('releveForm.data.poids_max_g') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
        <div><label class="{{ $etiquette }}">% de biomasse par jour, minimum *</label><input wire:model="releveForm.data.biomasse_min_pct" type="text" inputmode="decimal" class="{{ $champ }}">@error('releveForm.data.biomasse_min_pct') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
        <div><label class="{{ $etiquette }}">% de biomasse par jour, maximum *</label><input wire:model="releveForm.data.biomasse_max_pct" type="text" inputmode="decimal" class="{{ $champ }}">@error('releveForm.data.biomasse_max_pct') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
        <div><label class="{{ $etiquette }}">Taille du granulé</label><input wire:model="releveForm.data.granule" type="text" maxlength="30" placeholder="ex : 2 mm" class="{{ $champ }}">@error('releveForm.data.granule') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
        <div><label class="{{ $etiquette }}">Protéine (%)</label><input wire:model="releveForm.data.proteine_pct" type="text" inputmode="decimal" class="{{ $champ }}">@error('releveForm.data.proteine_pct') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
    @endif

    @if($releveType === 'poisson_temperature')
        <div><label class="{{ $etiquette }}">Température optimale minimale (°C) *</label><input wire:model="releveForm.data.optimale_min" type="text" inputmode="decimal" class="{{ $champ }}">@error('releveForm.data.optimale_min') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
        <div><label class="{{ $etiquette }}">Température optimale maximale (°C) *</label><input wire:model="releveForm.data.optimale_max" type="text" inputmode="decimal" class="{{ $champ }}">@error('releveForm.data.optimale_max') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
        <div class="sm:col-span-2"><label class="{{ $etiquette }}">Réduire la ration sous (°C) *</label><input wire:model="releveForm.data.reduire_sous" type="text" inputmode="decimal" class="{{ $champ }}">@error('releveForm.data.reduire_sous') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
    @endif

    @if($releveType === 'poisson_densite')
        <div><label class="{{ $etiquette }}">Densité d'empoissonnement</label><input wire:model="releveForm.data.densite" type="text" inputmode="decimal" placeholder="à renseigner" class="{{ $champ }}">@error('releveForm.data.densite') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
        <div><label class="{{ $etiquette }}">Unité</label><input wire:model="releveForm.data.unite" type="text" maxlength="30" placeholder="ex : poissons par m³" class="{{ $champ }}">@error('releveForm.data.unite') <p class="invalid-feedback">{{ $message }}</p> @enderror</div>
    @endif
</div>
