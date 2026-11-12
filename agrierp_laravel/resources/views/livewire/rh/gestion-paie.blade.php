<div class="mt-md space-y-md" x-data="{ bulletin: null }">
    <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm border-b border-outline-variant pb-md">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">payments</span>{{ __('rh.titre_gestion_paie') }}
            </h2>
            <p class="text-xs text-outline mt-xs">{{ __('rh.desc_gestion_paie') }}</p>
        </div>
        <div class="flex items-center gap-xs">
            <input wire:model.live="periodMonth" type="month" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <button type="button" wire:click="exportLivrePaiePdf" wire:loading.attr="disabled" wire:target="exportLivrePaiePdf" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full disabled:opacity-50"><span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>{{ __('rh.bouton_exporter_paie') }}</button>
        </div>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md">
        <x-kpi-card :label="__('rh.kpi_masse_salariale')" icon="account_balance_wallet" color="emerald" :value="number_format($this->kpis['masse_salariale'], 0, ',', ' ').' F'" />
        <x-kpi-card :label="__('rh.kpi_bulletins_emis')" icon="description" color="blue" :value="$this->kpis['bulletins_emis']" />
        <x-kpi-card :label="__('rh.kpi_charges_cnss')" icon="shield" color="maize" :value="number_format($this->kpis['charges_cnss'], 0, ',', ' ').' F'" />
        <x-kpi-card :label="__('rh.kpi_en_attente_paiement')" icon="pending" color="red" :value="$this->kpis['en_attente']" />
    </div>

    <div class="bg-info-blue/10 border border-info-blue/30 rounded-lg p-md text-xs text-brand-forest flex items-start gap-xs">
        <span class="material-symbols-outlined text-info-blue text-[18px] flex-shrink-0">info</span>
        <span>{{ __('rh.info_calcul_retenues_intro') }} <strong>{{ __('rh.info_calcul_retenues_formule') }}</strong>{{ __('rh.info_calcul_retenues_suite') }}</span>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('rh.col_employe') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('rh.col_poste') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('rh.col_salaire_brut') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('rh.col_absences') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('rh.col_ret_absences') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('rh.col_ret_cnss') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('rh.col_ret_its') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('rh.col_net_a_payer') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('rh.col_charges_patronales') }}</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">{{ __('rh.col_statut') }}</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">{{ __('rh.col_actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->rows as $i => $row)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="{{ __('rh.col_employe') }}" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $row['employee']->last_name }} {{ $row['employee']->first_name }}</td>
                            <td data-label="{{ __('rh.col_poste') }}" class="px-md py-sm text-xs">{{ $row['employee']->position }}</td>
                            <td data-label="{{ __('rh.col_salaire_brut') }}" class="px-md py-sm text-xs text-right">{{ number_format($row['gross'], 0, ',', ' ') }} FCFA</td>
                            <td data-label="{{ __('rh.col_absences') }}" class="px-md py-sm text-xs text-right {{ ($row['absence_days'] ?? 0) > 0 ? 'text-error-deep font-bold' : 'text-outline' }}">{{ $row['absence_days'] ?? '—' }}</td>
                            <td data-label="{{ __('rh.col_ret_absences') }}" class="px-md py-sm text-xs text-right">{{ number_format($row['absence_deduction'], 0, ',', ' ') }} FCFA</td>
                            <td data-label="{{ __('rh.col_ret_cnss') }}" class="px-md py-sm text-xs text-right">{{ number_format($row['cnss_deduction'], 0, ',', ' ') }} FCFA</td>
                            <td data-label="{{ __('rh.col_ret_its') }}" class="px-md py-sm text-xs text-right">
                                {{ number_format($row['its_deduction'] ?? 0, 0, ',', ' ') }} FCFA
                                @if(($row['bareme_its_renseigne'] ?? true) === false)
                                    <span class="block text-[10px] text-error-deep font-bold">{{ __('rh.msg_bareme_non_renseigne') }}</span>
                                @endif
                            </td>
                            <td data-label="{{ __('rh.col_net_a_payer') }}" class="px-md py-sm text-xs text-right font-bold text-brand-emerald">{{ number_format($row['net'], 0, ',', ' ') }} FCFA</td>
                            <td data-label="{{ __('rh.col_charges_patronales') }}" class="px-md py-sm text-xs text-right text-outline">+{{ number_format($row['charges_patronales'] ?? 0, 0, ',', ' ') }} FCFA</td>
                            <td data-label="{{ __('rh.col_statut') }}" class="px-md py-sm">
                                @if($row['paid'])
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">{{ __('rh.statut_paye') }}</span>
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-accent-yellow/20 text-brand-forest border-accent-yellow">{{ __('rh.statut_en_attente') }}</span>
                                @endif
                            </td>
                            <td data-label="{{ __('rh.col_actions') }}" class="px-md py-sm text-right whitespace-nowrap">
                                <button type="button"
                                    x-on:click="bulletin = {{ Illuminate\Support\Js::from([
                                        'name' => $row['employee']->last_name.' '.$row['employee']->first_name,
                                        'position' => $row['employee']->position,
                                        'gross' => $row['gross'],
                                        'absenceDays' => $row['absence_days'],
                                        'absenceDeduction' => $row['absence_deduction'],
                                        'cnssDeduction' => $row['cnss_deduction'],
                                        'net' => $row['net'],
                                        'period' => $periodMonth,
                                    ]) }}; $dispatch('open-modal', { name: 'modal-bulletin' })"
                                    class="text-info-blue hover:text-blue-800 p-1" title="Voir le bulletin"><span class="material-symbols-outlined text-[18px]">description</span></button>
                                @can('manage-rh')
                                @if(!$row['paid'])
                                    <button type="button" wire:click="validerReglement('{{ $row['employee']->id }}')" class="text-brand-emerald hover:text-brand-forest p-1" title="Valider le règlement"><span class="material-symbols-outlined text-[18px]">payments</span></button>
                                @endif
                                @endcan
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="9" class="px-md py-lg text-center text-outline">{{ __('rh.msg_aucun_employe_actif') }}</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal name="modal-bulletin" max-width="sm">
        <template x-if="bulletin">
            <div>
                <div class="text-center border-b border-outline-variant pb-md mb-md">
                    <h3 class="font-bold text-lg text-brand-forest" x-text="bulletin.name"></h3>
                    <p class="text-xs text-outline" x-text="bulletin.position"></p>
                    <p class="text-[10px] text-outline mt-xs" x-text="'{{ __('rh.bulletin_periode_prefix') }}' + bulletin.period"></p>
                </div>
                <div class="space-y-xs text-xs">
                    <div class="flex justify-between"><span class="text-outline">{{ __('rh.bulletin_salaire_brut') }}</span><span class="font-bold" x-text="bulletin.gross.toLocaleString('fr-FR') + ' FCFA'"></span></div>
                    <div class="flex justify-between" x-show="bulletin.absenceDays !== null"><span class="text-outline">{{ __('rh.bulletin_jours_absence') }}</span><span x-text="bulletin.absenceDays"></span></div>
                    <div class="flex justify-between text-error-deep"><span>{{ __('rh.bulletin_retenue_absences') }}</span><span x-text="'- ' + bulletin.absenceDeduction.toLocaleString('fr-FR') + ' FCFA'"></span></div>
                    <div class="flex justify-between text-error-deep"><span>{{ __('rh.bulletin_retenue_cnss') }}</span><span x-text="'- ' + bulletin.cnssDeduction.toLocaleString('fr-FR') + ' FCFA'"></span></div>
                    <div class="flex justify-between border-t border-outline-variant pt-xs mt-xs font-bold text-brand-emerald text-sm"><span>{{ __('rh.bulletin_net_a_payer') }}</span><span x-text="bulletin.net.toLocaleString('fr-FR') + ' FCFA'"></span></div>
                </div>
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-bulletin' })" class="w-full mt-lg px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">{{ __('rh.bouton_fermer') }}</button>
            </div>
        </template>
    </x-modal>
</div>
