@extends('errors.layout')

{{--
    Le motif posé par l'application (`abort_unless(…, 403, "Seul l'administrateur…")`) est affiché
    tel quel : il est déjà en français. Le motif par défaut du framework (« This action is
    unauthorized. », levé par `$this->authorize()`) passe par `__()` et `lang/fr.json`.
--}}
@section('code', '403')
@section('title', 'Accès refusé')
@section('message', __($exception->getMessage() ?: "Votre rôle ne permet pas d'accéder à cette page."))
