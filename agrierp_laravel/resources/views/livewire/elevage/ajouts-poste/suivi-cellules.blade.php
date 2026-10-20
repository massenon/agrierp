{{--
    Ticket H11 — cellules des colonnes ajoutées du poste pour un cycle (SuiviReproduction::getColonnesPosteProperty),
    ou, sans cycle ($cellules = null), la cellule vide qui complète la ligne « Aucune saillie déclarée ».
    Reçoit : $colonnes, $cellules (?array).
--}}
@if($cellules === null)
    <td colspan="{{ count($colonnes) }}" class="px-sm py-lg"></td>
@else
    @foreach($colonnes as $c => $colonne)
        <td data-label="{{ $colonne }}" class="px-sm py-sm">{{ $cellules[$c] ?? '—' }}</td>
    @endforeach
@endif
