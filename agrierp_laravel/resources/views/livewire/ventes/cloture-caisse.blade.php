<div class="mt-md space-y-md">
    <div class="flex flex-col gap-md border-b border-outline-variant pb-md">
        <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm">
            <div>
                <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                    <span class="material-symbols-outlined text-brand-emerald text-[26px]">point_of_sale</span>Clôture de Caisse
                </h2>
                <p class="text-xs text-outline mt-xs">Rapprochement quotidien entre la caisse physique et les ventes enregistrées.</p>
            </div>
        </div>
    </div>

    {{-- Sélecteur de date --}}
    <div class="bg-white border border-outline-variant rounded-lg p-md flex flex-wrap items-center gap-sm">
        <span class="material-symbols-outlined text-outline text-[18px]">calendar_month</span>
        <label class="text-xs text-on-surface font-medium">Date de clôture :</label>
        <input wire:model.live="closureDate" type="date" class="text-xs border border-outline-variant rounded-lg px-sm py-1.5">
        @if($dejaValidee)
            <span class="inline-flex items-center gap-xs bg-success-green/10 text-success-green border border-success-green/30 text-[10px] font-bold px-sm py-1 rounded-full">
                <span class="material-symbols-outlined text-[14px]">check_circle</span>Clôture déjà validée
            </span>
        @endif
    </div>

    {{-- Résumé des ventes du jour --}}
    <div class="grid grid-cols-1 md:grid-cols-3 gap-md">
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-brand-emerald shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">Ventes Espèces</span><span class="material-symbols-outlined text-[18px] text-brand-emerald">payments</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ number_format($ventesEspeces, 0, ',', ' ') }} <small class="text-xs font-normal">FCFA</small></span>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-info-blue shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">Ventes Mobile Money</span><span class="material-symbols-outlined text-[18px] text-info-blue">smartphone</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ number_format($ventesMobileMoney, 0, ',', ' ') }} <small class="text-xs font-normal">FCFA</small></span>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-accent-yellow shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">Ventes Virement</span><span class="material-symbols-outlined text-[18px] text-brand-forest">account_balance</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ number_format($ventesVirement, 0, ',', ' ') }} <small class="text-xs font-normal">FCFA</small></span>
        </div>
    </div>

    {{-- Formulaire de saisie --}}
    <div class="bg-white border border-outline-variant rounded-lg p-md">
        <h3 class="text-sm font-bold text-on-surface mb-md flex items-center gap-xs">
            <span class="material-symbols-outlined text-[18px] text-brand-emerald">calculate</span>Saisie de la caisse physique
        </h3>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-md">
            <div>
                <label class="block text-xs text-on-surface font-medium mb-xs">Fond de caisse (début de journée) <span class="text-error-red">*</span></label>
                <div class="relative">
                    <input wire:model.live="fondDeCaisse" type="number" min="0" step="1" placeholder="0"
                        class="w-full border border-outline-variant rounded-lg px-sm py-2 text-sm pr-16 @if($dejaValidee) bg-gray-50 opacity-60 @endif"
                        @if($dejaValidee) disabled @endif>
                    <span class="absolute right-sm top-1/2 -translate-y-1/2 text-xs text-outline">FCFA</span>
                </div>
            </div>
            <div>
                <label class="block text-xs text-on-surface font-medium mb-xs">Montant compté (fin de journée) <span class="text-error-red">*</span></label>
                <div class="relative">
                    <input wire:model.live="montantCompte" type="number" min="0" step="1" placeholder="0"
                        class="w-full border border-outline-variant rounded-lg px-sm py-2 text-sm pr-16 @if($dejaValidee) bg-gray-50 opacity-60 @endif"
                        @if($dejaValidee) disabled @endif>
                    <span class="absolute right-sm top-1/2 -translate-y-1/2 text-xs text-outline">FCFA</span>
                </div>
            </div>
        </div>

        {{-- Écart en temps réel --}}
        <div class="mt-md p-md rounded-lg border {{ $this->ecart > 0 ? 'bg-success-green/10 border-success-green/30' : ($this->ecart < 0 ? 'bg-error-red/10 border-error-red/30' : 'bg-gray-50 border-outline-variant') }}">
            <div class="flex items-center justify-between">
                <span class="text-xs font-bold text-on-surface flex items-center gap-xs">
                    <span class="material-symbols-outlined text-[16px]">{{ $this->ecart > 0 ? 'trending_up' : ($this->ecart < 0 ? 'trending_down' : 'remove') }}</span>
                    Écart de caisse
                </span>
                <span class="text-lg font-extrabold {{ $this->ecart > 0 ? 'text-success-green' : ($this->ecart < 0 ? 'text-error-red' : 'text-outline') }}">
                    {{ $this->ecart > 0 ? '+' : '' }}{{ number_format($this->ecart, 0, ',', ' ') }} FCFA
                </span>
            </div>
            @if($this->ecart !== 0.0)
                <p class="text-[10px] text-outline mt-xs">
                    @if($this->ecart > 0)
                        Excédent : écriture D 571 / C 718 (compte SYSCOHADA 718 — Autres subventions).
                    @else
                        Déficit : écriture D 658 / C 571 (compte SYSCOHADA 658 — Charges diverses).
                    @endif
                </p>
            @endif
        </div>

        {{-- Messages --}}
        @if($messageSucces)
            <div class="mt-md flex items-center gap-xs bg-success-green/10 border border-success-green/30 text-success-green rounded-lg px-md py-sm text-xs">
                <span class="material-symbols-outlined text-[16px]">check_circle</span>{{ $messageSucces }}
            </div>
        @endif
        @if($messageErreur)
            <div class="mt-md flex items-center gap-xs bg-error-red/10 border border-error-red/30 text-error-red rounded-lg px-md py-sm text-xs">
                <span class="material-symbols-outlined text-[16px]">error</span>{{ $messageErreur }}
            </div>
        @endif

        {{-- Bouton de validation --}}
        @unless($dejaValidee)
            <div class="mt-md flex justify-end">
                <button wire:click="valider" wire:loading.attr="disabled"
                    class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm disabled:opacity-60">
                    <span class="material-symbols-outlined text-[18px]" wire:loading.class="hidden">check</span>
                    <span wire:loading.remove>Valider la clôture</span>
                    <span wire:loading>Validation…</span>
                </button>
            </div>
        @endunless
    </div>

    {{-- Historique des 10 dernières clôtures (web) --}}
    @if($historique->isNotEmpty())
        <div class="bg-white border border-outline-variant rounded-lg p-md">
            <h3 class="text-sm font-bold text-on-surface mb-md flex items-center gap-xs">
                <span class="material-symbols-outlined text-[18px] text-outline">history</span>Dernières clôtures (web)
            </h3>
            <div class="overflow-x-auto">
                <table class="w-full text-xs">
                    <thead>
                        <tr class="text-[10px] text-outline uppercase border-b border-outline-variant">
                            <th class="text-left py-xs pr-sm">Date</th>
                            <th class="text-right py-xs pr-sm">Espèces</th>
                            <th class="text-right py-xs pr-sm">Mobile</th>
                            <th class="text-right py-xs pr-sm">Virement</th>
                            <th class="text-right py-xs pr-sm">Fond</th>
                            <th class="text-right py-xs pr-sm">Compté</th>
                            <th class="text-right py-xs pr-sm">Écart</th>
                            <th class="text-left py-xs">Statut</th>
                        </tr>
                    </thead>
                    <tbody class="divide-y divide-outline-variant/50">
                        @foreach($historique as $cl)
                            <tr class="hover:bg-gray-50">
                                <td class="py-xs pr-sm">{{ $cl->closure_date->format('d/m/Y') }}</td>
                                <td class="py-xs pr-sm text-right">{{ number_format($cl->ventes_especes, 0, ',', ' ') }}</td>
                                <td class="py-xs pr-sm text-right">{{ number_format($cl->ventes_mobile_money, 0, ',', ' ') }}</td>
                                <td class="py-xs pr-sm text-right">{{ number_format($cl->ventes_virement, 0, ',', ' ') }}</td>
                                <td class="py-xs pr-sm text-right">{{ number_format($cl->fond_de_caisse, 0, ',', ' ') }}</td>
                                <td class="py-xs pr-sm text-right">{{ number_format($cl->montant_compte, 0, ',', ' ') }}</td>
                                <td class="py-xs pr-sm text-right font-bold {{ $cl->ecart > 0 ? 'text-success-green' : ($cl->ecart < 0 ? 'text-error-red' : 'text-outline') }}">
                                    {{ $cl->ecart > 0 ? '+' : '' }}{{ number_format($cl->ecart, 0, ',', ' ') }}
                                </td>
                                <td class="py-xs">
                                    <span class="inline-block px-xs py-0.5 rounded-full text-[10px] font-bold
                                        {{ $cl->statut === 'validée' ? 'bg-success-green/10 text-success-green' : 'bg-gray-100 text-outline' }}">
                                        {{ ucfirst($cl->statut) }}
                                    </span>
                                </td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
        </div>
    @endif
</div>
