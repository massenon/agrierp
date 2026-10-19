<?php

/**
 * Ticket U5 (D-U5) — messages d'authentification en français.
 *
 * L'écran de connexion (`Livewire\Auth\Login`) et l'API (`Api\AuthController`) posent leurs propres
 * phrases (« Identifiants incorrects. ») ; ces lignes couvrent tout ce qui passe par les messages
 * par défaut du framework.
 */
return [

    'failed' => 'Identifiants incorrects.',
    'password' => 'Le mot de passe saisi est incorrect.',
    'throttle' => 'Trop de tentatives de connexion. Veuillez réessayer dans :seconds secondes.',

];
