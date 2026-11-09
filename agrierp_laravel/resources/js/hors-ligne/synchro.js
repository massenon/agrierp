/**
 * PWA-1 — SYNCHRONISATION : LE MÊME PROTOCOLE QUE LE POSTE (`/api/sync/pull` puis `/api/sync/push`), jamais un second.
 *
 *   1. TIRER d'abord : `GET /api/sync/pull?page=1[&since=<server_time>]`, puis `page=n&curseur_page=<page_suivante>` jusqu'à
 *      `page_suivante: null`. Le curseur est le `server_time` rendu par le SERVEUR à la DERNIÈRE page (jamais l'horloge
 *      de l'appareil) ; il n'avance qu'une fois toutes les pages absorbées, en UNE transaction. Seules les tables que le
 *      compte lit (`tables_servies`) et que la caisse utilise sont gardées ; si `tables_servies` change : tirage COMPLET.
 *   2. PUIS ENVOYER : `POST /api/sync/push` { device_id, data_reset_at, sales: [...] } par lots (413 : on réduit) ;
 *      une vente devient `synced` SEULEMENT après l'accusé (`sales.accepted`), `conflict` + motif français sinon ;
 *      renvoyer une vente que le serveur connaît n'est PAS une erreur (idempotence par UUID).
 *   3. 401/403 SUSPEND la synchronisation automatique (les ventes restent) ; 5xx / réseau : réessais 30 s, 2 min, 5 min,
 *      15 min, 1 h ; un refus 4xx n'est pas réessayé. Jamais deux synchronisations en même temps.
 *
 * Ce module ne contient AUCUNE règle métier : le serveur décide, numérote, écrit stock et comptabilité.
 */

import { lotAEnvoyer, marquerSynced, marquerConflit, compterTentative, nettoyerSynced, reaffecterClient, journaliser } from './file-envoi.js';
import { clientsEnAttente, aEnvoyer, retirerClients, refuserClient, clientEnJson } from './clients-hors-ligne.js';
import { chiffrer, dechiffrer } from './coffre.js';
import { aEnvoyerFiches, ficheEnJson, marquerFicheConflit, marquerFichesSynced, retirerFichesSynced, saisiesEnAttente } from './fiche-lapins-saisie.js';
import { aEnvoyerSoins, soinEnJson, marquerSoinsSynced, marquerSoinConflit, retirerSoinsSynced, soinsEnAttente } from './fiche-lapins-prophylaxie.js';
import { classerReponse, delaiDeReessai, heureDuServeur } from './etat.js';

/** Tables gardées par la caisse hors ligne (le reste du tirage est ignoré, jamais stocké). */
export const TABLES_GARDEES = [
    'products', 'product_categories', 'customers', 'company_settings',
    // PWA-1b — produits rattachés à une espèce : bandes, fiches journalières (chaîne d'effectif) et rémanences, sous le droit de lecture du compte.
    'livestock_lots', 'livestock_daily_entries', 'veterinary_withdrawal_periods',
    // PWA-3 (fiche lapins, É1) — barèmes de rationnement, prophylaxie, soins du mois, transferts, types de provende, exercices (lecture seule).
    'feed_ration_standards', 'prophylaxis_schedule_standards', 'veterinary_records', 'livestock_transfers', 'feed_types', 'fiscal_years',
    // PWA-3 (É5) — règle de terrain (seuil critique d'autonomie), lue seule.
    'field_survey_entries',
    // PWA-3 (délai fournisseur constaté) — bons de commande reçus et achats qui les ont reçus (`view-achats`), réduits à ce que le calcul lit.
    'purchase_orders', 'purchases',
    // PWA-3 (prophylaxie du jour) — saillies : le jour de cycle d'une bande en reproduction se compte depuis la dernière.
    'livestock_reproduction_events',
];
/** Familles PAGINÉES par le serveur : leurs lignes arrivent sur TOUTES les pages (les autres tables, sur la première seulement). */
export const TABLES_PAGINEES = ['livestock_daily_entries', 'veterinary_records', 'livestock_transfers', 'purchases', 'livestock_reproduction_events'];
/** Tables servies EN ENTIER à chaque tirage (jamais incrémentales) : leur copie est remplacée, une rémanence levée disparaît. */
export const TABLES_COMPLETES = ['veterinary_withdrawal_periods', 'feed_ration_standards', 'prophylaxis_schedule_standards', 'feed_types', 'fiscal_years', 'field_survey_entries', 'purchase_orders'];
const COLONNES_ENTREPRISE = ['company_name', 'tva_enabled', 'tva_default_rate', 'mecef_actif'];
export const TAILLE_LOT = 20;
const TIMEOUT_MS = 30_000;

export const MESSAGES = {
    suspendu: 'Session expirée ou appareil révoqué : reconnectez-vous (Mode hors ligne) pour reprendre la synchronisation. Vos ventes restent sur cet appareil.',
    injoignable: 'Serveur injoignable — les saisies restent sur cet appareil et partiront à la prochaine synchronisation.',
    termine: (recus, envoyes) => `Synchronisation terminée : ${recus} reçu(s), ${envoyes} envoyé(s).`,
    versionIncompatible: "La file d'envoi a été écrite par une version incompatible de l'application : rechargez la page.",
};

/** Absorption STRICTE d'une ligne : une ligne incohérente est REFUSÉE (comptée), jamais lissée. */
export function ligneValide(table, ligne) {
    if (!ligne || typeof ligne !== 'object' || typeof ligne.id !== 'string' || ligne.id === '') return false;
    if (table === 'products') return typeof ligne.name === 'string' && typeof ligne.pricing_mode === 'string';
    if (table === 'product_categories') return typeof ligne.label === 'string';
    if (table === 'customers') return typeof ligne.name === 'string';
    if (table === 'livestock_lots') return typeof ligne.code === 'string' && typeof ligne.stage === 'string';
    if (table === 'livestock_daily_entries') return typeof ligne.lot_id === 'string' && /^\d{4}-\d{2}-\d{2}/.test(String(ligne.entry_date ?? ''));
    if (table === 'feed_ration_standards') return typeof ligne.species_code === 'string' && typeof ligne.stage_label === 'string' && Number.isFinite(Number(ligne.ration_g_per_day));
    if (table === 'prophylaxis_schedule_standards') return typeof ligne.species_code === 'string' && typeof ligne.period_label === 'string';
    if (table === 'veterinary_records') return /^\d{4}-\d{2}-\d{2}/.test(String(ligne.record_date ?? ''));
    if (table === 'livestock_transfers') return typeof ligne.source_lot_id === 'string' && typeof ligne.target_lot_id === 'string' && /^\d{4}-\d{2}-\d{2}/.test(String(ligne.transfer_date ?? ''));
    if (table === 'feed_types') return typeof ligne.name === 'string';
    if (table === 'fiscal_years') return Number.isInteger(Number(ligne.year)) && typeof ligne.status === 'string';
    if (table === 'veterinary_withdrawal_periods') return typeof ligne.lot_id === 'string' && /^\d{4}-\d{2}-\d{2}/.test(String(ligne.end_date ?? ''));
    return true;
}

function garder(table, ligne) {
    if (table === 'company_settings') return ligne; // objet unique, traité à part
    // Réduits aux colonnes lues par `delaisFournisseurs` (le reste d'un achat ou d'un bon n'a rien à faire dans cette copie).
    if (table === 'purchases') return { id: ligne.id, purchase_order_id: ligne.purchase_order_id, purchase_date: ligne.purchase_date };
    if (table === 'purchase_orders') return { id: ligne.id, supplier_id: ligne.supplier_id, status: ligne.status, created_at: ligne.created_at, lines: (ligne.lines ?? []).map((x) => ({ product_id: x.product_id })) };
    return ligne;
}

export function creerSynchro({
    base, cle, jeton, deviceName, fetchFn = (...a) => globalThis.fetch(...a), maintenant = () => new Date(),
    urlBase = '', tailleLot = TAILLE_LOT, avecVerrou = null,
}) {
    const ctx = { base, cle };
    const etat = { enCours: false, suspendu: false, essai: 0 };

    async function appel(methode, chemin, corps) {
        const ctl = new AbortController();
        const minuterie = setTimeout(() => ctl.abort(), TIMEOUT_MS);
        try {
            const reponse = await fetchFn(`${urlBase}${chemin}`, {
                method: methode,
                headers: { Authorization: `Bearer ${jeton}`, Accept: 'application/json', ...(corps ? { 'Content-Type': 'application/json' } : {}) },
                body: corps ? JSON.stringify(corps) : undefined,
                credentials: 'omit',
                cache: 'no-store',
                signal: ctl.signal,
            });
            let json = null;
            try { json = await reponse.json(); } catch { /* corps vide ou non JSON */ }
            return { statut: reponse.status, json, date: reponse.headers?.get?.('date') ?? null };
        } finally {
            clearTimeout(minuterie);
        }
    }

    async function suspendre(raison = MESSAGES.suspendu) {
        etat.suspendu = true;
        await base.poserMeta('suspendu', { le: maintenant().toISOString(), raison });
        return { statut: 'suspendu', message: raison };
    }

    async function tirer() {
        const meta = {
            curseur: await base.meta('curseur'),
            tables: await base.meta('tables_servies'),
        };
        let since = meta.curseur ?? null;
        let tentative = 0;
        for (;;) {
            tentative++;
            const cumul = {};
            let page = 1;
            let curseurPage = null;
            let fin;
            let dateReponse = null;
            let tablesServies = null;
            let reset = null;
            for (;;) {
                const q = new URLSearchParams({ page: String(page) });
                if (since && page === 1) q.set('since', since);
                if (curseurPage) q.set('curseur_page', curseurPage);
                const r = await appel('GET', `/api/sync/pull?${q}`);
                const classe = classerReponse(r.statut);
                if (classe === 'suspendre') return { statut: 'suspendu', message: (await suspendre()).message };
                if (classe !== 'ok') return { statut: classe === 'reessayer' ? 'erreur' : 'refus', message: r.json?.message ?? `Tirage refusé (${r.statut}).` };
                const j = r.json ?? {};
                if (page === 1) {
                    tablesServies = Array.isArray(j.tables_servies) ? j.tables_servies : null;
                    reset = j.data_reset_at ?? null;
                    for (const t of TABLES_GARDEES) {
                        if (t in j) cumul[t] = j[t];
                    }
                } else {
                    // Les familles paginées (fiches journalières) continuent sur les pages suivantes.
                    for (const t of TABLES_PAGINEES) {
                        if (Array.isArray(j[t])) cumul[t] = [...(cumul[t] ?? []), ...j[t]];
                    }
                }
                dateReponse = r.date ?? dateReponse;
                fin = j;
                if (!j.page_suivante) break;
                curseurPage = j.page_suivante;
                page++;
            }
            // `tables_servies` a changé depuis le dernier tirage complet : repartir SANS `since` (sinon l'historique de la
            // table ajoutée ne viendrait jamais).
            const memes = tablesServies && meta.tables && tablesServies.length === meta.tables.length && tablesServies.every((t) => meta.tables.includes(t));
            if (since && tablesServies && meta.tables && !memes && tentative === 1) {
                since = null;
                continue;
            }
            return { statut: 'ok', cumul, fin, dateReponse, tablesServies, reset, completLors: since === null };
        }
    }

    /** Écrit le tirage en UNE transaction (ou rien) ; rend le nombre de lignes reçues et les lignes refusées. */
    async function absorber(t) {
        const refusees = [];
        let recus = 0;
        const ecritures = [];
        const servies = t.tablesServies ?? [];
        for (const table of TABLES_GARDEES) {
            if (!servies.includes(table)) {
                ecritures.push({ table, supprimer: true });
                continue;
            }
            const brut = t.cumul[table];
            if (table === 'company_settings') {
                const e = brut && typeof brut === 'object' ? Object.fromEntries(COLONNES_ENTREPRISE.map((c) => [c, brut[c] ?? null])) : null;
                ecritures.push({ table, lignes: e ? [{ id: 'entreprise', ...e }] : [], remplacer: true });
                recus += e ? 1 : 0;
                continue;
            }
            const bonnes = [];
            for (const l of Array.isArray(brut) ? brut : []) {
                if (table === 'purchases' && !l?.purchase_order_id) continue; // seuls les achats qui ont reçu un bon servent
                if (ligneValide(table, l)) bonnes.push(garder(table, l));
                else refusees.push({ table, id: l?.id ?? null });
            }
            recus += bonnes.length;
            ecritures.push({ table, lignes: bonnes, remplacer: t.completLors || TABLES_COMPLETES.includes(table) });
        }

        const existants = {};
        for (const e of ecritures) {
            if (!e.supprimer && !e.remplacer) existants[e.table] = await lireReferentiel(e.table);
        }
        const tireLe = maintenant().toISOString();
        const lignesAEcrire = [];
        const aSupprimer = [];
        for (const e of ecritures) {
            if (e.supprimer) { aSupprimer.push(e.table); continue; }
            let lignes = e.lignes;
            if (!e.remplacer) {
                const index = new Map((existants[e.table] ?? []).map((l) => [l.id, l]));
                for (const l of e.lignes) index.set(l.id, l);
                lignes = [...index.values()];
            }
            lignesAEcrire.push({ table: e.table, tire_le: tireLe, ...(await chiffrer(cle, lignes)) });
        }
        await base.transaction(['referentiels', 'meta'], 'readwrite', async (tx) => {
            const ref = tx.objectStore('referentiels');
            const meta = tx.objectStore('meta');
            const p = (req) => new Promise((ok, ko) => { req.onsuccess = () => ok(req.result); req.onerror = () => ko(req.error); });
            for (const l of lignesAEcrire) await p(ref.put(l));
            for (const table of aSupprimer) await p(ref.delete(table));
            await p(meta.put({ cle: 'curseur', valeur: t.fin.server_time }));
            await p(meta.put({ cle: 'tables_servies', valeur: t.tablesServies ?? [] }));
            await p(meta.put({ cle: 'data_reset_at', valeur: t.reset }));
            await p(meta.put({ cle: 'derniere_reception', valeur: tireLe }));
            if (t.dateReponse && Number.isFinite(Date.parse(t.dateReponse))) {
                await p(meta.put({ cle: 'decalage_horloge_ms', valeur: Date.parse(t.dateReponse) - maintenant().getTime() }));
            }
        });
        return { recus, refusees };
    }

    async function lireReferentiel(table) {
        const ligne = await base.lire('referentiels', table);
        if (!ligne) return [];
        return dechiffrer(cle, ligne);
    }

    /**
     * PWA-1b — les clients créés hors ligne partent AVANT les ventes (le serveur traite `customers` avant `sales`). Accusés : retirés de
     * la file ; fusionnés avec une fiche déjà connue : les ventes en file passent à l'identifiant du serveur ; refusés : gardés avec
     * leur motif français (journal), jamais renvoyés en boucle.
     */
    async function envoyerClients() {
        const liste = aEnvoyer(await clientsEnAttente(ctx));
        if (liste.length === 0) return { statut: 'ok', clients: 0 };
        const corps = { device_id: deviceName, customers: liste.map(clientEnJson) };
        const reset = await base.meta('data_reset_at');
        if (reset) corps.data_reset_at = reset;

        let r;
        try {
            r = await appel('POST', '/api/sync/push', corps);
        } catch {
            return { statut: 'hors_ligne', message: MESSAGES.injoignable };
        }
        const classe = classerReponse(r.statut);
        if (classe === 'suspendre') return suspendre();
        if (classe !== 'ok') return { statut: 'erreur', message: r.json?.message ?? `Le serveur n'a pas pu recevoir les nouveaux clients (${r.statut}).` };

        const c = r.json?.customers ?? { accepted: [], rejected: [], merged: [] };
        const acceptes = new Set(c.accepted ?? []);
        for (const m of c.merged ?? []) {
            if (m?.id && m?.id_serveur) await reaffecterClient(ctx, m.id, m.id_serveur);
        }
        await retirerClients(ctx, [...acceptes], maintenant);
        for (const x of c.rejected ?? []) {
            const motif = x.reason || 'Client refusé par le serveur.';
            await refuserClient(ctx, x.id, motif, maintenant);
            await journaliser(ctx, { vente_id: x.id, motif: `Client refusé : ${motif}` }, maintenant);
        }
        return { statut: 'ok', clients: acceptes.size };
    }

    /**
     * PWA-3 (É4) — les fiches saisies hors ligne partent AVANT les ventes (le serveur traite `livestock_daily_entries` avant `sales` : une vente
     * de sujets vivants se répercute sur la fiche). Même clé, mêmes colonnes et même règle que le poste (`pushDailyEntries`). Accusé : `synced`
     * (la copie locale reste rejouée jusqu'à un tirage ultérieur qui contient la fiche : l'effectif ne « remonte » pas) ; refus : `conflict`
     * avec le motif français du serveur, journalisé, jamais renvoyé en boucle (reprise manuelle depuis la fiche).
     */
    async function envoyerFiches() {
        const liste = aEnvoyerFiches(await saisiesEnAttente(ctx));
        if (liste.length === 0) return { statut: 'ok', acceptees: 0, refusees: 0 };
        const corps = { device_id: deviceName, livestock_daily_entries: liste.map((i) => ficheEnJson(i, deviceName)) };
        const reset = await base.meta('data_reset_at');
        if (reset) corps.data_reset_at = reset;
        let r;
        try {
            r = await appel('POST', '/api/sync/push', corps);
        } catch {
            return { statut: 'hors_ligne', message: MESSAGES.injoignable };
        }
        const classe = classerReponse(r.statut);
        if (classe === 'suspendre') return suspendre();
        if (classe === 'refuser' || classe === 'reinitialisation') {
            const motif = r.json?.message ?? `Envoi refusé par le serveur (${r.statut}).`;
            for (const i of liste) { await marquerFicheConflit(ctx, i.id_fiche, motif, maintenant); await journaliser(ctx, { vente_id: i.id_fiche, motif: `Fiche refusée : ${motif}` }, maintenant); }
            return { statut: 'ok', acceptees: 0, refusees: liste.length };
        }
        if (classe !== 'ok') return { statut: 'erreur', message: r.json?.message ?? `Le serveur n'a pas pu recevoir les fiches (${r.statut}).` };
        const c = r.json?.livestock_daily_entries ?? { accepted: [], rejected: [], merged: [] };
        const acceptees = new Set(c.accepted ?? []);
        await marquerFichesSynced(ctx, [...acceptees], maintenant);
        for (const x of c.rejected ?? []) {
            const motif = x.reason || 'Fiche refusée par le serveur.';
            await marquerFicheConflit(ctx, x.id, motif, maintenant);
            await journaliser(ctx, { vente_id: x.id, motif: `Fiche refusée : ${motif}` }, maintenant);
        }
        return { statut: 'ok', acceptees: acceptees.size, refusees: (c.rejected ?? []).length };
    }

    /**
     * PWA-3 (prophylaxie du jour) — les soins validés hors ligne partent après les fiches et AVANT les ventes (clé `veterinary_records` de
     * `pushVeterinaryRecords`, comme le poste) : le serveur crée lui-même la période de rémanence. Mêmes états que les fiches.
     */
    async function envoyerSoins() {
        const liste = aEnvoyerSoins(await soinsEnAttente(ctx));
        if (liste.length === 0) return { statut: 'ok', acceptes: 0, refuses: 0 };
        const corps = { device_id: deviceName, veterinary_records: liste.map((i) => soinEnJson(i, deviceName)) };
        const reset = await base.meta('data_reset_at');
        if (reset) corps.data_reset_at = reset;
        let r;
        try {
            r = await appel('POST', '/api/sync/push', corps);
        } catch {
            return { statut: 'hors_ligne', message: MESSAGES.injoignable };
        }
        const classe = classerReponse(r.statut);
        if (classe === 'suspendre') return suspendre();
        if (classe === 'refuser' || classe === 'reinitialisation') {
            const motif = r.json?.message ?? `Envoi refusé par le serveur (${r.statut}).`;
            for (const i of liste) { await marquerSoinConflit(ctx, i.id, motif, maintenant); await journaliser(ctx, { vente_id: i.id, motif: `Soin refusé : ${motif}` }, maintenant); }
            return { statut: 'ok', acceptes: 0, refuses: liste.length };
        }
        if (classe !== 'ok') return { statut: 'erreur', message: r.json?.message ?? `Le serveur n'a pas pu recevoir les soins (${r.statut}).` };
        const c = r.json?.veterinary_records ?? { accepted: [], rejected: [] };
        const acceptes = new Set(c.accepted ?? []);
        await marquerSoinsSynced(ctx, [...acceptes], maintenant);
        for (const x of c.rejected ?? []) {
            const motif = x.reason || 'Soin refusé par le serveur.';
            await marquerSoinConflit(ctx, x.id, motif, maintenant);
            await journaliser(ctx, { vente_id: x.id, motif: `Soin refusé : ${motif}` }, maintenant);
        }
        return { statut: 'ok', acceptes: acceptes.size, refuses: (c.rejected ?? []).length };
    }

    async function envoyer() {
        let taille = tailleLot;
        let envoyes = 0;
        let refuses = 0;
        for (;;) {
            const lot = await lotAEnvoyer(ctx, taille);
            if (lot.length === 0) break;
            const corps = {
                device_id: deviceName,
                sales: lot.map((l) => l.vente),
            };
            const reset = await base.meta('data_reset_at');
            if (reset) corps.data_reset_at = reset;

            let r;
            try {
                r = await appel('POST', '/api/sync/push', corps);
            } catch {
                await compterTentative(ctx, lot.map((l) => l.id));
                return { statut: 'hors_ligne', envoyes, refuses, message: MESSAGES.injoignable };
            }
            const classe = classerReponse(r.statut);
            if (classe === 'suspendre') return { ...(await suspendre()), envoyes, refuses };
            if (classe === 'reduire_lot' && taille > 1) { taille = Math.max(1, Math.floor(taille / 2)); continue; }
            if (classe === 'reinitialisation') {
                const motif = r.json?.message ?? 'Les données du serveur ont été remises à zéro : ces ventes ne peuvent plus être envoyées.';
                for (const l of lot) await marquerConflit(ctx, l.id, motif, maintenant);
                refuses += lot.length;
                continue;
            }
            if (classe === 'reessayer' || classe === 'reduire_lot') {
                await compterTentative(ctx, lot.map((l) => l.id));
                return { statut: 'erreur', envoyes, refuses, message: r.json?.message ?? `Le serveur n'a pas pu traiter l'envoi (${r.statut}).` };
            }
            if (classe === 'refuser') {
                const motif = r.json?.message ?? `Envoi refusé par le serveur (${r.statut}).`;
                for (const l of lot) await marquerConflit(ctx, l.id, motif, maintenant);
                refuses += lot.length;
                continue;
            }
            const ventes = r.json?.sales ?? { accepted: [], rejected: [] };
            const acceptees = new Set(ventes.accepted ?? []);
            const rejetees = new Map((ventes.rejected ?? []).map((x) => [x.id, x.reason]));
            // `synced` SEULEMENT après l'accusé ; une vente absente des deux listes reste `pending` (relancée plus tard).
            await marquerSynced(ctx, lot.filter((l) => acceptees.has(l.id)).map((l) => l.id), maintenant);
            for (const l of lot) {
                if (rejetees.has(l.id)) await marquerConflit(ctx, l.id, rejetees.get(l.id) || 'Vente refusée par le serveur.', maintenant);
            }
            const sansReponse = lot.filter((l) => !acceptees.has(l.id) && !rejetees.has(l.id)).map((l) => l.id);
            envoyes += acceptees.size;
            refuses += rejetees.size;
            if (sansReponse.length === lot.length) {
                await compterTentative(ctx, sansReponse);
                return { statut: 'erreur', envoyes, refuses, message: "Le serveur n'a pas accusé réception de ces ventes : elles restent en attente." };
            }
        }
        return { statut: 'ok', envoyes, refuses };
    }

    async function corps({ manuel }) {
        if (etat.suspendu && !manuel) return { statut: 'suspendu', message: MESSAGES.suspendu };
        if (!manuel) { /* automatique : respecte la suspension seulement */ }
        let recus = 0;
        const debutTirage = maintenant().getTime();
        try {
            const t = await tirer();
            if (t.statut !== 'ok') {
                return { statut: t.statut, message: t.message };
            }
            const a = await absorber(t);
            recus = a.recus;
            // PWA-3 (É4) : un tirage commencé plus de 5 s après l'accusé contient la fiche du serveur : la copie locale devient inutile.
            await retirerFichesSynced(ctx, debutTirage - 5000, maintenant);
            await retirerSoinsSynced(ctx, debutTirage - 5000, maintenant);
        } catch (e) {
            if (e?.name === 'ErreurBase') throw e;
            etat.essai++;
            return { statut: 'hors_ligne', message: MESSAGES.injoignable, prochainEssaiMs: delaiDeReessai(etat.essai - 1) };
        }
        const cl = await envoyerClients();
        if (cl.statut === 'suspendu') return cl;
        if (cl.statut !== 'ok') {
            etat.essai++;
            return { ...cl, recus, prochainEssaiMs: delaiDeReessai(etat.essai - 1) };
        }
        const fi = await envoyerFiches();
        if (fi.statut === 'suspendu') return fi;
        if (fi.statut !== 'ok') {
            etat.essai++;
            return { ...fi, recus, prochainEssaiMs: delaiDeReessai(etat.essai - 1) };
        }
        const so = await envoyerSoins();
        if (so.statut === 'suspendu') return so;
        if (so.statut !== 'ok') {
            etat.essai++;
            return { ...so, recus, prochainEssaiMs: delaiDeReessai(etat.essai - 1) };
        }
        const e = await envoyer();
        if (e.statut === 'suspendu') return e;
        if (e.statut !== 'ok') {
            etat.essai++;
            return { ...e, recus, prochainEssaiMs: delaiDeReessai(etat.essai - 1) };
        }
        etat.essai = 0;
        // PWA-1b — des ventes viennent d'être acceptées : leur effet sur les bandes et les fiches n'est dans la copie tirée qu'au tirage
        // SUIVANT. On le tire tout de suite (au mieux) : sans lui, l'effectif d'une bande « remonterait » entre l'accusé et le prochain tirage.
        if (e.envoyes > 0 || fi.acceptees > 0 || so.acceptes > 0) {
            try {
                const t2 = await tirer();
                if (t2.statut === 'ok') recus += (await absorber(t2)).recus;
            } catch (erreur) {
                if (erreur?.name === 'ErreurBase') throw erreur;
            }
        }
        await base.poserMeta('dernier_envoi', maintenant().toISOString());
        await nettoyerSynced(ctx, undefined, maintenant);
        const serveur = await base.meta('curseur');
        await base.poserMeta('derniere_synchro', serveur);
        return { statut: 'ok', recus, envoyes: e.envoyes, refuses: e.refuses, message: MESSAGES.termine(recus, e.envoyes) + (fi.refusees > 0 ? ` ${fi.refusees} fiche(s) d'élevage refusée(s) par le serveur : voir la fiche concernée.` : '') + (so.refuses > 0 ? ` ${so.refuses} soin(s) refusé(s) par le serveur : voir la fiche concernée.` : ''), heureServeur: heureDuServeur(serveur) };
    }

    async function synchroniser({ manuel = false } = {}) {
        if (etat.enCours) return { statut: 'deja_en_cours' };
        etat.enCours = true;
        try {
            const executer = () => corps({ manuel });
            return avecVerrou ? await avecVerrou(executer) : await executer();
        } finally {
            etat.enCours = false;
        }
    }

    return {
        synchroniser,
        etat: () => ({ ...etat }),
        async reprendre() { etat.suspendu = false; await base.supprimer('meta', 'suspendu'); },
        majJeton(nouveau) { jeton = nouveau; },
        async charger() { etat.suspendu = Boolean(await base.meta('suspendu')); return etat.suspendu; },
    };
}
