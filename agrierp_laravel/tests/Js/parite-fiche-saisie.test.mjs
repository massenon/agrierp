import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { calculsSaisie, chargerJour, enregistrerJour, MOTIFS } from '../../resources/js/hors-ligne/fiche-lapins-saisie.js';
import { computeEffectifFinal, jourDe } from '../../resources/js/hors-ligne/chaine-effectif.js';

/**
 * PWA-3 (fiche lapins, É3) — PARITÉ EXÉCUTÉE de la SAISIE d'un jour contre le vrai `FicheLapins` (ouverture du jour + `saveDay`, SQLite en
 * mémoire) : saisie rechargée, refus (même phrase), fiches écrites et chaîne recalculée des jours suivants, effectif de la bande.
 * Sans `php` : sauté AVEC sa raison.
 */
const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
let graine = 20261113;
const alea = (n) => { graine = (graine * 1103515245 + 12345) % 2147483648; return Math.floor(graine / 65536) % n; };
const uuid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const deux = (n) => String(n).padStart(2, '0');
const jourDuMois = (d) => `2026-${d > 31 ? '11' : '10'}-${deux(d > 31 ? d - 31 : d)}`; // 25 oct. … 9 nov.

let compteur = 0;
const scenarios = [];
const STADES = ['reproduction', 'croissance', 'engraissement', 'autre'];
const NB = Number(process.env.SCENARIOS_LIMITE ?? 420); // une valeur réduite sert aux contrôles par mutation seulement
for (let i = 0; i < NB; i++) {
    const initial = 20 + alea(200);
    const lot = { id: uuid(++compteur), code: `LAP-${i}`, species_code: 'cuniculture', stage: STADES[alea(4)], initial_quantity: initial, current_quantity: initial, status: 'actif', is_active: true };
    const chaine = alea(2) === 0;
    const nb = alea(7);
    const jours = [...new Set(Array.from({ length: nb }, () => 25 + alea(16)))].sort((a, b) => a - b);
    const fiches = [];
    let courant = initial;
    jours.forEach((d, k) => {
        const f = {
            id: uuid(++compteur), lot_id: lot.id, entry_date: jourDuMois(d),
            achat: alea(5) === 0 ? alea(6) : 0, ne: alea(4) === 0 ? alea(10) : 0, mort: 0, vente: alea(8) === 0 ? alea(4) : 0, don: 0,
            effectif_m: alea(10), effectif_f: alea(30), effectif_sevres: alea(40), effectif_smeres: alea(40),
            transfert_entree: 0, transfert_sortie: 0,
        };
        const ventile = alea(6) !== 0;
        const mr = alea(3), ms = alea(3), mj = alea(3), dr = alea(2), dsv = alea(2), dj = alea(2);
        f.mort = mr + ms + mj; f.don = dr + dsv + dj;
        if (ventile) Object.assign(f, { mort_repro: mr, mort_sevre: ms, mort_jeune: mj, don_repro: dr, don_sevre: dsv, don_jeune: dj, passage_sevre_jeune: alea(3) === 0 ? alea(4) : 0 });
        if (alea(10) === 0) Object.assign(f, { transfert_entree: 1 + alea(4), transfert_entree_repro: 0, transfert_entree_sevre: 0, transfert_entree_jeune: 0 });
        if (alea(10) === 0) Object.assign(f, { transfert_sortie: 1 + alea(3), transfert_sortie_repro: 0, transfert_sortie_sevre: 0, transfert_sortie_jeune: 0 });
        if (alea(3) === 0) f.weight_sample_avg_g = 500 + alea(3000);
        f.effectif_final = alea(12) === 0 ? alea(300) : computeEffectifFinal(courant, f.achat, f.ne, f.mort, f.vente, f.don, f.transfert_entree, f.transfert_sortie);
        courant = f.effectif_final;
        if (chaine && k === 0) {
            const r = Math.floor(initial / 3); const j = Math.floor(initial / 3);
            Object.assign(f, { cat_depart_repro: r, cat_depart_jeune: j, cat_depart_sevre: alea(9) === 0 ? initial - r - j + 1 : initial - r - j });
        }
        fiches.push(f);
    });
    if (fiches.length > 0) lot.current_quantity = courant;
    const jour = jourDuMois(25 + alea(16));
    const exercices = [{ id: 1, year: 2026, start_date: '2026-01-01', end_date: '2026-12-31', status: alea(14) === 0 ? 'cloture' : 'ouvert' }];
    const surcharges = {};
    const mettre = (p, v) => { if (alea(2) === 0) surcharges[p] = v; };
    mettre('achat', alea(4)); mettre('ne', alea(12));
    mettre('mortRepro', alea(4)); mettre('mortChair', alea(8) === 0 ? 150 + alea(100) : alea(6)); mettre('mortLapereau', alea(4));
    mettre('donRepro', alea(3)); mettre('donChair', alea(3)); mettre('donLapereau', alea(3));
    mettre('passage', alea(6) === 0 ? 40 + alea(40) : alea(5));
    mettre('effectifM', alea(10)); mettre('effectifF', alea(30)); mettre('effectifSevres', alea(40)); mettre('effectifSmeres', alea(40));
    if (alea(3) === 0) mettre('peseeTotal', alea(3) === 0 ? null : 500 + alea(9000));
    if (alea(3) === 0) { mettre('departRepro', alea(4) === 0 ? null : alea(80)); mettre('departSevre', alea(4) === 0 ? null : alea(80)); mettre('departJeune', alea(4) === 0 ? null : alea(80)); }
    scenarios.push({
        aujourdhui: '2026-11-09', lot, fiches, exercices, jour, saisie: surcharges,
        rations: Array.from({ length: alea(4) }, () => ({ stage_label: ['Reproducteur', 'Jeune', 'Sous-mères', 'Lapin de Chair'][alea(4)], ration_g_per_day: 20 + alea(200) })),
    });
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

const COLONNES = ['achat', 'ne', 'mort', 'vente', 'don', 'effectif_final', 'effectif_m', 'effectif_f', 'effectif_sevres', 'effectif_smeres', 'feed_qty_kg',
    'mort_repro', 'mort_sevre', 'mort_jeune', 'don_repro', 'don_sevre', 'don_jeune', 'passage_sevre_jeune', 'weight_sample_avg_g',
    'cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune', 'cat_eff_repro', 'cat_eff_sevre', 'cat_eff_jeune'];
const normaliser = (fiches) => [...fiches].sort((a, b) => (jourDe(a) < jourDe(b) ? -1 : 1)).map((f) => ({ entry_date: jourDe(f), ...Object.fromEntries(COLONNES.map((c) => [c, f[c] === undefined || f[c] === null ? null : Number(f[c])])) }));
const PROPS = ['achat', 'ne', 'mortRepro', 'mortChair', 'mortLapereau', 'donRepro', 'donChair', 'donLapereau', 'passage', 'effectifM', 'effectifF', 'effectifSevres', 'effectifSmeres', 'departRepro', 'departSevre', 'departJeune', 'peseeTotal', 'mortAncienTotal', 'donAncienTotal'];

test('saisie = vrai saveDay : saisie rechargée, refus, fiches écrites, chaîne et effectif de la bande', (t) => {
    if (!retour) return t.skip(raison);
    const stats = { ok: 0, clos: 0, passage: 0, depart: 0, ancienne: 0, cascade: 0, morts: 0, somme: 0, gmq: 0 };
    scenarios.forEach((s, i) => {
        const p = retour[i];
        const ctx = `scénario ${i}`;
        const charge = chargerJour(s.lot, s.fiches, s.jour);
        for (const k of PROPS) assert.equal(charge[k] ?? null, p.charge[k] ?? null, `${ctx} saisie rechargée ${k}`);
        const saisie = { ...charge, ...s.saisie };
        const c = calculsSaisie(s.lot, s.fiches, s.jour, saisie, s.rations);
        const a = p.apercu;
        assert.equal(c.veille, a.veille, `${ctx} effectif de la veille`);
        assert.equal(c.effectifFinal, a.effectifFinal, `${ctx} effectif final calculé`);
        assert.equal(c.taux, a.taux, `${ctx} taux de mortalité du jour`);
        assert.equal(c.avertissementMorts, a.avertissementMorts, `${ctx} avertissement des morts`);
        assert.equal(c.poidsEstime, a.poidsEstime, `${ctx} poids moyen estimé (GMQ)`);
        assert.equal(c.provende.total_kg, a.provende_kg, `${ctx} provende du jour`);
        for (const k of ['mode', 'repro', 'sevre', 'jeune', 'motif', 'refus_passage', 'depart_requis', 'depart_date']) assert.equal(c.cat[k] ?? null, a.cat[k] ?? null, `${ctx} catégories : ${k}`);
        assert.deepEqual(c.cat.avertissements, a.cat.avertissements, `${ctx} avertissements des catégories`);
        if (c.avertissementMorts) stats.morts++;
        if (c.cat.avertissements.length) stats.somme++;
        if (c.poidsEstime !== null) stats.gmq++;
        const r = enregistrerJour(s.lot, s.fiches, s.jour, saisie, { exercices: s.exercices, rations: s.rations });
        if (r.refus !== null) {
            assert.deepEqual(p.toast, { message: r.refus, type: 'error' }, `${ctx} refus`);
            assert.deepEqual(normaliser(p.fiches), normaliser(s.fiches), `${ctx} refus : aucune écriture`);
            assert.equal(p.current_quantity, s.lot.current_quantity, `${ctx} refus : bande intacte`);
            if (/clôturé/.test(r.refus)) stats.clos++; else if (/Passage/.test(r.refus)) stats.passage++; else if (r.refus === MOTIFS.ancienneFiche) stats.ancienne++; else stats.depart++;
            return;
        }
        assert.deepEqual(p.toast, { message: MOTIFS.enregistre, type: 'success' }, `${ctx} succès`);
        assert.deepEqual(normaliser(r.fiches), normaliser(p.fiches), `${ctx} fiches écrites et chaîne recalculée`);
        assert.equal(r.lot.current_quantity, p.current_quantity, `${ctx} effectif de la bande`);
        stats.ok++;
        if (normaliser(r.fiches).some((f, k) => f.effectif_final !== normaliser(s.fiches.concat([r.fiche]).filter((x, idx, arr) => arr.findIndex((y) => jourDe(y) === jourDe(x)) === idx))[k]?.effectif_final)) stats.cascade++;
    });
    if (NB === 420) assert.ok(stats.ok > 120 && stats.clos > 5 && stats.passage > 5 && stats.depart > 5 && stats.ancienne > 3 && stats.morts > 5 && stats.somme > 5 && stats.gmq > 20, `couverture insuffisante : ${JSON.stringify(stats)}`);
});
