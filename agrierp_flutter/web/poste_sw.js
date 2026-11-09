/* PWA-2 — service worker du POSTE WEB (portée /poste/).
 *
 * Il ne met en cache QUE l'enveloppe statique de l'application (code, moteur CanvasKit, polices, icônes, sqlite3.wasm,
 * drift_worker.js, index.html STATIQUE) : la liste est injectée au build par outils/generer_sw_poste.py.
 * Les données vivent dans IndexedDB (drift), jamais ici.
 *
 * RÈGLES DURES (gardées par PwaEtPolicesLocalesTest) :
 *  - aucun cache de /api/, /livewire/, /login, /sanctum/, ni d'aucune réponse authentifiée ;
 *  - jamais un POST (ni autre méthode que GET) : on ne répond pas, le navigateur fait sa requête ;
 *  - une requête qui n'est pas dans la liste précachée (et n'est pas une navigation dans /poste/) passe au réseau SANS cache ;
 *  - aucun skipWaiting automatique : une nouvelle version attend la fermeture des onglets (ou le message SKIP_WAITING),
 *    pour qu'une page ouverte ne mélange pas deux versions de son code.
 * Ce fichier ne pose AUCUN en-tête COOP/COEP (drift reste en IndexedDB : voir docs/logialvia/45, §7).
 */
const VERSION = '@@VERSION@@';
const PREFIXE_CACHE = 'poste-enveloppe-';
const CACHE = PREFIXE_CACHE + VERSION;
const PORTEE = new URL('./', self.location).pathname; // « /poste/ »
const FICHIERS = /*@@LISTE@@*/[];
const PRECACHE = new Set(FICHIERS.map((f) => PORTEE + f));
const INDEX = PORTEE + 'index.html';

// Chemins JAMAIS servis ni conservés par ce service worker (données et session).
const INTERDITS = ['/api/', '/livewire/', '/login', '/logout', '/sanctum/', '/storage/', '/caisse'];

function interdit(chemin) {
  return INTERDITS.some((p) => chemin.startsWith(p));
}

self.addEventListener('install', (evenement) => {
  evenement.waitUntil(
    caches.open(CACHE).then((cache) =>
      // `reload` : jamais une copie du cache HTTP du navigateur, toujours le fichier du serveur.
      cache.addAll(FICHIERS.map((f) => new Request(PORTEE + f, { cache: 'reload' })))
    )
  );
});

self.addEventListener('activate', (evenement) => {
  evenement.waitUntil(
    (async () => {
      const noms = await caches.keys();
      await Promise.all(noms.filter((n) => n.startsWith(PREFIXE_CACHE) && n !== CACHE).map((n) => caches.delete(n)));
      await self.clients.claim();
    })()
  );
});

self.addEventListener('message', (evenement) => {
  if (evenement.data === 'SKIP_WAITING') self.skipWaiting();
  if (evenement.data === 'VERSION' && evenement.source) evenement.source.postMessage({ version: VERSION });
});

self.addEventListener('fetch', (evenement) => {
  const requete = evenement.request;
  if (requete.method !== 'GET') return; // jamais un POST
  if (requete.headers.has('Authorization')) return; // jamais une réponse authentifiée

  const url = new URL(requete.url);
  if (url.origin !== self.location.origin) return;
  if (interdit(url.pathname)) return;
  if (!url.pathname.startsWith(PORTEE)) return;

  // Navigation dans /poste/ : l'index STATIQUE (aucune donnée), puis le réseau en repli.
  const navigation = requete.mode === 'navigate';
  const cle = navigation ? INDEX : url.pathname;
  if (!navigation && !PRECACHE.has(cle)) return;

  evenement.respondWith(
    (async () => {
      const cache = await caches.open(CACHE);
      const trouve = await cache.match(cle);
      if (trouve) return trouve;
      return fetch(requete); // enveloppe absente du cache : réseau, sans rien écrire
    })()
  );
});
