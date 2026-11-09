@props([
    'autonomie' => null,           // résultat de AutonomieAlimentaireService::evaluer()
    'filiere' => 'de cette filière', // complément du message « aucun produit de provende … »
])
{{--
    Autonomie alimentaire — fiches Lapins / Porcs et tiroir de Gestion des Bandes.
    ⚠️ ROUGE dès que le stock est en RUPTURE ou ne couvre plus que 3 jours : il faut s'approvisionner.
    ⚠️ N'EMPÊCHE JAMAIS l'enregistrement de la fiche : c'est une information, pas un contrôle.
--}}
@php $a = $autonomie ?? ['available' => false]; @endphp
@if(! ($a['available'] ?? false))
    <div class="bg-error-bg border border-error-deep/30 rounded-lg p-sm text-xs text-error-deep" role="alert">
        <p class="font-bold flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">warning</span>Autonomie alimentaire : aucun stock de provende suivi</p>
        <p>Aucun produit de provende {{ $filiere }} n'existe en catalogue avec un stock suivi : créez-le et approvisionnez-vous. La fiche s'enregistre quand même.</p>
    </div>
@elseif($a['rupture'] ?? false)
    <div class="bg-error-bg border border-error-deep/30 rounded-lg p-md flex items-start justify-between gap-sm shadow-sm flex-wrap" role="alert">
        <div class="flex items-start gap-sm">
            <span class="material-symbols-outlined text-error-deep text-[22px] flex-shrink-0 mt-0.5">warning</span>
            <div class="text-xs text-error-deep">
                <p class="font-bold text-sm">Autonomie alimentaire : rupture de stock</p>
                <p>Le stock de {{ $a['product']->name }} est épuisé ({{ $a['stock_kg'] }} Kg) : approvisionnez-vous. La fiche s'enregistre quand même.</p>
            </div>
        </div>
        <a wire:navigate href="/achats-commandes" class="flex-shrink-0 text-xs font-bold bg-error-red hover:bg-error-deep text-white px-md py-2 rounded-full whitespace-nowrap shadow-sm">Commander Stock</a>
    </div>
@elseif($a['inconnu'] ?? false)
    <div class="bg-surface-zebra border border-outline-variant rounded-lg p-sm text-xs text-brand-forest">
        Autonomie alimentaire : <strong>—</strong> ({{ $a['product']->name }}, {{ $a['stock_kg'] }} Kg en stock) — la consommation du jour est inconnue tant que les effectifs par catégorie le sont.
    </div>
@elseif($a['critique'] ?? false)
    <div class="bg-error-bg border border-error-deep/30 rounded-lg p-md flex items-start justify-between gap-sm shadow-sm flex-wrap" role="alert">
        <div class="flex items-start gap-sm">
            <span class="material-symbols-outlined text-error-deep text-[22px] flex-shrink-0 mt-0.5">warning</span>
            <div class="text-xs text-error-deep">
                <p class="font-bold text-sm">Alerte critique - Autonomie alimentaire</p>
                <p>Le stock de {{ $a['product']->name }} ne couvre plus que {{ $a['autonomie_jours'] }} jours de consommation théorique du cheptel actif ! Approvisionnez-vous.</p>
            </div>
        </div>
        <a wire:navigate href="/achats-commandes" class="flex-shrink-0 text-xs font-bold bg-error-red hover:bg-error-deep text-white px-md py-2 rounded-full whitespace-nowrap shadow-sm">Commander Stock</a>
    </div>
@else
    <div class="bg-brand-emerald/5 border border-brand-emerald/20 rounded-lg p-sm text-xs text-brand-forest">
        Autonomie alimentaire : <strong>{{ $a['autonomie_jours'] }} jours</strong> ({{ $a['product']->name }}, {{ $a['stock_kg'] }} Kg en stock).
    </div>
@endif
