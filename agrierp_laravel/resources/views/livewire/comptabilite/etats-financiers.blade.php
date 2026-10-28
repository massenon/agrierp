<div>
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">description</span>États Financiers
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">Bilan, Compte de Résultat, Tableau des Flux de Trésorerie et Notes Annexes — conformité SYSCOHADA.</p>
        </div>
        <button type="button" wire:click="exportEtatActifPdf" wire:loading.attr="disabled" wire:target="exportEtatActifPdf" class="flex items-center justify-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full transition-all disabled:opacity-50">
            <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Exporter PDF (Onglet Actif)
        </button>
    </div>

    <x-anouveaux-provisoires :ouverture="$this->bilan['ouverture']" />

    <div class="flex items-center gap-xs border-b border-outline-variant mb-md overflow-x-auto">
        @foreach(['bilan' => 'Bilan', 'resultat' => 'Compte de Résultat', 'tafire' => 'Flux de Trésorerie', 'notes' => 'Notes Annexes'] as $key => $label)
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
                        <span class="material-symbols-outlined text-[14px] align-middle">check_circle</span> Bilan Équilibré
                    </span>
                @else
                    <span class="text-[11px] font-bold px-sm py-1 rounded-full bg-error-red/10 text-error-deep">
                        <span class="material-symbols-outlined text-[14px] align-middle">warning</span> Écart de {{ number_format(abs($bn['total_actif'] - $bn['total_passif']), 0, ',', ' ') }} F
                    </span>
                @endif
            </div>

            <div class="grid grid-cols-1 lg:grid-cols-2 gap-md">
                <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
                    <div class="px-md py-sm border-b-2 border-brand-emerald bg-brand-emerald/5"><h3 class="text-sm font-bold text-brand-emerald uppercase">Actif (Emplois)</h3></div>
                    <table class="w-full text-xs">
                        <thead>
                            <tr class="border-b border-outline-variant text-[10px] text-outline uppercase">
                                <th class="px-md py-sm"></th>
                                <th class="px-md py-sm text-right">{{ \App\Support\ComparatifNMoinsUn::ENTETE_N }}<span class="block normal-case font-normal">{{ \App\Support\ComparatifNMoinsUn::sousTitre($c['exercice_n']) }}</span></th>
                                <th class="px-md py-sm text-right">{{ \App\Support\ComparatifNMoinsUn::ENTETE_N1 }}<span class="block normal-case font-normal">{{ \App\Support\ComparatifNMoinsUn::sousTitre($c['exercice_n1']) }}</span></th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr class="border-b border-outline-variant"><td class="px-md py-sm font-bold text-brand-forest uppercase text-[10px]" colspan="3">Actif Immobilisé (Classe 2)</td></tr>
                            @foreach($c['lignes']['immo'] as $ligne)
                                <tr class="border-b border-outline-variant">
                                    <td class="px-md py-sm pl-lg text-outline">{{ $ligne['code'] }} — {{ $ligne['label'] }}</td>
                                    <td class="px-md py-sm text-right {{ $ligne['n'] < 0 ? 'text-error-deep' : '' }}" data-colonne="n">{{ $m($ligne['n']) }}</td>
                                    <td class="px-md py-sm text-right text-outline" data-colonne="n1">{{ $m($ligne['n1']) }}</td>
                                </tr>
                            @endforeach
                            <tr class="bg-surface-zebra border-b border-outline-variant"><td class="px-md py-sm font-bold text-brand-forest">Sous-total Immobilisé</td><td class="px-md py-sm text-right font-bold text-brand-forest" data-colonne="n">{{ $m($bn['total_immo']) }}</td><td class="px-md py-sm text-right font-bold text-brand-forest" data-colonne="n1">{{ $m($b1['total_immo'] ?? null) }}</td></tr>

                            <tr class="border-b border-outline-variant"><td class="px-md py-sm font-bold text-brand-forest uppercase text-[10px]" colspan="3">Actif Circulant (Classes 3 &amp; 4)</td></tr>
                            @foreach(array_merge($c['lignes']['stocks'], $c['lignes']['creances']) as $ligne)
                                <tr class="border-b border-outline-variant"><td class="px-md py-sm pl-lg text-outline">{{ $ligne['code'] }} — {{ $ligne['label'] }}</td><td class="px-md py-sm text-right" data-colonne="n">{{ $m($ligne['n']) }}</td><td class="px-md py-sm text-right text-outline" data-colonne="n1">{{ $m($ligne['n1']) }}</td></tr>
                            @endforeach
                            <tr class="bg-surface-zebra border-b border-outline-variant"><td class="px-md py-sm font-bold text-brand-forest">Sous-total Circulant</td><td class="px-md py-sm text-right font-bold text-brand-forest" data-colonne="n">{{ $m($bn['total_circulant']) }}</td><td class="px-md py-sm text-right font-bold text-brand-forest" data-colonne="n1">{{ $m($b1['total_circulant'] ?? null) }}</td></tr>

                            <tr class="border-b border-outline-variant"><td class="px-md py-sm font-bold text-brand-forest uppercase text-[10px]" colspan="3">Trésorerie Actif (Classe 5)</td></tr>
                            @foreach($c['lignes']['tresorerie'] as $ligne)
                                <tr class="border-b border-outline-variant"><td class="px-md py-sm pl-lg text-outline">{{ $ligne['code'] }} — {{ $ligne['label'] }}</td><td class="px-md py-sm text-right" data-colonne="n">{{ $m($ligne['n']) }}</td><td class="px-md py-sm text-right text-outline" data-colonne="n1">{{ $m($ligne['n1']) }}</td></tr>
                            @endforeach
                            <tr class="bg-surface-zebra"><td class="px-md py-sm font-bold text-brand-forest">Sous-total Trésorerie</td><td class="px-md py-sm text-right font-bold text-brand-forest" data-colonne="n">{{ $m($bn['total_tresorerie']) }}</td><td class="px-md py-sm text-right font-bold text-brand-forest" data-colonne="n1">{{ $m($b1['total_tresorerie'] ?? null) }}</td></tr>
                        </tbody>
                        <tfoot>
                            <tr class="bg-surface-zebra border-t-2 border-brand-forest">
                                <td class="px-md py-sm font-black text-brand-forest uppercase">Total Actif</td>
                                <td class="px-md py-sm font-black text-brand-emerald text-right" data-colonne="n">{{ $f($bn['total_actif']) }}</td>
                                <td class="px-md py-sm font-black text-outline text-right" data-colonne="n1">{{ $f($b1['total_actif'] ?? null) }}</td>
                            </tr>
                        </tfoot>
                    </table>
                </div>

                <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
                    <div class="px-md py-sm border-b-2 border-info-blue bg-info-blue/5"><h3 class="text-sm font-bold text-info-blue uppercase">Passif (Ressources)</h3></div>
                    <table class="w-full text-xs">
                        <thead>
                            <tr class="border-b border-outline-variant text-[10px] text-outline uppercase">
                                <th class="px-md py-sm"></th>
                                <th class="px-md py-sm text-right">{{ \App\Support\ComparatifNMoinsUn::ENTETE_N }}<span class="block normal-case font-normal">{{ \App\Support\ComparatifNMoinsUn::sousTitre($c['exercice_n']) }}</span></th>
                                <th class="px-md py-sm text-right">{{ \App\Support\ComparatifNMoinsUn::ENTETE_N1 }}<span class="block normal-case font-normal">{{ \App\Support\ComparatifNMoinsUn::sousTitre($c['exercice_n1']) }}</span></th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr class="border-b border-outline-variant"><td class="px-md py-sm font-bold text-brand-forest uppercase text-[10px]" colspan="3">Capitaux Propres (Classe 1)</td></tr>
                            @foreach($c['lignes']['capitaux'] as $ligne)
                                <tr class="border-b border-outline-variant"><td class="px-md py-sm pl-lg text-outline">{{ $ligne['code'] }} — {{ $ligne['label'] }}</td><td class="px-md py-sm text-right" data-colonne="n">{{ $m(-$ligne['n']) }}</td><td class="px-md py-sm text-right text-outline" data-colonne="n1">{{ $m($neg($ligne['n1'])) }}</td></tr>
                            @endforeach
                            <tr class="border-b border-outline-variant"><td class="px-md py-sm pl-lg text-outline">Résultat de l'Exercice</td><td class="px-md py-sm text-right font-bold text-brand-emerald" data-colonne="n">{{ $m($bn['resultat']) }}</td><td class="px-md py-sm text-right font-bold text-outline" data-colonne="n1">{{ $m($b1['resultat'] ?? null) }}</td></tr>
                            <tr class="bg-surface-zebra border-b border-outline-variant"><td class="px-md py-sm font-bold text-brand-forest">Sous-total Capitaux Propres</td><td class="px-md py-sm text-right font-bold text-brand-forest" data-colonne="n">{{ $m($bn['total_capitaux'] + $bn['resultat']) }}</td><td class="px-md py-sm text-right font-bold text-brand-forest" data-colonne="n1">{{ $m($b1 === null ? null : $b1['total_capitaux'] + $b1['resultat']) }}</td></tr>

                            <tr class="border-b border-outline-variant"><td class="px-md py-sm font-bold text-brand-forest uppercase text-[10px]" colspan="3">Dettes (Classe 4)</td></tr>
                            @foreach($c['lignes']['dettes'] as $ligne)
                                <tr class="border-b border-outline-variant"><td class="px-md py-sm pl-lg text-outline">{{ $ligne['code'] }} — {{ $ligne['label'] }}</td><td class="px-md py-sm text-right" data-colonne="n">{{ $m($ligne['n']) }}</td><td class="px-md py-sm text-right text-outline" data-colonne="n1">{{ $m($ligne['n1']) }}</td></tr>
                            @endforeach
                            <tr class="bg-surface-zebra"><td class="px-md py-sm font-bold text-brand-forest">Sous-total Dettes</td><td class="px-md py-sm text-right font-bold text-brand-forest" data-colonne="n">{{ $m($bn['total_dettes']) }}</td><td class="px-md py-sm text-right font-bold text-brand-forest" data-colonne="n1">{{ $m($b1['total_dettes'] ?? null) }}</td></tr>
                        </tbody>
                        <tfoot>
                            <tr class="bg-surface-zebra border-t-2 border-brand-forest">
                                <td class="px-md py-sm font-black text-brand-forest uppercase">Total Passif</td>
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
                <div class="px-md py-sm border-b-2 border-brand-emerald bg-brand-emerald/5"><h3 class="text-sm font-bold text-brand-forest uppercase">Compte de Résultat — Structure en Cascade SYSCOHADA</h3></div>
                <table class="w-full text-xs">
                    <thead>
                        <tr class="border-b border-outline-variant text-[10px] text-outline uppercase">
                            <th class="px-md py-sm"></th>
                            <th class="px-md py-sm text-right">{{ \App\Support\ComparatifNMoinsUn::ENTETE_N }}<span class="block normal-case font-normal">{{ \App\Support\ComparatifNMoinsUn::sousTitre($cr['exercice_n']) }}</span></th>
                            <th class="px-md py-sm text-right">{{ \App\Support\ComparatifNMoinsUn::ENTETE_N1 }}<span class="block normal-case font-normal">{{ \App\Support\ComparatifNMoinsUn::sousTitre($cr['exercice_n1']) }}</span></th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr class="border-b border-outline-variant"><td class="px-md py-sm">Ventes (Aviculture, Cuniculture, Porciculture)</td><td class="px-md py-sm text-right" data-colonne="n">{{ $m($rn['ventes']) }}</td><td class="px-md py-sm text-right text-outline" data-colonne="n1">{{ $m($r1['ventes'] ?? null) }}</td></tr>
                        <tr class="border-b border-outline-variant"><td class="px-md py-sm">− Achats (Aliments, Intrants)</td><td class="px-md py-sm text-right text-error-deep" data-colonne="n">{{ $p($rn['achats']) }}</td><td class="px-md py-sm text-right text-error-deep" data-colonne="n1">{{ $p($r1['achats'] ?? null) }}</td></tr>
                        <tr class="bg-surface-zebra border-b border-outline-variant font-bold"><td class="px-md py-sm">= MARGE COMMERCIALE</td><td class="px-md py-sm text-right" data-colonne="n">{{ $m($rn['marge_commerciale']) }}</td><td class="px-md py-sm text-right" data-colonne="n1">{{ $m($r1['marge_commerciale'] ?? null) }}</td></tr>
                        <tr class="border-b border-outline-variant"><td class="px-md py-sm">− Charges de Personnel</td><td class="px-md py-sm text-right text-error-deep" data-colonne="n">{{ $p($rn['charges_personnel']) }}</td><td class="px-md py-sm text-right text-error-deep" data-colonne="n1">{{ $p($r1['charges_personnel'] ?? null) }}</td></tr>
                        <tr class="bg-surface-zebra border-b border-outline-variant font-bold"><td class="px-md py-sm">= EXCÉDENT BRUT D'EXPLOITATION</td><td class="px-md py-sm text-right" data-colonne="n">{{ $m($rn['ebe']) }}</td><td class="px-md py-sm text-right" data-colonne="n1">{{ $m($r1['ebe'] ?? null) }}</td></tr>
                        <tr class="border-b border-outline-variant"><td class="px-md py-sm">− Dotations aux Amortissements</td><td class="px-md py-sm text-right text-error-deep" data-colonne="n">{{ $p($rn['dotations']) }}</td><td class="px-md py-sm text-right text-error-deep" data-colonne="n1">{{ $p($r1['dotations'] ?? null) }}</td></tr>
                        <tr class="bg-surface-zebra border-b border-outline-variant font-bold"><td class="px-md py-sm">= RÉSULTAT D'EXPLOITATION</td><td class="px-md py-sm text-right" data-colonne="n">{{ $m($rn['resultat_exploitation']) }}</td><td class="px-md py-sm text-right" data-colonne="n1">{{ $m($r1['resultat_exploitation'] ?? null) }}</td></tr>
                        <tr class="border-b border-outline-variant"><td class="px-md py-sm">+ Résultat Financier</td><td class="px-md py-sm text-right" data-colonne="n">{{ $m($rn['resultat_financier']) }}</td><td class="px-md py-sm text-right" data-colonne="n1">{{ $m($r1['resultat_financier'] ?? null) }}</td></tr>
                        <tr class="bg-surface-zebra border-b border-outline-variant font-bold"><td class="px-md py-sm">= RÉSULTAT DES ACTIVITÉS ORDINAIRES (RAO)</td><td class="px-md py-sm text-right" data-colonne="n">{{ $m($rn['rao']) }}</td><td class="px-md py-sm text-right" data-colonne="n1">{{ $m($r1['rao'] ?? null) }}</td></tr>
                        <tr class="border-b border-outline-variant"><td class="px-md py-sm">+ Résultat Hors Activités Ordinaires (charges diverses de gestion)</td><td class="px-md py-sm text-right text-error-deep" data-colonne="n">{{ $p($rn['autres_charges']) }}</td><td class="px-md py-sm text-right text-error-deep" data-colonne="n1">{{ $p($r1['autres_charges'] ?? null) }}</td></tr>
                        <tr class="bg-brand-forest text-white font-extrabold"><td class="px-md py-sm">= RÉSULTAT NET DE L'EXERCICE</td><td class="px-md py-sm text-right" data-colonne="n">{{ $f($rn['resultat_net']) }}</td><td class="px-md py-sm text-right" data-colonne="n1">{{ $f($r1['resultat_net'] ?? null) }}</td></tr>
                    </tbody>
                </table>
            </div>
            <p class="text-[11px] text-outline mt-sm max-w-3xl">Le Résultat Net de l'Exercice ci-dessus est calculé depuis la même source que celui affiché au Bilan — les deux valeurs sont toujours strictement identiques.</p>
        </div>
    @endif

    @if($tab === 'tafire')
        <div>
            <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden max-w-2xl">
                <div class="px-md py-sm border-b-2 border-brand-emerald bg-brand-emerald/5"><h3 class="text-sm font-bold text-brand-forest uppercase">Tableau des Flux de Trésorerie (TAFIRE simplifié)</h3></div>
                <table class="w-full text-xs">
                    <tbody>
                        <tr class="bg-surface-zebra border-b border-outline-variant font-bold"><td class="px-md py-sm" colspan="2">FLUX LIÉS AUX ACTIVITÉS OPÉRATIONNELLES</td></tr>
                        <tr class="border-b border-outline-variant"><td class="px-md py-sm pl-lg">Résultat Net de l'Exercice</td><td class="px-md py-sm text-right">{{ number_format($this->tafire['resultat_net'], 0, ',', ' ') }}</td></tr>
                        <tr class="border-b border-outline-variant"><td class="px-md py-sm pl-lg">+ Dotations aux Amortissements</td><td class="px-md py-sm text-right">{{ number_format($this->tafire['dotations'], 0, ',', ' ') }}</td></tr>
                        <tr class="border-b border-outline-variant"><td class="px-md py-sm pl-lg">− Variation du BFR</td><td class="px-md py-sm text-right">({{ number_format($this->tafire['variation_bfr'], 0, ',', ' ') }})</td></tr>
                        <tr class="bg-accent-yellow/10 border-b border-outline-variant font-bold"><td class="px-md py-sm">= FLUX NET D'EXPLOITATION</td><td class="px-md py-sm text-right">{{ number_format($this->tafire['flux_exploitation'], 0, ',', ' ') }}</td></tr>
                        <tr class="bg-surface-zebra border-b border-outline-variant font-bold"><td class="px-md py-sm" colspan="2">FLUX LIÉS AUX ACTIVITÉS D'INVESTISSEMENT</td></tr>
                        <tr class="bg-accent-yellow/10 border-b border-outline-variant font-bold"><td class="px-md py-sm">= FLUX NET D'INVESTISSEMENT</td><td class="px-md py-sm text-right">{{ number_format($this->tafire['flux_investissement'], 0, ',', ' ') }}</td></tr>
                        <tr class="bg-surface-zebra border-b border-outline-variant font-bold"><td class="px-md py-sm" colspan="2">FLUX LIÉS AUX ACTIVITÉS DE FINANCEMENT</td></tr>
                        <tr class="bg-accent-yellow/10 border-b border-outline-variant font-bold"><td class="px-md py-sm">= FLUX NET DE FINANCEMENT</td><td class="px-md py-sm text-right">{{ number_format($this->tafire['flux_financement'], 0, ',', ' ') }}</td></tr>
                        <tr class="border-b border-outline-variant font-bold"><td class="px-md py-sm">VARIATION DE TRÉSORERIE</td><td class="px-md py-sm text-right">{{ number_format($this->tafire['variation_tresorerie'], 0, ',', ' ') }}</td></tr>
                        <tr class="border-b border-outline-variant"><td class="px-md py-sm">Trésorerie à l'Ouverture</td><td class="px-md py-sm text-right">{{ number_format($this->tafire['tresorerie_ouverture'], 0, ',', ' ') }}</td></tr>
                        <tr class="bg-brand-forest text-white font-extrabold"><td class="px-md py-sm">TRÉSORERIE À LA CLÔTURE</td><td class="px-md py-sm text-right">{{ number_format($this->tafire['tresorerie_cloture'], 0, ',', ' ') }} F</td></tr>
                    </tbody>
                </table>
            </div>
            <p class="text-[11px] text-outline mt-sm max-w-2xl">La Trésorerie à la Clôture doit être égale à la Trésorerie-Actif du Bilan (onglet Bilan) — vérification automatique ci-dessous.</p>
            @if($this->tafire['is_coherent'])
                <div class="max-w-2xl mt-sm rounded-lg p-md border border-brand-emerald/30 bg-brand-emerald/5 flex items-center gap-sm">
                    <span class="material-symbols-outlined text-brand-emerald text-[20px]">check_circle</span>
                    <p class="text-xs font-bold text-brand-emerald">Cohérence vérifiée : Trésorerie à la Clôture ({{ number_format($this->tafire['tresorerie_cloture'], 0, ',', ' ') }} F) = Trésorerie-Actif du Bilan.</p>
                </div>
            @else
                <div class="max-w-2xl mt-sm rounded-lg p-md border border-error-red/30 bg-error-red/10 flex items-center gap-sm">
                    <span class="material-symbols-outlined text-error-deep text-[20px]">warning</span>
                    <p class="text-xs font-bold text-error-deep">Incohérence détectée : écart de {{ number_format($this->tafire['ecart'], 0, ',', ' ') }} F entre la Trésorerie à la Clôture dérivée des flux et la Trésorerie-Actif du Bilan ({{ number_format($this->tafire['tresorerie_cloture_bilan'], 0, ',', ' ') }} F).</p>
                </div>
            @endif
        </div>
    @endif

    @if($tab === 'notes')
        <div class="space-y-md max-w-3xl">
            <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md">
                <h3 class="text-sm font-bold text-brand-forest mb-xs">Note 1 — Méthodes Comptables</h3>
                <p class="text-xs text-outline">Les immobilisations sont amorties selon la méthode linéaire. Les stocks (aliments, produits vétérinaires, produits finis) sont valorisés au Prix Moyen Pondéré (PMP). La monnaie de présentation est le Franc CFA (FCFA), sans décimale.</p>
            </div>

            <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md">
                <h3 class="text-sm font-bold text-brand-forest mb-xs">Note 2 — Immobilisations</h3>
                @if(count($this->registreImmobilisations['lignes']) > 0)
                    <table class="w-full text-xs mt-sm">
                        <thead class="bg-surface-zebra">
                            <tr>
                                <th class="px-sm py-xs text-left">Nature d'actif</th>
                                <th class="px-sm py-xs text-right">Valeur Brute</th>
                                <th class="px-sm py-xs text-right">Amortissement</th>
                                <th class="px-sm py-xs text-right">Valeur Nette</th>
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
                                <td class="px-sm py-xs">Total Registre</td>
                                <td class="px-sm py-xs text-right">{{ number_format($this->registreImmobilisations['brut'], 0, ',', ' ') }}</td>
                                <td class="px-sm py-xs text-right">−{{ number_format($this->registreImmobilisations['amortissement'], 0, ',', ' ') }}</td>
                                <td class="px-sm py-xs text-right">{{ number_format($this->registreImmobilisations['net'], 0, ',', ' ') }}</td>
                            </tr>
                        </tbody>
                    </table>
                    <p class="text-[11px] text-outline mt-xs">
                        Ventilation issue du <a wire:navigate href="{{ route('comptabilite.immobilisations') }}" class="text-brand-emerald font-bold underline">registre des immobilisations</a>, amortissement linéaire au prorata des mois écoulés.
                    </p>
                    @if(abs($this->registreImmobilisations['net'] - $this->bilan['total_immo']) >= 1)
                        <p class="text-[11px] text-error-deep mt-xs">
                            Actif Immobilisé au Bilan : {{ number_format($this->bilan['total_immo'], 0, ',', ' ') }} FCFA, soit un écart de
                            {{ number_format($this->registreImmobilisations['net'] - $this->bilan['total_immo'], 0, ',', ' ') }} FCFA avec ce registre.
                            @if($this->registreImmobilisations['hors_compta'] > 0)
                                Il s'explique par {{ number_format($this->registreImmobilisations['hors_compta'], 0, ',', ' ') }} FCFA de biens saisis en reprise d'antériorité, jamais portés à l'actif.
                            @else
                                Une dotation aux amortissements reste probablement à passer.
                            @endif
                        </p>
                    @endif
                @else
                    <table class="w-full text-xs mt-sm">
                        <thead class="bg-surface-zebra"><tr><th class="px-sm py-xs text-left">Compte</th><th class="px-sm py-xs text-right">Solde</th></tr></thead>
                        <tbody>
                            @forelse($this->bilan['immo'] as $ligne)
                                <tr class="border-t border-outline-variant">
                                    <td class="px-sm py-xs">{{ $ligne['code'] }} — {{ $ligne['label'] }}</td>
                                    <td class="px-sm py-xs text-right {{ $ligne['balance'] < 0 ? 'text-error-deep' : '' }}">{{ number_format($ligne['balance'], 0, ',', ' ') }}</td>
                                </tr>
                            @empty
                                <tr class="border-t border-outline-variant"><td class="px-sm py-xs text-outline" colspan="2">Aucune immobilisation enregistrée à ce jour.</td></tr>
                            @endforelse
                            <tr class="border-t-2 border-brand-forest font-bold"><td class="px-sm py-xs">Valeur Nette Totale</td><td class="px-sm py-xs text-right">{{ number_format($this->bilan['total_immo'], 0, ',', ' ') }}</td></tr>
                        </tbody>
                    </table>
                    <p class="text-[11px] text-outline mt-xs">
                        Aucun bien au registre : la note retombe sur les soldes de classe 2 du grand livre, sans ventilation par nature d'actif.
                        Renseignez le <a wire:navigate href="{{ route('comptabilite.immobilisations') }}" class="text-brand-emerald font-bold underline">registre des immobilisations</a> pour l'obtenir.
                    </p>
                @endif
            </div>

            <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md">
                <h3 class="text-sm font-bold text-brand-forest mb-xs">Note 3 — Stocks</h3>
                <p class="text-xs text-outline">Stock global valorisé au Prix Moyen Pondéré (PMP) : <strong>{{ number_format($this->stockValuation['valeur'], 0, ',', ' ') }} FCFA</strong> sur {{ $this->stockValuation['nb_valorises'] }} produit(s) disposant d'un historique d'achat.
                @if($this->stockValuation['nb_negatifs'] > 0)
                    <span class="block text-error-deep font-bold mt-xs">
                        {{ $this->stockValuation['nb_negatifs'] }} produit(s) en stock négatif
                        ({{ rtrim(rtrim(number_format($this->stockValuation['qte_manquante'], 2, ',', ' '), '0'), ',') }} unité(s) manquantes)
                        sont retenus à zéro dans cette valorisation : un actif ne peut pas être négatif.
                        Il s'agit d'entrées non saisies, à régulariser par un ajustement de stock.
                    </span>
                @endif
                @if($this->stockValuation['nb_sans_pmp'] > 0)
                    {{ $this->stockValuation['nb_sans_pmp'] }} produit(s) sans historique d'achat (sujets nés à la ferme, œufs) n'ont pas de PMP calculable et sont exclus de cette valorisation plutôt que remplacés par une estimation.
                @endif
                </p>
            </div>

            <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md">
                <h3 class="text-sm font-bold text-brand-forest mb-xs">Note 4 — Créances et Dettes</h3>
                <table class="w-full text-xs mt-sm">
                    <thead class="bg-surface-zebra"><tr><th class="px-sm py-xs text-left">Nature</th><th class="px-sm py-xs text-right">Montant</th></tr></thead>
                    <tbody>
                        @foreach($this->bilan['creances'] as $ligne)
                            <tr class="border-t border-outline-variant"><td class="px-sm py-xs">Créances — {{ $ligne['label'] }} ({{ $ligne['code'] }})</td><td class="px-sm py-xs text-right">{{ number_format($ligne['balance'], 0, ',', ' ') }}</td></tr>
                        @endforeach
                        @foreach($this->bilan['dettes'] as $ligne)
                            <tr class="border-t border-outline-variant"><td class="px-sm py-xs">Dettes — {{ $ligne['label'] }} ({{ $ligne['code'] }})</td><td class="px-sm py-xs text-right text-error-deep">{{ number_format($ligne['balance'], 0, ',', ' ') }}</td></tr>
                        @endforeach
                        @if(count($this->bilan['creances']) === 0 && count($this->bilan['dettes']) === 0)
                            <tr class="border-t border-outline-variant"><td class="px-sm py-xs text-outline" colspan="2">Aucune créance ni dette à la date de situation.</td></tr>
                        @endif
                    </tbody>
                </table>
            </div>

            <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md">
                <h3 class="text-sm font-bold text-brand-forest mb-xs">Note 5 — Engagements Hors Bilan</h3>
                <p class="text-xs text-outline">Néant à la date de clôture de la période présentée.</p>
            </div>
        </div>
    @endif
</div>
