{{--
    Ticket POP1 — fenêtre « Rappels du jour » (PRD docs/prd/popup-rappels.md). Reçoit : $visible, $rappels, $joursRappel, $forcer.
    Le navigateur ne décide de rien : il transmet au serveur le marqueur de session (sessionStorage) et la date de masquage
    (localStorage, par utilisateur) ; le serveur répond « ouvre » ou non (RappelsDuJour::ouvrir).
--}}
@php
    $groupes = [
        'retard' => ['titre' => 'En retard', 'classe' => 'bg-error-bg text-error-deep'],
        'aujourdhui' => ['titre' => "Aujourd'hui", 'classe' => 'bg-accent-yellow/30 text-brand-forest'],
        'avenir' => ['titre' => 'À venir (sous '.$joursRappel.' jour'.($joursRappel > 1 ? 's' : '').')', 'classe' => 'bg-brand-emerald/10 text-brand-emerald'],
    ];
@endphp
<div
    x-data="{
        uid: '{{ auth()->id() }}',
        cleSession: 'agrierp_rappels_session:{{ auth()->id() }}',
        cleMasques: 'agrierp_rappels_masques',
        aujourdhui: '{{ today()->toDateString() }}',
        masquer() {
            try {
                const m = JSON.parse(localStorage.getItem(this.cleMasques) || '{}');
                m[this.uid] = this.aujourdhui;
                localStorage.setItem(this.cleMasques, JSON.stringify(m));
            } catch (e) {}
            $wire.fermer();
        },
    }"
    x-init="
        let vu = false, masque = null;
        try { vu = sessionStorage.getItem(cleSession) === '1'; } catch (e) {}
        try { masque = JSON.parse(localStorage.getItem(cleMasques) || '{}')[uid] || null; } catch (e) {}
        if (@js($forcer) || !vu) {
            $wire.ouvrir(vu, masque).then(() => { try { sessionStorage.setItem(cleSession, '1'); } catch (e) {} });
        }
    "
    x-on:keydown.escape.window="if ($wire.visible) $wire.fermer()">
    @if($visible && count($rappels) > 0)
        <div class="fixed inset-0 bg-black/50 z-[110] flex items-center justify-center p-md" dusk="rappels-du-jour">
            <div class="bg-white rounded-lg shadow-xl w-full max-w-3xl p-lg max-h-[85vh] overflow-y-auto">
                <div class="flex items-start justify-between mb-md">
                    <div>
                        <p class="text-[10px] font-bold uppercase tracking-wider text-outline">Soins, vaccins et délais d'attente</p>
                        <h3 class="font-bold text-lg text-brand-forest flex items-center gap-xs"><span class="material-symbols-outlined text-brand-emerald">notifications_active</span>Rappels du jour</h3>
                    </div>
                    <button type="button" wire:click="fermer" class="text-outline hover:text-on-surface" title="Fermer"><span class="material-symbols-outlined">close</span></button>
                </div>

                @foreach($groupes as $cle => $groupe)
                    @php $lignes = array_values(array_filter($rappels, fn ($r) => $r['urgence'] === $cle)); @endphp
                    @if(count($lignes) > 0)
                        <div class="mb-md">
                            <p class="inline-block text-[10px] font-bold uppercase tracking-wider px-sm py-xs rounded {{ $groupe['classe'] }} mb-xs">{{ $groupe['titre'] }} ({{ count($lignes) }})</p>
                            <div class="overflow-x-auto">
                                <table class="w-full text-xs">
                                    <thead>
                                        <tr class="text-left text-outline border-b border-outline-variant">
                                            <th class="py-xs pr-sm font-semibold">Bande</th>
                                            <th class="py-xs pr-sm font-semibold">Rappel</th>
                                            <th class="py-xs pr-sm font-semibold">Produit</th>
                                            <th class="py-xs pr-sm font-semibold">Date prévue</th>
                                            <th class="py-xs font-semibold">Échéance</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        @foreach($lignes as $i => $r)
                                            <tr wire:key="rappel-{{ $cle }}-{{ $i }}" class="border-b border-outline-variant">
                                                <td class="py-xs pr-sm font-semibold">{{ $r['bande'] }} ({{ $r['espece'] }})</td>
                                                <td class="py-xs pr-sm">{{ $r['libelle'] }} <span class="text-outline">· {{ $r['type_libelle'] }}</span></td>
                                                <td class="py-xs pr-sm">{{ $r['produit'] }}</td>
                                                <td class="py-xs pr-sm">{{ $r['date_texte'] }}</td>
                                                <td class="py-xs">{{ $r['echeance'] }}</td>
                                            </tr>
                                        @endforeach
                                    </tbody>
                                </table>
                            </div>
                        </div>
                    @endif
                @endforeach

                <div class="flex flex-wrap items-center justify-between gap-sm pt-md border-t border-outline-variant">
                    <a wire:navigate href="/soins-vaccins-hub" class="text-xs font-bold text-brand-emerald hover:text-brand-forest flex items-center gap-xs">Ouvrir Soins et vaccins<span class="material-symbols-outlined text-[16px]">arrow_forward</span></a>
                    <div class="flex items-center gap-sm">
                        <button type="button" x-on:click="masquer()" class="text-xs font-semibold text-outline hover:text-on-surface">Ne plus afficher aujourd'hui</button>
                        <button type="button" wire:click="fermer" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-xs font-bold hover:bg-brand-forest">Plus tard</button>
                    </div>
                </div>
            </div>
        </div>
    @endif
</div>
