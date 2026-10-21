<?php

namespace App\Support;

use Illuminate\Support\Str;

/**
 * Ticket UNI — CLÉ DE COMPARAISON des codes et libellés qui doivent être uniques (code de bande, libellé de
 * catégorie de produits).
 *
 * « AVI-2026-01 », « avi-2026-01 » et « AVI-2026-01  » (espace en fin) désignent la même chose pour une personne,
 * et la collation du serveur (`utf8mb4_unicode_ci`) les confond déjà sur l'accent et la casse : la clé fait de même
 * pour la casse et les accents, et ajoute les espaces (début, fin, doubles) que la collation ne couvre pas.
 * Le poste a la même clé (`cleUnicite`, `pmp_service.dart`) : une valeur est « déjà prise » des deux côtés
 * exactement dans les mêmes cas.
 */
class CleUnicite
{
    public static function cle(?string $texte): string
    {
        $compact = trim((string) preg_replace('/\s+/u', ' ', (string) $texte));

        return Str::lower(Str::ascii($compact));
    }
}
