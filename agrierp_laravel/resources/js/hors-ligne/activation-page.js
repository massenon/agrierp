import { activer, etatAppareil, prerequis, purgerLocal } from './appairage.js';
import { ouvrirBase } from './base-locale.js';
import { pinValide, MOTIF_PIN } from './coffre.js';

/**
 * PWA-1 — composant Alpine de la page « Mode hors ligne » (`livewire/profil/mode-hors-ligne.blade.php`). Enregistré à
 * `alpine:init` (Alpine est démarré par Livewire : jamais de second démarrage d'Alpine ici). Le mot de passe ne quitte pas ce
 * composant que pour UNE requête `POST /api/auth/login`, puis il est effacé de la mémoire de la page.
 */
document.addEventListener('alpine:init', () => {
    window.Alpine.data('modeHorsLigne', (config) => ({
        identifiant: config.identifiant,
        urlCaisse: config.urlCaisse,
        prerequis: prerequis(),
        chargement: true,
        actif: false,
        nomAppareil: '',
        activeLe: '',
        persistant: false,
        enAttente: 0,
        motDePasse: '',
        pin: '',
        pin2: '',
        erreur: '',
        message: '',
        envoi: false,

        async init() {
            if (!this.prerequis.ok) { this.chargement = false; return; }
            await this.rafraichir();
        },

        async rafraichir() {
            let base;
            try {
                base = await ouvrirBase();
                const etat = await etatAppareil(base);
                this.actif = etat.active;
                this.nomAppareil = etat.deviceName ?? '';
                this.activeLe = etat.activeLe ? new Date(etat.activeLe).toLocaleString('fr-FR') : '';
                this.persistant = etat.persistant;
                const c = await base.compter();
                this.enAttente = c.pending + c.conflict;
            } catch (e) {
                this.erreur = e?.message ?? 'Stockage local indisponible.';
            } finally {
                base?.fermer();
                this.chargement = false;
            }
        },

        async activer() {
            this.erreur = ''; this.message = '';
            if (!pinValide(this.pin)) { this.erreur = MOTIF_PIN; return; }
            if (this.pin !== this.pin2) { this.erreur = 'Les deux PIN ne sont pas identiques.'; return; }
            this.envoi = true;
            try {
                await activer({ identifiant: this.identifiant, motDePasse: this.motDePasse, pin: this.pin });
                this.motDePasse = ''; this.pin = ''; this.pin2 = '';
                this.message = 'Mode hors ligne activé sur cet appareil. Ouvrez la caisse hors ligne : le catalogue y sera copié à la première synchronisation.';
                await this.rafraichir();
            } catch (e) {
                this.erreur = e?.message ?? 'Activation impossible.';
            } finally {
                this.motDePasse = '';
                this.envoi = false;
            }
        },

        async desactiver() {
            this.erreur = '';
            if (this.enAttente > 0) {
                this.erreur = `${this.enAttente} vente(s) ne sont pas encore envoyées : ouvrez la caisse hors ligne pour les envoyer (ou les abandonner explicitement) avant de désactiver cet appareil.`;
                return;
            }
            // Le jeton est chiffré par le PIN : sans lui on ne peut pas le révoquer ici. On purge l'appareil ; le jeton
            // reste révocable depuis Paramètres > Postes & Appairage (et expire sous 90 jours).
            let base;
            try { base = await ouvrirBase(); } catch { base = null; }
            await purgerLocal({ base });
            this.message = 'Cet appareil est désactivé : ses données locales sont effacées. Le jeton reste révocable dans Paramètres, Postes & Appairage.';
            await this.rafraichir();
        },
    }));
});

