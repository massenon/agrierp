<div class="mt-md space-y-md">
    <div class="border-b border-outline-variant pb-md flex flex-col sm:flex-row sm:items-center sm:justify-between gap-sm">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">campaign</span>{{ __('ventes.titre_relances_recouvrement') }}
            </h2>
            <p class="text-xs text-outline mt-xs">{{ __('ventes.desc_relances') }}</p>
        </div>
        <a wire:navigate href="{{ route('parametres.hub', ['tab' => 'email']) }}" class="flex items-center gap-xs text-xs font-bold text-brand-forest hover:text-brand-emerald">
            <span class="material-symbols-outlined text-[16px]">mail</span>{{ __('ventes.btn_configurer_email') }}
        </a>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md">
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-error-red shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">{{ __('ventes.kpi_creances_echues') }}</span><span class="material-symbols-outlined text-[18px] text-error-red">event_busy</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ number_format($this->kpis['creances_echues'], 0, ',', ' ') }} <small class="text-xs font-normal">FCFA</small></span>
            <p class="text-[10px] text-outline mt-xs">Échéance dépassée</p>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-info-blue shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">{{ __('ventes.kpi_relances_effectuees') }}</span><span class="material-symbols-outlined text-[18px] text-info-blue">campaign</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ $this->kpis['relances_effectuees'] }} <small class="text-xs font-normal">env.</small></span>
            <p class="text-[10px] text-outline mt-xs">Ce mois-ci, par email</p>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-brand-emerald shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">{{ __('ventes.kpi_taux_reponse') }}</span><span class="material-symbols-outlined text-[18px] text-brand-emerald">check_circle</span></div>
            @if($this->kpis['taux_reponse'] === null)
                <span class="text-lg md:text-2xl font-extrabold text-outline block mt-xs">—</span>
                <p class="text-[10px] text-outline mt-xs">{{ __('ventes.info_taux_reponse_vide') }}</p>
            @else
                <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ $this->kpis['taux_reponse'] }}%</span>
                <p class="text-[10px] text-outline mt-xs">{{ __('ventes.info_creances_relancees') }}</p>
            @endif
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-brand-forest shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">{{ __('ventes.kpi_montant_recouvre') }}</span><span class="material-symbols-outlined text-[18px] text-brand-forest">trending_up</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ number_format($this->kpis['montant_recouvre'], 0, ',', ' ') }} <small class="text-xs font-normal">FCFA</small></span>
            <p class="text-[10px] text-outline mt-xs">Sur créances relancées</p>
        </div>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-[65%_35%] gap-md">
        <div class="bg-white border border-outline-variant rounded-lg p-md">
            <p class="text-xs font-bold text-brand-forest uppercase mb-sm">{{ __('ventes.titre_file_relance') }}</p>
            <div class="space-y-sm">
                @forelse($this->queue as $receivable)
                    @php
                        $initials = collect(explode(' ', $receivable->customer?->name ?? '??'))->map(fn($w) => mb_substr($w, 0, 1))->take(2)->implode('');
                    @endphp
                    <div class="bg-white border border-outline-variant rounded-lg p-md flex flex-col sm:flex-row sm:items-center gap-sm">
                        <div class="w-10 h-10 rounded-full bg-brand-emerald text-white flex items-center justify-center font-bold text-sm flex-shrink-0">{{ strtoupper($initials) }}</div>
                        <div class="flex-1 min-w-0">
                            <a wire:navigate href="{{ route('ventes.profile-client', $receivable->customer) }}" class="text-brand-forest font-bold text-sm hover:underline hover:text-brand-emerald">{{ $receivable->customer?->name }}</a>
                            <p class="text-xs"><span class="text-error-deep font-bold">{{ number_format($receivable->balance, 0, ',', ' ') }} FCFA</span> <span class="text-outline">— {{ $receivable->days_overdue }} jours de retard</span></p>
                        </div>
                        <div class="flex items-center gap-xs flex-shrink-0 flex-wrap">
                            @can('manage-ventes')
                            <button type="button" wire:click="sendWhatsappReminder('{{ $receivable->id }}')" wire:loading.attr="disabled" class="flex items-center gap-1 bg-brand-emerald hover:bg-brand-forest text-white text-[11px] font-bold px-sm py-1.5 rounded-full disabled:opacity-50"><span class="material-symbols-outlined text-[14px]">chat</span>{{ __('ventes.btn_relancer_whatsapp') }}</button>
                            <button type="button" wire:click="sendMailReminder('{{ $receivable->id }}')" wire:loading.attr="disabled" class="flex items-center gap-1 bg-info-blue hover:bg-blue-800 text-white text-[11px] font-bold px-sm py-1.5 rounded-full disabled:opacity-50"><span class="material-symbols-outlined text-[14px]">mail</span>{{ __('ventes.btn_relancer_mail') }}</button>
                            @endcan
                            <button type="button" wire:click="exportCourrierPdf('{{ $receivable->id }}')" wire:loading.attr="disabled" class="flex items-center gap-1 border border-outline-variant hover:bg-surface-zebra text-brand-forest text-[11px] font-bold px-sm py-1.5 rounded-full disabled:opacity-50"><span class="material-symbols-outlined text-[14px]">picture_as_pdf</span>{{ __('ventes.btn_exporter_courrier') }}</button>
                            @can('manage-ventes')
                            @if($receivable->customer?->phone)
                                <a href="tel:{{ preg_replace('/[^0-9+]/', '', $receivable->customer->phone) }}" wire:click="callReminder('{{ $receivable->id }}')" class="flex items-center gap-1 border border-outline-variant hover:bg-surface-zebra text-brand-forest text-[11px] font-bold px-sm py-1.5 rounded-full"><span class="material-symbols-outlined text-[14px]">call</span>{{ __('ventes.btn_appeler') }}</a>
                            @else
                                <button type="button" wire:click="callReminder('{{ $receivable->id }}')" class="flex items-center gap-1 border border-outline-variant hover:bg-surface-zebra text-brand-forest text-[11px] font-bold px-sm py-1.5 rounded-full"><span class="material-symbols-outlined text-[14px]">call</span>{{ __('ventes.btn_appeler') }}</button>
                            @endif
                            @endcan
                        </div>
                    </div>
                @empty
                    <p class="text-xs text-outline text-center py-lg">{{ __('ventes.msg_aucune_creance_echue') }}</p>
                @endforelse
            </div>
        </div>
        <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_niveau_relance') }}</label>
                <select wire:model.live="templateLevel" wire:change="loadTemplate" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                    <option value="1">{{ __('ventes.relance_niveau_1') }}</option>
                    <option value="2">{{ __('ventes.relance_niveau_2') }}</option>
                    <option value="3">{{ __('ventes.relance_niveau_3') }}</option>
                </select>
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">{{ __('ventes.label_modele_message') }}</label>
                <textarea wire:model="templateText" rows="8" class="w-full px-md py-sm border border-outline-variant rounded-lg text-xs"></textarea>
                <div class="flex flex-wrap gap-xs mt-xs">
                    <button type="button" wire:click="insertTag('[NOM]')" class="text-[10px] font-bold px-sm py-1 rounded-full border border-outline-variant text-outline hover:bg-surface-zebra">[NOM]</button>
                    <button type="button" wire:click="insertTag('[FACTURE]')" class="text-[10px] font-bold px-sm py-1 rounded-full border border-outline-variant text-outline hover:bg-surface-zebra">[FACTURE]</button>
                    <button type="button" wire:click="insertTag('[MONTANT_DU]')" class="text-[10px] font-bold px-sm py-1 rounded-full border border-outline-variant text-outline hover:bg-surface-zebra">[MONTANT_DU]</button>
                    <button type="button" wire:click="insertTag('[DATE_ECHEANCE]')" class="text-[10px] font-bold px-sm py-1 rounded-full border border-outline-variant text-outline hover:bg-surface-zebra">[DATE_ECHEANCE]</button>
                </div>
                <p class="text-[10px] text-outline mt-xs">Ce modèle s'applique à l'envoi en cours — la sauvegarde durable des modèles arrive avec Paramètres (aucune table dédiée pour l'instant).</p>
            </div>
        </div>
    </div>
</div>
