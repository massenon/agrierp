import { indicateur, placerCarte, rectUtilisable, trouAutour } from './aide-logique.js';

/**
 * Ticket AIDE-1 — BOUTON FLOTTANT D'AIDE : panneau (aide de l'écran, relance de l'assistant, visite guidée) et visite
 * guidée en 4 étapes, en Alpine maison (AUCUNE bibliothèque, aucun CDN).
 *
 * Les textes viennent de `lang/fr/aide_ecrans.php` (passés par `components/aide-flottante.blade.php`) : rien n'est
 * écrit ici. Les éléments expliqués sont repérés par `data-aide="aide|topbar|contenu|menu"` dans `layouts/app.blade.php`.
 *
 * ⚠️ AUCUN ÉCOUTEUR GLOBAL POSÉ À LA MAIN. `resize`, `Escape` et les flèches sont des directives Alpine
 * (`x-on:resize.window`, `x-on:keydown.escape.window`…) du gabarit : Alpine les retire avec l'élément quand `wire:navigate` remplace la page. Poser ici un
 * `window.addEventListener` les cumulerait à chaque page (voir `verrou.js` et `NavigationSansRechargementTest`, qui
 * garde aussi ce fichier). Le seul écouteur est `alpine:init`, enregistré une fois au chargement du module.
 *
 * Le composant vit dans `#app-racine` : le verrou de session le rend inerte avec le reste de la page.
 */
document.addEventListener('alpine:init', () => {
    window.Alpine.data('aideFlottante', (config) => ({
        panneau: false,
        visite: false,
        fin: false,
        etape: 0,
        trou: null,
        carte: { top: 0, left: 0 },
        etapes: config.etapes,
        libelles: config.libelles,
        cibles: config.cibles,

        get total() {
            return this.etapes.length;
        },
        get courante() {
            return this.etapes[this.etape];
        },
        get indicateur() {
            return indicateur(this.libelles.etape_sur, this.etape, this.total);
        },
        get derniere() {
            return this.etape === this.total - 1;
        },
        get styleTrou() {
            if (!this.trou) {
                return '';
            }
            return `top:${this.trou.top}px;left:${this.trou.left}px;width:${this.trou.width}px;height:${this.trou.height}px;`
                + 'box-shadow:0 0 0 9999px rgba(0,0,0,0.6);';
        },
        get styleCarte() {
            return `top:${this.carte.top}px;left:${this.carte.left}px;`;
        },

        ouvrirPanneau() {
            this.panneau = true;
        },
        fermerPanneau() {
            this.panneau = false;
        },

        /** Rouvre l'assistant de démarrage : l'événement Livewire est reçu par `Parametres\AssistantDemarrage::relancer`. */
        relancerAssistant() {
            this.panneau = false;
            if (window.Livewire) {
                window.Livewire.dispatch('relancer-assistant');
            }
        },

        demarrerVisite() {
            this.panneau = false;
            this.fin = false;
            this.etape = 0;
            this.visite = true;
            this.placer();
        },
        suivant() {
            if (this.derniere) {
                this.fin = true;
            } else {
                this.etape += 1;
            }
            this.placer();
        },
        precedent() {
            if (this.etape > 0) {
                this.etape -= 1;
                this.placer();
            }
        },
        /** « Passer » (étapes) et « Fermer » (message de fin) : la visite se ferme, rien n'est mémorisé. */
        passer() {
            this.visite = false;
            this.fin = false;
            this.trou = null;
        },

        /** Met en valeur l'élément de l'étape et pose la carte, une fois le gabarit à jour. */
        placer() {
            this.$nextTick(() => {
                if (!this.visite) {
                    return;
                }
                const largeur = window.innerWidth;
                const hauteur = window.innerHeight;
                const element = this.fin ? null : document.querySelector(`[data-aide="${this.cibles[this.etape]}"]`);
                const rect = element ? element.getBoundingClientRect() : null;
                this.trou = rect && rectUtilisable(rect, largeur, hauteur) ? trouAutour(rect, largeur, hauteur) : null;
                this.$nextTick(() => {
                    const boite = this.$refs.carte;
                    this.carte = placerCarte(
                        this.trou,
                        { width: boite ? boite.offsetWidth : 352, height: boite ? boite.offsetHeight : 240 },
                        largeur,
                        hauteur,
                    );
                    if (this.$refs.primaire) {
                        this.$refs.primaire.focus();
                    }
                });
            });
        },
    }));
});
