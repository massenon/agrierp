{{--
    Ticket AIDE-1 — BOUTON FLOTTANT D'AIDE, PANNEAU ET VISITE GUIDÉE (module « Assistant de démarrage » allumé seulement).

    Posé par `layouts/app.blade.php` (sous `@if(\App\Support\AideEcrans::actif())`), dans `#app-racine` : le verrou de session rend donc
    ce composant inerte avec le reste de la page. Les textes viennent tous de `lang/fr/aide_ecrans.php` ; la logique de la
    visite est dans `resources/js/aide.js` (Alpine maison, aucune bibliothèque).

    Placement : à droite, AU-DESSUS du bouton « Accès rapide » (`bottom:88px`, 48 px de haut) avec 12 px d'écart, soit
    `bottom:148px` : les deux boutons ne se chevauchent sur aucun écran, mobile compris (la barre du bas fait 64 px).
    Le panneau reprend le gabarit du tiroir « Accès rapide » (même largeur, même voile, même en-tête).

    ⚠️ Classes Tailwind STATIQUES uniquement (aucune concaténation). Couleur de la marque : le maïs clair n'est employé que
    sur fond sombre (en-tête du tiroir, voile de la visite), jamais sur fond clair (`ContrasteMarqueTest`).
--}}
@php
    $panneau = \App\Support\AideEcrans::panneau();
    $visite = \App\Support\AideEcrans::visite();
    $aide = \App\Support\AideEcrans::pour(\App\Support\AideEcrans::cheminCourant());

    $config = [
        'etapes' => $visite['etapes'],
        // Les cibles de la visite : une par étape, repérées par `data-aide` dans le layout.
        'cibles' => ['aide', 'topbar', 'contenu', 'menu'],
        'libelles' => collect($visite)->except('etapes')->all(),
    ];
@endphp
<div x-data="aideFlottante({{ \Illuminate\Support\Js::from($config) }})"
    x-on:keydown.escape.window="visite ? passer() : (panneau ? fermerPanneau() : null)"
    x-on:keydown.arrow-right.window="visite && !fin ? suivant() : null"
    x-on:keydown.arrow-left.window="visite && !fin ? precedent() : null"
    x-on:resize.window.debounce.150ms="visite ? placer() : null"
    dusk="aide-flottante">

    <button type="button" data-aide="aide" dusk="aide-bouton" @click="ouvrirPanneau()"
        title="{{ $panneau['bouton'] }}" aria-label="{{ $panneau['bouton'] }}"
        class="fixed z-[60] flex items-center justify-center w-12 h-12 rounded-full bg-brand-emerald hover:bg-brand-forest text-white shadow-lg"
        style="bottom:148px; right:16px;">
        <span class="material-symbols-outlined" style="font-size:24px;">help</span>
    </button>

    <div x-show="panneau" x-cloak @click="fermerPanneau()" class="fixed inset-0 bg-black/40 z-[65]"></div>
    <div role="dialog" aria-label="{{ $panneau['titre'] }}" dusk="aide-panneau"
        class="fixed top-0 right-0 h-full w-72 max-w-[85vw] bg-white z-[70] shadow-2xl transform transition-transform duration-300 flex flex-col"
        :class="panneau ? 'translate-x-0' : 'translate-x-full'"
        :aria-hidden="panneau ? 'false' : 'true'" :inert="!panneau">
        <div class="flex items-center justify-between px-md py-md border-b border-outline-variant bg-brand-forest">
            <span class="text-white font-bold text-sm flex items-center gap-xs"><span class="material-symbols-outlined text-brand-maize text-[20px]">help</span>{{ $panneau['titre'] }}</span>
            <button type="button" @click="fermerPanneau()" title="{{ $panneau['fermer'] }}" aria-label="{{ $panneau['fermer'] }}" class="text-white/80 hover:text-white"><span class="material-symbols-outlined">close</span></button>
        </div>
        <div class="flex-1 overflow-y-auto p-sm space-y-md">
            <section dusk="aide-ecran" data-aide-generique="{{ $aide['generique'] ? '1' : '0' }}">
                <h3 class="px-sm text-[10px] font-bold uppercase tracking-wider text-outline flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald text-[16px]">lightbulb</span>{{ $panneau['ecran'] }}</h3>
                <p class="px-sm mt-xs text-sm font-bold text-brand-forest" dusk="aide-ecran-titre">{{ $aide['titre'] }}</p>
                <ul class="px-sm mt-xs list-disc pl-md space-y-xs text-xs text-on-surface" dusk="aide-ecran-puces">
                    @foreach($aide['puces'] as $puce)
                        <li>{{ $puce }}</li>
                    @endforeach
                </ul>
            </section>

            <div class="border-t border-outline-variant"></div>

            <div class="space-y-xs">
                {{-- Relancer l'assistant : réservé à qui le voit au démarrage (`manage-parametres`, comme `AssistantDemarrage::mount`). --}}
                @can('manage-parametres')
                    <button type="button" dusk="aide-relancer" @click="relancerAssistant()" class="w-full flex items-center gap-sm px-sm py-sm rounded-lg text-left text-on-surface hover:bg-surface-zebra transition-colors">
                        <span class="material-symbols-outlined text-brand-forest text-[22px]">checklist</span>
                        <span class="flex flex-col">
                            <span class="text-sm font-semibold">{{ $panneau['relancer'] }}</span>
                            <span class="text-[11px] text-outline">{{ $panneau['relancer_detail'] }}</span>
                        </span>
                    </button>
                @endcan
                <button type="button" dusk="aide-visite" @click="demarrerVisite()" class="w-full flex items-center gap-sm px-sm py-sm rounded-lg text-left text-on-surface hover:bg-surface-zebra transition-colors">
                    <span class="material-symbols-outlined text-brand-forest text-[22px]">school</span>
                    <span class="flex flex-col">
                        <span class="text-sm font-semibold">{{ $panneau['visite'] }}</span>
                        <span class="text-[11px] text-outline">{{ $panneau['visite_detail'] }}</span>
                    </span>
                </button>
            </div>
        </div>
    </div>

    {{-- Visite guidée : voile sombre, trou lumineux sur l'élément expliqué (ombre géante), carte de l'étape. --}}
    <div x-show="visite" x-cloak role="dialog" aria-modal="true" aria-labelledby="visite-titre" dusk="aide-visite-fenetre"
        class="fixed inset-0 z-[120]">
        <div class="absolute inset-0" :class="trou ? '' : 'bg-black/60'" @click.stop></div>
        <div x-show="trou" class="absolute rounded-lg pointer-events-none ring-2 ring-white transition-all duration-200 motion-reduce:transition-none" :style="styleTrou"></div>

        <div x-ref="carte" :style="styleCarte"
            class="absolute w-[22rem] max-w-[calc(100vw-2rem)] bg-white rounded-lg shadow-2xl p-md">
            {{-- Étapes --}}
            <template x-if="!fin">
                <div>
                    <div class="flex items-center justify-between gap-sm mb-sm">
                        <span class="text-[11px] font-bold uppercase tracking-wider text-outline" x-text="indicateur" dusk="aide-indicateur"></span>
                        <button type="button" dusk="aide-passer" @click="passer()" class="text-xs font-bold text-outline hover:text-brand-forest px-sm py-1 rounded-full border border-outline-variant">{{ $visite['passer'] }}</button>
                    </div>
                    <h3 id="visite-titre" class="text-base font-bold text-brand-forest" x-text="courante.titre" dusk="aide-etape-titre"></h3>
                    <p class="text-xs text-on-surface mt-xs" x-text="courante.texte" dusk="aide-etape-texte"></p>

                    <div class="flex items-center gap-xs mt-md" aria-hidden="true">
                        <template x-for="(e, i) in etapes" :key="i">
                            <span class="h-2 rounded-full transition-all" :class="i === etape ? 'w-5 bg-brand-emerald' : 'w-2 bg-outline-variant'"></span>
                        </template>
                    </div>

                    <div class="flex items-center justify-between mt-md">
                        <button type="button" dusk="aide-precedent" x-show="etape > 0" @click="precedent()" class="text-xs font-bold text-brand-forest px-md py-sm rounded-full border border-outline-variant">{{ $visite['precedent'] }}</button>
                        <span x-show="etape === 0"></span>
                        <button type="button" dusk="aide-suivant" x-ref="primaire" @click="suivant()" class="text-xs font-bold text-white bg-brand-emerald hover:bg-brand-forest px-md py-sm rounded-full" x-text="derniere ? libelles.terminer : libelles.suivant"></button>
                    </div>
                </div>
            </template>

            {{-- Message de fin : sobre, sans confettis. --}}
            <template x-if="fin">
                <div>
                    <h3 id="visite-titre" class="text-base font-bold text-brand-forest flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald text-[22px]">check_circle</span><span x-text="libelles.fin_titre"></span></h3>
                    <p class="text-xs text-on-surface mt-xs" x-text="libelles.fin_texte" dusk="aide-fin-texte"></p>
                    <div class="flex justify-end mt-md">
                        <button type="button" dusk="aide-fin-fermer" x-ref="primaire" @click="passer()" class="text-xs font-bold text-white bg-brand-emerald hover:bg-brand-forest px-md py-sm rounded-full" x-text="libelles.fin_fermer"></button>
                    </div>
                </div>
            </template>
        </div>
    </div>
</div>
