import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { evaluerAutonomie, produitProvende, seuilCritique, SEUIL_CRITIQUE_DEPART_JOURS } from '../../resources/js/hors-ligne/fiche-lapins-calculs.js';

/**
 * PWA-3 (fiche lapins, É5) — PARITÉ EXÉCUTÉE de l'autonomie alimentaire (produit de provende, stock en kg avec le poids du sac, seuil critique de
 * la règle de terrain, jours d'autonomie, rupture, inconnu) contre le vrai `AutonomieAlimentaireService`. Sans `php` : sauté AVEC sa raison.
 */
const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
let graine = 20261115;
const alea = (n) => { graine = (graine * 1103515245 + 12345) % 2147483648; return Math.floor(graine / 65536) % n; };
const uuid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const CUNI = 'ESP-CUNI';
const NOMS = ['Provende lapin', 'PROVENDE croissance', 'Aliment lapin', 'Sac de provende 25 kg', 'Son de blé', 'Poulet vif', 'Foin', 'aliment complet', 'Provende', 'Paille'];

let compteur = 0;
const scenarios = [];
for (let i = 0; i < 600; i++) {
    const produits = Array.from({ length: alea(5) }, () => ({ id: uuid(++compteur), name: NOMS[alea(NOMS.length)], unit: alea(2) === 0 ? 'sac' : 'kg', stock_qty: alea(4) === 0 ? 0 : (alea(2) === 0 ? alea(300) : alea(300) + 0.5), espece: ['cuniculture', 'cuniculture', 'porciculture', null][alea(4)] }));
    const feed_types = Array.from({ length: alea(3) }, () => ({ id: uuid(++compteur), standard_bag_weight_kg: [0, 25, 20, 50, 12.5][alea(5)] }));
    const releve = alea(3) === 0 ? null : { id: uuid(++compteur), status: alea(2) === 0 ? 'valide' : 'a_valider', data: { ...(alea(3) === 0 ? {} : { mode: alea(2) === 0 ? 'manuel' : 'constate' }), ...(alea(4) === 0 ? {} : { critique_jours: 1 + alea(10) }) } };
    const consommation = alea(5) === 0 ? null : (alea(6) === 0 ? 0 : (1 + alea(alea(2) === 0 ? 400 : 12000)) / 100);
    scenarios.push({ espece: i % 2 === 0 ? 'cuniculture' : 'porciculture', produits, feed_types, releve, consommation });
}
// Cas limites : l'autonomie vaut EXACTEMENT le seuil (3 j par défaut, ou la valeur de la règle) → critique.
for (let k = 1; k <= 20; k++) {
    const conso = k;
    scenarios.push({ produits: [{ id: uuid(++compteur), name: 'Provende lapin', unit: 'kg', stock_qty: 3 * conso, espece: 'cuniculture' }], feed_types: [], releve: null, consommation: conso });
    scenarios.push({ produits: [{ id: uuid(++compteur), name: 'Provende lapin', unit: 'kg', stock_qty: 6 * conso, espece: 'cuniculture' }], feed_types: [], releve: { id: uuid(++compteur), status: 'a_valider', data: { critique_jours: 6 } }, consommation: conso });
}

let retour = null;
let raison = null;
test('préparation : le PHP répond', (t) => {
    try {
        retour = JSON.parse(execFileSync('php', [path.join(racine, 'tests/Js/parite/executer-autonomie.php')], { input: JSON.stringify({ scenarios }), cwd: racine, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }));
    } catch (e) {
        if (e.code !== 'ENOENT') throw e;
        raison = 'PHP absent de cette machine (parité non exécutée)';
        t.skip(raison);
    }
});

test('autonomie = vrai AutonomieAlimentaireService', (t) => {
    if (!retour) return t.skip(raison);
    const stats = { disponible: 0, rupture: 0, critique: 0, inconnu: 0, sacs: 0 };
    scenarios.forEach((s, i) => {
        const produits = s.produits.map((p) => ({ id: p.id, name: p.name, unit: p.unit, stock_qty: p.stock_qty, species_id: p.espece === null ? null : p.espece === 'cuniculture' ? CUNI : 'ESP-PORC' }));
        const releves = s.releve === null ? [] : [{ id: s.releve.id, type: 'delai_regle', status: s.releve.status, is_active: true, data: s.releve.data }];
        const a = evaluerAutonomie(produitProvende(produits, [s.espece === 'porciculture' ? 'ESP-PORC' : CUNI]), s.consommation, s.feed_types, releves, []);
        const p = retour[i];
        const ctx = `scénario ${i}`;
        assert.equal(a.available, p.available, `${ctx} disponible`);
        if (!a.available) { assert.equal(p.product, null); return; }
        assert.equal(a.product.id, p.product, `${ctx} produit de provende`);
        assert.equal(a.stock_kg, p.stock_kg, `${ctx} stock en kg`);
        assert.equal(a.autonomie_jours, p.autonomie_jours, `${ctx} autonomie en jours`);
        assert.equal(a.critique, p.critique, `${ctx} critique`);
        assert.equal(a.rupture, p.rupture, `${ctx} rupture`);
        assert.equal(Boolean(a.inconnu), p.inconnu, `${ctx} inconnu`);
        stats.disponible++; if (a.rupture) stats.rupture++; if (a.critique && !a.rupture) stats.critique++; if (a.inconnu) stats.inconnu++; if (a.product.unit === 'sac') stats.sacs++;
    });
    assert.ok(stats.disponible > 200 && stats.rupture > 15 && stats.critique > 15 && stats.inconnu > 10 && stats.sacs > 50, `couverture insuffisante : ${JSON.stringify(stats)}`);
});

test('seuil critique : 3 jours par défaut ; règle validée en mode « constaté » = seuil incertain (jamais inventé)', () => {
    assert.equal(SEUIL_CRITIQUE_DEPART_JOURS, 3);
    assert.deepEqual(seuilCritique([]), { critique: 3, incertain: false, source: 'depart' });
    assert.deepEqual(seuilCritique([{ id: 'a', type: 'delai_regle', status: 'a_valider', data: { critique_jours: 5 } }]), { critique: 5, incertain: false, source: 'depart' });
    assert.deepEqual(seuilCritique([{ id: 'a', type: 'delai_regle', status: 'valide', data: { mode: 'manuel', critique_jours: 6 } }]), { critique: 6, incertain: false, source: 'manuel' });
    assert.equal(seuilCritique([{ id: 'a', type: 'delai_regle', status: 'valide', data: { mode: 'constate', critique_jours: 4 } }]).incertain, true);
});
