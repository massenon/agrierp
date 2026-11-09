import 'fake-indexeddb/auto';
import { IDBFactory } from 'fake-indexeddb';
import test from 'node:test';
import assert from 'node:assert/strict';
import { creerCoffre, dechiffrer } from '../../resources/js/hors-ligne/coffre.js';
import { ouvrirBase } from '../../resources/js/hors-ligne/base-locale.js';
import { ajouterVente } from '../../resources/js/hors-ligne/file-envoi.js';
import { creerSynchro } from '../../resources/js/hors-ligne/synchro.js';
import { jourBenin, lotsVendables, bandeSousRemanence, refusDuPanier, elevageApresVentes, lignesDeChaine } from '../../resources/js/hors-ligne/elevage-hors-ligne.js';
import { construireVente, MOTIFS } from '../../resources/js/hors-ligne/calculs-caisse.js';

/**
 * PWA-1b — produits rattachés à une espèce hors ligne : bande source, rémanence tirée, refus du web, effet d'une vente en attente sur la
 * bande et la fiche du jour. L'égalité de la chaîne avec le vrai PHP est prouvée par `parite-chaine.test.mjs`.
 */
const lapins = { id: 'b-lapins', code: 'LAP-1', species_id: 's-lap', species_code: 'cuniculture', stage: 'croissance', status: 'actif', is_active: true, initial_quantity: 40, current_quantity: 40 };
const poulets = { id: 'b-poul', code: 'VOL-1', species_id: 's-avi', species_code: 'aviculture', stage: 'croissance', status: 'actif', is_active: true, initial_quantity: 30, current_quantity: 30 };
const produits = [
    { id: 'p-lapin', name: 'Lapin vivant', species_id: 's-lap', categorie_effectif: null },
    { id: 'p-jeune', name: 'Poulet jeune', species_id: 's-avi', categorie_effectif: 'jeune' },
    { id: 'p-sans', name: 'Poulet sans catégorie', species_id: 's-avi', categorie_effectif: null },
    { id: 'p-oeufs', name: 'Œufs', species_id: null },
];

test('le jour du Bénin : UTC+1 toute l\'année', () => {
    assert.equal(jourBenin('2026-11-09T22:59:59Z'), '2026-11-09');
    assert.equal(jourBenin('2026-11-09T23:00:00Z'), '2026-11-10');
    assert.equal(jourBenin(Date.parse('2026-12-31T23:30:00Z')), '2027-01-01');
});

test('bandes proposées : même espèce, actives, non vides ; rémanence : un délai qui court encore ce jour-là', () => {
    const lots = [lapins, { ...lapins, id: 'archivee', status: 'archive' }, { ...lapins, id: 'vide', current_quantity: 0 }, { ...lapins, id: 'autre', species_id: 'x' }, { ...lapins, id: 'inactive', is_active: false }];
    assert.deepEqual(lotsVendables(produits[0], lots).map((l) => l.id), ['b-lapins']);
    assert.deepEqual(lotsVendables(produits[3], lots), []);
    const remanences = [{ lot_id: 'b-lapins', end_date: '2026-11-12' }];
    assert.equal(bandeSousRemanence('b-lapins', remanences, '2026-11-12'), true, 'le dernier jour compte');
    assert.equal(bandeSousRemanence('b-lapins', remanences, '2026-11-13'), false);
    assert.equal(bandeSousRemanence('b-poul', remanences, '2026-11-10'), false);
});

test('refus du panier : rémanence (phrase du web), volailles sans départ, produit sans catégorie, vente avant le départ', () => {
    const elevage = { lots: [lapins, poulets], fiches: [] };
    const l = (lot_id, product_id) => ({ lot_id, product_id, qty: 2 });
    assert.equal(refusDuPanier([l('b-lapins', 'p-lapin')], produits, elevage, [], '2026-11-10'), null, 'les lapins ne sont pas ventilés');
    const rem = refusDuPanier([l('b-lapins', 'p-lapin')], produits, elevage, [{ lot_id: 'b-lapins', end_date: '2026-11-20' }], '2026-11-10');
    assert.equal(rem.motif, 'Vente interdite - Bande LAP-1 sous remanence veterinaire active. Retirez ce sujet du panier avant de valider.');
    assert.equal(rem.motif, MOTIFS.remanenceValidation('LAP-1'));
    assert.equal(MOTIFS.remanenceAjout('LAP-1'), 'Vente interdite - Bande LAP-1 sous remanence veterinaire active. Blocage automatique du systeme.');
    assert.match(refusDuPanier([l('b-poul', 'p-jeune')], produits, elevage, [], '2026-11-10').motif, /^Vente refusée : l'effectif de départ par catégorie de la bande VOL-1 n'est pas saisi\./);

    const depart = { id: 'f1', lot_id: 'b-poul', entry_date: '2026-11-05', achat: 0, ne: 0, mort: 0, vente: 0, don: 0, effectif_final: 30, cat_depart_repro: 5, cat_depart_sevre: 5, cat_depart_jeune: 20 };
    const avecDepart = { lots: [lapins, poulets], fiches: [depart] };
    assert.equal(refusDuPanier([l('b-poul', 'p-jeune')], produits, avecDepart, [], '2026-11-10'), null);
    assert.equal(refusDuPanier([l('b-poul', 'p-sans')], produits, avecDepart, [], '2026-11-10').motif, "Vente refusée : le produit « Poulet sans catégorie » n'a pas de catégorie d'effectif (Reproducteur, Jeune ou Poussin). Renseignez-la dans « Modifier un produit » avant de le vendre sur une bande de volailles reproductrices.");
    assert.equal(refusDuPanier([l('b-poul', 'p-jeune')], produits, avecDepart, [], '2026-11-03').motif, "Vente refusée : la date de la vente (03/11/2026) précède l'effectif de départ de la bande (fixé le 05/11/2026).");
});

test('vente en attente : la bande et la fiche du jour se mettent à jour (rejouée au-dessus du tirage, jamais écrite dedans)', () => {
    const tire = { lots: [lapins], fiches: [{ id: 'f0', lot_id: 'b-lapins', entry_date: '2026-11-09', achat: 0, ne: 0, mort: 1, vente: 0, don: 0, effectif_final: 39 }] };
    const vente = (id, qty, sold_at) => ({ id, sold_at, lines: [{ product_id: 'p-lapin', lot_id: 'b-lapins', qty, manual_total_amount: 1000 }, { product_id: 'p-oeufs', lot_id: null, qty: 1, manual_total_amount: 100 }] });
    const apres = elevageApresVentes(tire, [vente('a', 3, '2026-11-10T08:00:00Z'), vente('b', 2, '2026-11-10T09:00:00Z')], produits);
    assert.equal(apres.lots[0].current_quantity, 34, '39 − 3 − 2');
    const fiche = apres.fiches.find((f) => f.entry_date === '2026-11-10');
    assert.equal(fiche.vente, 5, 'les deux ventes s\'ajoutent sur la fiche du jour');
    assert.equal(fiche.effectif_final, 34);
    assert.equal(tire.lots[0].current_quantity, 40, 'la copie tirée n\'est pas modifiée');
    assert.equal(tire.fiches.length, 1);
    assert.deepEqual(lignesDeChaine([{ product_id: 'p-oeufs', lot_id: null, qty: 1 }], produits), []);
    assert.equal(elevageApresVentes(tire, [], produits).lots[0].current_quantity, 40);
    // Une vente que la chaîne refuse (volailles sans départ) est ignorée ici : le serveur en jugera.
    const ignore = elevageApresVentes({ lots: [poulets], fiches: [] }, [{ id: 'c', sold_at: '2026-11-10T08:00:00Z', lines: [{ product_id: 'p-jeune', lot_id: 'b-poul', qty: 4 }] }], produits);
    assert.equal(ignore.lots[0].current_quantity, 30);
});

test('construireVente : la bande source part dans la ligne de vente (lot_id)', () => {
    const r = construireVente({ panier: [{ product_id: 'p-lapin', qty: 2, montant: 12000, lot_id: 'b-lapins' }], modePaiement: 'especes', id: 'v', instant: '2026-11-10T08:00:00.000Z', deviceId: 'pwa-x' });
    assert.equal(r.ok, true);
    assert.equal(r.vente.lines[0].lot_id, 'b-lapins');
});

// ---------------------------------------------------------------------------------------------------- tirage

const contexte = async () => ({ base: await ouvrirBase({ idb: new IDBFactory() }), cle: (await creerCoffre('4821', { iterations: 1000 })).cle });

function serveurElevage({ pages = 2, remanences = [{ id: 'r1', lot_id: 'b-lapins', end_date: '2026-11-20' }] } = {}) {
    const s = { pulls: 0, ventes: [] };
    const fiche = (k) => ({ id: `f${k}`, lot_id: 'b-lapins', entry_date: `2026-11-${String(k).padStart(2, '0')}`, achat: 0, ne: 0, mort: 0, vente: 0, don: 0, effectif_final: 40 });
    s.fetch = async (url, opts) => {
        const u = new URL(url, 'http://x');
        if (u.pathname === '/api/sync/pull') {
            s.pulls++;
            const n = Number(u.searchParams.get('page'));
            const j = { page: n, page_suivante: n < pages ? `p${n + 1}` : null, livestock_daily_entries: [fiche(n * 2 - 1), fiche(n * 2)] };
            if (n === 1) Object.assign(j, { tables_servies: ['products', 'product_categories', 'customers', 'company_settings', 'livestock_lots', 'livestock_daily_entries', 'veterinary_withdrawal_periods'], data_reset_at: null, products: [], product_categories: [], customers: [], company_settings: {}, livestock_lots: [lapins, { id: 'invalide' }], veterinary_withdrawal_periods: remanences });
            if (!j.page_suivante) j.server_time = '2026-11-10T09:00:00+01:00';
            return new Response(JSON.stringify(j), { status: 200 });
        }
        const corps = JSON.parse(opts.body);
        for (const v of corps.sales ?? []) s.ventes.push(v);
        return new Response(JSON.stringify({ sales: { accepted: (corps.sales ?? []).map((v) => v.id), rejected: [] } }), { status: 200 });
    };
    return s;
}
const synchroDe = (ctx, serveur) => creerSynchro({ base: ctx.base, cle: ctx.cle, jeton: 'J', deviceName: 'pwa-t', fetchFn: (...a) => serveur.fetch(...a), maintenant: () => new Date('2026-11-10T08:00:00Z') });
const lire = async (ctx, table) => dechiffrer(ctx.cle, await ctx.base.lire('referentiels', table));

test('tirage : bandes, fiches de TOUTES les pages et rémanences gardées (chiffrées) ; ligne invalide refusée', async () => {
    const ctx = await contexte();
    const serveur = serveurElevage();
    const r = await synchroDe(ctx, serveur).synchroniser();
    assert.equal(r.statut, 'ok');
    assert.deepEqual((await lire(ctx, 'livestock_lots')).map((l) => l.id), ['b-lapins'], 'la bande sans code ni stade est refusée');
    assert.deepEqual((await lire(ctx, 'livestock_daily_entries')).map((f) => f.id), ['f1', 'f2', 'f3', 'f4'], 'les deux pages sont accumulées');
    assert.equal((await lire(ctx, 'veterinary_withdrawal_periods')).length, 1);
    assert.ok(!JSON.stringify(await ctx.base.tout('referentiels')).includes('LAP-1'), 'aucun code de bande en clair');
});

test('tirage : une rémanence levée disparaît (table servie en entier) ; fiches et bandes sont fusionnées par identifiant', async () => {
    const ctx = await contexte();
    const serveur = serveurElevage({ pages: 1 });
    const s = synchroDe(ctx, serveur);
    await s.synchroniser();
    assert.equal((await lire(ctx, 'veterinary_withdrawal_periods')).length, 1);
    const serveur2 = serveurElevage({ pages: 1, remanences: [] });
    await synchroDe(ctx, serveur2).synchroniser();
    assert.equal((await lire(ctx, 'veterinary_withdrawal_periods')).length, 0, 'plus aucune rémanence');
    assert.equal((await lire(ctx, 'livestock_daily_entries')).length, 2, 'fusionnées par identifiant, jamais en double');
});

test('synchro : des ventes acceptées déclenchent un second tirage (l\'effectif de la bande ne « remonte » pas)', async () => {
    const ctx = await contexte();
    const serveur = serveurElevage({ pages: 1 });
    await ajouterVente(ctx, { id: 'v1', payment_mode: 'especes', subtotal: 1, discount: 0, total: 1, lines: [] });
    await synchroDe(ctx, serveur).synchroniser();
    assert.equal(serveur.ventes.length, 1);
    assert.equal(serveur.pulls, 2, 'un tirage avant l\'envoi, un après');
    const sans = serveurElevage({ pages: 1 });
    await synchroDe(await contexte(), sans).synchroniser();
    assert.equal(sans.pulls, 1, 'rien envoyé : un seul tirage');
});
