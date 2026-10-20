@extends('errors.layout')

@section('code', '503')
@section('title', 'Service momentanément indisponible')
@section('message', 'AgriERP est en maintenance. Réessayez dans quelques minutes.')
@section('actions')
    <a class="bouton" href="javascript:location.reload()">Réessayer</a>
@endsection
