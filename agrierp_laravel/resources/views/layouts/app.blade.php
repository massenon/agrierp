<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AgriERP | {{ $title ?? 'Ferme École Olouwachegoun' }}</title>
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
<body class="bg-surface-bg text-on-surface antialiased">
<div x-data="{
        sidebarMobileOpen: false,
        sidebarDesktopHidden: localStorage.getItem('agrierp_sidebar_hidden') === '1',
        quickNavOpen: false,
    }"
    id="app-racine"
    class="flex h-screen w-full overflow-hidden">

    <aside id="sidebar"
        class="sidebar-gradient w-72 h-full flex-shrink-0 flex flex-col transition-all duration-300 overflow-hidden fixed lg:static inset-y-0 left-0 z-50"
        :class="sidebarMobileOpen ? '' : '-translate-x-full lg:translate-x-0'"
        x-show="!sidebarDesktopHidden || sidebarMobileOpen"
        x-cloak>
        <div class="px-md py-lg border-b border-white/10">
            <div class="flex items-center gap-xs">
                <span class="material-symbols-outlined text-accent-yellow" style="font-size:26px;">agriculture</span>
                <h1 class="text-white font-extrabold text-lg">Agri<span class="text-accent-yellow">ERP</span></h1>
            </div>
            <p class="text-[10px] text-white/50 uppercase tracking-wider mt-xs">Ferme École Olouwachegoun</p>
        </div>
        <nav class="flex-1 overflow-y-auto custom-scrollbar px-md py-md">

            @hasanyrole(['admin', 'caissier', 'animalier', 'comptable'])
            <p class="text-[10px] text-white/40 font-bold uppercase tracking-wider px-xs pt-sm">PILOTAGE</p>
            <div class="space-y-xs mb-sm">
                <x-sidebar-link href="/dashboard" icon="dashboard" label="Tableau de Bord" />
            </div>
            @endhasanyrole

            @hasanyrole(['admin', 'animalier'])
            <p class="text-[10px] text-white/40 font-bold uppercase tracking-wider px-xs pt-sm">PRODUCTION ÉLEVAGE & SOINS</p>
            <div class="space-y-xs mb-sm">
                <x-sidebar-link href="/gestion-elevage" icon="pets" label="Gestion Élevage" />
                <x-sidebar-link href="/elevage-dashboard" icon="dashboard" label="Dashboard Élevage" />
                <x-sidebar-link href="/suivi-reproduction" icon="favorite" label="Suivi Reproduction" />
                <x-sidebar-link href="/soins-vaccins-hub" icon="vaccines" label="Soins et vaccins" />
                {{-- Ticket EL-1 — « Bon d'Abattage & Transformation » (route `elevage.transformation`, droit de la route : view-elevage). --}}
                @can('view-elevage')
                <x-sidebar-link href="/transformation" icon="restaurant" label="Transformation" />
                @endcan
                <x-sidebar-link href="/parametres-elevage" icon="tune" label="Paramètres Élevage" />
            </div>
            @endhasanyrole

            @hasanyrole(['admin', 'caissier'])
            <p class="text-[10px] text-white/40 font-bold uppercase tracking-wider px-xs pt-sm">VENTES FERME</p>
            <div class="space-y-xs mb-sm">
                <x-sidebar-link href="/ventes-devis" icon="point_of_sale" label="Ventes & Devis" />
                <x-sidebar-link href="/creances-clients" icon="payments" label="Clients et Créances" />
            </div>
            @endhasanyrole

            @hasanyrole(['admin'])
            <p class="text-[10px] text-white/40 font-bold uppercase tracking-wider px-xs pt-sm">ACHATS & CHARGES</p>
            <div class="space-y-xs mb-sm">
                <x-sidebar-link href="/achats-commandes" icon="local_shipping" label="Achats & Commandes" />
                <x-sidebar-link href="/fournisseurs" icon="contact_page" label="Fournisseurs" />
                <x-sidebar-link href="/saisie-depenses" icon="receipt" label="Saisie Dépenses" />
            </div>

            <p class="text-[10px] text-white/40 font-bold uppercase tracking-wider px-xs pt-sm">STOCKS & PRODUITS</p>
            <div class="space-y-xs mb-sm">
                <x-sidebar-link href="/gestion-stocks" icon="inventory_2" label="Gestion Stocks" />
                <x-sidebar-link href="/catalogue-produits" icon="category" label="Catalogue Produits" />
            </div>
            @endhasanyrole

            {{-- Ticket VC-5 : la facturation existe avec ou sans MeCeF ; seul le libellé suit le module (`config/mecef.php`). --}}
            @hasanyrole(['admin', 'caissier'])
            <p class="text-[10px] text-white/40 font-bold uppercase tracking-wider px-xs pt-sm">FACTURATION</p>
            <div class="space-y-xs mb-sm">
                <x-sidebar-link href="/facturation" icon="receipt_long" :label="config('mecef.actif') ? 'Facturation & MeCeF' : 'Facturation'" />
            </div>
            @endhasanyrole

            @hasanyrole(['admin'])
            <p class="text-[10px] text-white/40 font-bold uppercase tracking-wider px-xs pt-sm">RESSOURCES HUMAINES</p>
            <div class="space-y-xs mb-sm">
                <x-sidebar-link href="/personnel-stages" icon="badge" label="Personnel & Stages" />
            </div>

            <p class="text-[10px] text-white/40 font-bold uppercase tracking-wider px-xs pt-sm">ADMINISTRATION</p>
            <div class="space-y-xs mb-sm">
                <x-sidebar-link href="/administration" icon="folder_shared" label="Administration & Document" />
            </div>
            @endhasanyrole

            @hasanyrole(['admin', 'comptable'])
            <p class="text-[10px] text-white/40 font-bold uppercase tracking-wider px-xs pt-sm">COMPTABILITÉ & ADMIN</p>
            <div class="space-y-xs mb-sm">
                <x-sidebar-link href="/comptabilite-hub" icon="account_balance" label="Comptabilité" />
                <x-sidebar-link href="/parametres-hub" icon="settings" label="Paramètres Général" />
            </div>

            <p class="text-[10px] text-white/40 font-bold uppercase tracking-wider px-xs pt-sm">EDITIONS</p>
            <div class="space-y-xs mb-sm">
                <x-sidebar-link href="/rapports-exports" icon="picture_as_pdf" label="Rapports & Exports" />
            </div>
            @endhasanyrole

        </nav>
        <div class="p-md border-t border-white/10">
            <div class="flex items-center gap-sm px-xs py-xs rounded-lg hover:bg-white/10 cursor-pointer">
                <span class="w-8 h-8 rounded-full bg-white/10 flex items-center justify-center text-white"><span class="material-symbols-outlined text-[18px]">account_circle</span></span>
                <div class="flex flex-col leading-tight">
                    <span class="text-xs text-white font-semibold">{{ auth()->user()->name }}</span>
                    <span class="text-[9px] text-white/50 uppercase tracking-wider">{{ auth()->user()->roles->first()?->name }}</span>
                </div>
            </div>
        </div>
    </aside>
    <div id="sidebar-overlay" x-show="sidebarMobileOpen" x-cloak @click="sidebarMobileOpen = false" class="fixed inset-0 bg-black/40 z-40 lg:hidden"></div>

    <div x-show="sidebarDesktopHidden" x-cloak
        style="background:rgba(5,46,22,0.95); backdrop-filter:blur(6px);"
        class="fixed right-0 top-0 bottom-0 w-16 z-40 hidden lg:flex flex-col items-center py-md gap-sm">
        <a wire:navigate href="/dashboard" title="Tableau de Bord" class="text-white/80 hover:text-brand-maize p-2 rounded-lg hover:bg-white/10"><span class="material-symbols-outlined">dashboard</span></a>
        <a wire:navigate href="/ventes-devis" title="Caisse POS" class="text-white/80 hover:text-brand-maize p-2 rounded-lg hover:bg-white/10"><span class="material-symbols-outlined">point_of_sale</span></a>
        <a wire:navigate href="/gestion-elevage" title="Élevage" class="text-white/80 hover:text-brand-maize p-2 rounded-lg hover:bg-white/10"><span class="material-symbols-outlined">pets</span></a>
        <a wire:navigate href="/gestion-stocks" title="Stocks" class="text-white/80 hover:text-brand-maize p-2 rounded-lg hover:bg-white/10"><span class="material-symbols-outlined">inventory_2</span></a>
        <a wire:navigate href="/personnel-stages" title="Ressources Humaines" class="text-white/80 hover:text-brand-maize p-2 rounded-lg hover:bg-white/10"><span class="material-symbols-outlined">badge</span></a>
        <a wire:navigate href="/comptabilite-hub" title="Comptabilité" class="text-white/80 hover:text-brand-maize p-2 rounded-lg hover:bg-white/10"><span class="material-symbols-outlined">account_balance</span></a>
        <div class="flex-1"></div>
        <button @click="sidebarDesktopHidden = false; localStorage.setItem('agrierp_sidebar_hidden','0')" title="Réafficher le menu" class="text-brand-maize hover:text-white p-2 rounded-lg hover:bg-white/10"><span class="material-symbols-outlined">menu_open</span></button>
    </div>

    <div class="flex-1 flex flex-col min-w-0">
        <header class="h-16 bg-white border-b border-outline-variant px-md lg:px-lg flex items-center justify-between sticky top-0 z-30 flex-shrink-0">
            <div class="flex items-center gap-md min-w-0">
                <button @click="sidebarMobileOpen = true" class="lg:hidden text-brand-forest"><span class="material-symbols-outlined" style="font-size:26px;">menu</span></button>
                <button @click="sidebarDesktopHidden = !sidebarDesktopHidden; localStorage.setItem('agrierp_sidebar_hidden', sidebarDesktopHidden ? '1' : '0')" title="Afficher/Masquer la barre latérale" class="hidden lg:flex text-outline hover:text-brand-emerald"><span class="material-symbols-outlined" style="font-size:22px;">menu_open</span></button>
                <nav class="hidden sm:flex items-center gap-xs text-outline text-xs min-w-0">
                    <span class="text-brand-emerald font-bold truncate">{{ $title ?? 'Ferme École Olouwachegoun' }}</span>
                </nav>
            </div>
            <div class="flex items-center gap-sm md:gap-md">
                <livewire:shared.global-search />

                {{-- Ticket EX7 (EF8) — sélecteur d'exercice global, à gauche du bouton « Synchroniser » (tous les rôles). --}}
                <livewire:shared.selecteur-exercice />

                {{-- Ticket H3 — état de synchronisation des postes (administrateur). --}}
                @can('manage-users')
                    <livewire:shared.etat-synchronisation-postes />
                @endcan

                <livewire:shared.notification-bell />

                <div x-data="{ open: false }" class="relative" @click.outside="open = false">
                    <button id="admin-profile-btn" dusk="profile-menu" @click="open = !open" class="flex items-center gap-xs text-brand-forest font-semibold text-xs">
                        <span class="material-symbols-outlined">account_circle</span><span class="hidden md:inline">{{ auth()->user()->name }}</span><span class="material-symbols-outlined text-[16px]">expand_more</span>
                    </button>
                    <div id="dd-profile" x-show="open" x-cloak class="absolute right-0 mt-sm w-48 bg-white border border-outline-variant rounded-lg shadow-lg z-50 overflow-hidden">
                        <a wire:navigate href="/mon-profil" class="flex items-center gap-xs px-md py-sm text-xs hover:bg-surface-zebra"><span class="material-symbols-outlined text-[16px]">person</span>Mon Profil</a>
                        <a wire:navigate href="/aide-a-propos" class="flex items-center gap-xs px-md py-sm text-xs hover:bg-surface-zebra"><span class="material-symbols-outlined text-[16px]">help</span>Aide &amp; À Propos</a>
                        <a wire:navigate href="/contact-editeur" class="flex items-center gap-xs px-md py-sm text-xs hover:bg-surface-zebra"><span class="material-symbols-outlined text-[16px]">support_agent</span>Contactez l'Éditeur</a>
                        <a wire:navigate href="/parametres-hub" class="flex items-center gap-xs px-md py-sm text-xs hover:bg-surface-zebra"><span class="material-symbols-outlined text-[16px]">settings</span>Paramètres</a>
                        {{-- Sprint VW : « Verrouiller » (même libellé, même icône et même place que le menu du poste). --}}
                        <button type="button" dusk="verrouiller" @click="open = false; window.agrierpVerrou && window.agrierpVerrou.verrouiller()" class="w-full flex items-center gap-xs px-md py-sm text-xs hover:bg-surface-zebra"><span class="material-symbols-outlined text-[16px]">lock</span>Verrouiller</button>
                        <div class="border-t border-outline-variant"></div>
                        <form method="POST" action="{{ route('logout') }}">
                            @csrf
                            <button type="submit" dusk="logout" class="w-full flex items-center gap-xs px-md py-sm text-xs text-error-deep hover:bg-surface-zebra"><span class="material-symbols-outlined text-[16px]">logout</span>Déconnexion</button>
                        </form>
                    </div>
                </div>
            </div>
        </header>

        <div class="flex-1 overflow-y-auto p-md lg:p-lg pb-56 lg:pb-lg bg-surface-bg">
            {{-- Ticket EX7 (EF10) — bandeau de lecture seule d'un exercice clos, en haut du contenu. --}}
            <livewire:shared.bandeau-exercice />
            {{ $slot }}
        </div>
    </div>

    <nav class="lg:hidden fixed bottom-0 left-0 right-0 h-16 bg-white border-t border-outline-variant flex items-stretch z-40 shadow-[0_-2px_8px_rgba(0,0,0,0.06)]">
        <a wire:navigate href="/dashboard" class="flex-1 flex flex-col items-center justify-center gap-0.5 {{ request()->is('dashboard') ? 'text-brand-emerald' : 'text-outline' }}">
            <span class="material-symbols-outlined text-[22px]" @if(request()->is('dashboard')) style="font-variation-settings: 'FILL' 1;" @endif>dashboard</span>
            <span class="text-[9px] font-bold">Tableau de Bord</span>
        </a>
        <a wire:navigate href="/ventes-devis" class="flex-1 flex flex-col items-center justify-center gap-0.5 {{ request()->is('ventes-devis') ? 'text-brand-emerald' : 'text-outline' }}">
            <span class="material-symbols-outlined text-[22px]">point_of_sale</span>
            <span class="text-[9px] font-bold">Vente</span>
        </a>
        <a wire:navigate href="/gestion-elevage" class="flex-1 flex flex-col items-center justify-center gap-0.5 {{ request()->is('gestion-elevage') ? 'text-brand-emerald' : 'text-outline' }}">
            <span class="material-symbols-outlined text-[22px]">pets</span>
            <span class="text-[9px] font-bold">Élevage</span>
        </a>
        <a wire:navigate href="/gestion-stocks" class="flex-1 flex flex-col items-center justify-center gap-0.5 {{ request()->is('gestion-stocks') ? 'text-brand-emerald' : 'text-outline' }}">
            <span class="material-symbols-outlined text-[22px]">inventory_2</span>
            <span class="text-[9px] font-bold">Stock</span>
        </a>
    </nav>

    <button @click="quickNavOpen = true" title="Accès rapide Élevage & Modules" class="fixed z-[60] flex items-center justify-center w-12 h-12 rounded-full bg-brand-emerald hover:bg-brand-forest text-white shadow-lg" style="bottom:88px; right:16px;">
        <span class="material-symbols-outlined" style="font-size:24px;">apps</span>
    </button>

    <div x-show="quickNavOpen" x-cloak @click="quickNavOpen = false" class="fixed inset-0 bg-black/40 z-[65]"></div>
    <div class="fixed top-0 right-0 h-full w-72 max-w-[85vw] bg-white z-[70] shadow-2xl transform transition-transform duration-300 flex flex-col"
        :class="quickNavOpen ? 'translate-x-0' : 'translate-x-full'">
        <div class="flex items-center justify-between px-md py-md border-b border-outline-variant bg-brand-forest">
            <span class="text-white font-bold text-sm flex items-center gap-xs"><span class="material-symbols-outlined text-brand-maize text-[20px]">apps</span>Accès Rapide</span>
            <button @click="quickNavOpen = false" class="text-white/80 hover:text-white"><span class="material-symbols-outlined">close</span></button>
        </div>
        <div class="flex-1 overflow-y-auto p-sm space-y-xs">
            <a wire:navigate href="/fiche-lapins" class="flex items-center gap-sm px-sm py-sm rounded-lg text-on-surface hover:bg-surface-zebra transition-colors"><span class="material-symbols-outlined text-brand-emerald text-[22px]">cruelty_free</span><span class="text-sm font-semibold">Fiche Lapins</span></a>
            <a wire:navigate href="/fiche-volailles-pondeuses" class="flex items-center gap-sm px-sm py-sm rounded-lg text-on-surface hover:bg-surface-zebra transition-colors"><span class="material-symbols-outlined text-brand-emerald text-[22px]">egg</span><span class="text-sm font-semibold">Fiche Pondeuses</span></a>
            <a wire:navigate href="/fiche-volailles-reproducteurs" class="flex items-center gap-sm px-sm py-sm rounded-lg text-on-surface hover:bg-surface-zebra transition-colors"><span class="material-symbols-outlined text-brand-emerald text-[22px]">egg_alt</span><span class="text-sm font-semibold">Fiche Volailles Reproducteurs</span></a>
            <a wire:navigate href="/fiche-porcs" class="flex items-center gap-sm px-sm py-sm rounded-lg text-on-surface hover:bg-surface-zebra transition-colors"><span class="material-symbols-outlined text-brand-emerald text-[22px]">pets</span><span class="text-sm font-semibold">Fiche Porcs</span></a>
            <a wire:navigate href="/fiche-escargots" class="flex items-center gap-sm px-sm py-sm rounded-lg text-on-surface hover:bg-surface-zebra transition-colors"><span class="material-symbols-outlined text-brand-emerald text-[22px]">bug_report</span><span class="text-sm font-semibold">Fiche Escargots</span></a>
            <div class="border-t border-outline-variant my-xs"></div>
            <a wire:navigate href="/suivi-reproduction" class="flex items-center gap-sm px-sm py-sm rounded-lg text-on-surface hover:bg-surface-zebra transition-colors"><span class="material-symbols-outlined text-info-blue text-[22px]">favorite</span><span class="text-sm font-semibold">Suivi Reproduction</span></a>
            <a wire:navigate href="/soins-vaccins-hub" class="flex items-center gap-sm px-sm py-sm rounded-lg text-on-surface hover:bg-surface-zebra transition-colors"><span class="material-symbols-outlined text-info-blue text-[22px]">vaccines</span><span class="text-sm font-semibold">Calendrier Soins &amp; Vaccins</span></a>
            <div class="border-t border-outline-variant my-xs"></div>
            <a wire:navigate href="/ventes-devis" class="flex items-center gap-sm px-sm py-sm rounded-lg text-on-surface hover:bg-surface-zebra transition-colors"><span class="material-symbols-outlined text-brand-forest text-[22px]">point_of_sale</span><span class="text-sm font-semibold">Ventes &amp; Devis</span></a>
            <a wire:navigate href="/gestion-stocks" class="flex items-center gap-sm px-sm py-sm rounded-lg text-on-surface hover:bg-surface-zebra transition-colors"><span class="material-symbols-outlined text-brand-forest text-[22px]">inventory_2</span><span class="text-sm font-semibold">Gestion Stocks</span></a>
            <a wire:navigate href="/dashboard" class="flex items-center gap-sm px-sm py-sm rounded-lg text-on-surface hover:bg-surface-zebra transition-colors"><span class="material-symbols-outlined text-brand-forest text-[22px]">dashboard</span><span class="text-sm font-semibold">Tableau de Bord</span></a>
            <a wire:navigate href="/saisie-depenses" class="flex items-center gap-sm px-sm py-sm rounded-lg text-on-surface hover:bg-surface-zebra transition-colors"><span class="material-symbols-outlined text-brand-forest text-[22px]">receipt</span><span class="text-sm font-semibold">Saisie Dépenses</span></a>
            <a wire:navigate href="/comptabilite-hub" class="flex items-center gap-sm px-sm py-sm rounded-lg text-on-surface hover:bg-surface-zebra transition-colors"><span class="material-symbols-outlined text-brand-forest text-[22px]">account_balance</span><span class="text-sm font-semibold">Comptabilité</span></a>
            <a wire:navigate href="/rapports-exports" class="flex items-center gap-sm px-sm py-sm rounded-lg text-on-surface hover:bg-surface-zebra transition-colors"><span class="material-symbols-outlined text-brand-forest text-[22px]">picture_as_pdf</span><span class="text-sm font-semibold">Rapports et Exports</span></a>
        </div>
    </div>

    {{-- Visite guidée désactivée (client, 26/10/2026) --}}

    <x-pwa-install />
    {{-- Ticket POP1 — fenêtre « Rappels du jour » à l'ouverture, pour qui voit Soins et vaccins (view-elevage). --}}
    @can('view-elevage')
        <livewire:shared.rappels-du-jour />
    @endcan
    <x-toast-container />
    <x-flash-toast />
</div>
{{-- Sprint VW : écran de verrouillage + minuterie d'inactivité. HORS de `#app-racine` (qu'il rend inerte) ; absent de `guest`. --}}
<x-verrou-session minutes="{{ auth()->user()->delaiVerrouillage() }}" />
</body>
</html>
