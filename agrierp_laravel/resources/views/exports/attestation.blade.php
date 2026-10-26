<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<style>
    body {
        font-family: 'DejaVu Sans', sans-serif;
        color: #191c1d;
        font-size: 11px;
        padding: 20px 40px;
        margin: 0;
    }
    .entete {
        display: flex;
        justify-content: space-between;
        align-items: flex-start;
        border-bottom: 2px solid #052e16;
        padding-bottom: 10px;
        margin-bottom: 10px;
    }
    .ferme-nom {
        font-weight: 900;
        color: #052e16;
        font-size: 13px;
        margin: 0 0 2px;
    }
    .ferme-activites {
        font-size: 7px;
        color: #065f46;
        letter-spacing: 0.2px;
        margin: 2px 0;
        font-weight: bold;
    }
    .ferme-meta {
        font-size: 8px;
        color: #6f7973;
        margin: 1px 0;
    }
    .lieu-date {
        text-align: right;
        font-size: 10px;
        font-weight: bold;
        color: #052e16;
        white-space: nowrap;
        padding-left: 20px;
    }
    .numero {
        text-align: right;
        font-size: 10px;
        color: #065f46;
        font-weight: bold;
        margin: 6px 0;
    }
    .titre-doc {
        text-align: center;
        font-weight: 900;
        font-size: 14px;
        text-transform: uppercase;
        letter-spacing: 1.5px;
        color: #052e16;
        margin: 14px 0 10px;
        text-decoration: underline;
    }
    .domaines-titre {
        font-size: 9px;
        font-weight: bold;
        color: #374151;
        margin-bottom: 4px;
    }
    .domaines {
        display: flex;
        flex-wrap: wrap;
        gap: 0 30px;
        padding: 6px 0;
        margin-bottom: 10px;
        border-top: 1px solid #d1d5db;
        border-bottom: 1px solid #d1d5db;
    }
    .domaine {
        display: flex;
        align-items: center;
        gap: 5px;
        font-size: 10px;
        margin: 2px 0;
    }
    .cb {
        width: 11px;
        height: 11px;
        border: 1px solid #052e16;
        display: inline-block;
        text-align: center;
        line-height: 11px;
        font-size: 9px;
        font-weight: bold;
    }
    .cb-coche { background-color: #052e16; color: #ffffff; }
    .corps {
        line-height: 1.9;
        text-align: justify;
        margin: 12px 0;
        font-size: 11px;
    }
    .appreciation {
        font-style: italic;
        color: #374151;
        margin: 8px 0 16px;
        line-height: 1.6;
    }
    .signatures {
        display: flex;
        justify-content: space-between;
        margin-top: 40px;
    }
    .sig { text-align: center; width: 30%; }
    .sig-titre { font-size: 9px; color: #6f7973; margin-bottom: 0; }
    .sig-espace { height: 48px; }
    .sig-nom {
        font-weight: bold;
        color: #052e16;
        font-size: 10px;
        border-top: 1px solid #bec9c2;
        padding-top: 4px;
        display: inline-block;
        min-width: 120px;
    }
    .sig-vide {
        display: inline-block;
        min-width: 120px;
        border-top: 1px solid #bec9c2;
        height: 4px;
    }
</style>
</head>
<body>

    <div class="entete">
        <div>
            <p class="ferme-nom">FERME ÉCOLE OLOUWACHEGOUN</p>
            <p class="ferme-activites">MARAÎCHAGE - ÉLEVAGE - PISCICULTURE - AVICULTURE - TRANSFORMATION DES PRODUITS AGRICOLES - GESTION D'ENTREPRISE</p>
            <p class="ferme-meta">Attan-Ewé, Arrondissement d'Ikpinlè, Commune d'Adja-Ouèrè, Bénin</p>
            <p class="ferme-meta">Tél. : +229 01 97 84 02 85 &nbsp;|&nbsp; RCCM : RB/PNO/22 A 33870</p>
        </div>
        <div class="lieu-date">ATTAN-ÉWÉ, le {{ $dateLieu }}</div>
    </div>

    <p class="numero">Réf. : {{ $numero }}</p>

    <p class="titre-doc">{{ $title }}</p>

    @if(! empty($domaines))
    <p class="domaines-titre">Domaine(s) de formation :</p>
    <div class="domaines">
        @foreach(\App\Services\AttestationService::DOMAINES as $cle => $libelle)
        <div class="domaine">
            <span class="cb {{ in_array($cle, $domaines) ? 'cb-coche' : '' }}">{{ in_array($cle, $domaines) ? '&#10003;' : '&nbsp;' }}</span>
            <span>{{ $libelle }}</span>
        </div>
        @endforeach
    </div>
    @endif

    <p class="corps">{!! nl2br(e($body)) !!}</p>

    @if($note)
    <p class="appreciation">{{ $note }}</p>
    @endif

    <div class="signatures">
        <div class="sig">
            <p class="sig-titre">{{ $sig2Titre }}</p>
            <div class="sig-espace"></div>
            @if($sig2Nom)
            <span class="sig-nom">{{ $sig2Nom }}</span>
            @else
            <span class="sig-vide"></span>
            @endif
        </div>
        <div class="sig">
            <p class="sig-titre">{{ $sig3Titre }}</p>
            <div class="sig-espace"></div>
            @if($sig3Nom)
            <span class="sig-nom">{{ $sig3Nom }}</span>
            @else
            <span class="sig-vide"></span>
            @endif
        </div>
        <div class="sig">
            <p class="sig-titre">{{ $sig1Titre }}</p>
            <div class="sig-espace"></div>
            @if($sig1Nom)
            <span class="sig-nom">{{ $sig1Nom }}</span>
            @else
            <span class="sig-vide"></span>
            @endif
        </div>
    </div>

</body>
</html>
