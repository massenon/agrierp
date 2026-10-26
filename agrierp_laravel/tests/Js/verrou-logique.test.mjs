// Sprint VW (VW2) — logique pure de la minuterie d'inactivité. Valeurs attendues calculées à la main (PRD § 5).
import test from 'node:test';
import assert from 'node:assert/strict';
import { DUREES, DUREE_PAR_DEFAUT, decider, formaterAttente, dureeValide } from '../../resources/js/verrou-logique.js';

const base = { derniereActivite: 0, minutes: 5, requetesEnCours: 0, suspenduJusqua: 0, verrouille: false };

test('les durées et le défaut sont ceux du poste', () => {
    assert.deepEqual(DUREES, [0, 1, 5, 15, 30]);
    assert.equal(DUREE_PAR_DEFAUT, 5);
});

test('5 minutes : rien à 299 999 ms, verrouillage à 300 000 ms', () => {
    assert.equal(decider({ ...base, maintenant: 299_999 }), 'rien');
    assert.equal(decider({ ...base, maintenant: 300_000 }), 'verrouiller');
    assert.equal(decider({ ...base, maintenant: 900_000 }), 'verrouiller');
});

test('1 minute : verrouillage à 60 000 ms', () => {
    assert.equal(decider({ ...base, minutes: 1, maintenant: 59_999 }), 'rien');
    assert.equal(decider({ ...base, minutes: 1, maintenant: 60_000 }), 'verrouiller');
});

test('30 minutes : verrouillage à 1 800 000 ms', () => {
    assert.equal(decider({ ...base, minutes: 30, maintenant: 1_799_999 }), 'rien');
    assert.equal(decider({ ...base, minutes: 30, maintenant: 1_800_000 }), 'verrouiller');
});

test('Jamais (0) : jamais', () => {
    assert.equal(decider({ ...base, minutes: 0, maintenant: 86_400_000 }), 'rien');
});

test('une requête en vol fait attendre', () => {
    assert.equal(decider({ ...base, requetesEnCours: 1, maintenant: 300_000 }), 'attendre');
    assert.equal(decider({ ...base, requetesEnCours: 1, maintenant: 10_000 }), 'rien');
});

test('une suspension (export, téléchargement) fait attendre jusqu à son terme', () => {
    const s = { ...base, suspenduJusqua: 360_000 };
    assert.equal(decider({ ...s, maintenant: 300_000 }), 'attendre');
    assert.equal(decider({ ...s, maintenant: 359_999 }), 'attendre');
    assert.equal(decider({ ...s, maintenant: 360_000 }), 'verrouiller');
});

test('déjà verrouillé : rien', () => {
    assert.equal(decider({ ...base, verrouille: true, maintenant: 999_999 }), 'rien');
});

test('une durée inconnue retombe sur le défaut de 5 minutes', () => {
    assert.equal(decider({ ...base, minutes: 7, maintenant: 299_999 }), 'rien');
    assert.equal(decider({ ...base, minutes: 7, maintenant: 300_000 }), 'verrouiller');
    assert.equal(decider({ ...base, minutes: 'abc', maintenant: 300_000 }), 'verrouiller');
});

test('dureeValide', () => {
    assert.equal(dureeValide(0), true);
    assert.equal(dureeValide(15), true);
    assert.equal(dureeValide(7), false);
    assert.equal(dureeValide(null), false);
});

test('formaterAttente : comme le poste (1 min 05 s, 42 s)', () => {
    assert.equal(formaterAttente(42), '42 s');
    assert.equal(formaterAttente(59), '59 s');
    assert.equal(formaterAttente(60), '1 min 00 s');
    assert.equal(formaterAttente(65), '1 min 05 s');
    assert.equal(formaterAttente(900), '15 min 00 s');
});
