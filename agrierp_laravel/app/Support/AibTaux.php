<?php

namespace App\Support;

/**
 * L'AIB (acompte sur impôt sur les bénéfices) retenu à l'ACHETEUR d'une facture normalisée.
 *
 * Valeurs stockées (`sales.aib_taux`) : `5%` (cas général, défaut), `1%`, `N/A` — les trois valeurs de `aib` du boîtier
 * (`eltrade-cc300-driver/bill.spec.json` : `"1%"`, `"5%"`, `"N/A"`), pour que le futur mode boîtier (MECEF-2) les reprenne
 * telles quelles. Vers l'API e-MECeF en ligne, le champ `aib` de la facture prend `B` (5 %) ou `A` (1 %) — « L'AIB doit être
 * A (1%) ou B (5%) » dans le paquet de référence — et est OMIS pour `N/A`.
 *
 * ⚠️ Le MONTANT de l'AIB n'est jamais calculé ici : c'est la DGI qui le calcule et le renvoie (`mecef_aib_montant`).
 */
final class AibTaux
{
    public const CINQ = '5%';

    public const UN = '1%';

    public const AUCUN = 'N/A';

    public const DEFAUT = self::CINQ;

    /** Ordre d'affichage de la liste (web et poste) : 5 % d'abord, c'est le cas général. */
    public const LIBELLES = [
        self::CINQ => '5 %',
        self::UN => '1 %',
        self::AUCUN => 'Aucun (N/A)',
    ];

    /** Code du champ `aib` de l'API e-MECeF en ligne (`null` = champ omis). */
    public static function codeApi(?string $taux): ?string
    {
        return match ($taux) {
            self::CINQ => 'B',
            self::UN => 'A',
            default => null,
        };
    }
}
