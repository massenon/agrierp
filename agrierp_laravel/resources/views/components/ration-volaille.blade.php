{{-- Ticket 15.57 — rationnement par stade des fiches avicoles (Pondeuses, Reproducteurs), règle `App\Support\RationVolaille`,
     même tableau que le poste. « — » quand aucune ligne du barème ne correspond : jamais 0 g. --}}
@props(['tableau', 'ligneCle'])
<div>
    <p class="text-xs font-bold text-brand-forest uppercase mb-xs flex items-center gap-xs"><span class="material-symbols-outlined text-[16px] text-brand-emerald">restaurant</span>Rationnement &amp; Provende Servie par Stade (en Grammes g/j)</p>
    @if(count($tableau['lignes']) === 0)
        <p class="text-xs text-outline bg-surface-zebra border border-outline-variant rounded-lg p-md">Aucune ration normative pour l'aviculture : renseignez le barème dans Paramètres Élevage &gt; Rationnement.</p>
    @else
        <div class="bg-white border border-outline-variant rounded-lg overflow-hidden shadow-sm">
            <table class="w-full text-xs">
                <thead class="bg-surface-zebra text-outline border-b border-outline-variant">
                    <tr><th class="px-md py-xs text-left">Stade / Tranche d'Âge</th><th class="px-md py-xs text-center">Effectif</th><th class="px-md py-xs text-center">Ration Normative</th><th class="px-md py-xs text-right">Provende Servie (g)</th></tr>
                </thead>
                <tbody class="divide-y divide-outline-variant/60">
                    @foreach($tableau['lignes'] as $ligne)
                        <tr wire:key="ration-{{ $loop->index }}">
                            <td class="px-md py-xs font-bold text-brand-forest">{{ $ligne['libelle'] }}</td>
                            <td class="px-md py-xs text-center font-bold">{{ $ligne['effectif'] ?? '—' }}</td>
                            <td class="px-md py-xs text-center font-mono">{{ round($ligne['ration']) }} g/j</td>
                            <td class="px-md py-xs text-right font-mono font-bold text-brand-emerald">{{ $ligne['total_g'] === null ? '—' : round($ligne['total_g']).' g' }}</td>
                        </tr>
                    @endforeach
                </tbody>
                <tfoot class="bg-brand-emerald/10 font-bold text-brand-forest border-t border-brand-emerald/20">
                    <tr><td colspan="3" class="px-md py-xs uppercase text-[10px]">TOTAL PROVENDE SERVIE DU JOUR (CUMUL EN GRAMMES)</td><td class="px-md py-xs text-right font-mono text-sm text-brand-emerald">{{ $tableau['total_g'] === null ? '—' : round($tableau['total_g']).' g ('.$tableau['total_kg'].' Kg)' }}</td></tr>
                </tfoot>
            </table>
        </div>
        @if($tableau['rattachee'])
            <p class="text-[10px] text-outline mt-xs">L'effectif n'est pas encore ventilé par stade : la fiche du jour n'en porte que le total. La ligne {{ $ligneCle }} le reçoit entièrement.</p>
        @else
            <p class="text-[10px] text-error-deep mt-xs" role="status">Aucune ligne du barème ne correspond {{ $ligneCle }} : ajoutez-la dans Paramètres Élevage &gt; Rationnement pour calculer la provende.</p>
        @endif
    @endif
</div>
