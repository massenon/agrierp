<?php

/*
 * Ticket S3 — seule la durée de vie des jetons est fixée ici ; toutes les autres clés gardent la valeur du
 * paquet Sanctum (fusionnée par son fournisseur de service).
 *
 * 🔴 Les jetons des postes n'expiraient jamais : un jeton copié (sauvegarde, export de base) restait valable
 * indéfiniment. 90 jours couvrent un poste resté longtemps hors ligne ; au-delà, le poste affiche « Session
 * expirée : reconnectez-vous » et ses saisies en attente restent conservées localement jusqu'à la reconnexion.
 * `SANCTUM_EXPIRATION` (en minutes) permet d'ajuster sans redéployer ; vide = jamais (déconseillé).
 */
return [
    'expiration' => env('SANCTUM_EXPIRATION', 60 * 24 * 90),
];
