<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
{{--
    ATT-2 — ATTESTATION : FIDÉLITÉ AU MODÈLE OFFICIEL (attestation de formation du 24/10/2026).

    A4 PAYSAGE, tout en positions absolues (points) : DomPDF ne sait pas faire flex ni grille, et le modèle est
    une page unique à composition fixe. Mesures relevées sur la capture du modèle (2000 × 1413 px = 842 × 595 pt,
    1 px = 0,421 pt). Ressources : `resources/attestation/` (logo, filigrane, décor floral, polices libres).
--}}
<style>
    @page { size: 842pt 595pt; margin: 0; }
    @font-face { font-family: 'Corps'; font-style: normal; font-weight: normal; src: url('{{ str_replace('\\', '/', $polices) }}/Caladea-400.ttf') format('truetype'); }
    @font-face { font-family: 'Corps'; font-style: normal; font-weight: bold; src: url('{{ str_replace('\\', '/', $polices) }}/Caladea-700.ttf') format('truetype'); }
    @font-face { font-family: 'Corps'; font-style: italic; font-weight: normal; src: url('{{ str_replace('\\', '/', $polices) }}/Caladea-400i.ttf') format('truetype'); }
    @font-face { font-family: 'Corps'; font-style: italic; font-weight: bold; src: url('{{ str_replace('\\', '/', $polices) }}/Caladea-700i.ttf') format('truetype'); }
    @font-face { font-family: 'Note'; font-style: normal; font-weight: normal; src: url('{{ str_replace('\\', '/', $polices) }}/Carlito-400.ttf') format('truetype'); }
    @font-face { font-family: 'Note'; font-style: normal; font-weight: bold; src: url('{{ str_replace('\\', '/', $polices) }}/Carlito-700.ttf') format('truetype'); }
    @font-face { font-family: 'Note'; font-style: italic; font-weight: bold; src: url('{{ str_replace('\\', '/', $polices) }}/Carlito-700i.ttf') format('truetype'); }
    @font-face { font-family: 'Titre'; font-style: normal; font-weight: normal; src: url('{{ str_replace('\\', '/', $polices) }}/Bevan-400.ttf') format('truetype'); }

    body { margin: 0; padding: 0; font-family: 'Corps', 'DejaVu Serif', serif; font-size: 14pt; color: #000; }
    .abs { position: absolute; }
    .vert { color: #2e6b1a; }

    .decor { left: 0; top: 0; width: 842pt; height: 595pt; }
    .filigrane { left: 224pt; top: 128pt; width: 395pt; }
    .logo { left: 6pt; top: -6pt; width: 146pt; }

    .nom-ferme { left: 150pt; top: 4.6pt; width: 596pt; text-align: center; font-family: 'Titre', 'Corps', serif; font-size: 20pt; line-height: 24pt; color: #2e6b1a; }
    .activites { left: 150pt; width: 660pt; text-align: center; font-weight: bold; font-size: 13pt; line-height: 15.2pt; }
    .identite { left: 150pt; width: 660pt; text-align: center; font-size: 13pt; line-height: 15.2pt; }

    .lieu-date { right: 27pt; top: 111.4pt; width: 400pt; text-align: right; font-family: 'Note', sans-serif; font-weight: bold; font-style: italic; font-size: 12pt; }
    .numero { left: 34pt; top: 147pt; font-family: 'Note', sans-serif; font-weight: bold; font-size: 12pt; }

    .titre-doc { left: 34pt; top: 198.5pt; width: 781pt; text-align: center; font-weight: bold; font-size: 25pt; }
    /* Soulignement par une bordure : le text-decoration de DomPDF suit les métriques de la police et coupe les lettres. */
    .souligne { display: inline-block; border-bottom: 1.3pt solid #000; padding-bottom: 0; line-height: 24pt; }

    .texte { left: 34pt; width: 781pt; text-align: justify; font-size: 15.2pt; line-height: 17.7pt; }
    .texte p { margin: 0; }
    .puces { margin: 6pt 0 0 21pt; padding: 0; }
    .puce { margin: 0; padding: 0 0 0 16pt; position: relative; font-size: 14.2pt; }
    .fleche { position: absolute; left: -3pt; top: 1pt; font-family: 'DejaVu Sans', sans-serif; font-size: 15pt; line-height: 15pt; }
    .suite { margin-top: 5.5pt !important; }

    .sig { font-size: 11.7pt; line-height: 12.8pt; text-align: right; }
    .sig-titre { text-align: center; margin: 0; font-weight: bold; font-size: 11.7pt; line-height: 14pt; }
    .sig-titre span { display: inline-block; border-bottom: 1pt solid #000; line-height: 12.5pt; }
    .sig-nom { font-weight: bold; font-size: 13.7pt; margin: 0; line-height: 16pt; text-align: right; white-space: nowrap; }
    .sig-fonction { margin: 1.5pt 0 0; font-size: 11.5pt; line-height: 13pt; text-align: right; }

    .pied { left: 34pt; width: 825pt; text-align: center; font-size: 13pt; line-height: 15.2pt; }
    .sep { display: inline-block; line-height: 12pt; }
    .lien { color: #0563c1; display: inline-block; border-bottom: .8pt solid #0563c1; line-height: 12pt; }
</style>
</head>
<body>

    <img class="abs decor" src="{{ $images['decor'] }}">
    <img class="abs filigrane" src="{{ $images['filigrane'] }}">
    <img class="abs logo" src="{{ $images['logo'] }}">

    <div class="abs nom-ferme">{{ $entete['nom'] }}</div>
    <div class="abs activites" style="top: 34.5pt;">{{ $entete['activites'][0] }}</div>
    <div class="abs activites" style="top: 49.7pt;">{{ $entete['activites'][1] }}</div>
    <div class="abs identite" style="top: 64.9pt;"><strong>Adresse</strong> : {{ $entete['adresse'] }}</div>
    <div class="abs identite" style="top: 80.1pt;"><strong>Téléphone</strong> : {{ $entete['telephones'] }}, <strong>RCCM</strong> : {{ $entete['rccm'] }}</div>

    <div class="abs lieu-date">{{ $entete['lieu'] }}, le {{ $dateLieu }}</div>
    <div class="abs numero">{{ $numero }}</div>

    <div class="abs titre-doc"><span class="souligne">{{ mb_strtoupper($title) }}</span></div>

    @php
        $long = mb_strlen($corps) + mb_strlen((string) $appreciation) + array_sum(array_map('mb_strlen', $puces));
        $taille = $long > 1000 ? '13.4pt' : '15.2pt';
        $pas = $long > 1000 ? '15.9pt' : '17.7pt';
    @endphp
    <div class="abs texte" style="top: 232.7pt; font-size: {{ $taille }}; line-height: {{ $pas }};">
        <p>{!! \App\Services\AttestationService::enHtml($corps) !!}</p>

        @if(! empty($puces))
        <div class="puces">
            @foreach($puces as $ligne)
            <div class="puce"><span class="fleche">&#10146;</span>{{ str_replace("'", '’', $ligne) }}</div>
            @endforeach
        </div>
        @endif

        @if($appreciation)
        <p>{!! \App\Services\AttestationService::enHtml($appreciation) !!}</p>
        @endif

        <p class="suite">En foi de quoi, la présente attestation lui est délivrée pour servir et valoir ce que de droit.</p>
    </div>

    @if(count($signataires) === 1 && ($signataires[0]['position'] ?? null) === 1)
        {{-- Signataire UNIQUE (palier court) : nom, fonction ET signature (cachet et paraphe du Directeur) CENTRÉS en bas de page. --}}
        @php $unique = $signataires[0]; @endphp
        <div class="abs" style="left: 221pt; top: {{ $signatureHaut ?? 434 }}pt; width: 400pt; text-align: center;">
            @if(! empty($images['signature']))<img src="{{ $images['signature'] }}" style="height: 74pt; margin: 0 0 -6pt;" alt="Signature">@endif
            <p class="sig-nom" style="text-align: center; margin-top: 0;">{{ $unique['nom'] }}</p>
            @if($unique['fonction'] !== '')<p class="sig-fonction" style="text-align: center;">{{ str_replace("'", '’', $unique['fonction']) }}</p>@endif
        </div>
    @else
    @foreach($signataires as $sig)
        @php
            // Position 2 = Examinateur (gauche), 3 = Président du Jury (centre), 1 = Directeur Général (droite) :
            // [bord gauche de la boîte, largeur, retrait de la fonction] mesurés sur le modèle (pt).
            [$gauche, $largeur, $retrait] = [2 => [38, 205, 0], 3 => [316, 208, 0], 1 => [623, 190, 40]][$sig['position']] ?? [623, 190, 40];
            $haut = $sig['titre'] !== '' ? (($sig['position'] === 3) ? 482.5 : 479) : 500;
        @endphp
        <div class="abs sig" style="left: {{ $gauche }}pt; top: {{ $haut }}pt; width: {{ $largeur }}pt;">
            @if($sig['titre'] !== '')<p class="sig-titre"><span>{{ $sig['titre'] }}</span></p>@endif
            <p class="sig-nom" style="margin-top: {{ $sig['titre'] !== '' ? 6 : 0 }}pt;">{{ $sig['nom'] }}</p>
            @if($sig['fonction'] !== '')<p class="sig-fonction" style="padding-left: {{ $retrait }}pt;">{{ str_replace("'", '’', $sig['fonction']) }}</p>@endif
        </div>
    @endforeach
    @endif

    <div class="abs pied" style="top: 559pt;"><strong>E-mail</strong> : <span class="lien">{{ $entete['emails'][0] }}</span><span class="sep"> / </span><span class="lien">{{ $entete['emails'][1] }}</span></div>
    <div class="abs pied" style="top: 571.4pt;"><strong>Site web</strong>:<span class="lien">{{ $entete['site'] }}</span></div>

</body>
</html>
