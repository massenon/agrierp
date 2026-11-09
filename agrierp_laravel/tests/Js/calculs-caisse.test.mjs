import test from 'node:test';
import assert from 'node:assert/strict';
import {
    arrondiPhp, prixUnitaire, lireEntier, formaterFcfa, sousTotal, totalVente, monnaieARendre, tvaIncluse,
    validerLigne, validerChoixFacture, construireVente, MOTIFS,
} from '../../resources/js/hors-ligne/calculs-caisse.js';

// Valeurs calculées À LA MAIN (pas par le code testé).

test('arrondi : demi-unité loin de zéro, comme PHP', () => {
    assert.equal(arrondiPhp(2.5), 3);
    assert.equal(arrondiPhp(-2.5), -3);
    assert.equal(arrondiPhp(1.005, 2), 1.01); // PHP 8.3 : 1.01 (le flottant brut vaut 1.00499999…)
    assert.equal(arrondiPhp(0.125, 2), 0.13);
});

test('prix unitaire = montant / quantité arrondi à 2 décimales, exact en entiers', () => {
    assert.equal(prixUnitaire(11800, 2), 5900);
    assert.equal(prixUnitaire(10000, 3), 3333.33);   // 3333,333…
    assert.equal(prixUnitaire(20000, 3), 6666.67);   // 6666,666…
    assert.equal(prixUnitaire(1, 8), 0.13);          // 0,125 -> 0,13
    assert.equal(prixUnitaire(500, 0), 0);
});

test('lecture des entiers : jamais de décimal silencieux', () => {
    assert.equal(lireEntier('11 800'), 11800);
    assert.equal(lireEntier('0'), 0);
    assert.equal(lireEntier('12,5'), null);
    assert.equal(lireEntier('1.5'), null);
    assert.equal(lireEntier('-3'), null);
    assert.equal(lireEntier(''), null);
    assert.equal(lireEntier(7.2), null);
});

test('sous-total = somme des manual_total_amount ; total = max(0, sous-total - remise)', () => {
    const lignes = [{ manual_total_amount: 6000 }, { manual_total_amount: 2500 }, { manual_total_amount: 1500 }];
    assert.equal(sousTotal(lignes), 10000);
    assert.equal(totalVente(lignes, 0), 10000);
    assert.equal(totalVente(lignes, 1500), 8500);
    assert.equal(totalVente(lignes, 12000), 0);
});

test('monnaie rendue : espèces seulement, jamais négative', () => {
    assert.equal(monnaieARendre('especes', 10000, 8500), 1500);
    assert.equal(monnaieARendre('especes', 5000, 8500), 0);
    assert.equal(monnaieARendre('mobile_money', 10000, 8500), 0);
    assert.equal(monnaieARendre('especes', null, 8500), 0);
});

test('TVA incluse : 11 800 à 18 % = 1 800 de TVA ; 1 000 exonéré = 0', () => {
    assert.deepEqual(tvaIncluse([{ manual_total_amount: 11800, tva_rate: 18 }], 0, true), { ht: 10000, tva: 1800 });
    assert.deepEqual(tvaIncluse([{ manual_total_amount: 11800, tva_rate: 18 }, { manual_total_amount: 1000, tva_rate: 0 }], 0, true), { ht: 11000, tva: 1800 });
    assert.deepEqual(tvaIncluse([{ manual_total_amount: 11800, tva_rate: 18 }], 0, false), { ht: 11800, tva: 0 });
    // remise de 1 180 sur 11 800 : ratio 0,9 -> TVA 1 620, HT 9 000 (10 620 - 1 620)
    assert.deepEqual(tvaIncluse([{ manual_total_amount: 11800, tva_rate: 18 }], 1180, true), { ht: 9000, tva: 1620 });
});

test('ligne : quantité entière ≥ 1, montant entier ≥ 0, produit vendable', () => {
    const p = { id: 'p', pricing_mode: 'fixe', species_id: null };
    assert.deepEqual(validerLigne({ produit: p, qty: '2', montant: '11 800' }), { ok: true, qty: 2, montant: 11800 });
    assert.equal(validerLigne({ produit: p, qty: '0', montant: '100' }).motif, MOTIFS.quantite);
    assert.equal(validerLigne({ produit: p, qty: '1,5', montant: '100' }).motif, MOTIFS.quantiteEntiere);
    assert.equal(validerLigne({ produit: p, qty: '1', montant: '-5' }).motif, MOTIFS.montantNegatif);
    assert.equal(validerLigne({ produit: p, qty: '1', montant: '' }).motif, MOTIFS.montant);
    assert.equal(validerLigne({ produit: p, qty: '1', montant: '10,5' }).motif, MOTIFS.montantEntier);
    assert.equal(validerLigne({ produit: { ...p, pricing_mode: 'quote' }, qty: '1', montant: '1' }).motif, MOTIFS.produitSurDevis);
    // PWA-1b : un sujet vivant exige sa bande source (phrase de la caisse web) ; avec elle, la ligne passe.
    assert.equal(validerLigne({ produit: { ...p, species_id: 'x' }, qty: '1', montant: '1' }).motif, 'La bande source est obligatoire pour un sujet vivant.');
    assert.equal(validerLigne({ produit: { ...p, species_id: 'x' }, qty: '1', montant: '1', lotId: 'b1' }).ok, true);
    assert.equal(validerLigne({ produit: null, qty: '1', montant: '1' }).motif, MOTIFS.produitInconnu);
});

test('choix de facture : mêmes règles que ChoixFactureService', () => {
    assert.deepEqual(validerChoixFacture({}).choix, { facture_type: 'simple', client_ifu: null, client_nom_facture: null, aib_taux: null });
    assert.equal(validerChoixFacture({ facture_type: 'x' }).motif, MOTIFS.factureType);
    assert.equal(validerChoixFacture({ facture_type: 'normalisee', client_nom_facture: ' ', aib_taux: '5%' }).motif, MOTIFS.factureNom);
    assert.equal(validerChoixFacture({ facture_type: 'normalisee', client_nom_facture: 'A', client_ifu: '123', aib_taux: '5%' }).motif, MOTIFS.factureIfu);
    assert.equal(validerChoixFacture({ facture_type: 'normalisee', client_nom_facture: 'A', aib_taux: undefined }).motif, MOTIFS.factureAib);
    assert.deepEqual(validerChoixFacture({ facture_type: 'normalisee', client_nom_facture: ' A B ', client_ifu: '1234 5678 90123', aib_taux: '1%' }).choix,
        { facture_type: 'normalisee', client_ifu: '1234567890123', client_nom_facture: 'A B', aib_taux: '1%' });
    assert.equal(validerChoixFacture({ facture_type: 'normalisee', client_nom_facture: 'A', client_ifu: '', aib_taux: 'N/A' }).choix.client_ifu, null);
});

const base = { id: '11111111-1111-4111-8111-111111111111', instant: '2026-11-08T10:00:00.000Z', deviceId: 'pwa-x', modePaiement: 'especes' };

test('vente complète : 2 lignes, remise, espèces', () => {
    const r = construireVente({ ...base, panier: [{ product_id: 'a', qty: 2, montant: 11800 }, { product_id: 'b', qty: 3, montant: 10000 }], remise: 800, especesRecues: 25000 });
    assert.equal(r.ok, true);
    assert.equal(r.vente.subtotal, 21800);
    assert.equal(r.vente.total, 21000);
    assert.equal(r.vente.change_due, 4000);
    assert.equal(r.vente.lines[1].unit_price, 3333.33);
    assert.equal(r.vente.sync_status, 'pending');
    assert.equal(r.vente.device_id, 'pwa-x');
    assert.equal(r.vente.sold_at, base.instant);
    assert.equal(r.vente.facture_type, 'simple');
});

test('refus : panier vide, crédit sans client, remise trop grande, espèces insuffisantes', () => {
    assert.equal(construireVente({ ...base, panier: [] }).motif, 'Le panier est vide.');
    assert.equal(construireVente({ ...base, panier: [{ product_id: 'a', qty: 1, montant: 100 }], modePaiement: 'credit' }).motif, MOTIFS.venteACredit);
    assert.equal(construireVente({ ...base, panier: [{ product_id: 'a', qty: 1, montant: 100 }], remise: 101 }).motif, MOTIFS.remiseTropGrande);
    assert.equal(construireVente({ ...base, panier: [{ product_id: 'a', qty: 1, montant: 100 }], especesRecues: 50 }).motif, MOTIFS.especesInsuffisantes);
    assert.equal(construireVente({ ...base, panier: [{ product_id: 'a', qty: 1, montant: 100 }], modePaiement: 'cheque' }).champ, 'payment_mode');
    // PWA-1b : « Déduire de l'avance » est un mode connu ; il exige un client, comme le crédit.
    assert.equal(construireVente({ ...base, panier: [{ product_id: 'a', qty: 1, montant: 100 }], modePaiement: 'avance' }).champ, 'customer_id');
    assert.equal(construireVente({ ...base, panier: [{ product_id: 'a', qty: 1, montant: 100 }], modePaiement: 'credit', clientId: 'c' }).ok, true);
});

test('affichage FCFA', () => {
    assert.equal(formaterFcfa(11800), '11 800 FCFA');
    assert.equal(formaterFcfa(0), '0 FCFA');
});
