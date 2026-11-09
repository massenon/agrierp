import 'fake-indexeddb/auto';
import { IDBFactory } from 'fake-indexeddb';
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { creerCoffre, dechiffrer } from '../../resources/js/hors-ligne/coffre.js';
import { ouvrirBase } from '../../resources/js/hors-ligne/base-locale.js';
import { ajouterVente, lister, lireJournal } from '../../resources/js/hors-ligne/file-envoi.js';
import { creerSynchro } from '../../resources/js/hors-ligne/synchro.js';
import {
    construireVente, livraisonRetenue, totalVente, validerLivraison, lireNombre, MOTIFS, MODES_PAIEMENT, LIBELLES_PAIEMENT, MODES_LIVRAISON,
} from '../../resources/js/hors-ligne/calculs-caisse.js';
import { validerClient, ajouterClient, clientsEnAttente, clientsVisibles, MOTIFS_CLIENT } from '../../resources/js/hors-ligne/clients-hors-ligne.js';

/**
 * PWA-1b — la caisse COMPLÈTE hors ligne : livraison facturée, vente sur avance, client créé hors ligne. Les valeurs sont calculées
 * à la main ; l'égalité avec le vrai PHP est prouvée par `parite-php.test.mjs`.
 */
const ITER = 1000;
const contexte = async () => {
    const base = await ouvrirBase({ idb: new IDBFactory() });
    const { cle } = await creerCoffre('4821', { iterations: ITER });
    return { base, cle };
};
const panier = [{ product_id: 'p1', qty: 2, montant: 11800 }];
const entree = (plus = {}) => ({ panier, remise: 0, modePaiement: 'especes', especesRecues: null, facture: { facture_type: 'simple' }, id: 'v1', instant: '2026-11-09T08:00:00.000Z', deviceId: 'pwa-x', ...plus });

// ------------------------------------------------------------------------------------------------ livraison

test('livraison : seuls les frais d\'une livraison FACTURÉE entrent dans le total (entiers, demi vers le haut, jamais négatifs)', () => {
    assert.equal(livraisonRetenue({ concernee: true, mode: 'facturee', frais: 2500 }), 2500);
    assert.equal(livraisonRetenue({ concernee: true, mode: 'facturee', frais: 2500.5 }), 2501);
    assert.equal(livraisonRetenue({ concernee: true, mode: 'facturee', frais: 0.5 }), 1);
    assert.equal(livraisonRetenue({ concernee: true, mode: 'facturee', frais: -10 }), 0);
    assert.equal(livraisonRetenue({ concernee: true, mode: 'facturee', frais: null }), 0);
    for (const mode of ['gratuite', 'client', 'incluse']) assert.equal(livraisonRetenue({ concernee: true, mode, frais: 5000 }), 0, mode);
    assert.equal(livraisonRetenue({ concernee: false, mode: 'facturee', frais: 5000 }), 0, 'livraison non concernée');
    assert.equal(totalVente([{ manual_total_amount: 11800 }], 1800, 2500), 12500);
    assert.equal(totalVente([{ manual_total_amount: 1000 }], 5000, 300), 300, 'la remise ne descend pas sous 0, la livraison s\'ajoute');
});

test('vente avec livraison facturée : total, colonnes de livraison, monnaie sur le total complet', () => {
    const r = construireVente(entree({
        livraison: { concernee: true, mode: 'facturee', frais: 2500, adresse: ' Pobè, route de Kétou ', contact: '' },
        especesRecues: 20000,
    }));
    assert.equal(r.ok, true);
    const v = r.vente;
    assert.equal(v.subtotal, 11800);
    assert.equal(v.total, 14300);
    assert.equal(v.delivery_mode, 'facturee');
    assert.equal(v.delivery_fee, 2500);
    assert.equal(v.delivery_in_total, true);
    assert.equal(v.delivery_address, 'Pobè, route de Kétou');
    assert.equal(v.delivery_contact, null);
    assert.equal(v.change_due, 5700);

    const insuffisant = construireVente(entree({ livraison: { concernee: true, mode: 'facturee', frais: 2500 }, especesRecues: 12000 }));
    assert.equal(insuffisant.ok, false);
    assert.equal(insuffisant.motif, MOTIFS.especesInsuffisantes, 'le montant reçu se compare au total AVEC la livraison');
});

test('vente sans livraison concernée : colonnes nulles, aucun frais', () => {
    const v = construireVente(entree({ livraison: { concernee: false, mode: 'facturee', frais: 9999, adresse: 'x' } })).vente;
    assert.equal(v.total, 11800);
    assert.equal(v.delivery_mode, null);
    assert.equal(v.delivery_fee, 0);
    assert.equal(v.delivery_in_total, false);
    assert.equal(v.delivery_address, null);
    const sans = construireVente(entree()).vente;
    assert.equal(sans.delivery_mode, null);
});

test('livraison : refus avec les mots du serveur (mode inconnu, adresse trop longue, frais illisibles)', () => {
    assert.equal(validerLivraison({ concernee: true, mode: 'drone' }).motif, "La valeur du champ mode de livraison n'est pas autorisée.");
    assert.equal(validerLivraison({ concernee: true, mode: 'gratuite', adresse: 'a'.repeat(256) }).motif, 'Le champ adresse de livraison dépasse le maximum autorisé (255).');
    assert.equal(validerLivraison({ concernee: true, mode: 'facturee', frais: Number.NaN }).motif, 'Le champ frais de livraison doit être un nombre entier.');
    assert.equal(validerLivraison({ concernee: true, mode: 'gratuite', adresse: 'a'.repeat(255) }).ok, true);
    assert.equal(validerLivraison({ concernee: false, mode: 'drone' }).ok, true, 'non concernée : rien à valider');
    const r = construireVente(entree({ livraison: { concernee: true, mode: 'drone' } }));
    assert.deepEqual([r.ok, r.champ], [false, 'delivery_mode']);
    assert.equal(lireNombre('2 500,5'), 2500.5);
    assert.equal(lireNombre('abc'), null);
    assert.deepEqual(Object.keys(MODES_LIVRAISON), ['gratuite', 'client', 'incluse', 'facturee']);
});

// ---------------------------------------------------------------------------------------------- vente sur avance

test('vente sur avance : un client est exigé, avec la phrase de la caisse web ; le mode a son libellé du web', () => {
    assert.ok(MODES_PAIEMENT.includes('avance'));
    assert.equal(LIBELLES_PAIEMENT.avance, "Déduire de l'avance");
    const sans = construireVente(entree({ modePaiement: 'avance' }));
    assert.deepEqual([sans.ok, sans.champ, sans.motif], [false, 'customer_id', 'Une vente sur avance exige un client : choisissez-le dans la liste ou créez-le avec le bouton « + ».']);
    const avec = construireVente(entree({ modePaiement: 'avance', clientId: 'k1' }));
    assert.equal(avec.ok, true);
    assert.equal(avec.vente.payment_mode, 'avance');
    assert.equal(avec.vente.cash_received, null, 'pas d\'espèces reçues');
    assert.equal(avec.vente.change_due, null);
});

// -------------------------------------------------------------------------------------- client créé hors ligne

test('client : nom obligatoire, téléphone 30, IFU 13 chiffres ; saisie normalisée', () => {
    assert.deepEqual(validerClient({ name: '  Awa Kpossou ', phone: ' 0197112233', ifu: '3201 2345 67890' }), { ok: true, valeurs: { name: 'Awa Kpossou', phone: '0197112233', ifu: '3201234567890' } });
    assert.deepEqual(validerClient({ name: 'Awa' }), { ok: true, valeurs: { name: 'Awa', phone: null, ifu: null } });
    assert.equal(validerClient({ name: '' }).motif, MOTIFS_CLIENT.nomObligatoire);
    assert.equal(validerClient({ name: 'a'.repeat(151) }).motif, 'Le champ nom dépasse le maximum autorisé (150).');
    assert.equal(validerClient({ name: 'a', phone: '9'.repeat(31) }).motif, 'Le champ téléphone dépasse le maximum autorisé (30).');
    assert.equal(validerClient({ name: 'a', ifu: '123' }).motif, "L'IFU du client doit comporter 13 chiffres (laissez-le vide pour un client sans IFU).");
});

const serveurClients = ({ merge = {}, refuse = [] } = {}) => {
    const s = { appels: [], clients: [], ventes: [] };
    s.fetch = async (url, opts) => {
        const u = new URL(url, 'http://x');
        const corps = opts.body ? JSON.parse(opts.body) : null;
        s.appels.push({ chemin: u.pathname, corps });
        if (u.pathname === '/api/sync/pull') {
            return new Response(JSON.stringify({ page: 1, page_suivante: null, tables_servies: ['products', 'product_categories', 'customers', 'company_settings'], data_reset_at: null, products: [], product_categories: [], customers: [{ id: 'k-serveur', name: 'Awa Kpossou' }], company_settings: { company_name: 'F' }, server_time: '2026-11-09T09:00:00+01:00' }), { status: 200 });
        }
        const sortie = {};
        if (corps.customers) {
            const accepted = []; const rejected = []; const merged = [];
            for (const c of corps.customers) {
                if (refuse.includes(c.id)) rejected.push({ id: c.id, reason: 'Le champ nom est obligatoire.' });
                else { accepted.push(c.id); s.clients.push(c); if (merge[c.id]) merged.push({ id: c.id, id_serveur: merge[c.id], motif: 'fusion' }); }
            }
            sortie.customers = { accepted, rejected, merged };
        }
        if (corps.sales) {
            const accepted = [];
            for (const v of corps.sales) { s.ventes.push(v); accepted.push(v.id); }
            sortie.sales = { accepted, rejected: [] };
        }
        return new Response(JSON.stringify(sortie), { status: 200 });
    };
    return s;
};
const synchroDe = (ctx, serveur) => creerSynchro({ base: ctx.base, cle: ctx.cle, jeton: 'J', deviceName: 'pwa-test', fetchFn: (...a) => serveur.fetch(...a), maintenant: () => new Date('2026-11-09T08:05:00Z') });
const nouveauClient = (ctx, id, nom = 'Awa Kpossou', tel = '0197112233') => ajouterClient(ctx, { id, valeurs: { name: nom, phone: tel, ifu: null }, instant: '2026-11-09T08:00:00.000Z', deviceId: 'pwa-test' });

test('client créé hors ligne : chiffré au repos, proposé à la vente, jamais perdu', async () => {
    const ctx = await contexte();
    await nouveauClient(ctx, 'c1111111-1111-4111-8111-111111111111', 'KPOGNON Séraphin', '0197000099');
    const brut = JSON.stringify(await ctx.base.tout('referentiels'));
    assert.ok(!brut.includes('KPOGNON') && !brut.includes('0197000099'), 'aucun clair dans le stockage');
    assert.equal((await clientsEnAttente(ctx)).length, 1);
    const visibles = clientsVisibles([{ id: 'k1', name: 'Awa' }, { id: 'k2', name: 'Zoé', is_active: false }], await clientsEnAttente(ctx));
    assert.deepEqual(visibles.map((c) => c.name), ['Awa', 'KPOGNON Séraphin'], 'tri par nom, archivés exclus');
    assert.equal(clientsVisibles([{ id: 'c1111111-1111-4111-8111-111111111111', name: 'Doublon' }], await clientsEnAttente(ctx)).length, 1, 'un identifiant une fois');
});

test('synchro : le client part AVANT sa vente, est acquitté puis retiré ; un renvoi ne le recrée pas', async () => {
    const ctx = await contexte();
    const serveur = serveurClients();
    const id = 'c2222222-2222-4222-8222-222222222222';
    await nouveauClient(ctx, id);
    await ajouterVente(ctx, { id: 'v-1', payment_mode: 'avance', customer_id: id, total: 100, subtotal: 100, discount: 0, lines: [] });
    const r = await synchroDe(ctx, serveur).synchroniser();
    assert.equal(r.statut, 'ok');
    const pushes = serveur.appels.filter((a) => a.chemin === '/api/sync/push');
    assert.equal(pushes.length, 2);
    assert.ok(pushes[0].corps.customers && !pushes[0].corps.sales, 'les clients d\'abord');
    assert.deepEqual(Object.keys(pushes[0].corps.customers[0]).sort(), ['id', 'ifu', 'is_active', 'name', 'phone']);
    assert.ok(pushes[1].corps.sales);
    assert.equal((await clientsEnAttente(ctx)).length, 0, 'acquitté : retiré de la file');
    assert.equal((await lister(ctx, 'synced')).length, 1);
    await synchroDe(ctx, serveur).synchroniser();
    assert.equal(serveur.clients.length, 1, 'rien n\'est renvoyé');
});

test('synchro : client fusionné avec une fiche du serveur → les ventes en file passent à son identifiant', async () => {
    const ctx = await contexte();
    const id = 'c3333333-3333-4333-8333-333333333333';
    const serveur = serveurClients({ merge: { [id]: 'k-serveur' } });
    await nouveauClient(ctx, id);
    await ajouterVente(ctx, { id: 'v-2', payment_mode: 'credit', customer_id: id, total: 100, subtotal: 100, discount: 0, lines: [] });
    await synchroDe(ctx, serveur).synchroniser();
    assert.equal(serveur.ventes[0].customer_id, 'k-serveur', 'la vente part avec la fiche du serveur');
    assert.equal((await clientsEnAttente(ctx)).length, 0);
});

test('synchro : client refusé → gardé avec son motif français, journalisé, jamais renvoyé en boucle', async () => {
    const ctx = await contexte();
    const id = 'c4444444-4444-4444-8444-444444444444';
    const serveur = serveurClients({ refuse: [id] });
    await nouveauClient(ctx, id);
    const s = synchroDe(ctx, serveur);
    await s.synchroniser();
    const [c] = await clientsEnAttente(ctx);
    assert.equal(c.sync_status, 'conflict');
    assert.equal(c.motif, 'Le champ nom est obligatoire.');
    assert.match((await lireJournal(ctx))[0].motif, /Client refusé : Le champ nom est obligatoire\./);
    const avant = serveur.appels.filter((a) => a.corps?.customers).length;
    await s.synchroniser();
    assert.equal(serveur.appels.filter((a) => a.corps?.customers).length, avant, 'pas de renvoi');
});

test('synchro hors ligne : le client reste en file, rien n\'est perdu', async () => {
    const ctx = await contexte();
    await nouveauClient(ctx, 'c5555555-5555-4555-8555-555555555555');
    const serveur = serveurClients();
    const coupe = serveur.fetch;
    serveur.fetch = async (url, opts) => { if (new URL(url, 'http://x').pathname === '/api/sync/push') throw new TypeError('Failed to fetch'); return coupe(url, opts); };
    const r = await synchroDe(ctx, serveur).synchroniser();
    assert.equal(r.statut, 'hors_ligne');
    assert.equal((await clientsEnAttente(ctx)).length, 1);
    assert.deepEqual(await dechiffrer(ctx.cle, await ctx.base.lire('referentiels', 'clients_a_envoyer')).then((l) => l.map((c) => c.sync_status)), ['pending']);
});

// ----------------------------------------------------------------------------------- garde de sources

test('garde : l\'écran construit son DOM sans innerHTML ; la page porte le bouton « + », « Livraison » et le mode avance', () => {
    const app = readFileSync('resources/js/hors-ligne/caisse-app.js', 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
    assert.ok(!/innerHTML|outerHTML|insertAdjacentHTML|document\.write/.test(app));
    const html = readFileSync('public/caisse-hors-ligne.html', 'utf8');
    for (const id of ['btn-nouveau-client', 'dlg-client', 'btn-livraison', 'dlg-livraison', 'ligne-livraison']) assert.ok(html.includes(`id="${id}"`), id);
    assert.ok(html.includes('<option value="avance">Déduire de l\'avance</option>'));
    const sw = readFileSync('public/sw.js', 'utf8');
    assert.match(sw, /const VERSION = 'agrierp-v(\d+)';/);
    assert.ok(Number(/const VERSION = 'agrierp-v(\d+)';/.exec(sw)[1]) >= 8, 'les fichiers de la caisse ont changé : VERSION incrémentée');
});
