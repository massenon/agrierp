import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { calculsEscargots, chargerJourEscargots, enregistrerJourEscargots, MOTIFS_ESCARGOTS } from '../../resources/js/hors-ligne/fiche-escargots.js';
import { chargerJour, enregistrerJour, MOTIFS, refusExerciceClos } from '../../resources/js/hors-ligne/fiche-lapins-saisie.js';
import { FAMILLES } from '../../resources/js/hors-ligne/fiche-familles.js';
import { computeEffectifFinal, jourDe } from '../../resources/js/hors-ligne/chaine-effectif.js';

/**
 * PWA-3 (fiche escargots) — PARITÉ EXÉCUTÉE de la saisie d'un jour contre le vrai composant `FicheEscargots` (ouverture du jour, aperçu, `saveDay`,
 * SQLite en mémoire, module `helico` activé) : saisie rechargée, effectif final, taux de mortalité, taux d'éclosion, poids estimé, refus, fiches
 * écrites (colonnes de répartition des morts et dons NON touchées) et cascade de l'effectif. Sans `php` : sauté AVEC sa raison.
 */
const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
let graine = 20261118;
const alea = (n) => { graine = (graine * 1103515245 + 12345) % 2147483648; return Math.floor(graine / 65536) % n; };
const uuid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const deux = (n) => String(n).padStart(2, '0');
const jourDuMois = (d) => `2026-${d > 31 ? '11' : '10'}-${deux(d > 31 ? d - 31 : d)}`;

const NB = Number(process.env.SCENARIOS_LIMITE ?? 400);
let compteur = 0;
const scenarios = [];
for (let i = 0; i < NB; i++) {
    const initial = 50 + alea(400);
    const lot = { id: uuid(++compteur), code: `ESC-${i}`, species_code: 'helico', stage: 'croissance', initial_quantity: initial, current_quantity: initial, status: 'actif', is_active: true };
    const jours = [...new Set(Array.from({ length: alea(7) }, () => 25 + alea(16)))].sort((a, b) => a - b);
    const fiches = [];
    let courant = initial;
    for (const d of jours) {
        const f = {
            id: uuid(++compteur), lot_id: lot.id, entry_date: jourDuMois(d), achat: alea(5) === 0 ? alea(20) : 0, ne: alea(3) === 0 ? alea(80) : 0, mort: alea(4) === 0 ? alea(10) : 0,
            vente: alea(6) === 0 ? alea(10) : 0, don: alea(8) === 0 ? alea(5) : 0, ponte_total: alea(3) === 0 ? null : alea(200),
            effectif_m: alea(100), effectif_f: alea(100), effectif_sevres: alea(100), transfert_entree: alea(10) === 0 ? 1 + alea(5) : 0, transfert_sortie: alea(10) === 0 ? 1 + alea(5) : 0,
        };
        if (alea(3) === 0) f.weight_sample_avg_g = 5 + alea(60);
        f.effectif_final = alea(12) === 0 ? alea(500) : computeEffectifFinal(courant, f.achat, f.ne, f.mort, f.vente, f.don, f.transfert_entree, f.transfert_sortie);
        courant = f.effectif_final;
        fiches.push(f);
    }
    if (fiches.length > 0) lot.current_quantity = courant;
    const jour = fiches.length > 0 && alea(3) !== 0 ? jourDe(fiches[alea(fiches.length)]) : jourDuMois(25 + alea(16)); // souvent un jour déjà saisi
    const exercices = [{ id: 1, year: 2026, start_date: '2026-01-01', end_date: '2026-12-31', status: alea(8) === 0 ? 'cloture' : 'ouvert' }];
    const surcharges = {};
    const mettre = (p, v) => { if (alea(2) === 0) surcharges[p] = v; };
    mettre('achat', alea(15)); mettre('oeufsTerre', alea(5) === 0 ? 0 : alea(300)); mettre('naissainsNes', alea(100));
    if (alea(3) === 0) { mettre('mortBorde', alea(4)); mettre('mortEngraissement', alea(6)); mettre('mortNaissain', alea(alea(6) === 0 ? 700 : 8)); }
    if (alea(3) === 0) { mettre('donBorde', alea(3)); mettre('donEngraissement', alea(3)); mettre('donNaissain', alea(4)); }
    mettre('effectifNaissains', alea(120)); mettre('effectifEngraissement', alea(120)); mettre('effectifBordes', alea(120));
    if (alea(3) === 0) mettre('peseeTotal', alea(3) === 0 ? null : 100 + alea(5000));
    scenarios.push({ famille: 'escargots', aujourdhui: '2026-11-09', lot, fiches, exercices, jour, saisie: surcharges, provende: { produit: null, feed_types: [], releve: null }, rations: [] });
}

let retour = null;
let raison = null;
test('préparation : le PHP répond', (t) => {
    try {
        retour = JSON.parse(execFileSync('php', [path.join(racine, 'tests/Js/parite/executer-fiche-saisie.php')], { input: JSON.stringify({ scenarios }), cwd: racine, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 }));
    } catch (e) {
        if (e.code !== 'ENOENT') throw e;
        raison = 'PHP absent de cette machine (parité non exécutée)';
        t.skip(raison);
    }
});

const COLONNES = ['achat', 'ne', 'mort', 'vente', 'don', 'effectif_final', 'effectif_m', 'effectif_f', 'effectif_sevres', 'ponte_total', 'feed_qty_kg', 'mort_repro', 'mort_sevre', 'mort_jeune',
    'don_repro', 'don_sevre', 'don_jeune', 'passage_sevre_jeune', 'weight_sample_avg_g', 'cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune', 'cat_eff_repro', 'cat_eff_sevre', 'cat_eff_jeune'];
const normaliser = (fiches) => [...fiches].sort((a, b) => (jourDe(a) < jourDe(b) ? -1 : 1)).map((f) => ({ entry_date: jourDe(f), ...Object.fromEntries(COLONNES.map((c) => [c, f[c] === undefined || f[c] === null ? null : Number(f[c])])) }));
const PROPS = ['achat', 'oeufsTerre', 'naissainsNes', 'mortBorde', 'mortEngraissement', 'mortNaissain', 'donBorde', 'donEngraissement', 'donNaissain', 'mortEnregistre', 'donEnregistre', 'effectifNaissains', 'effectifEngraissement', 'effectifBordes', 'peseeTotal'];
const F = FAMILLES.escargots;

test('saisie escargots = vrai FicheEscargots : saisie rechargée, aperçu, refus, fiches écrites, cascade, effectif de la bande', (t) => {
    if (!retour) return t.skip(raison);
    const stats = { ok: 0, clos: 0, mortEnregistre: 0, donEnregistre: 0, gmq: 0, eclosion: 0, sansOeufs: 0, cascade: 0, mortAuDessus: 0 };
    scenarios.forEach((s, i) => {
        const p = retour[i];
        const ctx = `scénario ${i}`;
        const charge = chargerJour(s.lot, s.fiches, s.jour, F);
        assert.deepEqual(charge, chargerJourEscargots(s.lot, s.fiches, s.jour), `${ctx} répartition par la famille`);
        for (const k of PROPS) assert.equal(charge[k] ?? null, p.charge[k] ?? null, `${ctx} saisie rechargée ${k}`);
        const saisie = { ...charge, ...s.saisie };
        const c = calculsEscargots(s.lot, s.fiches, s.jour, saisie);
        const a = p.apercu;
        assert.equal(c.veille, a.veille, `${ctx} effectif de la veille`);
        assert.equal(c.vente, a.vente, `${ctx} vente du jour`);
        assert.equal(c.effectifFinal, a.effectifFinal, `${ctx} effectif final calculé`);
        assert.equal(c.taux, a.taux, `${ctx} taux de mortalité du jour`);
        assert.equal(c.eclosion, a.eclosion, `${ctx} taux d'éclosion`);
        assert.equal(c.poidsEstime, a.poidsEstime, `${ctx} poids moyen estimé (GMQ)`);
        if (c.poidsEstime !== null) stats.gmq++;
        if (c.eclosion !== null) stats.eclosion++; else stats.sansOeufs++;
        if (charge.mortEnregistre !== null && !['mortBorde', 'mortEngraissement', 'mortNaissain'].some((k) => k in s.saisie)) stats.mortEnregistre++;
        if (charge.donEnregistre !== null && !['donBorde', 'donEngraissement', 'donNaissain'].some((k) => k in s.saisie)) stats.donEnregistre++;
        const r = enregistrerJour(s.lot, s.fiches, s.jour, saisie, { exercices: s.exercices });
        if (r.refus !== null) {
            assert.deepEqual(p.toast, { message: r.refus, type: 'error' }, `${ctx} refus`);
            assert.deepEqual(normaliser(p.fiches), normaliser(s.fiches), `${ctx} refus : aucune écriture`);
            assert.equal(p.current_quantity, s.lot.current_quantity, `${ctx} refus : bande intacte`);
            assert.match(r.refus, /clôturé/);
            stats.clos++;
            return;
        }
        assert.deepEqual(p.toast, { message: MOTIFS.enregistre, type: 'success' }, `${ctx} succès`);
        assert.deepEqual(normaliser(r.fiches), normaliser(p.fiches), `${ctx} fiches écrites et effectif des jours suivants`);
        assert.equal(r.lot.current_quantity, p.current_quantity, `${ctx} effectif de la bande`);
        stats.ok++;
        if (c.effectifFinal === 0 && c.veille > 0) stats.mortAuDessus++;
        if (r.fiches.some((f) => jourDe(f) > s.jour)) stats.cascade++;
    });
    if (NB === 400) assert.ok(stats.ok > 250 && stats.clos > 15 && stats.mortEnregistre > 15 && stats.donEnregistre > 10 && stats.gmq > 25 && stats.eclosion > 100 && stats.sansOeufs > 20 && stats.cascade > 100 && stats.mortAuDessus > 3, `couverture insuffisante : ${JSON.stringify(stats)}`);
});

test('droit, bande absente et textes : ceux de FicheEscargots', () => {
    assert.match(enregistrerJour(null, [], '2026-11-09', {}, { famille: F }).refus, /Aucune bande active en héliciculture/);
    assert.equal(enregistrerJour(null, [], '2026-11-09', {}, { famille: F }).refus, MOTIFS_ESCARGOTS.aucuneBande);
    const lot = { id: 'l', species_code: 'helico', initial_quantity: 10, current_quantity: 10 };
    assert.equal(enregistrerJour(lot, [], '2026-11-09', {}, { role: 'caissier' }).refus, MOTIFS.droit, 'lecture seule sans manage-elevage');
    assert.equal(refusExerciceClos([{ year: 2026, start_date: '2026-01-01', end_date: '2026-12-31', status: 'cloture' }], '2026-11-09'), MOTIFS.exerciceClos(2026, '09/11/2026'));
    assert.equal(typeof enregistrerJourEscargots, 'function');
});
