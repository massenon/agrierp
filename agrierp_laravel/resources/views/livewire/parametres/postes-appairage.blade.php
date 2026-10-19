<div class="mt-md">
    <div class="border-b border-outline-variant pb-md mb-lg flex flex-col sm:flex-row sm:items-end sm:justify-between gap-sm">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">lan</span>Postes &amp; Appairage
            </h2>
            <p class="text-xs text-outline mt-xs">Postes Windows appairés au serveur : un poste est appairé dès qu'un compte s'y connecte, et le reste jusqu'à l'expiration de son jeton ou sa révocation.</p>
        </div>
        <div class="flex flex-wrap gap-sm">
            <button type="button" wire:click="demander" class="px-md py-sm rounded-lg border border-brand-emerald text-brand-emerald text-sm font-semibold flex items-center gap-xs hover:bg-surface-zebra"><span class="material-symbols-outlined text-[18px]">sync</span>Demander la synchronisation des postes</button>
            <button type="button" wire:click="actualiser" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">refresh</span>Actualiser</button>
        </div>
    </div>

    <div class="bg-white border border-outline-variant rounded-lg overflow-x-auto">
        <table class="rtable w-full text-xs">
            <thead>
                <tr class="text-left text-outline border-b border-outline-variant">
                    <th class="py-sm px-md font-semibold">Poste</th>
                    <th class="py-sm px-md font-semibold">Utilisateur</th>
                    <th class="py-sm px-md font-semibold">Appairé le</th>
                    <th class="py-sm px-md font-semibold">Dernier contact</th>
                    <th class="py-sm px-md font-semibold">Expiration</th>
                    <th class="py-sm px-md font-semibold">Dernier envoi</th>
                    <th class="py-sm px-md font-semibold">Dernier contrôle</th>
                    <th class="py-sm px-md font-semibold">État</th>
                    <th class="py-sm px-md font-semibold text-right">Actions</th>
                </tr>
            </thead>
            <tbody>
                @php
                    $pastilles = [
                        'a_jour' => 'bg-brand-emerald/10 text-brand-emerald',
                        'inactif' => 'bg-accent-yellow/30 text-brand-forest',
                        'refus' => 'bg-error-bg text-error-deep',
                    ];
                @endphp
                @forelse($this->postes as $poste)
                    <tr wire:key="appairage-{{ $poste['jeton_id'] }}" class="border-b border-outline-variant">
                        <td data-label="Poste" class="py-sm px-md font-semibold break-all">{{ $poste['poste'] }}</td>
                        <td data-label="Utilisateur" class="py-sm px-md">{{ $poste['utilisateur'] }}</td>
                        <td data-label="Appairé le" class="py-sm px-md">{{ $poste['cree_le']?->format('d/m/Y H:i') ?? '—' }}</td>
                        <td data-label="Dernier contact" class="py-sm px-md">{{ $poste['dernier_contact']?->format('d/m/Y H:i') ?? '—' }}</td>
                        <td data-label="Expiration" class="py-sm px-md">{{ $poste['expire_le']?->format('d/m/Y') ?? 'Sans expiration' }}</td>
                        <td data-label="Dernier envoi" class="py-sm px-md">{{ $poste['dernier_envoi']?->format('d/m/Y H:i') ?? '—' }}</td>
                        <td data-label="Dernier contrôle" class="py-sm px-md">{{ $poste['dernier_controle']?->format('d/m/Y H:i') ?? '—' }}</td>
                        <td data-label="État" class="py-sm px-md"><span class="inline-block px-2 py-0.5 rounded-full font-bold text-[10px] {{ $pastilles[$poste['etat']] }}">{{ $poste['libelle_etat'] }}</span></td>
                        <td data-label="Actions" class="py-sm px-md text-right whitespace-nowrap">
                            <button type="button" wire:click="demander(@js($poste['poste']))" title="Demander la synchronisation de ce poste" class="text-outline hover:text-brand-emerald"><span class="material-symbols-outlined text-[18px]">sync</span></button>
                            <button type="button" x-on:click="$dispatch('open-modal', { name: 'revoquer-poste-{{ $poste['jeton_id'] }}' })" title="Révoquer l'appairage" class="text-outline hover:text-error-red ml-xs"><span class="material-symbols-outlined text-[18px]">lock</span></button>
                            <x-modal-confirm-hard-delete
                                :name="'revoquer-poste-'.$poste['jeton_id']"
                                :item-label="'L\'appairage du poste '.$poste['poste']"
                                :action="'revoquer('.\Illuminate\Support\Js::from($poste['poste']).')'"
                                title="Révoquer l'appairage"
                                confirm-label="Révoquer l'appairage"
                                warning="Le poste ne pourra plus synchroniser jusqu'à une nouvelle connexion avec le mot de passe d'un compte actif. Ses saisies en attente restent sur le poste ; elles partiront après la reconnexion." />
                        </td>
                    </tr>
                @empty
                    <tr><td colspan="9" class="py-md text-center text-outline">Aucun poste n'est appairé au serveur pour le moment.</td></tr>
                @endforelse
            </tbody>
        </table>
    </div>

    <div class="bg-surface-zebra rounded-lg p-sm text-[11px] text-outline mt-md">
        « Révoquer l'appairage » supprime les jetons de ce poste, pour tous les comptes qui s'y sont connectés : utile pour un poste perdu, volé ou remplacé. « Demander la synchronisation » dépose une demande que chaque poste connecté lit dans les 30 secondes ; c'est lui qui envoie et reçoit. L'adresse du serveur et l'identifiant de chaque poste se consultent sur le poste lui-même (Paramètres &gt; Appairage).
    </div>
</div>
