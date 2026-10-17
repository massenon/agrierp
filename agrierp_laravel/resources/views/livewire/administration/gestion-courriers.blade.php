<div class="mt-md space-y-md">
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">mail</span>Gestion des Courriers
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">Enregistrement et suivi du courrier entrant et sortant de la ferme.</p>
        </div>
        @can('manage-administration')
        <button type="button" wire:click="newMail" class="flex items-center justify-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full transition-all shadow-sm">
            <span class="material-symbols-outlined text-[18px]">add_circle</span>Nouveau Courrier
        </button>
        @endcan
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-md">
        <x-kpi-card label="Reçus (mois)" icon="mark_email_read" color="emerald" :value="$this->kpis['recus']" />
        <x-kpi-card label="Envoyés (mois)" icon="send" color="blue" :value="$this->kpis['envoyes']" />
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
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Référence</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Type</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Objet</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Partie</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->mails as $i => $mail)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Référence" class="px-md py-sm text-xs font-mono font-bold text-brand-emerald">{{ $mail->reference }}</td>
                            <td data-label="Type" class="px-md py-sm text-xs">{{ $mail->type === 'entrant' ? 'Entrant' : 'Sortant' }}</td>
                            <td data-label="Objet" class="px-md py-sm text-xs font-semibold">{{ $mail->subject }}</td>
                            <td data-label="Partie" class="px-md py-sm text-xs">{{ $mail->party }}</td>
                            <td data-label="Date" class="px-md py-sm text-xs">{{ $mail->mail_date->format('d/m/Y') }}</td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                @can('manage-administration')
                                <button type="button" wire:click="editMail('{{ $mail->id }}')" class="text-info-blue hover:text-blue-800 p-1" title="Modifier"><span class="material-symbols-outlined text-[18px]">edit</span></button>
                                <button type="button" x-on:click="$dispatch('open-modal', { name: 'archive-mail-{{ $mail->id }}' })" class="text-error-deep hover:text-red-800 p-1" title="Archiver"><span class="material-symbols-outlined text-[18px]">archive</span></button>
                                @else
                                <span class="text-outline text-[10px] italic">Lecture seule</span>
                                @endcan
                            </td>
                        </tr>
                        <x-modal-confirm-delete :name="'archive-mail-'.$mail->id" :item-label="$mail->reference.' — '.$mail->subject" :action="'archiveMail(\''.$mail->id.'\')'" />
                    @empty
                        <tr><td colspan="6" class="px-md py-lg text-center text-outline">Aucun courrier pour le moment.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    <x-modal name="modal-create-gestion-courriers" max-width="md">
        <div class="flex items-center justify-between mb-md">
            <h3 class="font-bold text-lg text-brand-forest">{{ $editingId ? 'Modifier le Courrier' : 'Nouveau Courrier' }}</h3>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-gestion-courriers' })" class="text-outline hover:text-error-deep"><span class="material-symbols-outlined">close</span></button>
        </div>
        <form wire:submit="saveMail" class="space-y-md">
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Type *</label>
                <select wire:model="type" class="w-full h-11 px-md border rounded-lg text-sm bg-white {{ $errors->has('type') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Sélectionner --</option>
                    <option value="entrant">Entrant</option>
                    <option value="sortant">Sortant</option>
                </select>
                @error('type') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Objet *</label>
                <input wire:model="subject" type="text" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('subject') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('subject') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Expéditeur / Destinataire *</label>
                <input wire:model="party" type="text" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('party') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('party') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <div>
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Date *</label>
                <input wire:model="mailDate" type="date" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
            </div>
            <div class="flex justify-end gap-sm pt-sm border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-create-gestion-courriers' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
            </div>
        </form>
    </x-modal>
</div>
