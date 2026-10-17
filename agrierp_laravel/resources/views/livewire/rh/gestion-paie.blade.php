<div class="mt-md space-y-md" x-data="{ bulletin: null }">
    <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm border-b border-outline-variant pb-md">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">payments</span>Gestion de la Paie
            </h2>
            <p class="text-xs text-outline mt-xs">Calcul automatique des retenues croisées avec la Feuille de Pointage.</p>
        </div>
        <div class="flex items-center gap-xs">
            <input wire:model.live="periodMonth" type="month" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <button type="button" wire:click="exportLivrePaiePdf" wire:loading.attr="disabled" wire:target="exportLivrePaiePdf" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full disabled:opacity-50"><span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Exporter</button>
        </div>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md">
        <x-kpi-card label="Masse Salariale" icon="account_balance_wallet" color="emerald" :value="number_format($this->kpis['masse_salariale'], 0, ',', ' ').' F'" />
        <x-kpi-card label="Bulletins Émis" icon="description" color="blue" :value="$this->kpis['bulletins_emis']" />
        <x-kpi-card label="Charges Sociales (CNSS)" icon="shield" color="maize" :value="number_format($this->kpis['charges_cnss'], 0, ',', ' ').' F'" />
        <x-kpi-card label="En Attente de Paiement" icon="pending" color="red" :value="$this->kpis['en_attente']" />
    </div>

    <div class="bg-info-blue/10 border border-info-blue/30 rounded-lg p-md text-xs text-brand-forest flex items-start gap-xs">
        <span class="material-symbols-outlined text-info-blue text-[18px] flex-shrink-0">info</span>
        <span>Les retenues d'absence sont calculées automatiquement : <strong>(Salaire Brut / 26 jours ouvrés) x Jours d'absence non justifiée</strong>, croisées avec les données de la Feuille de Pointage. La retenue CNSS (3.6%) s'applique systématiquement sur le brut.</span>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Employé</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Poste</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Salaire Brut</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Absences</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Ret. Absences</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Ret. CNSS</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Ret. ITS</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Net à Payer</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Charges patronales</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Statut</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->rows as $i => $row)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Employé" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $row['employee']->last_name }} {{ $row['employee']->first_name }}</td>
                            <td data-label="Poste" class="px-md py-sm text-xs">{{ $row['employee']->position }}</td>
                            <td data-label="Salaire Brut" class="px-md py-sm text-xs text-right">{{ number_format($row['gross'], 0, ',', ' ') }} FCFA</td>
                            <td data-label="Absences" class="px-md py-sm text-xs text-right {{ ($row['absence_days'] ?? 0) > 0 ? 'text-error-deep font-bold' : 'text-outline' }}">{{ $row['absence_days'] ?? '—' }}</td>
                            <td data-label="Ret. Absences" class="px-md py-sm text-xs text-right">{{ number_format($row['absence_deduction'], 0, ',', ' ') }} FCFA</td>
                            <td data-label="Ret. CNSS" class="px-md py-sm text-xs text-right">{{ number_format($row['cnss_deduction'], 0, ',', ' ') }} FCFA</td>
                            <td data-label="Ret. ITS" class="px-md py-sm text-xs text-right">
                                {{ number_format($row['its_deduction'] ?? 0, 0, ',', ' ') }} FCFA
                                @if(($row['bareme_its_renseigne'] ?? true) === false)
                                    <span class="block text-[10px] text-error-deep font-bold">Barème non renseigné</span>
                                @endif
                            </td>
                            <td data-label="Net à Payer" class="px-md py-sm text-xs text-right font-bold text-brand-emerald">{{ number_format($row['net'], 0, ',', ' ') }} FCFA</td>
                            <td data-label="Charges patronales" class="px-md py-sm text-xs text-right text-outline">+{{ number_format($row['charges_patronales'] ?? 0, 0, ',', ' ') }} FCFA</td>
                            <td data-label="Statut" class="px-md py-sm">
                                @if($row['paid'])
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">Payé</span>
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-accent-yellow/20 text-brand-forest border-accent-yellow">En attente</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
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
                        <tr><td colspan="9" class="px-md py-lg text-center text-outline">Aucun employé actif pour le moment.</td></tr>
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
                    <p class="text-[10px] text-outline mt-xs" x-text="'Période : ' + bulletin.period"></p>
                </div>
                <div class="space-y-xs text-xs">
                    <div class="flex justify-between"><span class="text-outline">Salaire Brut</span><span class="font-bold" x-text="bulletin.gross.toLocaleString('fr-FR') + ' FCFA'"></span></div>
                    <div class="flex justify-between" x-show="bulletin.absenceDays !== null"><span class="text-outline">Jours d'absence non justifiée</span><span x-text="bulletin.absenceDays"></span></div>
                    <div class="flex justify-between text-error-deep"><span>Retenue Absences</span><span x-text="'- ' + bulletin.absenceDeduction.toLocaleString('fr-FR') + ' FCFA'"></span></div>
                    <div class="flex justify-between text-error-deep"><span>Retenue CNSS (3.6%)</span><span x-text="'- ' + bulletin.cnssDeduction.toLocaleString('fr-FR') + ' FCFA'"></span></div>
                    <div class="flex justify-between border-t border-outline-variant pt-xs mt-xs font-bold text-brand-emerald text-sm"><span>Net à Payer</span><span x-text="bulletin.net.toLocaleString('fr-FR') + ' FCFA'"></span></div>
                </div>
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-bulletin' })" class="w-full mt-lg px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Fermer</button>
            </div>
        </template>
    </x-modal>
</div>
