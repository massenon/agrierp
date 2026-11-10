import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { formaterFcfa } from '../../resources/js/hors-ligne/calculs-caisse.js';
import { contenuRecu, recuEnHtml, rendreRecu, idCourt, dateHeureBenin, libelleMode, recuProvisoireDisponible, LIBELLES_MODE, MENTION_RECU, TITRE_RECU, BOUTON_RECU } from '../../resources/js/hors-ligne/recu-provisoire.js';

/** CAISSE-2 (DV-33) — le reçu provisoire d'une vente hors ligne : sans numéro légal, avec l'identifiant court et la mention exacte. */
const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const lire = (p) => readFileSync(path.join(racine, p), 'utf8');
const vente = {
    id: 'a1b2c3d4-0000-4000-8000-000000000001', sold_at: '2026-11-09T21:05:00.000Z', customer_id: 'c1', payment_mode: 'especes', subtotal: 13000, discount: 500, total: 14500,
    cash_received: 15000, change_due: 500, delivery_fee: 2000, delivery_in_total: true,
    lines: [{ product_id: 'p1', lot_id: null, qty: 2, unit_price: 5900, manual_total_amount: 11800 }, { product_id: 'p2', lot_id: null, qty: 1, unit_price: 1200, manual_total_amount: 1200 }],
};
const donnees = { entreprise: { company_name: 'Ferme École OLOUWACHEGOUN' }, produits: [{ id: 'p1', name: 'Plaquette d\'œufs' }, { id: 'p2', name: 'Fumier' }], clients: [{ id: 'c1', name: 'Awa Koffi' }] };
const h = (tag, attrs = {}, ...enfants) => ({ tag, attrs, enfants: enfants.flat().filter((x) => x !== null) });
const texte = (n) => (typeof n === 'string' ? n : (n.enfants ?? []).map(texte).join(' '));

test('contenu exact : entête, identifiant court en majuscules, date du Bénin, client, lignes, remise, livraison, mode lisible, reçu / rendu, mention', () => {
    const c = contenuRecu(vente, donnees);
    assert.equal(c.entete, 'Ferme École OLOUWACHEGOUN');
    assert.equal(c.titre, 'Reçu provisoire');
    assert.equal(c.identifiant, 'A1B2C3D4');
    assert.equal(c.dateHeure, '09/11/2026 à 22:05', 'UTC+1 : 21:05 UTC = 22:05 au Bénin');
    assert.equal(c.client, 'Awa Koffi');
    assert.deepEqual(c.lignes.map((l) => [l.produit, l.quantite]), [['Plaquette d\'œufs', 2], ['Fumier', 1]]);
    assert.equal(c.remise, formaterFcfa(500));
    assert.equal(c.livraison, formaterFcfa(2000));
    assert.equal(c.total, formaterFcfa(14500));
    assert.equal(c.mode, 'Espèces');
    assert.equal(c.recu, formaterFcfa(15000));
    assert.equal(c.rendu, formaterFcfa(500));
    assert.equal(c.mention, 'Facture n° attribué à la synchronisation.');
    const t = texte(rendreRecu(h, c));
    for (const x of ['Reçu provisoire', 'Vente n° A1B2C3D4', 'Date : 09/11/2026 à 22:05', 'Client : Awa Koffi', 'Remise :', 'Frais de livraison (facturée) :', 'Mode de règlement : Espèces', 'Montant reçu :', 'Facture n° attribué à la synchronisation.']) assert.ok(t.includes(x), `absent : ${x}`);
});

test('AUCUN numéro de facture légal : ni dans le contenu ni dans la page imprimée ; le numéro viendra du serveur', () => {
    const c = contenuRecu(vente, donnees);
    const html = recuEnHtml(c);
    assert.ok(!/FA-|FV-|N°\s*\d|n° \d/.test(html + texte(rendreRecu(h, c))), 'pas de numéro de facture');
    assert.ok(html.includes(MENTION_RECU) && html.includes('A1B2C3D4'));
    const src = lire('resources/js/hors-ligne/recu-provisoire.js');
    assert.ok(!/invoice_number|numero_facture|\.number\b/.test(src), 'le navigateur n\'invente aucun numéro');
});

test('client anonyme, mode inconnu, montants à crédit sans reçu / rendu, HTML échappé', () => {
    const c = contenuRecu({ ...vente, customer_id: null, payment_mode: 'mobile_money', discount: 0, delivery_in_total: false, delivery_fee: 0 }, { ...donnees, produits: [{ id: 'p1', name: '<b>x</b> & "y"' }] });
    assert.equal(c.client, 'Client Anonyme');
    assert.equal(c.mode, 'Mobile Money');
    assert.equal(c.remise, null); assert.equal(c.livraison, null); assert.equal(c.recu, null);
    assert.equal(contenuRecu({ ...vente, delivery_in_total: false, delivery_fee: 2000 }, donnees).livraison, null, 'livraison non facturée : jamais sur le reçu');
    const html = recuEnHtml(c);
    assert.ok(html.includes('&lt;b&gt;x&lt;/b&gt; &amp; &quot;y&quot;') && !html.includes('<b>x</b>'));
    assert.equal(libelleMode('mode_inconnu'), 'Mode inconnu');
    assert.equal(libelleMode(''), '—');
    assert.equal(contenuRecu({ ...vente, client_nom_facture: 'Société Z' }, donnees).client, 'Société Z');
});

test('seulement tant que la vente attend son envoi (pending) ; ni refusée (conflict) ni après la synchronisation', () => {
    assert.equal(recuProvisoireDisponible({ sync_status: 'pending' }), true);
    assert.equal(recuProvisoireDisponible({ sync_status: 'conflict' }), false);
    assert.equal(recuProvisoireDisponible({ sync_status: 'synced' }), false);
});

test('garde de sources : libellés de ModePaiement, mention et bouton imposés, impression par le navigateur sans page en cache', () => {
    const php = lire('app/Support/ModePaiement.php').replace(/\s+/g, ' ');
    for (const [cle, libelle] of Object.entries(LIBELLES_MODE)) assert.ok(php.includes(`'${cle}' => '${libelle}'`), cle);
    assert.equal(MENTION_RECU, 'Facture n° attribué à la synchronisation.');
    assert.equal(TITRE_RECU, 'Reçu provisoire');
    assert.equal(BOUTON_RECU, 'Imprimer le reçu provisoire');
    assert.equal(idCourt('abcdef12-3456'), 'ABCDEF12');
    assert.equal(dateHeureBenin('2026-12-31T23:30:00Z'), '01/01/2027 à 00:30');
    const src = lire('resources/js/hors-ligne/recu-provisoire.js');
    assert.ok(src.includes('cadre.srcdoc = recuEnHtml(c)') && src.includes('.print()'));
    assert.ok(!/fetch\(|caches\.|serviceWorker/.test(src), 'aucune ressource, aucun cache');
    const sw = lire('public/sw.js');
    assert.ok(!sw.includes('recu-provisoire'), 'le worker ne met aucune page de reçu en cache');
    const html = lire('public/caisse-hors-ligne.html');
    assert.ok(html.includes('id="dlg-recu"') && html.includes('id="recu-imprimer"'));
});
