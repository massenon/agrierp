/**
 * LogiAgriERP — Service Worker (ticket 15.4, élargi par PWA-1 : caisse hors ligne, 08/11/2026)
 * =====================================================================
 *
 * Rôle : rendre l'application installable, lui donner une page d'attente correcte quand la liaison de la ferme tombe,
 * et (PWA-1) garder en cache l'ENVELOPPE STATIQUE de la caisse hors ligne : `caisse-hors-ligne.html`, son JavaScript et
 * sa feuille de style. Cette page ne contient AUCUNE donnée de la ferme : tout (catalogue, clients, ventes, jeton) vit en
 * IndexedDB, chiffré, lu par le JavaScript de la page. Le service worker, lui, ne voit JAMAIS une donnée métier.
 *
 * ⚠️ TROIS RÈGLES DE SÛRETÉ, à ne pas assouplir sans y réfléchir :
 *
 *   1. SEULES LES REQUÊTES `GET` SONT INTERCEPTÉES. Livewire pilote toute
 *      l'application par des `POST` vers /livewire/update : les mettre en
 *      cache, même une seconde, casserait la moindre saisie. L'ENVOI DES
 *      VENTES n'est PAS fait par ce worker : c'est le JavaScript de la page
 *      (`fetch` vers /api/sync/push) ; le worker ne fait que réveiller un
 *      onglet ouvert (Background Sync) quand le navigateur sait le faire.
 *
 *   2. AUCUNE PAGE HTML AUTHENTIFIÉE N'EST STOCKÉE. Le cache d'un
 *      navigateur n'est pas cloisonné par utilisateur : un tableau de bord
 *      mis en cache pourrait réapparaître après une déconnexion, sur un
 *      poste partagé au comptoir. Les navigations passent donc par le
 *      réseau, et ne retombent sur `offline.html` qu'en cas d'échec réel.
 *      SEULES EXCEPTIONS, deux pages STATIQUES sans donnée, nommées une à une
 *      dans HTML_STATIQUES : `/offline.html` et `/caisse-hors-ligne.html`.
 *      Toute autre réponse HTML est refusée au cache (voir `peutEtreStocke`).
 *
 *   3. SEULS LES FICHIERS STATIQUES SONT MIS EN CACHE (polices, icônes,
 *      CSS et JS compilés). Ils ne contiennent aucune donnée de la ferme.
 *      Jamais de JSON, jamais de réponse d'API, jamais de requête portant
 *      un en-tête `Authorization`.
 *
 * Pour forcer le renouvellement du cache après un déploiement, incrémenter
 * VERSION ci-dessous : `activate` supprime alors tous les caches précédents.
 */

// ⚠️ v2 (ticket 15.6) — LE NUMÉRO DOIT CHANGER, SINON LA RÉDUCTION N'ATTEINT
// PERSONNE. Les postes ayant déjà visité le site portent l'ANCIENNE fonte
// d'icônes de 3,87 Mo dans `agrierp-v1-statique`, et `/assets/fonts/` est
// servi cache d'abord : ils continueraient à la lire depuis leur disque, sans
// jamais redemander les 37 Ko. `activate` purge les caches des versions
// précédentes.
// v3 (ticket H11) — la fonte d'icônes embarque `flag` et `show_chart` (ajouts du poste au Dashboard Élevage) : sans
// nouveau numéro, un poste déjà venu lirait l'ancienne fonte en cache et afficherait ces noms en toutes lettres.
// v6 (PWA-1) — caisse hors ligne : nouvelle enveloppe statique précachée, nouveau cache `…-hors-ligne`.
// v7 (CONF-3) — la page de caisse gagne le bandeau et la confirmation « prix périmés » (3 j / 7 j).
const VERSION = 'agrierp-v16';
const CACHE_STATIQUE = `${VERSION}-statique`;

/** Le strict minimum pour afficher une page d'attente présentable ET ouvrir la caisse hors ligne. */
const SOCLE = [
    '/offline.html',
    '/caisse-hors-ligne.html',
    '/assets/hors-ligne/caisse.js',
    '/assets/hors-ligne/caisse-style.css',
    '/manifest.webmanifest',
    '/assets/icons/icon-192.png',
    '/assets/icons/apple-touch-icon.png',
    '/assets/icons/favicon-32.png',
    '/assets/fonts/Inter-latin.woff2',
    '/assets/fonts/Inter-latin-ext.woff2',
    '/assets/fonts/MaterialSymbolsOutlined.woff2',
    '/assets/images/logo_favicon.webp',
];

/** Chemins que le service worker ne doit JAMAIS toucher. */
const EXCLUS = [
    '/livewire/',
    '/api/',
    '/login',
    '/logout',
    '/reset-password',
    '/broadcasting/',
    '/storage/',   // justificatifs et photos : toujours frais, jamais en cache
];

/** Les SEULES pages HTML que ce worker a le droit de stocker : statiques, sans aucune donnée utilisateur. */
const HTML_STATIQUES = ['/offline.html', '/caisse-hors-ligne.html'];

/** Coque de la caisse hors ligne : fichiers à nom stable (sans empreinte), servis RÉSEAU D'ABORD puis cache. */
const PREFIXE_HORS_LIGNE = '/assets/hors-ligne/';

const estStatique = (url) =>
    url.pathname.startsWith('/build/') ||
    url.pathname.startsWith('/assets/fonts/') ||
    url.pathname.startsWith('/assets/icons/') ||
    url.pathname.startsWith('/assets/images/');

const estHorsLigne = (url) => url.pathname.startsWith(PREFIXE_HORS_LIGNE);

/**
 * Garde unique de ce que l'on met en cache : réponse 200 de même origine, jamais du HTML (hors les deux pages statiques
 * nommées), jamais du JSON, jamais le résultat d'une requête authentifiée.
 */
function peutEtreStocke(requete, url, reponse) {
    if (!reponse || reponse.status !== 200 || reponse.type !== 'basic') return false;
    if (requete.headers.has('Authorization')) return false;
    const type = (reponse.headers.get('Content-Type') || '').toLowerCase();
    if (type.includes('text/html') && !HTML_STATIQUES.includes(url.pathname)) return false;
    if (type.includes('json')) return false;
    return estStatique(url) || estHorsLigne(url) || HTML_STATIQUES.includes(url.pathname) || SOCLE.includes(url.pathname);
}

self.addEventListener('install', (event) => {
    event.waitUntil(
        caches
            .open(CACHE_STATIQUE)
            // `addAll` échoue en bloc si un seul fichier manque : on tolère
            // les absences plutôt que de laisser l'installation échouer.
            // `cache: 'reload'` : jamais une copie périmée du cache HTTP du navigateur.
            .then((cache) => Promise.allSettled(SOCLE.map((u) => cache.add(new Request(u, { cache: 'reload' })))))
            .then(() => self.skipWaiting())
    );
});

self.addEventListener('activate', (event) => {
    event.waitUntil(
        caches
            .keys()
            .then((noms) =>
                Promise.all(
                    noms.filter((n) => !n.startsWith(VERSION)).map((n) => caches.delete(n))
                )
            )
            .then(() => self.clients.claim())
    );
});

self.addEventListener('fetch', (event) => {
    const { request } = event;

    if (request.method !== 'GET') return;                       // règle 1
    if (request.headers.has('Authorization')) return;           // règle 3 : jamais une requête authentifiée
    const url = new URL(request.url);
    if (url.origin !== self.location.origin) return;
    if (EXCLUS.some((p) => url.pathname.startsWith(p))) return;

    // --- Navigations : réseau d'abord, page d'attente en dernier recours ---
    if (request.mode === 'navigate') {                          // règle 2
        // Exception NOMMÉE : l'enveloppe statique de la caisse hors ligne se sert du cache (elle ne contient aucune donnée).
        if (url.pathname === '/caisse-hors-ligne.html') {
            event.respondWith(
                caches.match('/caisse-hors-ligne.html').then((enCache) => {
                    if (enCache) return enCache;
                    return fetch(request).then((reponse) => {
                        if (peutEtreStocke(request, url, reponse)) {
                            const copie = reponse.clone();
                            caches.open(CACHE_STATIQUE).then((c) => c.put('/caisse-hors-ligne.html', copie));
                        }
                        return reponse;
                    }).catch(() => caches.match('/offline.html').then((r) => r || Response.error()));
                })
            );
            return;
        }
        event.respondWith(
            fetch(request).catch(() =>
                caches.match('/offline.html').then((r) => r || Response.error())
            )
        );
        return;
    }

    // --- Script et feuille de la caisse hors ligne : RÉSEAU D'ABORD (jamais un vieux script avec un nouveau HTML) ---
    if (estHorsLigne(url)) {
        event.respondWith(
            fetch(request)
                .then((reponse) => {
                    if (peutEtreStocke(request, url, reponse)) {
                        const copie = reponse.clone();
                        caches.open(CACHE_STATIQUE).then((c) => c.put(request, copie));
                    }
                    return reponse;
                })
                .catch(() => caches.match(request).then((r) => r || Response.error()))
        );
        return;
    }

    // --- Fichiers statiques : cache d'abord, rafraîchi en arrière-plan ---
    if (estStatique(url)) {                                     // règle 3
        event.respondWith(
            caches.match(request).then((enCache) => {
                const reseau = fetch(request)
                    .then((reponse) => {
                        if (peutEtreStocke(request, url, reponse)) {
                            const copie = reponse.clone();
                            caches.open(CACHE_STATIQUE).then((c) => c.put(request, copie));
                        }
                        return reponse;
                    })
                    .catch(() => enCache);
                return enCache || reseau;
            })
        );
    }
});

/**
 * Messages de la page :
 *  - `{ type: 'PURGER' }` : supprime TOUS les caches (déconnexion de l'appareil) ;
 *  - la chaîne historique `agrierp:activer-maintenant` : activation immédiate d'une nouvelle version.
 */
self.addEventListener('message', (event) => {
    if (event.data === 'agrierp:activer-maintenant') self.skipWaiting();
    if (event.data && event.data.type === 'PURGER') {
        event.waitUntil(caches.keys().then((noms) => Promise.all(noms.map((n) => caches.delete(n)))));
    }
});

/**
 * Background Sync (Chromium seulement ; absent de Safari/iOS et de Firefox, où la page se rabat sur `online`, le retour
 * au premier plan, une minuterie et le bouton). LE WORKER N'ENVOIE RIEN : il n'a ni le jeton (chiffré par le PIN) ni la
 * clé. Il réveille un onglet ouvert ; sans onglet ouvert, l'envoi attend la prochaine ouverture.
 */
self.addEventListener('sync', (event) => {
    if (event.tag !== 'sync-file-envoi') return;
    event.waitUntil(
        self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clients) => {
            clients.forEach((c) => c.postMessage({ type: 'SYNCHRONISER' }));
        })
    );
});
