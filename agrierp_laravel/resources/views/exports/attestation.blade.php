<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<style>
    body { font-family: 'DejaVu Sans', sans-serif; color: #191c1d; font-size: 11px; padding: 30px 40px; }
    .header { display: flex; justify-content: space-between; align-items: flex-start; border-bottom: 2px solid #052e16; padding-bottom: 14px; margin-bottom: 20px; }
    .company-name { font-weight: 900; color: #052e16; font-size: 13px; }
    .company-meta { font-size: 8px; color: #6f7973; margin-top: 2px; }
    .doc-title { font-weight: bold; color: #065f46; font-size: 13px; text-transform: uppercase; }
    .heading { text-align: center; font-weight: bold; color: #052e16; text-transform: uppercase; letter-spacing: 1px; margin: 24px 0; font-size: 14px; }
    .body-text { line-height: 1.8; text-align: justify; margin-bottom: 16px; }
    .note { font-style: italic; color: #6f7973; margin-bottom: 16px; }
    .signature { margin-top: 50px; text-align: right; }
    .signature p { margin: 2px 0; }
    .signature .role { font-size: 9px; color: #6f7973; }
    .signature .name { font-weight: bold; color: #052e16; border-top: 1px solid #bec9c2; padding-top: 4px; display: inline-block; margin-top: 40px; }
</style>
</head>
<body>
    <div class="header">
        <div>
            <p class="company-name">FERME ÉCOLE OLOUWACHEGOUN</p>
            <p class="company-meta">Attan-Ewé, Arrondissement d'Ikpinlè, Commune d'Adja-Ouèrè, Bénin</p>
            <p class="company-meta">Téléphone : +229 01 97 84 02 85/97 84 02 85, RCCM : RB/PNO/22 A 33870</p>
        </div>
        <p class="doc-title">{{ $title }}</p>
    </div>

    <p class="heading">{{ $title }}</p>

    <p class="body-text">{!! nl2br(e($body)) !!}</p>

    @if($note)
        <p class="note">{{ $note }}</p>
    @endif

    <p>Fait à Ikpinlè, le {{ $date }}.</p>

    <div class="signature">
        <p class="role">Le Directeur Général</p>
        <p class="name">OLOUKOUNLE Olouchegoun Hassimiyou</p>
    </div>
</body>
</html>
