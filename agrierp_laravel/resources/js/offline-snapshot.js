/**
 * PWA-4 — Snapshot hors ligne : stock, créances, ventes récentes (11/11/2026)
 * ============================================================================
 *
 * Ce module gère la mise en cache d'un instantané JSON dans IndexedDB
 * (`agrierp_offline_snapshot`, clé `offline_snapshot`) et l'interception
 * de navigation vers les trois pages concernées quand le navigateur est
 * hors ligne.
 *
 * Chargé par `resources/js/app.js` (import).
 *
 * Règles de sécurité respectées :
 *  - Aucune donnée dans le service worker (règle 3 de sw.js).
 *  - Le fetch utilise le cookie de session de Livewire (credentials: 'same-origin').
 *  - Aucun jeton ni mot de passe stocké ici.
 *  - Le snapshot est stocké en CLAIR (données métier peu sensibles : stock et
 *    historique de ventes internes). Pas de chiffrement nécessaire ici
 *    (différent de la caisse : les données d'encaissement PIN-chiffrées).
 *
 * Pages redirigées hors ligne :
 *  - /gestion-stocks  → /offline-stock.html
 *  - /creances-clients → /offline-creances.html
 *  - /ventes-devis    → /offline-ventes.html
 *  - /historique-ventes → /offline-ventes.html
 *
 * L'actualisation du snapshot est déclenchée :
 *  - juste après le chargement de la page (si en ligne) ;
 *  - à l'événement `online` (reconnexion) ;
 *  - au retour de focus (anti-rebond 60 s).
 */

'use strict';

// --- Base de données IndexedDB (propre à ce module, ne touche pas agrierp_hors_ligne) ---

const DB_NAME    = 'agrierp_offline_snapshot';
const DB_VERSION = 1;
const STORE      = 'snapshot';
const CLE        = 'offline_snapshot';

function ouvrirDb() {
    return new Promise((resolve, reject) => {
        const req = indexedDB.open(DB_NAME, DB_VERSION);
        req.onupgradeneeded = (e) => {
            e.target.result.createObjectStore(STORE, { keyPath: 'cle' });
        };
        req.onsuccess = (e) => resolve(e.target.result);
        req.onerror   = () => reject(req.error);
    });
}

async function ecrireSnapshot(data) {
    const db = await ouvrirDb();
    return new Promise((resolve, reject) => {
        const tx  = db.transaction(STORE, 'readwrite');
        const put = tx.objectStore(STORE).put({ cle: CLE, data });
        put.onsuccess = () => resolve();
        put.onerror   = () => reject(put.error);
    });
}

// --- Fetch du snapshot ---

let enCours = false;
let dernierFetch = 0;
const DELAI_MIN_MS = 60_000; // ne pas re-fetcher plus d'une fois par minute

async function actualiserSnapshot() {
    if (enCours) return;
    if (!navigator.onLine) return;
    const maintenant = Date.now();
    if (maintenant - dernierFetch < DELAI_MIN_MS) return;

    enCours = true;
    try {
        const rep = await fetch('/api/offline/snapshot', {
            method: 'GET',
            credentials: 'same-origin',
            headers: { Accept: 'application/json' },
        });
        if (!rep.ok) return; // 401/403 : non connecté ou droits insuffisants — silencieux
        const data = await rep.json();
        await ecrireSnapshot(data);
        dernierFetch = Date.now();
    } catch {
        // Réseau coupé entre le check navigator.onLine et le fetch : silencieux.
    } finally {
        enCours = false;
    }
}

// --- Interception de navigation hors ligne ---

const REDIRECTIONS = {
    '/gestion-stocks':     '/offline-stock.html',
    '/creances-clients':   '/offline-creances.html',
    '/ventes-devis':       '/offline-ventes.html',
    '/historique-ventes':  '/offline-ventes.html',
};

function intercepterNavigationHorsLigne() {
    const chemin = window.location.pathname;
    if (navigator.onLine) return; // en ligne : rien à faire
    const destination = REDIRECTIONS[chemin];
    if (!destination) return;
    window.location.replace(destination);
}

// --- Écoute des événements ---

// 1. Chargement initial : on tente d'actualiser ET on vérifie si on est hors ligne.
document.addEventListener('DOMContentLoaded', () => {
    intercepterNavigationHorsLigne();
    actualiserSnapshot();
});

// 2. Reconnexion : actualisation immédiate.
window.addEventListener('online', () => {
    actualiserSnapshot();
});

// 3. Retour de focus (anti-rebond 60 s, identique à la caisse).
let dernierFocus = 0;
window.addEventListener('focus', () => {
    const maintenant = Date.now();
    if (maintenant - dernierFocus < DELAI_MIN_MS) return;
    dernierFocus = maintenant;
    actualiserSnapshot();
});

// 4. Passage hors ligne : rediriger si on est sur une page concernée.
window.addEventListener('offline', () => {
    intercepterNavigationHorsLigne();
});
