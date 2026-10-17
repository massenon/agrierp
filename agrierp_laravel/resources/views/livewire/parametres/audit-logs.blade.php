<div class="mt-md space-y-md">
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">security</span>Audit Logs &amp; Sécurité
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">Historique horodaté des actions sensibles effectuées dans AgriERP.</p>
        </div>
        <button type="button" x-on:click="$dispatch('open-modal', { name: 'modal-create-audit-logs' })" class="flex items-center justify-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full transition-all shadow-sm">
            <span class="material-symbols-outlined text-[18px]">file_download</span>Exporter le Journal
        </button>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md">
        <x-kpi-card label="Événements (24h)" icon="history" color="emerald" :value="$this->kpis['evenements_24h']" />
        <x-kpi-card label="Connexions échouées" icon="lock" color="blue" :value="$this->kpis['connexions_echouees']" caption="Sur les dernières 24 h" />
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="p-md border-b border-outline-variant">
            <div class="relative max-w-xs">
                <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
                <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white outline-none">
            </div>
        </div>
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Horodatage</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Utilisateur</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Action</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Module</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->logs as $i => $log)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Horodatage" class="px-md py-sm text-xs">{{ $log->created_at->format('d/m/Y H:i') }}</td>
                            <td data-label="Utilisateur" class="px-md py-sm text-xs">{{ $log->user?->name ?? 'Inconnu' }}</td>
                            <td data-label="Action" class="px-md py-sm text-xs">{{ $log->action_label }}</td>
                            <td data-label="Module" class="px-md py-sm text-xs">{{ $log->module_label ?? '—' }}</td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                <span class="text-outline text-[10px] italic" title="Les journaux d'audit sont immuables : aucune modification ni suppression n'est possible.">Lecture seule</span>
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="5" class="px-md py-lg text-center text-outline">Aucun événement pour le moment.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal name="modal-create-audit-logs" max-width="lg">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">Exporter le Journal</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-audit-logs' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="exportLogs" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Période à exporter *</label>
                <select wire:model="exportPeriod" class="w-full h-11 px-md border rounded-lg bg-white text-sm {{ $errors->has('exportPeriod') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    <option>Aujourd'hui</option>
                    <option>7 derniers jours</option>
                    <option>Ce mois-ci</option>
                </select>
                @error('exportPeriod') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Format d'export *</label>
                <select wire:model="exportFormat" class="w-full h-11 px-md border rounded-lg bg-white text-sm {{ $errors->has('exportFormat') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    <option>PDF</option>
                    <option>Excel (CSV)</option>
                </select>
                @error('exportFormat') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div class="flex justify-end gap-sm pt-md border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-audit-logs' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
            </div>
        </form>
    </x-modal>
</div>
