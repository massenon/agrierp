/**
 * AgriERP — Service Worker (ticket 15.4)
 * =====================================================================
 *
 * Rôle VOLONTAIREMENT ÉTROIT : rendre l'application installable et lui
 * donner une page d'attente correcte quand la liaison de la ferme tombe.
 * Il ne cherche pas à faire fonctionner AgriERP hors ligne — c'est le rôle
 * du poste dédié, pas d'un cache de navigateur.
 *
 * ⚠️ TROIS RÈGLES DE SÛRETÉ, à ne pas assouplir sans y réfléchir :
 *
 *   1. SEULES LES REQUÊTES `GET` SONT INTERCEPTÉES. Livewire pilote toute
 *      l'application par des `POST` vers /livewire/update : les mettre en
 *      cache, même une seconde, casserait la moindre saisie.
 *
 *   2. AUCUNE PAGE HTML AUTHENTIFIÉE N'EST STOCKÉE. Le cache d'un
 *      navigateur n'est pas cloisonné par utilisateur : un tableau de bord
 *      mis en cache pourrait réapparaître après une déconnexion, sur un
 *      poste partagé au comptoir. Les navigations passent donc par le
 *      réseau, et ne retombent sur `offline.html` qu'en cas d'échec réel.
 *
 *   3. SEULS LES FICHIERS STATIQUES SONT MIS EN CACHE (polices, icônes,
 *      CSS et JS compilés). Ils ne contiennent aucune donnée de la ferme.
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
const VERSION = 'agrierp-v3';
const CACHE_STATIQUE = `${VERSION}-statique`;

/** Le strict minimum pour afficher une page d'attente présentable. */
const SOCLE = [
    '/offline.html',
    '/manifest.webmanifest',
    '/assets/icons/icon-192.png',
    '/assets/icons/apple-touch-icon.png',
    '/assets/fonts/Inter-latin.woff2',
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

const estStatique = (url) =>
    url.pathname.startsWith('/build/') ||
    url.pathname.startsWith('/assets/fonts/') ||
    url.pathname.startsWith('/assets/icons/') ||
    url.pathname.startsWith('/assets/images/');

self.addEventListener('install', (event) => {
    event.waitUntil(
        caches
            .open(CACHE_STATIQUE)
            // `addAll` échoue en bloc si un seul fichier manque : on tolère
            // les absences plutôt que de laisser l'installation échouer.
            .then((cache) => Promise.allSettled(SOCLE.map((u) => cache.add(u))))
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
    const url = new URL(request.url);
    if (url.origin !== self.location.origin) return;
    if (EXCLUS.some((p) => url.pathname.startsWith(p))) return;

    // --- Navigations : réseau d'abord, page d'attente en dernier recours ---
    if (request.mode === 'navigate') {                          // règle 2
        event.respondWith(
            fetch(request).catch(() =>
                caches.match('/offline.html').then((r) => r || Response.error())
            )
        );
        return;
    }

    // --- Fichiers statiques : cache d'abord, rafraîchi en arrière-plan ---
    if (estStatique(url)) {                                     // règle 3
        event.respondWith(
            caches.match(request).then((enCache) => {
                const reseau = fetch(request)
                    .then((reponse) => {
                        if (reponse && reponse.status === 200 && reponse.type === 'basic') {
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

/** Permet à la page de demander l'activation immédiate d'une nouvelle version. */
self.addEventListener('message', (event) => {
    if (event.data === 'agrierp:activer-maintenant') self.skipWaiting();
});
