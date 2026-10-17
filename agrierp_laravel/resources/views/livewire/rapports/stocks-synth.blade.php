<div class="mt-md">
    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="p-md border-b border-outline-variant">
            <div class="relative max-w-xs">
                <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
                <input wire:model.live.debounce.300ms="search" type="text" placeholder="Rechercher..." class="w-full pl-9 pr-md py-2 border border-outline-variant rounded-lg text-xs bg-white focus:ring-2 focus:ring-brand-emerald outline-none">
            </div>
        </div>
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Catégorie</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Valeur Stock</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Sous Seuil</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->rows as $i => $row)
                        <tr class="rrow border-b border-outline-variant hover:bg-brand-emerald/5 {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Catégorie" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $row['category']->label }}</td>
                            <td data-label="Valeur Stock" class="px-md py-sm text-xs">
                                {{ number_format($row['valeur_stock'], 0, ',', ' ') }} FCFA
                                @if($row['negatifs'] > 0)
                                    <span class="text-[10px] text-error-deep font-bold block">({{ $row['negatifs'] }} produit(s) en stock négatif, retenus à zéro)</span>
                                @endif
                                @if($row['non_valorises'] > 0)
                                    <span class="text-[10px] text-outline italic block">({{ $row['non_valorises'] }} produit(s) jamais achetés, non valorisés)</span>
                                @endif
                            </td>
                            <td data-label="Sous Seuil" class="px-md py-sm text-xs">
                                @if($row['sous_seuil'] > 0)
                                    <span class="inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border bg-error-bg text-error-deep border-error-deep/30">{{ $row['sous_seuil'] }}</span>
                                @else
                                    <span class="text-outline">0</span>
                                @endif
                            </td>
                            <td data-label="Actions" class="px-md py-sm text-right whitespace-nowrap">
                                <span class="text-outline text-[10px] italic" title="Ce rapport est généré à partir des données réelles ; il ne peut pas être modifié ici.">Lecture seule</span>
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="4" class="px-md py-lg text-center text-outline">Aucune catégorie active.</td></tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>
</div>
