{{--
    Ticket H11 — bandeau « Rappel du cycle » d'incubation du poste, APRÈS le contenu du Blade (dernière étape active,
    comme au poste). Volailles : Mise en Incubation J0 → Éclosion Attendue J+21 ; Escargots : Placement Bac de Ponte J0 →
    Éclosion Naissains Attendue J+25. Reçoit : $volailles (bool).
--}}
@if($volailles)
    <x-cycle-reminder :steps="[
        ['label' => 'Mise en Incubation J0'],
        ['label' => 'Éclosion Attendue J+21', 'active' => true],
    ]" />
@else
    <x-cycle-reminder :steps="[
        ['label' => 'Placement Bac de Ponte J0'],
        ['label' => 'Éclosion Naissains Attendue J+25', 'active' => true],
    ]" />
@endif
