import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { modeleFiche } from '../../resources/js/hors-ligne/fiche-lapins-ecran.js';
import { FAMILLES } from '../../resources/js/hors-ligne/fiche-familles.js';

/**
 * PWA-3 (fiche lapins, É2) — TEST D'ÉCRAN SUR DONNÉES TIRÉES SIMULÉES : l'effectif, les KPI, le taux de mortalité, le poids, les traitements, le mois,
 * le bandeau d'exercice clos et les transferts que l'écran AFFICHE sont égaux à ceux que calcule le VRAI composant PHP `FicheLapins` ou `FichePorcs` sur le même
 * jeu (base SQLITE en mémoire). Sans `php` : sauté AVEC sa raison.
 */
const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
let graine = 20261112;
const alea = (n) => { graine = (graine * 1103515245 + 12345) % 2147483648; return Math.floor(graine / 65536) % n; };
const uuid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const deux = (n) => String(n).padStart(2, '0');

const AUJOURDHUI = ['2026-11-09', '2026-01-31', '2026-03-01', '2027-02-15'];
let compteur = 0;
const scenarios = [];
for (let i = 0; i < 480; i++) {
    const famille = ['lapins', 'porcs', 'escargots', 'reproducteurs'][i % 4]; // un quart des scénarios par fiche
    const espece = { lapins: 'cuniculture', porcs: 'porciculture', escargots: 'helico', reproducteurs: 'aviculture' }[famille];
    const autre = famille === 'porcs' ? 'cuniculture' : (famille === 'reproducteurs' ? 'aviculture' : 'porciculture');
    const stageAutre = famille === 'reproducteurs' ? 'ponte' : 'reproduction'; // les pondeuses ne sont PAS dans la fiche des reproducteurs
    const stageDe = () => (famille === 'reproducteurs' ? ['reproduction', 'croissance', 'engraissement'][alea(3)] : 'reproduction');
    // Escargots : le module `helico` activé, désactivé ou jamais configuré.
    const module = famille === 'escargots' ? [true, true, true, false, null][alea(5)] : null;
    const aujourdhui = AUJOURDHUI[i % AUJOURDHUI.length];
    const annee = Number(aujourdhui.slice(0, 4));
    const produits = [{ id: uuid(++compteur), name: 'Vermifuge' }, { id: uuid(++compteur), name: 'Anticoccidien' }];
    const exercices = [{ id: 1, year: annee - 1, start_date: `${annee - 1}-01-01`, end_date: `${annee - 1}-12-31`, status: i % 3 === 0 ? 'cloture' : 'ouvert' },
        { id: 2, year: annee, start_date: `${annee}-01-01`, end_date: `${annee}-12-31`, status: i % 7 === 0 ? 'cloture' : 'ouvert' }];
    if (i % 11 === 0) exercices.length = 1;
    const lots = [];
    for (let k = 0; k < 1 + alea(3); k++) lots.push({ id: uuid(++compteur), code: `LAP-${i}-${k}`, species_code: espece, stage: stageDe(), status: 'actif', is_active: true, initial_quantity: 50 + alea(150), current_quantity: alea(200) });
    if (alea(3) === 0) lots.push({ id: uuid(++compteur), code: `ARCH-${i}`, species_code: espece, stage: stageDe(), status: 'archive', is_active: true, initial_quantity: 100, current_quantity: alea(50) });
    if (alea(3) === 0) lots.push({ id: uuid(++compteur), code: `POR-${i}`, species_code: autre, stage: stageAutre, status: 'actif', is_active: true, initial_quantity: 100, current_quantity: alea(50) });
    const fiches = [];
    const soins = [];
    for (const lot of lots) {
        let jour = 0;
        for (let mois = 0; mois < 3; mois++) {
            const base = new Date(Date.UTC(annee, Number(aujourdhui.slice(5, 7)) - 1 - mois, 1));
            // Du 2 au 28 : SQLite compare « 2026-01-01 » à la borne « 2026-01-01 00:00:00 » en TEXTE (le 1er serait écarté, ce que MySQL ne fait pas) ; pas de soin le 28 pour la même raison sur la borne haute (date stockée « … 00:00:00 »).
            for (let d = 2; d <= 28; d++) {
                if (alea(3) === 0) continue;
                jour++;
                const date = `${base.getUTCFullYear()}-${deux(base.getUTCMonth() + 1)}-${deux(d)}`;
                fiches.push({
                    id: uuid(++compteur), lot_id: lot.id, entry_date: date, achat: alea(4) === 0 ? alea(5) : 0, ne: alea(12), mort: alea(5) === 0 ? alea(8) : 0, vente: alea(6) === 0 ? alea(6) : 0, don: alea(9) === 0 ? alea(3) : 0,
                    effectif_m: alea(10), effectif_f: alea(30), effectif_sevres: alea(40), effectif_smeres: alea(40), effectif_final: 20 + alea(300), ponte_total: alea(3) === 0 ? null : alea(60),
                    weight_sample_avg_g: alea(3) === 0 ? null : 500 + alea(4000), symptomes: alea(6) === 0 ? 'Diarrhée' : null,
                    treatment_product_id: alea(5) === 0 ? produits[alea(2)].id : null,
                    transfert_entree: alea(8) === 0 ? 1 + alea(5) : 0, transfert_sortie: alea(8) === 0 ? 1 + alea(5) : 0,
                });
                if (alea(8) === 0 && d < 28) soins.push({ id: uuid(++compteur), lot_id: lot.id, action_type: alea(2) ? 'Vaccin' : 'Traitement', product_used: alea(2) ? 'Ivermectine' : null, record_date: date, is_active: alea(5) !== 0, created_at: `${date} 0${alea(9)}:00:00` });
            }
        }
    }
    // Reproducteurs : le sélecteur ne propose que les bandes de la fiche (une bande hors liste ne peut pas être choisie).
    const choisissables = famille === 'reproducteurs' ? lots.filter((l) => l.status === 'actif' && l.stage !== 'ponte') : lots;
    const lotChoisi = choisissables[alea(choisissables.length)] ?? lots[0];
    const mois = alea(3);
    const choisi = new Date(Date.UTC(annee, Number(aujourdhui.slice(5, 7)) - 1 - mois - (Math.floor(i / 4) % 2 === 0 ? 0 : 6), 1 + alea(28)));
    scenarios.push({
        famille, module, aujourdhui, produits, exercices, lots, fiches, soins, bandeId: alea(4) === 0 ? null : lotChoisi.id,
        date: alea(12) === 0 ? 'pas-une-date' : `${choisi.getUTCFullYear()}-${deux(choisi.getUTCMonth() + 1)}-${deux(choisi.getUTCDate())}`,
    });
}

let retour = null;
let raison = null;
test('préparation : le PHP répond', (t) => {
    try {
        retour = JSON.parse(execFileSync('php', [path.join(racine, 'tests/Js/parite/executer-fiche-mois.php')], { input: JSON.stringify({ scenarios }), cwd: racine, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 }));
    } catch (e) {
        if (e.code !== 'ENOENT') throw e;
        raison = 'PHP absent de cette machine (parité non exécutée)';
        t.skip(raison);
    }
});


test('écran = vrai FicheLapins : KPI, mois, jours, taux, poids, traitements, bandeau, transferts', (t) => {
    if (!retour) return t.skip(raison);
    let jours = 0; let bandeaux = 0; let avecTraitement = 0;
    scenarios.forEach((s, i) => {
        const donnees = { modules: s.module === null ? [] : [{ species_code: 'helico', is_enabled: s.module }], lots: s.lots, fiches: s.fiches, soins: s.soins, produits: s.produits.map((p) => ({ id: p.id, name: p.name })), exercices: s.exercices };
        const m = modeleFiche(donnees, { bandeId: s.bandeId, date: s.date, aujourdhui: s.aujourdhui, famille: FAMILLES[s.famille] });
        const p = retour[i];
        const ctx = `scénario ${i}`;
        assert.deepEqual(m.kpis, p.kpis, `${ctx} KPI`);
        assert.equal(m.libelleMois, p.libelleMois, `${ctx} libellé du mois`);
        assert.equal(m.estMoisCourant, p.estMoisCourant, `${ctx} mois courant`);
        assert.equal(m.bande?.id ?? null, p.bande, `${ctx} bande`);
        assert.deepEqual(m.bandeau, p.bandeau, `${ctx} bandeau`);
        assert.equal(m.transferts.transfert_entree, p.transferts.transfert_entree, `${ctx} transferts entrée`);
        assert.equal(m.transferts.transfert_sortie, p.transferts.transfert_sortie, `${ctx} transferts sortie`);
        assert.equal(m.jours.length, p.jours.length, `${ctx} nombre de jours`);
        m.jours.forEach((j, k) => {
            const q = p.jours[k];
            assert.equal(j.date, q.date, `${ctx} date`);
            assert.equal(j.fiche === null, q.fiche === null, `${ctx} ${j.date} fiche présente`);
            if (j.fiche) {
                assert.equal(j.fiche.taux, q.fiche.taux, `${ctx} ${j.date} taux`);
                assert.equal(j.fiche.poids_general_g, q.fiche.poids_general_g, `${ctx} ${j.date} poids`);
                assert.equal(j.fiche.effectif_final, q.fiche.effectif_final, `${ctx} ${j.date} effectif affiché`);
                assert.equal(j.fiche.effectif_m, q.fiche.effectif_m, `${ctx} ${j.date} effectif M`);
            }
            if (s.famille !== 'reproducteurs') assert.equal(j.traitements, q.traitements, `${ctx} ${j.date} traitements`);
            jours++; if (j.traitements !== '—') avecTraitement++;
        });
        if (m.bandeau) bandeaux++;
    });
    assert.ok(jours > 5000 && bandeaux > 10 && avecTraitement > 100, `couverture insuffisante : ${jours} jours, ${bandeaux} bandeaux, ${avecTraitement} traitements`);
});
