@extends('errors.layout')

{{-- Tout autre code 4xx sans page dédiée (400, 405, 413…). --}}
@section('code', (string) $exception->getStatusCode())
@section('title', 'Requête impossible')
@section('message', "La demande n'a pas pu être traitée. Revenez à la page précédente et réessayez.")
