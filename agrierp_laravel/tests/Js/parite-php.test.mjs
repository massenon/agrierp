import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import {
    sousTotal, totalVente, tvaIncluse, prixUnitaire, validerChoixFacture, validerLigne, construireVente, MOTIFS, livraisonRetenue, validerLivraison,
} from '../../resources/js/hors-ligne/calculs-caisse.js';
import { validerClient } from '../../resources/js/hors-ligne/clients-hors-ligne.js';

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
// PWA-1b — livraisons : modes, frais (entiers, décimaux, négatifs, vides), remises, dont la demi-unité (2,5 → 3).
const fraisFixes = [null, 0, 1, 2500, 2500.5, 0.5, 1.5, 2.5, -10, 99999];
const livraisons = [];
for (const [lignes, remise] of [[[[11800, 2, 18]], 0], [[[999, 7, 18], [1001, 3, 0]], 1180], [[[5000, 1, 0]], 5000], [[[1, 8, 18]], 0]]) {
    for (const mode of ['gratuite', 'client', 'incluse', 'facturee']) for (const frais of fraisFixes) for (const concernee of [true, false]) {
        livraisons.push({ lignes, remise, mode, frais, concernee });
    }
}
for (const l of livraisons) {
    const ls = l.lignes.map(([montant, qty, tva_rate]) => ({ montant, qty, tva_rate, manual_total_amount: montant }));
    const retenue = livraisonRetenue({ concernee: l.concernee, mode: l.mode, frais: l.frais });
    Object.assign(l, { total_js: totalVente(ls, l.remise, retenue), fee_js: retenue });
}
const clientsFixes = [
    { name: 'Awa Kpossou' }, { name: '' }, { name: '   ' }, { name: 'A'.repeat(150) }, { name: 'A'.repeat(151) },
    { name: 'Awa', phone: '0197112233' }, { name: 'Awa', phone: '9'.repeat(30) }, { name: 'Awa', phone: '9'.repeat(31) },
    { name: 'Awa', ifu: '3201234567890' }, { name: 'Awa', ifu: '320123456789' }, { name: 'Awa', ifu: '32012345678901' }, { name: 'Awa', ifu: '3201 2345 67890' },
    { name: 'Awa', ifu: '12345678901ab' }, { name: '', phone: '9'.repeat(31), ifu: '1' }, { name: 'é', phone: '', ifu: '' },
];
let retour = null;

test('préparation : le PHP répond', (t) => {
    const entree = {
        ventes: cas.map((c) => {
            const l = toLignes(c);
            return { lignes: l.map(({ montant, qty, tva_rate }) => ({ montant, qty, tva_rate })), remise: c.remise, tva_active: c.tva, total_js: totalVente(l, c.remise) };
        }),
        factures: facturesFixes,
        livraisons: livraisons.map(({ lignes, remise, mode, frais, concernee, total_js, fee_js }) => ({ lignes: lignes.map(([montant, qty]) => ({ montant, qty })), remise, mode, frais, concernee, total_js, fee_js })),
        // Ce que le navigateur ENVOIE : les valeurs normalisées quand la saisie passe (nom rogné, IFU sans espaces), la saisie brute sinon.
        clients: clientsFixes.map((d) => { const r = validerClient(d); return r.ok ? r.valeurs : d; }),
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

test('PWA-1b livraison : frais retenus et total égaux à la caisse web, et le serveur accepte le total', (t) => {
    if (!retour) return t.skip(raisonSaut || 'PHP non exécuté');
    assert.ok(livraisons.length >= 300);
    livraisons.forEach((l, i) => {
        const p = retour.livraisons[i];
        assert.equal(l.fee_js, p.retenue, `frais retenus cas ${i} ${JSON.stringify(l)}`);
        assert.equal(l.total_js, p.total, `total cas ${i} ${JSON.stringify(l)}`);
        assert.equal(p.total_accepte, true, `le serveur accepte le total du cas ${i}`);
    });
});

test('PWA-1b livraison : le serveur REFUSE un total qui oublie les frais facturés', (t) => {
    if (!retour) return t.skip(raisonSaut || 'PHP non exécuté');
    // Le même cas rejoué SANS les frais : la parité du refus (jamais acceptée par erreur).
    const facturees = livraisons.filter((l) => l.concernee && l.mode === 'facturee' && l.fee_js > 0);
    assert.ok(facturees.length > 0);
    for (const l of facturees) {
        const sans = totalVente(l.lignes.map(([montant]) => ({ manual_total_amount: montant })), l.remise, 0);
        assert.notEqual(sans, l.total_js);
    }
});

test('PWA-1b client : résultat, champ et motif identiques aux règles du serveur', (t) => {
    if (!retour) return t.skip(raisonSaut || 'PHP non exécuté');
    clientsFixes.forEach((d, i) => {
        const js = validerClient(d); const p = retour.clients[i];
        assert.equal(js.ok, p.ok, `client ${i} ${JSON.stringify(d)}`);
        if (!p.ok) { assert.equal(js.champ, p.champ, `champ ${i}`); assert.equal(js.motif, p.motif, `motif ${i}`); }
    });
});

test('PWA-1b motifs : vente sur avance et champs de livraison, mêmes mots que le web et le serveur', (t) => {
    if (!retour) return t.skip(raisonSaut || 'PHP non exécuté');
    assert.equal(MOTIFS.venteSurAvance, retour.motifs.venteSurAvance);
    assert.deepEqual(retour.regles_livraison_dans_pushsales, { delivery_mode: true, delivery_fee: true, delivery_address: true, delivery_contact: true });
    const m = retour.livraison_motifs;
    assert.equal(MOTIFS.livraisonMode, m.mode);
    assert.equal(MOTIFS.livraisonFrais, m.frais);
    assert.equal(MOTIFS.livraisonAdresse, m.adresse);
    assert.equal(MOTIFS.livraisonContact, m.contact);
    assert.equal(validerLivraison({ concernee: true, mode: 'drone' }).motif, m.mode);
    assert.equal(validerLivraison({ concernee: true, mode: 'facturee', frais: Number.NaN }).motif, m.frais);
    assert.equal(validerLivraison({ concernee: true, mode: 'gratuite', adresse: 'a'.repeat(256) }).motif, m.adresse);
    assert.equal(validerLivraison({ concernee: true, mode: 'gratuite', contact: 'a'.repeat(256) }).motif, m.contact);
});
