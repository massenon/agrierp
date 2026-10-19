{{--
    Ticket H11 — liste CALCULÉE des rappels VMS des 7 prochains jours (ajout du poste), au-dessus du texte et du lien du
    Blade : six au plus, comme au poste (`d.rappels.take(6)`). Reçoit : $rappels (DashboardElevage::getRappelsVmsProperty).
--}}
@if(empty($rappels))
    <p class="text-xs italic text-outline">— Aucun rappel dans les 7 prochains jours —</p>
@else
    <div class="space-y-sm">
        @foreach(array_slice($rappels, 0, 6) as $rappel)
            <div class="flex items-start gap-sm p-sm rounded-lg bg-accent-yellow/10 border border-accent-yellow/30">
                <span class="material-symbols-outlined text-[18px] text-brand-forest">event</span>
                <div>
                    <p class="text-xs font-semibold">{{ $rappel['libelle'] }}</p>
                    <p class="text-xs text-outline">{{ $rappel['echeance'] }}</p>
                </div>
            </div>
        @endforeach
    </div>
@endif
