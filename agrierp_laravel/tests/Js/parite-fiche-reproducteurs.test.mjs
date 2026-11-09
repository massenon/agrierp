import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { calculsVolailles, chargerJourVolailles, MOTIFS_VOLAILLES } from '../../resources/js/hors-ligne/fiche-volailles.js';
import { chargerJour, enregistrerJour, MOTIFS } from '../../resources/js/hors-ligne/fiche-lapins-saisie.js';
import { evaluerAutonomie, produitProvende } from '../../resources/js/hors-ligne/fiche-lapins-calculs.js';
import { FAMILLES } from '../../resources/js/hors-ligne/fiche-familles.js';
import { computeEffectifFinal, effectifVeille, jourDe } from '../../resources/js/hors-ligne/chaine-effectif.js';

/**
 * PWA-3 (fiche volailles REPRODUCTEURS) — PARITÉ EXÉCUTÉE de la saisie d'un jour contre le vrai `FicheReproducteurs` (ouverture du jour, aperçu, `saveDay`, SQLite en
 * mémoire) : saisie rechargée, effectif final, taux, éclosion, ventes par catégorie, catégories et départ, rationnement (`CategorieVolaille::tableauReproducteurs`),
 * autonomie, refus, fiches écrites (ventilation des morts, dons ET ventes, départ) et cascade. Sans `php` : sauté AVEC sa raison.
 */
const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
let graine = 20261120;
const alea = (n) => { graine = (graine * 1103515245 + 12345) % 2147483648; return Math.floor(graine / 65536) % n; };
const uuid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const deux = (n) => String(n).padStart(2, '0');
const jourDuMois = (d) => `2026-${d > 31 ? '11' : '10'}-${deux(d > 31 ? d - 31 : d)}`;
const F = FAMILLES.reproducteurs;

const NB = Number(process.env.SCENARIOS_LIMITE ?? 600);
let compteur = 0;
const scenarios = [];
for (let i = 0; i < NB; i++) {
    const initial = 20 + alea(200);
    const lot = { id: uuid(++compteur), code: `REP-${i}`, species_code: 'aviculture', stage: ['reproduction', 'croissance', 'engraissement'][alea(3)], initial_quantity: initial, current_quantity: initial, status: 'actif', is_active: true };
    const chaine = alea(2) === 0;
    const jours = [...new Set(Array.from({ length: alea(7) }, () => 25 + alea(16)))].sort((a, b) => a - b);
    const fiches = [];
    let courant = initial;
    jours.forEach((d, k) => {
        const mr = alea(3), ms = alea(3), mj = alea(3);
        const ventile = alea(7) !== 0;
        const vr = alea(3) === 0 ? alea(4) : 0, vs = alea(4) === 0 ? alea(3) : 0, vj = alea(3) === 0 ? alea(4) : 0;
        const f = { id: uuid(++compteur), lot_id: lot.id, entry_date: jourDuMois(d), achat: alea(6) === 0 ? alea(10) : 0, ne: alea(4) === 0 ? alea(40) : 0, ponte_total: alea(3) === 0 ? null : alea(120),
            mort: mr + ms + mj, vente: vr + vs + vj, don: 0, transfert_entree: alea(12) === 0 ? 1 + alea(4) : 0, transfert_sortie: alea(12) === 0 ? 1 + alea(3) : 0 };
        if (ventile) Object.assign(f, { mort_repro: mr, mort_sevre: ms, mort_jeune: mj, don_repro: 0, don_sevre: 0, don_jeune: 0, passage_sevre_jeune: alea(4) === 0 ? alea(4) : 0 });
        if (alea(8) !== 0) Object.assign(f, { vente_repro: vr, vente_sevre: vs, vente_jeune: vj });
        if (alea(3) === 0) f.weight_sample_avg_g = 300 + alea(2500);
        f.effectif_final = alea(12) === 0 ? alea(300) : computeEffectifFinal(courant, f.achat, f.ne, f.mort, f.vente, f.don, f.transfert_entree, f.transfert_sortie);
        courant = f.effectif_final;
        if (chaine && k === 0) { const r = Math.floor(initial / 3); Object.assign(f, { cat_depart_repro: r, cat_depart_jeune: r, cat_depart_sevre: alea(9) === 0 ? initial - 2 * r + 1 : initial - 2 * r }); }
        fiches.push(f);
    });
    if (fiches.length > 0) lot.current_quantity = courant;
    const jour = fiches.length > 0 && alea(3) !== 0 ? jourDe(fiches[alea(fiches.length)]) : jourDuMois(25 + alea(16));
    const exercices = [{ id: 1, year: 2026, start_date: '2026-01-01', end_date: '2026-12-31', status: alea(10) === 0 ? 'cloture' : 'ouvert' }];
    const surcharges = {};
    const mettre = (p, v) => { if (alea(2) === 0) surcharges[p] = v; };
    mettre('achat', alea(8)); mettre('oeufsCouves', alea(4) === 0 ? 0 : alea(150)); mettre('poussinsNes', alea(60));
    if (alea(2) === 0) { mettre('mortRepro', alea(3)); mettre('mortPoulet', alea(alea(8) === 0 ? 250 : 5)); mettre('mortPoussin', alea(4)); }
    if (alea(3) === 0) { mettre('donRepro', alea(3)); mettre('donPoulet', alea(3)); mettre('donPoussin', alea(3)); }
    mettre('passage', alea(6) === 0 ? 40 + alea(40) : alea(5));
    if (alea(3) === 0) mettre('peseeTotal', alea(3) === 0 ? null : 500 + alea(6000));
    if (alea(3) === 0) { mettre('departRepro', alea(4) === 0 ? null : alea(80)); mettre('departSevre', alea(4) === 0 ? null : alea(80)); mettre('departJeune', alea(4) === 0 ? null : alea(80)); }
    // Sans chaîne, un départ COHÉRENT (somme = effectif au début du jour) dans la plupart des scénarios : sinon presque tout est refusé.
    if (!('departRepro' in surcharges) && alea(5) !== 0) {
        const veille = effectifVeille(lot, fiches.filter((f) => f.lot_id === lot.id), jour);
        const r = Math.floor(veille / 3);
        Object.assign(surcharges, { departRepro: r, departJeune: r, departSevre: veille - 2 * r + (alea(12) === 0 ? 1 : 0) });
    }
    const provende = {
        produit: alea(4) === 0 ? null : { id: uuid(++compteur), name: ['Provende pondeuse', 'Aliment volaille', 'Sac de provende'][alea(3)], unit: alea(2) === 0 ? 'sac' : 'kg', stock_qty: alea(5) === 0 ? 0 : alea(500) },
        feed_types: Array.from({ length: alea(3) }, () => ({ id: uuid(++compteur), standard_bag_weight_kg: [25, 20, 50][alea(3)] })),
        releve: alea(3) === 0 ? null : { id: uuid(++compteur), status: alea(2) === 0 ? 'valide' : 'a_valider', data: { mode: alea(2) === 0 ? 'manuel' : 'constate', critique_jours: 1 + alea(8) } },
    };
    scenarios.push({ famille: 'reproducteurs', aujourdhui: '2026-11-09', lot, provende, fiches, exercices, jour, saisie: surcharges,
        rations: Array.from({ length: alea(5) }, () => ({ stage_label: ['Reproducteur', 'Jeune', 'Poussin', 'poussin ', 'JEUNE', 'Poussin ponte (0 à 2 mois)', 'Pondeuse (6 à 18 mois)', 'Jeune porc'][alea(8)], ration_g_per_day: 20 + alea(200) })) });
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

const COLONNES = ['achat', 'ne', 'mort', 'vente', 'don', 'effectif_final', 'ponte_total', 'feed_qty_kg', 'mort_repro', 'mort_sevre', 'mort_jeune', 'don_repro', 'don_sevre', 'don_jeune', 'vente_repro', 'vente_sevre', 'vente_jeune',
    'passage_sevre_jeune', 'weight_sample_avg_g', 'cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune', 'cat_eff_repro', 'cat_eff_sevre', 'cat_eff_jeune'];
const normaliser = (fiches) => [...fiches].sort((a, b) => (jourDe(a) < jourDe(b) ? -1 : 1)).map((f) => ({ entry_date: jourDe(f), ...Object.fromEntries(COLONNES.map((c) => [c, f[c] === undefined || f[c] === null ? null : Number(f[c])])) }));
const PROPS = ['achat', 'oeufsCouves', 'poussinsNes', 'mortRepro', 'mortPoulet', 'mortPoussin', 'donRepro', 'donPoulet', 'donPoussin', 'passage', 'departRepro', 'departSevre', 'departJeune', 'mortEnregistre', 'donEnregistre', 'peseeTotal'];

test('saisie reproducteurs = vrai FicheReproducteurs : saisie rechargée, aperçu, ration, autonomie, refus, fiches écrites, cascade', (t) => {
    if (!retour) return t.skip(raison);
    const stats = { ok: 0, clos: 0, avantDepart: 0, departManquant: 0, departRefuse: 0, passage: 0, ancienne: 0, nonVentilee: 0, proposition: 0, ration: 0, autonomie: 0, alerte: 0, gmq: 0, eclosion: 0, avertissement: 0, depart: 0 };
    scenarios.forEach((s, i) => {
        const p = retour[i];
        const ctx = `scénario ${i}`;
        const charge = chargerJour(s.lot, s.fiches, s.jour, F);
        assert.deepEqual(charge, chargerJourVolailles(s.lot, s.fiches, s.jour));
        for (const k of PROPS) assert.equal(charge[k] ?? null, p.charge[k] ?? null, `${ctx} saisie rechargée ${k}`);
        const saisie = { ...charge, ...s.saisie };
        const produits = s.provende.produit ? [{ ...s.provende.produit, species_id: 'ESP' }] : [];
        const releves = s.provende.releve ? [{ id: s.provende.releve.id, type: 'delai_regle', status: s.provende.releve.status, is_active: true, data: s.provende.releve.data }] : [];
        const c = calculsVolailles(s.lot, s.fiches, s.jour, saisie, s.rations, (kg) => evaluerAutonomie(produitProvende(produits, ['ESP']), kg, s.provende.feed_types, releves, []));
        const a = p.apercu;
        assert.equal(c.veille, a.veille, `${ctx} effectif de la veille`);
        assert.equal(c.vente, a.vente, `${ctx} vente du jour`);
        assert.deepEqual(c.ventes, a.ventes, `${ctx} ventes par catégorie`);
        assert.equal(c.effectifFinal, a.effectifFinal, `${ctx} effectif final`);
        assert.equal(c.taux, a.taux, `${ctx} taux de mortalité`);
        assert.equal(c.eclosion, a.eclosion, `${ctx} taux d'éclosion`);
        assert.equal(c.avertissementMorts, a.avertissementMorts, `${ctx} avertissement des morts`);
        assert.equal(c.poidsEstime, a.poidsEstime, `${ctx} poids estimé`);
        assert.deepEqual(c.ration, a.ration, `${ctx} rationnement`);
        for (const k of ['mode', 'repro', 'sevre', 'jeune', 'motif', 'refus_passage', 'depart_requis', 'depart_date']) assert.equal(c.cat[k] ?? null, a.cat[k] ?? null, `${ctx} catégories : ${k}`);
        assert.deepEqual(c.cat.avertissements, a.cat.avertissements, `${ctx} avertissements`);
        assert.deepEqual(c.cat.proposition === null ? null : { repro: c.cat.proposition.repro, sevre: c.cat.proposition.sevre, jeune: c.cat.proposition.jeune }, a.cat.proposition ?? null, `${ctx} proposition de départ`);
        assert.equal(c.autonomie.available, a.autonomie.available, `${ctx} autonomie : disponible`);
        if (c.autonomie.available) {
            assert.equal(c.autonomie.product.id, a.autonomie.product);
            for (const k of ['stock_kg', 'autonomie_jours', 'critique', 'rupture']) assert.equal(c.autonomie[k], a.autonomie[k], `${ctx} autonomie : ${k}`);
            assert.equal(Boolean(c.autonomie.inconnu), a.autonomie.inconnu);
            stats.autonomie++; if (c.autonomie.critique) stats.alerte++;
        }
        if (c.cat.proposition) stats.proposition++;
        if (c.ration.total_g !== null) stats.ration++;
        if (c.poidsEstime !== null) stats.gmq++;
        if (c.eclosion !== null) stats.eclosion++;
        if (c.cat.avertissements.length) stats.avertissement++;
        const r = enregistrerJour(s.lot, s.fiches, s.jour, saisie, { exercices: s.exercices, rations: s.rations });
        if (r.refus !== null) {
            assert.deepEqual(p.toast, { message: r.refus, type: 'error' }, `${ctx} refus`);
            assert.deepEqual(normaliser(p.fiches), normaliser(s.fiches), `${ctx} refus : aucune écriture`);
            assert.equal(p.current_quantity, s.lot.current_quantity, `${ctx} refus : bande intacte`);
            if (/clôturé/.test(r.refus)) stats.clos++;
            else if (/antérieur/.test(r.refus)) stats.avantDepart++;
            else if (r.refus === MOTIFS_VOLAILLES.departManquant) stats.departManquant++;
            else if (/Passage/.test(r.refus)) stats.passage++;
            else if (r.refus === MOTIFS_VOLAILLES.ancienneFiche) stats.ancienne++;
            else if (r.refus === MOTIFS_VOLAILLES.ventesNonVentilees) stats.nonVentilee++;
            else stats.departRefuse++;
            return;
        }
        assert.deepEqual(p.toast, { message: MOTIFS.enregistre, type: 'success' }, `${ctx} succès`);
        assert.deepEqual(normaliser(r.fiches), normaliser(p.fiches), `${ctx} fiches écrites et chaîne recalculée`);
        assert.equal(r.lot.current_quantity, p.current_quantity, `${ctx} effectif de la bande`);
        stats.ok++;
        if (r.fiche.cat_depart_repro !== undefined && s.fiches.every((f) => f.id !== r.fiche.id || f.cat_depart_repro === undefined)) stats.depart++;
    });
    if (NB === 600) assert.ok(stats.ok > 140 && stats.clos > 10 && stats.avantDepart > 3 && stats.departManquant > 10 && stats.departRefuse > 10 && stats.passage > 3 && stats.ancienne > 3 && stats.nonVentilee > 3 && stats.proposition > 100 && stats.ration > 100 && stats.autonomie > 150 && stats.alerte > 15 && stats.gmq > 20 && stats.eclosion > 100 && stats.depart > 30, `couverture insuffisante : ${JSON.stringify(stats)}`);
});
