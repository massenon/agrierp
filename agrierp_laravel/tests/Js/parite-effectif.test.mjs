import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import {
    calculerJour, verifierDepart, especeDuLot, categorieDuStade, categorieDeLaBande, departDepuisStade, LAPINS, PORCS, VOLAILLES_REPRO, VOLAILLES_PONTE,
} from '../../resources/js/hors-ligne/effectif-categories.js';

/**
 * PWA-3 — PARITÉ EXÉCUTÉE DU CALCUL D'EFFECTIF contre le vrai `EffectifParCategorieService` (lapins, porcs, volailles reproductrices,
 * volailles pondeuses à quatre stades, départ, déduction depuis le stade). Plus de 1 000 jeux pseudo-aléatoires reproductibles, avec
 * des inconnus (`null`), des passages trop grands, des transferts et des totaux faux. Sans `php` : les essais se sautent AVEC leur raison.
 */
const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
let graine = 20261109;
const alea = (n) => { graine = (graine * 1103515245 + 12345) % 2147483648; return Math.floor(graine / 65536) % n; };
const valeur = (inconnuPossible) => { const t = alea(10); return inconnuPossible && t < 2 ? null : (t < 5 ? 0 : alea(60)); };

const CLES = [
    'achat', 'ne', 'vente', 'vente_repro', 'vente_sevre', 'vente_jeune', 'vente_4', 'mort_repro', 'mort_sevre', 'mort_jeune', 'mort_4',
    'don_repro', 'don_sevre', 'don_jeune', 'don_4', 'passage', 'passage_4_sevre', 'passage_jeune_repro',
    'transfert_entree_repro', 'transfert_entree_sevre', 'transfert_entree_jeune', 'transfert_entree_4',
    'transfert_sortie_repro', 'transfert_sortie_sevre', 'transfert_sortie_jeune', 'transfert_sortie_4',
];
const ESPECES = [LAPINS, PORCS, VOLAILLES_REPRO, VOLAILLES_PONTE];

const jours = [];
for (let i = 0; i < 1200; i++) {
    const espece = ESPECES[i % 4];
    const inconnus = espece === LAPINS || espece === PORCS; // les volailles n'ont aucun inconnu
    const veille = { repro: valeur(inconnus) === null ? null : alea(120), sevre: alea(120), jeune: alea(120) };
    if (inconnus && alea(8) === 0) veille.sevre = null;
    if (espece === VOLAILLES_PONTE) veille.quatre = alea(120);
    const mouvements = {};
    for (const cle of CLES) if (alea(3) !== 0) mouvements[cle] = valeur(inconnus);
    jours.push({ espece, veille, mouvements, total: alea(5) === 0 ? null : alea(300) });
}
jours.push({ espece: 'heliciculture', veille: {}, mouvements: {}, total: null });

const departs = [];
const nulOu = (n) => (alea(6) === 0 ? null : n);
for (let i = 0; i < 400; i++) {
    const depart = { repro: nulOu(alea(80)), sevre: nulOu(alea(80)), jeune: nulOu(alea(80)) };
    if (i % 2 === 1) depart.quatre = nulOu(alea(80));
    const somme = ['repro', 'sevre', 'jeune', 'quatre'].reduce((s, c) => s + (depart[c] ?? 0), 0);
    departs.push({ depart, total: alea(4) === 0 ? null : (alea(3) === 0 ? somme + 1 + alea(5) : somme) });
}

const lots = [];
for (const code of [null, 'cuniculture', 'porciculture', 'aviculture', 'heliciculture', 'escargot']) {
    for (const stage of ['reproduction', 'croissance', 'engraissement', 'ponte', 'autre', null]) for (const total of [-5, 0, 37]) lots.push({ code, stage, total });
}

let retour = null;
let raison = null;

test('préparation : le PHP répond', (t) => {
    try {
        retour = JSON.parse(execFileSync('php', [path.join(racine, 'tests/Js/parite/executer-effectif.php')], {
            input: JSON.stringify({ jours, departs, lots }), cwd: racine, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024,
        }));
    } catch (e) {
        // Seule l'ABSENCE de PHP saute les essais ; un PHP présent qui échoue est une VRAIE panne.
        if (e.code !== 'ENOENT') throw e;
        raison = 'PHP absent de cette machine (parité non exécutée)';
        t.skip(raison);
    }
});

test('calculerJour : mêmes catégories, mêmes refus, mêmes passages que le serveur (1 200 jeux)', (t) => {
    if (!retour) return t.skip(raison);
    let refus = 0; let inconnus = 0; let pondeuses = 0;
    jours.forEach((c, i) => {
        const p = retour.jours[i];
        let js;
        try { js = calculerJour(c.espece, c.veille, c.mouvements, c.total); } catch (e) { js = { erreur: e.message }; }
        const contexte = `cas ${i} ${JSON.stringify(c)}`;
        if (p.erreur) { assert.deepEqual(js, p, contexte); return; }
        assert.deepEqual({ ...js, passagesAppliques: { ...js.passagesAppliques } }, { ...p, passagesAppliques: { ...p.passagesAppliques } }, contexte);
        if (p.refus) refus++;
        if (p.repro === null || p.sevre === null || p.jeune === null) inconnus++;
        if (c.espece === VOLAILLES_PONTE) pondeuses++;
    });
    // La grille touche vraiment les cas délicats (sinon la parité ne prouverait rien).
    assert.ok(refus > 80, `passages refusés couverts : ${refus}`);
    assert.ok(inconnus > 80, `inconnus couverts : ${inconnus}`);
    assert.equal(pondeuses, 300);
});

test('verifierDepart : même motif de refus que le serveur (trois et quatre stades)', (t) => {
    if (!retour) return t.skip(raison);
    let refuses = 0;
    departs.forEach((c, i) => {
        assert.equal(verifierDepart(c.depart, c.total), retour.departs[i], `départ ${i} ${JSON.stringify(c)}`);
        if (retour.departs[i]) refuses++;
    });
    assert.ok(refuses > 100 && refuses < departs.length, `refus couverts : ${refuses}`);
});

test('espèce de la bande, catégorie du stade, départ déduit : égaux au serveur', (t) => {
    if (!retour) return t.skip(raison);
    lots.forEach((c, i) => {
        const lot = { species_code: c.code, stage: c.stage };
        const p = retour.lots[i];
        assert.equal(especeDuLot(lot), p.espece, `espèce ${JSON.stringify(c)}`);
        assert.equal(categorieDuStade(c.stage), p.categorie_stade, `catégorie du stade ${JSON.stringify(c)}`);
        assert.equal(categorieDeLaBande(lot), p.categorie_bande, `catégorie de la bande ${JSON.stringify(c)}`);
        assert.deepEqual(departDepuisStade(lot, c.total), p.depart, `départ déduit ${JSON.stringify(c)}`);
    });
});
