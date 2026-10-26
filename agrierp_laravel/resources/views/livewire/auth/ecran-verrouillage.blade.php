<div>
    <x-verrou-session :page="true" :verrouille="true" minutes="{{ $minutes }}" :nom="$nom" :identifiant="$identifiant" />
    <x-toast-container />
</div>
