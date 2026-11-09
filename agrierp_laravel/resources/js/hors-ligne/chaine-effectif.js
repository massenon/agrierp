/**
 * PWA-1b / PWA-3 — LA CHAÎNE D'EFFECTIF D'UNE BANDE, EN JAVASCRIPT PUR : les fiches journalières d'une bande, leur effectif final,
 * les catégories (chaîne de départ) et la répercussion d'une VENTE sur la fiche du jour.
 *
 * Transposition fidèle, sur des tableaux en mémoire, de :
 *   - `RecordSaleOnFicheElevageAction` : `execute` (fiche du jour complétée, jamais écrasée), `refusDesLignes`, `emplacementDeLaLigne`,
 *     `recalculerEnCascade` ;
 *   - `LivestockDailyEntry` : `previousEffectif`, `computeEffectifFinal`, `effectifFinalDepuis`, `mouvementsParCategorie` ;
 *   - `EffectifParCategorieService` : `aUneChaine`, `teteDeChaine`, `departDeLaFiche`, `recalculerChaine` / `simuler` (chaîne EXPLICITE,
 *     c'est-à-dire démarrée par un départ saisi), `mouvementsConnusAZeroPour`.
 * Le calcul d'une journée est `effectif-categories.js` (parité exécutée). Ici : l'enchaînement, prouvé de même contre le vrai PHP
 * (`tests/Js/parite-chaine.test.mjs` : ventes sur des bandes aléatoires, refus et fiches obtenues égaux).
 *
 * Fonctions PURES : les entrées ne sont jamais modifiées, le résultat porte les fiches et la bande mises à jour. Le serveur reste juge :
 * il rejoue la vente (`SyncController::pushSales`) et recalcule sa propre chaîne.
 *
 * Non couvert (la fiche journalière hors ligne n'est pas encore construite) : chaîne IMPLICITE (D6), `etatPourJour`, `refusDuPassage`,
 * `rapportABlanc`.
 */

import {
    calculerJour, verifierDepart, especeDuLot, estVolailles, colonne, VOLAILLES_PONTE,
} from './effectif-categories.js';

/** Mêmes motifs que `MotifsRefusPush` (VOL-1, VOL-2) — garde : parité. */
export const MOTIFS_VENTE = {
    sansDepart: (bande) => `Vente refusée : l'effectif de départ par catégorie de la bande ${bande} n'est pas saisi. Ouvrez la fiche Volailles Reproducteurs et saisissez-le avant toute vente de cette bande.`,
    sansDepartPondeuses: (bande) => `Vente refusée : l'effectif de départ par stade de la bande ${bande} n'est pas saisi. Ouvrez la fiche Pondeuses et saisissez-le avant toute vente de cette bande.`,
    avantLeDepart: (dateVente, dateDepart) => `Vente refusée : la date de la vente (${dateVente}) précède l'effectif de départ de la bande (fixé le ${dateDepart}).`,
    sansCategorie: (produit) => `Vente refusée : le produit « ${produit} » n'a pas de catégorie d'effectif (Reproducteur, Jeune ou Poussin). Renseignez-la dans « Modifier un produit » avant de le vendre sur une bande de volailles reproductrices.`,
    sansStade: (produit) => `Vente refusée : le produit « ${produit} » n'a pas de stade d'effectif de pondeuses (Poussin ponte, Poussin en croissance, Poulette ou Pondeuse). Renseignez-le dans « Modifier un produit » avant de le vendre sur une bande de pondeuses.`,
};

/** `CategorieVolaille::EMPLACEMENTS` et `StadePondeuse::EMPLACEMENTS` : clé du produit → emplacement de colonnes. */
export const EMPLACEMENT_REPRODUCTEURS = { reproducteur: 'repro', jeune: 'jeune', poussin: 'sevre' };
export const EMPLACEMENT_PONDEUSES = { pondeuse: 'repro', poulette: 'jeune', poussin_croissance: 'sevre', poussin_ponte: 'quatre' };

const MOUVEMENTS_CONNUS_A_ZERO = {
    mort_repro: 0, mort_sevre: 0, mort_jeune: 0, don_repro: 0, don_sevre: 0, don_jeune: 0, passage_sevre_jeune: 0,
};
const VENTES_CONNUES_A_ZERO = { vente_repro: 0, vente_sevre: 0, vente_jeune: 0 };
const MOUVEMENTS_PONTE_CONNUS_A_ZERO = { mort_4: 0, don_4: 0, vente_4: 0, passage_4_sevre: 0, passage_jeune_repro: 0 };

const entier = (v) => Math.trunc(Number(v ?? 0)) || 0;
export const jourDe = (fiche) => String(fiche.entry_date).slice(0, 10);
const trier = (fiches) => [...fiches].sort((a, b) => (jourDe(a) < jourDe(b) ? -1 : jourDe(a) > jourDe(b) ? 1 : 0));

/** `d/m/Y` d'un jour `Y-m-d` (dans les motifs de refus). */
export const jourFrancais = (j) => `${j.slice(8, 10)}/${j.slice(5, 7)}/${j.slice(0, 4)}`;

/** `LivestockDailyEntry::computeEffectifFinal`. */
export function computeEffectifFinal(precedent, achat, ne, mort, vente, don = 0, transfertEntree = 0, transfertSortie = 0) {
    return Math.max(0, precedent + achat + ne + transfertEntree - (mort + vente + don + transfertSortie));
}

/** `LivestockDailyEntry::effectifFinalDepuis`. */
export function effectifFinalDepuis(fiche, precedent) {
    return computeEffectifFinal(
        precedent, entier(fiche.achat), entier(fiche.ne), entier(fiche.mort), entier(fiche.vente), entier(fiche.don),
        entier(fiche.transfert_entree), entier(fiche.transfert_sortie),
    );
}

/** `LivestockDailyEntry::previousEffectif` : effectif final de la fiche STRICTEMENT antérieure, sinon l'effectif initial de la bande. */
export function effectifVeille(lot, fichesDeLaBande, jour, idExclu = null) {
    const avant = trier(fichesDeLaBande).filter((f) => jourDe(f) < jour && (idExclu === null || f.id !== idExclu));
    const derniere = avant.at(-1);
    return derniere?.effectif_final ?? lot?.initial_quantity ?? 0;
}

/** `LivestockDailyEntry::mouvementsParCategorie`. */
export function mouvementsParCategorie(f) {
    const t = (c) => entier(f[c]);
    return {
        achat: f.achat ?? null, ne: f.ne ?? null, vente: f.vente ?? null,
        mort_repro: f.mort_repro ?? null, mort_sevre: f.mort_sevre ?? null, mort_jeune: f.mort_jeune ?? null,
        don_repro: f.don_repro ?? null, don_sevre: f.don_sevre ?? null, don_jeune: f.don_jeune ?? null,
        passage: f.passage_sevre_jeune ?? null,
        vente_repro: f.vente_repro ?? null, vente_sevre: f.vente_sevre ?? null, vente_jeune: f.vente_jeune ?? null,
        mort_4: f.mort_4 ?? null, don_4: f.don_4 ?? null, vente_4: f.vente_4 ?? null,
        passage_4_sevre: f.passage_4_sevre ?? null, passage_jeune_repro: f.passage_jeune_repro ?? null,
        transfert_entree_4: t('transfert_entree_4'), transfert_sortie_4: t('transfert_sortie_4'),
        transfert_entree_repro: t('transfert_entree_repro'), transfert_entree_sevre: t('transfert_entree_sevre'), transfert_entree_jeune: t('transfert_entree_jeune'),
        transfert_sortie_repro: t('transfert_sortie_repro'), transfert_sortie_sevre: t('transfert_sortie_sevre'), transfert_sortie_jeune: t('transfert_sortie_jeune'),
    };
}

// ---------------------------------------------------------------------------------------------- chaîne de catégories

/** `EffectifParCategorieService::departDeLaFiche` : départ COMPLET d'une fiche (`null` s'il manque une colonne). */
export function departDeLaFiche(f, ponte) {
    const depart = { repro: f.cat_depart_repro ?? null, sevre: f.cat_depart_sevre ?? null, jeune: f.cat_depart_jeune ?? null, ...(ponte ? { quatre: f.cat_depart_4 ?? null } : {}) };
    return Object.values(depart).includes(null) ? null : Object.fromEntries(Object.entries(depart).map(([k, v]) => [k, entier(v)]));
}

const estPonte = (lot) => especeDuLot(lot) === VOLAILLES_PONTE;

/** `EffectifParCategorieService::aUneChaine`. */
export function aUneChaine(lot, fichesDeLaBande) {
    return lot !== null && lot !== undefined && especeDuLot(lot) !== null && fichesDeLaBande.some((f) => departDeLaFiche(f, estPonte(lot)) !== null);
}

/** `EffectifParCategorieService::teteDeChaine` : la première fiche (par jour) qui porte un départ complet. */
export function teteDeChaine(lot, fichesDeLaBande) {
    const ponte = estPonte(lot);
    return trier(fichesDeLaBande).find((f) => departDeLaFiche(f, ponte) !== null) ?? null;
}

/** `EffectifParCategorieService::mouvementsConnusAZeroPour`. */
export function mouvementsConnusAZeroPour(lot) {
    const espece = especeDuLot(lot);
    return { ...MOUVEMENTS_CONNUS_A_ZERO, ...(estVolailles(espece) ? VENTES_CONNUES_A_ZERO : {}), ...(espece === VOLAILLES_PONTE ? MOUVEMENTS_PONTE_CONNUS_A_ZERO : {}) };
}

const colonnesDeCategories = (r) => ({ cat_eff_repro: r.repro, cat_eff_sevre: r.sevre, cat_eff_jeune: r.jeune, ...(r.quatre === null ? {} : { cat_eff_4: r.quatre }) });
const veilleDuResultat = (r) => ({ repro: r.repro, sevre: r.sevre, jeune: r.jeune, ...(r.quatre === null ? {} : { quatre: r.quatre }) });

/**
 * `EffectifParCategorieService::recalculerChaine` (chaîne explicite) : recalcule les catégories de TOUTES les fiches à partir du
 * départ saisi et des mouvements stockés. Ne touche JAMAIS aux mouvements ni à `effectif_final`. Un départ incohérent refuse la chaîne
 * ENTIÈRE (rien n'est écrit, le motif est rendu).
 *
 * @returns {{fiches: object[], chaine: boolean, refus: ?string, modifiees: number}}
 */
export function recalculerChaine(lot, fiches) {
    const espece = especeDuLot(lot);
    const sortie = { fiches, chaine: false, refus: null, modifiees: 0 };
    if (espece === null) return sortie;

    const triees = trier(fiches);
    const ponte = espece === VOLAILLES_PONTE;
    const indexTete = triees.findIndex((f) => departDeLaFiche(f, ponte) !== null);
    if (indexTete === -1) return sortie;

    const depart = departDeLaFiche(triees[indexTete], ponte);
    const totalDepart = indexTete > 0 ? entier(triees[indexTete - 1].effectif_final) : entier(lot.initial_quantity);
    sortie.chaine = true;
    sortie.refus = verifierDepart(depart, totalDepart);
    if (sortie.refus !== null) return sortie;

    let veille = depart;
    const ecrites = new Map();
    for (const f of triees.slice(indexTete)) {
        const r = calculerJour(espece, veille, mouvementsParCategorie(f), entier(f.effectif_final));
        const colonnes = colonnesDeCategories(r);
        if (Object.entries(colonnes).some(([c, v]) => (f[c] === undefined || f[c] === null ? null : entier(f[c])) !== v)) {
            ecrites.set(f.id ?? jourDe(f), { ...f, ...colonnes });
            sortie.modifiees++;
        }
        veille = veilleDuResultat(r);
    }
    sortie.fiches = fiches.map((f) => ecrites.get(f.id ?? jourDe(f)) ?? f);
    return sortie;
}

// ------------------------------------------------------------------------------------------------ cascade d'effectif

/**
 * `RecordSaleOnFicheElevageAction::recalculerEnCascade` : l'effectif final des fiches POSTÉRIEURES au jour donné, puis la quantité
 * courante de la bande (celle de la DERNIÈRE fiche), puis les catégories. Les mouvements saisis ne changent jamais.
 *
 * @returns {{lot: object, fiches: object[]}}
 */
export function recalculerEnCascade(lot, fiches, apresJour) {
    const triees = trier(fiches);
    const duJour = triees.find((f) => jourDe(f) === apresJour);
    let courant = duJour ? entier(duJour.effectif_final) : effectifVeille(lot, fiches, apresJour);

    const corrigees = new Map();
    for (const f of triees.filter((x) => jourDe(x) > apresJour)) {
        const juste = effectifFinalDepuis(f, courant);
        if (entier(f.effectif_final) !== juste) corrigees.set(f.id ?? jourDe(f), { ...f, effectif_final: juste });
        courant = juste;
    }
    let apres = fiches.map((f) => corrigees.get(f.id ?? jourDe(f)) ?? f);

    let nouvelleBande = lot;
    const derniere = trier(apres).at(-1);
    if (derniere !== undefined) {
        const cible = Math.max(0, entier(derniere.effectif_final));
        if (lot.current_quantity === null || lot.current_quantity === undefined || entier(lot.current_quantity) !== cible) nouvelleBande = { ...lot, current_quantity: cible };
    }

    apres = recalculerChaine(nouvelleBande, apres).fiches;
    return { lot: nouvelleBande, fiches: apres };
}

// ------------------------------------------------------------------------------------------------------- ventes

/**
 * `RecordSaleOnFicheElevageAction::emplacementDeLaLigne` : où la ligne range ses sujets vendus (`repro`, `sevre`, `jeune`, `quatre`), ou
 * `null` si la bande n'est pas une bande de volailles ou si la catégorie du produit n'est pas de la famille de la bande.
 */
export function emplacementDeLaLigne(lot, ligne) {
    const espece = lot ? especeDuLot(lot) : null;
    if (!estVolailles(espece)) return null;
    const cle = ligne.categorie_effectif ?? null;
    return (espece === VOLAILLES_PONTE ? EMPLACEMENT_PONDEUSES : EMPLACEMENT_REPRODUCTEURS)[cle] ?? null;
}

/**
 * `RecordSaleOnFicheElevageAction::refusDesLignes` : motif français du refus d'un jeu de lignes (volailles seulement), ou `null`.
 *
 * @param {{lot_id:?string, qty:number, categorie_effectif:?string, nom_produit:?string}[]} lignes
 * @param {{lots:object[], fiches:object[]}} elevage
 */
export function refusDesLignes(lignes, { lots, fiches }, jour) {
    for (const ligne of lignes) {
        if (!ligne.lot_id || entier(ligne.qty) <= 0) continue;
        const lot = lots.find((l) => l.id === ligne.lot_id) ?? null;
        const espece = lot ? especeDuLot(lot) : null;
        if (!estVolailles(espece)) continue;
        const ponte = espece === VOLAILLES_PONTE;

        const duLot = fiches.filter((f) => f.lot_id === lot.id);
        const tete = teteDeChaine(lot, duLot);
        if (tete === null) return ponte ? MOTIFS_VENTE.sansDepartPondeuses(lot.code) : MOTIFS_VENTE.sansDepart(lot.code);
        if (jour < jourDe(tete)) return MOTIFS_VENTE.avantLeDepart(jourFrancais(jour), jourFrancais(jourDe(tete)));

        if (emplacementDeLaLigne(lot, ligne) === null) {
            const nom = ligne.nom_produit ?? 'sans nom';
            return ponte ? MOTIFS_VENTE.sansStade(nom) : MOTIFS_VENTE.sansCategorie(nom);
        }
    }
    return null;
}

/**
 * `RecordSaleOnFicheElevageAction::execute` : répercute les lignes d'une vente sur la fiche DU JOUR de leur bande (créée si absente,
 * jamais écrasée : la vente s'AJOUTE), recalcule l'effectif final, la cascade et la chaîne de catégories.
 *
 * @returns {{ok:true, lots:object[], fiches:object[]}|{ok:false, motif:string}}
 */
export function repercuterVente(lignes, { lots, fiches }, jour) {
    const refus = refusDesLignes(lignes, { lots, fiches }, jour);
    if (refus !== null) return { ok: false, motif: refus };

    let lotsCourants = lots;
    let fichesCourantes = fiches;
    for (const ligne of lignes) {
        const qty = entier(ligne.qty);
        if (!ligne.lot_id || qty <= 0) continue;

        const lot = lotsCourants.find((l) => l.id === ligne.lot_id) ?? null;
        const duLot = fichesCourantes.filter((f) => f.lot_id === ligne.lot_id);
        const defauts = { achat: 0, ne: 0, mort: 0, vente: 0, don: 0, effectif_final: 0 };
        if (lot !== null && aUneChaine(lot, duLot)) Object.assign(defauts, mouvementsConnusAZeroPour(lot));
        const emplacement = emplacementDeLaLigne(lot, ligne);

        let fiche = duLot.find((f) => jourDe(f) === jour);
        const nouvelle = fiche === undefined;
        if (nouvelle) fiche = { id: ligne.id_fiche ?? `local:${ligne.lot_id}:${jour}`, lot_id: ligne.lot_id, entry_date: jour, ...defauts };

        fiche = { ...fiche, vente: entier(fiche.vente) + qty };
        if (emplacement !== null) {
            const c = colonne('vente', emplacement);
            fiche[c] = entier(fiche[c]) + qty;
        }
        const autres = duLot.filter((f) => f !== fiche && f.id !== fiche.id);
        fiche.effectif_final = effectifFinalDepuis(fiche, effectifVeille(lot, autres, jour, fiche.id));

        fichesCourantes = nouvelle ? [...fichesCourantes, fiche] : fichesCourantes.map((f) => (f.id === fiche.id ? fiche : f));
        if (lot !== null) {
            const cascade = recalculerEnCascade(lot, fichesCourantes.filter((f) => f.lot_id === lot.id), jour);
            lotsCourants = lotsCourants.map((l) => (l.id === lot.id ? cascade.lot : l));
            fichesCourantes = [...fichesCourantes.filter((f) => f.lot_id !== lot.id), ...cascade.fiches];
        }
    }
    return { ok: true, lots: lotsCourants, fiches: fichesCourantes };
}

// ----------------------------------------------------------------------------------------- lecture de la chaîne (fiche)

const entierOuNul = (v) => (v === undefined || v === null ? null : entier(v));

/**
 * `EffectifParCategorieService::etatPourJour` : ce qu'il faut pour calculer UN jour avec `calculerJour`, sans que la fiche recopie la
 * moindre formule. Modes : `sans_chaine`, `avant_depart` (le jour précède la tête de chaîne), `refus` (départ incohérent), `chaine`
 * (`veille` = le départ si le jour EST la tête, sinon les catégories de la dernière fiche antérieure ; une valeur nulle reste inconnue).
 *
 * @returns {{mode:string, depart_date:?string, depart:?object, veille:?object, refus:?string}}
 */
export function etatPourJour(lot, fiches, date) {
    const sortie = { mode: 'sans_chaine', depart_date: null, depart: null, veille: null, refus: null };
    if (especeDuLot(lot) === null) return sortie;

    const duLot = trier(fiches.filter((f) => f.lot_id === lot.id || f.lot_id === undefined));
    const tete = teteDeChaine(lot, duLot);
    if (tete === null) return sortie;

    const ponte = estPonte(lot);
    const dateTete = jourDe(tete);
    const depart = departDeLaFiche(tete, ponte);
    sortie.depart_date = dateTete;
    sortie.depart = depart;

    if (date < dateTete) {
        sortie.mode = 'avant_depart';
        return sortie;
    }

    const avantTete = duLot.filter((f) => jourDe(f) < dateTete).at(-1);
    const totalDepart = avantTete !== undefined ? entier(avantTete.effectif_final) : entier(lot.initial_quantity);
    const refus = verifierDepart(depart, totalDepart);
    if (refus !== null) {
        sortie.mode = 'refus';
        sortie.refus = refus;
        return sortie;
    }

    sortie.mode = 'chaine';
    if (date === dateTete) {
        sortie.veille = depart;
        return sortie;
    }

    const precedente = duLot.filter((f) => jourDe(f) < date && jourDe(f) >= dateTete).at(-1);
    sortie.veille = {
        repro: entierOuNul(precedente?.cat_eff_repro), sevre: entierOuNul(precedente?.cat_eff_sevre), jeune: entierOuNul(precedente?.cat_eff_jeune),
        ...(ponte ? { quatre: entierOuNul(precedente?.cat_eff_4) } : {}),
    };
    return sortie;
}

/**
 * `EffectifParCategorieService::refusDuPassage` : la fiche PROPOSÉE (saisie en cours) viole-t-elle la règle du passage, une fois
 * insérée dans la chaîne ? Motif français, ou `null`. Aucune écriture.
 */
export function refusDuPassage(lot, proposee, fiches) {
    const espece = especeDuLot(lot);
    if (espece === null) return null;

    const toutes = trier([...fiches.filter((f) => f.lot_id === lot.id && f.id !== proposee.id), proposee]);
    const ponte = espece === VOLAILLES_PONTE;
    const indexTete = toutes.findIndex((f) => departDeLaFiche(f, ponte) !== null);
    if (indexTete === -1) return null;

    let veille = departDeLaFiche(toutes[indexTete], ponte);
    for (const f of toutes.slice(indexTete)) {
        const r = calculerJour(espece, veille, mouvementsParCategorie(f));
        if (f.id === proposee.id) return r.refus;
        veille = veilleDuResultat(r);
    }
    return null;
}
