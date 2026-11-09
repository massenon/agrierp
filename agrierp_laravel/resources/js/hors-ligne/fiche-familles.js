/**
 * PWA-3 — LES FAMILLES DE LA VUE COMMUNE LAPINS / PORCS : tout ce qui change d'une fiche à l'autre (espèce, libellés, ordre des champs et des colonnes,
 * unité du poids, KPI, provende) et RIEN d'autre. Les écrans (`fiche-lapins-ecran.js`), la saisie (`fiche-lapins-saisie.js`), la provende
 * (`fiche-lapins-calculs.js`) et la prophylaxie (`fiche-lapins-prophylaxie.js`) prennent une famille en paramètre (lapins par défaut) : une seule
 * logique, prouvée contre le vrai PHP pour chacune. Les NOMS INTERNES de la saisie sont ceux des emplacements de synchronisation :
 * `mortChair` / `donChair` / `departJeune` = emplacement `jeune`, `mortLapereau` / `donLapereau` / `departSevre` = emplacement `sevre`,
 * `effectifM` / `F` / `Sevres` / `Smeres` = colonnes `effectif_m` / `_f` / `_sevres` / `_smeres`, `peseeTotal` = poids total pesé (g pour les lapins,
 * Kg pour les porcs). Les libellés sont lus dans `fiche-lapins.blade.php` / `fiche-porcs.blade.php` par les gardes de sources.
 */

import { LAPINS, PORCS, VOLAILLES_REPRO } from './effectif-categories.js';
import { provendeDuJour, provendeDuJourPorcs } from './fiche-lapins-calculs.js';

/** Libellés communs aux deux écrans (identiques dans les deux Blade). */
export const ECRAN_COMMUN = {
    exportPdf: 'Exporter PDF',
    exportPdfHorsLigne: 'Export PDF disponible en ligne seulement.',
    bande: 'Bande :', date: 'Date :', mois: 'Mois :', moisPrecedent: 'Mois précédent', moisSuivant: 'Mois suivant',
    transferts: 'Transferts entre bandes ce jour :',
    transfertsSuite: "— compris dans l'effectif final. Ils se modifient depuis l'écran",
    transfertsEcran: 'Transferts entre Bandes',
    vide: '—',
};

const GROUPES = (poids, colonnes = 5) => [['Date', 'rowspan'], ['Entrées', 2], ['Sorties', 3], ['Effectif Final du Jour', colonnes], ['Taux Mort %', 'rowspan'], [poids, 'rowspan'], ['Traitements & Prophylaxie', 'rowspan']];
const nombre = (n) => String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
const virgule = (n) => Number(n).toFixed(1).replace('.', ',');

export const LAPINS_F = {
    id: 'lapins', espece: 'cuniculture', calcul: LAPINS, filiere: 'cuniculture', bouton: 'Fiches Lapins', icone: 'cruelty_free',
    kg: false,
    ecran: {
        titre: 'Fiches Lapins - Cuniculture',
        sousTitre: 'Fiche de suivi mensuel du cheptel — transcription fidèle du registre de la ferme.',
        kpis: ['Effectif Total Vivant', 'Géniteurs (M/F)', 'Naissances du Mois', 'Taux de Mortalité'],
        kpiIcones: ['pets', 'favorite', 'child_care', 'trending_down'],
        aucuneBande: 'Aucune bande active en cuniculture pour le moment.',
        saisieTitre: 'Saisie Journalière du Cheptel',
        groupes: GROUPES('Poids Général (g)'),
        sousColonnes: ['Achat', 'Né', 'Mort', 'Vente', 'Don', 'M', 'F', 'Jeunes', 'S/Mères', 'Total'],
        colonnesEffectif: ['effectif_m', 'effectif_f', 'effectif_sevres', 'effectif_smeres'],
    },
    /** Les quatre valeurs de KPI affichées (`fiche-*.blade.php`, `x-kpi-card`). */
    kpiValeurs: (k) => [nombre(k.effectif_total), `${k.geniteurs_m} / ${k.geniteurs_f}`, String(k.naissances_mois), `${virgule(k.taux_mortalite_mois)} %`],
    motifs: {
        aucuneBande: "Aucune bande active en cuniculture. Créez d'abord une bande.",
        ancienneFiche: "Cette fiche porte des morts ou des dons non ventilés par catégorie : ventilez-les (Reproducteur / Jeune / Sous-mères) avant d'enregistrer.",
    },
    libelles: {
        titre: 'Saisie Journalière du Cheptel',
        achat: 'Achats du jour', ne: 'Nés (Mise bas)', vente: 'Ventes', venteSuite: '(POS, réel)',
        morts: 'Morts par catégorie', dons: 'Dons par catégorie',
        reproducteur: 'Reproducteur', jeune: 'Jeune', sousMeres: 'Sous-mères',
        mortsCat: ['Reproducteur', 'Jeune', 'Sous-mères'], donsCat: ['Reproducteur', 'Jeune', 'Sous-mères'],
        passage: 'Sevrage du jour (Sous-mères → Jeune)',
        departSaisissable: 'Effectif de départ par catégorie (déduit du stade de la bande)', departVerrouille: 'Effectif de départ par catégorie (verrouillé)',
        ordreDepart: [['departRepro', 'repro', 'Reproducteur'], ['departJeune', 'jeune', 'Jeune'], ['departSevre', 'sevre', 'Sous-mères']],
        effectifM: 'Effectif Mâles', effectifF: 'Effectif Femelles', effectifSevres: 'Jeunes', effectifSmeres: 'S/Mères',
        effectifFinal: 'Effectif Final du Jour (Calculé dynamique)', taux: 'Taux de Mortalité du Jour (%)',
        pesee: 'Poids Général Pesé (g)', echantillon: 'Taille Échantillon', echantillonAuto: '(Auto = Effectif Final)', poidsMoyen: 'Poids Moyen Constaté',
        peseeExemple: 'ex : 3500',
        gmq: 'Poids moyen estimé (GMQ) :', enregistrer: 'Enregistrer ce Jour',
        provende: 'Rationnement & Provende Servie par Catégorie (en Grammes g/j)', categorie: 'Catégorie', effectif: 'Effectif', ration: 'Ration Normative', servie: 'Provende Servie (g)',
        totalProvende: 'TOTAL PROVENDE SERVIE DU JOUR (CUMUL EN GRAMMES)',
        lignesProvende: [['repro', 'repro', 'Reproducteur'], ['chair', 'chair', 'Jeune'], ['sous_meres', 'lapereau', 'Sous-mères']],
    },
    provende: (cat, rations) => provendeDuJour(cat, rations),
    rationAffichee: (cle, ration) => `${ration} g/j`,
    prophylaxie: { titre: 'Traitements & Prophylaxie', observations: 'Observations / Notes Additionnelles', observationsExemple: "ex : RAS, légère perte d'appétit cage C3..." },
    categories: (r) => [r.repro, r.sevre, r.jeune],
};

export const PORCS_F = {
    id: 'porcs', espece: 'porciculture', calcul: PORCS, filiere: 'porcine', bouton: 'Fiches Porcs', icone: 'pets',
    kg: true,
    ecran: {
        titre: 'Fiches Porcs - Porciculture',
        sousTitre: 'Fiche de suivi mensuel du cheptel porcin — engraissement, maternité et reproduction.',
        kpis: ['Effectif Porcins Vivants', 'Truies Gestantes / Verrats', 'Porcelets sous Mère', 'Taux de Mortalité'],
        kpiIcones: ['pets', 'favorite', 'child_care', 'trending_down'],
        aucuneBande: 'Aucune bande active en porciculture pour le moment.',
        saisieTitre: 'Saisie Journalière du Cheptel Porcin',
        groupes: GROUPES('Poids Général (Kg)'),
        sousColonnes: ['Achat', 'Né', 'Mort', 'Vente', 'Don', 'Truies Gest.', 'Verrats', 'Porcelets', 'Engraiss.', 'Total'],
        colonnesEffectif: ['effectif_f', 'effectif_m', 'effectif_sevres', 'effectif_smeres'],
    },
    kpiValeurs: (k) => [nombre(k.effectif_total), `${k.truies} Truies / ${k.verrats} Verrats`, String(k.porcelets_sous_mere), `${virgule(k.taux_mortalite_mois)} %`],
    motifs: {
        aucuneBande: "Aucune bande active en porciculture. Créez d'abord une bande.",
        ancienneFiche: "Cette fiche porte des morts ou des dons non ventilés par catégorie : ventilez-les (Reproducteur / Porc Marchand / Porcelet) avant d'enregistrer.",
    },
    libelles: {
        titre: 'Saisie Journalière du Cheptel Porcin',
        achat: 'Achats du jour', ne: 'Nés (Mise bas porcelets)', vente: 'Ventes', venteSuite: '(POS, réel)',
        morts: 'Morts par catégorie', dons: 'Dons par catégorie',
        reproducteur: 'Reproducteur', jeune: 'Porc Marchand', sousMeres: 'Porcelet',
        mortsCat: ['Reproducteur (Truie/Verrat)', 'Porc marchand / Engraiss.', 'Porcelet'], donsCat: ['Reproducteur', 'Porc marchand', 'Porcelet'],
        passage: 'Passage de stade (Porcelet → Porc Marchand)', passageSuite: '(hors maquette)',
        departSaisissable: 'Effectif de départ par catégorie (déduit du stade de la bande)', departVerrouille: 'Effectif de départ par catégorie (verrouillé)',
        ordreDepart: [['departRepro', 'repro', 'Reproducteur'], ['departSevre', 'sevre', 'Porcelet'], ['departJeune', 'jeune', 'Porc Marchand']],
        effectifM: 'Verrats', effectifF: 'Truies Gestantes', effectifSevres: 'Porcelets', effectifSmeres: 'Engraissement',
        effectifFinal: 'Effectif Final du Jour (Calculé dynamique)', taux: 'Taux de Mortalité du Jour (%)',
        pesee: 'Poids Général Pesé (Kg)', echantillon: 'Effectif Final', echantillonAuto: '(diviseur)', poidsMoyen: 'Poids Moyen Constaté',
        peseeExemple: 'ex : 85',
        gmq: 'Poids moyen estimé (GMQ) :', enregistrer: 'Enregistrer ce Jour',
        provende: 'Rationnement & Provende Servie par Stade Porcin (en Grammes g/j)', categorie: 'Stade Physiologique', effectif: 'Effectif', ration: 'Ration Normative', servie: 'Provende Servie (g)',
        totalProvende: 'TOTAL PROVENDE SERVIE DU JOUR (CUMUL EN GRAMMES)',
        lignesProvende: [['porcelet', 'porcelet', 'Porcelet'], ['jeune', 'jeune', 'Porc Marchand'], ['repro', 'repro', 'Reproducteur']],
    },
    provende: (cat, rations) => provendeDuJourPorcs(cat, rations),
    /** Le Blade des porcs écrit la ration du reproducteur aussi en Kg : « 2 000 g/j (2.0 Kg) ». */
    rationAffichee: (cle, ration) => (cle === 'repro' ? `${nombre(ration)} g/j (${(Math.round((ration / 1000) * 10) / 10).toFixed(1)} Kg)` : `${ration} g/j`),
    prophylaxie: { titre: 'Suivi Clinique & Prophylaxie', observations: 'Observations', observationsExemple: 'ex : RAS' },
    categories: (r) => [r.repro, r.sevre, r.jeune],
};

/**
 * Escargots / héliciculture : PAS la vue commune. Pas de chaîne d'effectif par catégorie (`calcul: null`), pas de rationnement, de prophylaxie ni
 * d'autonomie au web ; la saisie est celle de `fiche-escargots.js`. Le module `helico` doit être activé (`modules_config`).
 */
export const ESCARGOTS_F = {
    id: 'escargots', espece: 'helico', calcul: null, filiere: null, bouton: 'Fiches Escargots', icone: 'bug_report', kg: false, escargots: true, module: 'helico',
    ecran: {
        titre: 'Fiches Escargots - Héliciculture',
        sousTitre: "Suivi mensuel du cheptel d'escargots — ponte en terre, éclosion des naissains et engraissement.",
        kpis: ['Effectif Total Vivant', 'Naissains Nés (mois)', "Taux d'Éclosion Naissains", 'Taux de Mortalité'],
        kpiIcones: ['bug_report', 'child_care', 'egg_alt', 'trending_down'],
        aucuneBande: 'Aucune bande active en héliciculture pour le moment.',
        saisieTitre: 'Saisie Journalière du Cheptel',
        groupes: GROUPES('Poids Général (g)', 4),
        sousColonnes: ['Achat', 'Naissain Né', 'Mort', 'Vente', 'Don', 'Naissains', 'Engraiss.', 'Bordés', 'Total'],
        colonnesEffectif: ['effectif_m', 'effectif_f', 'effectif_sevres'],
    },
    kpiValeurs: (k) => [nombre(k.effectif_total), String(k.naissains_mois), k.taux_eclosion === null ? '—' : `${virgule(k.taux_eclosion)} %`, `${virgule(k.taux_mortalite_mois)} %`],
    motifs: { aucuneBande: "Aucune bande active en héliciculture. Créez d'abord une bande." },
    libelles: {},
    prophylaxie: null,
};

const STADES_AVICULTURE = { reproduction: 'Reproducteur', croissance: 'Poussin', engraissement: 'Jeune', ponte: 'Ponte' };

/**
 * Volailles REPRODUCTEURS (VOL-1) : Reproducteur / Jeune / Poussin (emplacements `repro` / `jeune` / `sevre`), départ OBLIGATOIRE avant toute journée,
 * ventes par catégorie en lecture seule (la caisse les range), passage Poussin → Jeune, couvoir (œufs couvés = `ponte_total`, poussins nés = `ne`).
 * Les bandes : aviculture HORS stade `ponte` (les pondeuses sont l'autre famille). Pas de colonne de traitements au tableau du mois.
 */
export const REPRODUCTEURS_F = {
    id: 'reproducteurs', espece: 'aviculture', calcul: VOLAILLES_REPRO, filiere: 'aviculture', bouton: 'Fiches Reproducteurs', icone: 'grid_view', kg: false, volaille: true,
    accepte: (lot) => lot.species_code === 'aviculture' && lot.stage !== 'ponte',
    libelleStade: (stade) => STADES_AVICULTURE[stade] ?? (stade ? `${String(stade)[0].toUpperCase()}${String(stade).slice(1)}` : ''),
    ecran: {
        titre: 'Fiches Volailles - Reproducteurs, Poussins & Goliath',
        sousTitre: 'Suivi de la reproduction avicole, couvoir, incubation, éclosion, poussins et poulets de chair.',
        kpis: ['Effectif Total Vivant', "Taux d'Éclosion Couvoir", 'Poussins Nés (Éclosion)', 'Taux de Mortalité'],
        kpiLegendes: ['Reproducteurs, Poussins & Goliath', 'Ratio : Poussins Nés ÷ Œufs Couvés', 'Cumul naissances au couvoir', 'Seuil critique < 5%'],
        kpiIcones: ['grid_view', 'egg', 'child_care', 'trending_down'],
        aucuneBande: 'Aucune bande active (Reproducteurs/Goliath/Poussins) pour le moment.',
        saisieTitre: 'Saisie Journalière Couvoir & Suivi Chair',
        bandeLabel: 'Bande / Lot Concerné', bandeToujours: true,
        groupes: [['Date', 'rowspan'], ['Couvoir', 2], ['Morts (total)', 1], ['Effectif Final', 'rowspan'], ['Taux Mort %', 'rowspan'], ['Poids Général (g)', 'rowspan']],
        sousColonnes: ['Couvés', 'Nés', 'Reproducteur+Jeune+Poussin'],
        cartes: ['Couvés', 'Nés', 'Morts (total)', 'Effectif Final', 'Taux Mort %', 'Poids Général (g)'],
        // Cellules du tableau mensuel (dans l'ordre du Blade) : champ, alerte rouge si > 0, gras.
        cellules: [['ponte_total'], ['ne'], ['mort', 'alerte'], ['effectif_final', 'gras'], ['taux', 'tauxAlerte'], ['poids_general_g', 'num']],
        note: 'La ventilation Reproducteur / Jeune / Poussin des morts, des dons et des ventes est conservée par catégorie (ticket VOL-1) — le tableau mensuel en affiche le cumul.',
    },
    kpiValeurs: (k) => [nombre(k.effectif_total), k.taux_eclosion === null ? '—' : `${virgule(k.taux_eclosion)} %`, String(k.poussins_nes), `${virgule(k.taux_mortalite_mois)} %`],
    motifs: {
        aucuneBande: "Sélectionnez d'abord une bande.",
        ancienneFiche: "Cette fiche porte des morts ou des dons non ventilés par catégorie : ventilez-les (Reproducteur / Jeune / Poussin) avant d'enregistrer.",
    },
    libelles: {},
    prophylaxie: { titre: 'Traitements & Prophylaxie', observations: 'Observations', observationsExemple: 'ex : RAS' },
};

export const FAMILLES = { lapins: LAPINS_F, porcs: PORCS_F, escargots: ESCARGOTS_F, reproducteurs: REPRODUCTEURS_F };
export const FAMILLE_PAR_DEFAUT = LAPINS_F;
/** La famille d'une bande (par le code de son espèce), `null` si ni lapins ni porcs. */
export const familleDuLot = (lot) => Object.values(FAMILLES).find((f) => (f.accepte ? f.accepte(lot ?? {}) : f.espece === lot?.species_code)) ?? null;
