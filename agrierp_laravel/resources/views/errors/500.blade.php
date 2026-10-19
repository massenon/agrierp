@extends('errors.layout')

{{-- Le détail technique reste dans le journal (`storage/logs`), jamais à l'écran. --}}
@section('code', '500')
@section('title', 'Erreur du serveur')
@section('message', "Une erreur inattendue est survenue. Vos données déjà enregistrées sont intactes. Réessayez dans un instant ; si le problème persiste, contactez l'administrateur.")
