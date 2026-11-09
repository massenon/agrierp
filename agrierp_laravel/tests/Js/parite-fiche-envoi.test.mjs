import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { chargerJour, enregistrerJour, ficheEnJson, MOTIFS } from '../../resources/js/hors-ligne/fiche-lapins-saisie.js';
import { computeEffectifFinal, jourDe } from '../../resources/js/hors-ligne/chaine-effectif.js';

/**
 * PWA-3 (fiche lapins, É4) — L'ENVOI : la charge utile `ficheEnJson` est jouée sur le VRAI `POST /api/sync/push` (clé `livestock_daily_entries`) :
 * l'effectif et la chaîne que le serveur obtient sont ceux que le navigateur a calculés, un second envoi n'écrit ni ne duplique rien, un exercice
 * clos est refusé avec la phrase du web, une fiche déjà connue sous un autre identifiant n'est jamais dupliquée. Sans `php` : sauté AVEC sa raison.
 */
const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
let graine = 20261114;
const alea = (n) => { graine = (graine * 1103515245 + 12345) % 2147483648; return Math.floor(graine / 65536) % n; };
const uuid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const deux = (n) => String(n).padStart(2, '0');
const jourDuMois = (d) => `2026-${d > 31 ? '11' : '10'}-${deux(d > 31 ? d - 31 : d)}`;

let compteur = 0;
const scenarios = [];
const NB = Number(process.env.SCENARIOS_LIMITE ?? 400);
for (let i = 0; i < NB * 3 && scenarios.length < NB; i++) {
    const espece = i % 2 === 0 ? 'cuniculture' : 'porciculture'; // lapins et porcs : même règle d'envoi, chaîne propre à l'espèce
    const initial = 20 + alea(200);
    const lot = { id: uuid(++compteur), code: `LAP-${i}`, species_code: espece, stage: ['reproduction', 'croissance', 'engraissement'][alea(3)], initial_quantity: initial, current_quantity: initial, status: 'actif', is_active: true };
    const chaine = alea(2) === 0;
    const jours = [...new Set(Array.from({ length: alea(6) }, () => 25 + alea(16)))].sort((a, b) => a - b);
    const fiches = [];
    let courant = initial;
    jours.forEach((d, k) => {
        const f = { id: uuid(++compteur), lot_id: lot.id, entry_date: jourDuMois(d), achat: alea(5) === 0 ? alea(6) : 0, ne: alea(4) === 0 ? alea(10) : 0, vente: alea(8) === 0 ? alea(3) : 0, don: 0, effectif_m: alea(10), effectif_f: alea(30), effectif_sevres: alea(40), effectif_smeres: alea(40), transfert_entree: 0, transfert_sortie: 0 };
        const mr = alea(3), ms = alea(3), mj = alea(3);
        Object.assign(f, { mort: mr + ms + mj, mort_repro: mr, mort_sevre: ms, mort_jeune: mj, don_repro: 0, don_sevre: 0, don_jeune: 0, passage_sevre_jeune: 0 });
        if (alea(3) === 0) f.weight_sample_avg_g = 500 + alea(3000);
        f.effectif_final = computeEffectifFinal(courant, f.achat, f.ne, f.mort, f.vente, f.don, 0, 0);
        courant = f.effectif_final;
        if (chaine && k === 0) { const r = Math.floor(initial / 3); Object.assign(f, { cat_depart_repro: r, cat_depart_jeune: r, cat_depart_sevre: initial - 2 * r }); }
        fiches.push(f);
    });
    if (fiches.length > 0) lot.current_quantity = courant;
    const jour = jourDuMois(25 + alea(16));
    const s = chargerJour(lot, fiches, jour);
    for (const [p, v] of [['achat', alea(4)], ['ne', alea(12)], ['mortRepro', alea(3)], ['mortChair', alea(5)], ['mortLapereau', alea(3)], ['donRepro', alea(3)], ['donChair', alea(2)], ['effectifM', alea(10)], ['effectifF', alea(30)]]) if (alea(2) === 0) s[p] = v;
    if (alea(3) === 0) s.peseeTotal = 500 + alea(9000);
    const r = enregistrerJour(lot, fiches, jour, s, { exercices: [], rations: [{ stage_label: 'Jeune', ration_g_per_day: 60 }] });
    if (r.refus !== null) continue;
    const type = ['normal', 'normal', 'normal', 'clos', 'doublon'][alea(5)];
    const exercices = [{ id: 1, year: 2026, start_date: '2026-01-01', end_date: '2026-12-31', status: type === 'clos' ? 'cloture' : 'ouvert' }];
    let item = { id_fiche: r.fiche.id, lot_id: lot.id, jour, saisie: s, fiche: r.fiche, cree_le: '2026-11-09T10:00:00.000Z', sync_status: 'pending' };
    let serveur = fiches;
    if (type === 'doublon') {
        // Le serveur tient déjà ce (bande, jour) sous un AUTRE identifiant que le navigateur ne connaît pas encore.
        if (fiches.some((f) => jourDe(f) === jour)) continue;
        serveur = [...fiches, { id: uuid(++compteur), lot_id: lot.id, entry_date: jour, achat: 0, ne: 0, mort: 0, vente: 0, don: 0, effectif_final: courant }];
    }
    scenarios.push({ espece, aujourdhui: '2026-11-09', lot, fiches: serveur, exercices, type, jour, envois: type === 'normal' ? 2 : 1, charge: [ficheEnJson(item, 'pwa-test')], local: r, item });
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

const COLONNES = ['achat', 'ne', 'mort', 'vente', 'don', 'effectif_final', 'effectif_m', 'effectif_f', 'effectif_sevres', 'effectif_smeres', 'feed_qty_kg',
    'mort_repro', 'mort_sevre', 'mort_jeune', 'don_repro', 'don_sevre', 'don_jeune', 'passage_sevre_jeune', 'weight_sample_avg_g',
    'cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune', 'cat_eff_repro', 'cat_eff_sevre', 'cat_eff_jeune'];
const normaliser = (fiches) => [...fiches].sort((a, b) => (jourDe(a) < jourDe(b) ? -1 : 1)).map((f) => ({ entry_date: jourDe(f), ...Object.fromEntries(COLONNES.map((c) => [c, f[c] === undefined || f[c] === null ? null : Number(f[c])])) }));

test('envoi = vrai pushDailyEntries : effectif du serveur = effectif du navigateur, idempotence, exercice clos, doublon', (t) => {
    if (!retour) return t.skip(raison);
    const stats = { normal: 0, clos: 0, doublon: 0, fusion: 0 };
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
            const ok = premier.reponse.accepted.includes(id);
            const motif = premier.reponse.rejected[0]?.reason;
            assert.ok(ok || (typeof motif === 'string' && motif.length > 10), `${ctx} fusion ou refus motivé`);
            if (ok) stats.fusion++;
            stats.doublon++;
            return;
        }
        assert.deepEqual(premier.reponse.accepted, [id], `${ctx} accepté`);
        assert.deepEqual(premier.reponse.rejected, [], `${ctx} aucun refus`);
        assert.deepEqual(normaliser(premier.fiches), normaliser(s.local.fiches), `${ctx} fiches du serveur = fiches du navigateur (cascade comprise)`);
        assert.equal(premier.current_quantity, s.local.lot.current_quantity, `${ctx} effectif de la bande`);
        assert.deepEqual(envois[1].reponse.accepted, [id], `${ctx} second envoi accusé`);
        assert.deepEqual(normaliser(envois[1].fiches), normaliser(premier.fiches), `${ctx} second envoi : rien écrit ni dupliqué`);
        assert.equal(envois[1].current_quantity, premier.current_quantity);
        stats.normal++;
    });
    assert.ok(stats.normal > 60 && stats.clos > 5 && stats.doublon > 5, `couverture insuffisante : ${JSON.stringify(stats)}`);
});

test('charge utile : colonnes du poste Flutter, jamais effectif_final ni cat_eff, vente à 0', () => {
    const f = { id: uuid(1), lot_id: uuid(2), entry_date: '2026-11-08', achat: 1, ne: 2, mort: 3, vente: 9, don: 1, effectif_final: 50, mort_repro: 1, mort_sevre: 1, mort_jeune: 1, don_repro: 1, don_sevre: 0, don_jeune: 0, passage_sevre_jeune: 0, cat_eff_repro: 5, cat_depart_repro: 10, cat_depart_sevre: 20, cat_depart_jeune: 20, effectif_m: 2, effectif_f: 3, feed_qty_kg: 1.5, weight_sample_avg_g: 90 };
    const j = ficheEnJson({ fiche: f, cree_le: '2026-11-09T10:00:00.000Z' }, 'pwa-x');
    assert.equal(j.vente, 0);
    assert.equal(j.effectif_final, undefined);
    assert.equal(j.cat_eff_repro, undefined);
    assert.equal(j.mort, 3);
    assert.equal(j.don, 1);
    assert.equal(j.cat_depart_jeune, 20);
    assert.equal(j.device_id, 'pwa-x');
    assert.equal(j.ponte_total, undefined);
    const sansDepart = ficheEnJson({ fiche: { ...f, cat_depart_jeune: null }, cree_le: 'x' }, 'p');
    assert.equal(sansDepart.cat_depart_repro, undefined, 'départ incomplet : jamais envoyé');
});
