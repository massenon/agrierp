<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AgriERP | {{ $title ?? 'Connexion' }}</title>
    <meta name="author" content="Dr Rhodes MASSENON, Contact: +2290151335040">
    <link rel="icon" type="image/png" href="{{ asset('assets/images/logo_favicon.webp') }}">
    <link rel="preload" as="font" type="font/woff2" href="/assets/fonts/Inter-latin.woff2" crossorigin>
    <link rel="preload" as="font" type="font/woff2" href="/assets/fonts/MaterialSymbolsOutlined.woff2" crossorigin>
    <link rel="manifest" href="{{ asset('manifest.webmanifest') }}">
    <meta name="theme-color" content="#052e16">
    <meta name="mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
    <meta name="apple-mobile-web-app-title" content="AgriERP">
    <link rel="apple-touch-icon" href="{{ asset('assets/icons/apple-touch-icon.png') }}">
    <script>
        window.agrierpInviteInstallation = null;
        window.addEventListener('beforeinstallprompt', function (e) {
            e.preventDefault();                       // pas de bandeau natif du navigateur
            window.agrierpInviteInstallation = e;
            window.dispatchEvent(new CustomEvent('agrierp:installable', { detail: e }));
        });
        window.addEventListener('appinstalled', function () {
            window.agrierpInviteInstallation = null;
            localStorage.removeItem('agrierp_pwa_reduit');
            localStorage.removeItem('agrierp_pwa_reporte');
        });
        if ('serviceWorker' in navigator) {
            window.addEventListener('load', function () {
                navigator.serviceWorker.register('/sw.js', { scope: '/' }).catch(function () {
                    /* Sans HTTPS (ou en http:// hors localhost) l'enregistrement échoue :
                       c'est normal et sans conséquence, l'application fonctionne. */
                });
            });
        }
    </script>
    @vite(['resources/css/app.css', 'resources/js/app.js'])
</head>
<body
    x-data="{ darkMode: localStorage.getItem('agrierp_theme') === 'dark' }"
    x-init="$watch('darkMode', v => localStorage.setItem('agrierp_theme', v ? 'dark' : 'light'))"
    :class="{ 'dark-mode': darkMode }"
    class="antialiased">
    {{ $slot }}
    <x-pwa-install />
    <x-flash-toast />
</body>
</html>
