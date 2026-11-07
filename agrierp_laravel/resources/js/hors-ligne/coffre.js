/**
 * PWA-1 — LE COFFRE : chiffrement au repos des données locales par une clé tirée d'un PIN (WebCrypto, aucune dépendance).
 *
 * DÉCISION (justifiée, voir CLAUDE.md « PWA ») : le jeton Sanctum et les données de la caisse (ventes en attente, copie
 * des clients et du catalogue) sont chiffrés en AES-GCM 256 par une clé dérivée du PIN de 4 à 6 chiffres par PBKDF2
 * (SHA-256, sel aléatoire propre à l'appareil). La clé n'est JAMAIS stockée : elle vit en mémoire de la page, comme
 * `NON EXTRACTIBLE` (`extractable: false`). Chaque enregistrement porte son propre IV. Le PIN n'est jamais conservé ;
 * sa vérification se fait en déchiffrant une « sentinelle » (pas de hash du PIN à copier et à attaquer à part).
 *
 * Pourquoi pas `localStorage` : lisible par tout script de la même origine, jamais purgé tout seul, aucune protection.
 * Pourquoi pas une clé non extractible rangée dans IndexedDB seule : elle chiffrerait sans PIN, donc sans protection
 * contre qui ouvre l'appareil. LIMITE ASSUMÉE : un PIN de 4 à 6 chiffres ne résiste pas à une attaque HORS LIGNE menée
 * sur une copie de la base (10^4 à 10^6 essais) ; il protège contre le curieux, pas contre un attaquant équipé. Le
 * compteur de 10 échecs ne protège que l'interface (il se contourne en copiant la base).
 */

export const ITERATIONS_PAR_DEFAUT = 600_000;
export const SENTINELLE = 'agrierp-hors-ligne:sentinelle:v1';
export const ECHECS_MAXIMUM = 10;

export class ErreurPin extends Error {
    constructor(message = 'PIN incorrect.') {
        super(message);
        this.name = 'ErreurPin';
    }
}

export function pinValide(pin) {
    return typeof pin === 'string' && /^\d{4,6}$/.test(pin);
}

export const MOTIF_PIN = 'Le PIN doit comporter 4 à 6 chiffres.';

const encodeur = new TextEncoder();
const decodeur = new TextDecoder();

export function enBase64(octets) {
    let s = '';
    const u = octets instanceof Uint8Array ? octets : new Uint8Array(octets);
    for (let i = 0; i < u.length; i += 0x8000) {
        s += String.fromCharCode(...u.subarray(i, i + 0x8000));
    }
    return btoa(s);
}

export function deBase64(texte) {
    const s = atob(texte);
    const u = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) {
        u[i] = s.charCodeAt(i);
    }
    return u;
}

export function aleatoire(taille, cryptoApi = globalThis.crypto) {
    return cryptoApi.getRandomValues(new Uint8Array(taille));
}

/** Clé AES-GCM 256 NON EXTRACTIBLE, dérivée du PIN. */
export async function deriverCle(pin, sel, iterations = ITERATIONS_PAR_DEFAUT, cryptoApi = globalThis.crypto) {
    const matiere = await cryptoApi.subtle.importKey('raw', encodeur.encode(pin), 'PBKDF2', false, ['deriveKey']);
    return cryptoApi.subtle.deriveKey(
        { name: 'PBKDF2', hash: 'SHA-256', salt: sel, iterations },
        matiere,
        { name: 'AES-GCM', length: 256 },
        false,
        ['encrypt', 'decrypt'],
    );
}

/** Chiffre une valeur JSON ; rend `{ iv, d }` en base64 (jamais de texte lisible). */
export async function chiffrer(cle, valeur, cryptoApi = globalThis.crypto) {
    const iv = aleatoire(12, cryptoApi);
    const clair = encodeur.encode(JSON.stringify(valeur));
    const chiffre = await cryptoApi.subtle.encrypt({ name: 'AES-GCM', iv }, cle, clair);
    return { iv: enBase64(iv), d: enBase64(chiffre) };
}

export async function dechiffrer(cle, enveloppe, cryptoApi = globalThis.crypto) {
    const clair = await cryptoApi.subtle.decrypt({ name: 'AES-GCM', iv: deBase64(enveloppe.iv) }, cle, deBase64(enveloppe.d));
    return JSON.parse(decodeur.decode(clair));
}

/**
 * Crée le coffre d'un appareil : sel, itérations, sentinelle chiffrée (à ranger dans `meta`) et la clé de la session.
 */
export async function creerCoffre(pin, { iterations = ITERATIONS_PAR_DEFAUT, cryptoApi = globalThis.crypto } = {}) {
    if (!pinValide(pin)) {
        throw new ErreurPin(MOTIF_PIN);
    }
    const sel = aleatoire(16, cryptoApi);
    const cle = await deriverCle(pin, sel, iterations, cryptoApi);
    const sentinelle = await chiffrer(cle, SENTINELLE, cryptoApi);
    return { cle, parametres: { sel: enBase64(sel), iterations, sentinelle } };
}

/** Rouvre le coffre avec le PIN saisi ; `ErreurPin` si la sentinelle ne se déchiffre pas. */
export async function ouvrirCoffre(pin, parametres, cryptoApi = globalThis.crypto) {
    if (!pinValide(pin)) {
        throw new ErreurPin(MOTIF_PIN);
    }
    const cle = await deriverCle(pin, deBase64(parametres.sel), parametres.iterations, cryptoApi);
    try {
        const lu = await dechiffrer(cle, parametres.sentinelle, cryptoApi);
        if (lu !== SENTINELLE) {
            throw new ErreurPin();
        }
    } catch (e) {
        throw e instanceof ErreurPin ? e : new ErreurPin();
    }
    return cle;
}
