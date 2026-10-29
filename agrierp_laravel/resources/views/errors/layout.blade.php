{{--
    Ticket U5 (D-U5) — PAGES D'ERREUR EN FRANÇAIS.

    Sans `resources/views/errors/`, Laravel affichait ses pages par défaut, en anglais
    (« 404 | Not Found », « 419 | Page Expired », « 403 | This action is unauthorized. »).

    ⚠️ GABARIT AUTONOME, VOLONTAIREMENT : ni `@vite`, ni session, ni base de données, ni composant
    Livewire. Une page 500 peut justement venir d'un manifeste Vite absent ou d'une base injoignable
    ; elle ne doit dépendre de rien de ce qui a pu tomber. Même parti que `public/offline.html`
    (styles en ligne, police Inter LOCALE — jamais Google Fonts).

    Livewire affiche aussi ces pages dans sa fenêtre d'échec quand une action échoue côté serveur
    (hors mode débogage) : elles doivent rester lisibles hors du gabarit de l'application.
--}}
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>LogiAgriERP | @yield('title')</title>
    <link rel="icon" type="image/png" href="/assets/icons/favicon-32.png">
    <style>
        @font-face {
            font-family: "Inter";
            font-style: normal;
            font-weight: 100 900;
            font-display: swap;
            src: url("/assets/fonts/Inter-latin.woff2") format("woff2");
        }
        * { box-sizing: border-box; }
        body {
            margin: 0;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 24px;
            font-family: "Inter", Arial, sans-serif;
            color: #17201b;
            background: linear-gradient(160deg, #052e16 0%, #064e2b 55%, #0a6b3c 100%);
        }
        .carte {
            width: 100%;
            max-width: 480px;
            background: #fff;
            border-radius: 16px;
            padding: 32px 28px;
            text-align: center;
            box-shadow: 0 18px 50px rgba(0, 0, 0, .28);
        }
        img { width: 88px; height: 88px; object-fit: contain; margin-bottom: 4px; }
        .code { margin: 0; font-size: 40px; font-weight: 800; color: #065f46; letter-spacing: .04em; }
        h1 { margin: 4px 0 10px; font-size: 21px; color: #052e16; }
        p { margin: 0 0 18px; font-size: 14.5px; line-height: 1.6; color: #5b6660; }
        .actions { display: flex; gap: 10px; flex-wrap: wrap; justify-content: center; }
        .bouton {
            flex: 1 1 180px;
            display: inline-block;
            border: 0;
            border-radius: 10px;
            padding: 12px 16px;
            background: #065f46;
            color: #fff;
            font-size: 14.5px;
            font-weight: 700;
            font-family: inherit;
            text-decoration: none;
            cursor: pointer;
        }
        .bouton:hover { background: #052e16; }
        .bouton.secondaire { background: #eef2ef; color: #052e16; }
        .bouton.secondaire:hover { background: #dfe7e1; }
        .pied { margin: 18px 0 0; font-size: 11.5px; color: #8d968f; }
    </style>
</head>
<body>
    <main class="carte">
        <img src="/assets/icons/icon-192.png" alt="LogiAgriERP">
        <p class="code">@yield('code')</p>
        <h1>@yield('title')</h1>
        <p>@yield('message')</p>
        <div class="actions">
            @hasSection('actions')
                @yield('actions')
            @else
                <a class="bouton secondaire" href="javascript:history.back()">Page précédente</a>
                <a class="bouton" href="{{ url('/') }}">Retour à l'accueil</a>
            @endif
        </div>
        <p class="pied">LogiAgriERP — Ferme École Olouwachegoun</p>
    </main>
</body>
</html>
