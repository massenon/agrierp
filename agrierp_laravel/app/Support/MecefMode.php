<?php

namespace App\Support;

/**
 * MECEF-1 — les modes de facturation normalisée. Les trois premiers sont réglables ; `simule` n'existe que quand rien
 * n'est réglé et que le commutateur général `config/mecef.php` est allumé (développement, tests : `FakeMecefGateway`).
 */
final class MecefMode
{
    public const DESACTIVE = 'desactive';

    public const EMECEF = 'emecef';

    public const BOITIER = 'boitier';

    public const SIMULE = 'simule';

    public const REGLABLES = [self::DESACTIVE, self::EMECEF, self::BOITIER];

    public const LIBELLES = [
        self::DESACTIVE => 'Désactivé',
        self::EMECEF => 'e-MECeF (en ligne)',
        self::BOITIER => 'Boîtier MeCeF (à venir)',
    ];

    /** URL de l'API e-MECeF proposée par défaut (production DGI). */
    public const URL_PAR_DEFAUT = 'https://developper.impots.bj/sygmef-emcf/api';
}
