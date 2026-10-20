@extends('errors.layout')

{{-- Le motif technique d'un 404 (« No query results for model … ») n'est jamais affiché. --}}
@section('code', '404')
@section('title', 'Page introuvable')
@section('message', "La page demandée n'existe pas ou a été déplacée. Vérifiez l'adresse, ou revenez à l'accueil.")
