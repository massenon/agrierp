/**
 * PWA-3 (fiche lapins, É3) — LA SAISIE D'UN JOUR de la fiche lapins, hors ligne.
 *
 * Transposition de `Livewire\Elevage\FicheLapins` : `loadDay` (`chargerJour`), `calculerCategoriesJour`, `getEffectifFinalCalcProperty`,
 * `getAvertissementMortsProperty`, `getPoidsMoyenEstimeProperty` (`calculsSaisie`) et `saveDay` (`enregistrerJour` : contrôles AVANT toute
 * écriture, fiche écrite, cascade `recalculerEnCascade` des jours suivants). Les calculs d'effectif, la chaîne et la provende sont ceux,
 * DÉJÀ prouvés, de `effectif-categories.js`, `chaine-effectif.js` et `fiche-lapins-calculs.js`. Les phrases de refus et d'avertissement sont
 * celles du PHP (garde de sources : `tests/Js/fiche-lapins-saisie.test.mjs`) ; la parité avec le vrai `saveDay` est exécutée par
 * `tests/Js/parite-fiche-saisie.test.mjs`.
 *
 * La saisie est gardée dans le magasin chiffré local (`fiches_a_envoyer`, UUID du navigateur, `sync_status: 'pending'`) ; l'ENVOI au serveur
 * est l'étape É4 : la fiche reste « en attente d'envoi ». Écarts assumés avec le web : le champ « Observations » (jamais enregistré par
 * `saveDay`) et la prophylaxie du jour (É5) ne sont pas repris ; les effets de stock (`SyncLotProductionStockAction`) sont ceux du SERVEUR.
 */

import { computeEffectifFinal, effectifVeille, etatPourJour, jourDe, recalculerEnCascade, teteDeChaine } from './chaine-effectif.js';
import { LAPINS, calculerJour, departDepuisStade, verifierDepart } from './effectif-categories.js';
import { provendeDuJour, LIBELLES as LIBELLES_RATION } from './fiche-lapins-calculs.js';
import { arrondiPhp } from './calculs-caisse.js';
import { chiffrer, dechiffrer } from './coffre.js';
import { FAMILLE_PAR_DEFAUT, LAPINS_F, familleDuLot } from './fiche-familles.js';
import { rendreProphylaxie, LIBELLES as LIBELLES_PROPHY } from './fiche-lapins-prophylaxie.js';
import { META_AUTRES_EN_ATTENTE } from './base-locale.js';

/** Le NOMBRE d'éléments non envoyés, en clair (meta) : l'avertissement de déconnexion le lit sans le PIN. */
export async function noterAutres(base, genre, n) {
    const actuel = (await base.meta(META_AUTRES_EN_ATTENTE)) ?? {};
    await base.poserMeta(META_AUTRES_EN_ATTENTE, { ...actuel, [genre]: n });
}

export const TABLE_FICHES_A_ENVOYER = 'fiches_a_envoyer';
/** Rôles qui ont `manage-elevage` (seeder) : les autres lisent la fiche sans pouvoir l'écrire. */
export const ROLES_ECRITURE = ['admin', 'animalier'];

/** Phrases et libellés (garde : lus dans le PHP et le Blade). */
export const MOTIFS = {
    aucuneBande: LAPINS_F.motifs.aucuneBande,
    dateInvalide: 'Date invalide : choisissez un jour.',
    ancienneFiche: LAPINS_F.motifs.ancienneFiche,
    droit: "Votre profil ne permet pas d'enregistrer la fiche d'élevage : lecture seule.",
    exerciceClos: (annee, jourFr) => `L'exercice ${annee} est clôturé : aucune saisie ne peut être datée du ${jourFr}.`,
    mortsAuDessus: (morts, veille) => `Morts du jour (${morts}) supérieurs à l'effectif de la veille (${veille}) : l'effectif est ramené à 0, vérifiez la saisie.`,
    somme: (jourFr, somme, total) => `Avertissement (hors maquette) — fiche du ${jourFr} : la somme des catégories (${somme}) diffère de l'effectif total (${total}). Un effectif de catégorie ne descend jamais sous 0 : vérifiez les ventes, morts et dons saisis.`,
    ancienNonVentile: (m, d) => `Fiche ancienne non ventilée par catégorie : ${m} mort(s) et ${d} don(s) non ventilé(s) y sont enregistrés. Ventilez-les ci-dessus avant d'enregistrer.`,
    avantDepart: (jourFr) => `Jour antérieur à l'effectif de départ fixé le ${jourFr} : les effectifs par catégorie ne sont pas calculés (—).`,
    enregistre: 'Jour enregistré avec succès.',
    enAttente: "Enregistrée sur cet appareil — en attente d'envoi.",
};

/** Libellés de la saisie des lapins (chaînes seules : la garde de sources les lit toutes dans le Blade). */
export const LIBELLES = Object.fromEntries(Object.entries(LAPINS_F.libelles).filter(([, v]) => typeof v === 'string'));

/** `components/autonomie-alimentaire.blade.php` : les cinq états, mêmes phrases (garde : `fiche-lapins-saisie.test.mjs`). */
export const AUTONOMIE = {
    aucunTitre: 'Autonomie alimentaire : aucun stock de provende suivi',
    aucunTexte: (filiere) => `Aucun produit de provende ${filiere} n'existe en catalogue avec un stock suivi : créez-le et approvisionnez-vous. La fiche s'enregistre quand même.`,
    ruptureTitre: 'Autonomie alimentaire : rupture de stock',
    ruptureTexte: (nom, kg) => `Le stock de ${nom} est épuisé (${kg} Kg) : approvisionnez-vous. La fiche s'enregistre quand même.`,
    inconnu: (nom, kg) => `Autonomie alimentaire : — (${nom}, ${kg} Kg en stock) — la consommation du jour est inconnue tant que les effectifs par catégorie le sont.`,
    critiqueTitre: 'Alerte critique - Autonomie alimentaire',
    critiqueTexte: (nom, jours) => `Le stock de ${nom} ne couvre plus que ${jours} jours de consommation théorique du cheptel actif ! Approvisionnez-vous.`,
    normal: (jours, nom, kg) => `Autonomie alimentaire : ${jours} jours (${nom}, ${kg} Kg en stock).`,
    seuilIncertain: 'Seuil critique constaté sur les bons de commande : à confirmer en ligne.',
};

const FORMAT_JOUR = /^\d{4}-\d{2}-\d{2}$/;
export const dateValide = (d) => {
    if (typeof d !== 'string' || !FORMAT_JOUR.test(d)) return false;
    const [a, m, j] = d.split('-').map(Number);
    const x = new Date(Date.UTC(a, m - 1, j));
    return x.getUTCFullYear() === a && x.getUTCMonth() === m - 1 && x.getUTCDate() === j;
};
const n = (v) => Math.trunc(Number(v ?? 0)) || 0;
const jourFr = (j) => `${j.slice(8, 10)}/${j.slice(5, 7)}/${j.slice(0, 4)}`;
const jours = (a, b) => Math.round((Date.UTC(+b.slice(0, 4), +b.slice(5, 7) - 1, +b.slice(8, 10)) - Date.UTC(+a.slice(0, 4), +a.slice(5, 7) - 1, +a.slice(8, 10))) / 86400000);
const nonNul = (v) => v !== null && v !== undefined;
const COLONNES_TRANSFERT = ['transfert_entree', 'transfert_sortie', 'transfert_entree_repro', 'transfert_entree_sevre', 'transfert_entree_jeune', 'transfert_sortie_repro', 'transfert_sortie_sevre', 'transfert_sortie_jeune', 'transfert_entree_4', 'transfert_sortie_4'];

export const saisieVide = () => ({
    achat: 0, ne: 0, mortRepro: 0, mortChair: 0, mortLapereau: 0, donRepro: 0, donChair: 0, donLapereau: 0, passage: 0,
    effectifM: 0, effectifF: 0, effectifSevres: 0, effectifSmeres: 0, departRepro: null, departSevre: null, departJeune: null,
    peseeTotal: null, mortAncienTotal: null, donAncienTotal: null,
});

/** Le barème de LA famille (les barèmes tirés couvrent toutes les espèces ; sans `species_code`, tel quel). */
const rationsDe = (rations, F) => rations.filter((r) => r.species_code === undefined || r.species_code === F.espece);
const fichesDe = (lot, fiches) => fiches.filter((f) => f.lot_id === lot.id);

/** `loadDay` : la saisie telle que le web l'ouvre pour ce jour (fiche existante rechargée, sinon zéros ; départ proposé d'après le stade). */
export function chargerJour(lot, fiches, jour, F = FAMILLE_PAR_DEFAUT) {
    const s = saisieVide();
    if (lot === null || lot === undefined) return s;
    const duLot = fichesDe(lot, fiches);
    if (teteDeChaine(lot, duLot) === null) {
        const depart = departDepuisStade(lot, effectifVeille(lot, duLot, jour));
        if (depart !== null && depart !== undefined) { s.departRepro = depart.repro; s.departSevre = depart.sevre; s.departJeune = depart.jeune; }
    }
    const f = duLot.find((x) => jourDe(x) === jour);
    if (!f) return s;
    s.achat = n(f.achat); s.ne = n(f.ne);
    if (nonNul(f.mort_repro) && nonNul(f.mort_sevre) && nonNul(f.mort_jeune)) { s.mortRepro = n(f.mort_repro); s.mortLapereau = n(f.mort_sevre); s.mortChair = n(f.mort_jeune); }
    else s.mortAncienTotal = n(f.mort) > 0 ? n(f.mort) : null;
    if (nonNul(f.don_repro) && nonNul(f.don_sevre) && nonNul(f.don_jeune)) { s.donRepro = n(f.don_repro); s.donLapereau = n(f.don_sevre); s.donChair = n(f.don_jeune); }
    else s.donAncienTotal = n(f.don) > 0 ? n(f.don) : null;
    s.passage = n(f.passage_sevre_jeune);
    s.effectifM = n(f.effectif_m); s.effectifF = n(f.effectif_f); s.effectifSevres = n(f.effectif_sevres); s.effectifSmeres = n(f.effectif_smeres);
    const final = n(f.effectif_final);
    // Lapins : total pesé en grammes (arrondi) ; porcs : en Kg, deux décimales (`round(avg × effectif / 1000, 2)`).
    s.peseeTotal = f.weight_sample_avg_g && final > 0
        ? (F.kg ? arrondiPhp((Number(f.weight_sample_avg_g) * final) / 1000, 2) : Math.round(Number(f.weight_sample_avg_g) * final))
        : null;
    return s;
}

/** `getPoidsMoyenEstimeProperty` : poids moyen estimé (GMQ entre la première et la dernière pesée), `null` si aucune pesée ou pesée saisie. */
export function poidsMoyenEstime(lot, fiches, jour, s, F = FAMILLE_PAR_DEFAUT) {
    if (nonNul(s.peseeTotal) || !lot || !dateValide(jour)) return null;
    const pesees = fichesDe(lot, fiches).filter((f) => nonNul(f.weight_sample_avg_g) && jourDe(f) < jour).sort((a, b) => (jourDe(a) < jourDe(b) ? -1 : 1));
    if (pesees.length === 0) return null;
    const derniere = pesees.at(-1);
    const ecoules = jours(jourDe(derniere), jour);
    const poids = Number(derniere.weight_sample_avg_g);
    if (ecoules <= 0) return F.kg ? arrondiPhp(poids / 1000, 2) : arrondiPhp(poids, 0);
    let gmq = 0;
    if (pesees.length >= 2) {
        const jg = jours(jourDe(pesees[0]), jourDe(derniere));
        gmq = jg > 0 ? (poids - Number(pesees[0].weight_sample_avg_g)) / jg : 0;
    }
    return F.kg ? arrondiPhp((poids + gmq * ecoules) / 1000, 2) : arrondiPhp(poids + gmq * ecoules, 0);
}

/**
 * Tout ce que l'écran du web calcule à partir de la saisie : effectif de la veille, effectif final, taux, catégories (`categoriesJour`),
 * avertissement des morts, provende, poids estimé.
 */
export function calculsSaisie(lot, fiches, jour, s, rations = [], autonomie = null, F = FAMILLE_PAR_DEFAUT) {
    rations = rationsDe(rations, F);
    const cat = { mode: 'sans_chaine', repro: null, sevre: null, jeune: null, resultat: null, motif: null, refus_passage: null, avertissements: [], depart_requis: false, depart_date: null, depart: null };
    const sortie = { veille: 0, vente: 0, effectifFinal: 0, taux: 0, cat, avertissementMorts: null, provende: F.provende({}, rations), poidsEstime: null, autonomie: { available: false } };
    if (!lot) return sortie;
    const valide = dateValide(jour);
    const duLot = fichesDe(lot, fiches);
    const duJour = valide ? duLot.find((f) => jourDe(f) === jour) ?? null : null;
    sortie.veille = valide ? effectifVeille(lot, duLot, jour) : 0;
    sortie.vente = n(duJour?.vente);
    const transferts = Object.fromEntries(COLONNES_TRANSFERT.map((c) => [c, n(duJour?.[c])]));
    const mort = n(s.mortRepro) + n(s.mortChair) + n(s.mortLapereau);
    const don = n(s.donRepro) + n(s.donChair) + n(s.donLapereau);
    sortie.effectifFinal = computeEffectifFinal(sortie.veille, n(s.achat), n(s.ne), mort, sortie.vente, don, transferts.transfert_entree, transferts.transfert_sortie);
    sortie.taux = sortie.veille > 0 ? arrondiPhp((mort / sortie.veille) * 100, 1) : 0;
    if (mort > sortie.veille) sortie.avertissementMorts = MOTIFS.mortsAuDessus(mort, sortie.veille);
    sortie.poidsEstime = poidsMoyenEstime(lot, fiches, jour, s, F);

    if (valide) {
        const etat = etatPourJour(lot, duLot, jour);
        cat.mode = etat.mode; cat.depart_date = etat.depart_date; cat.depart = etat.depart; cat.motif = etat.refus;
        let veille = etat.veille;
        let continuer = true;
        if (etat.mode === 'sans_chaine') {
            cat.depart_requis = true;
            const saisi = { repro: s.departRepro, sevre: s.departSevre, jeune: s.departJeune };
            const inconnus = Object.values(saisi).some((v) => v === null || v === undefined);
            if (inconnus) {
                if (Object.values(saisi).some(nonNul)) cat.motif = verifierDepart(saisi, sortie.veille);
                continuer = false;
            } else {
                cat.motif = verifierDepart(saisi, sortie.veille);
                if (cat.motif !== null) continuer = false; else veille = saisi;
            }
        }
        if (continuer && veille !== null && veille !== undefined) {
            const r = calculerJour(F.calcul, veille, {
                achat: n(s.achat), ne: n(s.ne), vente: sortie.vente,
                mort_repro: n(s.mortRepro), mort_sevre: n(s.mortLapereau), mort_jeune: n(s.mortChair),
                don_repro: n(s.donRepro), don_sevre: n(s.donLapereau), don_jeune: n(s.donChair), passage: n(s.passage), ...transferts,
            }, sortie.effectifFinal);
            cat.resultat = r; cat.repro = r.repro; cat.sevre = r.sevre; cat.jeune = r.jeune; cat.refus_passage = r.refus;
            if (r.sommeDifferente === true) cat.avertissements.push(MOTIFS.somme(jourFr(jour), r.repro + r.sevre + r.jeune, sortie.effectifFinal));
        }
    }
    sortie.provende = F.provende({ repro: cat.repro, sevre: cat.sevre, jeune: cat.jeune }, rations);
    sortie.autonomie = autonomie ? autonomie(sortie.provende.total_kg) : { available: false };
    return sortie;
}

/** L'exercice qui couvre le jour (le premier par début) et son refus éventuel (`AccountingEntryService::refusExerciceClos`). */
export function refusExerciceClos(exercices, jour) {
    const e = [...exercices].sort((a, b) => (String(a.start_date) < String(b.start_date) ? -1 : 1)).find((x) => String(x.start_date).slice(0, 10) <= jour && String(x.end_date).slice(0, 10) >= jour);
    return e && e.status !== 'ouvert' ? MOTIFS.exerciceClos(Number(e.year), jourFr(jour)) : null;
}

/**
 * `saveDay` : contrôles AVANT toute écriture (un refus n'écrit RIEN), puis la fiche du jour (mise à jour ou création) et la cascade.
 *
 * @param {{exercices?:object[], rations?:object[], idFiche?:string, role?:?string}} ctx
 * @returns {{refus:string}|{refus:null, fiche:object, lot:object, fiches:object[]}}
 */
export function enregistrerJour(lot, fiches, jour, s, ctx = {}) {
    const F = ctx.famille ?? familleDuLot(lot) ?? FAMILLE_PAR_DEFAUT;
    if (ctx.role !== undefined && ctx.role !== null && !ROLES_ECRITURE.includes(ctx.role)) return { refus: MOTIFS.droit };
    if (!lot) return { refus: F.motifs.aucuneBande };
    if (!dateValide(jour)) return { refus: MOTIFS.dateInvalide };
    const clos = refusExerciceClos(ctx.exercices ?? [], jour);
    if (clos !== null) return { refus: clos };

    const c = calculsSaisie(lot, fiches, jour, s, ctx.rations ?? [], null, F);
    if (c.cat.refus_passage !== null && c.cat.refus_passage !== undefined) return { refus: c.cat.refus_passage };
    const saisiDepart = { repro: s.departRepro, sevre: s.departSevre, jeune: s.departJeune };
    let departAEcrire = false;
    if (c.cat.mode === 'sans_chaine' && Object.values(saisiDepart).some(nonNul)) {
        const refus = verifierDepart(saisiDepart, c.veille);
        if (refus !== null) return { refus };
        departAEcrire = true;
    }
    const mort = n(s.mortRepro) + n(s.mortChair) + n(s.mortLapereau);
    const don = n(s.donRepro) + n(s.donChair) + n(s.donLapereau);
    if ((nonNul(s.mortAncienTotal) && mort === 0) || (nonNul(s.donAncienTotal) && don === 0)) return { refus: F.motifs.ancienneFiche };

    const donnees = {
        achat: n(s.achat), ne: n(s.ne), mort, vente: c.vente, don, effectif_final: c.effectifFinal,
        effectif_m: n(s.effectifM), effectif_f: n(s.effectifF), effectif_sevres: n(s.effectifSevres), effectif_smeres: n(s.effectifSmeres),
        feed_qty_kg: c.provende.total_kg,
        mort_repro: n(s.mortRepro), mort_sevre: n(s.mortLapereau), mort_jeune: n(s.mortChair),
        don_repro: n(s.donRepro), don_sevre: n(s.donLapereau), don_jeune: n(s.donChair),
        passage_sevre_jeune: n(s.passage),
        weight_sample_avg_g: s.peseeTotal && c.effectifFinal > 0 ? arrondiPhp((F.kg ? Number(s.peseeTotal) * 1000 : n(s.peseeTotal)) / c.effectifFinal, 0) : null,
    };
    if (departAEcrire) Object.assign(donnees, { cat_depart_repro: s.departRepro, cat_depart_sevre: s.departSevre, cat_depart_jeune: s.departJeune });

    const existante = fiches.find((f) => f.lot_id === lot.id && jourDe(f) === jour);
    const fiche = { ...(existante ?? { id: ctx.idFiche ?? globalThis.crypto.randomUUID(), lot_id: lot.id, entry_date: jour }), ...donnees, sync_status: 'pending' };
    const avec = existante ? fiches.map((f) => (f === existante ? fiche : f)) : [...fiches, fiche];
    const cascade = recalculerEnCascade(lot, fichesDe(lot, avec), jour);
    const autres = avec.filter((f) => f.lot_id !== lot.id);
    return { refus: null, fiche, lot: cascade.lot, fiches: [...autres, ...cascade.fiches] };
}

// ------------------------------------------------------------------------------------------ magasin local des saisies

export async function saisiesEnAttente({ base, cle }) {
    const ligne = await base.lire('referentiels', TABLE_FICHES_A_ENVOYER);
    return ligne ? dechiffrer(cle, ligne) : [];
}

/** Garde la saisie (une par bande et jour, la dernière gagne) ; ne rend qu'une fois l'écriture DURABLE. */
export async function garderSaisie({ base, cle }, item, maintenant = () => new Date()) {
    const liste = await saisiesEnAttente({ base, cle });
    const suivante = [...liste.filter((x) => !(x.lot_id === item.lot_id && x.jour === item.jour)), { ...item, sync_status: 'pending' }];
    await base.ecrire('referentiels', { table: TABLE_FICHES_A_ENVOYER, tire_le: maintenant().toISOString(), ...(await chiffrer(cle, suivante)) });
    await noterAutres(base, 'fiches', suivante.filter((x) => x.sync_status !== 'synced').length);
    return suivante;
}

/**
 * Rejoue les saisies en attente (dans l'ordre) au-dessus de la copie tirée : jamais écrites dans la copie, une saisie qui serait refusée
 * à nouveau (exercice clos entre-temps…) est sautée et rendue dans `sautees`.
 */
export function appliquerSaisies(tire, saisies, ctx = {}) {
    let courant = { lots: tire.lots, fiches: tire.fiches };
    const sautees = [];
    for (const it of saisies.filter((x) => x.sync_status !== 'conflict')) {
        const lot = courant.lots.find((l) => l.id === it.lot_id);
        const r = lot ? enregistrerJour(lot, courant.fiches, it.jour, it.saisie, { ...ctx, role: null, idFiche: it.id_fiche }) : { refus: LAPINS_F.motifs.aucuneBande };
        if (r.refus !== null) { sautees.push({ ...it, refus: r.refus }); continue; }
        courant = { lots: courant.lots.map((l) => (l.id === r.lot.id ? r.lot : l)), fiches: r.fiches };
    }
    return { ...courant, sautees };
}

// ------------------------------------------------------------------------------------------------------ file d'envoi (É4)

const ecrireSaisies = async ({ base, cle }, liste, maintenant = () => new Date()) => {
    if (liste.length === 0) await base.supprimer('referentiels', TABLE_FICHES_A_ENVOYER);
    else await base.ecrire('referentiels', { table: TABLE_FICHES_A_ENVOYER, tire_le: maintenant().toISOString(), ...(await chiffrer(cle, liste)) });
    await noterAutres(base, 'fiches', liste.filter((x) => x.sync_status !== 'synced').length);
};

/** Les saisies à envoyer : `pending` seulement (une saisie refusée reste `conflict` jusqu'à la reprise manuelle, jamais renvoyée en boucle). */
export const aEnvoyerFiches = (liste) => liste.filter((x) => x.sync_status === 'pending');

/**
 * La fiche telle que le poste Flutter l'envoie (`_ficheEnJson`) : mêmes colonnes, les mouvements par catégorie seulement quand ils sont
 * connus, le départ seulement s'il est écrit, JAMAIS `effectif_final` ni `cat_eff_*` (le serveur les recalcule). `vente` part à 0 : les
 * ventes arrivent par leur propre envoi, juste après, et chacune incrémente la fiche une seule fois (règle S-T9 du serveur).
 */
export function ficheEnJson(item, deviceId) {
    const f = item.fiche;
    const somme = (a, b, c) => (nonNul(a) && nonNul(b) && nonNul(c) ? n(a) + n(b) + n(c) : null);
    const connus = {};
    for (const c of ['mort_repro', 'mort_sevre', 'mort_jeune', 'don_repro', 'don_sevre', 'don_jeune', 'passage_sevre_jeune', 'cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune', 'effectif_m', 'effectif_f', 'effectif_sevres', 'effectif_smeres']) {
        if (nonNul(f[c])) connus[c] = n(f[c]);
    }
    const depart = nonNul(f.cat_depart_repro) && nonNul(f.cat_depart_sevre) && nonNul(f.cat_depart_jeune);
    if (!depart) for (const c of ['cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune']) delete connus[c];
    return {
        id: f.id, lot_id: f.lot_id, entry_date: jourDe(f), achat: n(f.achat), ne: n(f.ne),
        mort: somme(f.mort_repro, f.mort_sevre, f.mort_jeune) ?? n(f.mort), vente: 0,
        don: somme(f.don_repro, f.don_sevre, f.don_jeune) ?? n(f.don),
        feed_qty_kg: nonNul(f.feed_qty_kg) ? Number(f.feed_qty_kg) : null, weight_sample_avg_g: nonNul(f.weight_sample_avg_g) ? Number(f.weight_sample_avg_g) : null,
        ...connus, device_id: deviceId, updated_at: item.cree_le,
    };
}

const modifier = async (ctx, f, maintenant) => { await ecrireSaisies(ctx, f(await saisiesEnAttente(ctx)), maintenant); };

/** Accusé du serveur : `synced` (reste rejouée sur la copie tirée jusqu'à un tirage ultérieur qui la contient). `fusion` : id de la fiche du serveur. */
export const marquerFichesSynced = (ctx, ids, maintenant = () => new Date()) => modifier(ctx, (l) => l.map((x) => (ids.includes(x.id_fiche) ? { ...x, sync_status: 'synced', synced_le: maintenant().toISOString(), motif: null } : x)), maintenant);
export const marquerFicheConflit = (ctx, id, motif, maintenant = () => new Date()) => modifier(ctx, (l) => l.map((x) => (x.id_fiche === id ? { ...x, sync_status: 'conflict', motif } : x)), maintenant);
export const remettreFicheEnFile = (ctx, id, maintenant = () => new Date()) => modifier(ctx, (l) => l.map((x) => (x.id_fiche === id && x.sync_status === 'conflict' ? { ...x, sync_status: 'pending', motif: null } : x)), maintenant);
export const abandonnerFiche = (ctx, id, maintenant = () => new Date()) => modifier(ctx, (l) => l.filter((x) => x.id_fiche !== id), maintenant);
/** Retire les saisies acquittées avant `avant` (instant) : un tirage commencé APRÈS les contient, la copie tirée les porte alors seule. */
export const retirerFichesSynced = (ctx, avant, maintenant = () => new Date()) => modifier(ctx, (l) => l.filter((x) => !(x.sync_status === 'synced' && Date.parse(x.synced_le ?? 0) < avant)), maintenant);

/** L'alerte d'autonomie alimentaire (classes de la PWA : rouge = `refus`, neutre, vert = `info`). Jamais bloquante. */
export function rendreAutonomie(h, a, filiere = 'cuniculture') {
    const bloc = (classe, ...enfants) => h('div', { class: `bandeau ${classe}`, id: 'saisie-autonomie-bloc', style: 'margin:0' }, ...enfants);
    if (!a.available) return bloc('refus', h('b', {}, AUTONOMIE.aucunTitre), h('p', { style: 'margin:2px 0 0' }, AUTONOMIE.aucunTexte(filiere)));
    const note = a.seuilIncertain ? h('p', { class: 'muted', style: 'margin:2px 0 0' }, AUTONOMIE.seuilIncertain) : null;
    if (a.rupture) return bloc('refus', h('b', {}, AUTONOMIE.ruptureTitre), h('p', { style: 'margin:2px 0 0' }, AUTONOMIE.ruptureTexte(a.product.name, a.stock_kg)));
    if (a.inconnu) return bloc('neutre', AUTONOMIE.inconnu(a.product.name, a.stock_kg));
    if (a.critique) return bloc('refus', h('b', {}, AUTONOMIE.critiqueTitre), h('p', { style: 'margin:2px 0 0' }, AUTONOMIE.critiqueTexte(a.product.name, a.autonomie_jours)), note);
    return bloc('info', AUTONOMIE.normal(a.autonomie_jours, a.product.name, a.stock_kg), note);
}

// ------------------------------------------------------------------------------------------------------------ formulaire

/**
 * Le formulaire (DOM, jamais `innerHTML`). `lire()` rend `{lot, fiches, jour, rations, lectureSeule, enAttente}` à jour ; `actions.enregistrer(s)`
 * rend `{refus}` ou `{ok}` ; `s` est l'objet de saisie (modifié en place).
 */
export function rendreFormulaire(h, { s, lire, actions, retourInitial = null, famille = FAMILLE_PAR_DEFAUT }) {
    const F = famille;
    const L = F.libelles;
    const champs = new Map();
    const entier = (cle, libelle, classe = '') => {
        const input = h('input', { type: 'number', min: '0', ...(cle === 'peseeTotal' && F.kg ? { step: '0.1' } : {}), id: `saisie-${cle}`, class: `fiche-select ${classe}`, value: String(s[cle] ?? '') });
        input.addEventListener('input', () => { s[cle] = input.value === '' ? (cle.startsWith('depart') || cle === 'peseeTotal' ? null : 0) : Math.max(0, cle === 'peseeTotal' && F.kg ? (Number(input.value) || 0) : (Math.trunc(Number(input.value)) || 0)); rafraichir(); });
        champs.set(cle, input);
        return h('label', { class: 'saisie-champ' }, h('span', { class: 'muted' }, libelle), input);
    };
    const groupe = (titre, cles, etiquettes) => h('div', { class: 'saisie-groupe' }, h('b', {}, titre), h('div', { class: 'saisie-trois' }, ...['Repro', 'Chair', 'Lapereau'].map((suffixe, i) => entier(`${cles}${suffixe}`, etiquettes[i]))));
    const alertes = h('div', { id: 'saisie-alertes', class: 'saisie-alertes', role: 'status' });
    const departZone = h('div', { id: 'saisie-depart' });
    const finale = h('b', { id: 'saisie-effectif-final' });
    const taux = h('b', { id: 'saisie-taux' });
    const poidsMoyen = h('b', { id: 'saisie-poids-moyen' });
    const echantillon = h('b', { id: 'saisie-echantillon' });
    const gmq = h('p', { id: 'saisie-gmq', class: 'muted' });
    const venteChamp = h('b', { id: 'saisie-vente' });
    const etatEnvoi = h('p', { id: 'saisie-etat', class: 'muted', role: 'status' });
    const provende = h('div', { id: 'saisie-provende' });
    const prophyZone = h('div', { id: 'saisie-prophy-zone' });
    const autonomieZone = h('div', { id: 'saisie-autonomie' });

    function rafraichir() {
        const ctx = lire();
        const c = calculsSaisie(ctx.lot, ctx.fiches, ctx.jour, s, ctx.rations, ctx.autonomie, F);
        const g = (v) => (v === null || v === undefined ? '—' : `${v} g`);
        const ligne = (libelle, cle, id) => h('tr', {}, h('td', {}, libelle), h('td', { class: 'num' }, h('input', { id: `cat-eff-${id}`, type: 'text', disabled: true, value: String(c.provende[cle].effectif ?? '—'), style: 'width:56px;text-align:center' })), h('td', { class: 'num' }, F.rationAffichee(cle, c.provende[cle].ration)), h('td', { class: 'num', id: `cat-prov-${id}-g` }, g(c.provende[cle].total_g)));
        provende.replaceChildren(h('b', {}, L.provende), h('table', { class: 'rtable' },
            h('thead', {}, h('tr', {}, ...[L.categorie, L.effectif, L.ration, L.servie].map((t) => h('th', {}, t)))),
            h('tbody', {}, ...L.lignesProvende.map(([cle, id, libelle]) => ligne(libelle, cle, id))),
            h('tfoot', {}, h('tr', {}, h('td', { colspan: 3 }, L.totalProvende), h('td', { class: 'num', id: 'day-total-provende-g' }, c.provende.total_g === null ? '—' : `${c.provende.total_g} g (${c.provende.total_kg} Kg)`)))));
        autonomieZone.replaceChildren(rendreAutonomie(h, c.autonomie, F.filiere));
        const notes = [];
        const bloc = (texte, classe) => h('div', { class: `bandeau ${classe}`, style: 'margin:6px 0 0', role: classe === 'avert' ? 'status' : 'alert' }, texte);
        if (c.cat.motif) notes.push(bloc(c.cat.motif, 'refus'));
        if (c.cat.refus_passage) notes.push(bloc(c.cat.refus_passage, 'refus'));
        if (c.avertissementMorts) notes.push(bloc(c.avertissementMorts, 'avert'));
        for (const a of c.cat.avertissements) notes.push(bloc(a, 'avert'));
        if (nonNul(s.mortAncienTotal) || nonNul(s.donAncienTotal)) notes.push(bloc(MOTIFS.ancienNonVentile(s.mortAncienTotal ?? 0, s.donAncienTotal ?? 0), 'avert'));
        alertes.replaceChildren(...notes);
        finale.textContent = String(c.effectifFinal);
        taux.textContent = `${c.taux.toFixed(1).replace('.', ',')} %`;
        echantillon.textContent = String(c.effectifFinal);
        poidsMoyen.textContent = s.peseeTotal && c.effectifFinal > 0 ? (F.kg ? `${arrondiPhp(s.peseeTotal / c.effectifFinal, 1).toFixed(1)} Kg` : `${arrondiPhp(s.peseeTotal / c.effectifFinal, 0)} g`) : '—';
        venteChamp.textContent = String(c.vente);
        gmq.replaceChildren(...(c.poidsEstime !== null ? [`${L.gmq} `, h('b', {}, F.kg ? `${arrondiPhp(c.poidsEstime, 2).toFixed(2)} Kg / animal` : `${c.poidsEstime} g / animal`)] : []));
        const placeholder = c.poidsEstime !== null && c.effectifFinal > 0 ? (F.kg ? `~${arrondiPhp(c.poidsEstime * c.effectifFinal, 1).toFixed(1)} Kg (estimé)` : `~${c.poidsEstime * c.effectifFinal} g (estimé)`) : L.peseeExemple;
        champs.get('peseeTotal')?.setAttribute('placeholder', placeholder);
        etatEnvoi.textContent = ctx.enAttente ? MOTIFS.enAttente : '';
        return c;
    }

    const ctx0 = lire();
    const c0 = calculsSaisie(ctx0.lot, ctx0.fiches, ctx0.jour, s, ctx0.rations, ctx0.autonomie, F);
    if (c0.cat.depart_requis) {
        departZone.append(h('div', { class: 'saisie-groupe' }, h('b', {}, L.departSaisissable),
            h('p', { class: 'muted' }, `Effectif au DÉBUT du jour, avant les mouvements du jour, pré-rempli automatiquement depuis le stade de la bande. La somme des trois catégories doit égaler l'effectif total au début du jour (${c0.veille}). Corrigez-le seulement pour une bande mixte ; il est verrouillé au premier enregistrement.`),
            h('div', { class: 'saisie-trois' }, ...L.ordreDepart.map(([prop, , libelle]) => entier(prop, libelle)))));
    } else if (c0.cat.depart) {
        departZone.append(h('div', { class: 'saisie-groupe' }, h('b', {}, L.departVerrouille),
            h('p', { class: 'muted' }, `Effectif de départ fixé le ${jourFr(c0.cat.depart_date)} (au début de ce jour).`),
            h('div', { class: 'saisie-trois' }, ...L.ordreDepart.map(([, k, l]) => h('label', { class: 'saisie-champ' }, h('span', { class: 'muted' }, l), h('input', { type: 'number', value: String(c0.cat.depart[k]), disabled: true, class: 'fiche-select' })))),
            c0.cat.mode === 'avant_depart' ? h('p', { class: 'alerte' }, MOTIFS.avantDepart(jourFr(c0.cat.depart_date))) : null));
    }

    const conflit = ctx0.conflit
        ? h('div', { class: 'bandeau refus', id: 'saisie-conflit', role: 'alert', style: 'margin:0' }, `Fiche refusée par le serveur : ${ctx0.conflit} `,
            h('button', { type: 'button', class: 'btn', id: 'saisie-renvoyer', onclick: () => actions.renvoyer() }, 'Renvoyer'),
            h('button', { type: 'button', class: 'btn danger', id: 'saisie-abandonner', onclick: () => actions.abandonner() }, 'Abandonner cette saisie'))
        : null;
    const coches = new Set();
    const observations = h('input', { type: 'text', id: 'saisie-observations', class: 'fiche-select', style: 'width:100%', placeholder: F.prophylaxie.observationsExemple, disabled: Boolean(ctx0.lectureSeule) });
    const conflitsSoins = (ctx0.conflitsSoins ?? []).map((x) => h('div', { class: 'bandeau refus', role: 'alert', style: 'margin:6px 0 0', 'data-conflit-soin': x.id }, `Soin « ${x.soin.action_type} » refusé par le serveur : ${x.motif} `,
        h('button', { type: 'button', class: 'btn', onclick: () => actions.renvoyerSoin(x.id) }, 'Renvoyer'), h('button', { type: 'button', class: 'btn danger', onclick: () => actions.abandonnerSoin(x.id) }, 'Abandonner ce soin')));
    const message = (r) => { retour.textContent = r.refus ?? r.avertissement ?? r.message ?? ''; retour.className = r.refus ? 'alerte' : 'muted'; };
    prophyZone.append(rendreProphylaxie(h, { titre: F.prophylaxie.titre, protocole: ctx0.protocole, coches, lectureSeule: ctx0.lectureSeule, actions: { valider: async () => message(await actions.validerTraitements([...coches], observations.value)) } }), ...conflitsSoins,
        h('label', { class: 'saisie-champ' }, h('span', { class: 'muted' }, F.prophylaxie.observations), observations));
    const bouton = h('button', { type: 'button', class: 'btn plein', id: 'saisie-enregistrer', disabled: Boolean(ctx0.lectureSeule) }, h('span', { class: 'material-symbols-outlined' }, 'save'), L.enregistrer);
    const retour = h('p', { id: 'saisie-retour', role: 'alert', class: 'muted' }, retourInitial);
    bouton.addEventListener('click', async () => {
        const r = await actions.enregistrer(s);
        retour.textContent = r.refus ?? MOTIFS.enregistre;
        retour.className = r.refus ? 'alerte' : 'muted';
        rafraichir();
    });

    const racine = h('div', { id: 'fiche-saisie', class: 'saisie-form' },
        ctx0.lectureSeule ? h('div', { class: 'bandeau neutre', id: 'saisie-lecture-seule', style: 'margin:0 0 8px' }, ctx0.lectureSeule) : null,
        conflit,
        h('div', { class: 'saisie-trois' }, entier('achat', L.achat), entier('ne', L.ne),
            h('div', { class: 'saisie-champ' }, h('span', { class: 'muted' }, `${L.vente} ${L.venteSuite}`), venteChamp)),
        groupe(L.morts, 'mort', L.mortsCat), groupe(L.dons, 'don', L.donsCat),
        h('div', { class: 'saisie-trois' }, entier('passage', L.passageSuite ? `${L.passage} ${L.passageSuite}` : L.passage)),
        departZone, alertes,
        h('div', { class: 'saisie-quatre' }, entier('effectifM', L.effectifM), entier('effectifF', L.effectifF), entier('effectifSevres', L.effectifSevres), entier('effectifSmeres', L.effectifSmeres)),
        h('div', { class: 'saisie-trois' },
            h('div', { class: 'saisie-champ' }, h('span', { class: 'muted' }, L.effectifFinal), finale),
            h('div', { class: 'saisie-champ' }, h('span', { class: 'muted' }, L.taux), taux)),
        provende, autonomieZone,
        h('div', { class: 'saisie-trois' }, entier('peseeTotal', L.pesee),
            h('div', { class: 'saisie-champ' }, h('span', { class: 'muted' }, `${L.echantillon} ${L.echantillonAuto}`), echantillon),
            h('div', { class: 'saisie-champ' }, h('span', { class: 'muted' }, L.poidsMoyen), poidsMoyen)),
        gmq, prophyZone, retour, etatEnvoi, h('div', { class: 'groupe', style: 'justify-content:flex-end' }, bouton));
    if (ctx0.lectureSeule) for (const el of racine.querySelectorAll('input')) el.disabled = true;
    rafraichir();
    return racine;
}
