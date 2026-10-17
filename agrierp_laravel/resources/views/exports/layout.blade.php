<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <title>{{ $reportTitle }} — AgriERP</title>
    <style>
        /**
         * En-tête institutionnel — nuancier RÉSERVÉ aux documents imprimés
         * (DIRECTIVE_PDF_HEADER_OFFICIEL_ENTETE_EXACT.md §Constat Important) :
         * ces 3 couleurs ne sont JAMAIS utilisées dans l'UI web/Flutter, qui
         * garde brand-forest/brand-emerald (Document 04 §1). Deux nuanciers
         * séparés, chacun à son usage exclusif.
         *   Titre            #375623 (RGB 55,86,35)
         *   Anneau du logo   #123E23 (RGB 18,62,35) — asset déjà coloré, pour référence
         *   Feuillage/accent #497A42 (RGB 73,122,66) — asset déjà coloré, pour référence
         */
        body { font-family: 'DejaVu Sans', sans-serif; font-size: 10px; color: #191c1d; }
        .header-table { width: 100%; border-collapse: collapse; margin-bottom: 8px; }
        .header-logo { width: 110px; vertical-align: top; }
        .header-logo img { width: 100px; }
        .header-title {
            color: #375623;
            font-family: 'Georgia', 'DejaVu Serif', serif;
            font-weight: bold;
            font-size: 17px;
            margin: 0 0 4px 0;
        }
        .header-box {
            width: 100%;
            border: 1px solid #000;
            border-collapse: collapse;
            font-size: 9px;
            text-align: center;
        }
        .header-box td { padding: 4px; }
        .report-meta {
            margin-top: 10px;
            padding-top: 6px;
            border-top: 2px solid #052e16;
        }
        .report-meta h2 { color: #052e16; font-size: 13px; margin: 0 0 2px 0; }
        .report-meta p { color: #6f7973; font-size: 9px; margin: 0; }
        .content { margin-top: 10px; }
        table.data-table { width: 100%; border-collapse: collapse; font-size: 9px; }
        table.data-table th {
            background: #052e16; color: #fff; text-align: left;
            padding: 5px 6px; font-size: 8.5px; text-transform: uppercase;
        }
        table.data-table td { padding: 4px 6px; border-bottom: 1px solid #bec9c2; }
        table.data-table tr:nth-child(even) td { background: #f3f4f5; }
        .footer {
            position: fixed;
            bottom: -25px;
            left: 0; right: 0;
            text-align: center;
            font-size: 8px;
            color: #191c1d;
        }
        .footer a { color: #2563EB; text-decoration: underline; }
    </style>
</head>
<body>

    <table class="header-table">
        <tr>
            <td class="header-logo">
                @if(file_exists($companyLogo))
                    <img src="{{ $companyLogo }}" alt="Logo Ferme École Olouwachegoun">
                @endif
            </td>
            <td>
                <p class="header-title">{{ $companyName }}</p>
                <table class="header-box">
                    <tr>
                        <td>
                            <strong>{{ $companyActivities }}</strong><br>
                            <strong>Adresse</strong> : {{ $companyAddress }}<br>
                            <strong>Téléphone</strong> : {{ $companyPhone }}, <strong>RCCM</strong> : {{ $companyRccm }}
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
    </table>

    <div class="report-meta">
        <h2>{{ $reportTitle }}</h2>
        <p>Période : {{ $period }} &nbsp;·&nbsp; Généré le {{ now()->translatedFormat('d/m/Y à H:i') }} par {{ $author }}</p>
    </div>

    <div class="content">
        @include($reportView)
    </div>

    <div class="footer">
        <strong>E-mail :</strong> <a href="mailto:olomagloire1@gmail.com">olomagloire1@gmail.com</a> / <a href="mailto:contact@fermeolouwachegoun.com">contact@fermeolouwachegoun.com</a>
        &nbsp;·&nbsp; <strong>Site web:</strong><a href="https://{{ $companyWebsite }}">{{ $companyWebsite }}</a>
    </div>

</body>
</html>
