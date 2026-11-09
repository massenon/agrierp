import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { delaisFournisseurs, seuilCritique } from '../../resources/js/hors-ligne/fiche-lapins-calculs.js';

/**
 * PWA-3 (délai fournisseur constaté) — PARITÉ EXÉCUTÉE contre le vrai `ReleveTerrainService::delaisFournisseurs()` et `regleEnVigueur()` :
 * bons reçus de la catégorie « Aliments », 5 derniers par fournisseur, délai du jour du bon à la réception, seuil critique de la règle de
 * terrain (départ, manuel, constaté). Sans `php` : sauté AVEC sa raison.
 */
const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
let graine = 20261116;
const alea = (n) => { graine = (graine * 1103515245 + 12345) % 2147483648; return Math.floor(graine / 65536) % n; };
const uuid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const deux = (n) => String(n).padStart(2, '0');
const jour = (offset) => { const d = new Date(Date.UTC(2026, 5, 1 + offset)); return `${d.getUTCFullYear()}-${deux(d.getUTCMonth() + 1)}-${deux(d.getUTCDate())}`; };

let compteur = 0;
const scenarios = [];
for (let i = 0; i < 300; i++) {
    const fournisseurs = Array.from({ length: 1 + alea(3) }, (_, k) => ({ id: uuid(++compteur), name: `F${i}-${k}` }));
    const produits = Array.from({ length: 4 }, (_, k) => ({ id: uuid(++compteur), categorie: k < 2 ? 'Aliments' : 'Médicaments' }));
    const bons = [];
    for (const f of fournisseurs) {
        const nb = alea(9);
        for (let k = 0; k < nb; k++) {
            const creation = alea(120);
            const heure = `${deux(alea(24))}:${deux(alea(60))}:${deux(alea(60))}`;
            bons.push({
                id: uuid(++compteur), supplier_id: f.id, status: alea(8) === 0 ? 'envoye' : 'recu', created_at: `${jour(creation)} ${heure}`,
                lignes: Array.from({ length: 1 + alea(2) }, () => produits[alea(alea(4) === 0 ? 4 : 2)].id),
                reception: alea(8) === 0 ? null : jour(creation + (alea(10) === 0 ? -alea(3) : alea(20))),
            });
        }
    }
    const releve = alea(3) === 0 ? null : { id: uuid(++compteur), status: alea(3) === 0 ? 'a_valider' : 'valide', data: { ...(alea(3) === 0 ? {} : { mode: alea(3) === 0 ? 'manuel' : 'constate' }), ...(alea(3) === 0 ? {} : { critique_jours: 1 + alea(8) }) } };
    scenarios.push({ fournisseurs, produits, bons, releve });
}

let retour = null;
let raison = null;
test('préparation : le PHP répond', (t) => {
    try {
        retour = JSON.parse(execFileSync('php', [path.join(racine, 'tests/Js/parite/executer-delais.php')], { input: JSON.stringify({ scenarios }), cwd: racine, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }));
    } catch (e) {
        if (e.code !== 'ENOENT') throw e;
        raison = 'PHP absent de cette machine (parité non exécutée)';
        t.skip(raison);
    }
});

test('délais et seuil constaté = vrai ReleveTerrainService', (t) => {
    if (!retour) return t.skip(raison);
    const stats = { constate: 0, avecCinq: 0, negatif: 0 };
    scenarios.forEach((s, i) => {
        // Ce que le tirage donne : created_at au format ISO (temps du serveur, ici UTC), lignes, achats qui ont reçu un bon.
        const bons = s.bons.map((b) => ({ id: b.id, supplier_id: b.supplier_id, status: b.status, created_at: `${b.created_at.replace(' ', 'T')}+00:00`, lines: b.lignes.map((p) => ({ product_id: p })) }));
        const achats = s.bons.filter((b) => b.reception !== null).map((b) => ({ id: `${b.id}-a`, purchase_order_id: b.id, purchase_date: b.reception }));
        const categories = [{ id: 'c-al', label: 'Aliments' }, { id: 'c-me', label: 'Médicaments' }];
        const produits = s.produits.map((p) => ({ id: p.id, category_id: p.categorie === 'Aliments' ? 'c-al' : 'c-me' }));
        const delais = delaisFournisseurs({ bons, achats, produits, categories });
        const p = retour[i];
        const ctx = `scénario ${i}`;
        const norm = (l) => l.map((d) => ({ supplier_id: d.supplier_id, nb: d.nb, critique_propose: d.critique_propose, delais: d.delais })).sort((a, b) => (a.supplier_id < b.supplier_id ? -1 : 1));
        assert.deepEqual(norm(delais), norm(p.delais), `${ctx} délais par fournisseur`);
        const releves = s.releve ? [{ id: s.releve.id, type: 'delai_regle', status: s.releve.status, is_active: true, data: s.releve.data }] : [];
        const seuil = seuilCritique(releves, delais);
        assert.equal(seuil.critique, p.critique, `${ctx} seuil critique`);
        assert.equal(seuil.source, p.source, `${ctx} source de la règle`);
        if (seuil.source === 'constate') stats.constate++;
        if (delais.some((d) => d.nb >= 5)) stats.avecCinq++;
    });
    assert.ok(stats.constate > 30 && stats.avecCinq > 60, `couverture insuffisante : ${JSON.stringify(stats)}`);
});

test('sans droit view-achats (bons non tirés) : seuil « constaté » incertain, jamais inventé', () => {
    const r = [{ id: 'a', type: 'delai_regle', status: 'valide', data: { mode: 'constate', critique_jours: 4 } }];
    assert.equal(seuilCritique(r, null).incertain, true);
    assert.equal(seuilCritique(r, []).incertain, false);
});
