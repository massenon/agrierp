<div class="mt-md space-y-md">
    <div class="border-b border-outline-variant pb-md flex flex-col sm:flex-row sm:items-center sm:justify-between gap-sm">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">campaign</span>Relances &amp; Recouvrement
            </h2>
            <p class="text-xs text-outline mt-xs">Moteur de relance des créances clients échues.</p>
        </div>
        <a href="{{ route('parametres.integrations') }}" class="flex items-center gap-xs text-xs font-bold text-brand-forest hover:text-brand-emerald">
            <span class="material-symbols-outlined text-[16px]">settings_input_antenna</span>Configurer Email &amp; SMS
        </a>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md">
        <div class="bg-white p-md rounded-lg border border-outline-variant border-l-4 border-l-error-red shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">Créances Échues</span><span class="material-symbols-outlined text-[18px] text-error-red">event_busy</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ number_format($this->kpis['creances_echues'], 0, ',', ' ') }} <small class="text-xs font-normal">FCFA</small></span>
            <p class="text-[10px] text-outline mt-xs">Échéance dépassée</p>
        </div>
        <div class="bg-white p-md rounded-lg border border-outline-variant border-l-4 border-l-info-blue shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">Relances Effectuées</span><span class="material-symbols-outlined text-[18px] text-info-blue">campaign</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ $this->kpis['relances_effectuees'] }} <small class="text-xs font-normal">env.</small></span>
            <p class="text-[10px] text-outline mt-xs">Ce mois-ci, par email</p>
        </div>
        <div class="bg-white p-md rounded-lg border border-outline-variant border-l-4 border-l-brand-emerald shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">Taux de Réponse</span><span class="material-symbols-outlined text-[18px] text-brand-emerald">check_circle</span></div>
            @if($this->kpis['taux_reponse'] === null)
                <span class="text-lg md:text-2xl font-extrabold text-outline block mt-xs">—</span>
                <p class="text-[10px] text-outline mt-xs">Aucune relance envoyée pour le moment</p>
            @else
                <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ $this->kpis['taux_reponse'] }}%</span>
                <p class="text-[10px] text-outline mt-xs">Créances relancées ayant reçu un paiement</p>
            @endif
        </div>
        <div class="bg-white p-md rounded-lg border border-outline-variant border-l-4 border-l-brand-forest shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">Montant Recouvré</span><span class="material-symbols-outlined text-[18px] text-brand-forest">trending_up</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ number_format($this->kpis['montant_recouvre'], 0, ',', ' ') }} <small class="text-xs font-normal">FCFA</small></span>
            <p class="text-[10px] text-outline mt-xs">Sur créances relancées</p>
        </div>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-[65%_35%] gap-md">
        <div class="bg-white border border-outline-variant rounded-lg p-md">
            <p class="text-xs font-bold text-brand-forest uppercase mb-sm">File de Relance Active</p>
            <div class="space-y-sm">
                @forelse($this->queue as $receivable)
                    @php
                        $initials = collect(explode(' ', $receivable->customer?->name ?? '??'))->map(fn($w) => mb_substr($w, 0, 1))->take(2)->implode('');
                    @endphp
                    <div class="bg-white border border-outline-variant rounded-lg p-md flex flex-col sm:flex-row sm:items-center gap-sm">
                        <div class="w-10 h-10 rounded-full bg-brand-emerald text-white flex items-center justify-center font-bold text-sm flex-shrink-0">{{ strtoupper($initials) }}</div>
                        <div class="flex-1 min-w-0">
                            <a href="{{ route('ventes.profile-client', $receivable->customer) }}" class="text-brand-forest font-bold text-sm hover:underline hover:text-brand-emerald">{{ $receivable->customer?->name }}</a>
                            <p class="text-xs"><span class="text-error-deep font-bold">{{ number_format($receivable->balance, 0, ',', ' ') }} FCFA</span> <span class="text-outline">— {{ $receivable->days_overdue }} jours de retard</span></p>
                        </div>
                        <div class="flex items-center gap-xs flex-shrink-0 flex-wrap">
                            <button type="button" wire:click="sendWhatsappReminder('{{ $receivable->id }}')" wire:loading.attr="disabled" class="flex items-center gap-1 bg-brand-emerald hover:bg-brand-forest text-white text-[11px] font-bold px-sm py-1.5 rounded-full disabled:opacity-50"><span class="material-symbols-outlined text-[14px]">chat</span>Relancer WhatsApp</button>
                            <button type="button" wire:click="sendMailReminder('{{ $receivable->id }}')" wire:loading.attr="disabled" class="flex items-center gap-1 bg-info-blue hover:bg-blue-800 text-white text-[11px] font-bold px-sm py-1.5 rounded-full disabled:opacity-50"><span class="material-symbols-outlined text-[14px]">mail</span>Relancer par Mail</button>
                            <button type="button" wire:click="exportCourrierPdf('{{ $receivable->id }}')" wire:loading.attr="disabled" class="flex items-center gap-1 border border-outline-variant hover:bg-surface-zebra text-brand-forest text-[11px] font-bold px-sm py-1.5 rounded-full disabled:opacity-50"><span class="material-symbols-outlined text-[14px]">picture_as_pdf</span>Exporter Courrier</button>
                            <button type="button" wire:click="sendSmsReminder('{{ $receivable->id }}')" wire:loading.attr="disabled" class="flex items-center gap-1 border border-outline-variant hover:bg-surface-zebra text-brand-forest text-[11px] font-bold px-sm py-1.5 rounded-full disabled:opacity-50"><span class="material-symbols-outlined text-[14px]">sms</span>Relancer par SMS</button>
                        </div>
                    </div>
                @empty
                    <p class="text-xs text-outline text-center py-lg">Aucune créance échue pour le moment.</p>
                @endforelse
            </div>
        </div>
        <div class="bg-white border border-outline-variant rounded-lg p-md space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Niveau de Relance</label>
                <select wire:model.live="templateLevel" wire:change="loadTemplate" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                    <option value="1">Niveau 1 : Rappel amiable (J+7)</option>
                    <option value="2">Niveau 2 : Rappel ferme (30 jours)</option>
                    <option value="3">Niveau 3 : Mise en demeure</option>
                </select>
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Modèle de Message</label>
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
