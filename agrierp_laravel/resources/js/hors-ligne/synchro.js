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
import { classerReponse, delaiDeReessai, heureDuServeur } from './etat.js';

/** Tables gardées par la caisse hors ligne (le reste du tirage est ignoré, jamais stocké). */
export const TABLES_GARDEES = ['products', 'product_categories', 'customers', 'company_settings'];
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
    return true;
}

function garder(table, ligne) {
    if (table === 'company_settings') return ligne; // objet unique, traité à part
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
                if (ligneValide(table, l)) bonnes.push(garder(table, l));
                else refusees.push({ table, id: l?.id ?? null });
            }
            recus += bonnes.length;
            ecritures.push({ table, lignes: bonnes, remplacer: t.completLors });
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
        try {
            const t = await tirer();
            if (t.statut !== 'ok') {
                return { statut: t.statut, message: t.message };
            }
            const a = await absorber(t);
            recus = a.recus;
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
        const e = await envoyer();
        if (e.statut === 'suspendu') return e;
        if (e.statut !== 'ok') {
            etat.essai++;
            return { ...e, recus, prochainEssaiMs: delaiDeReessai(etat.essai - 1) };
        }
        etat.essai = 0;
        await base.poserMeta('dernier_envoi', maintenant().toISOString());
        await nettoyerSynced(ctx, undefined, maintenant);
        const serveur = await base.meta('curseur');
        await base.poserMeta('derniere_synchro', serveur);
        return { statut: 'ok', recus, envoyes: e.envoyes, refuses: e.refuses, message: MESSAGES.termine(recus, e.envoyes), heureServeur: heureDuServeur(serveur) };
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
