<div>
    @php
        // Ticket EX8 (EF11) — Bilan N / N-1 : colonne « Exercice N » (date choisie) et « Exercice N-1 » (à sa clôture,
        // « — » s'il n'existe pas, jamais 0). Un seul point de calcul : `FinancialReportService::bilanComparatif`.
        $c = $this->comparatif;
        $bilan = $c['n'];
        $n1 = $c['n1'];
        $m = fn ($v) => \App\Support\ComparatifNMoinsUn::montant($v);
        $neg = fn ($v) => $v === null ? null : -$v;
    @endphp
    <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-sm border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">balance</span>{{ __('comptabilite.bilan_titre') }}
            </h2>
            <p class="text-xs text-outline mt-xs">{{ __('comptabilite.bilan_sous_titre') }} {{ \Carbon\Carbon::parse($asOfDate)->format('d/m/Y') }}.</p>
        </div>
        <div class="flex items-center gap-xs">
            <input wire:model.live="asOfDate" type="date" min="{{ \App\Support\ExerciceChoisi::bornes()[0] }}" max="{{ \App\Support\ExerciceChoisi::bornes()[1] }}" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white">
        </div>
    </div>

    <x-anouveaux-provisoires :ouverture="$bilan['ouverture']" />

    <div class="mb-lg">
        @if($bilan['is_balanced'])
            <div class="bg-brand-emerald/10 border border-brand-emerald/30 rounded-lg p-md flex items-center gap-xs text-brand-forest text-sm font-bold">
                <span class="material-symbols-outlined text-brand-emerald">check_circle</span>{{ __('comptabilite.bilan_equilibre', ['total' => number_format($bilan['total_actif'], 0, ',', ' ')]) }}
            </div>
        @else
            <div class="bg-error-bg border border-error-deep/30 rounded-lg p-md flex items-center gap-xs text-error-deep text-sm font-bold">
                <span class="material-symbols-outlined text-error-red">error</span>{{ __('comptabilite.bilan_desequilibre', ['actif' => number_format($bilan['total_actif'], 0, ',', ' '), 'passif' => number_format($bilan['total_passif'], 0, ',', ' ')]) }}
            </div>
        @endif
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-md">
        @foreach([
            ['titre' => __('comptabilite.bilan_actif_titre'), 'bordure' => 'border-brand-emerald bg-brand-emerald/5', 'couleur' => 'text-brand-emerald', 'total' => 'total_actif', 'libelleTotal' => __('comptabilite.bilan_total_actif')],
            ['titre' => __('comptabilite.bilan_passif_titre'), 'bordure' => 'border-info-blue bg-info-blue/5', 'couleur' => 'text-info-blue', 'total' => 'total_passif', 'libelleTotal' => __('comptabilite.bilan_total_passif')],
        ] as $carte)
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
            <div class="px-md py-sm border-b-2 {{ $carte['bordure'] }}"><h3 class="text-sm font-bold {{ $carte['couleur'] }} uppercase">{{ $carte['titre'] }}</h3></div>
            <div class="p-md space-y-md text-xs">
                {{-- En-têtes des deux colonnes juxtaposées. --}}
                <div class="flex gap-sm pb-xs border-b border-outline-variant text-[10px] font-bold uppercase text-outline">
                    <span class="flex-1 min-w-0"></span>
                    <span class="w-28 text-right">{{ \App\Support\ComparatifNMoinsUn::ENTETE_N }}<span class="block normal-case font-normal">{{ \App\Support\ComparatifNMoinsUn::sousTitre($c['exercice_n']) }}</span></span>
                    <span class="w-28 text-right">{{ \App\Support\ComparatifNMoinsUn::ENTETE_N1 }}<span class="block normal-case font-normal">{{ \App\Support\ComparatifNMoinsUn::sousTitre($c['exercice_n1']) }}</span></span>
                </div>

                @if($carte['total'] === 'total_actif')
                    @foreach([
                        ['titre' => __('comptabilite.bilan_immo_titre'), 'rubriques' => ['immo'], 'vide' => __('comptabilite.bilan_vide_classe'), 'sousTotal' => __('comptabilite.bilan_sous_total_immo'), 'cle' => 'total_immo'],
                        ['titre' => __('comptabilite.bilan_circulant_titre'), 'rubriques' => ['stocks', 'creances'], 'vide' => __('comptabilite.bilan_vide_classes'), 'sousTotal' => __('comptabilite.bilan_sous_total_circulant'), 'cle' => 'total_circulant'],
                        ['titre' => __('comptabilite.bilan_tresorerie_titre'), 'rubriques' => ['tresorerie'], 'vide' => __('comptabilite.bilan_vide_classe'), 'sousTotal' => __('comptabilite.bilan_sous_total_tresorerie'), 'cle' => 'total_tresorerie'],
                    ] as $section)
                        @php $lignes = array_merge(...array_map(fn ($r) => $c['lignes'][$r], $section['rubriques'])); @endphp
                        <div>
                            <p class="font-bold text-brand-forest uppercase text-[10px] mb-xs">{{ $section['titre'] }}</p>
                            @forelse($lignes as $line)
                                <div class="flex gap-sm py-1 border-b border-outline-variant"><span class="flex-1 min-w-0 text-outline">{{ $line['code'] }} - {{ $line['label'] }}</span><span class="w-28 text-right" data-colonne="n">{{ $m($line['n']) }}</span><span class="w-28 text-right text-outline" data-colonne="n1">{{ $m($line['n1']) }}</span></div>
                            @empty
                                <p class="text-outline italic py-1">{{ $section['vide'] }}</p>
                            @endforelse
                            <div class="flex gap-sm py-1 font-bold text-brand-forest"><span class="flex-1 min-w-0">{{ $section['sousTotal'] }}</span><span class="w-28 text-right" data-colonne="n">{{ $m($bilan[$section['cle']]) }}</span><span class="w-28 text-right" data-colonne="n1">{{ $m($n1[$section['cle']] ?? null) }}</span></div>
                        </div>
                    @endforeach
                @else
                    <div>
                        <p class="font-bold text-brand-forest uppercase text-[10px] mb-xs">{{ __('comptabilite.bilan_capitaux_titre') }}</p>
                        @forelse($c['lignes']['capitaux'] as $line)
                            <div class="flex gap-sm py-1 border-b border-outline-variant"><span class="flex-1 min-w-0 text-outline">{{ $line['code'] }} - {{ $line['label'] }}</span><span class="w-28 text-right" data-colonne="n">{{ $m(-$line['n']) }}</span><span class="w-28 text-right text-outline" data-colonne="n1">{{ $m($neg($line['n1'])) }}</span></div>
                        @empty
                            <p class="text-outline italic py-1">{{ __('comptabilite.bilan_vide_classe') }}</p>
                        @endforelse
                        <div class="flex gap-sm py-1 border-b border-outline-variant"><span class="flex-1 min-w-0 text-outline">{{ __('comptabilite.bilan_resultat') }}</span><span class="w-28 text-right {{ $bilan['resultat'] >= 0 ? 'text-brand-emerald' : 'text-error-deep' }} font-bold" data-colonne="n">{{ $m($bilan['resultat']) }}</span><span class="w-28 text-right {{ ($n1['resultat'] ?? 0) >= 0 ? 'text-brand-emerald' : 'text-error-deep' }} font-bold" data-colonne="n1">{{ $m($n1['resultat'] ?? null) }}</span></div>
                        <div class="flex gap-sm py-1 font-bold text-brand-forest"><span class="flex-1 min-w-0">{{ __('comptabilite.bilan_sous_total_capitaux') }}</span><span class="w-28 text-right" data-colonne="n">{{ $m($bilan['total_capitaux'] + $bilan['resultat']) }}</span><span class="w-28 text-right" data-colonne="n1">{{ $m($n1 === null ? null : $n1['total_capitaux'] + $n1['resultat']) }}</span></div>
                    </div>
                    <div>
                        <p class="font-bold text-brand-forest uppercase text-[10px] mb-xs">{{ __('comptabilite.bilan_dettes_titre') }}</p>
                        @forelse($c['lignes']['dettes'] as $line)
                            <div class="flex gap-sm py-1 border-b border-outline-variant"><span class="flex-1 min-w-0 text-outline">{{ $line['code'] }} - {{ $line['label'] }}</span><span class="w-28 text-right" data-colonne="n">{{ $m($line['n']) }}</span><span class="w-28 text-right text-outline" data-colonne="n1">{{ $m($line['n1']) }}</span></div>
                        @empty
                            <p class="text-outline italic py-1">{{ __('comptabilite.bilan_vide_classe') }}</p>
                        @endforelse
                        <div class="flex gap-sm py-1 font-bold text-brand-forest"><span class="flex-1 min-w-0">{{ __('comptabilite.bilan_sous_total_dettes') }}</span><span class="w-28 text-right" data-colonne="n">{{ $m($bilan['total_dettes']) }}</span><span class="w-28 text-right" data-colonne="n1">{{ $m($n1['total_dettes'] ?? null) }}</span></div>
                    </div>
                    <div class="pt-lg text-outline italic text-[10px] border-t border-outline-variant">
                        <p>{{ __('comptabilite.bilan_note_passif') }}</p>
                    </div>
                @endif
            </div>
            <div class="px-md py-md border-t-2 border-brand-forest bg-surface-zebra flex gap-sm items-center">
                <span class="flex-1 min-w-0 font-black text-brand-forest uppercase text-sm">{{ $carte['libelleTotal'] }}</span>
                <span class="w-28 text-right font-black {{ $carte['couleur'] }} text-lg" data-colonne="n">{{ $m($bilan[$carte['total']]) }}</span>
                <span class="w-28 text-right font-black text-outline text-lg" data-colonne="n1">{{ $m($n1[$carte['total']] ?? null) }}</span>
            </div>
        </div>
        @endforeach
    </div>
</div>
