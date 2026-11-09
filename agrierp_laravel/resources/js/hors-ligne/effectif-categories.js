/**
 * PWA-3 (PREMIÈRE PIERRE) — CALCUL DE L'EFFECTIF PAR CATÉGORIE / STADE D'UNE JOURNÉE, EN JAVASCRIPT PUR.
 *
 * Transposition FIDÈLE des fonctions PURES de `App\\Services\\EffectifParCategorieService` (tickets 14.11, 15.39, VOL-1, VOL-2) :
 * `calculerJour` (lapins, porcs, volailles reproductrices, volailles pondeuses à quatre stades), `verifierDepart`,
 * `departDepuisStade`, `categorieDuStade`, `categorieDeLaBande`, `especeDuLot`. Aucun accès réseau ni stockage.
 *
 * ⚠️ CE MODULE N'EST PAS ENCORE UNE FICHE JOURNALIÈRE HORS LIGNE : il ne contient ni écran, ni saisie, ni file d'envoi, ni tirage
 * des bandes (voir `docs/PLAN_FINALISATION.md`, PWA-3). Il fournit la pièce qui devait être PROUVÉE en premier : le calcul
 * d'effectif du navigateur est égal, sur des centaines de jeux, à celui du serveur (`tests/Js/parite-php.test.mjs`, exécute le vrai
 * PHP). Le serveur reste juge : il recalcule la chaîne (`recalculerChaine`) à l'envoi.
 *
 * Conventions : `null` = INCONNU (jamais 0) pour les lapins et les porcs ; les volailles n'ont aucun inconnu (absent ou null = 0).
 */

export const LAPINS = 'lapins';
export const PORCS = 'porcs';
export const VOLAILLES_REPRO = 'volailles_repro';
export const VOLAILLES_PONTE = 'volailles_ponte';

/** `StadePondeuse::LIBELLES`, dans les messages de passage refusé. */
export const LIBELLES_STADE_PONDEUSE = {
    poussin_ponte: 'Poussin ponte (0 à 2 mois)',
    poussin_croissance: 'Poussin en croissance (2 à 4 mois)',
    poulette: 'Poulette (4 à 5.5 mois)',
    pondeuse: 'Pondeuse (6 à 18 mois)',
};

const ESPECES = { cuniculture: LAPINS, porciculture: PORCS };
const STADE_VERS_CATEGORIE = { reproduction: 'repro', croissance: 'sevre', engraissement: 'jeune' };

const entier = (v) => Math.trunc(Number(v ?? 0)) || 0;
const somme = (liste) => liste.reduce((s, v) => s + v, 0);
const estNul = (v) => v === null || v === undefined;

/** Veille + entrées − sorties, SANS plancher (null si une entrée est inconnue). */
function brut(base, plus, moins) {
    if (estNul(base) || plus.some(estNul) || moins.some(estNul)) return null;
    return base + somme(plus) - somme(moins);
}

/** Idem, borné à 0. */
function appliquer(base, plus, moins) {
    const b = brut(base, plus, moins);
    return b === null ? null : Math.max(0, b);
}

export const estVolailles = (espece) => espece === VOLAILLES_REPRO || espece === VOLAILLES_PONTE;

export const emplacementsDe = (espece) => (espece === VOLAILLES_PONTE ? ['repro', 'sevre', 'jeune', 'quatre'] : ['repro', 'sevre', 'jeune']);

export const colonne = (prefixe, emplacement) => `${prefixe}_${emplacement === 'quatre' ? '4' : emplacement}`;

/**
 * Effectifs par catégorie d'UNE journée. `veille` : `{repro, sevre, jeune[, quatre]}` ; `mouvements` : clés du serveur (achat, ne,
 * vente[_repro|_sevre|_jeune|_4], mort_*, don_*, passage*, transfert_entree_*, transfert_sortie_*) ; `totalFinal` : effectif total de fin de
 * journée (indicateur « somme ≠ total »).
 *
 * @returns {{repro:?number, sevre:?number, jeune:?number, sommeDifferente:?boolean, refus:?string, passageApplique:?number, quatre:?number, passagesAppliques:object}}
 */
export function calculerJour(espece, veille, mouvements, totalFinal = null) {
    if (![LAPINS, PORCS, VOLAILLES_REPRO, VOLAILLES_PONTE].includes(espece)) {
        throw new Error(`Espèce non prise en charge : ${espece}.`);
    }
    if (espece === VOLAILLES_REPRO) return calculerJourVolailles(veille, mouvements, totalFinal);
    if (espece === VOLAILLES_PONTE) return calculerJourPondeuses(veille, mouvements, totalFinal);

    const lapins = espece === LAPINS;
    const m = (cle) => mouvements[cle] ?? null;
    const t = (cle) => entier(mouvements[cle]);

    // Reproducteur : ne change jamais de stade ; les achats de porcs lui reviennent.
    const repro = appliquer(
        veille.repro ?? null,
        [...(lapins ? [] : [m('achat')]), t('transfert_entree_repro')],
        [m('mort_repro'), m('don_repro'), t('transfert_sortie_repro')],
    );

    // Catégorie « sevre » avant passage : les lapins achetés y entrent, les nés aussi.
    const avant = brut(
        veille.sevre ?? null,
        [...(lapins ? [m('achat'), m('ne')] : [m('ne')]), t('transfert_entree_sevre')],
        [m('mort_sevre'), m('don_sevre'), t('transfert_sortie_sevre')],
    );

    const passage = m('passage');
    let refus = null;
    let passageApplique;
    if (passage === null) {
        passageApplique = null;
    } else {
        passageApplique = passage;
        if (avant !== null && passage > Math.max(0, avant)) {
            const source = Math.max(0, avant);
            passageApplique = source;
            refus = `Passage de stade refusé : ${passage} sujet(s) à faire passer, mais la catégorie source n'en compte que ${source}.`;
        }
    }

    const sevre = (avant === null || passageApplique === null) ? null : Math.max(0, avant - passageApplique);
    const jeune = appliquer(
        veille.jeune ?? null,
        [passageApplique, t('transfert_entree_jeune')],
        [m('vente'), m('mort_jeune'), m('don_jeune'), t('transfert_sortie_jeune')],
    );

    let sommeDifferente = null;
    if (repro !== null && sevre !== null && jeune !== null && !estNul(totalFinal)) {
        sommeDifferente = (repro + sevre + jeune) !== totalFinal;
    }
    return { repro, sevre, jeune, sommeDifferente, refus, passageApplique, quatre: null, passagesAppliques: {} };
}

function calculerJourVolailles(veille, mouvements, totalFinal) {
    const m = (cle) => entier(mouvements[cle]);
    const v = (cle) => entier(veille[cle]);

    const repro = Math.max(0, v('repro') + m('transfert_entree_repro')
        - m('vente_repro') - m('mort_repro') - m('don_repro') - m('transfert_sortie_repro'));

    const avant = v('sevre') + m('ne') + m('transfert_entree_sevre')
        - m('vente_sevre') - m('mort_sevre') - m('don_sevre') - m('transfert_sortie_sevre');

    const passage = m('passage');
    let refus = null;
    let passageApplique = passage;
    if (passage > Math.max(0, avant)) {
        const source = Math.max(0, avant);
        passageApplique = source;
        refus = `Passage de stade refusé : ${passage} sujet(s) à faire passer, mais la catégorie source n'en compte que ${source}.`;
    }

    const poussin = Math.max(0, avant - passageApplique);
    // Les ACHATS vont aux Jeunes.
    const jeune = Math.max(0, v('jeune') + m('achat') + passageApplique + m('transfert_entree_jeune')
        - m('vente_jeune') - m('mort_jeune') - m('don_jeune') - m('transfert_sortie_jeune'));

    const sommeDifferente = estNul(totalFinal) ? null : ((repro + poussin + jeune) !== totalFinal);
    return { repro, sevre: poussin, jeune, sommeDifferente, refus, passageApplique, quatre: null, passagesAppliques: {} };
}

function calculerJourPondeuses(veille, mouvements, totalFinal) {
    const m = (cle) => entier(mouvements[cle]);
    const v = (cle) => entier(veille[cle]);
    const refus = [];
    const borne = (demande, avant, source, cible) => {
        const disponible = Math.max(0, avant);
        if (demande > disponible) {
            refus.push(`Passage de stade refusé (${source} vers ${cible}) : ${demande} sujet(s) à faire passer, mais le stade source n'en compte que ${disponible}.`);
            return disponible;
        }
        return demande;
    };
    const l = LIBELLES_STADE_PONDEUSE;

    const avantPP = v('quatre') + m('ne') + m('transfert_entree_4')
        - m('vente_4') - m('mort_4') - m('don_4') - m('transfert_sortie_4');
    const p1 = borne(m('passage_4_sevre'), avantPP, l.poussin_ponte, l.poussin_croissance);
    const pp = Math.max(0, avantPP - p1);

    const avantPC = v('sevre') + p1 + m('transfert_entree_sevre')
        - m('vente_sevre') - m('mort_sevre') - m('don_sevre') - m('transfert_sortie_sevre');
    const p2 = borne(m('passage'), avantPC, l.poussin_croissance, l.poulette);
    const pc = Math.max(0, avantPC - p2);

    const avantPL = v('jeune') + m('achat') + p2 + m('transfert_entree_jeune')
        - m('vente_jeune') - m('mort_jeune') - m('don_jeune') - m('transfert_sortie_jeune');
    const p3 = borne(m('passage_jeune_repro'), avantPL, l.poulette, l.pondeuse);
    const pl = Math.max(0, avantPL - p3);

    const po = Math.max(0, v('repro') + p3 + m('transfert_entree_repro')
        - m('vente_repro') - m('mort_repro') - m('don_repro') - m('transfert_sortie_repro'));

    const sommeDifferente = estNul(totalFinal) ? null : ((pp + pc + pl + po) !== totalFinal);
    return {
        repro: po, sevre: pc, jeune: pl, sommeDifferente, refus: refus.length === 0 ? null : refus.join(' '), passageApplique: p2, quatre: pp,
        passagesAppliques: { passage_4_sevre: p1, passage_sevre_jeune: p2, passage_jeune_repro: p3 },
    };
}

/**
 * Contrôle du départ saisi : trois catégories renseignées (QUATRE stades pour les pondeuses : clé `quatre` présente) dont la somme
 * égale l'effectif total au début du jour de départ. Rend le motif du refus, ou `null`.
 */
export function verifierDepart(depart, totalDepart) {
    if (Object.hasOwn(depart, 'quatre')) return verifierDepartPondeuses(depart, totalDepart);

    const r = depart.repro ?? null;
    const s = depart.sevre ?? null;
    const j = depart.jeune ?? null;

    if (r === null || s === null || j === null) {
        return 'Effectif de départ incomplet : les trois catégories doivent être renseignées (0 si la catégorie est vide).';
    }
    if (estNul(totalDepart)) {
        return `Effectif total de départ inconnu : la somme des catégories (${r} + ${s} + ${j}) ne peut pas être contrôlée.`;
    }
    if (r + s + j !== totalDepart) {
        return `La somme des catégories de départ (${r + s + j}) ne correspond pas à l'effectif total au début du jour de départ (${totalDepart}).`;
    }
    return null;
}

function verifierDepartPondeuses(depart, totalDepart) {
    const valeurs = ['quatre', 'sevre', 'jeune', 'repro'].map((c) => depart[c] ?? null);
    if (valeurs.includes(null)) {
        return 'Effectif de départ incomplet : les quatre stades doivent être renseignés (0 si le stade est vide).';
    }
    const total = somme(valeurs);
    if (estNul(totalDepart)) {
        return `Effectif total de départ inconnu : la somme des stades (${valeurs[0]} + ${valeurs[1]} + ${valeurs[2]} + ${valeurs[3]}) ne peut pas être contrôlée.`;
    }
    if (total !== totalDepart) {
        return `La somme des stades de départ (${total}) ne correspond pas à l'effectif total au début du jour de départ (${totalDepart}).`;
    }
    return null;
}

/** Espèce de calcul d'une bande : `{species_code, stage}` (l'aviculture se partage entre pondeuses — stade `ponte` — et reproducteurs). */
export function especeDuLot(lot) {
    const code = lot?.species_code ?? null;
    if (code === 'aviculture') return lot.stage === 'ponte' ? VOLAILLES_PONTE : VOLAILLES_REPRO;
    return ESPECES[code] ?? null;
}

/** Catégorie (repro / sevre / jeune) d'un stade de bande ; `null` pour `ponte` ou un stade inconnu. */
export const categorieDuStade = (stade) => STADE_VERS_CATEGORIE[stade] ?? null;

/** Catégorie proposée pour les sujets d'une bande : celle de son stade ; « Pondeuse » (`repro`) pour une bande de pondeuses. */
export const categorieDeLaBande = (lot) => (especeDuLot(lot) === VOLAILLES_PONTE ? 'repro' : categorieDuStade(lot?.stage));

/** Effectif de départ DÉDUIT du stade de la bande (rationnement automatique) ; `null` : espèce sans catégories ou stade sans catégorie. */
export function departDepuisStade(lot, totalDebutJour) {
    if (especeDuLot(lot) === VOLAILLES_PONTE) {
        return { repro: Math.max(0, totalDebutJour), sevre: 0, jeune: 0, quatre: 0 };
    }
    const emplacement = STADE_VERS_CATEGORIE[lot?.stage] ?? null;
    if (especeDuLot(lot) === null || emplacement === null) return null;
    return { repro: 0, sevre: 0, jeune: 0, [emplacement]: Math.max(0, totalDebutJour) };
}
