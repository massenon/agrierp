@extends('errors.layout')

{{-- Tout autre code 5xx sans page dédiée (502, 504…). --}}
@section('code', (string) $exception->getStatusCode())
@section('title', 'Erreur du serveur')
@section('message', "Une erreur inattendue est survenue. Réessayez dans un instant ; si le problème persiste, contactez l'administrateur.")
