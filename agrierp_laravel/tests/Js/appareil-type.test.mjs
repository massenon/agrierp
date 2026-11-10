import 'fake-indexeddb/auto';
import { IDBFactory } from 'fake-indexeddb';
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { activer, deverrouiller, etatAppareil, desactiver, decisionDeconnexion } from '../../resources/js/hors-ligne/appairage.js';
import { ouvrirBase } from '../../resources/js/hors-ligne/base-locale.js';
import { ajouterVente } from '../../resources/js/hors-ligne/file-envoi.js';
import { pinValidePour, motifPinPour, MOTIF_PIN, MOTIF_PIN_PERSONNEL } from '../../resources/js/hors-ligne/coffre.js';

/** CAISSE-1 (DV-32) — type d'appareil : entreprise (PIN 4 à 6) ou personnel (PIN de 6 chiffres, tout effacé à la déconnexion). */
const ITER = 1000;
const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const login = async () => new Response(JSON.stringify({ token: '7|JETON-EN-CLAIR-SECRET', user: { id: 'u', name: 'N', username: 'n', role: 'caissier', droits: ['manage-ventes'] }, must_change_password: false }), { status: 200 });
const activerType = (idb, typeAppareil, pin) => activer({ identifiant: 'n', motDePasse: 'x', pin, typeAppareil, idb, iterations: ITER, fetchFn: login });

test('règles du PIN : entreprise 4 à 6 chiffres, personnel 6 chiffres exactement', () => {
    for (const p of ['1234', '12345', '123456']) assert.equal(pinValidePour(p, 'entreprise'), true, p);
    for (const p of ['123', '1234567', 'abcd', '12 34', '']) assert.equal(pinValidePour(p, 'entreprise'), false, p);
    assert.equal(pinValidePour('123456', 'personnel'), true);
    for (const p of ['1234', '12345', '1234567', '12345a', '']) assert.equal(pinValidePour(p, 'personnel'), false, p);
    assert.equal(pinValidePour('1234'), true, 'défaut : entreprise');
    assert.equal(motifPinPour('personnel'), MOTIF_PIN_PERSONNEL);
    assert.equal(motifPinPour('entreprise'), MOTIF_PIN);
    assert.match(MOTIF_PIN_PERSONNEL, /exactement 6 chiffres/);
});

test('activation en appareil personnel : PIN de 5 refusé (message français), PIN de 6 accepté ; type inconnu refusé', async () => {
    const idb = new IDBFactory();
    await assert.rejects(activerType(idb, 'personnel', '48215'), (e) => e.code === 'pin' && /exactement 6 chiffres/.test(e.message));
    await assert.rejects(activerType(idb, 'portable', '482151'), (e) => e.code === 'type');
    assert.equal((await etatAppareil(await ouvrirBase({ idb }))).active, false, 'aucun refus n\'active l\'appareil');
    await activerType(idb, 'personnel', '482151');
    const base = await ouvrirBase({ idb });
    assert.equal((await etatAppareil(base)).typeAppareil, 'personnel');
    const r = await deverrouiller(base, '482151');
    assert.equal(r.typeAppareil, 'personnel');
});

test('appareil de l\'entreprise : PIN de 4 accepté, type par défaut', async () => {
    const idb = new IDBFactory();
    await activer({ identifiant: 'n', motDePasse: 'x', pin: '4821', idb, iterations: ITER, fetchFn: login });
    const base = await ouvrirBase({ idb });
    assert.equal((await deverrouiller(base, '4821')).typeAppareil, 'entreprise');
});

test('le type est mémorisé CHIFFRÉ avec l\'appairage ; une altération de la copie en clair donne « personnel », jamais le plus permissif', async () => {
    const idb = new IDBFactory();
    await activerType(idb, 'personnel', '482151');
    const base = await ouvrirBase({ idb });
    const brut = JSON.stringify(await base.meta('type_appareil'));
    assert.ok(!brut.includes('personnel'), 'copie chiffrée : aucun clair');
    const tout = JSON.stringify(await base.tout('meta'));
    assert.ok(!tout.includes('JETON-EN-CLAIR') && !tout.includes('482151'), 'aucun secret en clair');
    // copie en clair falsifiée vers « entreprise » : au déverrouillage, le type reste « personnel »
    const appareil = await base.meta('appareil');
    await base.poserMeta('appareil', { ...appareil, type_appareil: 'entreprise' });
    assert.equal((await deverrouiller(base, '482151')).typeAppareil, 'personnel');
    // copie en clair incohérente avec la copie chiffrée (clair « personnel », chiffré « entreprise ») : le plus strict l'emporte
    const idb2 = new IDBFactory();
    await activer({ identifiant: 'n', motDePasse: 'x', pin: '4821', idb: idb2, iterations: ITER, fetchFn: login });
    const b2 = await ouvrirBase({ idb: idb2 });
    await b2.poserMeta('appareil', { ...(await b2.meta('appareil')), type_appareil: 'personnel' });
    assert.equal((await deverrouiller(b2, '4821')).typeAppareil, 'personnel');
    // appareil activé avant CAISSE-1 (ni copie chiffrée ni clair) : entreprise
    await base.supprimer('meta', 'type_appareil');
    await base.poserMeta('appareil', { ...(await base.meta('appareil')), type_appareil: undefined });
    assert.equal((await deverrouiller(base, '482151')).typeAppareil, 'entreprise');
});

test('déconnexion : tout est effacé (base, coffre, jeton, copie chiffrée) pour un appareil personnel comme pour un appareil d\'entreprise', async () => {
    for (const [type, pin] of [['personnel', '482151'], ['entreprise', '4821']]) {
        const idb = new IDBFactory();
        await activerType(idb, type, pin);
        let base = await ouvrirBase({ idb });
        const { cle } = await deverrouiller(base, pin);
        await ajouterVente({ base, cle }, { id: 'v1', total: 100 });
        assert.equal((await base.compter()).pending, 1);
        await desactiver({ base, jeton: null, idb, fetchFn: async () => new Response('{}', { status: 200 }) });
        base = await ouvrirBase({ idb });
        const etat = await etatAppareil(base);
        assert.equal(etat.active, false, `${type} : appareil désactivé`);
        assert.deepEqual(await base.tout('meta'), [], `${type} : plus de coffre, de jeton ni de type`);
        assert.deepEqual(await base.tout('ventes'), [], `${type} : plus de vente`);
        assert.deepEqual(await base.tout('referentiels'), [], `${type} : plus de copie chiffrée`);
    }
});

test('déconnexion du web : entreprise = refus tant que des éléments attendent ; personnel = confirmation puis tout effacé', () => {
    assert.equal(decisionDeconnexion('entreprise', 0), 'purger');
    assert.equal(decisionDeconnexion('personnel', 0), 'purger');
    assert.equal(decisionDeconnexion('entreprise', 3), 'refuser');
    assert.equal(decisionDeconnexion(undefined, 3), 'refuser', 'appareil d\'avant : entreprise');
    assert.equal(decisionDeconnexion('personnel', 3), 'confirmer');
    const src = readFileSync(path.join(racine, 'resources/js/hors-ligne/deconnexion-web.js'), 'utf8');
    assert.ok(src.includes("decisionDeconnexion((await base.meta('appareil'))?.type_appareil, n)") && src.includes("decision === 'confirmer'") && src.includes('window.confirm('));
});

test('garde de sources : la page web propose les deux types, l\'entreprise par défaut', () => {
    const vue = readFileSync(path.join(racine, 'resources/views/livewire/profil/mode-hors-ligne.blade.php'), 'utf8');
    assert.ok(vue.includes('id="hl-type-entreprise"') && vue.includes('id="hl-type-personnel"'));
    assert.ok(vue.includes('Appareil de l\'entreprise') && vue.includes('(recommandé)') && vue.includes('Appareil personnel') && vue.includes('PIN de 6 chiffres obligatoire'));
    const page = readFileSync(path.join(racine, 'resources/js/hors-ligne/activation-page.js'), 'utf8');
    assert.ok(page.includes("typeAppareil: TYPE_APPAREIL_PAR_DEFAUT") && page.includes('pinValidePour(this.pin, this.typeAppareil)'));
});
