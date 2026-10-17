<div>
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md mb-lg">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">receipt_long</span>Déclaration TVA
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">TVA Collectée (4431) et TVA Déductible (4452) — taux 18% (transformés/services) ou 0% (produits bruts, exonéré).</p>
        </div>
        <button type="button" wire:click="exportDeclarationTvaPdf" wire:loading.attr="disabled" wire:target="exportDeclarationTvaPdf" class="flex items-center justify-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full transition-all disabled:opacity-50">
            <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Générer la Déclaration PDF
        </button>
    </div>

    <div class="bg-white border border-outline-variant rounded-lg p-md mb-lg flex flex-wrap items-center gap-sm">
        <label for="tva-periode-select" class="text-[10px] text-brand-forest font-bold uppercase">Période de déclaration :</label>
        <select id="tva-periode-select" wire:model.live="periode" class="text-sm font-bold border border-outline-variant rounded-lg px-md py-2 bg-white focus:ring-2 focus:ring-brand-emerald outline-none">
            @foreach($this->periodes as $value => $label)
                <option value="{{ $value }}">{{ $label }}</option>
            @endforeach
        </select>
        <span class="text-[11px] text-outline">Échéance de dépôt : le {{ $this->echeance }} (DGI Bénin)</span>
    </div>

    <div class="grid grid-cols-1 md:grid-cols-3 gap-md mb-lg">
        <div class="bg-white p-md rounded-lg border border-outline-variant border-l-4 border-l-brand-emerald shadow-sm">
            <span class="text-[10px] text-outline font-bold uppercase block">TVA Collectée (4431)</span>
            <span class="text-lg md:text-2xl font-extrabold block mt-xs">{{ number_format($this->declaration['collectee']['total_tva'], 0, ',', ' ') }} F</span>
        </div>
        <div class="bg-white p-md rounded-lg border border-outline-variant border-l-4 border-l-info-blue shadow-sm">
            <span class="text-[10px] text-outline font-bold uppercase block">TVA Déductible (4452)</span>
            <span class="text-lg md:text-2xl font-extrabold block mt-xs">{{ number_format($this->declaration['deductible']['total_tva'], 0, ',', ' ') }} F</span>
        </div>
        <div class="p-md rounded-lg border shadow-sm {{ $this->declaration['is_credit'] ? 'border-brand-emerald/30 bg-brand-emerald/5' : 'border-error-red/30 bg-error-red/10' }}">
            <span class="text-[10px] text-outline font-bold uppercase block">{{ $this->declaration['is_credit'] ? 'Crédit de TVA reportable' : 'TVA Nette à Payer' }}</span>
            <span class="text-lg md:text-2xl font-extrabold block mt-xs {{ $this->declaration['is_credit'] ? 'text-brand-emerald' : 'text-error-deep' }}">
                {{ number_format($this->declaration['montant_affiche'], 0, ',', ' ') }} F
            </span>
        </div>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden mb-lg">
        <div class="px-md py-sm border-b-2 border-brand-emerald bg-brand-emerald/5"><h3 class="text-sm font-bold text-brand-emerald uppercase">TVA Collectée — Ventes Assujetties</h3></div>
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">N° Facture</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Client</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date</th>
                        <th class="px-md py-sm text-center text-[10px] text-outline font-bold uppercase">Taux</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Montant HT</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">TVA</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Montant TTC</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->declaration['collectee']['rows'] as $i => $row)
                        <tr class="rrow border-b border-outline-variant {{ $i % 2 === 0 ? 'bg-white' : 'bg-surface-zebra' }}">
                            <td data-label="N° Facture" class="px-md py-sm text-xs font-mono">{{ $row['reference'] }}</td>
                            <td data-label="Client" class="px-md py-sm text-xs">{{ $row['tiers'] }}</td>
                            <td data-label="Date" class="px-md py-sm text-xs">{{ \Carbon\Carbon::parse($row['date'])->format('d/m/Y') }}</td>
                            <td data-label="Taux" class="px-md py-sm text-xs text-center">
                                @if($row['rate_label'] === '0% (exonéré)')
                                    <span class="text-outline">{{ $row['rate_label'] }}</span>
                                @else
                                    <span class="font-bold text-brand-emerald">{{ $row['rate_label'] }}</span>
                                @endif
                            </td>
                            <td data-label="Montant HT" class="px-md py-sm text-xs text-right">{{ number_format($row['ht'], 0, ',', ' ') }}</td>
                            <td data-label="TVA" class="px-md py-sm text-xs text-right font-bold text-brand-emerald">{{ $row['tva'] > 0 ? number_format($row['tva'], 0, ',', ' ') : '—' }}</td>
                            <td data-label="Montant TTC" class="px-md py-sm text-xs text-right">{{ number_format($row['ttc'], 0, ',', ' ') }}</td>
                        </tr>
                    @empty
                        <tr><td colspan="7" class="px-md py-lg text-center text-outline">Aucune facture transmise sur cette période.</td></tr>
                    @endforelse
                </tbody>
                @if(count($this->declaration['collectee']['rows']) > 0)
                    <tfoot>
                        <tr class="bg-brand-forest text-white font-bold">
                            <td class="px-md py-sm text-xs" colspan="4">TOTAL VENTES ASSUJETTIES</td>
                            <td class="px-md py-sm text-xs text-right">{{ number_format($this->declaration['collectee']['total_ht'], 0, ',', ' ') }}</td>
                            <td class="px-md py-sm text-xs text-right">{{ number_format($this->declaration['collectee']['total_tva'], 0, ',', ' ') }}</td>
                            <td class="px-md py-sm text-xs text-right">{{ number_format($this->declaration['collectee']['total_ttc'], 0, ',', ' ') }}</td>
                        </tr>
                    </tfoot>
                @endif
            </table>
        </div>
        <p class="text-[11px] text-outline p-sm border-t border-outline-variant">Factures issues de <a href="{{ route('facturation.index') }}" class="text-brand-emerald underline font-semibold">Facturation &amp; MeCeF</a> — seules les factures au statut « Transmise » sont retenues dans la déclaration. Une facture en erreur MeCeF n'a pas été transmise à la DGI et ne peut donc pas être déclarée.</p>
    </div>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden mb-lg">
        <div class="px-md py-sm border-b-2 border-info-blue bg-info-blue/5"><h3 class="text-sm font-bold text-info-blue uppercase">TVA Déductible — Achats Assujettis</h3></div>
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Référence</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Fournisseur</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date</th>
                        <th class="px-md py-sm text-center text-[10px] text-outline font-bold uppercase">Taux</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Montant HT</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">TVA</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Montant TTC</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->declaration['deductible']['rows'] as $i => $row)
                        <tr class="rrow border-b border-outline-variant {{ $i % 2 === 0 ? 'bg-white' : 'bg-surface-zebra' }}">
                            <td data-label="Référence" class="px-md py-sm text-xs font-mono">{{ $row['reference'] }}</td>
                            <td data-label="Fournisseur" class="px-md py-sm text-xs">{{ $row['tiers'] }}</td>
                            <td data-label="Date" class="px-md py-sm text-xs">{{ \Carbon\Carbon::parse($row['date'])->format('d/m/Y') }}</td>
                            <td data-label="Taux" class="px-md py-sm text-xs text-center">
                                @if($row['rate_label'] === '0% (exonéré)')
                                    <span class="text-outline">{{ $row['rate_label'] }}</span>
                                @else
                                    <span class="font-bold text-info-blue">{{ $row['rate_label'] }}</span>
                                @endif
                            </td>
                            <td data-label="Montant HT" class="px-md py-sm text-xs text-right">{{ number_format($row['ht'], 0, ',', ' ') }}</td>
                            <td data-label="TVA" class="px-md py-sm text-xs text-right font-bold text-info-blue">{{ $row['tva'] > 0 ? number_format($row['tva'], 0, ',', ' ') : '—' }}</td>
                            <td data-label="Montant TTC" class="px-md py-sm text-xs text-right">{{ number_format($row['ttc'], 0, ',', ' ') }}</td>
                        </tr>
                    @empty
                        <tr><td colspan="7" class="px-md py-lg text-center text-outline">Aucun achat enregistré sur cette période.</td></tr>
                    @endforelse
                </tbody>
                @if(count($this->declaration['deductible']['rows']) > 0)
                    <tfoot>
                        <tr class="bg-brand-forest text-white font-bold">
                            <td class="px-md py-sm text-xs" colspan="4">TOTAL ACHATS ASSUJETTIS</td>
                            <td class="px-md py-sm text-xs text-right">{{ number_format($this->declaration['deductible']['total_ht'], 0, ',', ' ') }}</td>
                            <td class="px-md py-sm text-xs text-right">{{ number_format($this->declaration['deductible']['total_tva'], 0, ',', ' ') }}</td>
                            <td class="px-md py-sm text-xs text-right">{{ number_format($this->declaration['deductible']['total_ttc'], 0, ',', ' ') }}</td>
                        </tr>
                    </tfoot>
                @endif
            </table>
        </div>
        <p class="text-[11px] text-outline p-sm border-t border-outline-variant">Achats issus du module <a href="{{ route('achats.commandes-hub') }}" class="text-info-blue underline font-semibold">Achats &amp; Commandes</a>.</p>
    </div>

    <div class="bg-info-blue/10 border border-info-blue/30 rounded-lg p-md flex items-start gap-sm text-xs">
        <span class="material-symbols-outlined text-info-blue text-[18px] flex-shrink-0">info</span>
        <p class="text-on-surface">Le taux appliqué à chaque ligne provient du champ <strong>TVA du produit</strong> (fiche produit), jamais d'une hypothèse : 18% pour les produits transformés et les services, 0% pour les produits bruts exonérés. Une facture mêlant les deux est affichée comme « mixte », le détail restant consultable ligne par ligne sur la facture.</p>
    </div>
</div>
