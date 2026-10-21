<div>
    <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md mb-lg flex flex-col sm:flex-row items-start sm:items-center gap-md">
        <div class="w-20 h-20 rounded-lg bg-brand-emerald/10 flex items-center justify-center flex-shrink-0 border-2 border-dashed border-brand-emerald/30">
            <span class="material-symbols-outlined text-brand-emerald" style="font-size:36px;">pets</span>
        </div>
        <div class="flex-1 min-w-0">
            <div class="flex items-center gap-sm flex-wrap">
                <h2 class="text-xl font-bold text-on-surface">Sujet #{{ $animal->identifier }}</h2>
                @if($animal->isPresent())
                    <span class="text-[11px] font-bold px-sm py-0.5 rounded-full bg-brand-emerald/10 text-brand-emerald">Actif — {{ ucfirst($animal->category) }}</span>
                @else
                    <span class="text-[11px] font-bold px-sm py-0.5 rounded-full bg-error-red/10 text-error-deep">{{ $animal->status_label }}</span>
                @endif
            </div>
            <p class="text-xs text-outline mt-xs">
                {{ $animal->species?->label ?? '—' }}
                @if($animal->breed) · Race {{ $animal->breed }} @endif
                · {{ $animal->sex === 'F' ? 'Femelle' : 'Mâle' }}
                @if($animal->lot) · Lot <a href="{{ route('elevage.bandes') }}" class="text-brand-emerald underline font-semibold">{{ $animal->lot->code }}</a> @endif
                @if($animal->cage) · Cage {{ $animal->cage }} @endif
            </p>
        </div>
        <div class="flex items-center gap-xs flex-shrink-0">
            <button type="button" wire:click="exportFicheAnimalPdf" wire:loading.attr="disabled" wire:target="exportFicheAnimalPdf" class="flex items-center justify-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-sm rounded-full transition-all disabled:opacity-50">
                <span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>Exporter PDF
            </button>
        </div>
    </div>

    <div class="flex items-center gap-xs border-b border-outline-variant mb-md overflow-x-auto">
        @foreach(['general' => 'Général', 'historique' => 'Historique', 'alimentation' => 'Alimentation', 'vaccins' => 'Vaccins', 'reproduction' => 'Reproduction', 'production' => 'Production', 'mouvements' => 'Mouvements', 'documents' => 'Documents'] as $key => $label)
            <button type="button" wire:click="switchTab('{{ $key }}')" class="px-md py-2.5 text-xs font-bold border-b-2 whitespace-nowrap {{ $tab === $key ? 'border-brand-emerald text-brand-emerald' : 'border-transparent text-outline' }}">{{ $label }}</button>
        @endforeach
    </div>

    @if($tab === 'general')
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-md">
            <div class="lg:col-span-2 bg-white rounded-lg border border-outline-variant shadow-sm p-md">
                <h3 class="text-sm font-bold text-brand-forest mb-md flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">badge</span>Identification</h3>
                <div class="grid grid-cols-2 gap-md text-xs">
                    <div><p class="text-outline uppercase text-[10px] font-bold">N° Identification</p><p class="font-bold mt-1">{{ $animal->identifier }}</p></div>
                    <div><p class="text-outline uppercase text-[10px] font-bold">Espèce</p><p class="font-bold mt-1">{{ $animal->species?->label ?? '—' }}</p></div>
                    <div><p class="text-outline uppercase text-[10px] font-bold">Catégorie</p><p class="font-bold mt-1">{{ ucfirst($animal->category) }}</p></div>
                    <div><p class="text-outline uppercase text-[10px] font-bold">Race</p><p class="font-bold mt-1">{{ $animal->breed ?: '—' }}</p></div>
                    <div><p class="text-outline uppercase text-[10px] font-bold">Sexe</p><p class="font-bold mt-1">{{ $animal->sex === 'F' ? 'Femelle' : 'Mâle' }}</p></div>
                    <div><p class="text-outline uppercase text-[10px] font-bold">Date de Naissance</p><p class="font-bold mt-1">{{ $animal->birth_date?->format('d/m/Y') ?: '—' }}@if($animal->age_in_months !== null) <span class="text-outline font-normal">({{ $animal->age_in_months }} mois)</span>@endif</p></div>
                    <div><p class="text-outline uppercase text-[10px] font-bold">Date d'Entrée</p><p class="font-bold mt-1">{{ $animal->entry_date->format('d/m/Y') }}</p></div>
                    <div><p class="text-outline uppercase text-[10px] font-bold">Origine</p><p class="font-bold mt-1">{{ $animal->origin ?: '—' }}</p></div>
                    <div><p class="text-outline uppercase text-[10px] font-bold">Cage</p><p class="font-bold mt-1">{{ $animal->cage ?: '—' }}</p></div>
                    <div><p class="text-outline uppercase text-[10px] font-bold">Lot</p><p class="font-bold mt-1">{{ $animal->lot?->code ?: '—' }}</p></div>
                </div>
            </div>
            <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md">
                <h3 class="text-sm font-bold text-brand-forest mb-md flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">qr_code_2</span>QR Code Sujet</h3>
                <div class="w-full aspect-square bg-surface-zebra rounded-lg flex items-center justify-center border border-outline-variant p-md">
                    {!! $this->qrCode !!}
                </div>
                <p class="text-[11px] text-outline mt-sm text-center">Scan terrain pour ouvrir directement cette fiche depuis l'application mobile.</p>
            </div>
        </div>
    @endif

    @if($tab === 'historique')
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
            <div class="overflow-x-auto">
                <table class="w-full rtable">
                    <thead class="bg-surface-zebra border-b border-outline-variant">
                        <tr>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Type</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Événement</th>
                        </tr>
                    </thead>
                    <tbody>
                        @forelse($this->history as $i => $ligne)
                            <tr class="rrow border-b border-outline-variant {{ $i % 2 === 0 ? 'bg-white' : 'bg-surface-zebra' }}">
                                <td data-label="Date" class="px-md py-sm text-xs">{{ \Carbon\Carbon::parse($ligne['date'])->format('d/m/Y') }}</td>
                                <td data-label="Type" class="px-md py-sm text-xs font-semibold text-brand-forest">{{ $ligne['type'] }}</td>
                                <td data-label="Événement" class="px-md py-sm text-xs">{{ $ligne['libelle'] }}</td>
                            </tr>
                        @empty
                            <tr><td colspan="3" class="px-md py-lg text-center text-outline">Aucun événement enregistré pour ce sujet.</td></tr>
                        @endforelse
                    </tbody>
                </table>
            </div>
        </div>
    @endif

    @if($tab === 'vaccins')
        <div class="bg-info-blue/10 border border-info-blue/30 rounded-lg p-md mb-md flex items-start gap-sm text-xs">
            <span class="material-symbols-outlined text-info-blue text-[18px] flex-shrink-0">info</span>
            <p class="text-on-surface">La prophylaxie est administrée <strong>par bande</strong> sur cette ferme, jamais sujet par sujet. Les soins ci-dessous sont ceux de la bande {{ $animal->lot?->code ?? '—' }} et concernent donc ce sujet — ils ne sont pas des traitements individuels.</p>
        </div>
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
            <div class="overflow-x-auto">
                <table class="w-full rtable">
                    <thead class="bg-surface-zebra border-b border-outline-variant">
                        <tr>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Action</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Produit</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Dose</th>
                        </tr>
                    </thead>
                    <tbody>
                        @forelse($this->veterinaryRecords as $i => $soin)
                            <tr class="rrow border-b border-outline-variant {{ $i % 2 === 0 ? 'bg-white' : 'bg-surface-zebra' }}">
                                <td data-label="Date" class="px-md py-sm text-xs">{{ $soin->record_date->format('d/m/Y') }}</td>
                                <td data-label="Action" class="px-md py-sm text-xs font-semibold">{{ $soin->action_type }}</td>
                                <td data-label="Produit" class="px-md py-sm text-xs">{{ $soin->product_used ?: '—' }}</td>
                                <td data-label="Dose" class="px-md py-sm text-xs">{{ $soin->dose ?: '—' }}</td>
                            </tr>
                        @empty
                            <tr><td colspan="4" class="px-md py-lg text-center text-outline">Aucun soin enregistré pour la bande de ce sujet.</td></tr>
                        @endforelse
                    </tbody>
                </table>
            </div>
        </div>
    @endif

    @if($tab === 'reproduction')
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
            <div class="overflow-x-auto">
                <table class="w-full rtable">
                    <thead class="bg-surface-zebra border-b border-outline-variant">
                        <tr>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Saillie</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Rôle</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Mise Bas</th>
                            <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Nés Vivants</th>
                            <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Nés Morts</th>
                            <th class="px-md py-sm text-center text-[10px] text-outline font-bold uppercase">Statut</th>
                        </tr>
                    </thead>
                    <tbody>
                        @forelse($this->reproductionEvents as $i => $event)
                            <tr class="rrow border-b border-outline-variant {{ $i % 2 === 0 ? 'bg-white' : 'bg-surface-zebra' }}">
                                <td data-label="Saillie" class="px-md py-sm text-xs">{{ $event->saillie_date->format('d/m/Y') }}</td>
                                <td data-label="Rôle" class="px-md py-sm text-xs font-semibold">{{ $event->mother_ref === $animal->identifier ? 'Mère' : 'Géniteur' }}</td>
                                <td data-label="Mise Bas" class="px-md py-sm text-xs">{{ $event->mise_bas_date_actual?->format('d/m/Y') ?: '—' }}</td>
                                <td data-label="Nés Vivants" class="px-md py-sm text-xs text-right font-bold text-brand-emerald">{{ $event->nes_vivants ?? '—' }}</td>
                                <td data-label="Nés Morts" class="px-md py-sm text-xs text-right text-error-deep">{{ $event->nes_morts ?? '—' }}</td>
                                <td data-label="Statut" class="px-md py-sm text-xs text-center">{{ ucfirst(str_replace('_', ' ', $event->status)) }}</td>
                            </tr>
                        @empty
                            <tr><td colspan="6" class="px-md py-lg text-center text-outline">Aucun événement de reproduction pour ce sujet.</td></tr>
                        @endforelse
                    </tbody>
                </table>
            </div>
            <p class="text-[11px] text-outline p-sm border-t border-outline-variant">Événements retrouvés par correspondance sur les références mère/géniteur déjà saisies dans le <a href="{{ route('elevage.suivi-reproduction') }}" class="text-brand-emerald underline font-semibold">Suivi de Reproduction</a>.</p>
        </div>
    @endif

    @if($tab === 'mouvements')
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
            <div class="overflow-x-auto">
                <table class="w-full rtable">
                    <thead class="bg-surface-zebra border-b border-outline-variant">
                        <tr>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Mouvement</th>
                            <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Détail</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach($this->movements as $i => $m)
                            <tr class="rrow border-b border-outline-variant {{ $i % 2 === 0 ? 'bg-white' : 'bg-surface-zebra' }}">
                                <td data-label="Date" class="px-md py-sm text-xs">{{ \Carbon\Carbon::parse($m['date'])->format('d/m/Y') }}</td>
                                <td data-label="Mouvement" class="px-md py-sm text-xs font-semibold">{{ $m['libelle'] }}</td>
                                <td data-label="Détail" class="px-md py-sm text-xs">{{ $m['detail'] }}</td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
            <p class="text-[11px] text-outline p-sm border-t border-outline-variant">Seuls les mouvements réellement enregistrés sont listés. Aucun historique de déplacement entre cages n'est modélisé à ce jour — en fabriquer un ici afficherait des lignes jamais saisies.</p>
        </div>
    @endif

    @if(in_array($tab, ['alimentation', 'production', 'documents'], true))
        @php
            $motifs = [
                'alimentation' => "Le rationnement est calculé PAR BANDE et par catégorie (par exemple, pour les lapins : Reproducteur / Jeune / Sous-mères), jamais par sujet. Afficher une ration individuelle supposerait de diviser arbitrairement la provende de la bande — un chiffre qui n'aurait aucune valeur zootechnique.",
                'production' => "La ponte est relevée par bande dans la fiche journalière (œufs récoltés, cassés, commercialisables). Aucune source ne rattache une production à une poule donnée.",
                'documents' => "Aucune table de pièces jointes par sujet n'existe dans le schéma. Le module Administration gère les documents de la ferme, pas ceux d'un animal.",
            ];
        @endphp
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-lg text-center">
            <span class="material-symbols-outlined text-outline-variant" style="font-size:44px;">hourglass_empty</span>
            <p class="text-sm font-bold text-brand-forest mt-sm">Aucune donnée réelle pour cet onglet</p>
            <p class="text-xs text-outline mt-xs max-w-2xl mx-auto">{{ $motifs[$tab] }}</p>
            <p class="text-[11px] text-outline mt-md max-w-2xl mx-auto italic">Cet onglet reste vide tant qu'une source réelle n'existe pas — le remplir de valeurs plausibles serait plus trompeur qu'utile.</p>
        </div>
    @endif
</div>
