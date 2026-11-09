import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { chargerJour, enregistrerJour, ficheEnJson, MOTIFS } from '../../resources/js/hors-ligne/fiche-lapins-saisie.js';
import { FAMILLES } from '../../resources/js/hors-ligne/fiche-familles.js';
import { computeEffectifFinal, jourDe } from '../../resources/js/hors-ligne/chaine-effectif.js';

/**
 * PWA-3 (fiche volailles PONDEUSES) — L'ENVOI d'une fiche de pondeuses (quatre stades, trois passages, œufs récoltés et cassés) joué sur le VRAI
 * `POST /api/sync/push` : effectif du serveur = effectif du navigateur, second envoi sans effet, exercice clos refusé avec la phrase du web, doublon jamais
 * dupliqué. Sans `php` : sauté AVEC sa raison.
 */
const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
let graine = 20261122;
const alea = (n) => { graine = (graine * 1103515245 + 12345) % 2147483648; return Math.floor(graine / 65536) % n; };
const uuid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const deux = (n) => String(n).padStart(2, '0');
const jourDuMois = (d) => `2026-${d > 31 ? '11' : '10'}-${deux(d > 31 ? d - 31 : d)}`;
const F = FAMILLES.pondeuses;

const NB = Number(process.env.SCENARIOS_LIMITE ?? 400);
let compteur = 0;
const scenarios = [];
for (let i = 0; i < NB * 3 && scenarios.length < NB; i++) {
    const initial = 50 + alea(400);
    const lot = { id: uuid(++compteur), code: `PON-${i}`, species_code: 'aviculture', stage: 'ponte', initial_quantity: initial, current_quantity: initial, status: 'actif', is_active: true };
    const jours = [...new Set(Array.from({ length: alea(6) }, () => 25 + alea(16)))].sort((a, b) => a - b);
    const fiches = [];
    let courant = initial;
    for (const d of jours) {
        const m = [alea(3), alea(3), alea(3), alea(3)], v = [alea(6) === 0 ? alea(3) : 0, 0, alea(6) === 0 ? alea(3) : 0, alea(6) === 0 ? alea(3) : 0];
        const f = { id: uuid(++compteur), lot_id: lot.id, entry_date: jourDuMois(d), achat: alea(5) === 0 ? alea(20) : 0, ne: alea(3) === 0 ? alea(40) : 0, mort: m[0] + m[1] + m[2] + m[3], vente: v[0] + v[1] + v[2] + v[3], don: 0, ponte_total: alea(3) === 0 ? null : alea(120), ponte_casses: alea(3) === 0 ? null : alea(15),
            mort_repro: m[0], mort_sevre: m[1], mort_jeune: m[2], mort_4: m[3], don_repro: 0, don_sevre: 0, don_jeune: 0, don_4: 0, vente_repro: v[0], vente_sevre: v[1], vente_jeune: v[2], vente_4: v[3],
            passage_4_sevre: 0, passage_sevre_jeune: 0, passage_jeune_repro: 0, transfert_entree: 0, transfert_sortie: 0 };
        if (alea(3) === 0) f.weight_sample_avg_g = 5 + alea(60);
        f.effectif_final = computeEffectifFinal(courant, f.achat, f.ne, f.mort, f.vente, f.don, 0, 0);
        courant = f.effectif_final;
        if (fiches.length === 0 && alea(2) === 0) { const r = Math.floor(initial / 4); Object.assign(f, { cat_depart_repro: r, cat_depart_jeune: r, cat_depart_4: r, cat_depart_sevre: initial - 3 * r }); }
        fiches.push(f);
    }
    if (fiches.length > 0) lot.current_quantity = courant;
    const jour = fiches.length > 0 && alea(2) === 0 ? jourDe(fiches[alea(fiches.length)]) : jourDuMois(25 + alea(16));
    const s = chargerJour(lot, fiches, jour, F);
    for (const [p, v] of [['achat', alea(8)], ['ne', alea(40)], ['oeufsRecoltes', alea(150)], ['oeufsCasses', alea(15)], ['mortRepro', alea(3)], ['mortSevre', alea(4)], ['mortQuatre', alea(3)], ['donJeune', alea(3)], ['donQuatre', alea(2)], ['passage1', alea(4)], ['passage2', alea(4)], ['passage3', alea(4)]]) if (alea(2) === 0) s[p] = v;
    if (alea(2) === 0) { const r = Math.floor(lot.initial_quantity / 4); Object.assign(s, { departRepro: r, departJeune: r, departQuatre: r, departSevre: lot.initial_quantity - 3 * r }); }
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
        // `PARITE_CACHE=<dossier>` : la réponse du PHP est gardée par empreinte de l'ENTRÉE (outil des contrôles par mutation : le PHP ne change pas quand on mute le JavaScript).
        const entree = JSON.stringify({ scenarios: scenarios.map(({ local, item, ...s }) => s) });
        const cache = process.env.PARITE_CACHE ? path.join(process.env.PARITE_CACHE, `${path.basename(import.meta.url)}-${createHash('sha256').update(entree).digest('hex').slice(0, 16)}.json`) : null;
        if (cache && existsSync(cache)) retour = JSON.parse(readFileSync(cache, 'utf8'));
        else {
            const brut = execFileSync('php', [path.join(racine, 'tests/Js/parite/executer-fiche-envoi.php')], { input: entree, cwd: racine, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
            if (cache) writeFileSync(cache, brut);
            retour = JSON.parse(brut);
        }
    } catch (e) {
        if (e.code !== 'ENOENT') throw e;
        raison = 'PHP absent de cette machine (parité non exécutée)';
        t.skip(raison);
    }
});

const COLONNES = ['achat', 'ne', 'mort', 'vente', 'don', 'effectif_final', 'ponte_total', 'ponte_casses', 'vente_repro', 'vente_sevre', 'vente_jeune', 'vente_4', 'cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune', 'cat_depart_4', 'feed_qty_kg', 'mort_repro', 'mort_sevre', 'mort_jeune', 'mort_4', 'don_repro', 'don_sevre', 'don_jeune', 'don_4', 'passage_4_sevre', 'passage_sevre_jeune', 'passage_jeune_repro', 'weight_sample_avg_g', 'cat_eff_repro', 'cat_eff_sevre', 'cat_eff_jeune', 'cat_eff_4'];
const normaliser = (fiches) => [...fiches].sort((a, b) => (jourDe(a) < jourDe(b) ? -1 : 1)).map((f) => ({ entry_date: jourDe(f), ...Object.fromEntries(COLONNES.map((c) => [c, f[c] === undefined || f[c] === null ? null : Number(f[c])])) }));

test('envoi pondeuses = vrai pushDailyEntries', (t) => {
    if (!retour) return t.skip(raison);
    const stats = { normal: 0, clos: 0, doublon: 0, ponte: 0, depart: 0, quatre: 0, passages: 0 };
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
        if (s.item.fiche.ponte_total > 0 && s.item.fiche.ponte_casses > 0) stats.ponte++;
        if (s.item.fiche.cat_depart_4 !== undefined) stats.depart++;
        if (s.item.fiche.mort_4 > 0 || s.item.fiche.don_4 > 0) stats.quatre++;
        if (s.item.fiche.passage_4_sevre + s.item.fiche.passage_jeune_repro > 0) stats.passages++;
    });
    if (NB === 400) assert.ok(stats.normal > 100 && stats.clos > 10 && stats.doublon > 10 && stats.ponte > 20 && stats.depart > 15 && stats.quatre > 30 && stats.passages > 15, `couverture insuffisante : ${JSON.stringify(stats)}`);
});

test('charge utile : quatre stades, trois passages, œufs cassés, ventes par stade à 0, départ à quatre stades envoyé', () => {
    const f = { id: uuid(1), lot_id: uuid(2), entry_date: '2026-11-08', achat: 0, ne: 5, mort: 4, vente: 3, don: 1, effectif_final: 50, ponte_total: 40, ponte_casses: 3, mort_repro: 1, mort_sevre: 1, mort_jeune: 0, mort_4: 2, don_repro: 1, don_sevre: 0, don_jeune: 0, don_4: 0,
        vente_repro: 1, vente_sevre: 1, vente_jeune: 0, vente_4: 1, passage_4_sevre: 2, passage_sevre_jeune: 1, passage_jeune_repro: 3, cat_depart_repro: 10, cat_depart_sevre: 20, cat_depart_jeune: 10, cat_depart_4: 10, feed_qty_kg: null, weight_sample_avg_g: 20 };
    const j = ficheEnJson({ fiche: f, cree_le: 'x' }, 'p');
    assert.equal(j.ponte_total, 40);
    assert.equal(j.ponte_casses, 3);
    assert.equal(j.vente, 0);
    assert.deepEqual([j.vente_repro, j.vente_sevre, j.vente_jeune, j.vente_4], [0, 0, 0, 0]);
    assert.equal(j.mort, 4, 'la somme porte aussi le quatrième stade');
    assert.equal(j.don, 1);
    assert.deepEqual([j.mort_4, j.don_4, j.passage_4_sevre, j.passage_sevre_jeune, j.passage_jeune_repro, j.cat_depart_4], [2, 0, 2, 1, 3, 10]);
    assert.equal(j.effectif_final, undefined);
    // Un départ à trois stades seulement ne part pas ; une fiche de reproducteurs n'envoie aucune colonne à quatre stades.
    const sans = ficheEnJson({ fiche: { ...f, cat_depart_4: null }, cree_le: 'x' }, 'p');
    assert.equal(sans.cat_depart_repro, undefined);
    assert.equal(sans.cat_depart_4, undefined);
    const repro = ficheEnJson({ fiche: { id: uuid(3), lot_id: uuid(2), entry_date: '2026-11-08', achat: 0, ne: 0, mort: 2, vente: 0, don: 0, mort_repro: 1, mort_sevre: 1, mort_jeune: 0, vente_repro: 0, vente_sevre: 0, vente_jeune: 0 }, cree_le: 'x' }, 'p');
    assert.equal(repro.mort_4, undefined);
    assert.equal(repro.vente_4, undefined);
    assert.equal(repro.passage_4_sevre, undefined);
});
