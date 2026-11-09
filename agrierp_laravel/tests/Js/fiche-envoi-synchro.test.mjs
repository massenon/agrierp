import 'fake-indexeddb/auto';
import { IDBFactory } from 'fake-indexeddb';
import test from 'node:test';
import assert from 'node:assert/strict';
import { creerCoffre } from '../../resources/js/hors-ligne/coffre.js';
import { ouvrirBase } from '../../resources/js/hors-ligne/base-locale.js';
import { ajouterVente, lister, lireJournal } from '../../resources/js/hors-ligne/file-envoi.js';
import { creerSynchro } from '../../resources/js/hors-ligne/synchro.js';
import { garderSaisie, saisiesEnAttente, remettreFicheEnFile, abandonnerFiche, appliquerSaisies, aEnvoyerFiches } from '../../resources/js/hors-ligne/fiche-lapins-saisie.js';

/**
 * PWA-3 (fiche lapins, É4) — la FILE D'ENVOI des fiches : machine d'états (pending → synced à l'accusé seulement ; refus → conflict avec le motif
 * du serveur, journalisé, jamais renvoyé en boucle ; reprise manuelle ; abandon), ordre (fiches AVANT ventes), tirage de confirmation, copie
 * locale rejouée tant que le serveur ne la contient pas. L'égalité avec le vrai serveur est prouvée par `parite-fiche-envoi.test.mjs`.
 */
const contexte = async () => {
    const base = await ouvrirBase({ idb: new IDBFactory() });
    const { cle } = await creerCoffre('4821', { iterations: 1000 });
    return { base, cle };
};
const LOT = { id: '00000000-0000-4000-8000-000000000001', code: 'LAP-1', species_code: 'cuniculture', stage: 'engraissement', initial_quantity: 40, current_quantity: 40, status: 'actif', is_active: true };
const FICHE = (id, jour) => ({ id, lot_id: LOT.id, entry_date: jour, achat: 0, ne: 0, mort: 3, vente: 0, don: 0, effectif_final: 37, mort_repro: 0, mort_sevre: 0, mort_jeune: 3, don_repro: 0, don_sevre: 0, don_jeune: 0, passage_sevre_jeune: 0, cat_depart_repro: 0, cat_depart_sevre: 0, cat_depart_jeune: 40, sync_status: 'pending' });
const saisie = (ctx, id, jour = '2026-11-08') => garderSaisie(ctx, { id_fiche: id, lot_id: LOT.id, jour, saisie: {}, fiche: FICHE(id, jour), cree_le: '2026-11-09T08:00:00.000Z' });
const serveurFiches = ({ refuse = {}, refuseSoin = {} } = {}) => {
    const s = { appels: [], fiches: [] };
    s.fetch = async (url, opts) => {
        const u = new URL(url, 'http://x');
        const corps = opts.body ? JSON.parse(opts.body) : null;
        s.appels.push({ chemin: u.pathname, cles: corps ? Object.keys(corps) : [], corps });
        if (u.pathname === '/api/sync/pull') {
            return new Response(JSON.stringify({ page: 1, page_suivante: null, tables_servies: ['products', 'product_categories', 'customers', 'company_settings', 'livestock_lots', 'livestock_daily_entries'], data_reset_at: null, products: [], product_categories: [], customers: [], company_settings: { company_name: 'F' }, livestock_lots: [LOT], livestock_daily_entries: s.fiches, server_time: '2026-11-09T09:00:00+01:00' }), { status: 200 });
        }
        const sortie = {};
        if (corps.livestock_daily_entries) {
            const accepted = []; const rejected = [];
            for (const f of corps.livestock_daily_entries) {
                if (refuse[f.id]) rejected.push({ id: f.id, reason: refuse[f.id] });
                else { accepted.push(f.id); s.fiches.push({ ...f, effectif_final: 37 }); }
            }
            sortie.livestock_daily_entries = { accepted, rejected, merged: [] };
        }
        if (corps.veterinary_records) {
            sortie.veterinary_records = { accepted: corps.veterinary_records.filter((x) => !refuseSoin[x.id]).map((x) => x.id), rejected: corps.veterinary_records.filter((x) => refuseSoin[x.id]).map((x) => ({ id: x.id, reason: refuseSoin[x.id] })) };
        }
        if (corps.sales) sortie.sales = { accepted: corps.sales.map((v) => v.id), rejected: [] };
        return new Response(JSON.stringify(sortie), { status: 200 });
    };
    return s;
};
const synchroDe = (ctx, serveur, heure = '2026-11-09T08:05:00Z') => creerSynchro({ base: ctx.base, cle: ctx.cle, jeton: 'J', deviceName: 'pwa-test', fetchFn: (...a) => serveur.fetch(...a), maintenant: () => new Date(heure) });
const A = 'a1111111-1111-4111-8111-111111111111';

test('envoi : la fiche part avec la clé du poste, AVANT les ventes ; synced à l\'accusé seulement ; un renvoi ne repart pas', async () => {
    const ctx = await contexte();
    const serveur = serveurFiches();
    await saisie(ctx, A);
    await ajouterVente(ctx, { id: 'v1111111-1111-4111-8111-111111111111', sold_at: '2026-11-09T08:00:00Z', total: 100, payment_mode: 'especes', lines: [{ product_id: 'p', qty: 1, montant: 100 }] });
    const r = await synchroDe(ctx, serveur).synchroniser({ manuel: true });
    assert.equal(r.statut, 'ok');
    const pushs = serveur.appels.filter((a) => a.chemin === '/api/sync/push');
    assert.deepEqual(pushs.map((p) => p.cles.find((c) => c === 'livestock_daily_entries' || c === 'sales')), ['livestock_daily_entries', 'sales'], 'fiches avant ventes');
    assert.equal(pushs[0].corps.livestock_daily_entries[0].vente, 0);
    assert.equal(pushs[0].corps.livestock_daily_entries[0].id, A);
    assert.equal(serveur.appels.filter((a) => a.chemin === '/api/sync/pull').length, 2, 'tirage initial, puis UN tirage de confirmation après les envois');
    const liste = await saisiesEnAttente(ctx);
    assert.equal(liste[0].sync_status, 'synced');
    await synchroDe(ctx, serveur).synchroniser({ manuel: true });
    assert.equal(serveur.appels.filter((a) => a.chemin === '/api/sync/push' && a.corps.livestock_daily_entries).length, 1, 'jamais renvoyée');
});

test('copie locale : rejouée tant qu\'un tirage ultérieur ne contient pas la fiche, retirée ensuite', async () => {
    const ctx = await contexte();
    const serveur = serveurFiches();
    await saisie(ctx, A);
    await synchroDe(ctx, serveur, '2026-11-09T08:05:00Z').synchroniser({ manuel: true });
    assert.equal((await saisiesEnAttente(ctx)).length, 1, 'acquittée mais gardée : pas de « remontée » de l\'effectif');
    await synchroDe(ctx, serveur, '2026-11-09T08:05:03Z').synchroniser({ manuel: true });
    assert.equal((await saisiesEnAttente(ctx)).length, 1, 'un tirage dans les 5 s qui suivent l\'accusé ne suffit pas');
    await synchroDe(ctx, serveur, '2026-11-09T08:06:00Z').synchroniser({ manuel: true });
    assert.equal((await saisiesEnAttente(ctx)).length, 0, 'un tirage plus tardif la contient : la copie locale est retirée');
    const rejouee = appliquerSaisies({ lots: [LOT], fiches: [] }, [{ id_fiche: A, lot_id: LOT.id, jour: '2026-11-08', saisie: { mortChair: 3, departRepro: 0, departSevre: 0, departJeune: 40 }, sync_status: 'synced' }], {});
    assert.equal(rejouee.fiches.length, 1, 'une saisie acquittée est encore rejouée');
    assert.equal(appliquerSaisies({ lots: [LOT], fiches: [] }, [{ id_fiche: A, lot_id: LOT.id, jour: '2026-11-08', saisie: {}, sync_status: 'conflict' }], {}).fiches.length, 0, 'une saisie refusée n\'est pas rejouée');
});

test('refus : conflict + motif français du serveur, journalisé, jamais renvoyé en boucle ; reprise manuelle ; abandon', async () => {
    const ctx = await contexte();
    const motif = "L'exercice 2025 est clôturé : aucune saisie ne peut être datée du 08/11/2025.";
    const serveur = serveurFiches({ refuse: { [A]: motif } });
    await saisie(ctx, A);
    const r = await synchroDe(ctx, serveur).synchroniser({ manuel: true });
    assert.equal(r.statut, 'ok');
    assert.match(r.message, /1 fiche\(s\) d'élevage refusée\(s\)/);
    const [it] = await saisiesEnAttente(ctx);
    assert.equal(it.sync_status, 'conflict');
    assert.equal(it.motif, motif);
    assert.ok((await lireJournal(ctx)).some((j) => j.motif.includes(motif)), 'journalisé');
    await synchroDe(ctx, serveur).synchroniser({ manuel: true });
    assert.equal(serveur.appels.filter((a) => a.corps?.livestock_daily_entries).length, 1, 'jamais renvoyée en boucle');
    assert.deepEqual(aEnvoyerFiches(await saisiesEnAttente(ctx)), []);

    await remettreFicheEnFile(ctx, A);
    assert.equal((await saisiesEnAttente(ctx))[0].sync_status, 'pending', 'reprise manuelle');
    await synchroDe(ctx, serveur).synchroniser({ manuel: true });
    assert.equal(serveur.appels.filter((a) => a.corps?.livestock_daily_entries).length, 2, 'renvoyée une fois après la reprise');
    await abandonnerFiche(ctx, A);
    assert.equal((await saisiesEnAttente(ctx)).length, 0);
});

test('déconnexion : les fiches en attente et les clients créés hors ligne sont comptés (en clair, sans PIN)', async () => {
    const { totalEnAttente, listeEnAttente } = await import('../../resources/js/hors-ligne/base-locale.js');
    const { ajouterClient, retirerClients } = await import('../../resources/js/hors-ligne/clients-hors-ligne.js');
    const ctx = await contexte();
    assert.deepEqual(await ctx.base.compterTout(), { pending: 0, conflict: 0, synced: 0, fiches: 0, clients: 0, soins: 0 });
    await saisie(ctx, A);
    await saisie(ctx, 'b2222222-2222-4222-8222-222222222222', '2026-11-07');
    await ajouterClient(ctx, { id: 'c1111111-1111-4111-8111-111111111111', valeurs: { name: 'Awa', phone: null, ifu: null }, instant: '2026-11-09T08:00:00.000Z', deviceId: 'pwa-test' });
    await ajouterVente(ctx, { id: 'v1111111-1111-4111-8111-111111111111', sold_at: '2026-11-09T08:00:00Z', total: 100, payment_mode: 'especes', lines: [] });
    let c = await ctx.base.compterTout();
    assert.equal(c.fiches, 2); assert.equal(c.clients, 1); assert.equal(c.pending, 1);
    assert.equal(totalEnAttente(c), 4);
    assert.equal(listeEnAttente(c), "1 vente(s), 2 fiche(s) d'élevage et 1 client(s) créé(s) hors ligne");
    assert.equal(listeEnAttente({ pending: 0, conflict: 0, fiches: 0, clients: 3 }), '3 client(s) créé(s) hors ligne');
    const brut = JSON.stringify(await ctx.base.tout('meta'));
    assert.ok(!brut.includes('Awa') && !brut.includes('LAP-1'), 'seul un nombre est en clair');
    await abandonnerFiche(ctx, A);
    await retirerClients(ctx, ['c1111111-1111-4111-8111-111111111111']);
    c = await ctx.base.compterTout();
    assert.equal(c.fiches, 1); assert.equal(c.clients, 0);
    // acquittée (synced) : plus à perdre
    const serveur = serveurFiches();
    await synchroDe(ctx, serveur).synchroniser({ manuel: true });
    assert.equal((await ctx.base.compterTout()).fiches, 0, 'une fiche acquittée par le serveur n\'est plus comptée');
});

test('soins (prophylaxie) : envoyés après les fiches et AVANT les ventes avec la rémanence ; refus = conflict + motif ; comptés à la déconnexion', async () => {
    const { garderSoins, soinsEnAttente, remettreSoinEnFile, aEnvoyerSoins } = await import('../../resources/js/hors-ligne/fiche-lapins-prophylaxie.js');
    const ctx = await contexte();
    const S1 = 's1111111-1111-4111-8111-111111111111'; const S2 = 's2222222-2222-4222-8222-222222222222';
    const soin = (id) => ({ id, lot_id: LOT.id, action_type: 'Vermifuge', product_used: 'Ivermectine', dose: '1 ml', vet_name: null, symptomes: null, cost: null, record_date: '2026-11-09', withdrawal_days: 5, is_active: true });
    await garderSoins(ctx, [soin(S1), soin(S2)]);
    await saisie(ctx, A);
    await ajouterVente(ctx, { id: 'v1111111-1111-4111-8111-111111111111', sold_at: '2026-11-09T08:00:00Z', total: 100, payment_mode: 'especes', lines: [] });
    assert.equal((await ctx.base.compterTout()).soins, 2);
    const serveur = serveurFiches({ refuseSoin: { [S2]: 'Le champ action_type est obligatoire.' } });
    const r = await synchroDe(ctx, serveur).synchroniser({ manuel: true });
    assert.match(r.message, /1 soin\(s\) refusé\(s\)/);
    const pushs = serveur.appels.filter((a) => a.chemin === '/api/sync/push');
    assert.deepEqual(pushs.map((p) => p.cles.find((c) => ['livestock_daily_entries', 'veterinary_records', 'sales'].includes(c))), ['livestock_daily_entries', 'veterinary_records', 'sales']);
    const envoye = pushs[1].corps.veterinary_records[0];
    assert.equal(envoye.withdrawal_days, 5, 'la rémanence part avec le soin : le serveur crée la période');
    assert.equal(envoye.device_id, 'pwa-test');
    const liste = await soinsEnAttente(ctx);
    assert.equal(liste.find((x) => x.id === S1).sync_status, 'synced');
    assert.equal(liste.find((x) => x.id === S2).sync_status, 'conflict');
    assert.equal(liste.find((x) => x.id === S2).motif, 'Le champ action_type est obligatoire.');
    assert.equal((await ctx.base.compterTout()).soins, 1, 'seul le soin refusé reste à perdre');
    await synchroDe(ctx, serveur).synchroniser({ manuel: true });
    assert.equal(serveur.appels.filter((a) => a.corps?.veterinary_records).length, 1, 'jamais renvoyé en boucle');
    await remettreSoinEnFile(ctx, S2);
    assert.deepEqual(aEnvoyerSoins(await soinsEnAttente(ctx)).map((x) => x.id), [S2], 'reprise manuelle');
});
