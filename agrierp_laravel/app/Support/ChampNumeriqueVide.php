<?php

namespace App\Support;

use Livewire\Component;

use function Livewire\on;

/**
 * Un champ numérique VIDÉ au clavier ne doit jamais casser l'écran.
 *
 * Constat (21/10/2026, fiche Lapins : « Property [$ne] not found », puis « [$mortChair] ») : le navigateur envoie
 * `''` quand on efface un `<input type="number">` ; le middleware `ConvertEmptyStringsToNull` le change en `null` ;
 * Livewire ne peut pas l'affecter à une propriété `public int` (non nulle) et la laisse NON INITIALISÉE. Le rendu
 * suivant lit `$this->ne` et lève `PropertyNotFoundException` (erreur 500), sur tous les écrans à champ numérique.
 *
 * Règle : après la mise à jour d'une propriété publique de premier niveau, typée `int` ou `float` NON NULLE et
 * restée non initialisée, on la remet à zéro — un champ vide d'une saisie numérique vaut 0, comme au poste.
 * Une propriété nullable (`?int`) garde son `null` (« inconnu », jamais 0).
 */
final class ChampNumeriqueVide
{
    public static function enregistrer(): void
    {
        on('update', function (Component $component, string $chemin, mixed $valeur) {
            return function () use ($component, $chemin): void {
                self::normaliser($component, $chemin);
            };
        });
    }

    public static function normaliser(Component $component, string $chemin): void
    {
        $nom = explode('.', $chemin)[0];

        if (! property_exists($component, $nom)) {
            return;
        }

        $propriete = new \ReflectionProperty($component, $nom);
        $type = $propriete->getType();

        if (! $propriete->isPublic() || ! $type instanceof \ReflectionNamedType
            || $type->allowsNull() || $propriete->isInitialized($component)) {
            return;
        }

        match ($type->getName()) {
            'int' => $component->{$nom} = 0,
            'float' => $component->{$nom} = 0.0,
            default => null,
        };
    }
}
