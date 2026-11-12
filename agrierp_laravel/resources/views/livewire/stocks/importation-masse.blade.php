@php
    // Classes Tailwind COMPLÈTES et statiques (jamais de construction dynamique : le scanner ne les verrait pas).
    $badges = [
        'valide' => 'bg-brand-emerald/10 text-brand-forest',
        'creee' => 'bg-brand-emerald/10 text-brand-forest',
        'ignoree' => 'bg-accent-yellow/30 text-on-surface',
        'refusee' => 'bg-error-red/10 text-error-red',
    ];
    $lot = $this->lot;
    $termine = $lot && $lot->statut === 'termine';
    $libelles = app(\App\Services\Import\ImportMasseService::class)->libellesDeStatut($termine);
    $etapes = [1 => __('stocks.etape_module'), 2 => __('stocks.etape_modele'), 3 => __('stocks.etape_fichier'), 4 => __('stocks.etape_apercu'), 5 => __('stocks.etape_confirmation'), 6 => __('stocks.etape_rapport')];
    $etapeActive = $etape === 6 ? 6 : $etape;
    $module = $this->moduleChoisi;
@endphp
<div>
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">upload_file</span>{{ __('stocks.titre_importation_masse') }}
        </h2>
        <p class="text-xs text-outline mt-xs">{{ __('stocks.desc_importation_masse') }}</p>
    </div>

    {{-- Étapes --}}
    <ol class="flex flex-wrap gap-xs mb-lg" data-etapes>
        @foreach($etapes as $numero => $libelle)
            <li class="flex items-center gap-xs text-[11px] font-bold uppercase px-sm py-1 rounded-full border {{ $numero === $etapeActive ? 'bg-brand-emerald text-white border-brand-emerald' : ($numero < $etapeActive ? 'bg-brand-emerald/10 text-brand-forest border-brand-emerald/30' : 'bg-white text-outline border-outline-variant') }}">
                <span>{{ $numero }}</span><span>{{ $libelle }}</span>
            </li>
        @endforeach
    </ol>

    {{-- ÉTAPE 1 : choisir le module --}}
    @if($etape === 1)
        <h3 class="text-sm font-bold text-brand-forest uppercase mb-sm">{{ __('stocks.etape1_titre') }}</h3>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-md">
            @foreach($this->modules as $cle => $m)
                <button type="button" wire:click="choisirModule('{{ $cle }}')" dusk="module-{{ $cle }}" class="text-left bg-white rounded-lg border border-outline-variant shadow-sm p-md hover:border-brand-emerald hover:shadow-md transition-colors">
                    <span class="material-symbols-outlined text-brand-emerald text-[28px]">{{ $m->icone() }}</span>
                    <span class="block text-sm font-bold text-on-surface mt-xs">{{ $m->libelle() }}</span>
                    <span class="block text-xs text-outline mt-xs">{{ $m->description() }}</span>
                </button>
            @endforeach
        </div>
        <p class="text-[11px] text-outline mt-md">{{ __('stocks.info_modules_role') }}</p>
    @endif

    {{-- ÉTAPE 2 : télécharger le modèle --}}
    @if($etape === 2 && $module)
        <div class="bg-white rounded-lg border border-outline-variant shadow-sm p-md lg:p-lg max-w-3xl">
            <h3 class="text-sm font-bold text-brand-forest uppercase mb-xs">{{ __('stocks.etape2_titre_module', ['libelle' => $module->libelle()]) }}</h3>
            <p class="text-sm text-on-surface mb-sm">{{ __('stocks.info_contenu_modele', ['version' => $module->version()]) }}</p>
            <ul class="text-xs text-outline list-disc pl-md space-y-xs mb-md">
                <li>{{ __('stocks.info_entetes') }}</li>
                <li>{{ __('stocks.info_montants') }}</li>
                <li>{{ __('stocks.info_limite_taille', ['lignes' => number_format(\App\Services\Import\LecteurXlsx::LIGNES_MAX, 0, ',', ' '), 'mo' => \App\Services\Import\LecteurXlsx::TAILLE_MAX_OCTETS / 1024 / 1024]) }}</li>
            </ul>
            <div class="flex flex-wrap gap-sm">
                <button type="button" wire:click="telechargerModele" dusk="telecharger-modele" class="flex items-center gap-xs bg-brand-emerald text-white text-xs font-bold px-md py-2 rounded-lg hover:opacity-90"><span class="material-symbols-outlined text-[18px]">download</span>{{ __('stocks.bouton_telecharger_modele') }}</button>
                <button type="button" wire:click="versEtape(3)" class="flex items-center gap-xs border border-outline-variant text-brand-forest text-xs font-bold px-md py-2 rounded-lg hover:bg-surface-zebra">{{ __('stocks.bouton_deposer_fichier') }}<span class="material-symbols-outlined text-[18px]">arrow_forward</span></button>
                <button type="button" wire:click="versEtape(1)" class="text-xs font-bold text-outline px-sm py-2 hover:text-brand-forest">{{ __('stocks.bouton_changer_module') }}</button>
            </div>
        </div>
    @endif

    {{-- ÉTAPE 3 : déposer le fichier (glisser-déposer ou clic) --}}
    @if($etape === 3 && $module)
        <div class="max-w-3xl">
            <h3 class="text-sm font-bold text-brand-forest uppercase mb-xs">{{ __('stocks.etape3_titre_module', ['libelle' => $module->libelle()]) }}</h3>
            @if($erreurFichier)
                <div class="mb-sm p-md rounded-lg border border-error-red/40 bg-error-red/10 text-error-red text-sm flex items-start gap-xs" role="alert" dusk="erreur-fichier">
                    <span class="material-symbols-outlined text-[20px]">error</span><span>{{ $erreurFichier }}</span>
                </div>
            @endif
            <div x-data="{ survol: false, envoi: false }"
                x-on:livewire-upload-start="envoi = true" x-on:livewire-upload-finish="envoi = false" x-on:livewire-upload-error="envoi = false"
                x-on:dragover.prevent="survol = true" x-on:dragleave.prevent="survol = false"
                x-on:drop.prevent="survol = false; $refs.entree.files = $event.dataTransfer.files; $refs.entree.dispatchEvent(new Event('change', { bubbles: true }))"
                class="relative">
                <label for="fichier-import" :class="survol ? 'border-brand-emerald bg-brand-emerald/10' : 'border-outline-variant bg-white'" class="flex flex-col items-center justify-center gap-xs text-center border-2 border-dashed rounded-lg p-lg cursor-pointer hover:border-brand-emerald">
                    <span class="material-symbols-outlined text-brand-emerald text-[36px]">upload_file</span>
                    <span class="text-sm font-bold text-on-surface">{{ __('stocks.dropzone_consigne') }}</span>
                    <span class="text-[11px] text-outline">{{ __('stocks.dropzone_contrainte', ['libelle' => $module->libelle(), 'version' => $module->version(), 'mo' => \App\Services\Import\LecteurXlsx::TAILLE_MAX_OCTETS / 1024 / 1024, 'lignes' => number_format(\App\Services\Import\LecteurXlsx::LIGNES_MAX, 0, ',', ' ')]) }}</span>
                    <span x-show="envoi" x-cloak class="text-xs text-brand-forest font-bold">{{ __('stocks.dropzone_envoi') }}</span>
                    <span wire:loading wire:target="fichier" class="text-xs text-brand-forest font-bold">{{ __('stocks.dropzone_lecture') }}</span>
                </label>
                <input id="fichier-import" x-ref="entree" type="file" wire:model="fichier" accept=".xlsx,.csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,text/csv" class="sr-only">
            </div>
            <div class="flex gap-sm mt-md">
                <button type="button" wire:click="versEtape(2)" class="text-xs font-bold text-brand-forest border border-outline-variant px-md py-2 rounded-lg hover:bg-surface-zebra">{{ __('stocks.bouton_retour_modele') }}</button>
                <button type="button" wire:click="versEtape(1)" class="text-xs font-bold text-outline px-sm py-2 hover:text-brand-forest">{{ __('stocks.bouton_changer_module') }}</button>
            </div>
        </div>
    @endif

    {{-- ÉTAPES 4 (aperçu) et 6 (rapport) : mêmes compteurs et même tableau --}}
    @if(in_array($etape, [4, 6], true) && $lot && $module)
        @if($etape === 4)
            <h3 class="text-sm font-bold text-brand-forest uppercase mb-xs">{{ __('stocks.etape4_titre') }}</h3>
            <p class="text-xs text-outline mb-sm">{{ __('stocks.info_fichier_apercu', ['fichier' => $lot->nom_fichier, 'libelle' => $module->libelle(), 'version' => $lot->version_modele]) }}</p>
            @if($lot->avertissement)
                <div class="mb-sm p-md rounded-lg border border-accent-yellow bg-accent-yellow/20 text-sm text-on-surface flex items-start gap-xs" dusk="avertissement-deja-importe">
                    <span class="material-symbols-outlined text-[20px]">info</span><span>{{ $lot->avertissement }}</span>
                </div>
            @endif
            @if($this->bloquant)
                <div class="mb-sm p-md rounded-lg border border-error-red/40 bg-error-red/10 text-error-red text-sm flex items-start gap-xs" role="alert" dusk="import-bloque">
                    <span class="material-symbols-outlined text-[20px]">lock</span><span>{{ $this->bloquant }} {{ __('stocks.alerte_bloquant') }}</span>
                </div>
            @endif
        @else
            <h3 class="text-sm font-bold text-brand-forest uppercase mb-xs">{{ __('stocks.etape6_titre') }}</h3>
            <p class="text-xs text-outline mb-sm">{{ __('stocks.info_fichier_rapport', ['fichier' => $lot->nom_fichier, 'date' => $lot->termine_le?->format('d/m/Y à H:i')]) }}</p>
        @endif

        <div class="grid grid-cols-2 lg:grid-cols-4 gap-md mb-md" data-compteurs>
            <x-kpi-card :label="__('stocks.kpi_lignes_lues')" icon="table_rows" color="forest" :value="$lot->lues" />
            @if($termine)
                <x-kpi-card :label="__('stocks.kpi_creees')" icon="check_circle" color="emerald" :value="$lot->creees" />
            @else
                <x-kpi-card :label="__('stocks.kpi_valides')" icon="check_circle" color="emerald" :value="$lot->valides" />
            @endif
            <x-kpi-card :label="__('stocks.kpi_ignorees')" icon="content_copy" color="maize" :value="$lot->ignorees" />
            <x-kpi-card :label="__('stocks.kpi_refusees')" icon="error" color="red" :value="$lot->refusees" />
        </div>
        @if($termine && $module->cle() === 'stocks')
            <p class="text-xs text-outline mb-md">{{ __('stocks.info_stocks_ignores') }}</p>
        @endif

        <div class="flex flex-wrap items-center gap-xs mb-sm">
            @foreach(['tous' => __('stocks.filtre_toutes_lignes'), 'refusee' => __('stocks.filtre_refusees'), 'ignoree' => __('stocks.filtre_ignorees')] + ($termine ? ['creee' => __('stocks.filtre_creees')] : ['valide' => __('stocks.filtre_valides')]) as $valeur => $texte)
                <button type="button" wire:click="filtrer('{{ $valeur }}')" class="text-[11px] font-bold px-sm py-1 rounded-full border {{ $filtre === $valeur ? 'bg-brand-forest text-white border-brand-forest' : 'bg-white text-brand-forest border-outline-variant hover:bg-surface-zebra' }}">{{ $texte }}</button>
            @endforeach
        </div>

        <x-datatable :headers="[__('stocks.col_ligne'), __('stocks.col_designation'), __('stocks.col_valeurs_lues'), __('stocks.col_resultat'), __('stocks.col_motif_import')]">
            @forelse($this->lignesDeLaPage as $l)
                <tr class="border-b border-outline-variant/60 align-top">
                    <td data-label="{{ __('stocks.col_ligne') }}" class="px-md py-sm text-xs font-bold">{{ $l['ligne'] }}</td>
                    <td data-label="{{ __('stocks.col_designation') }}" class="px-md py-sm text-xs">{{ $l['designation'] !== '' ? $l['designation'] : '—' }}</td>
                    <td data-label="{{ __('stocks.col_valeurs_lues') }}" class="px-md py-sm text-[11px] text-outline">{{ $l['brut'] ? \Illuminate\Support\Str::limit(implode(' · ', array_filter($l['brut'], fn ($v) => $v !== '')), 90) : '—' }}</td>
                    <td data-label="{{ __('stocks.col_resultat') }}" class="px-md py-sm"><span class="text-[10px] font-bold uppercase px-sm py-1 rounded-full {{ $badges[$l['statut']] ?? '' }}">{{ $libelles[$l['statut']] ?? $l['statut'] }}</span></td>
                    <td data-label="{{ __('stocks.col_motif_import') }}" class="px-md py-sm text-xs whitespace-pre-line">{{ $l['motif'] ?? '' }}</td>
                </tr>
            @empty
                <tr><td colspan="5" class="px-md py-lg text-center text-xs text-outline">{{ __('stocks.msg_aucune_ligne_filtre') }}</td></tr>
            @endforelse
        </x-datatable>
        <div class="flex items-center justify-between mt-sm text-[11px] text-outline">
            <span>{{ count($this->lignesFiltrees) }} {{ count($this->lignesFiltrees) > 1 ? __('stocks.mot_lignes') : __('stocks.mot_ligne') }} — page {{ $page }} sur {{ $this->dernierePage }}</span>
            <div class="flex gap-xs">
                <button type="button" wire:click="pagePrecedente" @disabled($page <= 1) class="text-xs font-bold px-sm py-1 rounded-lg border border-outline-variant text-brand-forest hover:bg-surface-zebra disabled:opacity-50">{{ __('stocks.bouton_precedent') }}</button>
                <button type="button" wire:click="pageSuivante" @disabled($page >= $this->dernierePage) class="text-xs font-bold px-sm py-1 rounded-lg border border-outline-variant text-brand-forest hover:bg-surface-zebra disabled:opacity-50">{{ __('stocks.bouton_suivant') }}</button>
            </div>
        </div>

        <div class="flex flex-wrap gap-sm mt-lg">
            @if($etape === 4)
                <button type="button" wire:click="versEtape(3)" class="text-xs font-bold text-brand-forest border border-outline-variant px-md py-2 rounded-lg hover:bg-surface-zebra">{{ __('stocks.bouton_changer_fichier') }}</button>
                <button type="button" x-on:click="$dispatch('open-modal', { name: 'modal-confirmer-import' })" dusk="importer" @disabled($lot->valides === 0 || $this->bloquant) class="flex items-center gap-xs bg-brand-emerald text-white text-xs font-bold px-md py-2 rounded-lg hover:opacity-90 disabled:opacity-50 disabled:cursor-not-allowed"><span class="material-symbols-outlined text-[18px]">task_alt</span>{{ __('stocks.bouton_importer') }} {{ $lot->valides }} {{ $lot->valides > 1 ? __('stocks.mot_lignes') : __('stocks.mot_ligne') }}</button>
                <button type="button" wire:click="recommencer" class="text-xs font-bold text-outline px-sm py-2 hover:text-brand-forest">{{ __('stocks.bouton_abandonner') }}</button>
            @else
                <button type="button" wire:click="telechargerRapport" dusk="telecharger-rapport" class="flex items-center gap-xs bg-brand-emerald text-white text-xs font-bold px-md py-2 rounded-lg hover:opacity-90"><span class="material-symbols-outlined text-[18px]">download</span>{{ __('stocks.bouton_telecharger_rapport') }}</button>
                @if($lot->refusees > 0)
                    <button type="button" wire:click="corriger" class="text-xs font-bold text-brand-forest border border-outline-variant px-md py-2 rounded-lg hover:bg-surface-zebra">{{ __('stocks.bouton_corriger') }}</button>
                @endif
                <button type="button" wire:click="recommencer" class="text-xs font-bold text-outline px-sm py-2 hover:text-brand-forest">{{ __('stocks.bouton_nouvel_import') }}</button>
            @endif
        </div>

        {{-- ÉTAPE 5 : confirmation --}}
        <x-modal name="modal-confirmer-import" maxWidth="md">
            <h3 class="text-base font-bold text-on-surface flex items-center gap-xs mb-sm"><span class="material-symbols-outlined text-brand-emerald">task_alt</span>{{ __('stocks.modal_confirmer_titre') }}</h3>
            <p class="text-sm text-on-surface mb-xs">{{ $lot->valides }} {{ $lot->valides > 1 ? __('stocks.modal_lignes_valides_pl', ['module' => $module->libelle()]) : __('stocks.modal_lignes_valides_sg', ['module' => $module->libelle()]) }}</p>
            <p class="text-xs text-outline mb-md">{{ __('stocks.modal_nb_exclus', ['ignorees' => $lot->ignorees, 'refusees' => $lot->refusees]) }} {{ $module->cle() === 'stocks' ? __('stocks.modal_stock_initial') : '' }} {{ __('stocks.modal_independance') }}</p>
            <div class="flex justify-end gap-sm">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-confirmer-import' })" class="text-xs font-bold text-brand-forest border border-outline-variant px-md py-2 rounded-lg hover:bg-surface-zebra">{{ __('stocks.bouton_annuler') }}</button>
                <button type="button" wire:click="confirmer" wire:loading.attr="disabled" dusk="confirmer-import" class="bg-brand-emerald text-white text-xs font-bold px-md py-2 rounded-lg hover:opacity-90 disabled:opacity-50">{{ __('stocks.bouton_confirmer_importation') }}</button>
            </div>
        </x-modal>
    @endif
</div>
