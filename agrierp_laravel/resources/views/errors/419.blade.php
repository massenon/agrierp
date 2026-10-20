@extends('errors.layout')

@section('code', '419')
@section('title', 'Page expirée')
@section('message', 'La page est restée ouverte trop longtemps et votre session a expiré. Rechargez-la, puis recommencez votre saisie.')
@section('actions')
    <a class="bouton" href="javascript:location.reload()">Recharger la page</a>
@endsection
