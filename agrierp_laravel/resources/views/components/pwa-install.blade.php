
<div
    x-data="{
        etat: 'cache',            // cache | ouvert | reduit
        ios: false,
        invite: null,

        init() {
            // Déjà installée : ne jamais proposer l'installation.
            const installee = window.matchMedia('(display-mode: standalone)').matches
                || window.navigator.standalone === true;
            if (installee) return;

            // Reportée par l'utilisateur il y a moins de 7 jours.
            const reporte = Number(localStorage.getItem('agrierp_pwa_reporte') || 0);
            if (reporte && Date.now() < reporte) return;

            this.ios = /iphone|ipad|ipod/i.test(navigator.userAgent)
                && !/crios|fxios/i.test(navigator.userAgent);

            if (this.ios) {
                this.afficher();
                return;
            }

            // L'événement a pu se déclencher AVANT qu'Alpine ne démarre :
            // il est mis de côté par le script d'amorçage du layout.
            if (window.agrierpInviteInstallation) {
                this.invite = window.agrierpInviteInstallation;
                this.afficher();
            }
            window.addEventListener('agrierp:installable', (e) => {
                this.invite = e.detail;
                this.afficher();
            });
        },

        afficher() {
            this.etat = localStorage.getItem('agrierp_pwa_reduit') === '1' ? 'reduit' : 'ouvert';
        },

        reduire() {
            this.etat = 'reduit';
            localStorage.setItem('agrierp_pwa_reduit', '1');
        },

        agrandir() {
            this.etat = 'ouvert';
            localStorage.removeItem('agrierp_pwa_reduit');
        },

        plusTard() {
            // 7 jours = 7 × 24 × 3600 × 1000 ms
            localStorage.setItem('agrierp_pwa_reporte', Date.now() + 604800000);
            this.etat = 'cache';
        },

        async installer() {
            if (!this.invite) return;
            this.invite.prompt();
            const choix = await this.invite.userChoice;
            this.invite = null;
            window.agrierpInviteInstallation = null;
            if (choix.outcome === 'accepted') {
                this.etat = 'cache';
                localStorage.removeItem('agrierp_pwa_reduit');
            } else {
                this.plusTard();
            }
        },
    }"
    x-cloak
    class="fixed bottom-md left-md z-[150] print:hidden"
>
    <button
        x-show="etat === 'reduit'"
        x-on:click="agrandir()"
        x-transition.opacity
        type="button"
        title="Installer AgriERP sur cet appareil"
        class="flex items-center gap-xs bg-brand-forest hover:bg-brand-emerald text-white rounded-full shadow-lg pl-sm pr-md py-sm transition-colors"
    >
        <span class="material-symbols-outlined text-accent-yellow text-[20px]">install_mobile</span>
        <span class="text-xs font-bold">Installer</span>
    </button>

    <div
        x-show="etat === 'ouvert'"
        x-transition:enter="transition ease-out duration-200"
        x-transition:enter-start="opacity-0 translate-y-2"
        x-transition:enter-end="opacity-100 translate-y-0"
        x-transition:leave="transition ease-in duration-150"
        x-transition:leave-start="opacity-100"
        x-transition:leave-end="opacity-0"
        role="dialog"
        aria-label="Installer AgriERP"
        class="w-[21.5rem] max-w-[calc(100vw-2rem)] bg-white border border-outline-variant rounded-xl shadow-2xl overflow-hidden"
    >
        <div class="flex items-center gap-sm bg-brand-forest px-md py-sm">
            <img src="{{ asset('assets/icons/icon-192.png') }}" alt=""
                 class="w-8 h-8 rounded-lg bg-white object-contain flex-shrink-0">
            <div class="flex-1 min-w-0">
                <p class="text-white text-xs font-bold leading-tight">Installer AgriERP</p>
                <p class="text-white/60 text-[10px] leading-tight">Ferme École Olouwachegoun</p>
            </div>
            <button type="button" x-on:click="reduire()" title="Réduire"
                class="text-white/70 hover:text-accent-yellow transition-colors flex-shrink-0">
                <span class="material-symbols-outlined text-[20px]">minimize</span>
            </button>
        </div>

        <div class="px-md py-md">
            <p class="text-xs text-outline leading-relaxed">
                Installez AgriERP sur cet appareil pour l'ouvrir <strong class="text-brand-forest">directement
                depuis l'écran d'accueil</strong>, en plein écran, sans passer par le navigateur.
            </p>

            <ul class="mt-sm space-y-xs text-[11px] text-outline">
                <li class="flex items-start gap-xs">
                    <span class="material-symbols-outlined text-brand-emerald text-[16px] mt-[1px]">bolt</span>
                    <span>Ouverture plus rapide, en un seul geste</span>
                </li>
                <li class="flex items-start gap-xs">
                    <span class="material-symbols-outlined text-brand-emerald text-[16px] mt-[1px]">fullscreen</span>
                    <span>Plein écran : plus de place pour les tableaux</span>
                </li>
                <li class="flex items-start gap-xs">
                    <span class="material-symbols-outlined text-brand-emerald text-[16px] mt-[1px]">wifi_off</span>
                    <span>Message clair si le réseau de la ferme tombe</span>
                </li>
            </ul>

            <template x-if="ios">
                <div class="mt-md bg-info-blue/10 border border-info-blue/30 rounded-lg px-sm py-sm">
                    <p class="text-[11px] text-brand-forest leading-relaxed">
                        Sur iPhone et iPad : touchez
                        <span class="material-symbols-outlined text-[14px] align-middle text-info-blue">ios_share</span>
                        <strong>Partager</strong>, puis
                        <strong>« Sur l'écran d'accueil »</strong>.
                    </p>
                </div>
            </template>
        </div>

        <div class="flex items-center gap-xs px-md pb-md">
            <button type="button" x-on:click="plusTard()"
                class="px-md py-sm rounded-lg border border-outline-variant text-xs font-semibold text-outline hover:bg-surface-zebra transition-colors">
                Plus tard
            </button>
            <button type="button" x-on:click="installer()" x-show="!ios"
                class="flex-1 flex items-center justify-center gap-xs px-md py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white text-xs font-bold whitespace-nowrap transition-colors">
                <span class="material-symbols-outlined text-[18px]">install_mobile</span>
                Installer l'application
            </button>
            <button type="button" x-on:click="reduire()" x-show="ios"
                class="flex-1 px-md py-sm rounded-lg bg-brand-emerald hover:bg-brand-forest text-white text-xs font-bold transition-colors">
                J'ai compris
            </button>
        </div>
    </div>
</div>
