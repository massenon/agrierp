<div class="mt-md space-y-md">
    <div class="flex flex-col gap-md border-b border-outline-variant pb-md">
        <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm">
            <div>
                <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                    <span class="material-symbols-outlined text-brand-emerald text-[26px]">receipt_long</span>Historique des Ventes
                </h2>
                <p class="text-xs text-outline mt-xs">Toutes les ventes enregistrées de l'entreprise.</p>
            </div>
            <a href="{{ route('ventes.devis-hub') }}" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
                <span class="material-symbols-outlined text-[18px]">add_circle</span>Nouvelle Vente
            </a>
        </div>
        <div class="flex items-center gap-xs bg-white border border-outline-variant rounded-lg p-sm w-fit">
            <span class="material-symbols-outlined text-outline text-[18px]">calendar_month</span>
            <input wire:model.live="dateFrom" type="date" min="{{ \App\Support\ExerciceChoisi::bornes()[0] }}" max="{{ \App\Support\ExerciceChoisi::bornes()[1] }}" class="text-xs border border-outline-variant rounded-lg px-sm py-1.5">
            <span class="text-outline text-xs">au</span>
            <input wire:model.live="dateTo" type="date" min="{{ \App\Support\ExerciceChoisi::bornes()[0] }}" max="{{ \App\Support\ExerciceChoisi::bornes()[1] }}" class="text-xs border border-outline-variant rounded-lg px-sm py-1.5">
        </div>
    </div>

    <div class="grid grid-cols-2 md:grid-cols-4 gap-md">
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-brand-emerald shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">Chiffre d'Affaires</span><span class="material-symbols-outlined text-[18px] text-brand-emerald">payments</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ number_format($this->kpis['ca'], 0, ',', ' ') }} <small class="text-xs font-normal">FCFA</small></span>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-info-blue shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">Transactions</span><span class="material-symbols-outlined text-[18px] text-info-blue">receipt</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ $this->kpis['transactions'] }}</span>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-accent-yellow shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">Panier Moyen</span><span class="material-symbols-outlined text-[18px] text-brand-forest">shopping_cart</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ number_format($this->kpis['panier_moyen'], 0, ',', ' ') }} <small class="text-xs font-normal">FCFA</small></span>
        </div>
        <div class="kpi-card bg-white rounded-lg border border-outline-variant border-l-error-red shadow-sm">
            <div class="flex justify-between items-start"><span class="text-[10px] text-outline font-bold uppercase">Encours Créances</span><span class="material-symbols-outlined text-[18px] text-error-red">request_quote</span></div>
            <span class="text-lg md:text-2xl font-extrabold text-on-surface block mt-xs">{{ number_format($this->kpis['encours_creances'], 0, ',', ' ') }} <small class="text-xs font-normal">FCFA</small></span>
        </div>
    </div>

    <div class="bg-white border border-outline-variant rounded-lg p-md flex flex-wrap items-center gap-sm">
        <div class="relative flex-1 min-w-[180px]">
            <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
            <input wire:model.live.debounce.300ms="search" type="text" placeholder="Facture, client..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
        </div>
        <select wire:model.live="statusFilter" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <option value="">Statut : Toutes</option>
            <option value="payee">Payée</option>
            <option value="attente">En attente</option>
            <option value="annulee">Annulée</option>
        </select>
        <select wire:model.live="modeFilter" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <option value="">Mode : Tous</option>
            <option value="especes">Espèces</option>
            <option value="mobile_money">Mobile Money</option>
            <option value="virement">Virement</option>
            <option value="credit">Crédit client</option>
            <option value="avance">Avance</option>
        </select>
        <select wire:model.live="customerFilter" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
            <option value="">Client : Tous</option>
            @foreach($this->customers as $customer)
                <option value="{{ $customer->id }}">{{ $customer->name }}</option>
            @endforeach
        </select>
        <button type="button" wire:click="resetFilters" class="flex items-center gap-xs text-xs font-bold text-outline hover:text-brand-forest px-sm py-2"><span class="material-symbols-outlined text-[16px]">restart_alt</span>Réinitialiser</button>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Facture</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Client</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Articles</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Remise</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Total TTC</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Payé</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Reste</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Mode</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Statut</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->sales as $i => $sale)
                        @php
                            $modeLabels = ['especes' => 'Espèces', 'mobile_money' => 'Mobile Money', 'virement' => 'Virement', 'credit' => 'Crédit client', 'avance' => 'Avance'];
                            $reste = $sale->status === 'annulee' ? 0 : ($sale->receivable?->balance ?? 0);
                            $paye = $sale->status === 'annulee' ? 0 : $sale->total - $reste;
                        @endphp
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }} {{ $sale->status === 'annulee' ? 'opacity-50' : '' }}">
                            <td data-label="Facture" class="px-md py-sm text-xs"><button type="button" wire:click="view('{{ $sale->id }}')" class="text-brand-emerald hover:underline font-bold font-mono">{{ strtoupper(substr($sale->id, 0, 8)) }}</button></td>
                            <td data-label="Client" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $sale->customer?->name ?? 'Client Anonyme' }}</td>
                            <td data-label="Date" class="px-md py-sm text-xs">{{ $sale->date_effective->format('d/m/Y H:i') }}</td>
                            <td data-label="Articles" class="px-md py-sm text-xs text-right">{{ $sale->lines->count() }}</td>
                            <td data-label="Remise" class="px-md py-sm text-xs text-right">{{ number_format($sale->discount, 0, ',', ' ') }}</td>
                            <td data-label="Total TTC" class="px-md py-sm text-xs text-right font-bold">{{ number_format($sale->total, 0, ',', ' ') }} FCFA</td>
                            <td data-label="Payé" class="px-md py-sm text-xs text-right text-brand-emerald">{{ number_format($paye, 0, ',', ' ') }}</td>
                            <td data-label="Reste" class="px-md py-sm text-xs text-right {{ $reste > 0 ? 'text-error-deep font-bold' : '' }}">{{ number_format($reste, 0, ',', ' ') }}</td>
                            <td data-label="Mode" class="px-md py-sm text-xs">{{ $modeLabels[$sale->payment_mode] ?? $sale->payment_mode }}</td>
                            <td data-label="Statut" class="px-md py-sm">
                                @if($sale->status === 'annulee')
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-error-bg text-error-deep border-error-deep/30">Annulée</span>
                                @elseif($reste > 0)
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-accent-yellow/20 text-brand-forest border-accent-yellow">En attente</span>
                                @else
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30">Payée</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                <button type="button" wire:click="view('{{ $sale->id }}')" class="text-info-blue hover:text-blue-800 p-1" title="Voir"><span class="material-symbols-outlined text-[18px]">visibility</span></button>
                                @if($sale->status !== 'annulee')
                                    <button @lectureSeule type="button" wire:click="confirmCancel('{{ $sale->id }}')" class="text-error-deep hover:text-red-800 p-1" title="Annuler"><span class="material-symbols-outlined text-[18px]">delete</span></button>
                                @endif
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="11" class="px-md py-lg text-center text-outline">Aucune vente pour le moment.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
        <x-pagination :paginator="$this->sales" />
    </div>

    <x-modal name="modal-cancel-sale" max-width="sm">
        <div class="text-center">
            <div class="w-12 h-12 bg-error-bg rounded-full flex items-center justify-center mx-auto mb-md">
                <span class="material-symbols-outlined text-error-deep text-[28px]">warning</span>
            </div>
            <h3 class="font-bold text-lg text-brand-forest mb-xs">Annuler cette vente ?</h3>
            <p class="text-xs text-outline mb-lg">Le stock des produits vendus sera automatiquement réintégré. Cette action est réversible uniquement en recréant une nouvelle vente.</p>
            <div class="flex justify-center gap-sm">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-cancel-sale' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button @lectureSeule type="button" wire:click="cancelSale" class="px-md py-sm rounded-lg bg-error-deep text-white text-sm font-bold hover:bg-red-800">Oui, Annuler la Vente</button>
            </div>
        </div>
    </x-modal>

    @if($this->viewingSale)
        <div x-data x-on:keydown.escape.window="$wire.closeDrawer()" class="fixed inset-0 bg-black/40 z-[105]" wire:click="closeDrawer"></div>
        <div class="fixed top-0 right-0 h-full w-full sm:w-96 bg-white z-[106] shadow-2xl overflow-y-auto">
            <div class="flex items-center justify-between px-lg py-md border-b border-outline-variant bg-brand-forest">
                <span class="text-white font-bold text-sm font-mono">{{ strtoupper(substr($this->viewingSale->id, 0, 8)) }}</span>
                <button type="button" wire:click="closeDrawer" class="text-white/80 hover:text-white"><span class="material-symbols-outlined">close</span></button>
            </div>
            <div class="p-lg space-y-md">
                <div class="grid grid-cols-2 gap-sm text-xs">
                    <div><span class="text-outline block">Client</span><span class="font-bold">{{ $this->viewingSale->customer?->name ?? 'Client Anonyme' }}</span></div>
                    <div><span class="text-outline block">Date</span><span class="font-bold">{{ $this->viewingSale->date_effective->format('d/m/Y H:i') }}</span></div>
                </div>
                <div class="border-t border-outline-variant pt-md">
                    <p class="text-xs font-bold text-brand-forest uppercase mb-sm">Articles</p>
                    <div class="space-y-xs">
                        @foreach($this->viewingSale->lines as $line)
                            <div class="flex justify-between text-xs border-b border-outline-variant/50 pb-1">
                                <span>{{ $line->product?->name }} × {{ rtrim(rtrim(number_format($line->qty, 2, '.', ''), '0'), '.') }}</span>
                                <span class="font-bold">{{ number_format($line->manual_total_amount, 0, ',', ' ') }} FCFA</span>
                            </div>
                        @endforeach
                    </div>
                </div>
                <div class="border-t border-outline-variant pt-md space-y-1 text-xs">
                    <div class="flex justify-between"><span class="text-outline">Sous-total</span><span>{{ number_format($this->viewingSale->subtotal, 0, ',', ' ') }} FCFA</span></div>
                    <div class="flex justify-between"><span class="text-outline">Remise</span><span>{{ number_format($this->viewingSale->discount, 0, ',', ' ') }} FCFA</span></div>
                    <div class="flex justify-between font-bold text-brand-emerald text-sm"><span>Total</span><span>{{ number_format($this->viewingSale->total, 0, ',', ' ') }} FCFA</span></div>
                </div>
            </div>
            <div class="p-lg border-t border-outline-variant flex justify-center gap-sm">
                <button type="button" wire:click="exportSaleTicketPdf('{{ $this->viewingSale->id }}')" wire:loading.attr="disabled" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest flex items-center gap-xs disabled:opacity-50"><span class="material-symbols-outlined text-[16px]">download</span>Télécharger PDF</button>
                <button type="button" wire:click="closeDrawer" class="px-md py-sm rounded-lg border border-outline-variant text-outline text-sm font-bold hover:bg-surface-zebra">Fermer</button>
            </div>
        </div>
    @endif
</div>
