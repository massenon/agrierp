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

    /**
     * Environnement d'ESSAI de la DGI (sans valeur fiscale) : c'est l'adresse proposée tant que rien n'est réglé — un premier essai
     * ne doit jamais partir en production par défaut.
     *
     * ⚠️ Adresses relevées dans le paquet de référence non officiel Banelsems/laraSgmefQR (README, `config/lara_sgmef_qr.php`,
     * cahier des charges : « environnement de test … https://developper.impots.bj/sygmef-emcf ») ; NON confirmées par la
     * documentation de la DGI (injoignable). MECEF-1 avait nommé celle-ci « production » à tort.
     */
    public const URL_ESSAI = 'https://developper.impots.bj/sygmef-emcf/api';

    /** Production DGI, d'après la seule valeur `APP_ENV=production` du même paquet de référence (une source, non confirmée). */
    public const URL_PRODUCTION = 'https://api.impots.bj/sygmef-emcf/api';

    /** Adresse de l'API quand aucune n'est enregistrée : l'environnement d'essai. */
    public const URL_PAR_DEFAUT = self::URL_ESSAI;

    /** Les deux préréglages du formulaire (clé → [libellé, adresse]). */
    public const PREREGLAGES_URL = [
        'production' => ['Production (DGI)', self::URL_PRODUCTION],
        'essai' => ["Environnement d'essai (DGI)", self::URL_ESSAI],
    ];
}
