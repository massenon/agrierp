<div>
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">functions</span>Barème IR-PTS / ITS
        </h2>
        <p class="text-xs text-outline mt-xs">
            Impôt sur les Traitements et Salaires — retenu à la source, progressif, assis sur le net imposable (salaire dû moins CNSS salariale).
        </p>
    </div>

    @if($this->settings->payrollSettingsLocked())
        <div class="rounded-lg p-md mb-lg flex items-start gap-sm {{ $this->editable ? 'bg-accent-yellow/10 border border-accent-yellow/40' : 'bg-error-bg border border-error-deep/30' }}">
            <span class="material-symbols-outlined text-[20px] {{ $this->editable ? 'text-brand-forest' : 'text-error-deep' }}">
                {{ $this->editable ? 'lock_open' : 'lock' }}
            </span>
            <div>
                <p class="text-xs font-bold {{ $this->editable ? 'text-brand-forest' : 'text-error-deep' }}">
                    Barème arrêté le {{ $this->settings->payroll_settings_edited_at?->format('d/m/Y à H:i') }}
                    @if($this->settings->payrollSettingsEditor)
                        par {{ $this->settings->payrollSettingsEditor->name }}
                    @endif
                </p>
                <p class="text-[11px] text-outline mt-xs">
                    @if($this->editable)
                        Vous pouvez le modifier en tant qu'administrateur. Les bulletins <strong>déjà réglés ne sont jamais recalculés</strong> : leur écriture comptable est passée et le salarié a été payé. Une correction rétroactive passe par le Journal Comptable.
                    @else
                        Seul un <strong>administrateur</strong> peut désormais le modifier. Un barème fiscal détermine le net versé à chaque salarié et les montants déclarés aux organismes : une fois arrêté, il ne se modifie plus au fil de l'eau.
                    @endif
                </p>
            </div>
        </div>
    @else
        <div class="bg-brand-emerald/5 border border-brand-emerald/20 rounded-lg p-md mb-lg flex items-start gap-sm">
            <span class="material-symbols-outlined text-brand-emerald text-[20px]">edit_note</span>
            <div>
                <p class="text-xs font-bold text-brand-forest">Première configuration — à valider avant toute paie réelle</p>
                <p class="text-[11px] text-outline mt-xs">
                    Le barème ci-dessous est une valeur de départ : ni le prototype ni le cahier des charges ne le documentent.
                    Faites-le confirmer par le Cabinet FAGUEZ, puis enregistrez.
                    <strong>Après cet enregistrement, seul un administrateur pourra le modifier.</strong>
                </p>
            </div>
        </div>
    @endif

    @error('tranches')
        <div class="bg-error-bg border border-error-deep/30 rounded-lg p-md mb-lg flex items-start gap-sm">
            <span class="material-symbols-outlined text-error-deep text-[20px]">error</span>
            <p class="text-xs text-error-deep font-bold">{{ $message }}</p>
        </div>
    @enderror

    <div class="grid grid-cols-1 lg:grid-cols-3 gap-lg">
        <div class="lg:col-span-2 bg-white border border-outline-variant rounded-lg overflow-hidden">
            <div class="px-md py-sm border-b border-outline-variant bg-surface-zebra flex items-center justify-between">
                <h3 class="text-sm font-bold text-brand-forest">Tranches d'imposition</h3>
                @if($this->editable)
                    <button type="button" wire:click="ajouterTranche" class="flex items-center gap-xs text-xs font-bold text-brand-emerald hover:text-brand-forest">
                        <span class="material-symbols-outlined text-[16px]">add</span>Ajouter une tranche
                    </button>
                @endif
            </div>

            <div class="overflow-x-auto">
                <table class="w-full rtable">
                    <thead class="bg-surface-zebra border-b border-outline-variant">
                        <tr>
                            <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">De (FCFA)</th>
                            <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">À (FCFA)</th>
                            <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Taux (%)</th>
                            @if($this->editable)
                                <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                            @endif
                        </tr>
                    </thead>
                    <tbody>
                        @foreach($tranches as $i => $tranche)
                            <tr class="rrow border-b border-outline-variant {{ $i % 2 === 0 ? 'bg-white' : 'bg-surface-zebra' }}">
                                <td data-label="De" class="px-md py-sm text-xs text-right">
                                    <input type="number" step="1" min="0" wire:model="tranches.{{ $i }}.from" @disabled(! $this->editable)
                                        class="w-full h-9 px-sm border border-outline-variant rounded-lg text-xs text-right disabled:bg-surface-zebra disabled:text-outline">
                                </td>
                                <td data-label="À" class="px-md py-sm text-xs text-right">
                                    <input type="number" step="1" min="0" wire:model="tranches.{{ $i }}.to" @disabled(! $this->editable)
                                        placeholder="sans plafond"
                                        class="w-full h-9 px-sm border border-outline-variant rounded-lg text-xs text-right disabled:bg-surface-zebra disabled:text-outline">
                                </td>
                                <td data-label="Taux" class="px-md py-sm text-xs text-right">
                                    <input type="number" step="0.1" min="0" max="100" wire:model="tranches.{{ $i }}.rate" @disabled(! $this->editable)
                                        class="w-full h-9 px-sm border border-outline-variant rounded-lg text-xs text-right disabled:bg-surface-zebra disabled:text-outline">
                                </td>
                                @if($this->editable)
                                    <td data-label="Actions" class="px-md py-sm text-xs text-right">
                                        <button type="button" wire:click="retirerTranche({{ $i }})" class="text-outline hover:text-error-deep" title="Retirer">
                                            <span class="material-symbols-outlined text-[18px] align-middle">delete</span>
                                        </button>
                                    </td>
                                @endif
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>

            <div class="p-md border-t border-outline-variant">
                <p class="text-[11px] text-outline mb-md">
                    La première tranche part de <strong>0</strong>, chaque tranche reprend exactement où la précédente s'arrête,
                    et la dernière reste <strong>sans plafond</strong>. Un barème troué ou chevauchant produirait un impôt faux sans lever la moindre erreur.
                </p>

                @if($this->editable)
                    <button type="button" wire:click="enregistrer" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full transition-all">
                        <span class="material-symbols-outlined text-[18px]">save</span>Enregistrer le barème
                    </button>
                @endif
            </div>
        </div>

        <div class="bg-white border border-outline-variant rounded-lg p-md h-fit">
            <h3 class="text-sm font-bold text-brand-forest mb-md flex items-center gap-xs">
                <span class="material-symbols-outlined text-[18px]">calculate</span>Simulation
            </h3>

            <label for="brut-simule" class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Salaire brut mensuel (FCFA)</label>
            <input id="brut-simule" type="number" step="1000" min="0" wire:model.live="brutSimule"
                class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm mb-md">

            <dl class="space-y-1 text-xs">
                <div class="flex justify-between"><dt class="text-outline">Salaire dû</dt><dd class="font-bold">{{ number_format($this->simulation['salaire_du'], 0, ',', ' ') }}</dd></div>
                <div class="flex justify-between"><dt class="text-outline">− CNSS salariale</dt><dd class="text-error-deep">{{ number_format($this->simulation['cnss_salariale'], 0, ',', ' ') }}</dd></div>
                <div class="flex justify-between border-t border-outline-variant pt-1"><dt class="text-outline">= Net imposable</dt><dd class="font-bold">{{ number_format($this->simulation['net_imposable'], 0, ',', ' ') }}</dd></div>
                <div class="flex justify-between"><dt class="text-outline">− ITS</dt><dd class="text-error-deep">{{ number_format($this->simulation['its'], 0, ',', ' ') }}</dd></div>
                <div class="flex justify-between border-t-2 border-brand-forest pt-1 mt-1"><dt class="font-bold text-brand-forest">NET À PAYER</dt><dd class="font-extrabold text-brand-emerald">{{ number_format($this->simulation['net'], 0, ',', ' ') }}</dd></div>
            </dl>

            <p class="text-[10px] text-outline mt-md pt-md border-t border-outline-variant">
                Charges patronales en sus : <strong>{{ number_format($this->simulation['total_charges_patronales'], 0, ',', ' ') }} FCFA</strong>
                — elles ne diminuent pas le net du salarié, elles s'ajoutent au coût employeur
                ({{ number_format($this->simulation['cout_employeur'], 0, ',', ' ') }} FCFA au total).
            </p>

            @unless($this->simulation['bareme_its_renseigne'])
                <p class="text-[11px] text-error-deep font-bold mt-md">Aucune tranche enregistrée : l'ITS est nul faute de barème, et non parce que le salaire serait sous le seuil.</p>
            @endunless
        </div>
    </div>
</div>
