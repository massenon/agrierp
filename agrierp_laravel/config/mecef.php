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
];
