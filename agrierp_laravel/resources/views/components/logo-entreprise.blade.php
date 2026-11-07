@props(['taille' => 26, 'classe' => 'text-accent-yellow'])
{{-- CONF-1 — le logo CHOISI de l'entreprise (Paramètres > Données de l'Entreprise), sinon l'icône d'installation. Point de passage : `IdentiteVisuelle`. --}}
@php($logo = \App\Support\IdentiteVisuelle::logoUrl())
@if($logo)
    <img src="{{ $logo }}" alt="Logo de l'entreprise" class="object-contain flex-shrink-0 rounded" style="height:{{ $taille }}px; width:{{ $taille }}px;" data-logo-entreprise>
@else
    <span class="material-symbols-outlined {{ $classe }}" style="font-size:{{ $taille }}px;">agriculture</span>
@endif
