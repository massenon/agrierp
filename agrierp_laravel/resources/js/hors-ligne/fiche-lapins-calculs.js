/**
 * PWA-3 (fiche lapins) — CALCUL DE LA PROVENDE DU JOUR, EN JAVASCRIPT PUR.
 *
 * Transposition de `App\\Support\\CategorieRationLapin` (clé stable des catégories de rationnement, ticket 15.36, glossaire du 17/10/2026)
 * et de `Livewire\\Elevage\\FicheLapins::getProvendeCalculationProperty` : ration normative (g/j) × effectif de chaque catégorie. Une catégorie
 * INCONNUE (`null`) donne une ligne « — » et un total inconnu : jamais une provende partielle présentée comme complète. Parité exécutée contre le
 * vrai PHP : `tests/Js/parite-fiche-lapins.test.mjs`.
 *
 * Emplacements de synchronisation INCHANGÉS : `sevre` = Sous-mères, `jeune` = Jeune.
 */

import { arrondiPhp } from './calculs-caisse.js';

export const REPRODUCTEUR = 'reproducteur';
export const SOUS_MERES = 'sous_meres';
export const CHAIR = 'chair';

/** Valeurs de secours (g/j) — utilisées UNIQUEMENT si le barème ne porte pas la catégorie. */
export const RATIONS_DE_SECOURS = { [REPRODUCTEUR]: 120, [SOUS_MERES]: 30, [CHAIR]: 60 };

/** Libellés affichés (décision client du 17/10/2026). */
export const LIBELLES = { [REPRODUCTEUR]: 'Reproducteur', [SOUS_MERES]: 'Sous-mères', [CHAIR]: 'Jeune' };

/** `Str::lower(Str::ascii(trim(...)))` : sans accents ni casse. */
const ascii = (t) => String(t ?? '').trim().replace(/œ/gi, 'oe').replace(/æ/gi, 'ae').normalize('NFD').replace(/\p{M}/gu, '').toLowerCase();

/** Clé d'un libellé de barème (ancien ou nouveau), ou `null` s'il n'en relève pas. */
export function cleRation(libelle) {
    const l = ascii(libelle);
    if (l === '') return null;
    if (l.includes('reproducteur')) return REPRODUCTEUR;
    // Avant « jeune » : « Sous-mères » et l'ancien « Lapin Sevré » sont la petite catégorie.
    if (l.includes('sous-mere') || l.includes('sous mere') || l.includes('sevre')) return SOUS_MERES;
    // « Jeune » en ÉGALITÉ STRICTE (jamais « Jeunes » ni « Jeune porc »), et les anciens libellés.
    if (l.includes('engraissement') || l.includes('chair') || l === 'jeune') return CHAIR;
    return null;
}

/** Ration (g/j) d'une catégorie : celle du barème (première ligne qui en relève) si elle existe, sinon la valeur de secours. */
export function rationDe(rations, cle) {
    const ligne = rations.find((r) => cleRation(r.stage_label) === cle);
    return Math.trunc(Number(ligne?.ration_g_per_day ?? RATIONS_DE_SECOURS[cle])) || 0;
}

/**
 * `getProvendeCalculationProperty` : provende servie par catégorie et total (g, kg arrondi à 2 décimales).
 *
 * @param {{repro:?number, sevre:?number, jeune:?number}} cat  effectifs du jour par catégorie (`null` = inconnu)
 * @param {{stage_label:string, ration_g_per_day:number}[]} rations  barème des lapins (`feed_ration_standards`, espèce cuniculture)
 */
export function provendeDuJour(cat, rations) {
    const ligne = (effectif, ration) => ({ ration, effectif, total_g: effectif === null || effectif === undefined ? null : effectif * ration });
    const repro = ligne(cat.repro ?? null, rationDe(rations, REPRODUCTEUR));
    const sousMeres = ligne(cat.sevre ?? null, rationDe(rations, SOUS_MERES));
    const chair = ligne(cat.jeune ?? null, rationDe(rations, CHAIR));
    const inconnu = repro.total_g === null || sousMeres.total_g === null || chair.total_g === null;
    const total = inconnu ? null : repro.total_g + sousMeres.total_g + chair.total_g;
    return { repro, sous_meres: sousMeres, chair, total_g: total, total_kg: total === null ? null : arrondiPhp(total / 1000, 2) };
}
