import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import {
    etatPourJour, refusDuPassage, repercuterVente, refusDesLignes, computeEffectifFinal, effectifFinalDepuis, effectifVeille, recalculerEnCascade, recalculerChaine, aUneChaine, teteDeChaine,
    mouvementsConnusAZeroPour, emplacementDeLaLigne, jourFrancais, MOTIFS_VENTE,
} from '../../resources/js/hors-ligne/chaine-effectif.js';

/**
 * PWA-1b / PWA-3 — PARITÉ EXÉCUTÉE DE LA CHAÎNE D'EFFECTIF : 600 scénarios (bande, fiches existantes, départs, UNE vente) rejoués sur le
 * vrai `RecordSaleOnFicheElevageAction` (base SQLite en mémoire). Refus et fiches obtenues doivent être ÉGAUX. Sans `php` : sauté avec sa raison.
 */
const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
let graine = 20261110;
const alea = (n) => { graine = (graine * 1103515245 + 12345) % 2147483648; return Math.floor(graine / 65536) % n; };

const ESPECES = [['cuniculture', 'reproduction'], ['cuniculture', 'croissance'], ['porciculture', 'engraissement'], ['aviculture', 'reproduction'], ['aviculture', 'croissance'], ['aviculture', 'ponte'], ['heliciculture', 'croissance']];
const CATEGORIES = [null, 'reproducteur', 'jeune', 'poussin', 'pondeuse', 'poulette', 'poussin_croissance', 'poussin_ponte', 'inconnue'];
const NOMS = ['Poulet fermier', 'Lapin vivant', 'Œufs'];
const jour = (n) => `2026-11-${String(1 + n).padStart(2, '0')}`;

function scenario() {
    const [code, stage] = ESPECES[alea(ESPECES.length)];
    const lot = { id: 'LOT', code: 'B', species_code: code, stage, initial_quantity: 20 + alea(200) };
    lot.current_quantity = lot.initial_quantity;
    const ponte = code === 'aviculture' && stage === 'ponte';
    const nb = alea(6);
    const jours = [...new Set(Array.from({ length: nb }, () => alea(10)))].sort((a, b) => a - b);
    const fiches = [];
    let courant = lot.initial_quantity;
    const chaine = code === 'aviculture' ? alea(5) !== 0 : alea(3) !== 0; // la plupart des bandes ont un départ
    jours.forEach((j, k) => {
        const f = { entry_date: jour(j), achat: alea(4) === 0 ? alea(10) : 0, ne: alea(4) === 0 ? alea(10) : 0, mort: alea(3) === 0 ? alea(5) : 0, vente: alea(4) === 0 ? alea(8) : 0, don: alea(5) === 0 ? alea(3) : 0 };
        if (alea(6) === 0) f.transfert_entree = alea(5);
        if (alea(6) === 0) f.transfert_sortie = alea(5);
        if (chaine && k === 0) {
            // Départ : tantôt juste (somme = effectif de début de jour), tantôt faux (refus de la chaîne).
            const total = alea(5) === 0 ? courant + 1 + alea(4) : courant;
            const a = alea(total + 1); const b = alea(total - a + 1);
            Object.assign(f, ponte ? { cat_depart_repro: a, cat_depart_sevre: b, cat_depart_jeune: Math.floor((total - a - b) / 2), cat_depart_4: total - a - b - Math.floor((total - a - b) / 2) } : { cat_depart_repro: a, cat_depart_sevre: b, cat_depart_jeune: total - a - b });
            if (alea(8) === 0) delete f.cat_depart_jeune; // départ incomplet = pas de chaîne
        }
        if (alea(5) === 0) Object.assign(f, ponte ? { passage_4_sevre: alea(6), passage_sevre_jeune: alea(6), passage_jeune_repro: alea(6) } : { passage_sevre_jeune: alea(6) });
        if (alea(2) === 0) Object.assign(f, { cat_eff_repro: alea(30), cat_eff_sevre: alea(30), cat_eff_jeune: alea(30), ...(ponte ? { cat_eff_4: alea(30) } : {}) });
        f.effectif_final = effectifFinalDepuis(f, courant);
        courant = f.effectif_final;
        fiches.push(f);
    });
    if (fiches.length > 0) lot.current_quantity = fiches.at(-1).effectif_final;
    const famille = ponte ? ['pondeuse', 'poulette', 'poussin_croissance', 'poussin_ponte'] : ['reproducteur', 'jeune', 'poussin'];
    const categorie = code === 'aviculture' && alea(3) !== 0 ? famille[alea(famille.length)] : CATEGORIES[alea(CATEGORIES.length)];
    const vente = { qty: alea(10) === 0 ? 0 : 1 + alea(6), categorie_effectif: categorie, nom_produit: NOMS[alea(3)], jour: jour(alea(12) === 0 ? 0 : alea(11)) };
    // PWA-3 — lecture de la chaîne : l'état d'un jour (avant, sur, après le départ) et une fiche PROPOSÉE (passage éventuellement trop grand).
    const etat_jour = fiches.length > 0 && alea(2) === 0 ? fiches[alea(fiches.length)].entry_date : jour(alea(12));
    const proposee = { entry_date: jour(alea(12)), achat: 0, ne: alea(4) === 0 ? alea(10) : 0, mort: alea(3) === 0 ? alea(4) : 0, vente: 0, don: 0, effectif_final: 0 };
    if (alea(2) === 0) Object.assign(proposee, ponte ? { passage_4_sevre: alea(60), passage_sevre_jeune: alea(60), passage_jeune_repro: alea(60) } : { passage_sevre_jeune: alea(60) });
    while (fiches.some((f) => f.entry_date === proposee.entry_date)) proposee.entry_date = jour(alea(12) + 10); // jour distinct : la proposée est une NOUVELLE fiche
    return { lot, fiches, vente, etat_jour, proposee };
}

const scenarios = Array.from({ length: 600 }, scenario);
const COLONNES = ['achat', 'ne', 'mort', 'vente', 'don', 'effectif_final', 'mort_repro', 'mort_sevre', 'mort_jeune', 'don_repro', 'don_sevre', 'don_jeune',
    'passage_sevre_jeune', 'vente_repro', 'vente_sevre', 'vente_jeune', 'mort_4', 'don_4', 'vente_4', 'passage_4_sevre', 'passage_jeune_repro',
    'cat_eff_repro', 'cat_eff_sevre', 'cat_eff_jeune', 'cat_eff_4', 'cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune', 'cat_depart_4'];

let retour = null;
let raison = null;

test('préparation : le PHP répond (migrations réelles en mémoire)', (t) => {
    try {
        retour = JSON.parse(execFileSync('php', [path.join(racine, 'tests/Js/parite/executer-chaine.php')], { input: JSON.stringify({ scenarios }), cwd: racine, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 }));
    } catch (e) {
        if (e.code !== 'ENOENT') throw e;
        raison = 'PHP absent de cette machine (parité non exécutée)';
        t.skip(raison);
    }
});

const normaliser = (f) => Object.fromEntries([['entry_date', String(f.entry_date).slice(0, 10)], ...COLONNES.map((c) => [c, f[c] === undefined || f[c] === null ? null : Number(f[c])])]);

test('une vente sur une bande : même refus, mêmes fiches, même quantité que le serveur (600 scénarios)', (t) => {
    if (!retour) return t.skip(raison);
    const couverture = { refus: 0, ok: 0, chaine: 0, nouvelleFiche: 0, cascade: 0, ventilee: 0 };
    scenarios.forEach((s, i) => {
        const p = retour[i];
        const lot = { ...s.lot, code: `B${i}` };
        const fiches = s.fiches.map((f, k) => ({ ...f, id: `f${k}`, lot_id: 'LOT' }));
        const ligne = { lot_id: 'LOT', qty: s.vente.qty, categorie_effectif: s.vente.categorie_effectif, nom_produit: s.vente.nom_produit };
        const r = repercuterVente([ligne], { lots: [lot], fiches }, s.vente.jour);
        const contexte = `scénario ${i} ${JSON.stringify(s)}`;
        if (p.refus !== null) {
            assert.equal(r.ok, false, `refus attendu : ${contexte}`);
            assert.equal(r.motif, p.refus, contexte);
            couverture.refus++;
            return;
        }
        assert.equal(r.ok, true, `${contexte} ; JS : ${r.motif}`);
        const js = [...r.fiches].sort((a, b) => (a.entry_date < b.entry_date ? -1 : 1)).map(normaliser);
        assert.deepEqual(js, p.fiches, contexte);
        assert.equal(r.lots[0].current_quantity, p.current_quantity, `quantité de la bande ${contexte}`);
        couverture.ok++;
        if (aUneChaine(lot, fiches)) couverture.chaine++;
        if (s.vente.qty > 0 && !s.fiches.some((f) => f.entry_date === s.vente.jour)) couverture.nouvelleFiche++;
        if (s.fiches.some((f) => f.entry_date > s.vente.jour)) couverture.cascade++;
        if (p.fiches.some((f) => f.vente_repro || f.vente_sevre || f.vente_jeune || f.vente_4)) couverture.ventilee++;
    });
    // La grille touche vraiment les cas délicats (sinon la parité ne prouverait rien).
    assert.ok(couverture.refus > 30 && couverture.ok > 200, JSON.stringify(couverture));
    assert.ok(couverture.chaine > 100 && couverture.nouvelleFiche > 50 && couverture.cascade > 40 && couverture.ventilee > 30, JSON.stringify(couverture));
});

test('lecture de la chaîne : état d\'un jour et refus d\'une fiche proposée égaux au serveur (600 scénarios)', (t) => {
    if (!retour) return t.skip(raison);
    const modes = {}; let passagesRefuses = 0;
    scenarios.forEach((s, i) => {
        const p = retour[i];
        const lot = { ...s.lot, code: `B${i}` };
        const fiches = s.fiches.map((f, k) => ({ ...f, id: `f${k}`, lot_id: 'LOT' }));
        const contexte = `scénario ${i} ${JSON.stringify(s)}`;
        const etat = etatPourJour(lot, fiches, s.etat_jour);
        assert.deepEqual(etat, p.etat, `état du jour : ${contexte}`);
        modes[etat.mode] = (modes[etat.mode] ?? 0) + 1;
        const refus = refusDuPassage(lot, { ...s.proposee, id: 'proposee', lot_id: 'LOT' }, fiches);
        assert.equal(refus, p.passage, `passage : ${contexte}`);
        if (refus) passagesRefuses++;
    });
    assert.ok(['sans_chaine', 'avant_depart', 'refus', 'chaine'].every((m) => modes[m] > 20), JSON.stringify(modes));
    assert.ok(passagesRefuses > 15, `passages refusés couverts : ${passagesRefuses}`);
});

test('motifs de refus : mêmes mots que MotifsRefusPush ; fonctions de base', () => {
    assert.equal(computeEffectifFinal(10, 2, 3, 4, 5, 1, 2, 1), 6);
    assert.equal(computeEffectifFinal(1, 0, 0, 5, 0), 0, 'plancher à 0');
    assert.equal(jourFrancais('2026-11-09'), '09/11/2026');
    assert.equal(effectifVeille({ initial_quantity: 40 }, [], '2026-11-02'), 40);
    assert.ok(MOTIFS_VENTE.sansDepart('B1').startsWith('Vente refusée : l\'effectif de départ par catégorie de la bande B1 n\'est pas saisi.'));
    assert.equal(emplacementDeLaLigne({ species_code: 'cuniculture', stage: 'croissance' }, { categorie_effectif: 'jeune' }), null, 'les lapins ne se ventilent pas');
    assert.equal(emplacementDeLaLigne({ species_code: 'aviculture', stage: 'ponte' }, { categorie_effectif: 'poulette' }), 'jeune');
    assert.equal(emplacementDeLaLigne({ species_code: 'aviculture', stage: 'ponte' }, { categorie_effectif: 'jeune' }), null, 'autre famille');
    assert.deepEqual(Object.keys(mouvementsConnusAZeroPour({ species_code: 'aviculture', stage: 'ponte' })).length, 15);
    assert.equal(refusDesLignes([], { lots: [], fiches: [] }, '2026-11-01'), null);
    assert.equal(teteDeChaine({ species_code: 'cuniculture', stage: 'reproduction' }, []), null);
    assert.equal(recalculerChaine({ species_code: 'heliciculture', stage: 'x' }, []).chaine, false);
    assert.equal(recalculerEnCascade({ initial_quantity: 5, current_quantity: 5 }, [], '2026-11-01').lot.current_quantity, 5);
});
