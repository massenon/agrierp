// Sprint VW (VW2) — le composant Alpine `verrouSession` de resources/js/verrou.js, exécuté sans navigateur : le DOM,
// `fetch`, `localStorage`, l'horloge et Livewire sont des doublures. Ce que ce test ne prouve PAS : le rendu réel, le
// focus, `inert` (aucun navigateur ici — voir README_SPRINT0, « NON vérifié »).
import test from 'node:test';
import assert from 'node:assert/strict';

const ecouteursDocument = {};
const ecouteursFenetre = {};
const fabriques = {};
const hooks = {};
const stockage = new Map();
const intervalles = [];
let maintenant = 1_000_000;
let appels = [];
let reponses = [];

Date.now = () => maintenant;
globalThis.Element = class {};
globalThis.document = {
    hidden: false,
    body: { classList: { toggle() {} } },
    addEventListener: (nom, f) => (ecouteursDocument[nom] ??= []).push(f),
    removeEventListener: (nom, f) => { ecouteursDocument[nom] = (ecouteursDocument[nom] ?? []).filter((g) => g !== f); },
    getElementById: () => ({ toggleAttribute() {}, setAttribute() {} }),
};
globalThis.window = {
    Alpine: { data: (nom, f) => { fabriques[nom] = f; } },
    Livewire: { hook: (nom, f) => { hooks[nom] = f; } },
    localStorage: { getItem: (k) => stockage.get(k) ?? null, setItem: (k, v) => stockage.set(k, String(v)) },
    addEventListener: (nom, f) => (ecouteursFenetre[nom] ??= []).push(f),
    removeEventListener: (nom, f) => { ecouteursFenetre[nom] = (ecouteursFenetre[nom] ?? []).filter((g) => g !== f); },
    setInterval: (f) => { intervalles.push(f); return intervalles.length; },
    clearInterval: () => {},
    location: { href: '', reload() { this.rechargee = true; } },
};
globalThis.fetch = async (url, options) => {
    appels.push({ url, options });
    const r = reponses.shift() ?? { status: 200, corps: {} };

    return { ok: r.status >= 200 && r.status < 300, status: r.status, json: async () => r.corps };
};

await import('../../resources/js/verrou.js');
ecouteursDocument['alpine:init'].forEach((f) => f());
ecouteursDocument['livewire:init'].forEach((f) => f());

const CONFIG = {
    minutes: 5, verrouille: false, page: false, erreur: '',
    urlVerrouiller: '/verrouiller', urlDeverrouiller: '/deverrouiller', urlConnexion: '/login', jeton: 'jeton-csrf',
};

function composant(surcharge = {}) {
    const c = fabriques.verrouSession({ ...CONFIG, ...surcharge });
    c.$watch = () => {};
    c.$nextTick = (f) => f();
    c.$refs = { champ: { focus() {} } };
    stockage.clear();
    intervalles.length = 0;
    appels = [];
    reponses = [];
    c.init();

    return c;
}

const tic = () => intervalles.forEach((f) => f());
const attendre = () => new Promise((r) => setImmediate(r));

test('5 minutes sans geste : le serveur est appelé, la surcouche s affiche', async () => {
    maintenant = 1_000_000;
    const c = composant();

    maintenant += 299_000;
    tic();
    await attendre();
    assert.equal(appels.length, 0);
    assert.equal(c.verrouille, false);

    maintenant += 1_000;
    tic();
    await attendre();
    assert.equal(appels.length, 1);
    assert.equal(appels[0].url, '/verrouiller');
    assert.equal(appels[0].options.method, 'POST');
    assert.equal(appels[0].options.headers['X-CSRF-TOKEN'], 'jeton-csrf');
    assert.equal(c.verrouille, true);
    assert.match(stockage.get('agrierp_verrou_etat'), /^verrouille:/);
});

test('un geste repousse l échéance', async () => {
    maintenant = 2_000_000;
    const c = composant();
    maintenant += 200_000;
    ecouteursFenetre.pointerdown.forEach((f) => f());
    maintenant += 200_000; // 400 s après le début, mais 200 s après le geste

    tic();
    await attendre();
    assert.equal(appels.length, 0);
    assert.equal(c.verrouille, false);
});

test('Jamais : aucun appel, même un jour plus tard', async () => {
    maintenant = 3_000_000;
    const c = composant({ minutes: 0 });
    maintenant += 86_400_000;

    tic();
    await attendre();
    assert.equal(appels.length, 0);
    assert.equal(c.verrouille, false);
});

test('une requête Livewire en vol retarde le verrouillage jusqu à sa réponse', async () => {
    maintenant = 4_000_000;
    const c = composant();
    let repondre;
    hooks.request({ respond: (f) => { repondre = f; }, fail: () => {} });

    maintenant += 400_000;
    tic();
    await attendre();
    assert.equal(appels.length, 0, 'requête en vol : on attend');

    repondre({});
    tic();
    await attendre();
    assert.equal(appels.length, 1);
    assert.equal(c.verrouille, true);
});

test('un 423 de Livewire affiche la surcouche sans fenêtre d erreur', () => {
    const c = composant();
    let empeche = false;
    let echec;
    hooks.request({ respond: () => {}, fail: (f) => { echec = f; } });

    echec({ status: 423, preventDefault: () => { empeche = true; } });

    assert.equal(empeche, true);
    assert.equal(c.verrouille, true);
});

test('un autre statut d échec n est pas intercepté', () => {
    const c = composant();
    let empeche = false;
    let echec;
    hooks.request({ respond: () => {}, fail: (f) => { echec = f; } });

    echec({ status: 500, preventDefault: () => { empeche = true; } });

    assert.equal(empeche, false);
    assert.equal(c.verrouille, false);
});

test('déverrouillage : vide, incorrect, bloqué, déconnecté, réussi', async () => {
    const c = composant({ verrouille: true });

    c.motDePasse = '';
    await c.soumettre();
    assert.equal(c.erreur, 'Le mot de passe est obligatoire.');
    assert.equal(appels.length, 0);

    c.motDePasse = 'faux';
    reponses.push({ status: 422, corps: { message: 'Mot de passe incorrect.' } });
    await c.soumettre();
    assert.equal(c.erreur, 'Mot de passe incorrect.');
    assert.equal(c.motDePasse, '');
    assert.equal(c.verrouille, true);
    assert.equal(JSON.parse(appels[0].options.body).password, 'faux');

    c.motDePasse = 'faux2';
    reponses.push({ status: 429, corps: { message: "Trop d'essais.", secondes: 900 } });
    await c.soumettre();
    assert.equal(c.attente, 900);
    assert.equal(c.verrouille, true);

    // Pendant l attente, aucun nouvel envoi.
    c.motDePasse = 'x';
    const avant = appels.length;
    await c.soumettre();
    assert.equal(appels.length, avant);

    c.attente = 0;
    c.motDePasse = 'faux3';
    reponses.push({ status: 401, corps: { deconnecte: true, redirect: '/login' } });
    await c.soumettre();
    assert.equal(window.location.href, '/login');

    window.location.href = '';
    c.motDePasse = 'bon';
    reponses.push({ status: 200, corps: { verrouille: false, retour: '/mon-profil' } });
    await c.soumettre();
    assert.equal(c.verrouille, false);
    assert.match(stockage.get('agrierp_verrou_etat'), /^deverrouille:/);
});

test('sur la page de verrouillage, le succès redirige vers la page demandée', async () => {
    const c = composant({ verrouille: true, page: true });
    c.motDePasse = 'bon';
    reponses.push({ status: 200, corps: { verrouille: false, retour: '/gestion-stocks' } });

    await c.soumettre();

    assert.equal(window.location.href, '/gestion-stocks');
});

test('un autre onglet verrouille ou déverrouille', () => {
    const c = composant();

    ecouteursFenetre.storage.forEach((f) => f({ key: 'agrierp_verrou_etat', newValue: 'verrouille:1' }));
    assert.equal(c.verrouille, true);

    ecouteursFenetre.storage.forEach((f) => f({ key: 'agrierp_verrou_etat', newValue: 'deverrouille:2' }));
    assert.equal(c.verrouille, false);

    ecouteursFenetre.storage.forEach((f) => f({ key: 'autre', newValue: 'verrouille:3' }));
    assert.equal(c.verrouille, false);
});

test('la durée modifiée dans Mon Profil s applique aussitôt (événement Livewire)', () => {
    const c = composant({ minutes: 5 });

    ecouteursFenetre['verrou-delai-modifie'].forEach((f) => f({ detail: { minutes: 30 } }));
    assert.equal(c.minutes, 30);

    ecouteursFenetre['verrou-delai-modifie'].forEach((f) => f({ detail: { minutes: 7 } }));
    assert.equal(c.minutes, 30, 'une durée hors liste est ignorée');
});

test('session expirée pendant le verrou : retour à la connexion', async () => {
    const c = composant({ verrouille: true });
    c.motDePasse = 'bon';
    reponses.push({ status: 419, corps: {} });

    await c.soumettre();

    assert.equal(window.location.href, '/login');
});
