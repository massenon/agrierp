<div class="mt-md space-y-md">
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">restore_from_trash</span>Restauration
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">
                Rien n'est jamais supprimé définitivement : tout enregistrement retiré d'un module est archivé et reste restaurable ici.
            </p>
        </div>
        <select wire:model.live="typeFiltre" class="h-10 px-md border border-outline-variant rounded-lg text-xs bg-white">
            <option value="">Tous les types</option>
            @foreach($this->types as $cle => $definition)
                <option value="{{ $cle }}">{{ $definition['libelle'] }}</option>
            @endforeach
        </select>
    </div>

    <div class="bg-info-blue/10 border border-info-blue/20 rounded-lg p-md text-xs text-brand-forest">
        <span class="material-symbols-outlined text-[16px] align-middle mr-xs">info</span>
        Les <strong>écritures comptables</strong> n'apparaissent pas ici : une écriture ne se supprime pas, elle se contre-passe — la restaurer modifierait un grand livre sans contrepartie. Les <strong>comptes utilisateurs</strong> non plus : leur réactivation se fait depuis Gestion Utilisateurs.
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Type</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Élément</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Module</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Archivé le</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->elements as $i => $element)
                        <tr class="rrow border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Type" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $element['libelle_type'] }}</td>
                            <td data-label="Élément" class="px-md py-sm text-xs">{{ $element['titre'] }}</td>
                            <td data-label="Module" class="px-md py-sm text-xs text-outline">{{ ucfirst($element['module']) }}</td>
                            <td data-label="Archivé le" class="px-md py-sm text-xs text-outline">
                                {{ $element['archive_le']?->format('d/m/Y à H:i') ?? '—' }}
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                <button type="button"
                                    wire:click="restaurer('{{ $element['type'] }}', '{{ $element['id'] }}')"
                                    wire:loading.attr="disabled"
                                    class="inline-flex items-center gap-xs text-xs font-bold text-brand-emerald hover:text-brand-forest disabled:opacity-50">
                                    <span class="material-symbols-outlined text-[16px]">restore</span>Restaurer
                                </button>
                            </td>
                        </tr>
                    @empty
                        <tr>
                            <td colspan="5" class="px-md py-lg text-center text-outline text-xs">
                                La corbeille est vide — aucun élément archivé.
                            </td>
                        </tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>
</div>
