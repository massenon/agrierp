<div class="mt-md">
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">tune</span>Modules Actifs
        </h2>
        <p class="text-xs text-outline mt-xs">Activez ou désactivez indépendamment chaque espèce d'élevage. La désactivation masque les menus et onglets concernés, sans jamais toucher à la comptabilité générale.</p>
    </div>

    <div class="space-y-md max-w-2xl">
        @foreach($this->species as $species)
            <div class="bg-white border border-outline-variant rounded-lg p-md flex items-center justify-between {{ !$species->is_enabled ? 'opacity-90' : '' }}">
                <div class="flex items-center gap-sm">
                    <span class="material-symbols-outlined {{ $species->module_enabled ? 'text-brand-emerald' : 'text-outline' }} text-[24px]">{{ $species->icon }}</span>
                    <div>
                        <p class="font-bold text-sm text-brand-forest">
                            {{ $species->label }}
                            @unless($species->is_enabled)
                                <span class="text-[9px] font-bold text-info-blue border border-info-blue/30 bg-info-blue/10 px-1.5 py-0.5 rounded-full ml-xs">FUTUR</span>
                            @endunless
                        </p>
                        <p class="text-[10px] text-outline">{{ $species->is_enabled ? 'Fiches, VMS, catalogue POS liés à cette filière' : 'Module en préparation — désactivé par défaut' }}</p>
                    </div>
                </div>
                <label class="relative inline-flex items-center cursor-pointer">
                    <input type="checkbox" wire:click="toggleModule('{{ $species->code }}')" {{ $species->module_enabled ? 'checked' : '' }} class="sr-only peer">
                    <div class="w-11 h-6 bg-outline-variant rounded-full peer peer-checked:bg-brand-emerald transition-all"></div>
                    <div class="absolute left-1 top-1 w-4 h-4 bg-white rounded-full transition-all peer-checked:translate-x-5"></div>
                </label>
            </div>
        @endforeach
    </div>

    <div class="mt-lg max-w-2xl bg-info-blue/10 border border-info-blue/30 rounded-lg p-md text-xs text-brand-forest flex items-start gap-xs">
        <span class="material-symbols-outlined text-info-blue text-[18px] flex-shrink-0">info</span>
        <span>Ces réglages sont appliqués immédiatement sur tous les onglets de <strong>Gestion Élevage</strong> et du <strong>Dashboard Élevage</strong>. Les données déjà enregistrées d'une espèce désactivée restent conservées et réapparaissent dès la réactivation du module.</span>
    </div>
</div>
