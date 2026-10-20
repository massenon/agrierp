@extends('errors.layout')

@section('code', '401')
@section('title', 'Connexion requise')
@section('message', "Votre session a expiré ou vous n'êtes pas connecté. Reconnectez-vous pour continuer.")
@section('actions')
    <a class="bouton" href="{{ url('/login') }}">Se connecter</a>
@endsection
