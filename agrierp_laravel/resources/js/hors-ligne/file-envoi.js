/**
 * PWA-1 — FILE D'ENVOI DES VENTES (magasin `ventes` de la base locale) et JOURNAL DES REFUS.
 *
 * Une vente est un FAIT écrit une fois (UUID du navigateur = clé d'idempotence côté serveur) ; son statut suit le
 * protocole du poste : `pending` → `synced` SEULEMENT après l'accusé du serveur, ou `conflict` + motif français.
 * Jamais de suppression silencieuse : une vente `pending` ou `conflict` ne disparaît que par un geste explicite
 * (« Abandonner »), et les ventes `synced` anciennes sont nettoyées par `nettoyerSynced`.
 */

import { chiffrer, dechiffrer } from './coffre.js';

export const STATUTS = ['pending', 'synced', 'conflict'];
export const JOURS_DE_CONSERVATION_SYNCED = 30;

/** Enregistre une vente `pending` ; ne rend qu'une fois l'écriture DURABLE (sinon lève : la vente n'est PAS validée). */
export async function ajouterVente({ base, cle }, vente, maintenant = () => new Date()) {
    const instant = maintenant().toISOString();
    const enveloppe = await chiffrer(cle, { vente: { ...vente, sync_status: 'pending' }, motif: null });
    await base.ecrire('ventes', {
        id: vente.id, sync_status: 'pending', cree_le: instant, synced_le: null, tentatives: 0, ...enveloppe,
    });
    return vente.id;
}

async function ouvrir({ cle }, ligne) {
    const { vente, motif } = await dechiffrer(cle, ligne);
    return { ...ligne, vente, motif, iv: undefined, d: undefined };
}

export async function lister(ctx, statut = null) {
    const lignes = (await ctx.base.tout('ventes')).filter((l) => statut === null || l.sync_status === statut);
    lignes.sort((a, b) => (a.cree_le < b.cree_le ? -1 : a.cree_le > b.cree_le ? 1 : 0));
    return Promise.all(lignes.map((l) => ouvrir(ctx, l)));
}

/** Prochain lot à envoyer : les `pending` les plus anciennes d'abord, taille bornée (le mandataire peut répondre 413). */
export async function lotAEnvoyer(ctx, taille = 20) {
    return (await lister(ctx, 'pending')).slice(0, Math.max(1, taille));
}

async function remplacer(ctx, id, fn) {
    const ligne = await ctx.base.lire('ventes', id);
    if (!ligne) {
        return false;
    }
    const clair = await dechiffrer(ctx.cle, ligne);
    const [entete, contenu] = fn({ ...ligne }, clair);
    await ctx.base.ecrire('ventes', { ...entete, ...(await chiffrer(ctx.cle, contenu)) });
    return true;
}

/** Accusé du serveur : seul moment où une vente devient `synced`. */
export function marquerSynced(ctx, ids, maintenant = () => new Date()) {
    return Promise.all(ids.map((id) => remplacer(ctx, id, (l, c) => [
        { id: l.id, sync_status: 'synced', cree_le: l.cree_le, synced_le: maintenant().toISOString(), tentatives: l.tentatives },
        { vente: { ...c.vente, sync_status: 'synced' }, motif: null },
    ])));
}

/** Refus motivé : la vente reste sur l'appareil, en `conflict`, avec le motif français du serveur, et le journal le garde. */
export async function marquerConflit(ctx, id, motif, maintenant = () => new Date()) {
    const ok = await remplacer(ctx, id, (l, c) => [
        { id: l.id, sync_status: 'conflict', cree_le: l.cree_le, synced_le: null, tentatives: l.tentatives + 1 },
        { vente: { ...c.vente, sync_status: 'conflict' }, motif },
    ]);
    if (ok) {
        await journaliser(ctx, { vente_id: id, motif }, maintenant);
    }
    return ok;
}

/** « Remettre en file » : le refus est levé (ex. client envoyé entre-temps) ; la vente repart au prochain envoi. */
export function remettreEnFile(ctx, id) {
    return remplacer(ctx, id, (l, c) => [
        { id: l.id, sync_status: 'pending', cree_le: l.cree_le, synced_le: null, tentatives: l.tentatives },
        { vente: { ...c.vente, sync_status: 'pending' }, motif: null },
    ]);
}

export async function abandonner(ctx, id) {
    await ctx.base.supprimer('ventes', id);
}

export async function compterTentative(ctx, ids) {
    await Promise.all(ids.map(async (id) => {
        const l = await ctx.base.lire('ventes', id);
        if (l) {
            await ctx.base.ecrire('ventes', { ...l, tentatives: l.tentatives + 1 });
        }
    }));
}

/** Nettoyage des ventes `synced` plus vieilles que `jours` (jamais une `pending` ni une `conflict`). */
export async function nettoyerSynced({ base }, jours = JOURS_DE_CONSERVATION_SYNCED, maintenant = () => new Date()) {
    const limite = maintenant().getTime() - jours * 86_400_000;
    let n = 0;
    for (const l of await base.tout('ventes')) {
        if (l.sync_status === 'synced' && l.synced_le && Date.parse(l.synced_le) < limite) {
            await base.supprimer('ventes', l.id);
            n++;
        }
    }
    return n;
}

export async function journaliser(ctx, { vente_id, motif }, maintenant = () => new Date()) {
    const enveloppe = await chiffrer(ctx.cle, { vente_id, motif });
    await ctx.base.ecrire('journal', { le: maintenant().toISOString(), ...enveloppe });
}

export async function lireJournal(ctx, limite = 50) {
    const lignes = (await ctx.base.tout('journal')).slice(-limite).reverse();
    return Promise.all(lignes.map(async (l) => ({ le: l.le, ...(await dechiffrer(ctx.cle, l)) })));
}
