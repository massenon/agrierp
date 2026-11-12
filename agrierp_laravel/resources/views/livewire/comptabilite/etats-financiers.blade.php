<div>
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">description</span>{{ __('comptabilite.etats_titre') }}
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">{{ __('comptabilite.etats_sous_titre') }}</p>
        </div>
        <button type="button" wire:click="exportEtatActifPdf" wire:loading.attr="disabled" wire:target="exportEtatActifPdf" class="flex items-center justify-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full transition-all disabled:opacity-50">
            <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>{{ __('comptabilite.etats_exporter_pdf') }}
        </button>
    </div>

    <x-anouveaux-provisoires :ouverture="$this->bilan['ouverture']" />

    <div class="flex items-center gap-xs border-b border-outline-variant mb-md overflow-x-auto">
        @foreach(['bilan' => __('comptabilite.etats_tab_bilan'), 'resultat' => __('comptabilite.etats_tab_resultat'), 'tafire' => __('comptabilite.etats_tab_tafire'), 'notes' => __('comptabilite.etats_tab_notes')] as $key => $label)
            <button type="button" wire:click="switchTab('{{ $key }}')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap {{ $tab === $key ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}">{{ $label }}</button>
        @endforeach
    </div>

    @php
        // Ticket EX8 (EF11) — Bilan et Compte de Résultat N / N-1 : colonne « Exercice N » (exercice affiché) et
        // « Exercice N-1 » (à sa clôture, « — » s'il n'existe pas, jamais 0). `FinancialReportService::bilanComparatif`
        // et `compteResultatComparatif`, un seul point de calcul.
        $m = fn ($v) => \App\Support\ComparatifNMoinsUn::montant($v);
        $f = fn ($v) => $v === null ? '—' : \App\Support\ComparatifNMoinsUn::montant($v).' F';
        $p = fn ($v) => $v === null ? '—' : '('.\App\Support\ComparatifNMoinsUn::montant($v).')';
        $neg = fn ($v) => $v === null ? null : -$v;
    @endphp

    @if($tab === 'bilan')
        @php
            $c = $this->bilanComparatif;
            $bn = $c['n'];
            $b1 = $c['n1'];
        @endphp
        <div>
            <div class="bg-white border border-outline-variant rounded-lg p-md mb-md flex items-center justify-between">
                <span class="text-xs text-outline">{{ $this->situationLabel }}</span>
                @if($bn['is_balanced'])
                    <span class="text-[11px] font-bold px-sm py-1 rounded-full bg-brand-emerald/10 text-brand-emerald">
                        <span class="material-symbols-outlined text-[14px] align-middle">check_circle</span>{{ __('comptabilite.etats_bilan_equilibre') }}
                    </span>
                @else
                    <span class="text-[11px] font-bold px-sm py-1 rounded-full bg-error-red/10 text-error-deep">
                        <span class="material-symbols-outlined text-[14px] align-middle">warning</span>{{ __('comptabilite.etats_bilan_ecart', ['ecart' => number_format(abs($bn['total_actif'] - $bn['total_passif']), 0, ',', ' ')]) }}
                    </span>
                @endif
            </div>

            <div class="grid grid-cols-1 lg:grid-cols-2 gap-md">
                <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
                    <div class="px-md py-sm border-b-2 border-brand-emerald bg-brand-emerald/5"><h3 class="text-sm font-bold text-brand-emerald uppercase">{{ __('comptabilite.etats_actif_titre') }}</h3></div>
                    <table class="w-full text-xs">
                        <thead>
                            <tr class="border-b border-outline-variant text-[10px] text-outline uppercase">
                                <th class="px-md py-sm"></th>
                                <th class="px-md py-sm text-right">{{ \App\Support\ComparatifNMoinsUn::ENTETE_N }}<span class="block normal-case font-normal">{{ \App\Support\ComparatifNMoinsUn::sousTitre($c['exercice_n']) }}</span></th>
                                <th class="px-md py-sm text-right">{{ \App\Support\ComparatifNMoinsUn::ENTETE_N1 }}<span class="block normal-case font-normal">{{ \App\Support\ComparatifNMoinsUn::sousTitre($c['exercice_n1']) }}</span></th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr class="border-b border-outline-variant"><td class="px-md py-sm font-bold text-brand-forest uppercase text-[10px]" colspan="3">{{ __('comptabilite.bilan_immo_titre') }}</td></tr>
                            @foreach($c['lignes']['immo'] as $ligne)
                                <tr class="border-b border-outline-variant">
                                    <td class="px-md py-sm pl-lg text-outline">{{ $ligne['code'] }} — {{ $ligne['label'] }}</td>
                                    <td class="px-md py-sm text-right {{ $ligne['n'] < 0 ? 'text-error-deep' : '' }}" data-colonne="n">{{ $m($ligne['n']) }}</td>
                                    <td class="px-md py-sm text-right text-outline" data-colonne="n1">{{ $m($ligne['n1']) }}</td>
                                </tr>
                            @endforeach
                            <tr class="bg-surface-zebra border-b border-outline-variant"><td class="px-md py-sm font-bold text-brand-forest">{{ __('comptabilite.bilan_sous_total_immo') }}</td><td class="px-md py-sm text-right font-bold text-brand-forest" data-colonne="n">{{ $m($bn['total_immo']) }}</td><td class="px-md py-sm text-right font-bold text-brand-forest" data-colonne="n1">{{ $m($b1['total_immo'] ?? null) }}</td></tr>

                            <tr class="border-b border-outline-variant"><td class="px-md py-sm font-bold text-brand-forest uppercase text-[10px]" colspan="3">{{ __('comptabilite.bilan_circulant_titre') }}</td></tr>
                            @foreach(array_merge($c['lignes']['stocks'], $c['lignes']['creances']) as $ligne)
                                <tr class="border-b border-outline-variant"><td class="px-md py-sm pl-lg text-outline">{{ $ligne['code'] }} — {{ $ligne['label'] }}</td><td class="px-md py-sm text-right" data-colonne="n">{{ $m($ligne['n']) }}</td><td class="px-md py-sm text-right text-outline" data-colonne="n1">{{ $m($ligne['n1']) }}</td></tr>
                            @endforeach
                            <tr class="bg-surface-zebra border-b border-outline-variant"><td class="px-md py-sm font-bold text-brand-forest">{{ __('comptabilite.bilan_sous_total_circulant') }}</td><td class="px-md py-sm text-right font-bold text-brand-forest" data-colonne="n">{{ $m($bn['total_circulant']) }}</td><td class="px-md py-sm text-right font-bold text-brand-forest" data-colonne="n1">{{ $m($b1['total_circulant'] ?? null) }}</td></tr>

                            <tr class="border-b border-outline-variant"><td class="px-md py-sm font-bold text-brand-forest uppercase text-[10px]" colspan="3">{{ __('comptabilite.bilan_tresorerie_titre') }}</td></tr>
                            @foreach($c['lignes']['tresorerie'] as $ligne)
                                <tr class="border-b border-outline-variant"><td class="px-md py-sm pl-lg text-outline">{{ $ligne['code'] }} — {{ $ligne['label'] }}</td><td class="px-md py-sm text-right" data-colonne="n">{{ $m($ligne['n']) }}</td><td class="px-md py-sm text-right text-outline" data-colonne="n1">{{ $m($ligne['n1']) }}</td></tr>
                            @endforeach
                            <tr class="bg-surface-zebra"><td class="px-md py-sm font-bold text-brand-forest">{{ __('comptabilite.bilan_sous_total_tresorerie') }}</td><td class="px-md py-sm text-right font-bold text-brand-forest" data-colonne="n">{{ $m($bn['total_tresorerie']) }}</td><td class="px-md py-sm text-right font-bold text-brand-forest" data-colonne="n1">{{ $m($b1['total_tresorerie'] ?? null) }}</td></tr>
                        </tbody>
                        <tfoot>
                            <tr class="bg-surface-zebra border-t-2 border-brand-forest">
                                <td class="px-md py-sm font-black text-brand-forest uppercase">{{ __('comptabilite.bilan_total_actif') }}</td>
                                <td class="px-md py-sm font-black text-brand-emerald text-right" data-colonne="n">{{ $f($bn['total_actif']) }}</td>
                                <td class="px-md py-sm font-black text-outline text-right" data-colonne="n1">{{ $f($b1['total_actif'] ?? null) }}</td>
                            </tr>
                        </tfoot>
                    </table>
                </div>

                <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
                    <div class="px-md py-sm border-b-2 border-info-blue bg-info-blue/5"><h3 class="text-sm font-bold text-info-blue uppercase">{{ __('comptabilite.etats_passif_titre') }}</h3></div>
                    <table class="w-full text-xs">
                        <thead>
                            <tr class="border-b border-outline-variant text-[10px] text-outline uppercase">
                                <th class="px-md py-sm"></th>
                                <th class="px-md py-sm text-right">{{ \App\Support\ComparatifNMoinsUn::ENTETE_N }}<span class="block normal-case font-normal">{{ \App\Support\ComparatifNMoinsUn::sousTitre($c['exercice_n']) }}</span></th>
                                <th class="px-md py-sm text-right">{{ \App\Support\ComparatifNMoinsUn::ENTETE_N1 }}<span class="block normal-case font-normal">{{ \App\Support\ComparatifNMoinsUn::sousTitre($c['exercice_n1']) }}</span></th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr class="border-b border-outline-variant"><td class="px-md py-sm font-bold text-brand-forest uppercase text-[10px]" colspan="3">{{ __('comptabilite.bilan_capitaux_titre') }}</td></tr>
                            @foreach($c['lignes']['capitaux'] as $ligne)
                                <tr class="border-b border-outline-variant"><td class="px-md py-sm pl-lg text-outline">{{ $ligne['code'] }} — {{ $ligne['label'] }}</td><td class="px-md py-sm text-right" data-colonne="n">{{ $m(-$ligne['n']) }}</td><td class="px-md py-sm text-right text-outline" data-colonne="n1">{{ $m($neg($ligne['n1'])) }}</td></tr>
                            @endforeach
                            <tr class="border-b border-outline-variant"><td class="px-md py-sm pl-lg text-outline">{{ __('comptabilite.bilan_resultat') }}</td><td class="px-md py-sm text-right font-bold text-brand-emerald" data-colonne="n">{{ $m($bn['resultat']) }}</td><td class="px-md py-sm text-right font-bold text-outline" data-colonne="n1">{{ $m($b1['resultat'] ?? null) }}</td></tr>
                            <tr class="bg-surface-zebra border-b border-outline-variant"><td class="px-md py-sm font-bold text-brand-forest">{{ __('comptabilite.bilan_sous_total_capitaux') }}</td><td class="px-md py-sm text-right font-bold text-brand-forest" data-colonne="n">{{ $m($bn['total_capitaux'] + $bn['resultat']) }}</td><td class="px-md py-sm text-right font-bold text-brand-forest" data-colonne="n1">{{ $m($b1 === null ? null : $b1['total_capitaux'] + $b1['resultat']) }}</td></tr>

                            <tr class="border-b border-outline-variant"><td class="px-md py-sm font-bold text-brand-forest uppercase text-[10px]" colspan="3">{{ __('comptabilite.bilan_dettes_titre') }}</td></tr>
                            @foreach($c['lignes']['dettes'] as $ligne)
                                <tr class="border-b border-outline-variant"><td class="px-md py-sm pl-lg text-outline">{{ $ligne['code'] }} — {{ $ligne['label'] }}</td><td class="px-md py-sm text-right" data-colonne="n">{{ $m($ligne['n']) }}</td><td class="px-md py-sm text-right text-outline" data-colonne="n1">{{ $m($ligne['n1']) }}</td></tr>
                            @endforeach
                            <tr class="bg-surface-zebra"><td class="px-md py-sm font-bold text-brand-forest">{{ __('comptabilite.bilan_sous_total_dettes') }}</td><td class="px-md py-sm text-right font-bold text-brand-forest" data-colonne="n">{{ $m($bn['total_dettes']) }}</td><td class="px-md py-sm text-right font-bold text-brand-forest" data-colonne="n1">{{ $m($b1['total_dettes'] ?? null) }}</td></tr>
                        </tbody>
                        <tfoot>
                            <tr class="bg-surface-zebra border-t-2 border-brand-forest">
                                <td class="px-md py-sm font-black text-brand-forest uppercase">{{ __('comptabilite.bilan_total_passif') }}</td>
                                <td class="px-md py-sm font-black text-info-blue text-right" data-colonne="n">{{ $f($bn['total_passif']) }}</td>
                                <td class="px-md py-sm font-black text-outline text-right" data-colonne="n1">{{ $f($b1['total_passif'] ?? null) }}</td>
                            </tr>
                        </tfoot>
                    </table>
                </div>
            </div>
        </div>
    @endif

    @if($tab === 'resultat')
        @php
            $cr = $this->resultatComparatif;
            $rn = $cr['n'];
            $r1 = $cr['n1'];
        @endphp
        <div>
            <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden max-w-3xl">
                <div class="px-md py-sm border-b-2 border-brand-emerald bg-brand-emerald/5"><h3 class="text-sm font-bold text-brand-forest uppercase">{{ __('comptabilite.etats_resultat_titre') }}</h3></div>
                <table class="w-full text-xs">
                    <thead>
                        <tr class="border-b border-outline-variant text-[10px] text-outline uppercase">
                            <th class="px-md py-sm"></th>
                            <th class="px-md py-sm text-right">{{ \App\Support\ComparatifNMoinsUn::ENTETE_N }}<span class="block normal-case font-normal">{{ \App\Support\ComparatifNMoinsUn::sousTitre($cr['exercice_n']) }}</span></th>
                            <th class="px-md py-sm text-right">{{ \App\Support\ComparatifNMoinsUn::ENTETE_N1 }}<span class="block normal-case font-normal">{{ \App\Support\ComparatifNMoinsUn::sousTitre($cr['exercice_n1']) }}</span></th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr class="border-b border-outline-variant"><td class="px-md py-sm">{{ __('comptabilite.etats_resultat_ventes') }}</td><td class="px-md py-sm text-right" data-colonne="n">{{ $m($rn['ventes']) }}</td><td class="px-md py-sm text-right text-outline" data-colonne="n1">{{ $m($r1['ventes'] ?? null) }}</td></tr>
                        <tr class="border-b border-outline-variant"><td class="px-md py-sm">{{ __('comptabilite.etats_resultat_achats') }}</td><td class="px-md py-sm text-right text-error-deep" data-colonne="n">{{ $p($rn['achats']) }}</td><td class="px-md py-sm text-right text-error-deep" data-colonne="n1">{{ $p($r1['achats'] ?? null) }}</td></tr>
                        <tr class="bg-surface-zebra border-b border-outline-variant font-bold"><td class="px-md py-sm">{{ __('comptabilite.etats_resultat_marge') }}</td><td class="px-md py-sm text-right" data-colonne="n">{{ $m($rn['marge_commerciale']) }}</td><td class="px-md py-sm text-right" data-colonne="n1">{{ $m($r1['marge_commerciale'] ?? null) }}</td></tr>
                        <tr class="border-b border-outline-variant"><td class="px-md py-sm">{{ __('comptabilite.etats_resultat_charges_personnel') }}</td><td class="px-md py-sm text-right text-error-deep" data-colonne="n">{{ $p($rn['charges_personnel']) }}</td><td class="px-md py-sm text-right text-error-deep" data-colonne="n1">{{ $p($r1['charges_personnel'] ?? null) }}</td></tr>
                        <tr class="bg-surface-zebra border-b border-outline-variant font-bold"><td class="px-md py-sm">{{ __('comptabilite.etats_resultat_ebe') }}</td><td class="px-md py-sm text-right" data-colonne="n">{{ $m($rn['ebe']) }}</td><td class="px-md py-sm text-right" data-colonne="n1">{{ $m($r1['ebe'] ?? null) }}</td></tr>
                        <tr class="border-b border-outline-variant"><td class="px-md py-sm">{{ __('comptabilite.etats_resultat_dotations') }}</td><td class="px-md py-sm text-right text-error-deep" data-colonne="n">{{ $p($rn['dotations']) }}</td><td class="px-md py-sm text-right text-error-deep" data-colonne="n1">{{ $p($r1['dotations'] ?? null) }}</td></tr>
                        <tr class="bg-surface-zebra border-b border-outline-variant font-bold"><td class="px-md py-sm">{{ __('comptabilite.etats_resultat_exploitation') }}</td><td class="px-md py-sm text-right" data-colonne="n">{{ $m($rn['resultat_exploitation']) }}</td><td class="px-md py-sm text-right" data-colonne="n1">{{ $m($r1['resultat_exploitation'] ?? null) }}</td></tr>
                        <tr class="border-b border-outline-variant"><td class="px-md py-sm">{{ __('comptabilite.etats_resultat_financier') }}</td><td class="px-md py-sm text-right" data-colonne="n">{{ $m($rn['resultat_financier']) }}</td><td class="px-md py-sm text-right" data-colonne="n1">{{ $m($r1['resultat_financier'] ?? null) }}</td></tr>
                        <tr class="bg-surface-zebra border-b border-outline-variant font-bold"><td class="px-md py-sm">{{ __('comptabilite.etats_resultat_rao') }}</td><td class="px-md py-sm text-right" data-colonne="n">{{ $m($rn['rao']) }}</td><td class="px-md py-sm text-right" data-colonne="n1">{{ $m($r1['rao'] ?? null) }}</td></tr>
                        <tr class="border-b border-outline-variant"><td class="px-md py-sm">{{ __('comptabilite.etats_resultat_hao') }}</td><td class="px-md py-sm text-right text-error-deep" data-colonne="n">{{ $p($rn['autres_charges']) }}</td><td class="px-md py-sm text-right text-error-deep" data-colonne="n1">{{ $p($r1['autres_charges'] ?? null) }}</td></tr>
                        <tr class="bg-brand-forest text-white font-extrabold"><td class="px-md py-sm">{{ __('comptabilite.etats_resultat_net') }}</td><td class="px-md py-sm text-right" data-colonne="n">{{ $f($rn['resultat_net']) }}</td><td class="px-md py-sm text-right" data-colonne="n1">{{ $f($r1['resultat_net'] ?? null) }}</td></tr>
                    </tbody>
                </table>
            </div>
            <p class="text-[11px] text-outline mt-sm max-w-3xl">{{ __('comptabilite.etats_resultat_note') }}</p>
        </div>
    @endif

    @if($tab === 'tafire')
        <div>
            <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden max-w-2xl">
                <div class="px-md py-sm border-b-2 border-brand-emerald bg-brand-emerald/5"><h3 class="text-sm font-bold text-brand-forest uppercase">{{ __('comptabilite.etats_tafire_titre') }}</h3></div>
                <table class="w-full text-xs">
                    <tbody>
                        <tr class="bg-surface-zebra border-b border-outline-variant font-bold"><td class="px-md py-sm" colspan="2">{{ __('comptabilite.etats_tafire_operations') }}</td></tr>
                        <tr class="border-b border-outline-variant"><td class="px-md py-sm pl-lg">{{ __('comptabilite.etats_tafire_resultat_net') }}</td><td class="px-md py-sm text-right">{{ number_format($this->tafire['resultat_net'], 0, ',', ' ') }}</td></tr>
                        <tr class="border-b border-outline-variant"><td class="px-md py-sm pl-lg">{{ __('comptabilite.etats_tafire_dotations') }}</td><td class="px-md py-sm text-right">{{ number_format($this->tafire['dotations'], 0, ',', ' ') }}</td></tr>
                        <tr class="border-b border-outline-variant"><td class="px-md py-sm pl-lg">{{ __('comptabilite.etats_tafire_bfr') }}</td><td class="px-md py-sm text-right">({{ number_format($this->tafire['variation_bfr'], 0, ',', ' ') }})</td></tr>
                        <tr class="bg-accent-yellow/10 border-b border-outline-variant font-bold"><td class="px-md py-sm">{{ __('comptabilite.etats_tafire_flux_exploit') }}</td><td class="px-md py-sm text-right">{{ number_format($this->tafire['flux_exploitation'], 0, ',', ' ') }}</td></tr>
                        <tr class="bg-surface-zebra border-b border-outline-variant font-bold"><td class="px-md py-sm" colspan="2">{{ __('comptabilite.etats_tafire_investissement') }}</td></tr>
                        <tr class="bg-accent-yellow/10 border-b border-outline-variant font-bold"><td class="px-md py-sm">{{ __('comptabilite.etats_tafire_flux_invest') }}</td><td class="px-md py-sm text-right">{{ number_format($this->tafire['flux_investissement'], 0, ',', ' ') }}</td></tr>
                        <tr class="bg-surface-zebra border-b border-outline-variant font-bold"><td class="px-md py-sm" colspan="2">{{ __('comptabilite.etats_tafire_financement') }}</td></tr>
                        <tr class="bg-accent-yellow/10 border-b border-outline-variant font-bold"><td class="px-md py-sm">{{ __('comptabilite.etats_tafire_flux_finance') }}</td><td class="px-md py-sm text-right">{{ number_format($this->tafire['flux_financement'], 0, ',', ' ') }}</td></tr>
                        <tr class="border-b border-outline-variant font-bold"><td class="px-md py-sm">{{ __('comptabilite.etats_tafire_variation') }}</td><td class="px-md py-sm text-right">{{ number_format($this->tafire['variation_tresorerie'], 0, ',', ' ') }}</td></tr>
                        <tr class="border-b border-outline-variant"><td class="px-md py-sm">{{ __('comptabilite.etats_tafire_ouverture') }}</td><td class="px-md py-sm text-right">{{ number_format($this->tafire['tresorerie_ouverture'], 0, ',', ' ') }}</td></tr>
                        <tr class="bg-brand-forest text-white font-extrabold"><td class="px-md py-sm">{{ __('comptabilite.etats_tafire_cloture') }}</td><td class="px-md py-sm text-right">{{ number_format($this->tafire['tresorerie_cloture'], 0, ',', ' ') }} F</td></tr>
                    </tbody>
                </table>
            </div>
            <p class="text-[11px] text-outline mt-sm max-w-2xl">{{ __('comptabilite.etats_tafire_note') }}</p>
            @if($this->tafire['is_coherent'])
                <div class="max-w-2xl mt-sm rounded-lg p-md border border-brand-emerald/30 bg-brand-emerald/5 flex items-center gap-sm">
                    <span class="material-symbols-outlined text-brand-emerald text-[20px]">check_circle</span>
                    <p class="text-xs font-bold text-brand-emerald">{{ __('comptabilite.etats_tafire_coherent', ['montant' => number_format($this->tafire['tresorerie_cloture'], 0, ',', ' ')]) }}</p>
                </div>
            @else
                <div class="max-w-2xl mt-sm rounded-lg p-md border border-error-red/30 bg-error-red/10 flex items-center gap-sm">
                    <span class="material-symbols-outlined text-error-deep text-[20px]">warning</span>
                    <p class="text-xs font-bold text-error-deep">{{ __('comptabilite.etats_tafire_incoherence', ['ecart' => number_format($this->tafire['ecart'], 0, ',', ' '), 'bilan' => number_format($this->tafire['tresorerie_cloture_bilan'], 0, ',', ' ')]) }}</p>
                </div>
            @endif
        </div>
    @endif

    @if($tab === 'notes')
        <div class="space-y-md max-w-3xl">
            <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md">
                <h3 class="text-sm font-bold text-brand-forest mb-xs">{{ __('comptabilite.etats_note1_titre') }}</h3>
                <p class="text-xs text-outline">{{ __('comptabilite.etats_note1_msg') }}</p>
            </div>

            <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md">
                <h3 class="text-sm font-bold text-brand-forest mb-xs">{{ __('comptabilite.etats_note2_titre') }}</h3>
                @if(count($this->registreImmobilisations['lignes']) > 0)
                    <table class="w-full text-xs mt-sm">
                        <thead class="bg-surface-zebra">
                            <tr>
                                <th class="px-sm py-xs text-left">{{ __('comptabilite.etats_note2_nature') }}</th>
                                <th class="px-sm py-xs text-right">{{ __('comptabilite.etats_note2_col_brut') }}</th>
                                <th class="px-sm py-xs text-right">{{ __('comptabilite.etats_note2_col_amort') }}</th>
                                <th class="px-sm py-xs text-right">{{ __('comptabilite.etats_note2_col_net') }}</th>
                            </tr>
                        </thead>
                        <tbody>
                            @foreach($this->registreImmobilisations['lignes'] as $ligne)
                                <tr class="border-t border-outline-variant">
                                    <td class="px-sm py-xs">{{ $ligne['code'] }} — {{ $ligne['label'] }}</td>
                                    <td class="px-sm py-xs text-right">{{ number_format($ligne['brut'], 0, ',', ' ') }}</td>
                                    <td class="px-sm py-xs text-right text-error-deep">{{ $ligne['amortissement'] > 0 ? '−'.number_format($ligne['amortissement'], 0, ',', ' ') : '—' }}</td>
                                    <td class="px-sm py-xs text-right font-bold">{{ number_format($ligne['net'], 0, ',', ' ') }}</td>
                                </tr>
                            @endforeach
                            <tr class="border-t-2 border-brand-forest font-bold">
                                <td class="px-sm py-xs">{{ __('comptabilite.etats_note2_total') }}</td>
                                <td class="px-sm py-xs text-right">{{ number_format($this->registreImmobilisations['brut'], 0, ',', ' ') }}</td>
                                <td class="px-sm py-xs text-right">−{{ number_format($this->registreImmobilisations['amortissement'], 0, ',', ' ') }}</td>
                                <td class="px-sm py-xs text-right">{{ number_format($this->registreImmobilisations['net'], 0, ',', ' ') }}</td>
                            </tr>
                        </tbody>
                    </table>
                    <p class="text-[11px] text-outline mt-xs">
                        {{ __('comptabilite.etats_note2_amort_note') }} <a wire:navigate href="{{ route('comptabilite.immobilisations') }}" class="text-brand-emerald font-bold underline">{{ __('comptabilite.etats_note2_lien') }}</a>{{ __('comptabilite.etats_note2_amort_fin') }}
                    </p>
                    @if(abs($this->registreImmobilisations['net'] - $this->bilan['total_immo']) >= 1)
                        <p class="text-[11px] text-error-deep mt-xs">
                            {{ __('comptabilite.etats_note2_ecart_intro', ['bilan' => number_format($this->bilan['total_immo'], 0, ',', ' '), 'ecart' => number_format($this->registreImmobilisations['net'] - $this->bilan['total_immo'], 0, ',', ' ')]) }}
                            @if($this->registreImmobilisations['hors_compta'] > 0)
                                {{ __('comptabilite.etats_note2_ecart_hors_compta', ['montant' => number_format($this->registreImmobilisations['hors_compta'], 0, ',', ' ')]) }}
                            @else
                                {{ __('comptabilite.etats_note2_ecart_dotation') }}
                            @endif
                        </p>
                    @endif
                @else
                    <table class="w-full text-xs mt-sm">
                        <thead class="bg-surface-zebra"><tr><th class="px-sm py-xs text-left">{{ __('comptabilite.etats_note2_col_compte') }}</th><th class="px-sm py-xs text-right">{{ __('comptabilite.etats_note2_col_solde') }}</th></tr></thead>
                        <tbody>
                            @forelse($this->bilan['immo'] as $ligne)
                                <tr class="border-t border-outline-variant">
                                    <td class="px-sm py-xs">{{ $ligne['code'] }} — {{ $ligne['label'] }}</td>
                                    <td class="px-sm py-xs text-right {{ $ligne['balance'] < 0 ? 'text-error-deep' : '' }}">{{ number_format($ligne['balance'], 0, ',', ' ') }}</td>
                                </tr>
                            @empty
                                <tr class="border-t border-outline-variant"><td class="px-sm py-xs text-outline" colspan="2">{{ __('comptabilite.etats_note2_vide') }}</td></tr>
                            @endforelse
                            <tr class="border-t-2 border-brand-forest font-bold"><td class="px-sm py-xs">{{ __('comptabilite.etats_note2_vnc_totale') }}</td><td class="px-sm py-xs text-right">{{ number_format($this->bilan['total_immo'], 0, ',', ' ') }}</td></tr>
                        </tbody>
                    </table>
                    <p class="text-[11px] text-outline mt-xs">
                        {{ __('comptabilite.etats_note2_sans_registre') }} <a wire:navigate href="{{ route('comptabilite.immobilisations') }}" class="text-brand-emerald font-bold underline">{{ __('comptabilite.etats_note2_lien') }}</a> {{ __('comptabilite.etats_note2_sans_registre_fin') }}
                    </p>
                @endif
            </div>

            <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md">
                <h3 class="text-sm font-bold text-brand-forest mb-xs">{{ __('comptabilite.etats_note3_titre') }}</h3>
                <p class="text-xs text-outline">{{ __('comptabilite.etats_note3_intro') }} <strong>{{ number_format($this->stockValuation['valeur'], 0, ',', ' ') }} FCFA</strong> {{ __('comptabilite.etats_note3_detail', ['nb' => $this->stockValuation['nb_valorises']]) }}
                @if($this->stockValuation['nb_negatifs'] > 0)
                    <span class="block text-error-deep font-bold mt-xs">
                        {{ __('comptabilite.etats_note3_negatifs', ['nb' => $this->stockValuation['nb_negatifs'], 'qte' => rtrim(rtrim(number_format($this->stockValuation['qte_manquante'], 2, ',', ' '), '0'), ',')]) }}
                    </span>
                @endif
                @if($this->stockValuation['nb_sans_pmp'] > 0)
                    {{ __('comptabilite.etats_note3_sans_pmp', ['nb' => $this->stockValuation['nb_sans_pmp']]) }}
                @endif
                </p>
            </div>

            <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md">
                <h3 class="text-sm font-bold text-brand-forest mb-xs">{{ __('comptabilite.etats_note4_titre') }}</h3>
                <table class="w-full text-xs mt-sm">
                    <thead class="bg-surface-zebra"><tr><th class="px-sm py-xs text-left">{{ __('comptabilite.etats_note4_nature') }}</th><th class="px-sm py-xs text-right">{{ __('comptabilite.etats_note4_col_montant') }}</th></tr></thead>
                    <tbody>
                        @foreach($this->bilan['creances'] as $ligne)
                            <tr class="border-t border-outline-variant"><td class="px-sm py-xs">{{ __('comptabilite.etats_note4_creances') }}{{ $ligne['label'] }} ({{ $ligne['code'] }})</td><td class="px-sm py-xs text-right">{{ number_format($ligne['balance'], 0, ',', ' ') }}</td></tr>
                        @endforeach
                        @foreach($this->bilan['dettes'] as $ligne)
                            <tr class="border-t border-outline-variant"><td class="px-sm py-xs">{{ __('comptabilite.etats_note4_dettes') }}{{ $ligne['label'] }} ({{ $ligne['code'] }})</td><td class="px-sm py-xs text-right text-error-deep">{{ number_format($ligne['balance'], 0, ',', ' ') }}</td></tr>
                        @endforeach
                        @if(count($this->bilan['creances']) === 0 && count($this->bilan['dettes']) === 0)
                            <tr class="border-t border-outline-variant"><td class="px-sm py-xs text-outline" colspan="2">{{ __('comptabilite.etats_note4_vide') }}</td></tr>
                        @endif
                    </tbody>
                </table>
            </div>

            <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md">
                <h3 class="text-sm font-bold text-brand-forest mb-xs">{{ __('comptabilite.etats_note5_titre') }}</h3>
                <p class="text-xs text-outline">{{ __('comptabilite.etats_note5_msg') }}</p>
            </div>
        </div>
    @endif
</div>
