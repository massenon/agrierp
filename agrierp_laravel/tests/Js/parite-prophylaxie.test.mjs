import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { protocoleDuJour, etatProtocole, enAttente, validerTraitements, remanenceDuSoin } from '../../resources/js/hors-ligne/fiche-lapins-prophylaxie.js';

/**
 * PWA-3 (fiche lapins) — PARITÉ EXÉCUTÉE de la prophylaxie du jour contre le vrai composant `FicheLapins` : jour de cycle (mise en lot ou dernière
 * saillie), traitements dus, déjà administrés, calendaires, état, refus et messages de `validerTraitements`, soins et rémanences créés.
 * Sans `php` : sauté AVEC sa raison.
 */
const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
let graine = 20261117;
const alea = (n) => { graine = (graine * 1103515245 + 12345) % 2147483648; return Math.floor(graine / 65536) % n; };
const uuid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const deux = (n) => String(n).padStart(2, '0');
const jour = (offset) => { const d = new Date(Date.UTC(2026, 9, 1 + offset)); return `${d.getUTCFullYear()}-${deux(d.getUTCMonth() + 1)}-${deux(d.getUTCDate())}`; };
const TRAITEMENTS = ['Vermifuge', 'Vitamines', 'Anticoccidien', 'Vaccin VHD', 'Antibiotique', 'Désinfection', 'Déparasitage', 'Complexe B'];

let compteur = 0;
const scenarios = [];
const NB = Number(process.env.SCENARIOS_LIMITE ?? 600); // une valeur réduite sert aux contrôles par mutation seulement
for (let i = 0; i < NB; i++) {
    const famille = ['lapins', 'porcs', 'reproducteurs'][i % 3];
    const espece = { lapins: 'cuniculture', porcs: 'porciculture', reproducteurs: 'aviculture' }[famille];
    const autre = famille === 'porcs' ? 'cuniculture' : (famille === 'reproducteurs' ? 'porciculture' : 'porciculture');
    const stage = ['reproduction', 'croissance', 'engraissement'][alea(3)];
    const lot = { id: uuid(++compteur), stage, created_date: jour(10 + alea(20)) };
    const evenements = stage === 'reproduction' ? Array.from({ length: alea(4) }, () => ({ id: uuid(++compteur), saillie_date: jour(alea(40)) })) : [];
    const standards = Array.from({ length: 2 + alea(10) }, () => {
        const debut = alea(6) === 0 ? null : 1 + alea(22);
        return { id: uuid(++compteur), species_code: alea(6) === 0 ? autre : espece, treatment: TRAITEMENTS[alea(TRAITEMENTS.length)], product_recommended: `Produit ${alea(5)}`, dosage: `${1 + alea(5)} ml`, withdrawal_days: alea(3) === 0 ? 1 + alea(14) : 0, is_active: alea(8) === 0 ? 0 : 1, cycle_day_start: debut, cycle_day_end: debut === null ? null : debut + alea(6) };
    });
    const j = jour(alea(9) === 0 ? 41 + alea(5) : 20 + alea(21)); // jusqu'à aujourd'hui (jour 40 = 10 nov.) et parfois le futur
    const soins = standards.filter(() => alea(5) === 0).map((s) => ({ id: uuid(++compteur), action_type: s.treatment, record_date: alea(4) === 0 ? jour(alea(40)) : j, is_active: alea(5) !== 0 }));
    const coches = [...standards.filter(() => alea(4) !== 0).map((s) => s.id), ...(alea(6) === 0 ? [uuid(999999)] : [])];
    scenarios.push({ famille, espece, aujourdhui: jour(39), lot, evenements, standards, soins, jour: j, coches, observations: ['', '  ', null, 'RAS', '  légère toux  ', 'x'.repeat(30)][alea(6)] ?? '' });
}

let retour = null;
let raison = null;
test('préparation : le PHP répond', (t) => {
    try {
        retour = JSON.parse(execFileSync('php', [path.join(racine, 'tests/Js/parite/executer-prophylaxie.php')], { input: JSON.stringify({ scenarios }), cwd: racine, encoding: 'utf8', maxBuffer: 128 * 1024 * 1024 }));
    } catch (e) {
        if (e.code !== 'ENOENT') throw e;
        raison = 'PHP absent de cette machine (parité non exécutée)';
        t.skip(raison);
    }
});

const trier = (l) => [...l].sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b)));

test('prophylaxie du jour = vrai FicheLapins : protocole, refus, messages, soins et rémanences', (t) => {
    if (!retour) return t.skip(raison);
    const stats = { protocoles: 0, indetermine: 0, succes: 0, rien: 0, futur: 0, remanences: 0, reproduction: 0 };
    scenarios.forEach((s, i) => {
        const p = retour[i];
        const ctx = `scénario ${i}`;
        const standards = s.standards.map((x) => ({ ...x, is_active: Boolean(x.is_active) }));
        const lot = { ...s.lot, id: s.lot.id };
        const protocole = protocoleDuJour({ lot, evenements: s.evenements.map((e) => ({ ...e, lot_id: lot.id })), standards, soins: s.soins.map((x) => ({ ...x, lot_id: lot.id })), jour: s.jour, espece: s.espece });
        assert.equal(protocole.jourDeCycle, p.avant.jourDeCycle, `${ctx} jour de cycle`);
        assert.equal(protocole.motifIndetermine, p.avant.motif, `${ctx} motif`);
        assert.equal(protocole.calendairesNonEvalues, p.avant.calendaires, `${ctx} calendaires`);
        assert.equal(etatProtocole(protocole), p.avant.etat, `${ctx} état`);
        assert.equal(enAttente(protocole), p.avant.enAttente, `${ctx} en attente`);
        assert.deepEqual(protocole.traitements.map((l) => ({ id: l.standard.id, deja: l.deja_administre })), p.avant.traitements, `${ctx} traitements (ordre compris)`);
        stats.protocoles++; if (protocole.jourDeCycle === null) stats.indetermine++; if (lot.stage === 'reproduction') stats.reproduction++;

        let n = 0;
        const r = validerTraitements({ lot, evenements: s.evenements.map((e) => ({ ...e, lot_id: lot.id })), standards, soins: s.soins.map((x) => ({ ...x, lot_id: lot.id })), jour: s.jour, aujourdhui: s.aujourdhui, espece: s.espece, idsCoches: s.coches, observations: s.observations, nouvelId: () => `n${++n}` });
        const attendu = r.refus ? { message: r.refus, type: 'error' } : r.avertissement ? { message: r.avertissement, type: 'warning' } : { message: r.message, type: 'success' };
        assert.deepEqual(p.toast, attendu, `${ctx} message`);
        const nouveaux = (r.soins ?? []).map((x) => ({ action_type: x.action_type, product_used: x.product_used, dose: x.dose, symptomes: x.symptomes, record_date: x.record_date, is_active: true }));
        const anciens = s.soins.map((x) => ({ action_type: x.action_type, product_used: null, dose: null, symptomes: null, record_date: x.record_date, is_active: Boolean(x.is_active) }));
        assert.deepEqual(trier(p.soins), trier([...anciens, ...nouveaux]), `${ctx} soins au registre`);
        const periodes = (r.soins ?? []).map(remanenceDuSoin).filter(Boolean).map((x) => ({ product_used: x.product_used, start_date: x.start_date, withdrawal_days: x.withdrawal_days, end_date: x.end_date }));
        assert.deepEqual(trier(p.periodes), trier(periodes), `${ctx} périodes de rémanence`);
        if (r.soins?.length) stats.succes++; else if (r.refus) stats.futur++; else stats.rien++;
        stats.remanences += periodes.length;
    });
    if (NB === 600) assert.ok(stats.succes > 80 && stats.rien > 20 && stats.futur > 15 && stats.remanences > 30 && stats.indetermine > 15 && stats.reproduction > 80, `couverture insuffisante : ${JSON.stringify(stats)}`);
});
