import 'fake-indexeddb/auto';
import { IDBFactory } from 'fake-indexeddb';
import test from 'node:test';
import assert from 'node:assert/strict';
import { creerCoffre, ouvrirCoffre, chiffrer, dechiffrer, ErreurPin, pinValide, MOTIF_PIN } from '../../resources/js/hors-ligne/coffre.js';
import { ouvrirBase, supprimerBase, MIGRATIONS, DB_VERSION, ErreurBase, NOM_BASE } from '../../resources/js/hors-ligne/base-locale.js';
import { ajouterVente, lister, lotAEnvoyer, marquerSynced, marquerConflit, remettreEnFile, abandonner, nettoyerSynced, lireJournal } from '../../resources/js/hors-ligne/file-envoi.js';
import { etatAffiche, classerReponse, delaiDeReessai, heureDuServeur } from '../../resources/js/hors-ligne/etat.js';
import { creerSynchro, TABLES_GARDEES } from '../../resources/js/hors-ligne/synchro.js';

const ITER = 1000; // 600 000 en production ; ici l'essai doit rester rapide
const nouvelleBase = async () => {
    const idb = new IDBFactory();
    const base = await ouvrirBase({ idb });
    return { idb, base };
};
const vente = (id, plus = {}) => ({ id, payment_mode: 'especes', subtotal: 100, discount: 0, total: 100, lines: [{ product_id: 'p', qty: 1, unit_price: 100, manual_total_amount: 100 }], ...plus });

// --------------------------------------------------------------------------------------------- coffre

test('coffre : PIN de 4 à 6 chiffres, mauvais PIN refusé, le clair n\'est pas dans l\'enveloppe', async () => {
    assert.equal(pinValide('1234'), true);
    assert.equal(pinValide('123'), false);
    assert.equal(pinValide('1234567'), false);
    assert.equal(pinValide('12a4'), false);
    await assert.rejects(creerCoffre('12', { iterations: ITER }), (e) => e instanceof ErreurPin && e.message === MOTIF_PIN);

    const { cle, parametres } = await creerCoffre('4821', { iterations: ITER });
    const env = await chiffrer(cle, { jeton: 'SECRET-TOKEN-123', produit: 'Lapin vivant' });
    assert.ok(!JSON.stringify(env).includes('SECRET'));
    assert.ok(!JSON.stringify(env).includes('Lapin'));
    assert.deepEqual(await dechiffrer(cle, env), { jeton: 'SECRET-TOKEN-123', produit: 'Lapin vivant' });

    const cle2 = await ouvrirCoffre('4821', parametres);
    assert.deepEqual(await dechiffrer(cle2, env), { jeton: 'SECRET-TOKEN-123', produit: 'Lapin vivant' });
    await assert.rejects(ouvrirCoffre('0000', parametres), ErreurPin);
    // deux chiffrements de la même valeur ne donnent pas le même texte (IV propre)
    const a = await chiffrer(cle, 'x'); const b = await chiffrer(cle, 'x');
    assert.notEqual(a.d, b.d);
});

// ------------------------------------------------------------------------------------------- base locale

test('base : schéma v2, migration v1 → v2 SANS perte, base plus récente refusée', async () => {
    const idb = new IDBFactory();
    // Une base de version 1 (telle que la v1 la créait), avec une vente en attente.
    const v1 = await ouvrirBase({ idb, version: 1, migrations: { 1: MIGRATIONS[1] } });
    assert.deepEqual(v1.magasins().sort(), ['meta', 'referentiels', 'ventes']);
    await v1.ecrire('ventes', { id: 'v-ancienne', sync_status: 'pending', cree_le: '2026-11-08T08:00:00.000Z', iv: 'x', d: 'y', tentatives: 0 });
    v1.fermer();

    const v2 = await ouvrirBase({ idb });
    assert.equal(v2.version, DB_VERSION);
    assert.deepEqual(v2.magasins().sort(), ['journal', 'meta', 'referentiels', 'ventes']);
    assert.equal((await v2.lire('ventes', 'v-ancienne')).sync_status, 'pending', 'la file survit à la migration');
    assert.deepEqual(await v2.compter(), { pending: 1, conflict: 0, synced: 0 });
    v2.fermer();

    // Base d'une version PLUS RÉCENTE que l'application : refusée, message français, rien n'est supprimé.
    const idb2 = new IDBFactory();
    const futur = await ouvrirBase({ idb: idb2, version: 3, migrations: { ...MIGRATIONS, 3: () => {} } });
    await futur.ecrire('meta', { cle: 'x', valeur: 1 });
    futur.fermer();
    await assert.rejects(ouvrirBase({ idb: idb2 }), (e) => e instanceof ErreurBase && e.code === 'version-recente' && /plus récente/.test(e.message));
    const encore = await ouvrirBase({ idb: idb2, version: 3, migrations: MIGRATIONS });
    assert.equal((await encore.lire('meta', 'x')).valeur, 1);
});

test('base : une migration qui échoue garde la file intacte', async () => {
    const idb = new IDBFactory();
    const v1 = await ouvrirBase({ idb, version: 1, migrations: { 1: MIGRATIONS[1] } });
    await v1.ecrire('ventes', { id: 'garde', sync_status: 'pending', cree_le: 'x', iv: 'x', d: 'y', tentatives: 0 });
    v1.fermer();
    await assert.rejects(
        ouvrirBase({ idb, migrations: { ...MIGRATIONS, 2: () => { throw new Error('boum'); } } }),
        (e) => e.code === 'migration' && /intactes/.test(e.message),
    );
    const apres = await ouvrirBase({ idb, version: 1, migrations: { 1: MIGRATIONS[1] } });
    assert.equal((await apres.lire('ventes', 'garde')).id, 'garde');
});

test('base : une erreur de quota est dite clairement', async () => {
    const { base } = await nouvelleBase();
    const quota = Object.assign(new Error('plein'), { name: 'QuotaExceededError' });
    const faux = { transaction() { throw quota; } };
    base.db = faux;
    await assert.rejects(base.ecrire('ventes', { id: 'x' }), (e) => e.code === 'quota' && /Espace de stockage/.test(e.message) && /PAS enregistrée/.test(e.message));
});

test('base : suppression complète de la base (déconnexion = purge)', async () => {
    const { idb, base } = await nouvelleBase();
    await base.poserMeta('x', 1);
    base.fermer();
    assert.equal(await supprimerBase({ idb }), true);
    assert.ok(!(await idb.databases()).some((d) => d.name === NOM_BASE));
});

// ----------------------------------------------------------------------------------------- file d'envoi

async function contexte() {
    const { idb, base } = await nouvelleBase();
    const { cle } = await creerCoffre('4821', { iterations: ITER });
    return { idb, base, cle };
}

test('file : une vente est chiffrée au repos, statut et compteurs lisibles sans clé', async () => {
    const ctx = await contexte();
    await ajouterVente(ctx, vente('11111111-1111-4111-8111-111111111111', { client_nom_facture: 'KPOGNON Séraphin', total: 777777 }));
    const brut = await ctx.base.tout('ventes');
    assert.equal(brut.length, 1);
    assert.equal(brut[0].sync_status, 'pending');
    const texte = JSON.stringify(brut);
    assert.ok(!texte.includes('KPOGNON') && !texte.includes('777777'), 'aucun nom ni montant en clair');
    assert.deepEqual(await ctx.base.compter(), { pending: 1, conflict: 0, synced: 0 });
    assert.equal((await lister(ctx))[0].vente.client_nom_facture, 'KPOGNON Séraphin');
});

test('file : synced seulement après l\'accusé ; conflit + motif ; remise en file ; abandon ; nettoyage', async () => {
    const ctx = await contexte();
    for (const id of ['a', 'b', 'c', 'd']) await ajouterVente(ctx, vente(id), () => new Date('2026-11-08T10:00:00Z'));
    assert.equal((await lotAEnvoyer(ctx, 2)).length, 2);

    await marquerSynced(ctx, ['a'], () => new Date('2026-09-01T00:00:00Z'));
    await marquerConflit(ctx, 'b', 'Vente refusée : exercice clos.');
    assert.deepEqual(await ctx.base.compter(), { pending: 2, conflict: 1, synced: 1 });
    const b = (await lister(ctx, 'conflict'))[0];
    assert.equal(b.motif, 'Vente refusée : exercice clos.');
    assert.equal((await lireJournal(ctx))[0].motif, 'Vente refusée : exercice clos.');

    await remettreEnFile(ctx, 'b');
    assert.equal((await lister(ctx, 'pending')).length, 3);
    assert.equal((await lister(ctx, 'pending')).find((l) => l.id === 'b').motif, null);

    await abandonner(ctx, 'c');
    assert.equal((await lister(ctx)).length, 3);

    // 'a' est synced depuis 68 jours : nettoyée ; les pending ne le sont jamais.
    assert.equal(await nettoyerSynced(ctx, 30, () => new Date('2026-11-08T00:00:00Z')), 1);
    assert.deepEqual(await ctx.base.compter(), { pending: 2, conflict: 0, synced: 0 });
});

// ------------------------------------------------------------------------------------------------- état

test('état affiché : priorités et libellés', () => {
    const base = { enLigne: true, enCours: false, suspendu: false, pending: 0, conflict: 0, derniereSynchro: null };
    assert.deepEqual(etatAffiche(base), { cle: 'synchronise', libelle: 'Synchronisé', ton: 'ok' });
    assert.equal(etatAffiche({ ...base, derniereSynchro: heureDuServeur('2026-11-08T14:46:13+01:00') }).libelle, 'Synchronisé — 14:46');
    assert.deepEqual(etatAffiche({ ...base, pending: 3 }), { cle: 'en_attente', libelle: 'En attente (3)', ton: 'attention' });
    assert.deepEqual(etatAffiche({ ...base, enLigne: false }), { cle: 'hors_ligne', libelle: 'Hors ligne', ton: 'neutre' });
    assert.equal(etatAffiche({ ...base, enLigne: false, pending: 2 }).libelle, 'Hors ligne — 2 en attente');
    assert.equal(etatAffiche({ ...base, enLigne: false }).ton, 'neutre', 'hors ligne n\'est jamais une erreur');
    assert.deepEqual(etatAffiche({ ...base, conflict: 2, pending: 1 }), { cle: 'refus', libelle: 'Refus (2)', ton: 'erreur' });
    assert.equal(etatAffiche({ ...base, suspendu: true, conflict: 2 }).cle, 'reconnexion');
    assert.equal(etatAffiche({ ...base, enCours: true }).cle, 'en_cours');
});

test('réponses HTTP classées ; réessais 30 s, 2 min, 5 min, 15 min, 1 h', () => {
    assert.equal(classerReponse(200), 'ok');
    assert.equal(classerReponse(401), 'suspendre');
    assert.equal(classerReponse(403), 'suspendre');
    assert.equal(classerReponse(409), 'reinitialisation');
    assert.equal(classerReponse(413), 'reduire_lot');
    assert.equal(classerReponse(500), 'reessayer');
    assert.equal(classerReponse(429), 'reessayer');
    assert.equal(classerReponse(422), 'refuser');
    assert.deepEqual([0, 1, 2, 3, 4, 9].map(delaiDeReessai), [30000, 120000, 300000, 900000, 3600000, 3600000]);
});

// ------------------------------------------------------------------------------- machine de synchronisation

/** Faux serveur : répond comme `/api/sync/*` ; garde ce qu'il reçoit. */
function fauxServeur({ pages = 1, produits = [{ id: 'p1', name: 'Œufs', pricing_mode: 'fixe', price_min: '2000', stock_qty: '5', species_id: null, tva_rate: '0' }], plus = {} } = {}) {
    const s = { appels: [], ventesRecues: new Map(), reponses: [], file: [] };
    s.fetch = async (url, opts) => {
        const u = new URL(url, 'http://x');
        s.appels.push({ methode: opts.method, chemin: u.pathname, q: Object.fromEntries(u.searchParams), corps: opts.body ? JSON.parse(opts.body) : null, auth: opts.headers.Authorization, credentials: opts.credentials });
        const prevue = s.file.shift();
        if (prevue) return prevue(u, opts);
        if (u.pathname === '/api/sync/pull') {
            const n = Number(u.searchParams.get('page'));
            const j = { page: n, page_suivante: n < pages ? `jeton-${n + 1}` : null };
            if (n === 1) Object.assign(j, { tables_servies: ['products', 'product_categories', 'customers', 'company_settings', 'users'], data_reset_at: null, products: produits, product_categories: [{ id: 'c1', label: 'Œufs' }], customers: [{ id: 'k1', name: 'Awa' }], company_settings: { company_name: 'Ferme', mecef_actif: true, tva_enabled: true, secret_smtp: 'NE-DOIT-PAS-PASSER' }, users: [{ id: 'u', name: 'x' }], ...plus });
            if (!j.page_suivante) j.server_time = `2026-11-08T14:${String(40 + n).padStart(2, '0')}:00+01:00`;
            return new Response(JSON.stringify(j), { status: 200, headers: { date: 'Sun, 08 Nov 2026 13:50:00 GMT' } });
        }
        const corps = JSON.parse(opts.body);
        const accepted = []; const rejected = [];
        for (const v of corps.sales) {
            if (v.refuser) rejected.push({ id: v.id, reason: 'Vente refusée : produit archivé.' });
            else { s.ventesRecues.set(v.id, v); accepted.push(v.id); }
        }
        return new Response(JSON.stringify({ sales: { accepted, rejected } }), { status: 200 });
    };
    return s;
}
const reponse = (statut, json = {}) => async () => new Response(JSON.stringify(json), { status: statut });

async function synchro(opts = {}, serveur = fauxServeur(opts.serveur)) {
    const ctx = await contexte();
    const s = creerSynchro({ base: ctx.base, cle: ctx.cle, jeton: 'JETON', deviceName: 'pwa-test', fetchFn: (...a) => serveur.fetch(...a), maintenant: () => new Date('2026-11-08T13:55:00Z'), tailleLot: opts.tailleLot ?? 20 });
    return { ...ctx, s, serveur };
}

test('synchro : tire d\'abord (pages), garde seulement les tables de la caisse, écrit le curseur serveur', async () => {
    const { s, base, cle, serveur } = await synchro({ serveur: { pages: 3 } });
    const r = await s.synchroniser();
    assert.equal(r.statut, 'ok');
    const pulls = serveur.appels.filter((a) => a.chemin === '/api/sync/pull');
    assert.equal(pulls.length, 3);
    assert.equal(pulls[0].q.page, '1');
    assert.equal(pulls[1].q.curseur_page, 'jeton-2');
    assert.equal(pulls[2].q.curseur_page, 'jeton-3');
    assert.equal(pulls[0].auth, 'Bearer JETON');
    assert.equal(pulls[0].credentials, 'omit');
    assert.equal(await base.meta('curseur'), '2026-11-08T14:43:00+01:00', 'curseur = server_time de la DERNIÈRE page');
    // Seules les tables que le compte lit (`tables_servies`) sont gardées : ici, celles de la caisse.
    assert.deepEqual((await base.tout('referentiels')).map((l) => l.table).sort(), ['company_settings', 'customers', 'product_categories', 'products']);
    assert.ok(TABLES_GARDEES.includes('livestock_lots') && TABLES_GARDEES.includes('livestock_daily_entries') && TABLES_GARDEES.includes('veterinary_withdrawal_periods'));
    const entreprise = await dechiffrer(cle, await base.lire('referentiels', 'company_settings'));
    assert.deepEqual(entreprise[0], { id: 'entreprise', company_name: 'Ferme', tva_enabled: true, tva_default_rate: null, mecef_actif: true });
    assert.ok(!JSON.stringify(await base.tout('referentiels')).includes('NE-DOIT-PAS'));
    assert.equal(await base.meta('decalage_horloge_ms'), Date.parse('2026-11-08T13:50:00Z') - Date.parse('2026-11-08T13:55:00Z'));
    assert.equal(r.recus, 4);
});

test('synchro : le second tirage envoie `since` ; tables_servies changé = tirage complet', async () => {
    const { s, base, serveur } = await synchro();
    await s.synchroniser();
    serveur.appels.length = 0;
    await s.synchroniser();
    assert.equal(serveur.appels.find((a) => a.chemin === '/api/sync/pull').q.since, '2026-11-08T14:41:00+01:00');

    // le compte lit désormais une table de plus : repartir SANS `since`
    serveur.appels.length = 0;
    const orig = serveur.fetch;
    let premiere = true;
    serveur.fetch = async (url, opts) => {
        const rep = await orig(url, opts);
        if (premiere && new URL(url, 'http://x').pathname === '/api/sync/pull') {
            premiere = false;
            const j = await rep.json();
            j.tables_servies.push('sales');
            return new Response(JSON.stringify(j), { status: 200 });
        }
        return rep;
    };
    await s.synchroniser();
    const pulls = serveur.appels.filter((a) => a.chemin === '/api/sync/pull');
    assert.equal(pulls.length, 2);
    assert.ok(pulls[0].q.since, 'premier essai avec since');
    assert.equal(pulls[1].q.since, undefined, 'recommencé sans since');
});

test('synchro : une ligne incohérente est REFUSÉE (comptée), jamais lissée ; un référentiel n\'écrase pas une vente en attente', async () => {
    const serveur = fauxServeur({ produits: [{ id: 'bon', name: 'Œufs', pricing_mode: 'fixe' }, { id: 'mauvais', pricing_mode: 'fixe' }, { name: 'sans id', pricing_mode: 'fixe' }] });
    const { s, base, cle, ...ctx } = await synchro({}, serveur);
    await ajouterVente({ base, cle }, vente('attente-1'));
    serveur.file.push(null); serveur.file.shift();
    const r = await s.synchroniser();
    assert.equal(r.statut, 'ok');
    const produits = await dechiffrer(cle, await base.lire('referentiels', 'products'));
    assert.deepEqual(produits.map((p) => p.id), ['bon']);
    assert.ok(ctx.idb);
    // la vente a été envoyée puis acquittée (pas écrasée par le tirage)
    assert.equal((await lister({ base, cle }, 'synced')).length, 1);
});

test('synchro : envoi idempotent — réponse perdue puis renvoi = UNE vente côté serveur, file `synced`', async () => {
    const { s, base, cle, serveur } = await synchro();
    await ajouterVente({ base, cle }, vente('v-unique'));
    // 1er envoi : le serveur TRAITE la vente puis la réponse est perdue (coupure réseau)
    const orig = serveur.fetch;
    let coupe = true;
    serveur.fetch = async (url, opts) => {
        const rep = await orig(url, opts);
        if (coupe && new URL(url, 'http://x').pathname === '/api/sync/push') { coupe = false; throw new TypeError('Failed to fetch'); }
        return rep;
    };
    const s1 = creerSynchro({ base, cle, jeton: 'J', deviceName: 'pwa-test', fetchFn: (...a) => serveur.fetch(...a), maintenant: () => new Date('2026-11-08T13:55:00Z') });
    const r1 = await s1.synchroniser();
    assert.equal(r1.statut, 'hors_ligne');
    assert.equal((await lister({ base, cle }, 'pending')).length, 1, 'jamais synced sans accusé');
    assert.equal(serveur.ventesRecues.size, 1);
    const r2 = await s1.synchroniser();
    assert.equal(r2.statut, 'ok');
    assert.equal((await lister({ base, cle }, 'synced')).length, 1);
    void s;
});

test('synchro : refus motivé → conflict + motif + journal ; les autres ventes partent', async () => {
    const { s, base, cle } = await synchro();
    await ajouterVente({ base, cle }, vente('bonne'), () => new Date('2026-11-08T10:00:00Z'));
    await ajouterVente({ base, cle }, vente('mauvaise', { refuser: true }), () => new Date('2026-11-08T10:01:00Z'));
    const r = await s.synchroniser();
    assert.equal(r.statut, 'ok');
    assert.equal(r.envoyes, 1);
    assert.equal(r.refuses, 1);
    const c = (await lister({ base, cle }, 'conflict'))[0];
    assert.equal(c.id, 'mauvaise');
    assert.equal(c.motif, 'Vente refusée : produit archivé.');
    assert.equal((await lireJournal({ base, cle })).length, 1);
});

test('synchro : 401 suspend, les ventes restent, « manuel » reprend la main ; reprendre() lève la suspension', async () => {
    const { s, base, cle, serveur } = await synchro();
    await ajouterVente({ base, cle }, vente('v1'));
    serveur.file.push(reponse(401, { message: 'Unauthenticated.' }));
    const r = await s.synchroniser();
    assert.equal(r.statut, 'suspendu');
    assert.match(r.message, /reconnectez-vous/);
    assert.equal((await lister({ base, cle }, 'pending')).length, 1);
    assert.ok(await base.meta('suspendu'));
    const auto = await s.synchroniser();
    assert.equal(auto.statut, 'suspendu');
    assert.equal(serveur.appels.length, 1, 'aucune requête automatique tant que suspendu');
    await s.reprendre();
    assert.equal((await s.synchroniser()).statut, 'ok');
});

test('synchro : 403 (poste différent du jeton) suspend aussi ; 500 → réessai planifié ; 413 réduit le lot', async () => {
    let t = await synchro();
    await ajouterVente(t, vente('a'));
    t.serveur.file.push(null);
    t.serveur.file.shift();
    // tirage 200 puis envoi 403
    t.serveur.file.push(undefined);
    t.serveur.file.shift();
    const orig = t.serveur.fetch;
    let n = 0;
    t.serveur.fetch = async (u, o) => (new URL(u, 'http://x').pathname === '/api/sync/push' && n++ === 0 ? new Response('{"message":"x"}', { status: 403 }) : orig(u, o));
    t.s = creerSynchro({ base: t.base, cle: t.cle, jeton: 'J', deviceName: 'pwa-test', fetchFn: (...a) => t.serveur.fetch(...a) });
    assert.equal((await t.s.synchroniser()).statut, 'suspendu');

    t = await synchro({ tailleLot: 4 });
    for (const id of ['1', '2', '3', '4']) await ajouterVente(t, vente(id));
    let tailles = [];
    const o2 = t.serveur.fetch;
    t.serveur.fetch = async (u, o) => {
        if (new URL(u, 'http://x').pathname === '/api/sync/push') {
            const taille = JSON.parse(o.body).sales.length; tailles.push(taille);
            if (taille > 1) return new Response('{}', { status: 413 });
        }
        return o2(u, o);
    };
    t.s = creerSynchro({ base: t.base, cle: t.cle, jeton: 'J', deviceName: 'pwa-test', fetchFn: (...a) => t.serveur.fetch(...a), tailleLot: 4 });
    const r = await t.s.synchroniser();
    assert.equal(r.statut, 'ok');
    assert.deepEqual(tailles.slice(0, 3), [4, 2, 1]);
    assert.equal((await lister(t, 'synced')).length, 4);

    t = await synchro();
    await ajouterVente(t, vente('x'));
    const o3 = t.serveur.fetch;
    t.serveur.fetch = async (u, o) => (new URL(u, 'http://x').pathname === '/api/sync/push' ? new Response('{"message":"panne"}', { status: 503 }) : o3(u, o));
    t.s = creerSynchro({ base: t.base, cle: t.cle, jeton: 'J', deviceName: 'pwa-test', fetchFn: (...a) => t.serveur.fetch(...a) });
    const e = await t.s.synchroniser();
    assert.equal(e.statut, 'erreur');
    assert.equal(e.prochainEssaiMs, 30000);
    assert.equal((await lister(t, 'pending')).length, 1);
});

test('synchro : jamais deux synchronisations à la fois', async () => {
    const t = await synchro();
    const [a, b] = await Promise.all([t.s.synchroniser(), t.s.synchroniser()]);
    assert.deepEqual([a.statut, b.statut].sort(), ['deja_en_cours', 'ok']);
});

test('synchro : le tirage est inaccessible hors ligne → statut hors_ligne, la file n\'est pas touchée', async () => {
    const t = await synchro();
    await ajouterVente(t, vente('z'));
    t.s = creerSynchro({ base: t.base, cle: t.cle, jeton: 'J', deviceName: 'pwa-test', fetchFn: async () => { throw new TypeError('Failed to fetch'); } });
    const r = await t.s.synchroniser();
    assert.equal(r.statut, 'hors_ligne');
    assert.equal(r.prochainEssaiMs, 30000);
    assert.equal((await lister(t, 'pending')).length, 1);
});
