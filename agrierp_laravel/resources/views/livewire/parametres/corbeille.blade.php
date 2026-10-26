<div class="mt-md space-y-md">
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">restore_from_trash</span>Corbeille
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">
                Rien n'est effacé par erreur : tout enregistrement retiré d'un module est archivé ici. Restaurez-le, ou supprimez-le définitivement quand il n'a aucune conséquence.
            </p>
        </div>
    </div>

    <div class="grid grid-cols-1 sm:grid-cols-3 gap-md">
        <x-kpi-card label="Éléments archivés" icon="inventory_2" :value="$cartes['archives']" color="forest" />
        <x-kpi-card label="Restaurables" icon="restore" :value="$cartes['restaurables']" color="emerald" />
        <x-kpi-card label="Suppression définitive possible" icon="delete" :value="$cartes['supprimables']" color="red" />
    </div>

    <div class="bg-info-blue/10 border border-info-blue/20 rounded-lg p-md text-xs text-brand-forest">
        <span class="material-symbols-outlined text-[16px] align-middle mr-xs">info</span>
        Les <strong>écritures comptables</strong> n'apparaissent pas ici : une écriture ne se supprime pas, elle se contre-passe. Les <strong>comptes utilisateurs</strong> non plus : leur réactivation se fait depuis Gestion Utilisateurs. Une <strong>dépense</strong>, une <strong>vente annulée</strong> ou un <strong>transfert annulé</strong> se consulte ici mais ne se restaure pas : sa contre-passation ou son mouvement ne seraient pas rejoués.
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md">
        <div class="grid grid-cols-1 md:grid-cols-5 gap-sm items-end">
            <div class="md:col-span-2">
                <label for="corbeille-recherche" class="block text-[10px] text-outline font-bold uppercase mb-xs">Recherche</label>
                <div class="relative">
                    <span class="material-symbols-outlined text-[18px] text-outline absolute left-sm top-1/2 -translate-y-1/2">search</span>
                    <input id="corbeille-recherche" type="text" wire:model.live.debounce.300ms="recherche" placeholder="Rechercher un élément archivé…"
                        class="w-full h-10 pl-10 pr-md border border-outline-variant rounded-lg text-xs bg-white">
                </div>
            </div>
            <div>
                <label for="corbeille-type" class="block text-[10px] text-outline font-bold uppercase mb-xs">Type</label>
                <select id="corbeille-type" wire:model.live="typeFiltre" class="w-full h-10 px-md border border-outline-variant rounded-lg text-xs bg-white">
                    <option value="">Tous les types</option>
                    @foreach($this->types as $cle => $definition)
                        <option value="{{ $cle }}">{{ $definition['libelle'] }}</option>
                    @endforeach
                </select>
            </div>
            <div>
                <label for="corbeille-du" class="block text-[10px] text-outline font-bold uppercase mb-xs">Archivé du</label>
                <input id="corbeille-du" type="date" wire:model.live="du" class="w-full h-10 px-md border border-outline-variant rounded-lg text-xs bg-white">
            </div>
            <div>
                <label for="corbeille-au" class="block text-[10px] text-outline font-bold uppercase mb-xs">Au</label>
                <input id="corbeille-au" type="date" wire:model.live="au" class="w-full h-10 px-md border border-outline-variant rounded-lg text-xs bg-white">
            </div>
        </div>
        @if($filtre)
            <button type="button" wire:click="reinitialiserFiltres" class="mt-sm text-xs font-bold text-brand-emerald hover:text-brand-forest">Réinitialiser</button>
        @endif
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Type</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Élément</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Détail</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Module</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Archivé le</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Archivé par</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($page as $i => $element)
                        <tr wire:key="corbeille-{{ $element['type'] }}-{{ $element['id'] }}" class="rrow border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Type" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $element['libelle_type'] }}</td>
                            <td data-label="Élément" class="px-md py-sm text-xs">{{ $element['titre'] }}</td>
                            <td data-label="Détail" class="px-md py-sm text-xs text-outline">{{ $element['detail'] !== '' ? $element['detail'] : '—' }}</td>
                            <td data-label="Module" class="px-md py-sm text-xs text-outline">{{ ucfirst($element['module']) }}</td>
                            <td data-label="Archivé le" class="px-md py-sm text-xs text-outline">
                                {{ $element['archive_le']?->format('d/m/Y à H:i') ?? '—' }}
                            </td>
                            <td data-label="Archivé par" class="px-md py-sm text-xs text-outline">{{ $element['archive_par'] ?? '—' }}</td>
                            <td data-label="Actions" class="px-md py-sm text-right">
                                <div class="flex flex-col items-end gap-xs">
                                    @if($element['restaurable'])
                                        <button type="button"
                                            wire:click="restaurer('{{ $element['type'] }}', '{{ $element['id'] }}')"
                                            wire:loading.attr="disabled"
                                            class="inline-flex items-center gap-xs text-xs font-bold text-brand-emerald hover:text-brand-forest disabled:opacity-50">
                                            <span class="material-symbols-outlined text-[16px]">restore</span>Restaurer
                                        </button>
                                    @else
                                        <span class="inline-flex items-start gap-xs text-[11px] text-outline max-w-xs text-right">
                                            <span class="material-symbols-outlined text-[14px] flex-shrink-0">block</span>Non restaurable : {{ $element['motif_restauration'] }}
                                        </span>
                                    @endif
                                    @if($element['supprimable'])
                                        <button type="button"
                                            wire:click="demanderSuppression('{{ $element['type'] }}', '{{ $element['id'] }}')"
                                            wire:loading.attr="disabled"
                                            class="inline-flex items-center gap-xs text-xs font-bold text-error-deep hover:text-red-800 disabled:opacity-50">
                                            <span class="material-symbols-outlined text-[16px]">delete</span>Supprimer définitivement
                                        </button>
                                    @else
                                        <span class="inline-flex items-start gap-xs text-[11px] text-outline max-w-xs text-right">
                                            <span class="material-symbols-outlined text-[14px] flex-shrink-0">lock</span>Suppression définitive impossible : {{ $element['motif_suppression'] }}
                                        </span>
                                    @endif
                                </div>
                            </td>
                        </tr>
                    @empty
                        <tr>
                            <td colspan="7" class="px-md py-lg text-center text-outline text-xs">
                                @if($vide)
                                    La corbeille est vide — aucun élément archivé.
                                @else
                                    Aucun élément archivé ne correspond à cette recherche.
                                @endif
                            </td>
                        </tr>
                    @endforelse
                </tbody>
            </table>
        </div>
        <div class="flex flex-wrap items-center justify-between gap-sm px-md py-sm border-t border-outline-variant bg-white" data-pagination>
            <p class="text-[11px] text-outline">{{ $page->total() }} {{ $page->total() > 1 ? 'éléments' : 'élément' }} — page {{ $page->currentPage() }} sur {{ $page->lastPage() }}</p>
            @if($page->hasPages())
                <div class="flex items-center gap-xs">
                    <button type="button" wire:click="previousPage('pageCorbeille')" @disabled($page->onFirstPage()) class="flex items-center gap-[2px] text-xs font-bold px-sm py-1 rounded-lg border border-outline-variant text-brand-forest hover:bg-surface-zebra disabled:opacity-50"><span class="material-symbols-outlined text-[16px]">chevron_left</span>Précédent</button>
                    <button type="button" wire:click="nextPage('pageCorbeille')" @disabled(! $page->hasMorePages()) class="flex items-center gap-[2px] text-xs font-bold px-sm py-1 rounded-lg border border-outline-variant text-brand-forest hover:bg-surface-zebra disabled:opacity-50">Suivant<span class="material-symbols-outlined text-[16px]">chevron_right</span></button>
                </div>
            @endif
        </div>
    </div>

    {{-- Second temps de la suppression définitive : le mot SUPPRIMER, saisi à la main. --}}
    <x-modal name="modal-confirm-suppression-definitive" max-width="sm">
        <div class="text-center">
            <div class="w-12 h-12 bg-error-bg rounded-full flex items-center justify-center mx-auto mb-md">
                <span class="material-symbols-outlined text-error-deep text-[28px]">warning</span>
            </div>
            <h3 class="font-bold text-lg text-error-deep mb-xs">Supprimer définitivement ?</h3>
            <p class="text-sm text-outline">
                <strong class="text-on-surface">{{ $suppressionTitre }}</strong>
                @if($suppressionLibelle !== '')({{ $suppressionLibelle }})@endif
                sera supprimé définitivement. Cette action est irréversible : l'élément ne pourra plus être restauré.
            </p>
            <div class="text-left mt-md">
                <label for="corbeille-confirmation" class="block text-xs font-bold text-on-surface mb-xs">Pour confirmer, saisissez le mot SUPPRIMER</label>
                <input id="corbeille-confirmation" type="text" wire:model.live="confirmation" autocomplete="off" placeholder="SUPPRIMER"
                    class="w-full h-10 px-md border border-outline-variant rounded-lg text-sm bg-white">
            </div>
            <div class="flex justify-center gap-sm mt-lg">
                <button type="button" wire:click="annulerSuppression" x-on:click="$dispatch('close-modal', { name: 'modal-confirm-suppression-definitive' })" class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">Annuler</button>
                <button type="button" wire:click="supprimerDefinitivement" @disabled($confirmation !== \App\Services\CorbeilleService::MOT_CONFIRMATION)
                    class="px-md py-sm rounded-lg bg-error-red text-white text-sm font-bold hover:bg-red-700 disabled:opacity-40 disabled:cursor-not-allowed">Supprimer définitivement</button>
            </div>
        </div>
    </x-modal>
</div>
