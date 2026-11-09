<?php

/**
 * MECEF-1 : ce commutateur n'est plus que la VALEUR PAR DÉFAUT. Le mode (désactivé / e-MECeF / boîtier) se règle en base
 * (Paramètres, Données de l'Entreprise) et prime dès qu'il est enregistré ; tant qu'il ne l'est pas, `MECEF_ACTIF=true` donne
 * la passerelle de démonstration (`simule`) et `false` désactive. Lecture unique : `App\Services\Mecef\MecefReglage`.
 *
 * Ticket VC-5 — MODULE MeCeF (facture normalisée, retransmission), DÉSACTIVÉ jusqu'à sa configuration.
 *
 * `MECEF_ACTIF=false` (défaut) : aucune facture normalisée n'est transmise, les ventes restent « en attente » sans alerte,
 * le lien « Facturation & MeCeF » disparaît du menu et la page répond « module désactivé ». Le passage à `true` suppose une
 * passerelle réelle liée dans `AppServiceProvider` (aujourd'hui `FakeMecefGateway`) et la configuration du dispositif.
 * Les tests mettent `MECEF_ACTIF=true` (phpunit.xml) : le circuit lui-même reste couvert.
 */
return [
    'actif' => (bool) env('MECEF_ACTIF', false),

    /*
     * CONF-1 — VALEURS DE REPLI e-MECeF lues de `.env` (variables du paquet de référence). Elles ne servent QUE quand le
     * réglage correspondant est vide en base : le réglage saisi à l'écran (Paramètres > Facturation normalisée) prime toujours.
     * Le jeton `SGMEF_TOKEN` n'est jamais affiché, jamais servi au poste, jamais journalisé.
     * Hors périmètre (volontairement non repris du paquet) : interface web, file d'attente, préfixe de route, polling.
     * Lecture unique : `App\Services\Mecef\MecefReglage`.
     */
    'sgmef' => [
        'api_url' => env('SGMEF_API_URL'),
        'token' => env('SGMEF_TOKEN'),
        'default_ifu' => env('SGMEF_DEFAULT_IFU'),
        'default_operator_name' => env('SGMEF_DEFAULT_OPERATOR_NAME'),
        'default_operator_id' => env('SGMEF_DEFAULT_OPERATOR_ID'),
        'http_timeout' => (int) env('SGMEF_HTTP_TIMEOUT', 30),
        'connect_timeout' => (int) env('SGMEF_CONNECT_TIMEOUT', 10),
        'verify_ssl' => filter_var(env('SGMEF_VERIFY_SSL', true), FILTER_VALIDATE_BOOLEAN),
    ],
];
