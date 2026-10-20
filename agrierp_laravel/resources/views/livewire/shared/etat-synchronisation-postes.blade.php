<div>
    <button type="button" dusk="bouton-synchroniser" x-on:click="$dispatch('open-modal', { name: 'modal-etat-synchronisation' })" title="Synchroniser — état des postes" class="text-outline hover:text-brand-emerald relative">
        <span class="material-symbols-outlined">sync</span>
    </button>

    <x-modal name="modal-etat-synchronisation" max-width="lg">
        <div class="flex items-start justify-between mb-md">
            <div>
                <p class="text-[10px] font-bold uppercase tracking-wider text-outline">Postes de la ferme</p>
                <h3 class="font-bold text-lg text-brand-forest flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald">sync</span>Synchronisation</h3>
            </div>
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-etat-synchronisation' })" class="text-outline hover:text-on-surface"><span class="material-symbols-outlined">close</span></button>
        </div>
        <p class="text-xs text-outline mb-md">Le site est la base de référence : il ne synchronise rien lui-même. Chaque poste Windows envoie ses saisies et reçoit les données du site quand il synchronise ; voici ce que le serveur en sait. « Demander la synchronisation » dépose une demande que chaque poste connecté lit dans les 30 secondes ; c'est lui qui envoie et reçoit.</p>

        <div class="overflow-x-auto">
            <table class="w-full text-xs">
                <thead>
                    <tr class="text-left text-outline border-b border-outline-variant">
                        <th class="py-xs pr-sm font-semibold">Poste</th>
                        <th class="py-xs pr-sm font-semibold">Utilisateur</th>
                        <th class="py-xs pr-sm font-semibold">Dernier contact</th>
                        <th class="py-xs pr-sm font-semibold">Dernier envoi</th>
                        <th class="py-xs pr-sm font-semibold">Acceptés / Refusés</th>
                        <th class="py-xs pr-sm font-semibold">Dernier contrôle</th>
                        <th class="py-xs pr-sm font-semibold">État</th>
                        <th class="py-xs font-semibold text-right">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->postes as $poste)
                        @php
                            $pastilles = [
                                'a_jour' => 'bg-brand-emerald/10 text-brand-emerald',
                                'inactif' => 'bg-accent-yellow/30 text-brand-forest',
                                'refus' => 'bg-error-bg text-error-deep',
                            ];
                        @endphp
                        <tr wire:key="poste-{{ $poste['poste'] }}" class="border-b border-outline-variant">
                            <td data-label="Poste" class="py-xs pr-sm font-semibold break-all">{{ $poste['poste'] }}</td>
                            <td data-label="Utilisateur" class="py-xs pr-sm">{{ $poste['utilisateur'] }}</td>
                            <td data-label="Dernier contact" class="py-xs pr-sm">{{ $poste['dernier_contact']?->format('d/m/Y H:i') ?? '—' }}</td>
                            <td data-label="Dernier envoi" class="py-xs pr-sm">{{ $poste['dernier_envoi']?->format('d/m/Y H:i') ?? '—' }}</td>
                            <td data-label="Acceptés / Refusés" class="py-xs pr-sm">{{ $poste['acceptes'] === null ? '—' : $poste['acceptes'].' / '.$poste['refuses'] }}</td>
                            <td data-label="Dernier contrôle" class="py-xs pr-sm">{{ $poste['dernier_controle']?->format('d/m/Y H:i') ?? '—' }}</td>
                            <td data-label="État" class="py-xs pr-sm"><span class="inline-block px-2 py-0.5 rounded-full font-bold text-[10px] {{ $pastilles[$poste['etat']] }}">{{ $poste['libelle_etat'] }}</span></td>
                            <td data-label="Actions" class="py-xs text-right">
                                <button type="button" wire:click="demander(@js($poste['poste']))" title="Demander la synchronisation de ce poste" class="text-outline hover:text-brand-emerald"><span class="material-symbols-outlined text-[18px]">sync</span></button>
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="8" class="py-md text-center text-outline">Aucun poste n'est connecté au serveur pour le moment.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>

        <div class="flex justify-end gap-sm mt-lg">
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-etat-synchronisation' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Fermer</button>
            <button type="button" wire:click="demander" class="px-md py-sm rounded-lg border border-brand-emerald text-brand-emerald text-sm font-semibold flex items-center gap-xs hover:bg-surface-zebra"><span class="material-symbols-outlined text-[18px]">sync</span>Demander la synchronisation des postes</button>
            <button type="button" wire:click="actualiser" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">refresh</span>Actualiser</button>
        </div>
    </x-modal>
</div>
