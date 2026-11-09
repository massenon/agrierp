/**
 * PWA-1b — LES DONNÉES D'ÉLEVAGE DE LA CAISSE HORS LIGNE : bandes vivantes, fiches journalières, rémanences vétérinaires tirées
 * (`livestock_lots`, `livestock_daily_entries`, `veterinary_withdrawal_periods`, sous le droit de lecture du compte), et ce qu'une vente
 * de sujets vivants en fait AVANT l'envoi : la fiche du jour et la bande se mettent à jour comme le serveur le fera à la réception
 * (`chaine-effectif.js`, parité exécutée). Le serveur reste juge : il rejoue la vente et peut la refuser, avec son motif.
 *
 * Les ventes en attente sont REJOUÉES au-dessus des données tirées à chaque affichage (jamais écrites dans la copie tirée) : un tirage qui
 * n'a pas encore vu la vente ne fait donc pas « remonter » l'effectif de la bande.
 */

import { repercuterVente, refusDesLignes } from './chaine-effectif.js';
import { MOTIFS } from './calculs-caisse.js';

/** Le jour du BÉNIN (UTC+1 toute l'année) d'un instant ISO : celui de la fiche du jour, comme `sold_at` côté serveur. */
export function jourBenin(instant) {
    const ms = typeof instant === 'number' ? instant : Date.parse(instant);
    return new Date(ms + 3_600_000).toISOString().slice(0, 10);
}

/** Bandes proposées pour un produit rattaché à une espèce (`PosInterface::getLotsForWeightModalProperty`) : même espèce, actives, en cours, non vides. */
export function lotsVendables(produit, lots) {
    if (!produit?.species_id) return [];
    return lots
        .filter((l) => l.species_id === produit.species_id && l.status === 'actif' && l.is_active !== false && Number(l.current_quantity) > 0)
        .sort((a, b) => String(a.code).localeCompare(String(b.code), 'fr'));
}

/** `VeterinaryWithdrawalPeriod::isLotBlocked` : un délai d'attente de la bande qui court encore ce jour-là. */
export function bandeSousRemanence(lotId, remanences, jour) {
    return remanences.some((r) => r.lot_id === lotId && String(r.end_date).slice(0, 10) >= jour);
}

/** Les lignes d'une vente, au format de la chaîne d'effectif (catégorie d'effectif et nom lus dans le catalogue tiré). */
export function lignesDeChaine(lignes, produits) {
    return lignes.filter((l) => l.lot_id).map((l) => {
        const p = produits.find((x) => x.id === l.product_id);
        return { lot_id: l.lot_id, qty: l.qty, categorie_effectif: p?.categorie_effectif ?? null, nom_produit: p?.name ?? null };
    });
}

/**
 * Refus d'un panier de sujets vivants, avant l'enregistrement (`validateSale` de la caisse web) : rémanence active, puis départ, date, catégorie
 * ou stade (`refusDesLignes`). `null` : rien à refuser.
 */
export function refusDuPanier(lignes, produits, elevage, remanences, jour) {
    for (const l of lignes) {
        if (l.lot_id && bandeSousRemanence(l.lot_id, remanences, jour)) {
            const lot = elevage.lots.find((x) => x.id === l.lot_id);
            return { champ: 'lot_id', motif: MOTIFS.remanenceValidation(lot?.code) };
        }
    }
    const motif = refusDesLignes(lignesDeChaine(lignes, produits), elevage, jour);
    return motif === null ? null : { champ: 'lot_id', motif };
}

/**
 * Les bandes et les fiches telles qu'elles seront APRÈS les ventes en attente (rejouées dans l'ordre de saisie). Une vente que la chaîne
 * refuse est ignorée ici : le serveur en jugera.
 *
 * @param {{lots:object[], fiches:object[]}} tire
 * @param {object[]} ventesEnAttente  les ventes (clair) `pending` et `conflict` ? seulement `pending` : une vente refusée n'a aucun effet.
 */
export function elevageApresVentes(tire, ventesEnAttente, produits) {
    let courant = { lots: tire.lots, fiches: tire.fiches };
    for (const v of ventesEnAttente) {
        const lignes = lignesDeChaine(v.lines ?? [], produits);
        if (lignes.length === 0) continue;
        const r = repercuterVente(lignes, courant, jourBenin(v.sold_at));
        if (r.ok) courant = { lots: r.lots, fiches: r.fiches };
    }
    return courant;
}
