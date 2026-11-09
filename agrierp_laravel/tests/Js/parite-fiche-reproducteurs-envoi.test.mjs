import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { chargerJour, enregistrerJour, ficheEnJson, MOTIFS } from '../../resources/js/hors-ligne/fiche-lapins-saisie.js';
import { FAMILLES } from '../../resources/js/hors-ligne/fiche-familles.js';
import { computeEffectifFinal, jourDe } from '../../resources/js/hors-ligne/chaine-effectif.js';

/**
 * PWA-3 (fiche volailles reproducteurs) — L'ENVOI d'une fiche d'escargots (colonne `ponte_total` comprise, aucune colonne de répartition) joué sur le VRAI
 * `POST /api/sync/push` : effectif du serveur = effectif du navigateur, second envoi sans effet, exercice clos refusé avec la phrase du web, doublon jamais
 * dupliqué. Sans `php` : sauté AVEC sa raison.
 */
const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
let graine = 20261119;
const alea = (n) => { graine = (graine * 1103515245 + 12345) % 2147483648; return Math.floor(graine / 65536) % n; };
const uuid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const deux = (n) => String(n).padStart(2, '0');
const jourDuMois = (d) => `2026-${d > 31 ? '11' : '10'}-${deux(d > 31 ? d - 31 : d)}`;
const F = FAMILLES.reproducteurs;

const NB = Number(process.env.SCENARIOS_LIMITE ?? 400);
let compteur = 0;
const scenarios = [];
for (let i = 0; i < NB * 3 && scenarios.length < NB; i++) {
    const initial = 50 + alea(400);
    const lot = { id: uuid(++compteur), code: `ESC-${i}`, species_code: 'aviculture', stage: ['reproduction', 'croissance', 'engraissement'][alea(3)], initial_quantity: initial, current_quantity: initial, status: 'actif', is_active: true };
    const jours = [...new Set(Array.from({ length: alea(6) }, () => 25 + alea(16)))].sort((a, b) => a - b);
    const fiches = [];
    let courant = initial;
    for (const d of jours) {
        const mr = alea(3), ms = alea(3), mj = alea(3), vr = alea(6) === 0 ? alea(3) : 0, vj = alea(6) === 0 ? alea(3) : 0;
        const f = { id: uuid(++compteur), lot_id: lot.id, entry_date: jourDuMois(d), achat: alea(5) === 0 ? alea(20) : 0, ne: alea(3) === 0 ? alea(40) : 0, mort: mr + ms + mj, vente: vr + vj, don: 0, ponte_total: alea(3) === 0 ? null : alea(120),
            mort_repro: mr, mort_sevre: ms, mort_jeune: mj, don_repro: 0, don_sevre: 0, don_jeune: 0, vente_repro: vr, vente_sevre: 0, vente_jeune: vj, passage_sevre_jeune: 0, transfert_entree: 0, transfert_sortie: 0 };
        if (alea(3) === 0) f.weight_sample_avg_g = 5 + alea(60);
        f.effectif_final = computeEffectifFinal(courant, f.achat, f.ne, f.mort, f.vente, f.don, 0, 0);
        courant = f.effectif_final;
        if (fiches.length === 0 && alea(2) === 0) { const r = Math.floor(initial / 3); Object.assign(f, { cat_depart_repro: r, cat_depart_jeune: r, cat_depart_sevre: initial - 2 * r }); }
        fiches.push(f);
    }
    if (fiches.length > 0) lot.current_quantity = courant;
    const jour = fiches.length > 0 && alea(2) === 0 ? jourDe(fiches[alea(fiches.length)]) : jourDuMois(25 + alea(16));
    const s = chargerJour(lot, fiches, jour, F);
    for (const [p, v] of [['achat', alea(8)], ['oeufsCouves', alea(150)], ['poussinsNes', alea(60)], ['mortRepro', alea(3)], ['mortPoussin', alea(4)], ['donPoulet', alea(3)], ['passage', alea(4)]]) if (alea(2) === 0) s[p] = v;
    if (alea(2) === 0) { const r = Math.floor(lot.initial_quantity / 3); Object.assign(s, { departRepro: r, departJeune: r, departSevre: lot.initial_quantity - 2 * r }); }
    if (alea(3) === 0) s.peseeTotal = 100 + alea(5000);
    const r = enregistrerJour(lot, fiches, jour, s, { exercices: [] });
    if (r.refus !== null) continue;
    const type = ['normal', 'normal', 'normal', 'clos', 'doublon'][alea(5)];
    const exercices = [{ id: 1, year: 2026, start_date: '2026-01-01', end_date: '2026-12-31', status: type === 'clos' ? 'cloture' : 'ouvert' }];
    const item = { id_fiche: r.fiche.id, fiche: r.fiche, cree_le: '2026-11-09T10:00:00.000Z' };
    let serveur = fiches;
    if (type === 'doublon') {
        if (fiches.some((f) => jourDe(f) === jour)) continue;
        serveur = [...fiches, { id: uuid(++compteur), lot_id: lot.id, entry_date: jour, achat: 0, ne: 0, mort: 0, vente: 0, don: 0, effectif_final: courant }];
    }
    scenarios.push({ espece: 'aviculture', aujourdhui: '2026-11-09', lot, fiches: serveur, exercices, type, jour, envois: type === 'normal' ? 2 : 1, charge: [ficheEnJson(item, 'pwa-test')], local: r, item });
}

let retour = null;
let raison = null;
test('préparation : le PHP répond', (t) => {
    try {
        retour = JSON.parse(execFileSync('php', [path.join(racine, 'tests/Js/parite/executer-fiche-envoi.php')], { input: JSON.stringify({ scenarios: scenarios.map(({ local, item, ...s }) => s) }), cwd: racine, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 }));
    } catch (e) {
        if (e.code !== 'ENOENT') throw e;
        raison = 'PHP absent de cette machine (parité non exécutée)';
        t.skip(raison);
    }
});

const COLONNES = ['achat', 'ne', 'mort', 'vente', 'don', 'effectif_final', 'ponte_total', 'vente_repro', 'vente_sevre', 'vente_jeune', 'cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune', 'feed_qty_kg', 'mort_repro', 'mort_sevre', 'mort_jeune', 'don_repro', 'don_sevre', 'don_jeune', 'passage_sevre_jeune', 'weight_sample_avg_g'];
const normaliser = (fiches) => [...fiches].sort((a, b) => (jourDe(a) < jourDe(b) ? -1 : 1)).map((f) => ({ entry_date: jourDe(f), ...Object.fromEntries(COLONNES.map((c) => [c, f[c] === undefined || f[c] === null ? null : Number(f[c])])) }));

test('envoi escargots = vrai pushDailyEntries', (t) => {
    if (!retour) return t.skip(raison);
    const stats = { normal: 0, clos: 0, doublon: 0, ponte: 0 };
    scenarios.forEach((s, i) => {
        const ctx = `scénario ${i} (${s.type})`;
        const envois = retour[i];
        const premier = envois[0];
        assert.equal(premier.statut, 200, `${ctx} statut`);
        const id = s.item.id_fiche;
        if (s.type === 'clos') {
            assert.deepEqual(premier.reponse.accepted, [], `${ctx} rien d'accepté`);
            assert.equal(premier.reponse.rejected[0].reason, MOTIFS.exerciceClos(2026, `${s.jour.slice(8)}/${s.jour.slice(5, 7)}/${s.jour.slice(0, 4)}`), `${ctx} phrase du web`);
            assert.deepEqual(normaliser(premier.fiches), normaliser(s.fiches), `${ctx} aucune écriture`);
            stats.clos++;
            return;
        }
        if (s.type === 'doublon') {
            assert.equal(premier.fiches.filter((f) => f.entry_date === s.jour).length, 1, `${ctx} jamais deux fiches pour un même jour`);
            const motif = premier.reponse.rejected[0]?.reason;
            assert.ok(premier.reponse.accepted.includes(id) || (typeof motif === 'string' && motif.length > 10), `${ctx} fusion ou refus motivé`);
            stats.doublon++;
            return;
        }
        assert.deepEqual(premier.reponse.accepted, [id], `${ctx} accepté`);
        assert.deepEqual(premier.reponse.rejected, [], `${ctx} aucun refus`);
        assert.deepEqual(normaliser(premier.fiches), normaliser(s.local.fiches), `${ctx} fiches du serveur = fiches du navigateur (ponte_total, ventilation et départ compris)`);
        assert.equal(premier.current_quantity, s.local.lot.current_quantity, `${ctx} effectif de la bande`);
        assert.deepEqual(envois[1].reponse.accepted, [id], `${ctx} second envoi accusé`);
        assert.deepEqual(normaliser(envois[1].fiches), normaliser(premier.fiches), `${ctx} second envoi : rien écrit ni dupliqué`);
        stats.normal++;
        if (s.item.fiche.ponte_total > 0) stats.ponte++;
    });
    if (NB === 400) assert.ok(stats.normal > 100 && stats.clos > 10 && stats.doublon > 10 && stats.ponte > 40, `couverture insuffisante : ${JSON.stringify(stats)}`);
});

test('charge utile : ponte_total, ventilation des morts / dons, ventes par catégorie à 0, départ envoyé', () => {
    const f = { id: uuid(1), lot_id: uuid(2), entry_date: '2026-11-08', achat: 0, ne: 5, mort: 2, vente: 3, don: 1, effectif_final: 50, ponte_total: 40, mort_repro: 1, mort_sevre: 1, mort_jeune: 0, don_repro: 1, don_sevre: 0, don_jeune: 0, vente_repro: 1, vente_sevre: 1, vente_jeune: 1, passage_sevre_jeune: 2, cat_depart_repro: 10, cat_depart_sevre: 20, cat_depart_jeune: 20, feed_qty_kg: null, weight_sample_avg_g: 20 };
    const j = ficheEnJson({ fiche: f, cree_le: 'x' }, 'p');
    assert.equal(j.ponte_total, 40);
    assert.equal(j.vente, 0);
    assert.deepEqual([j.vente_repro, j.vente_sevre, j.vente_jeune], [0, 0, 0]);
    assert.equal(j.mort, 2);
    assert.equal(j.cat_depart_sevre, 20);
    assert.equal(j.effectif_final, undefined);
});
