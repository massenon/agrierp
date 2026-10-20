<?php

/**
 * Ticket U5 (D-U5) — statuts de la réinitialisation de mot de passe en français.
 *
 * Renvoyés par `Password::sendResetLink()` / `Password::reset()`. L'écran de connexion ne les
 * affiche pas tels quels (même message que l'adresse existe ou non, pour ne pas révéler les
 * comptes) ; ils sont traduits pour tout autre usage.
 */
return [

    'reset' => 'Votre mot de passe a été réinitialisé.',
    'sent' => 'Le lien de réinitialisation du mot de passe vous a été envoyé par e-mail.',
    'throttled' => 'Veuillez patienter avant de réessayer.',
    'token' => 'Ce lien de réinitialisation du mot de passe est invalide ou a expiré.',
    'user' => 'Aucun compte ne correspond à cette adresse e-mail.',

];
