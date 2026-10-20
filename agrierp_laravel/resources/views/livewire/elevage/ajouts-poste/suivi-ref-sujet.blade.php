{{--
    Ticket H11 — référence de femelle ou de mâle : un LIEN vers la fiche du sujet (`elevage.animal-details`) quand un sujet
    enregistré porte ce nom, du texte sinon (comme `_celluleRef` du poste : un lien vers une fiche inexistante serait pire
    que du texte). Reçoit : $ref (?string), $sujets (identifier → id).
--}}
@if($ref !== null && isset($sujets[$ref]))
    <a href="{{ route('elevage.animal-details', $sujets[$ref]) }}" class="text-brand-emerald underline hover:text-brand-forest">{{ $ref }}</a>
@else
    {{ $ref ?? '—' }}
@endif
