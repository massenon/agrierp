<div>
    <x-tab-page
        :tabs="[
            ['key' => 'lapins', 'label' => 'Lapins', 'icon' => 'cruelty_free'],
            ['key' => 'volailles', 'label' => 'Volailles', 'icon' => 'egg'],
            ['key' => 'porcs', 'label' => 'Porcs', 'icon' => 'pets'],
            ['key' => 'escargots', 'label' => 'Escargots', 'icon' => 'bug_report'],
        ]"
        :active="$tab">

        <x-kpi-accordion title="Indicateurs de Reproduction & Éclosion">
            <x-kpi-card label="Reproductrices Gestantes" icon="favorite" color="blue" :value="$this->kpis['gestantes']" />
            <x-kpi-card label="Palpations / Échéances dues" icon="event" color="maize" :value="$this->kpis['palpations_dues']" />
            <x-kpi-card label="Mises bas / Éclosions (mois)" icon="child_care" color="emerald" :value="$this->kpis['mises_bas_mois']" />
            <x-kpi-card label="Alertes Réforme / Pertes" icon="warning" color="red" :value="$this->kpis['echecs']" />
        </x-kpi-accordion>

        @if(in_array($tab, ['lapins', 'porcs']))
            @php
                $isLapins = $tab === 'lapins';
                $offsets = $isLapins ? ['check' => 14, 'misebas' => 30, 'sevrage' => 60] : ['check' => 21, 'misebas' => 114, 'sevrage' => 42];
                $checkLabel = $isLapins ? 'Palpation' : 'Retour Chaleur';
            @endphp
            <div class="space-y-md mt-md">
                <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm">
                    <div>
                        <h2 class="text-lg lg:text-xl font-bold flex items-center gap-xs">
                            <span class="material-symbols-outlined text-brand-emerald">{{ $isLapins ? 'cruelty_free' : 'pets' }}</span>
                            Suivi Reproduction — {{ $isLapins ? 'Cuniculture (Lapins)' : 'Porciculture (Porcs)' }}
                        </h2>
                        <p class="text-xs text-outline mt-xs">Suivi par {{ $isLapins ? 'lapine' : 'truie' }} nommée : saillie, {{ strtolower($checkLabel) }} J+{{ $offsets['check'] }}, mise bas J+{{ $offsets['misebas'] }} et sevrage J+{{ $offsets['sevrage'] }}.</p>
                    </div>
                    <button type="button" wire:click="newDeclaration" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
                        <span class="material-symbols-outlined text-[18px]">add_circle</span>Déclarer une Saillie {{ $isLapins ? 'Lapin' : 'Porc' }}
                    </button>
                </div>

                <x-cycle-reminder :steps="[
                    ['label' => 'Saillie J0'],
                    ['label' => $checkLabel.' J+'.$offsets['check']],
                    ['label' => 'Mise bas J+'.$offsets['misebas'], 'active' => true],
                    ['label' => 'Sevrage J+'.$offsets['sevrage']],
                ]" />

                <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
                    <div class="overflow-x-auto">
                        <table class="w-full rtable text-xs">
                            <thead class="bg-surface-zebra border-b border-outline-variant">
                                <tr>
                                    <th class="px-sm py-sm text-left text-[10px] text-outline font-bold uppercase">Bande</th>
                                    <th class="px-sm py-sm text-left text-[10px] text-outline font-bold uppercase">N° {{ $isLapins ? 'Lapine' : 'Truie' }}</th>
                                    <th class="px-sm py-sm text-left text-[10px] text-outline font-bold uppercase">Date Saillie</th>
                                    <th class="px-sm py-sm text-left text-[10px] text-outline font-bold uppercase">{{ $isLapins ? 'Mâle' : 'Verrat' }} N°</th>
                                    <th class="px-sm py-sm text-left text-[10px] text-outline font-bold uppercase">{{ $checkLabel }}</th>
                                    <th class="px-sm py-sm text-left text-[10px] text-outline font-bold uppercase">Mise Bas Attendue</th>
                                    <th class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase">Nés (Vivants)</th>
                                    <th class="px-sm py-sm text-left text-[10px] text-outline font-bold uppercase">Statut</th>
                                    <th class="px-sm py-sm text-right text-[10px] text-outline font-bold uppercase">Action</th>
                                </tr>
                            </thead>
                            <tbody>
                                @forelse($this->eventsForTab as $i => $event)
                                    @php
                                        $checkDue = $event->saillie_date->copy()->addDays($offsets['check']);
                                        $miseBasAttendue = $event->saillie_date->copy()->addDays($offsets['misebas']);
                                    @endphp
                                    <tr class="rrow border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                                        <td data-label="Bande" class="px-sm py-sm font-bold text-brand-forest">{{ $event->lot?->code }}</td>
                                        <td data-label="N°" class="px-sm py-sm font-mono font-bold text-brand-emerald">{{ $event->mother_ref }}</td>
                                        <td data-label="Saillie" class="px-sm py-sm">{{ $event->saillie_date->format('d/m/Y') }}</td>
                                        <td data-label="Mâle" class="px-sm py-sm font-mono">{{ $event->sire_ref ?? '—' }}</td>
                                        <td data-label="{{ $checkLabel }}" class="px-sm py-sm">
                                            @if($event->palpation_date)
                                                {{ $event->palpation_date->format('d/m/Y') }} ({{ $event->status === 'echec' ? 'Négatif' : 'Positif' }})
                                            @else
                                                <span class="{{ now()->gte($checkDue) ? 'text-error-deep font-bold' : 'text-outline' }}">Prévue {{ $checkDue->format('d/m/Y') }}</span>
                                            @endif
                                        </td>
                                        <td data-label="Mise Bas" class="px-sm py-sm font-bold">{{ $event->mise_bas_date_actual?->format('d/m/Y') ?? $miseBasAttendue->format('d/m/Y') }}</td>
                                        <td data-label="Nés" class="px-sm py-sm text-right">{{ $event->nes_vivants !== null ? $event->nes_vivants.' ('.$event->nes_morts.' morts)' : '—' }}</td>
                                        <td data-label="Statut" class="px-sm py-sm">
                                            @if($event->status === 'echec')
                                                <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[10px] font-bold border bg-error-bg text-error-deep border-error-deep/30">Réforme / Échec</span>
                                            @elseif($event->status === 'termine')
                                                <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[10px] font-bold border bg-surface-zebra text-outline border-outline-variant">Cycle Clôturé</span>
                                            @elseif($event->mise_bas_date_actual)
                                                <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[10px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">Mère Allaitante</span>
                                            @else
                                                <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[10px] font-bold border bg-info-blue/10 text-info-blue border-info-blue/30">Gestante</span>
                                            @endif
                                        </td>
                                        <td data-label="Action" class="px-sm py-sm text-right whitespace-nowrap">
                                            @if(!$event->palpation_date)
                                                <button type="button" wire:click="recordPalpation('{{ $event->id }}', true)" class="text-[10px] font-bold bg-brand-emerald text-white px-2 py-1 rounded-full shadow-sm mr-1">{{ $checkLabel }} +</button>
                                                <button type="button" wire:click="recordPalpation('{{ $event->id }}', false)" class="text-[10px] font-bold bg-error-red text-white px-2 py-1 rounded-full shadow-sm">{{ $checkLabel }} −</button>
                                            @elseif($event->status !== 'echec' && !$event->mise_bas_date_actual)
                                                <button type="button" wire:click="openMiseBasModal('{{ $event->id }}')" class="text-[10px] font-bold bg-brand-emerald text-white px-2 py-1 rounded-full shadow-sm">Saisir Mise Bas</button>
                                            @elseif($event->mise_bas_date_actual && $event->status !== 'termine')
                                                <button type="button" wire:click="closeCycle('{{ $event->id }}')" class="text-[10px] font-bold bg-brand-forest text-white px-2 py-1 rounded-full shadow-sm">Clôturer (Sevrage)</button>
                                            @endif
                                        </td>
                                    </tr>
                                @empty
                                    <tr><td colspan="9" class="px-sm py-lg text-center text-outline">Aucune saillie déclarée pour le moment.</td></tr>
                                @endforelse
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>

            <x-modal name="modal-saillie" max-width="sm">
                <div class="flex items-center justify-between mb-md">
                    <h3 class="font-bold text-lg text-brand-forest">Déclarer une Saillie ({{ $isLapins ? 'Cuniculture' : 'Porciculture' }})</h3>
                    <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-saillie' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
                </div>
                <form wire:submit="saveDeclaration" class="space-y-md">
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Bande *</label>
                        <select wire:model="lotId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('lotId') ? 'is-invalid' : 'border-outline-variant' }}">
                            <option value="">-- Sélectionner --</option>
                            @foreach($this->lotsForTab as $lot)
                                <option value="{{ $lot->id }}">{{ $lot->code }}</option>
                            @endforeach
                        </select>
                        @error('lotId') <p class="invalid-feedback">{{ $message }}</p> @enderror
                    </div>
                    <div class="grid grid-cols-2 gap-sm">
                        <div>
                            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">N° {{ $isLapins ? 'Lapine' : 'Truie' }} *</label>
                            <input wire:model="motherRef" type="text" placeholder="{{ $isLapins ? 'ex : R8' : 'ex : T3' }}" class="w-full h-11 px-md border rounded-lg text-sm font-mono font-bold text-brand-emerald {{ $errors->has('motherRef') ? 'is-invalid' : 'border-outline-variant' }}">
                            @error('motherRef') <p class="invalid-feedback">{{ $message }}</p> @enderror
                        </div>
                        <div>
                            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ $isLapins ? 'Mâle Saillisseur' : 'Verrat' }} N°</label>
                            <input wire:model="sireRef" type="text" placeholder="{{ $isLapins ? 'ex : M2' : 'ex : V1' }}" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm font-mono">
                        </div>
                    </div>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date de Saillie *</label>
                        <input wire:model="saillieDate" type="date" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    </div>
                    <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                        <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-saillie' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                        <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer la Saillie</button>
                    </div>
                </form>
            </x-modal>

            <x-modal name="modal-misebas" max-width="sm">
                <div class="flex items-center justify-between mb-md">
                    <h3 class="font-bold text-lg text-brand-forest">Saisir la Mise Bas</h3>
                    <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-misebas' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
                </div>
                <form wire:submit="saveMiseBas" class="space-y-md">
                    <div class="grid grid-cols-2 gap-sm">
                        <div>
                            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Nés Vivants *</label>
                            <input wire:model="nesVivants" type="number" min="0" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm font-bold">
                        </div>
                        <div>
                            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Nés Morts</label>
                            <input wire:model="nesMorts" type="number" min="0" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                        </div>
                    </div>
                    <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                        <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-misebas' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                        <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
                    </div>
                </form>
            </x-modal>
        @endif

        @if(in_array($tab, ['volailles', 'escargots']))
            <div class="mt-md space-y-md">
                <div>
                    <h2 class="text-lg lg:text-xl font-bold flex items-center gap-xs">
                        <span class="material-symbols-outlined text-brand-emerald">{{ $tab === 'volailles' ? 'egg' : 'bug_report' }}</span>
                        Suivi Reproduction {{ $tab === 'volailles' ? 'Volailles' : 'Escargots' }} — Couvoir &amp; Éclosion
                    </h2>
                    <p class="text-xs text-outline mt-xs">La saisie quotidienne du couvoir se fait depuis la fiche journalière dédiée — résumé réel du mois affiché ci-dessous, un seul point de vérité pour cette donnée.</p>
                </div>
                <div class="grid grid-cols-3 gap-md">
                    <x-kpi-card label="Œufs Couvés (mois)" icon="egg" color="blue" :value="$this->incubationSummary['couves'] ?? 0" />
                    <x-kpi-card label="Naissains Nés (mois)" icon="child_care" color="emerald" :value="$this->incubationSummary['nes'] ?? 0" />
                    <x-kpi-card label="Taux d'Éclosion" icon="egg_alt" color="maize" :value="number_format($this->incubationSummary['taux_eclosion'] ?? 0, 1, ',', ' ').' %'" />
                </div>
                <a href="{{ $tab === 'volailles' ? route('elevage.fiche-reproducteurs') : route('elevage.fiche-escargots') }}" class="inline-flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
                    <span class="material-symbols-outlined text-[18px]">edit_note</span>Saisir le Couvoir du Jour →
                </a>
            </div>
        @endif
    </x-tab-page>
</div>
