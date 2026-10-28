<?php

/**
 * Ticket VC-5 — MODULE MeCeF (facture normalisée, retransmission), DÉSACTIVÉ jusqu'à sa configuration.
 *
 * `MECEF_ACTIF=false` (défaut) : aucune facture normalisée n'est transmise, les ventes restent « en attente » sans alerte,
 * le lien « Facturation & MeCeF » disparaît du menu et la page répond « module désactivé ». Le passage à `true` suppose une
 * passerelle réelle liée dans `AppServiceProvider` (aujourd'hui `FakeMecefGateway`) et la configuration du dispositif.
 * Les tests mettent `MECEF_ACTIF=true` (phpunit.xml) : le circuit lui-même reste couvert.
 */
return [
    'actif' => (bool) env('MECEF_ACTIF', false),
];
