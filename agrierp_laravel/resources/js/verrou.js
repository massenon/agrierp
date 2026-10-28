import { DUREE_PAR_DEFAUT, decider, dureeValide, formaterAttente } from './verrou-logique.js';

/**
 * Sprint VW (VW2) — VERROU DE SESSION WEB, côté navigateur.
 *
 * ⚠️ LE NAVIGATEUR NE DÉCIDE RIEN DE CE QUI EST PROTÉGÉ : il déclenche (`POST /verrouiller`) et il affiche. Le refus
 * des requêtes est fait par `SessionVerrouillee` côté serveur ; la surcouche (`components/verrou-session.blade.php`)
 * n'est que ce que voit l'utilisateur.
 *
 * Minuterie : le moment du dernier geste est partagé entre les onglets par `localStorage` (un geste dans un onglet
 * compte pour tous). Chaque onglet revérifie toutes les 5 s sur l'horloge, pas sur un `setTimeout` : un onglet en
 * arrière-plan, dont les minuteurs sont ralentis, verrouille quand même à l'heure. Ne verrouille jamais pendant une
 * requête Livewire en vol ni juste après un téléchargement lancé. L'état « verrouillé » passe aux autres onglets par
 * l'événement `storage` ; à défaut, leur prochaine requête reçoit 423 et fait apparaître la surcouche.
 *
 * `localStorage` peut être indisponible (navigation privée, stockage bloqué) : tout accès est protégé, la minuterie
 * retombe alors sur la mémoire de l'onglet.
 */

const CLE_ACTIVITE = 'agrierp_derniere_activite';
const CLE_ETAT = 'agrierp_verrou_etat';
const PERIODE_VERIFICATION_MS = 5_000;
const SUSPENSION_TELECHARGEMENT_MS = 60_000;
const EVENEMENTS_ACTIVITE = ['pointerdown', 'pointermove', 'keydown', 'wheel', 'touchstart', 'scroll', 'click'];

let requetesEnCours = 0;
let suspenduJusqua = 0;
let instance = null;

function lire(cle) {
    try {
        return window.localStorage.getItem(cle);
    } catch {
        return null;
    }
}

function ecrire(cle, valeur) {
    try {
        window.localStorage.setItem(cle, valeur);
    } catch {
        /* stockage indisponible : on continue avec la mémoire de l'onglet */
    }
}

// Navigation sans rechargement (`wire:navigate`) : le composant est réinitialisé à CHAQUE page. Les écouteurs posés sur
// `window` / `document` et la minuterie de vérification sont donc retirés avant d'être reposés, sinon ils se cumulent
// (une activité comptée N fois, N minuteries).
let ecouteursPoses = [];
let minuterieVerification = null;

function poser(cible, nom, rappel, options) {
    cible.addEventListener(nom, rappel, options);
    ecouteursPoses.push([cible, nom, rappel, options]);
}

function retirerEcouteurs() {
    for (const [cible, nom, rappel, options] of ecouteursPoses) {
        cible.removeEventListener(nom, rappel, options);
    }
    ecouteursPoses = [];
    if (minuterieVerification !== null) {
        window.clearInterval(minuterieVerification);
        minuterieVerification = null;
    }
}

document.addEventListener('alpine:init', () => {
    window.Alpine.data('verrouSession', (config) => ({
        verrouille: config.verrouille,
        page: config.page,
        minutes: dureeValide(config.minutes) ? config.minutes : DUREE_PAR_DEFAUT,
        erreur: config.erreur || '',
        motDePasse: '',
        envoi: false,
        attente: 0,
        formaterAttente,
        _derniereLocale: Date.now(),
        _derniereEcriture: 0,

        init() {
            retirerEcouteurs();
            instance = this;
            window.agrierpVerrou = this;
            this.$watch('verrouille', (v) => this._appliquerEtat(v));
            this._appliquerEtat(this.verrouille);

            poser(window, 'storage', (e) => {
                if (e.key !== CLE_ETAT || !e.newValue) {
                    return;
                }
                if (e.newValue.startsWith('verrouille') && !this.verrouille) {
                    this.afficher();
                } else if (e.newValue.startsWith('deverrouille')) {
                    if (this.page) {
                        window.location.reload();
                    } else if (this.verrouille) {
                        this._cacher(false);
                    }
                }
            });

            if (this.page) {
                this.$nextTick(() => this.$refs.champ?.focus());
                return;
            }

            for (const nom of EVENEMENTS_ACTIVITE) {
                poser(window, nom, () => this._marquerActivite(), { passive: true, capture: true });
            }
            poser(document, 'click', (e) => {
                if (e.target instanceof Element && e.target.closest('a[download], [data-verrou-suspendre]')) {
                    suspenduJusqua = Date.now() + SUSPENSION_TELECHARGEMENT_MS;
                }
            }, true);
            poser(document, 'visibilitychange', () => {
                if (!document.hidden) {
                    this._verifier();
                }
            });
            poser(window, 'verrou-delai-modifie', (e) => {
                const minutes = e.detail?.minutes ?? e.detail?.[0]?.minutes;
                if (dureeValide(minutes)) {
                    this.minutes = minutes;
                }
            });
            this._marquerActivite(true);
            minuterieVerification = window.setInterval(() => this._verifier(), PERIODE_VERIFICATION_MS);
        },

        _marquerActivite(forcer = false) {
            if (this.verrouille) {
                return;
            }
            const maintenant = Date.now();
            this._derniereLocale = maintenant;
            // Écriture au plus une fois par seconde (pointermove arrive à plusieurs dizaines de Hz).
            if (forcer || maintenant - this._derniereEcriture >= 1_000) {
                this._derniereEcriture = maintenant;
                ecrire(CLE_ACTIVITE, String(maintenant));
            }
        },

        _derniereActivite() {
            const partagee = parseInt(lire(CLE_ACTIVITE) ?? '', 10);

            return Number.isFinite(partagee) ? Math.max(partagee, this._derniereLocale) : this._derniereLocale;
        },

        _verifier() {
            const action = decider({
                maintenant: Date.now(),
                derniereActivite: this._derniereActivite(),
                minutes: this.minutes,
                requetesEnCours,
                suspenduJusqua,
                verrouille: this.verrouille,
            });
            if (action === 'verrouiller') {
                this.verrouiller();
            }
        },

        _appliquerEtat(verrouille) {
            // Verrouillé : l'application est rendue inerte (clavier, lecteur d'écran) sous la surcouche.
            const racine = document.getElementById('app-racine');
            if (racine) {
                racine.toggleAttribute('inert', verrouille);
                racine.setAttribute('aria-hidden', verrouille ? 'true' : 'false');
            }
            document.body.classList.toggle('overflow-hidden', verrouille && !this.page);
            if (verrouille) {
                this.$nextTick(() => this.$refs.champ?.focus());
            }
        },

        /** Demande le verrouillage au serveur (menu « Verrouiller » ou échéance de la minuterie). */
        async verrouiller() {
            if (this.verrouille) {
                return;
            }
            try {
                const reponse = await fetch(config.urlVerrouiller, {
                    method: 'POST',
                    headers: { Accept: 'application/json', 'X-CSRF-TOKEN': config.jeton, 'X-Requested-With': 'XMLHttpRequest' },
                    credentials: 'same-origin',
                });
                if (reponse.status === 401 || reponse.status === 419) {
                    window.location.href = config.urlConnexion;

                    return;
                }
                if (reponse.ok || reponse.status === 423) {
                    this.afficher();
                    ecrire(CLE_ETAT, `verrouille:${Date.now()}`);
                }
            } catch {
                /* réseau coupé : la prochaine vérification réessaiera */
            }
        },

        /** Affiche la surcouche (aucune requête : le serveur est déjà verrouillé, ou vient de répondre 423). */
        afficher() {
            this.erreur = '';
            this.attente = 0;
            this.motDePasse = '';
            this.verrouille = true;
        },

        _cacher(prevenir = true) {
            this.verrouille = false;
            this.motDePasse = '';
            this.erreur = '';
            this.attente = 0;
            this._marquerActivite(true);
            if (prevenir) {
                ecrire(CLE_ETAT, `deverrouille:${Date.now()}`);
            }
        },

        async soumettre() {
            if (this.envoi || this.attente > 0) {
                return;
            }
            if (this.motDePasse === '') {
                this.erreur = 'Le mot de passe est obligatoire.';

                return;
            }
            this.envoi = true;
            try {
                const reponse = await fetch(config.urlDeverrouiller, {
                    method: 'POST',
                    headers: {
                        Accept: 'application/json',
                        'Content-Type': 'application/json',
                        'X-CSRF-TOKEN': config.jeton,
                        'X-Requested-With': 'XMLHttpRequest',
                    },
                    credentials: 'same-origin',
                    body: JSON.stringify({ password: this.motDePasse }),
                });
                const donnees = await reponse.json().catch(() => ({}));
                if (reponse.ok) {
                    if (this.page) {
                        window.location.href = donnees.retour || '/dashboard';
                    } else {
                        this._cacher();
                    }
                } else if (reponse.status === 401 && donnees.deconnecte) {
                    window.location.href = donnees.redirect || config.urlConnexion;
                } else if (reponse.status === 401 || reponse.status === 419) {
                    // Session expirée côté serveur (SESSION_LIFETIME) pendant le verrou : retour à la connexion.
                    window.location.href = config.urlConnexion;
                } else if (reponse.status === 429) {
                    this.motDePasse = '';
                    this._compterAttente(donnees.secondes || 0);
                } else {
                    this.motDePasse = '';
                    this.erreur = donnees.message || 'Mot de passe incorrect.';
                    this.$nextTick(() => this.$refs.champ?.focus());
                }
            } catch {
                this.erreur = 'Connexion impossible. Réessayez.';
            } finally {
                this.envoi = false;
            }
        },

        _compterAttente(secondes) {
            this.attente = secondes;
            this.erreur = 'attente';
            const minuteur = window.setInterval(() => {
                this.attente -= 1;
                if (this.attente <= 0) {
                    window.clearInterval(minuteur);
                    this.attente = 0;
                    this.erreur = '';
                }
            }, 1_000);
        },
    }));
});

document.addEventListener('livewire:init', () => {
    // Requêtes Livewire en vol : on ne verrouille jamais au milieu (enregistrement, export, téléchargement).
    // `respond` couvre toute réponse reçue, `fail` couvre l'échec réseau ; le compteur ne peut donc pas rester coincé.
    window.Livewire.hook('request', ({ respond, fail }) => {
        requetesEnCours += 1;
        let termine = false;
        const fin = () => {
            if (!termine) {
                termine = true;
                requetesEnCours = Math.max(0, requetesEnCours - 1);
            }
        };
        respond(fin);
        fail(({ status, preventDefault }) => {
            fin();
            // 423 : le serveur est verrouillé (autre onglet, minuterie d'un autre onglet…). Pas de fenêtre d'erreur :
            // la surcouche apparaît, la page n'est pas démontée, la saisie en cours est conservée.
            if (status === 423 && instance) {
                preventDefault();
                instance.afficher();
            }
        });
    });
});
