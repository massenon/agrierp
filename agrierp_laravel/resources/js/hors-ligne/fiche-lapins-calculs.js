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

// ------------------------------------------------------------------------------------------ autonomie alimentaire (É5)

/** `ReleveTerrainService::CRITIQUE_DEPART` : seuil critique d'autonomie (jours) tant qu'aucune règle n'est validée. */
export const SEUIL_CRITIQUE_DEPART_JOURS = 3;
const sansAccent = (t) => String(t ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

/** `AutonomieAlimentaireService::produitProvende` : le premier produit (par identifiant) de l'espèce dont le nom contient « provende » ou « aliment ». */
export function produitProvende(produits, especeIds) {
    return [...produits]
        .filter((p) => especeIds.includes(p.species_id) && (sansAccent(p.name).includes('provende') || sansAccent(p.name).includes('aliment')))
        .sort((a, b) => (String(a.id) < String(b.id) ? -1 : 1))[0] ?? null;
}

/** `Product::stockEnKg` : un sac vaut le poids du premier type de provende (par identifiant), 25 kg à défaut. */
export function stockEnKg(produit, feedTypes) {
    const quantite = Number(produit.stock_qty ?? 0) || 0;
    if (produit.unit !== 'sac') return quantite;
    const premier = [...feedTypes].sort((a, b) => (String(a.id) < String(b.id) ? -1 : 1))[0];
    return arrondiPhp(quantite * (Number(premier?.standard_bag_weight_kg) || 25), 2);
}

/** `ReleveTerrainService::NB_BONS` : nombre de bons de commande reçus retenus par fournisseur. */
export const NB_BONS = 5;
const joursEntre = (a, b) => Math.round((Date.UTC(+b.slice(0, 4), +b.slice(5, 7) - 1, +b.slice(8, 10)) - Date.UTC(+a.slice(0, 4), +a.slice(5, 7) - 1, +a.slice(8, 10))) / 86400000);

/**
 * `ReleveTerrainService::delaisFournisseurs` : les 5 DERNIERS bons de commande REÇUS portant une ligne de la catégorie « Aliments », par
 * fournisseur, du jour du bon (`created_at`) au jour de la réception (`purchase_date` de l'achat qui l'a reçu), jamais négatif ;
 * proposition critique = le plus long des 5 (seulement avec 5 bons).
 *
 * @returns {{supplier_id:string, nb:number, delais:number[], critique_propose:?number}[]}
 */
export function delaisFournisseurs({ bons, achats, produits, categories }) {
    const achatDuBon = new Map();
    for (const a of achats) if (a.purchase_order_id && !achatDuBon.has(a.purchase_order_id)) achatDuBon.set(a.purchase_order_id, a);
    const etiquette = new Map(categories.map((c) => [c.id, c.label]));
    const categorieDe = new Map(produits.map((p) => [p.id, etiquette.get(p.category_id)]));
    const parFournisseur = new Map();
    for (const b of bons) {
        if (b.status !== 'recu' || !achatDuBon.has(b.id) || !b.created_at) continue;
        if (!(b.lines ?? []).some((l) => categorieDe.get(l.product_id) === 'Aliments')) continue;
        parFournisseur.set(b.supplier_id ?? '', [...(parFournisseur.get(b.supplier_id ?? '') ?? []), b]);
    }
    const sortie = [];
    for (const [fournisseur, groupe] of parFournisseur) {
        const horodatage = (b) => `${String(achatDuBon.get(b.id).purchase_date).slice(0, 10)}${String(b.created_at).slice(0, 10)} ${String(b.created_at).slice(11, 19)}${b.id}`;
        const retenus = [...groupe].sort((x, y) => (horodatage(x) < horodatage(y) ? 1 : -1)).slice(0, NB_BONS);
        const delais = retenus.map((b) => Math.max(0, joursEntre(String(b.created_at).slice(0, 10), String(achatDuBon.get(b.id).purchase_date).slice(0, 10))));
        sortie.push({ supplier_id: String(fournisseur), nb: delais.length, delais, critique_propose: delais.length >= NB_BONS ? Math.max(...delais) : null });
    }
    return sortie;
}

/**
 * `ReleveTerrainService::regleEnVigueur` (la part « seuil critique ») : la ligne `delai_regle` active de plus petit identifiant ; son
 * `critique_jours` (3 par défaut) ; règle VALIDÉE en mode « constaté » : le plus long des délais proposés (fournisseurs ayant 5 bons).
 * `delais` : résultat de `delaisFournisseurs`, ou `null` quand le compte ne lit pas les bons de commande (`view-achats`) : le seuil est alors
 * porté `incertain` (l'écran le dit, jamais une valeur inventée).
 */
export function seuilCritique(releves, delais = null) {
    const ligne = [...releves].filter((r) => r.type === 'delai_regle' && r.is_active !== false).sort((a, b) => (String(a.id) < String(b.id) ? -1 : 1))[0] ?? null;
    let d = ligne?.data ?? {};
    if (typeof d === 'string') { try { d = JSON.parse(d); } catch { d = {}; } }
    let critique = Math.trunc(Number(d.critique_jours ?? SEUIL_CRITIQUE_DEPART_JOURS)) || 0;
    let incertain = false;
    let source = 'depart';
    if (ligne?.status === 'valide') {
        if ((d.mode ?? 'constate') === 'manuel') source = 'manuel';
        else if (delais === null) incertain = true;
        else {
            const propositions = delais.map((x) => x.critique_propose).filter((v) => v !== null && v !== undefined);
            if (propositions.length > 0) { critique = Math.max(...propositions); source = 'constate'; }
        }
    }
    return { critique, incertain, source };
}

/** `AutonomieAlimentaireService::evaluer`. `consommationKgJour` : `null` = inconnue. */
export function evaluerAutonomie(produit, consommationKgJour, feedTypes, releves, delais = null) {
    if (!produit) return { available: false };
    const stockKg = stockEnKg(produit, feedTypes);
    const rupture = stockKg <= 0;
    const seuil = seuilCritique(releves, delais);
    if (consommationKgJour === null || consommationKgJour === undefined) {
        return { available: true, inconnu: true, product: produit, stock_kg: stockKg, autonomie_jours: null, critique: rupture, rupture, seuilIncertain: seuil.incertain };
    }
    const autonomieJours = consommationKgJour > 0 ? arrondiPhp(stockKg / consommationKgJour, 1) : 99;
    return { available: true, product: produit, stock_kg: stockKg, autonomie_jours: autonomieJours, critique: rupture || autonomieJours <= seuil.critique, rupture, seuilIncertain: seuil.incertain };
}

// ------------------------------------------------------------------------------------------------- porcs (PWA-3, fiche porcs)

export const PORC_REPRODUCTEUR = 'reproducteur';
export const PORC_PORCELET = 'porcelet';
export const PORC_MARCHAND = 'marchand';
/** `CategorieRationPorc::RATIONS_DE_SECOURS` — UNIQUEMENT si le barème ne porte pas la catégorie. */
export const RATIONS_PORCS_DE_SECOURS = { [PORC_REPRODUCTEUR]: 2000, [PORC_PORCELET]: 300, [PORC_MARCHAND]: 600 };
/** `CategorieRationPorc::LIBELLES` : « Porc Marchand » est le libellé de la maquette (D15), le barème dit « Jeune porc ». */
export const LIBELLES_PORCS = { [PORC_REPRODUCTEUR]: 'Reproducteur', [PORC_PORCELET]: 'Porcelet', [PORC_MARCHAND]: 'Porc Marchand' };

/** `CategorieRationPorc::cle`. */
export function cleRationPorc(libelle) {
    const l = ascii(libelle);
    if (l === '') return null;
    if (l.includes('reproducteur')) return PORC_REPRODUCTEUR;
    if (l.includes('porcelet')) return PORC_PORCELET;
    if (l.includes('marchand') || l.includes('engraissement') || /^jeune( porc)?$/.test(l)) return PORC_MARCHAND;
    return null;
}

/** `CategorieRationPorc::ration`. */
export function rationPorc(rations, cle) {
    const ligne = rations.find((r) => cleRationPorc(r.stage_label) === cle);
    return Math.trunc(Number(ligne?.ration_g_per_day ?? RATIONS_PORCS_DE_SECOURS[cle])) || 0;
}

/** `FichePorcs::getProvendeCalculationProperty` : porcelet (`sevre`), porc marchand (`jeune`), reproducteur (`repro`). */
export function provendeDuJourPorcs(cat, rations) {
    const ligne = (effectif, ration) => ({ ration, effectif, total_g: effectif === null || effectif === undefined ? null : effectif * ration });
    const porcelet = ligne(cat.sevre ?? null, rationPorc(rations, PORC_PORCELET));
    const jeune = ligne(cat.jeune ?? null, rationPorc(rations, PORC_MARCHAND));
    const repro = ligne(cat.repro ?? null, rationPorc(rations, PORC_REPRODUCTEUR));
    const inconnu = porcelet.total_g === null || jeune.total_g === null || repro.total_g === null;
    const total = inconnu ? null : porcelet.total_g + jeune.total_g + repro.total_g;
    return { porcelet, jeune, repro, total_g: total, total_kg: total === null ? null : arrondiPhp(total / 1000, 2) };
}

// -------------------------------------------------------------------------- volailles reproductrices (PWA-3, fiche reproducteurs)

/** `CategorieVolaille::RATIONS_PROVISOIRES` — UNIQUEMENT si le barème ne porte pas la ligne. */
export const RATIONS_VOLAILLES_PROVISOIRES = { reproducteur: 130, jeune: 80, poussin: 30 };
export const LIBELLES_VOLAILLES = { reproducteur: 'Reproducteur', jeune: 'Jeune', poussin: 'Poussin' };
/** `CategorieVolaille::EMPLACEMENTS` : reproducteur → `repro`, jeune → `jeune`, poussin → `sevre`. */
export const EMPLACEMENTS_VOLAILLES = { reproducteur: 'repro', jeune: 'jeune', poussin: 'sevre' };

/** `CategorieVolaille::cleDuLibelle` : ÉGALITÉ STRICTE du libellé normalisé (jamais une sous-chaîne), `null` sinon. */
export function cleVolaille(libelle) {
    const l = ascii(libelle);
    return Object.entries(LIBELLES_VOLAILLES).find(([, affiche]) => ascii(affiche) === l)?.[0] ?? null;
}

/** `CategorieVolaille::ration`. */
export function rationVolaille(rations, cle) {
    const ligne = rations.find((r) => cleVolaille(r.stage_label) === cle);
    return Math.trunc(Number(ligne?.ration_g_per_day ?? RATIONS_VOLAILLES_PROVISOIRES[cle])) || 0;
}

/** `CategorieVolaille::tableauReproducteurs` : une ligne par catégorie (effectif calculé × ration), total g et kg (2 décimales), `null` si une catégorie est inconnue. */
export function tableauReproducteurs(rations, effectifs) {
    const lignes = Object.keys(LIBELLES_VOLAILLES).map((cle) => {
        const effectif = effectifs[EMPLACEMENTS_VOLAILLES[cle]] ?? null;
        const ration = rationVolaille(rations, cle);
        return { cle, libelle: LIBELLES_VOLAILLES[cle], ration, effectif: effectif === null ? null : Math.trunc(effectif), total_g: effectif === null ? null : Math.trunc(effectif) * ration };
    });
    const inconnu = lignes.some((l) => l.total_g === null);
    const total = inconnu ? null : lignes.reduce((s, l) => s + l.total_g, 0);
    return { lignes, total_g: total, total_kg: total === null ? null : arrondiPhp(total / 1000, 2) };
}

// -------------------------------------------------------------------------- volailles pondeuses (PWA-3, fiche pondeuses)

/** `EggStockLedgerService::OEUFS_PAR_PLATEAU`. */
export const OEUFS_PAR_PLATEAU = 30;
/** `StadePondeuse::CLES` (ordre du barème) et `LIBELLES` (tranche d'âge comprise, affichée telle quelle). */
export const CLES_STADES_PONDEUSE = ['poussin_ponte', 'poussin_croissance', 'poulette', 'pondeuse'];
export const LIBELLES_STADES_PONDEUSE = {
    poussin_ponte: 'Poussin ponte (0 à 2 mois)', poussin_croissance: 'Poussin en croissance (2 à 4 mois)', poulette: 'Poulette (4 à 5.5 mois)', pondeuse: 'Pondeuse (6 à 18 mois)',
};
/** `StadePondeuse::EMPLACEMENTS`. */
export const EMPLACEMENTS_STADES_PONDEUSE = { pondeuse: 'repro', poulette: 'jeune', poussin_croissance: 'sevre', poussin_ponte: 'quatre' };
/** `StadePondeuse::RATIONS_PAR_DEFAUT` — UNIQUEMENT si le barème ne porte pas la ligne. */
export const RATIONS_STADES_PONDEUSE_PAR_DEFAUT = { poussin_ponte: 30, poussin_croissance: 60, poulette: 80, pondeuse: 110 };

/** `StadePondeuse::normaliser` : la tranche d'âge entre parenthèses est ignorée, ASCII, minuscules, espaces réduits. */
const normaliserStade = (t) => sansAccent(String(t ?? '').replace(/\([^)]*\)/gu, ' ')).replace(/\s+/gu, ' ').trim();

/** `StadePondeuse::cleDuLibelle` : ÉGALITÉ STRICTE du libellé normalisé, `null` sinon. */
export function cleStadePondeuse(libelle) {
    const l = normaliserStade(libelle);
    return CLES_STADES_PONDEUSE.find((c) => l === normaliserStade(LIBELLES_STADES_PONDEUSE[c])) ?? null;
}

/** `StadePondeuse::ration`. */
export function rationStadePondeuse(rations, cle) {
    const ligne = rations.find((r) => cleStadePondeuse(r.stage_label) === cle);
    return Math.trunc(Number(ligne?.ration_g_per_day ?? RATIONS_STADES_PONDEUSE_PAR_DEFAUT[cle])) || 0;
}

/** `StadePondeuse::tableau` : une ligne par stade (effectif calculé × ration), total g et kg (2 décimales), `null` si un stade est inconnu. */
export function tableauPondeuses(rations, effectifs) {
    const lignes = CLES_STADES_PONDEUSE.map((cle) => {
        const effectif = effectifs[EMPLACEMENTS_STADES_PONDEUSE[cle]] ?? null;
        const ration = rationStadePondeuse(rations, cle);
        return { cle, libelle: LIBELLES_STADES_PONDEUSE[cle], ration, effectif: effectif === null ? null : Math.trunc(effectif), total_g: effectif === null ? null : Math.trunc(effectif) * ration };
    });
    const total = lignes.some((l) => l.total_g === null) ? null : lignes.reduce((s, l) => s + l.total_g, 0);
    return { lignes, total_g: total, total_kg: total === null ? null : arrondiPhp(total / 1000, 2) };
}
