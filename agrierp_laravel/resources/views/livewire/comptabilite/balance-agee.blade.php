<div>
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">schedule</span>Balance Âgée
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">
                Encours par ancienneté de retard — qui relancer, et dans quel ordre.
            </p>
        </div>
    </div>

    <div class="bg-info-blue/10 border border-info-blue/20 rounded-lg p-sm text-[11px] text-brand-forest mb-lg">
        <span class="material-symbols-outlined text-[14px] align-middle mr-xs">info</span>
        Écran ajouté hors maquette, à la demande. L'âge se compte depuis
        l'<strong>échéance</strong> — pas depuis l'émission — et seul le
        <strong>reste dû</strong> est ventilé.
    </div>

    <div class="bg-white border border-outline-variant rounded-lg p-md mb-lg flex flex-wrap items-center gap-md">
        <div class="flex items-center gap-sm">
            <label for="ba-volet" class="text-[10px] text-brand-forest font-bold uppercase">Volet :</label>
            <select id="ba-volet" wire:model.live="volet"
                class="text-sm font-bold border border-outline-variant rounded-lg px-md py-2 bg-white focus:ring-2 focus:ring-brand-emerald outline-none">
                <option value="creances">Créances clients</option>
                <option value="dettes">Dettes fournisseurs</option>
            </select>
        </div>
        <div class="flex items-center gap-sm">
            <label for="ba-arrete" class="text-[10px] text-brand-forest font-bold uppercase">Arrêté au :</label>
            <input id="ba-arrete" type="date" wire:model.live="arrete"
                class="text-sm font-bold border border-outline-variant rounded-lg px-md py-2 bg-white focus:ring-2 focus:ring-brand-emerald outline-none">
        </div>
    </div>

    <div class="grid grid-cols-2 md:grid-cols-5 gap-md mb-lg">
        @foreach($this->tranches as $tranche)
            <div class="kpi-card bg-white rounded-lg border border-outline-variant {{ $tranche === 'Non échu' ? 'border-l-brand-emerald' : ($tranche === 'Plus de 90 jours' ? 'border-l-error-red' : 'border-l-accent-yellow') }} shadow-sm">
                <span class="text-[10px] text-outline font-bold uppercase block">{{ $tranche }}</span>
                <span class="text-base md:text-xl font-extrabold block mt-xs">
                    {{ number_format($this->donnees['totaux'][$tranche], 0, ',', ' ') }} F
                </span>
            </div>
        @endforeach
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">
                            {{ $volet === 'dettes' ? 'Fournisseur' : 'Client' }}
                        </th>
                        @foreach($this->tranches as $tranche)
                            <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ $tranche }}</th>
                        @endforeach
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Total</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->donnees['tiers'] as $i => $tiers)
                        <tr class="rrow border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="{{ $volet === 'dettes' ? 'Fournisseur' : 'Client' }}"
                                class="px-md py-sm text-xs font-bold text-brand-forest">{{ $tiers['nom'] }}</td>
                            @foreach($this->tranches as $tranche)
                                <td data-label="{{ $tranche }}" class="px-md py-sm text-xs text-right">
                                    {{ $tiers['tranches'][$tranche] > 0 ? number_format($tiers['tranches'][$tranche], 0, ',', ' ') : '—' }}
                                </td>
                            @endforeach
                            <td data-label="Total" class="px-md py-sm text-xs text-right font-bold text-brand-forest">
                                {{ number_format($tiers['total'], 0, ',', ' ') }}
                            </td>
                        </tr>
                    @empty
                        <tr>
                            <td colspan="{{ count($this->tranches) + 2 }}" class="px-md py-lg text-center text-outline text-xs">
                                Aucun encours à cette date — tout est soldé.
                            </td>
                        </tr>
                    @endforelse
                </tbody>
                @if(count($this->donnees['tiers']) > 0)
                    <tfoot class="bg-brand-emerald/10 border-t-2 border-brand-emerald">
                        <tr>
                            <td class="px-md py-sm text-xs font-black text-brand-forest uppercase">Total général</td>
                            @foreach($this->tranches as $tranche)
                                <td class="px-md py-sm text-xs text-right font-bold">
                                    {{ number_format($this->donnees['totaux'][$tranche], 0, ',', ' ') }}
                                </td>
                            @endforeach
                            <td class="px-md py-sm text-xs text-right font-black text-brand-forest">
                                {{ number_format($this->donnees['total'], 0, ',', ' ') }}
                            </td>
                        </tr>
                    </tfoot>
                @endif
            </table>
        </div>
    </div>
</div>
