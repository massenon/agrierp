import 'fake-indexeddb/auto';
import { IDBFactory } from 'fake-indexeddb';
import test from 'node:test';
import assert from 'node:assert/strict';
import { activer, deverrouiller, etatAppareil, desactiver, purgerLocal, prerequis } from '../../resources/js/hors-ligne/appairage.js';
import { ouvrirBase } from '../../resources/js/hors-ligne/base-locale.js';
import { ajouterVente } from '../../resources/js/hors-ligne/file-envoi.js';
import { ErreurPin, dechiffrer } from '../../resources/js/hors-ligne/coffre.js';
import { filtrerProduits, etatTuile, fourchetteDePrix, messageAgeTirage, normaliser, SEUIL_AVERTISSEMENT_PRIX_JOURS, SEUIL_CONFIRMATION_PRIX_JOURS, niveauPrixPerimes, messageBandeauPrix, messageConfirmationVente, NIVEAUX_PRIX } from '../../resources/js/hors-ligne/catalogue.js';
import { ageDuTirageEnJours } from '../../resources/js/hors-ligne/etat.js';

const ITER = 1000;
const reponseLogin = (corps = {}, statut = 200) => async () => new Response(JSON.stringify({ token: '7|JETON-EN-CLAIR-SECRET', user: { id: 'u', name: 'Caissière', username: 'caisse', role: 'caissier' }, must_change_password: false, ...corps }), { status: statut });

test('prérequis : HTTPS, WebCrypto, IndexedDB', () => {
    assert.equal(prerequis({ isSecureContext: true, crypto: { subtle: {} }, indexedDB: {} }).ok, true);
    assert.match(prerequis({ isSecureContext: false, crypto: { subtle: {} }, indexedDB: {} }).motif, /HTTPS/);
    assert.match(prerequis({ isSecureContext: true, crypto: {}, indexedDB: {} }).motif, /chiffrement/);
});

test('activation : jeton nommé pwa-<uuid>, chiffré, mot de passe jamais conservé', async () => {
    const idb = new IDBFactory();
    let envoye = null;
    const r = await activer({
        identifiant: 'caisse', motDePasse: 'MOT-DE-PASSE-SECRET', pin: '4821', idb, iterations: ITER,
        fetchFn: async (u, o) => { envoye = { u, o: { ...o, body: JSON.parse(o.body) } }; return (await reponseLogin())(); },
    });
    assert.match(r.deviceName, /^pwa-[0-9a-f-]{36}$/);
    assert.equal(envoye.u, '/api/auth/login');
    assert.equal(envoye.o.body.device_name, r.deviceName);
    assert.equal(envoye.o.credentials, 'omit');

    const base = await ouvrirBase({ idb });
    const brut = JSON.stringify(await base.tout('meta'));
    assert.ok(!brut.includes('JETON-EN-CLAIR'), 'jeton chiffré');
    assert.ok(!brut.includes('MOT-DE-PASSE'), 'mot de passe jamais conservé');
    assert.ok(!brut.includes('4821'), 'PIN jamais conservé');
    const etat = await etatAppareil(base);
    assert.equal(etat.active, true);
    assert.equal(etat.deviceName, r.deviceName);

    const { jeton } = await deverrouiller(base, '4821');
    assert.equal(jeton, '7|JETON-EN-CLAIR-SECRET');
});

test('activation : refus clairs (PIN, hors ligne, identifiants, limite, mot de passe temporaire)', async () => {
    const idb = new IDBFactory();
    const essai = (fetchFn, plus = {}) => activer({ identifiant: 'c', motDePasse: 'x', pin: '4821', idb, iterations: ITER, fetchFn, ...plus });
    await assert.rejects(essai(reponseLogin(), { pin: '12' }), /4 à 6 chiffres/);
    await assert.rejects(essai(async () => { throw new TypeError('Failed to fetch'); }), (e) => e.code === 'reseau' && /EN LIGNE/.test(e.message));
    await assert.rejects(essai(async () => new Response(JSON.stringify({ errors: { identifiant: ['Identifiants incorrects.'] } }), { status: 422 })), /Identifiants incorrects\./);
    await assert.rejects(essai(async () => new Response('{}', { status: 429 })), /Trop de tentatives/);
    await assert.rejects(essai(reponseLogin({ must_change_password: true })), (e) => e.code === 'mot-de-passe-temporaire');
    const base = await ouvrirBase({ idb });
    assert.equal((await etatAppareil(base)).active, false, 'aucun refus n\'active l\'appareil');
});

test('réactivation : même appareil = même nom (le serveur remplace le jeton) ; une file existante n\'est pas écrasée', async () => {
    const idb = new IDBFactory();
    const a = await activer({ identifiant: 'c', motDePasse: 'x', pin: '4821', idb, iterations: ITER, fetchFn: reponseLogin() });
    const b = await activer({ identifiant: 'c', motDePasse: 'x', pin: '5555', idb, iterations: ITER, fetchFn: reponseLogin() });
    assert.equal(a.deviceName, b.deviceName);

    const base = await ouvrirBase({ idb });
    const { cle } = await deverrouiller(base, '5555');
    await ajouterVente({ base, cle }, { id: 'v1', total: 100 });
    base.fermer();
    await assert.rejects(activer({ identifiant: 'c', motDePasse: 'x', pin: '9999', idb, iterations: ITER, fetchFn: reponseLogin() }), (e) => e.code === 'file-existante' && /1 vente\(s\) non envoyée\(s\)/.test(e.message));
});

test('PIN : compteur d\'échecs, avertissement avant le dernier essai, 10 échecs = effacement', async () => {
    const idb = new IDBFactory();
    await activer({ identifiant: 'c', motDePasse: 'x', pin: '4821', idb, iterations: ITER, fetchFn: reponseLogin() });
    const base = await ouvrirBase({ idb });
    const messages = [];
    for (let i = 1; i <= 9; i++) {
        await assert.rejects(deverrouiller(base, '0000', { idb }), (e) => { messages.push(e.message); return e instanceof ErreurPin; });
    }
    assert.match(messages[0], /PIN incorrect \(1\/10\)/);
    assert.match(messages[6], /Attention : 3 essai\(s\) avant l'EFFACEMENT/);
    assert.match(messages[8], /1 essai\(s\) avant l'EFFACEMENT/);
    // un bon PIN remet le compteur à zéro
    await deverrouiller(base, '4821', { idb });
    assert.equal(await base.meta('echecs_pin'), 0);

    for (let i = 1; i <= 9; i++) await assert.rejects(deverrouiller(base, '1111', { idb }));
    await assert.rejects(deverrouiller(base, '1111', { idb }), /Trop d'échecs : les données de cet appareil ont été effacées/);
    assert.ok(!(await idb.databases()).some((d) => d.name === 'agrierp_hors_ligne'), 'la base est supprimée');
});

test('désactivation : jeton révoqué côté serveur si joignable, puis purge ; hors ligne : purge quand même', async () => {
    let idb = new IDBFactory();
    await activer({ identifiant: 'c', motDePasse: 'x', pin: '4821', idb, iterations: ITER, fetchFn: reponseLogin() });
    let base = await ouvrirBase({ idb });
    const { jeton } = await deverrouiller(base, '4821');
    let appel = null;
    const r = await desactiver({ base, jeton, idb, fetchFn: async (u, o) => { appel = { u, auth: o.headers.Authorization }; return new Response('{}', { status: 200 }); } });
    assert.deepEqual(appel, { u: '/api/auth/logout', auth: 'Bearer 7|JETON-EN-CLAIR-SECRET' });
    assert.equal(r.revoque, true);
    assert.ok(!(await idb.databases()).some((d) => d.name === 'agrierp_hors_ligne'));

    idb = new IDBFactory();
    await activer({ identifiant: 'c', motDePasse: 'x', pin: '4821', idb, iterations: ITER, fetchFn: reponseLogin() });
    base = await ouvrirBase({ idb });
    const hors = await desactiver({ base, jeton: 'x', idb, fetchFn: async () => { throw new TypeError('offline'); } });
    assert.equal(hors.revoque, false);
    assert.ok(!(await idb.databases()).some((d) => d.name === 'agrierp_hors_ligne'));
    assert.equal(await purgerLocal({ idb }), true);
});

test('catalogue : filtre sans accents, catégorie, tuiles non vendables, âge du tirage', () => {
    const produits = [
        { id: '1', name: 'Œufs de table', sku: 'OEUF', category_id: 'c1', pricing_mode: 'fourchette', price_min: '2000', price_max: '2500' },
        { id: '2', name: 'Lapin vivant', category_id: 'c2', species_id: 's', pricing_mode: 'fourchette', price_min: '6000', price_max: '11000' },
        { id: '3', name: 'Cage 4', category_id: 'c3', pricing_mode: 'quote' },
        { id: '4', name: 'Légumes frais', category_id: 'c1', pricing_mode: 'fixe', price_min: '2500', price_max: '2500' },
        { id: '5', name: 'Archivé', is_active: false, pricing_mode: 'fixe' },
    ];
    assert.deepEqual(filtrerProduits(produits).map((p) => p.id), ['3', '2', '4', '1'], 'actifs seulement, triés sans accents ni casse');
    assert.deepEqual(filtrerProduits(produits, 'legumes').map((p) => p.id), ['4']);
    assert.deepEqual(filtrerProduits(produits, 'œufs').map((p) => p.id), ['1']);
    assert.deepEqual(filtrerProduits(produits, '', 'c1').map((p) => p.id), ['4', '1']);
    assert.equal(etatTuile(produits[1]).vendable, false);
    assert.equal(etatTuile(produits[2]).note, 'Sur devis technique');
    assert.equal(etatTuile(produits[0]).vendable, true);
    assert.equal(fourchetteDePrix(produits[0]), '2 000 – 2 500 FCFA');
    assert.equal(fourchetteDePrix(produits[3]), '2 500 FCFA');
    assert.equal(normaliser('  Œufs É '), 'œufs e');
    assert.equal(messageAgeTirage(5), 'Dernier tirage du catalogue : il y a 5 jours.');
    assert.equal(messageAgeTirage(1), 'Dernier tirage du catalogue : il y a 1 jour.');
    assert.match(messageAgeTirage(0), /aujourd'hui/);
    assert.match(messageAgeTirage(null), /jamais tiré/);
});

test('un jeton déchiffré n\'est pas lisible sans le bon PIN', async () => {
    const idb = new IDBFactory();
    await activer({ identifiant: 'c', motDePasse: 'x', pin: '4821', idb, iterations: ITER, fetchFn: reponseLogin() });
    const base = await ouvrirBase({ idb });
    const { cle } = await deverrouiller(base, '4821');
    assert.equal(await dechiffrer(cle, await base.meta('jeton')), '7|JETON-EN-CLAIR-SECRET');
    await assert.rejects(deverrouiller(base, '4822', { idb }), ErreurPin);
});

// ---------------------------------------------------------------------------------------------------------------
// CONF-3 (DV-21) — prix périmés : 3 jours = avertissement, 7 jours = confirmation avant chaque vente, jamais un refus.

test('CONF-3 : les seuils sont des constantes nommées (3 et 7 jours)', () => {
    assert.equal(SEUIL_AVERTISSEMENT_PRIX_JOURS, 3);
    assert.equal(SEUIL_CONFIRMATION_PRIX_JOURS, 7);
});

test('CONF-3 : niveau selon l\'âge, aux bornes exactes', () => {
    for (const [jours, niveau] of [[null, 'aucun'], [undefined, 'aucun'], [0, 'aucun'], [1, 'aucun'], [2, 'aucun'], [3, 'avertissement'], [6, 'avertissement'], [7, 'confirmation'], [8, 'confirmation'], [90, 'confirmation']]) {
        assert.equal(niveauPrixPerimes(jours), niveau, `${jours} jour(s)`);
    }
    assert.equal(NIVEAUX_PRIX.confirmation, 'confirmation');
});

test('CONF-3 : libellés français, état vide sans « 0 », jamais de refus dans le texte', () => {
    assert.equal(messageBandeauPrix(0), '');
    assert.equal(messageBandeauPrix(2), '');
    assert.equal(messageBandeauPrix(null), '');
    assert.equal(messageBandeauPrix(3), 'Prix tirés il y a 3 jours : reconnectez-vous pour les actualiser.');
    assert.match(messageBandeauPrix(8), /^Attention : les prix datent de 8 jours et peuvent être périmés\./);
    assert.equal(messageConfirmationVente(8), 'Les prix datent de 8 jours et peuvent être périmés. Confirmer la vente ?');
    assert.equal(messageAgeTirage(0), "Catalogue tiré aujourd'hui.");
});

test('CONF-3 : l\'âge se calcule sur le dernier tirage RÉUSSI, horloge corrigée du décalage serveur', () => {
    const J = 86_400_000;
    const tirage = '2026-11-01T10:00:00.000Z';
    const t = Date.parse(tirage);
    assert.equal(ageDuTirageEnJours(null, t), null, 'aucun tirage : pas d\'âge');
    assert.equal(ageDuTirageEnJours(tirage, t + 3 * J - 1), 2);
    assert.equal(ageDuTirageEnJours(tirage, t + 3 * J), 3);
    assert.equal(ageDuTirageEnJours(tirage, t + 8 * J), 8);
    // Appareil en AVANCE de 5 jours : sans correction il croirait 8 jours ; le décalage mesuré (-5 j) ramène à 3.
    assert.equal(ageDuTirageEnJours(tirage, t + 8 * J, -5 * J), 3);
    // Appareil en retard : jamais d'âge négatif.
    assert.equal(ageDuTirageEnJours(tirage, t - 2 * J), 0);
});
