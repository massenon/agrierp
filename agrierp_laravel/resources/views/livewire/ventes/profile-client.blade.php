<div>
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface">Profil Client</h2>
        <p class="text-xs text-outline mt-xs">Fiche complète, historique et créances du tiers.</p>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-[35%_65%] gap-md items-start">
        <div class="bg-white border border-outline-variant rounded-lg p-lg text-center space-y-md">
            <div class="w-16 h-16 rounded-full bg-brand-emerald text-white flex items-center justify-center text-xl font-extrabold mx-auto">
                {{ strtoupper(collect(explode(' ', $customer->name))->map(fn($p) => mb_substr($p, 0, 1))->take(2)->implode('')) }}
            </div>
            <div>
                <p class="font-bold text-brand-forest">{{ $customer->name }}</p>
                <p class="text-xs text-outline">{{ $customer->phone ?? '—' }}</p>
            </div>
            <div class="bg-surface-zebra rounded-lg p-md">
                <p class="text-[10px] text-outline font-bold uppercase">Solde Global Dû</p>
                <p class="text-xl font-extrabold text-error-deep">{{ number_format($this->soldeGlobal, 0, ',', ' ') }} FCFA</p>
            </div>

            @if($customer->credit_limit > 0)
                @php
                    $usedPct = min(100, round(($this->soldeGlobal / $customer->credit_limit) * 100));
                @endphp
                <div class="bg-white border border-outline-variant rounded-lg p-md text-left">
                    <p class="text-[10px] text-outline font-bold uppercase mb-xs">Limite de Crédit</p>
                    <div class="w-full h-2 bg-surface-zebra rounded-full overflow-hidden mb-xs"><div class="h-full rounded-full" style="width:{{ $usedPct }}%; background:#065f46;"></div></div>
                    <p class="text-[10px] text-outline">{{ number_format($this->soldeGlobal, 0, ',', ' ') }} FCFA utilisés sur {{ number_format($customer->credit_limit, 0, ',', ' ') }} FCFA autorisés ({{ $usedPct }}%)</p>
                </div>
            @endif

            <div class="space-y-xs">
                <a href="{{ route('ventes.creances-hub') }}?tab=liste" class="block w-full py-sm rounded-lg border border-outline-variant text-xs font-bold text-brand-forest hover:bg-surface-zebra">Modifier la fiche</a>
                <button type="button" wire:click="openGlobalRegularisation" class="w-full py-sm rounded-lg bg-brand-emerald text-white text-xs font-bold hover:bg-brand-forest">Enregistrer un règlement</button>
                <button type="button" wire:click="sendQuickReminder" class="w-full py-sm rounded-lg border border-brand-emerald text-brand-emerald text-xs font-bold hover:bg-brand-emerald/5">Envoyer une relance rapide</button>
            </div>
        </div>

        <div class="bg-white border border-outline-variant rounded-lg p-md">
            <div class="flex items-center gap-xs border-b border-outline-variant mb-md overflow-x-auto">
                <button type="button" wire:click="$set('tab', 'ventes')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap {{ $tab === 'ventes' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}">Ventes</button>
                <button type="button" wire:click="$set('tab', 'creances')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap {{ $tab === 'creances' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}">Créances</button>
                <button type="button" wire:click="$set('tab', 'avances')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap {{ $tab === 'avances' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}">Avances &amp; Acomptes</button>
                <button type="button" wire:click="$set('tab', 'relances')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap {{ $tab === 'relances' ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}">Relances</button>
            </div>

            @if($tab === 'ventes')
                <table class="w-full text-xs">
                    <thead><tr class="text-outline border-b border-outline-variant"><th class="text-left py-xs">Facture</th><th class="text-left py-xs">Date</th><th class="text-left py-xs">Articles</th><th class="text-right py-xs">Montant</th><th class="text-left py-xs">Statut</th></tr></thead>
                    <tbody>
                        @forelse($this->sales as $i => $sale)
                            <tr class="border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : '' }}">
                                <td class="py-xs font-mono">{{ strtoupper(substr($sale->id, 0, 8)) }}</td>
                                <td class="py-xs">{{ $sale->date_effective->format('d/m/Y') }}</td>
                                <td class="py-xs">{{ $sale->lines->map(fn($l) => $l->product?->name)->filter()->implode(', ') }}</td>
                                <td class="py-xs text-right">{{ number_format($sale->total, 0, ',', ' ') }}</td>
                                <td class="py-xs">
                                    @if($sale->payment_mode !== 'credit')
                                        <span class="text-brand-emerald font-bold">Payée</span>
                                    @else
                                        <span class="text-error-deep font-bold">Crédit</span>
                                    @endif
                                </td>
                            </tr>
                        @empty
                            <tr><td colspan="5" class="py-md text-center text-outline">Aucune vente pour ce client.</td></tr>
                        @endforelse
                    </tbody>
                </table>
            @endif

            @if($tab === 'creances')
                <table class="w-full text-xs">
                    <thead><tr class="text-outline border-b border-outline-variant"><th class="text-left py-xs">Facture</th><th class="text-left py-xs">Échéance</th><th class="text-left py-xs">Ancienneté</th><th class="text-right py-xs">Solde Dû</th><th class="text-right py-xs">Actions</th></tr></thead>
                    <tbody>
                        @forelse($this->receivables as $i => $r)
                            <tr class="border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : '' }}">
                                <td class="py-xs font-mono">{{ strtoupper(substr($r->sale_id ?? $r->id, 0, 8)) }}</td>
                                <td class="py-xs">{{ $r->due_date->format('d/m/Y') }}</td>
                                <td class="py-xs text-error-deep font-bold">{{ $r->due_date->diffInDays(now()) }} jours</td>
                                <td class="py-xs text-right font-bold text-error-deep">{{ number_format($r->balance, 0, ',', ' ') }}</td>
                                <td class="py-xs text-right"><button type="button" wire:click="openReceivableRegularisation('{{ $r->id }}')" class="text-brand-emerald text-[11px] font-bold hover:underline">Régler</button></td>
                            </tr>
                        @empty
                            <tr><td colspan="5" class="py-md text-center text-outline">Aucune créance en cours.</td></tr>
                        @endforelse
                    </tbody>
                </table>
            @endif

            @if($tab === 'avances')
                @forelse($this->advances as $advance)
                    <div class="flex justify-between items-center border-b border-outline-variant py-xs text-xs">
                        <span>{{ $advance->advance_date->format('d/m/Y') }} — {{ number_format($advance->amount, 0, ',', ' ') }} FCFA</span>
                        <span class="text-outline">Restant : {{ number_format($advance->remaining, 0, ',', ' ') }} FCFA</span>
                    </div>
                @empty
                    <p class="text-xs text-outline">Aucun acompte en cours pour ce client.</p>
                @endforelse
            @endif

            @if($tab === 'relances')
                <table class="w-full text-xs">
                    <thead><tr class="text-outline border-b border-outline-variant"><th class="text-left py-xs">Canal</th><th class="text-left py-xs">Date</th><th class="text-left py-xs">Message</th></tr></thead>
                    <tbody>
                        @forelse($this->reminders as $reminder)
                            <tr class="border-b border-outline-variant">
                                <td class="py-xs">
                                    @if($reminder->channel === 'whatsapp')
                                        <span class="inline-flex items-center gap-1 text-brand-emerald font-bold"><span class="material-symbols-outlined text-[14px]">chat</span>WhatsApp</span>
                                    @elseif($reminder->channel === 'email')
                                        <span class="inline-flex items-center gap-1 text-info-blue font-bold"><span class="material-symbols-outlined text-[14px]">mail</span>Email</span>
                                    @elseif($reminder->channel === 'appel')
                                        <span class="inline-flex items-center gap-1 text-brand-forest font-bold"><span class="material-symbols-outlined text-[14px]">call</span>Appel</span>
                                    @else
                                        <span class="inline-flex items-center gap-1 text-outline font-bold"><span class="material-symbols-outlined text-[14px]">sms</span>SMS</span>
                                    @endif
                                </td>
                                <td class="py-xs">{{ $reminder->reminder_date->format('d/m/Y') }}</td>
                                <td class="py-xs">{{ $reminder->message }}</td>
                            </tr>
                        @empty
                            <tr><td colspan="3" class="py-md text-center text-outline">Aucune relance envoyée à ce client.</td></tr>
                        @endforelse
                    </tbody>
                </table>
            @endif
        </div>
    </div>

    <x-modal name="modal-regularisation" max-width="sm">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">Enregistrer un Règlement</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-regularisation' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <div class="bg-surface-zebra rounded-lg p-md text-xs mb-md">
            <div class="flex justify-between"><span class="text-outline">Référence</span><span class="font-bold">{{ $regularisationLabel }}</span></div>
            <div class="flex justify-between"><span class="text-outline">Solde restant</span><span class="font-bold text-error-deep">{{ number_format($regularisationSolde, 0, ',', ' ') }} FCFA</span></div>
        </div>
        <div class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Montant du Règlement (FCFA)</label>
                <input wire:model="regularisationMontant" type="number" placeholder="Saisir le montant..." class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('regularisationMontant') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('regularisationMontant') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Compte de Trésorerie</label>
                <select wire:model="regularisationTreasuryId" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('regularisationTreasuryId') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    @foreach($this->treasuryAccounts as $account)
                        <option value="{{ $account->id }}">{{ $account->label }}{{ $account->account_code ? ' ('.$account->account_code.')' : '' }}</option>
                    @endforeach
                </select>
                @error('regularisationTreasuryId') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
        </div>
        <button type="button" wire:click="confirmRegularisation" class="w-full mt-md py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs">Valider le Règlement</button>
    </x-modal>
</div>
