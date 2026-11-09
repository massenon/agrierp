/**
 * PWA-1b — CLIENTS CRÉÉS HORS LIGNE (bouton « + » de la caisse).
 *
 * Le navigateur écrit un FAIT : une fiche client avec son UUID (clé d'idempotence côté serveur). Le serveur reste juge
 * (`SyncController::pushCustomers` → `CustomerCatalogService`, droit `manage-ventes`) : il valide, crée, ou FUSIONNE avec une fiche
 * déjà connue (même nom normalisé + même téléphone) et le DIT (`merged` : l'identifiant du navigateur → celui du serveur) ; les ventes
 * en file sont alors rattachées à la fiche du serveur.
 *
 * Stockage : le magasin `referentiels` existant, table `clients_a_envoyer` (chiffrée par le PIN comme le reste ; aucun changement de
 * schéma IndexedDB). Le pull ne la touche pas (il ne remplace que les tables du catalogue).
 *
 * Mêmes règles et mêmes mots que le serveur (`CustomerCatalogService::regles` + `MotifsRefusPush`), prouvés par
 * `tests/Js/parite-php.test.mjs`. L'IFU facultatif est une extension du bouton « + » du web (qui ne demande que nom et téléphone) :
 * il suit la règle de la facture normalisée.
 */

import { chiffrer, dechiffrer } from './coffre.js';
import { MOTIFS } from './calculs-caisse.js';

export const TABLE_CLIENTS_A_ENVOYER = 'clients_a_envoyer';
export const NOM_MAX = 150;
export const TELEPHONE_MAX = 30;

export const MOTIFS_CLIENT = {
    nomObligatoire: 'Le champ nom est obligatoire.',
    nomTropLong: `Le champ nom dépasse le maximum autorisé (${NOM_MAX}).`,
    telephoneTropLong: `Le champ téléphone dépasse le maximum autorisé (${TELEPHONE_MAX}).`,
    ifu: MOTIFS.factureIfu,
};

/**
 * Valide la saisie du bouton « + » (`CustomerCatalogService::regles` : nom obligatoire ≤ 150, téléphone ≤ 30, IFU de 13 chiffres).
 *
 * @returns {{ok:true, valeurs:{name:string, phone:?string, ifu:?string}}|{ok:false, champ:string, motif:string}}
 */
export function validerClient({ name = '', phone = '', ifu = '' } = {}) {
    const nom = String(name ?? '').trim();
    if (nom === '') return { ok: false, champ: 'name', motif: MOTIFS_CLIENT.nomObligatoire };
    if ([...nom].length > NOM_MAX) return { ok: false, champ: 'name', motif: MOTIFS_CLIENT.nomTropLong };

    const tel = String(phone ?? '').trim();
    if ([...tel].length > TELEPHONE_MAX) return { ok: false, champ: 'phone', motif: MOTIFS_CLIENT.telephoneTropLong };

    const numero = String(ifu ?? '').trim().replace(/\s+/gu, '');
    if (numero !== '' && !/^\d{13}$/.test(numero)) return { ok: false, champ: 'ifu', motif: MOTIFS_CLIENT.ifu };

    return { ok: true, valeurs: { name: nom, phone: tel === '' ? null : tel, ifu: numero === '' ? null : numero } };
}

/** Les clients créés ici et pas encore acquittés par le serveur (clair après déchiffrement). */
export async function clientsEnAttente({ base, cle }) {
    const ligne = await base.lire('referentiels', TABLE_CLIENTS_A_ENVOYER);
    return ligne ? dechiffrer(cle, ligne) : [];
}

async function ecrireClients({ base, cle }, liste, maintenant = () => new Date()) {
    if (liste.length === 0) {
        await base.supprimer('referentiels', TABLE_CLIENTS_A_ENVOYER);
        return;
    }
    await base.ecrire('referentiels', { table: TABLE_CLIENTS_A_ENVOYER, tire_le: maintenant().toISOString(), ...(await chiffrer(cle, liste)) });
}

/** Enregistre un client `pending` ; ne rend qu'une fois l'écriture DURABLE (sinon lève : le client n'est PAS créé). */
export async function ajouterClient(ctx, { id, valeurs, instant, deviceId }, maintenant = () => new Date()) {
    const liste = await clientsEnAttente(ctx);
    const client = { id, ...valeurs, is_active: true, device_id: deviceId, updated_at: instant, sync_status: 'pending', motif: null };
    await ecrireClients(ctx, [...liste.filter((c) => c.id !== id), client], maintenant);
    return client;
}

export async function retirerClients(ctx, ids, maintenant = () => new Date()) {
    const liste = await clientsEnAttente(ctx);
    await ecrireClients(ctx, liste.filter((c) => !ids.includes(c.id)), maintenant);
}

/** Un refus motivé du serveur : le client reste sur l'appareil, en `conflict`, avec son motif (jamais renvoyé en boucle). */
export async function refuserClient(ctx, id, motif, maintenant = () => new Date()) {
    const liste = await clientsEnAttente(ctx);
    await ecrireClients(ctx, liste.map((c) => (c.id === id ? { ...c, sync_status: 'conflict', motif } : c)), maintenant);
}

/** Les clients à ENVOYER : ceux que le serveur n'a pas encore refusés. */
export const aEnvoyer = (liste) => liste.filter((c) => c.sync_status === 'pending');

/** Clients proposés dans la liste : ceux du tirage, puis ceux créés ici (un identifiant n'apparaît qu'une fois), par nom. */
export function clientsVisibles(tires, enAttente) {
    const vus = new Set();
    const tous = [];
    for (const c of [...tires, ...enAttente]) {
        if (!vus.has(c.id) && c.is_active !== false) { vus.add(c.id); tous.push(c); }
    }
    return tous.sort((a, b) => String(a.name).localeCompare(String(b.name), 'fr'));
}

/** Le corps d'un client dans l'envoi : exactement les clés du formulaire du poste (`_clientEnJson`). */
export const clientEnJson = (c) => ({ id: c.id, name: c.name, phone: c.phone ?? null, ifu: c.ifu ?? null, is_active: true });
