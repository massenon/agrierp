<div>
    @if($afficher)
        <div x-data x-init="$nextTick(() => $dispatch('open-modal', { name: 'modal-demarrage' }))">
            <x-modal name="modal-demarrage" max-width="lg">
                <div class="flex items-center gap-sm mb-sm">
                    <span class="material-symbols-outlined text-brand-emerald" style="font-size:32px;">checklist</span>
                    <div>
                        <h3 class="font-bold text-lg text-brand-forest">Bienvenue dans LogiAgriERP</h3>
                        <p class="text-xs text-outline">Ce qu'il faut en place avant la première saisie — constaté dans la base, pas à cocher.</p>
                    </div>
                </div>

                <ol class="flex flex-col gap-sm">
                    @foreach($etapes as $i => $etape)
                        <li wire:key="etape-{{ $etape['cle'] }}" data-etape="{{ $etape['cle'] }}"
                            class="border border-outline-variant rounded-lg p-sm flex items-start gap-sm">
                            @if($etape['fait'])
                                <span class="material-symbols-outlined text-brand-emerald text-[20px]">check_circle</span>
                            @else
                                <span class="material-symbols-outlined text-error-deep text-[20px]">pending</span>
                            @endif
                            <div class="flex-1">
                                <p class="text-xs font-bold text-brand-forest">
                                    {{ $i + 1 }}. {{ $etape['titre'] }}
                                    @unless($etape['obligatoire'])
                                        <span class="font-normal text-outline">(recommandé)</span>
                                    @endunless
                                </p>
                                <p class="text-xs text-outline">{{ $etape['detail'] }}</p>
                            </div>
                            @if(! $etape['fait'])
                                @if($etape['cle'] === 'exercice')
                                    @can('manage-comptabilite')
                                        <button type="button" wire:click="ouvrirExercice"
                                            class="text-xs font-bold text-white bg-brand-emerald rounded-full px-sm py-xs whitespace-nowrap">
                                            Ouvrir l'exercice {{ now()->format('Y') }}
                                        </button>
                                    @endcan
                                @elseif($etape['lien'])
                                    <a href="{{ $etape['lien'] }}" wire:navigate
                                        class="text-xs font-bold text-brand-emerald whitespace-nowrap">Régler</a>
                                @endif
                            @endif
                        </li>
                    @endforeach
                </ol>

                <div class="flex justify-end gap-sm mt-md pt-sm border-t border-outline-variant">
                    <button type="button" wire:click="reporter"
                        class="text-xs font-bold text-outline px-md py-sm rounded-full border border-outline-variant">Plus tard</button>
                    <button type="button" wire:click="terminer"
                        class="text-xs font-bold text-white bg-brand-forest px-md py-sm rounded-full">Terminer</button>
                </div>
            </x-modal>
        </div>
    @endif
</div>
