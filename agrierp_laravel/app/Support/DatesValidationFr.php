<?php

namespace App\Support;

use Carbon\Carbon;
use Illuminate\Support\Facades\Validator;

/**
 * Ticket U5 (D-U5) — LA DATE DE COMPARAISON DES RÈGLES DE DATE, EN FRANÇAIS.
 *
 * `lang/fr/validation.php` traduit la phrase, mais Laravel remplace `:date` par le paramètre BRUT
 * de la règle : `before_or_equal:today` donnait « … antérieure ou égale à today. », et une date
 * fixe sortait au format ISO (« 2026-10-19 »). Treize règles du web portent `today`, deux `now`.
 *
 * Ce remplaçant ne change AUCUNE règle — seulement le texte de `:date` :
 *   - les mots relatifs de `strtotime` (today, now, tomorrow, yesterday) → « aujourd'hui »… ;
 *   - une date fixe → jj/mm/aaaa ;
 *   - le nom d'un autre champ (`after_or_equal:start`) → son libellé, comme le fait Laravel.
 */
class DatesValidationFr
{
    /** Règles dont le message porte `:date`. */
    private const REGLES = ['before', 'before_or_equal', 'after', 'after_or_equal', 'date_equals'];

    /** Mots relatifs reconnus par `strtotime`, et leur traduction. */
    private const MOTS = [
        'today' => 'aujourd\'hui',
        'now' => 'maintenant',
        'tomorrow' => 'demain',
        'yesterday' => 'hier',
    ];

    public static function enregistrer(): void
    {
        foreach (self::REGLES as $regle) {
            Validator::replacer($regle, function (string $message, string $attribut, string $r, array $parametres, $validator): string {
                return str_replace(':date', self::libelle($parametres[0] ?? '', $validator), $message);
            });
        }
    }

    /** Texte français qui remplace `:date` pour le paramètre d'une règle de date. */
    public static function libelle(string $parametre, $validator = null): string
    {
        $cle = strtolower(trim($parametre));

        if (isset(self::MOTS[$cle])) {
            return self::MOTS[$cle];
        }

        // Pas une date : c'est le nom d'un autre champ (« after_or_equal:start »).
        if (strtotime($parametre) === false) {
            return $validator ? $validator->getDisplayableAttribute($parametre) : $parametre;
        }

        try {
            return Carbon::parse($parametre)->format('d/m/Y');
        } catch (\Throwable) {
            return $parametre;
        }
    }
}
