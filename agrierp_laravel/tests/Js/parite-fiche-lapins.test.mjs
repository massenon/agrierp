import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { cleRation, rationDe, provendeDuJour, RATIONS_DE_SECOURS, LIBELLES } from '../../resources/js/hors-ligne/fiche-lapins-calculs.js';

/**
 * PWA-3 (fiche lapins) — PARITÉ EXÉCUTÉE de la clé de rationnement et de la provende du jour contre le vrai `CategorieRationLapin` et le
 * vrai `FicheLapins::getProvendeCalculationProperty`. Sans `php` : sauté AVEC sa raison.
 */
const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
let graine = 20261111;
const alea = (n) => { graine = (graine * 1103515245 + 12345) % 2147483648; return Math.floor(graine / 65536) % n; };

const LIBELLES_BAREME = [
    'Reproducteur', 'reproducteurs (lapine)', 'Sous-mères', 'Sous mères', 'SOUS-MÈRES', 'Lapin Sevré', 'Sevrés', 'Jeune', ' jeune ', 'JEUNE', 'Jeunes', 'Jeune porc',
    'Lapin de Chair', 'Jeune (engraissement)', 'Engraissement', 'Porcelet', 'Truie', '', 'Poussin ponte (0 à 2 mois)', 'Œufs', 'Lapereau',
];
const libelles = [...LIBELLES_BAREME, ...Array.from({ length: 80 }, () => LIBELLES_BAREME[alea(LIBELLES_BAREME.length)] + (alea(3) === 0 ? ' x' : ''))];
const provendes = Array.from({ length: 400 }, () => ({
    rations: Array.from({ length: alea(6) }, () => ({ stage_label: LIBELLES_BAREME[alea(LIBELLES_BAREME.length)], ration_g_per_day: 1 + alea(300) })),
    cat: { repro: alea(8) === 0 ? null : alea(120), sevre: alea(8) === 0 ? null : alea(120), jeune: alea(8) === 0 ? null : alea(500) },
}));

let retour = null;
let raison = null;

test('préparation : le PHP répond', (t) => {
    try {
        retour = JSON.parse(execFileSync('php', [path.join(racine, 'tests/Js/parite/executer-fiche-lapins.php')], { input: JSON.stringify({ libelles, provendes }), cwd: racine, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }));
    } catch (e) {
        if (e.code !== 'ENOENT') throw e;
        raison = 'PHP absent de cette machine (parité non exécutée)';
        t.skip(raison);
    }
});

test('clé de rationnement : égale à CategorieRationLapin::cle', (t) => {
    if (!retour) return t.skip(raison);
    libelles.forEach((l, i) => assert.equal(cleRation(l), retour.cles[i], `« ${l} »`));
    assert.ok(new Set(retour.cles).size === 4, 'les trois catégories ET « aucune » sont couvertes');
});

test('provende du jour : lignes, total g et kg égaux à getProvendeCalculationProperty (400 jeux)', (t) => {
    if (!retour) return t.skip(raison);
    let inconnus = 0; let secours = 0;
    provendes.forEach((c, i) => {
        const p = retour.provendes[i];
        assert.deepEqual(provendeDuJour(c.cat, c.rations), p, `cas ${i} ${JSON.stringify(c)}`);
        if (p.total_g === null) inconnus++;
        if (['reproducteur', 'sous_meres', 'chair'].some((k) => !c.rations.some((r) => cleRation(r.stage_label) === k))) secours++;
    });
    assert.ok(inconnus > 40 && secours > 100, `inconnus ${inconnus}, valeurs de secours ${secours}`);
});

test('valeurs de secours et libellés du glossaire du 17/10/2026', () => {
    assert.deepEqual(RATIONS_DE_SECOURS, { reproducteur: 120, sous_meres: 30, chair: 60 });
    assert.deepEqual(LIBELLES, { reproducteur: 'Reproducteur', sous_meres: 'Sous-mères', chair: 'Jeune' });
    assert.equal(rationDe([], 'chair'), 60);
});
