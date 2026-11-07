/**
 * PWA-1 — APPAIRAGE DU NAVIGATEUR COMME UN POSTE.
 *
 * Le web s'authentifie par la session Laravel, pas par jeton : l'appareil devient un POSTE en appelant, APRÈS la connexion
 * web normale, le `POST /api/auth/login` du poste Windows avec `device_name = « pwa-<uuid> »` (tiré UNE fois, jamais le nom
 * du navigateur). Le jeton Sanctum nommé qui en résulte est :
 *   - gardé CHIFFRÉ (coffre.js, clé dérivée du PIN) dans la base locale — jamais en clair, jamais `localStorage` ;
 *   - le `device_id` de chaque envoi (le serveur refuse sinon : 403) ;
 *   - révocable depuis Paramètres > Postes & Appairage (c'est un poste de plus) : la synchro reçoit alors 401 et s'arrête.
 * Le mot de passe saisi sert UNE requête puis disparaît : il n'est ni stocké, ni journalisé, ni passé à Livewire.
 *
 * Un seul jeton par navigateur : réactiver le même appareil réutilise son nom, donc le serveur REMPLACE l'ancien jeton
 * (`AuthController::login` supprime les jetons de même nom).
 */

import { creerCoffre, ouvrirCoffre, chiffrer, dechiffrer, ErreurPin, ECHECS_MAXIMUM, pinValide, MOTIF_PIN } from './coffre.js';
import { ouvrirBase, supprimerBase } from './base-locale.js';

export const MARQUEUR_ACTIVE = 'agrierp_hors_ligne_active';       // localStorage : un drapeau, AUCUN secret
export const MARQUEUR_EN_ATTENTE = 'agrierp_hors_ligne_n';          // localStorage : le nombre de ventes non envoyées (détecte une purge)

export class ErreurAppairage extends Error {
    constructor(message, code = 'appairage') {
        super(message);
        this.name = 'ErreurAppairage';
        this.code = code;
    }
}

function marquer(cle, valeur) {
    try { valeur === null ? localStorage.removeItem(cle) : localStorage.setItem(cle, String(valeur)); } catch { /* stockage bloqué */ }
}
export function lireMarqueur(cle) {
    try { return localStorage.getItem(cle); } catch { return null; }
}
export function noterEnAttente(n) { marquer(MARQUEUR_EN_ATTENTE, n); }

/** Le navigateur offre-t-il tout ce qu'il faut ? (WebCrypto exige HTTPS ou localhost.) */
export function prerequis(env = globalThis) {
    if (!env.isSecureContext) return { ok: false, motif: "Le mode hors ligne exige une connexion sécurisée (HTTPS)." };
    if (!env.crypto?.subtle) return { ok: false, motif: "Ce navigateur n'offre pas le chiffrement local nécessaire." };
    if (!env.indexedDB) return { ok: false, motif: "Ce navigateur n'offre pas de stockage local (IndexedDB)." };
    return { ok: true };
}

export async function demanderPersistance(env = globalThis) {
    try {
        if (env.navigator?.storage?.persist) return Boolean(await env.navigator.storage.persist());
    } catch { /* refusé : on le dira */ }
    return false;
}

/**
 * Active l'appareil : connexion de poste, coffre par PIN, jeton chiffré.
 *
 * @returns {{deviceName:string, utilisateur:object, persistant:boolean}}
 */
export async function activer({ identifiant, motDePasse, pin, fetchFn = (...a) => globalThis.fetch(...a), idb = globalThis.indexedDB, cryptoApi = globalThis.crypto, iterations, urlBase = '' }) {
    if (!pinValide(pin)) throw new ErreurAppairage(MOTIF_PIN, 'pin');
    if (!motDePasse) throw new ErreurAppairage('Saisissez votre mot de passe.', 'mot-de-passe');

    const base = await ouvrirBase({ idb });
    try {
        const existant = await base.meta('appareil');
        const deviceName = existant?.device_name ?? `pwa-${cryptoApi.randomUUID()}`;

        let reponse;
        try {
            reponse = await fetchFn(`${urlBase}/api/auth/login`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
                body: JSON.stringify({ identifiant, password: motDePasse, device_name: deviceName }),
                credentials: 'omit',
                cache: 'no-store',
            });
        } catch {
            throw new ErreurAppairage("Pas de connexion au serveur : l'activation se fait EN LIGNE, une première fois.", 'reseau');
        }
        const json = await reponse.json().catch(() => ({}));
        if (reponse.status === 429) throw new ErreurAppairage('Trop de tentatives : patientez une minute puis réessayez.', 'limite');
        if (reponse.status === 422) throw new ErreurAppairage(json?.errors?.identifiant?.[0] ?? json?.message ?? 'Identifiants incorrects.', 'identifiants');
        if (!reponse.ok || typeof json.token !== 'string') throw new ErreurAppairage(`Activation refusée par le serveur (${reponse.status}).`, 'refus');
        if (json.must_change_password) throw new ErreurAppairage("Changez d'abord votre mot de passe temporaire dans AgriERP, puis réactivez le mode hors ligne.", 'mot-de-passe-temporaire');

        const { cle, parametres } = await creerCoffre(pin, { iterations, cryptoApi });
        // Réactivation : les ventes déjà en file étaient chiffrées par l'ANCIENNE clé ; on ne les écrase pas en silence.
        const enAttente = (await base.compter());
        if (enAttente.pending + enAttente.conflict > 0 && existant) {
            throw new ErreurAppairage(`Cet appareil garde ${enAttente.pending + enAttente.conflict} vente(s) non envoyée(s) chiffrée(s) par l'ancien PIN : ouvrez la caisse hors ligne, déverrouillez avec l'ancien PIN et envoyez-les d'abord.`, 'file-existante');
        }
        const utilisateur = { id: json.user?.id, name: json.user?.name, username: json.user?.username, role: json.user?.role };
        const persistant = await demanderPersistance();
        // ⚠️ Tout ce qui est ASYNCHRONE hors IndexedDB (WebCrypto) se fait AVANT la transaction : une transaction IndexedDB se
        // referme dès qu'elle n'a plus de requête en cours, et l'écriture suivante échouerait (ou serait perdue).
        const jetonChiffre = await chiffrer(cle, json.token, cryptoApi);
        await base.transaction(['meta'], 'readwrite', async (tx) => {
            const p = (req) => new Promise((ok, ko) => { req.onsuccess = () => ok(); req.onerror = () => ko(req.error); });
            const m = tx.objectStore('meta');
            await p(m.put({ cle: 'appareil', valeur: { device_name: deviceName, utilisateur, active_le: new Date().toISOString(), persistant } }));
            await p(m.put({ cle: 'coffre', valeur: parametres }));
            await p(m.put({ cle: 'jeton', valeur: jetonChiffre }));
            await p(m.put({ cle: 'echecs_pin', valeur: 0 }));
            await p(m.delete('suspendu'));
        });
        marquer(MARQUEUR_ACTIVE, '1');
        marquer(MARQUEUR_EN_ATTENTE, 0);
        return { deviceName, utilisateur, persistant };
    } finally {
        base.fermer();
    }
}

/** Ce que l'on sait de l'appareil SANS déverrouiller (aucun secret). */
export async function etatAppareil(base) {
    const appareil = await base.meta('appareil');
    return {
        active: Boolean(appareil),
        deviceName: appareil?.device_name ?? null,
        utilisateur: appareil?.utilisateur ?? null,
        activeLe: appareil?.active_le ?? null,
        persistant: appareil?.persistant ?? false,
        suspendu: Boolean(await base.meta('suspendu')),
        echecsPin: (await base.meta('echecs_pin')) ?? 0,
    };
}

/**
 * Déverrouille avec le PIN. 10 échecs cumulés = le coffre est EFFACÉ (clé, jeton, copie des données et ventes illisibles)
 * et la reconnexion en ligne est exigée ; l'écran prévient avant l'essai fatal.
 *
 * @returns {{cle:CryptoKey, jeton:string}}
 */
export async function deverrouiller(base, pin, { cryptoApi = globalThis.crypto, idb = globalThis.indexedDB } = {}) {
    const parametres = await base.meta('coffre');
    if (!parametres) throw new ErreurAppairage("Cet appareil n'est pas activé pour le mode hors ligne.", 'inactif');
    try {
        const cle = await ouvrirCoffre(pin, parametres, cryptoApi);
        const jeton = await dechiffrer(cle, await base.meta('jeton'), cryptoApi);
        await base.poserMeta('echecs_pin', 0);
        return { cle, jeton };
    } catch (e) {
        if (!(e instanceof ErreurPin)) throw e;
        const echecs = ((await base.meta('echecs_pin')) ?? 0) + 1;
        if (echecs >= ECHECS_MAXIMUM) {
            await purgerLocal({ base, idb });
            throw new ErreurPin(`Trop d'échecs : les données de cet appareil ont été effacées. Reconnectez-vous à AgriERP en ligne pour réactiver le mode hors ligne.`);
        }
        await base.poserMeta('echecs_pin', echecs);
        const restant = ECHECS_MAXIMUM - echecs;
        throw new ErreurPin(restant <= 3
            ? `PIN incorrect. Attention : ${restant} essai(s) avant l'EFFACEMENT des données de cet appareil (les ventes non envoyées seraient perdues).`
            : `PIN incorrect (${echecs}/${ECHECS_MAXIMUM}).`);
    }
}

/** Purge locale : base IndexedDB, caches du service worker, marqueurs. Ne touche pas au serveur. */
export async function purgerLocal({ base = null, idb = globalThis.indexedDB, env = globalThis } = {}) {
    try { base?.fermer(); } catch { /* déjà fermée */ }
    let supprimee = await supprimerBase({ idb }).catch(() => false);
    if (!supprimee) supprimee = await supprimerBase({ idb }).catch(() => false);
    try {
        if (env.caches?.keys) for (const nom of await env.caches.keys()) await env.caches.delete(nom);
    } catch { /* le service worker purge aussi, par message */ }
    try { env.navigator?.serviceWorker?.controller?.postMessage({ type: 'PURGER' }); } catch { /* pas de service worker */ }
    marquer(MARQUEUR_ACTIVE, null);
    marquer(MARQUEUR_EN_ATTENTE, null);
    return supprimee;
}

/** Désactive l'appareil : révoque SON jeton côté serveur (si joignable), puis purge. */
export async function desactiver({ base, jeton = null, fetchFn = (...a) => globalThis.fetch(...a), idb = globalThis.indexedDB, urlBase = '' }) {
    let revoque = false;
    if (jeton) {
        try {
            const r = await fetchFn(`${urlBase}/api/auth/logout`, { method: 'POST', headers: { Authorization: `Bearer ${jeton}`, Accept: 'application/json' }, credentials: 'omit', cache: 'no-store' });
            revoque = r.ok || r.status === 401;
        } catch { /* hors ligne : le jeton reste valable côté serveur (révocable depuis les Postes), il expire sous 90 jours */ }
    }
    await purgerLocal({ base, idb });
    return { revoque };
}
