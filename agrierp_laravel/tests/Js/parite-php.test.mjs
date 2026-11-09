import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import {
    sousTotal, totalVente, tvaIncluse, prixUnitaire, validerChoixFacture, validerLigne, construireVente, MOTIFS,
} from '../../resources/js/hors-ligne/calculs-caisse.js';

/**
 * PARITÉ EXÉCUTÉE CONTRE LE VRAI PHP (PosInterface, RecordSaleAccountingEntryAction::ventilerHtEtTva,
 * SyncController::verifierCoherenceDuTotal, ChoixFactureService, MotifsRefusPush). Une divergence = test rouge.
 * Sans `php` sur la machine : les tests se sautent AVEC leur raison.
 */
const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
let php = null;
let raisonSaut = false;

// Grille : cas choisis (remises, taux, arrondis délicats) + 60 cas pseudo-aléatoires reproductibles.
const lignesFixes = [
    [[11800, 2, 18]], [[10000, 3, 0]], [[1, 8, 18]], [[999, 7, 18], [1001, 3, 0]],
    [[5000, 1, 18], [5000, 1, 18], [333, 3, 0]], [[0, 1, 0]], [[1234567, 11, 18]],
];
const remisesFixes = [0, 1, 7, 1180, 5000];
let graine = 20261108;
const alea = (n) => { graine = (graine * 1103515245 + 12345) % 2147483648; return graine % n; };
const cas = [];
for (const lignes of lignesFixes) for (const remise of remisesFixes) {
    const somme = lignes.reduce((s, l) => s + l[0], 0);
    if (remise <= somme) for (const tva of [true, false]) cas.push({ lignes, remise, tva });
}
for (let i = 0; i < 60; i++) {
    const n = 1 + alea(4);
    const lignes = Array.from({ length: n }, () => [alea(200000), 1 + alea(12), [0, 18, 18, 9][alea(4)]]);
    const somme = lignes.reduce((s, l) => s + l[0], 0);
    cas.push({ lignes, remise: alea(somme + 1), tva: alea(2) === 0 });
}
const toLignes = (c) => c.lignes.map(([montant, qty, tva_rate]) => ({ montant, qty, tva_rate, manual_total_amount: montant }));
const facturesFixes = [
    {}, { facture_type: 'simple', client_ifu: '12' }, { facture_type: 'inconnu' }, { facture_type: 'normalisee' },
    { facture_type: 'normalisee', client_nom_facture: 'Awa K.', aib_taux: '5%' },
    { facture_type: 'normalisee', client_nom_facture: 'Awa K.', client_ifu: '12345678901', aib_taux: '5%' },
    { facture_type: 'normalisee', client_nom_facture: 'Awa K.', client_ifu: '1234 5678 90123', aib_taux: '1%' },
    { facture_type: 'normalisee', client_nom_facture: 'Awa K.', client_ifu: '12345678901ab', aib_taux: 'N/A' },
    { facture_type: 'normalisee', client_nom_facture: 'X'.repeat(151), aib_taux: '5%' },
    { facture_type: 'normalisee', client_nom_facture: 'X'.repeat(150), aib_taux: '5%' },
    { facture_type: 'normalisee', client_nom_facture: '  é  ', aib_taux: '7%' },
    { facture_type: ' normalisee ', client_nom_facture: 'A', aib_taux: 'N/A' },
];
let retour = null;

test('préparation : le PHP répond', (t) => {
    const entree = {
        ventes: cas.map((c) => {
            const l = toLignes(c);
            return { lignes: l.map(({ montant, qty, tva_rate }) => ({ montant, qty, tva_rate })), remise: c.remise, tva_active: c.tva, total_js: totalVente(l, c.remise) };
        }),
        factures: facturesFixes,
    };
    try {
        retour = JSON.parse(execFileSync('php', [path.join(racine, 'tests/Js/parite/executer-php.php')], { input: JSON.stringify(entree), cwd: racine, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }));
    } catch (e) {
        // Seule l'ABSENCE de PHP saute les essais ; un PHP présent qui échoue est une VRAIE panne (jamais un saut silencieux).
        if (e.code !== 'ENOENT') throw e;
        raisonSaut = 'PHP absent de cette machine (parité non exécutée)';
        t.skip(raisonSaut);
    }
});

test('sous-total, total, prix unitaire : égaux à la caisse web', (t) => {
    if (!retour) return t.skip(raisonSaut || 'PHP non exécuté');
    cas.forEach((c, i) => {
        const l = toLignes(c); const p = retour.ventes[i];
        assert.equal(sousTotal(l), p.subtotal, `sous-total cas ${i}`);
        assert.equal(totalVente(l, c.remise), p.total, `total cas ${i}`);
        c.lignes.forEach(([m, q], k) => assert.equal(prixUnitaire(m, q), p.unit_prices[k], `prix unitaire cas ${i} ligne ${k}`));
    });
});

test('TVA incluse : égale à ventilerHtEtTva', (t) => {
    if (!retour) return t.skip(raisonSaut || 'PHP non exécuté');
    cas.forEach((c, i) => {
        const r = tvaIncluse(toLignes(c), c.remise, c.tva);
        assert.equal(r.tva, retour.ventes[i].tva, `TVA cas ${i} ${JSON.stringify(c)}`);
        assert.equal(r.ht, retour.ventes[i].ht, `HT cas ${i} ${JSON.stringify(c)}`);
    });
});

test('le serveur accepte le total que la caisse calcule', (t) => {
    if (!retour) return t.skip(raisonSaut || 'PHP non exécuté');
    cas.forEach((c, i) => assert.equal(retour.ventes[i].total_accepte, true, `cas ${i}`));
});

test('choix de facture : résultat et motif identiques à ChoixFactureService', (t) => {
    if (!retour) return t.skip(raisonSaut || 'PHP non exécuté');
    facturesFixes.forEach((d, i) => {
        const js = validerChoixFacture(d); const p = retour.factures[i];
        assert.equal(js.ok, p.ok, `facture ${i} ${JSON.stringify(d)}`);
        if (p.ok) assert.deepEqual(js.choix, p.choix, `facture ${i}`);
        else { assert.equal(js.champ, p.champ, `champ ${i}`); assert.equal(js.motif, p.motif, `motif ${i}`); }
    });
});

test('motifs : mêmes mots que la caisse web et le serveur', (t) => {
    if (!retour) return t.skip(raisonSaut || 'PHP non exécuté');
    const m = retour.motifs;
    assert.equal(MOTIFS.panierVide, m.panierVide);
    assert.equal(MOTIFS.venteACredit, m.venteACredit);
    assert.equal(MOTIFS.factureType, m.factureType);
    assert.equal(MOTIFS.factureNom, m.factureNom);
    assert.equal(MOTIFS.factureIfu, m.factureIfu);
    assert.equal(MOTIFS.factureAib, m.factureAib);
    // Le serveur, lui, dit seulement « Une vente à crédit exige un client. » : la phrase du web COMMENCE pareil.
    assert.ok(MOTIFS.venteACredit.startsWith(m.serveurCredit.slice(0, -1)));
    const v = retour.validation_lignes;
    assert.equal(validerLigne({ produit: { pricing_mode: 'x' }, qty: '0', montant: '10' }).motif, v.quantite);
    assert.equal(validerLigne({ produit: { pricing_mode: 'x' }, qty: '1', montant: '-1' }).motif, v.montant_negatif);
    assert.equal(validerLigne({ produit: { pricing_mode: 'x' }, qty: '1', montant: '' }).motif, v.montant_texte);
});
