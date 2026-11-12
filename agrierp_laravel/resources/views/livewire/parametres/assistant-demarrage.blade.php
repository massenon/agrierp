<div class="mt-md space-y-md">
    <div class="border-b border-outline-variant pb-md">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">checklist</span>{{ __('parametres.titre_assistant') }}
        </h2>
        <p class="text-xs text-outline mt-xs">{{ __('parametres.desc_assistant') }}</p>
    </div>

    <div class="space-y-sm max-w-2xl">
        @foreach($this->etapes as $etape)
            <div wire:key="etape-{{ $etape['id'] }}" class="bg-white border border-outline-variant rounded-lg p-md flex items-start gap-sm {{ $etape['fait'] ? 'opacity-80' : '' }}">
                <span class="material-symbols-outlined text-[22px] {{ $etape['fait'] ? 'text-brand-emerald' : 'text-outline-variant' }} flex-shrink-0 mt-0.5">{{ $etape['fait'] ? 'check_circle' : 'radio_button_unchecked' }}</span>
                <div class="flex-1">
                    <p class="font-bold text-sm {{ $etape['fait'] ? 'line-through text-outline' : 'text-brand-forest' }}">{{ $etape['titre'] }}</p>
                    @if(!$etape['fait'])
                        <p class="text-xs text-outline mt-xs">{{ $etape['detail'] }}</p>
                    @endif
                    @if(!$etape['fait'])
                        <div class="flex flex-wrap gap-sm mt-sm">
                            @if($etape['lien'])
                                <a href="{{ $etape['lien'] }}" wire:navigate class="flex items-center gap-xs text-xs font-bold text-brand-emerald hover:text-brand-forest">
                                    <span class="material-symbols-outlined text-[16px]">open_in_new</span>{{ __('parametres.btn_regler') }}
                                </a>
                            @endif
                            @if($etape['id'] === 'ouvrir_exercice')
                                <a href="{{ route('comptabilite.exercices') }}" wire:navigate class="flex items-center gap-xs text-xs font-bold text-brand-emerald hover:text-brand-forest">
                                    <span class="material-symbols-outlined text-[16px]">calendar_today</span>{{ __('parametres.btn_ouvrir_exercice') }} {{ now()->format('Y') }}
                                </a>
                            @endif
                            @if($etape['recommande'])
                                <span class="text-[9px] text-info-blue border border-info-blue/30 bg-info-blue/10 px-1.5 py-0.5 rounded-full font-bold">{{ __('parametres.label_recommande') }}</span>
                            @endif
                            <button type="button" wire:click="marquerFait('{{ $etape['id'] }}')" class="text-[11px] text-outline hover:text-brand-forest underline">{{ __('parametres.btn_plus_tard') }}</button>
                        </div>
                    @endif
                </div>
            </div>
        @endforeach
    </div>

    @if($this->toutFait)
        <div class="max-w-2xl bg-brand-emerald/10 border border-brand-emerald/30 rounded-lg p-md flex items-center justify-between">
            <div class="flex items-center gap-sm">
                <span class="material-symbols-outlined text-brand-emerald text-[24px]">task_alt</span>
                <p class="font-bold text-brand-forest">{{ __('parametres.desc_assistant') }}</p>
            </div>
            <button type="button" wire:click="terminer" class="flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full">
                <span class="material-symbols-outlined text-[16px]">done_all</span>{{ __('parametres.btn_terminer') }}
            </button>
        </div>
    @endif
</div>
