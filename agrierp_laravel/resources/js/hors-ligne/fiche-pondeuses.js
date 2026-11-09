/**
 * PWA-3 (fiche volailles PONDEUSES, VOL-2) — LA SAISIE D'UN JOUR, hors ligne.
 *
 * Transposition de `Livewire\Elevage\FichePondeuses` : `loadDay` (`chargerJourPondeuses`), les propriétés calculées (`calculsPondeuses` : effectif de la veille, effectif
 * final, taux de mortalité et de ponte, œufs commercialisables et plateaux, stades `categoriesJour`, ventes du jour par stade, rationnement `StadePondeuse::tableau`,
 * autonomie) et `saveDay` (`enregistrerJourPondeuses`). Différences avec les reproducteurs, lues dans le PHP et le Blade : QUATRE stades (Poussin ponte / Poussin en
 * croissance / Poulette / Pondeuse = emplacements `quatre` / `sevre` / `jeune` / `repro`), TROIS passages (`passage_4_sevre`, `passage_sevre_jeune`, `passage_jeune_repro`),
 * départ obligatoire à quatre stades, œufs récoltés / cassés (`ponte_total` / `ponte_casses`) au lieu du couvoir.
 *
 * STOCK D'ŒUFS : l'incrémentation du stock (`RecordEggProductionStockAction`) et le grand livre (SRH / TS / OS / stock final, `EggStockLedgerService`) sont CÔTÉ SERVEUR, à
 * l'envoi ; le navigateur n'en calcule rien (les mouvements de stock ne sont pas tirés). Il montre les plateaux nets du jour (calcul pur) et le produit « Œufs » tel que le
 * dernier tirage des produits le donne (même choix que le serveur : premier par nom dont le nom contient « oeufs »).
 */

import { computeEffectifFinal, effectifVeille, etatPourJour, jourDe, recalculerEnCascade } from './chaine-effectif.js';
import { calculerJour, departDepuisStade, verifierDepart, VOLAILLES_PONTE } from './effectif-categories.js';
import { tableauPondeuses, LIBELLES_STADES_PONDEUSE, OEUFS_PAR_PLATEAU } from './fiche-lapins-calculs.js';
import { arrondiPhp } from './calculs-caisse.js';
import { rendreProphylaxie } from './fiche-lapins-prophylaxie.js';

const n = (v) => Math.trunc(Number(v ?? 0)) || 0;
const nonNul = (v) => v !== null && v !== undefined;
const FORMAT_JOUR = /^\d{4}-\d{2}-\d{2}$/;
const dateValide = (d) => {
    if (typeof d !== 'string' || !FORMAT_JOUR.test(d)) return false;
    const [a, m, j] = d.split('-').map(Number);
    const x = new Date(Date.UTC(a, m - 1, j));
    return x.getUTCFullYear() === a && x.getUTCMonth() === m - 1 && x.getUTCDate() === j;
};
const jourFr = (j) => `${j.slice(8, 10)}/${j.slice(5, 7)}/${j.slice(0, 4)}`;
const COLONNES_TRANSFERT = ['transfert_entree', 'transfert_sortie', 'transfert_entree_repro', 'transfert_entree_sevre', 'transfert_entree_jeune', 'transfert_sortie_repro', 'transfert_sortie_sevre', 'transfert_sortie_jeune', 'transfert_entree_4', 'transfert_sortie_4'];

/** Les quatre stades dans l'ordre du Blade : clé du barème, emplacement, suffixe des champs de saisie. */
export const STADES_SAISIE = [
    { cle: 'poussin_ponte', emp: 'quatre', suffixe: 'Quatre' },
    { cle: 'poussin_croissance', emp: 'sevre', suffixe: 'Sevre' },
    { cle: 'poulette', emp: 'jeune', suffixe: 'Jeune' },
    { cle: 'pondeuse', emp: 'repro', suffixe: 'Repro' },
];
const LISTE_STADES = '(Poussin ponte / Poussin en croissance / Poulette / Pondeuse)';

export const MOTIFS_PONDEUSES = {
    bande: "Aucune bande active au stade Ponte. Créez d'abord une bande.",
    dateInvalide: 'Date invalide : choisissez un jour.',
    avantDepart: (jourFrancais) => `Jour antérieur à l'effectif de départ fixé le ${jourFrancais} : il n'est pas saisissable.`,
    departManquant: "Saisissez d'abord l'effectif de départ de la bande par stade (Poussin ponte, Poussin en croissance, Poulette, Pondeuse) : la journée ne peut pas être enregistrée sans lui.",
    ancienneFiche: `Cette fiche porte des morts ou des dons non ventilés par stade : ventilez-les ${LISTE_STADES} avant d'enregistrer.`,
    ventesNonVentilees: "Cette journée porte des ventes d'avant la mise en place des stades, non ventilées : elle ne peut pas être ré-enregistrée. Saisissez le départ de la bande un autre jour.",
    ventesNonVentileesAvertissement: "Cette journée porte des ventes d'avant la mise en place des stades, non ventilées : elle ne peut pas être ré-enregistrée.",
    sommeDifferente: (jourFrancais, somme, total) => `Avertissement — fiche du ${jourFrancais} : la somme des stades (${somme}) diffère de l'effectif total (${total}). Un effectif de stade ne descend jamais sous 0 : vérifiez les ventes, morts et dons saisis.`,
    mortEnregistre: (m) => `${m} mort(s) déjà enregistré(s) ce jour, sans répartition par catégorie : ventilez-les ci-dessous ${LISTE_STADES} avant d'enregistrer.`,
    donEnregistre: (d) => `${d} don(s) déjà enregistré(s) ce jour, sans répartition par catégorie : ventilez-les ci-dessous ${LISTE_STADES} avant d'enregistrer.`,
    mortsAuDessus: (morts, veille) => `Morts du jour (${morts}) supérieurs à l'effectif de la veille (${veille}) : l'effectif est ramené à 0, vérifiez la saisie.`,
    aucuneProposition: 'Aucune proposition pour le stade de cette bande : saisissez le départ de chaque stade.',
    departRequis: (veille) => `Cette bande n'a pas encore d'effectif de départ : saisissez l'effectif de chaque stade au DÉBUT de ce jour, avant les mouvements du jour. La somme des quatre stades doit égaler l'effectif total au début du jour (${veille}). Il est verrouillé au premier enregistrement ; la journée ne s'enregistre pas sans lui.`,
    departFixe: (jourFrancais) => `Effectif de départ fixé le ${jourFrancais} (au début de ce jour).`,
    proposition: (p) => `Reprendre la proposition d'après le stade de la bande (${LIBELLES_STADES_PONDEUSE.pondeuse} ${p.repro} · ${LIBELLES_STADES_PONDEUSE.poulette} ${p.jeune} · ${LIBELLES_STADES_PONDEUSE.poussin_croissance} ${p.sevre} · ${LIBELLES_STADES_PONDEUSE.poussin_ponte} ${p.quatre})`,
    rationDepart: "Saisissez l'effectif de départ de la bande pour calculer les effectifs par stade et la provende servie.",
    aucunProduitOeufs: 'Aucun produit "Œufs de table" trouvé au catalogue — le stock ne sera pas incrémenté.',
};

export const LIBELLES_PONDEUSES_FICHE = {
    achat: 'Achats / Entrées du jour', ne: 'Nés / Transferts du jour', vente: 'Ventes', venteSuite: '(POS, réel)',
    ventesStade: (v) => STADES_SAISIE.map((s) => `${LIBELLES_STADES_PONDEUSE[s.cle]} ${v[s.emp]}`).join(' · '),
    oeufs: "Workflow Récolte & Stock d'Œufs", recoltes: 'Total Œufs Récoltés (OR)', casses: 'Œufs Cassés / Fêlés (OF)', commercialisables: 'Commercialisables (OR-OF)', tauxPonte: 'Taux de Ponte Calculé (%)',
    plateaux: (p) => `Plateaux Nets Générés (30 œufs/plateau) : ${p.plateaux} Plateaux (${p.vrac} œufs vrac)`,
    incrementation: (p, nom) => `Incrémentation Automatique du Stock : +${p.plateaux} Plateaux (${nom})`,
    morts: 'Morts par catégorie', dons: 'Dons par catégorie',
    passages: ['Passage du jour (Poussin ponte → Poussin en croissance)', 'Passage du jour (Poussin en croissance → Poulette)', 'Passage du jour (Poulette → Pondeuse)'],
    departTitre: 'Effectif de départ par stade (obligatoire)', departVerrouille: 'Effectif de départ par stade (verrouillé)',
    effectifFinal: 'Effectif Final du Jour', taux: 'Taux de Mortalité du Jour (%)',
    provende: 'Rationnement & Provende Servie par Stade (en Grammes g/j)', categorie: "Stade / Tranche d'Âge", effectif: 'Effectif', ration: 'Ration Normative', servie: 'Provende Servie (g)',
    totalProvende: 'TOTAL PROVENDE SERVIE DU JOUR (CUMUL EN GRAMMES)',
    pesee: 'Poids Général Pesé (g)', peseeExemple: 'ex : 1800', taille: 'Taille Échantillon', poidsMoyen: 'Poids Moyen Constaté', poidsMoyenSuite: '(Poids Général ÷ Effectif Final)',
    stockTitre: 'Stock Œufs & Plateaux (30) — Jour Sélectionné', stockCases: ['Stock Hier (SRH)', 'Total Stock (TS)', 'Sortie Vente (OS)', 'Stock Final'],
    stockHorsLigne: "Stock d'œufs jour par jour (SRH / TS / OS / stock final) : calculé par le serveur, disponible en ligne seulement.",
    enregistrer: 'Enregistrer ce Jour',
};

export const saisieVidePondeuses = () => ({
    achat: 0, ne: 0, oeufsRecoltes: 0, oeufsCasses: 0,
    mortRepro: 0, mortJeune: 0, mortSevre: 0, mortQuatre: 0, donRepro: 0, donJeune: 0, donSevre: 0, donQuatre: 0, passage1: 0, passage2: 0, passage3: 0,
    departRepro: null, departSevre: null, departJeune: null, departQuatre: null, mortEnregistre: null, donEnregistre: null, peseeTotal: null,
});

/** `loadDay` : la fiche de LA bande à ce jour ; le départ n'est JAMAIS prérempli (il est proposé par un bouton). */
export function chargerJourPondeuses(lot, fiches, jour) {
    const s = saisieVidePondeuses();
    const f = lot ? fiches.find((x) => x.lot_id === lot.id && jourDe(x) === jour) : null;
    if (!f) return s;
    s.achat = n(f.achat); s.ne = n(f.ne);
    if (![f.mort_repro, f.mort_sevre, f.mort_jeune, f.mort_4].some((v) => !nonNul(v))) { s.mortRepro = n(f.mort_repro); s.mortSevre = n(f.mort_sevre); s.mortJeune = n(f.mort_jeune); s.mortQuatre = n(f.mort_4); }
    else s.mortEnregistre = n(f.mort) > 0 ? n(f.mort) : null;
    if (![f.don_repro, f.don_sevre, f.don_jeune, f.don_4].some((v) => !nonNul(v))) { s.donRepro = n(f.don_repro); s.donSevre = n(f.don_sevre); s.donJeune = n(f.don_jeune); s.donQuatre = n(f.don_4); }
    else s.donEnregistre = n(f.don) > 0 ? n(f.don) : null;
    s.passage1 = n(f.passage_4_sevre); s.passage2 = n(f.passage_sevre_jeune); s.passage3 = n(f.passage_jeune_repro);
    s.oeufsRecoltes = n(f.ponte_total); s.oeufsCasses = n(f.ponte_casses);
    const final = n(f.effectif_final);
    s.peseeTotal = f.weight_sample_avg_g && final > 0 ? Math.round(Number(f.weight_sample_avg_g) * final) : null;
    return s;
}

export const mortDuJourPondeuses = (s) => { const x = n(s.mortRepro) + n(s.mortJeune) + n(s.mortSevre) + n(s.mortQuatre); return x > 0 ? x : n(s.mortEnregistre); };
export const donDuJourPondeuses = (s) => { const x = n(s.donRepro) + n(s.donJeune) + n(s.donSevre) + n(s.donQuatre); return x > 0 ? x : n(s.donEnregistre); };

/** `getVentesDuJourProperty` : les ventes du jour par stade (posées par la caisse) ; `non_ventilee` : des ventes d'avant la mise en place des stades. */
export function ventesDuJourPondeuses(lot, fiches, jour) {
    const f = lot && dateValide(jour) ? fiches.find((x) => x.lot_id === lot.id && jourDe(x) === jour) ?? null : null;
    return { repro: n(f?.vente_repro), sevre: n(f?.vente_sevre), jeune: n(f?.vente_jeune), quatre: n(f?.vente_4), non_ventilee: f !== null && n(f.vente) > 0 && !nonNul(f.vente_repro) };
}

/** `EggStockLedgerService::eggProduct` : le premier produit (par nom) dont le nom, « œ » ramené à « oe » et en minuscules, contient « oeufs » ; `null` sinon. */
export function produitOeufs(produits) {
    const nom = (p) => String(p.name ?? '');
    return [...(produits ?? [])].sort((a, b) => (nom(a) < nom(b) ? -1 : nom(a) > nom(b) ? 1 : 0))
        .find((p) => nom(p).toLowerCase().replaceAll('œ', 'oe').includes('oeufs')) ?? null;
}

/** `EggStockLedgerService::enPlateaux`. */
export function enPlateaux(oeufs) {
    const o = Math.max(0, oeufs);
    return { plateaux: Math.trunc(o / OEUFS_PAR_PLATEAU), vrac: o % OEUFS_PAR_PLATEAU };
}

const departSaisi = (s) => ({ repro: s.departRepro, sevre: s.departSevre, jeune: s.departJeune, quatre: s.departQuatre });

/** Tout ce que l'écran calcule. `rations` : le barème de l'aviculture ; `autonomie(total_kg)` ; `produits` : le dernier tirage des produits (stock d'œufs). */
export function calculsPondeuses(lot, fiches, jour, s, rations = [], autonomie = null, produits = []) {
    const cat = { mode: 'depart_requis', repro: null, sevre: null, jeune: null, quatre: null, resultat: null, motif: null, refus_passage: null, avertissements: [], depart_requis: true, depart_date: null, depart: null, proposition: null };
    const oeufs = produitOeufs(produits);
    const comm = Math.max(0, n(s.oeufsRecoltes) - n(s.oeufsCasses));
    const sortie = {
        veille: 0, vente: 0, ventes: ventesDuJourPondeuses(lot, fiches, jour), effectifFinal: 0, taux: 0, tauxPonte: 0, commercialisables: comm, plateaux: enPlateaux(comm), produitOeufs: oeufs,
        avertissementMorts: null, cat, ration: tableauPondeuses(rations, {}), autonomie: { available: false },
    };
    if (!lot) return sortie;
    const duLot = fiches.filter((f) => f.lot_id === lot.id);
    const duJour = duLot.find((f) => jourDe(f) === jour) ?? null;
    sortie.veille = effectifVeille(lot, duLot, jour);
    sortie.vente = n(duJour?.vente);
    const transferts = Object.fromEntries(COLONNES_TRANSFERT.map((c) => [c, n(duJour?.[c])]));
    const mort = mortDuJourPondeuses(s);
    sortie.effectifFinal = computeEffectifFinal(sortie.veille, n(s.achat), n(s.ne), mort, sortie.vente, donDuJourPondeuses(s), transferts.transfert_entree, transferts.transfert_sortie);
    sortie.taux = sortie.veille > 0 ? arrondiPhp((mort / sortie.veille) * 100, 1) : 0;
    sortie.tauxPonte = sortie.veille > 0 ? arrondiPhp((n(s.oeufsRecoltes) / sortie.veille) * 100, 1) : 0;
    if (mort > sortie.veille) sortie.avertissementMorts = MOTIFS_PONDEUSES.mortsAuDessus(mort, sortie.veille);

    if (dateValide(jour)) {
        const etat = etatPourJour(lot, duLot, jour);
        cat.depart_date = etat.depart_date; cat.depart = etat.depart; cat.motif = etat.refus;
        let veille = etat.veille;
        let continuer = true;
        if (etat.mode === 'sans_chaine') {
            cat.mode = 'depart_requis';
            cat.proposition = departDepuisStade(lot, sortie.veille) ?? null;
            const saisi = departSaisi(s);
            if (Object.values(saisi).some((v) => !nonNul(v))) {
                if (Object.values(saisi).some(nonNul)) cat.motif = verifierDepart(saisi, sortie.veille);
                continuer = false;
            } else {
                cat.motif = verifierDepart(saisi, sortie.veille);
                if (cat.motif !== null) continuer = false; else veille = saisi;
            }
        } else {
            cat.mode = etat.mode;
            cat.depart_requis = false;
        }
        if (continuer && nonNul(veille)) {
            const v = sortie.ventes;
            const r = calculerJour(VOLAILLES_PONTE, veille, {
                achat: n(s.achat), ne: n(s.ne), vente_repro: v.repro, vente_sevre: v.sevre, vente_jeune: v.jeune, vente_4: v.quatre,
                mort_repro: n(s.mortRepro), mort_sevre: n(s.mortSevre), mort_jeune: n(s.mortJeune), mort_4: n(s.mortQuatre),
                don_repro: n(s.donRepro), don_sevre: n(s.donSevre), don_jeune: n(s.donJeune), don_4: n(s.donQuatre),
                passage_4_sevre: n(s.passage1), passage: n(s.passage2), passage_jeune_repro: n(s.passage3), ...transferts,
            }, sortie.effectifFinal);
            cat.resultat = r; cat.repro = r.repro; cat.sevre = r.sevre; cat.jeune = r.jeune; cat.quatre = r.quatre; cat.refus_passage = r.refus;
            if (r.sommeDifferente === true) cat.avertissements.push(MOTIFS_PONDEUSES.sommeDifferente(jourFr(jour), r.repro + r.sevre + r.jeune + r.quatre, sortie.effectifFinal));
        }
    }
    sortie.ration = tableauPondeuses(rations, { repro: cat.repro, sevre: cat.sevre, jeune: cat.jeune, quatre: cat.quatre });
    sortie.autonomie = autonomie ? autonomie(sortie.ration.total_kg) : { available: false };
    return sortie;
}

/**
 * `saveDay` : mêmes contrôles et même ORDRE que le PHP (droit, bande, exercice clos, date, jour avant le départ, départ refusé ou manquant, passage, répartition des
 * morts et dons, ventes non ventilées), AUCUNE écriture si un refus ; puis la fiche (ventilation des morts, dons ET ventes, œufs), le départ (une fois) et la cascade.
 */
export function enregistrerJourPondeuses(lot, fiches, jour, s, ctx = {}) {
    if (ctx.role !== undefined && ctx.role !== null && !(ctx.roles ?? ['admin', 'animalier']).includes(ctx.role)) return { refus: ctx.droit };
    if (!lot) return { refus: MOTIFS_PONDEUSES.bande };
    const clos = ctx.refusExercice ? ctx.refusExercice(ctx.exercices ?? [], jour) : null;
    if (clos) return { refus: clos };
    if (!dateValide(jour)) return { refus: MOTIFS_PONDEUSES.dateInvalide };
    const c = calculsPondeuses(lot, fiches, jour, s, ctx.rations ?? []);
    if (c.cat.mode === 'avant_depart') return { refus: MOTIFS_PONDEUSES.avantDepart(jourFr(c.cat.depart_date)) };
    if (c.cat.mode === 'refus') return { refus: c.cat.motif };
    let departAEcrire = false;
    if (c.cat.mode === 'depart_requis') {
        const saisi = departSaisi(s);
        const aucun = Object.values(saisi).filter(nonNul).length === 0;
        const refus = aucun ? MOTIFS_PONDEUSES.departManquant : verifierDepart(saisi, c.veille);
        if (refus !== null) return { refus };
        departAEcrire = true;
    }
    if (c.cat.refus_passage !== null && c.cat.refus_passage !== undefined) return { refus: c.cat.refus_passage };
    const mort = n(s.mortRepro) + n(s.mortJeune) + n(s.mortSevre) + n(s.mortQuatre);
    const don = n(s.donRepro) + n(s.donJeune) + n(s.donSevre) + n(s.donQuatre);
    if ((nonNul(s.mortEnregistre) && mort === 0) || (nonNul(s.donEnregistre) && don === 0)) return { refus: MOTIFS_PONDEUSES.ancienneFiche };
    if (c.ventes.non_ventilee) return { refus: MOTIFS_PONDEUSES.ventesNonVentilees };

    const donnees = {
        achat: n(s.achat), ne: n(s.ne), mort, vente: c.vente, don, effectif_final: c.effectifFinal, ponte_total: n(s.oeufsRecoltes), ponte_casses: n(s.oeufsCasses),
        mort_repro: n(s.mortRepro), mort_sevre: n(s.mortSevre), mort_jeune: n(s.mortJeune), mort_4: n(s.mortQuatre),
        don_repro: n(s.donRepro), don_sevre: n(s.donSevre), don_jeune: n(s.donJeune), don_4: n(s.donQuatre),
        vente_repro: c.ventes.repro, vente_sevre: c.ventes.sevre, vente_jeune: c.ventes.jeune, vente_4: c.ventes.quatre,
        passage_4_sevre: n(s.passage1), passage_sevre_jeune: n(s.passage2), passage_jeune_repro: n(s.passage3),
        weight_sample_avg_g: s.peseeTotal && c.effectifFinal > 0 ? arrondiPhp(n(s.peseeTotal) / c.effectifFinal, 0) : null,
    };
    if (departAEcrire) Object.assign(donnees, { cat_depart_repro: s.departRepro, cat_depart_sevre: s.departSevre, cat_depart_jeune: s.departJeune, cat_depart_4: s.departQuatre });
    const existante = fiches.find((f) => f.lot_id === lot.id && jourDe(f) === jour);
    const fiche = { ...(existante ?? { id: ctx.idFiche ?? globalThis.crypto.randomUUID(), lot_id: lot.id, entry_date: jour }), ...donnees, sync_status: 'pending' };
    const avec = existante ? fiches.map((f) => (f === existante ? fiche : f)) : [...fiches, fiche];
    const cascade = recalculerEnCascade(lot, avec.filter((f) => f.lot_id === lot.id), jour);
    return { refus: null, fiche, lot: cascade.lot, fiches: [...avec.filter((f) => f.lot_id !== lot.id), ...cascade.fiches] };
}

// ------------------------------------------------------------------------------------------------------------ formulaire

/**
 * Le formulaire (DOM, jamais `innerHTML`). `lire()` rend `{lot, fiches, jour, rations, autonomie, protocole, produits, conflitsSoins, lectureSeule, enAttente, conflit}` ;
 * `actions` : `enregistrer`, `renvoyer`, `abandonner`, `validerTraitements`, `renvoyerSoin`, `abandonnerSoin`. `rendreAutonomie` est injectée.
 */
export function rendreFormulairePondeuses(h, { s, lire, actions, retourInitial = null, messages, rendreAutonomie, titreProphylaxie = 'Traitements & Prophylaxie', observationsLibelle = 'Observations', observationsExemple = 'ex : RAS' }) {
    const L = LIBELLES_PONDEUSES_FICHE;
    const M = MOTIFS_PONDEUSES;
    const champs = new Map();
    const entier = (cle, libelle) => {
        const input = h('input', { type: 'number', min: '0', id: `saisie-${cle}`, class: 'fiche-select', value: String(s[cle] ?? ''), ...(cle === 'peseeTotal' ? { placeholder: L.peseeExemple } : {}) });
        input.addEventListener('input', () => { s[cle] = input.value === '' ? (cle.startsWith('depart') || cle === 'peseeTotal' ? null : 0) : Math.max(0, Math.trunc(Number(input.value)) || 0); rafraichir(); });
        champs.set(cle, input);
        return h('label', { class: 'saisie-champ' }, h('span', { class: 'muted' }, libelle), input);
    };
    const groupe = (titre, prefixe, enregistre, message) => h('div', { class: 'saisie-groupe' }, h('b', {}, titre),
        nonNul(enregistre) ? h('p', { class: 'bandeau avert', role: 'status', style: 'margin:0' }, message(enregistre)) : null,
        h('div', { class: 'saisie-quatre' }, ...STADES_SAISIE.map((st) => entier(`${prefixe}${st.suffixe}`, LIBELLES_STADES_PONDEUSE[st.cle]))));
    const departZone = h('div', { id: 'saisie-depart' });
    const alertes = h('div', { id: 'saisie-alertes', class: 'saisie-alertes', role: 'status' });
    const finale = h('b', { id: 'saisie-effectif-final' });
    const taux = h('b', { id: 'saisie-taux' });
    const commercialisables = h('b', { id: 'saisie-commercialisables' });
    const tauxPonte = h('b', { id: 'saisie-taux-ponte' });
    const plateaux = h('div', { id: 'saisie-plateaux', class: 'saisie-champ' });
    const incrementation = h('div', { id: 'saisie-incrementation', class: 'saisie-champ' });
    const taille = h('b', { id: 'saisie-echantillon' });
    const poidsMoyen = h('b', { id: 'saisie-poids-moyen' });
    const venteChamp = h('b', { id: 'saisie-vente' });
    const ventesStade = h('p', { id: 'ventes-par-stade', class: 'muted' });
    const provende = h('div', { id: 'saisie-provende' });
    const autonomieZone = h('div', { id: 'saisie-autonomie' });
    const etatEnvoi = h('p', { id: 'saisie-etat', class: 'muted', role: 'status' });
    const retour = h('p', { id: 'saisie-retour', role: 'alert', class: 'muted' }, retourInitial);
    const prophyZone = h('div', { id: 'saisie-prophy-zone' });

    function rafraichir() {
        const ctx = lire();
        const c = calculsPondeuses(ctx.lot, ctx.fiches, ctx.jour, s, ctx.rations, ctx.autonomie, ctx.produits);
        const bloc = (texte, classe) => h('div', { class: `bandeau ${classe}`, style: 'margin:6px 0 0', role: classe === 'avert' ? 'status' : 'alert' }, texte);
        const notes = [];
        if (c.cat.motif) notes.push(bloc(c.cat.motif, 'refus'));
        if (c.cat.refus_passage) notes.push(bloc(c.cat.refus_passage, 'refus'));
        if (c.avertissementMorts) notes.push(bloc(c.avertissementMorts, 'avert'));
        for (const a of c.cat.avertissements) notes.push(bloc(a, 'avert'));
        if (c.ventes.non_ventilee) notes.push(bloc(M.ventesNonVentileesAvertissement, 'avert'));
        alertes.replaceChildren(...notes);
        finale.textContent = String(c.effectifFinal);
        taux.textContent = `${c.taux.toFixed(1).replace('.', ',')} %`;
        commercialisables.textContent = String(c.commercialisables);
        tauxPonte.textContent = `${c.tauxPonte.toFixed(1).replace('.', ',')} %`;
        plateaux.replaceChildren(h('b', {}, L.plateaux(c.plateaux)));
        incrementation.replaceChildren(c.produitOeufs ? h('b', {}, L.incrementation(c.plateaux, c.produitOeufs.name)) : h('span', { class: 'muted' }, M.aucunProduitOeufs));
        venteChamp.textContent = String(c.vente);
        ventesStade.textContent = L.ventesStade(c.ventes);
        taille.textContent = String(c.effectifFinal);
        poidsMoyen.textContent = s.peseeTotal && c.effectifFinal > 0 ? `${arrondiPhp(s.peseeTotal / c.effectifFinal, 0)} g` : '—';
        provende.replaceChildren(h('b', {}, L.provende), c.cat.repro === null
            ? h('p', { id: 'ration-depart-requis', class: 'muted' }, M.rationDepart)
            : h('table', { class: 'rtable' },
                h('thead', {}, h('tr', {}, ...[L.categorie, L.effectif, L.ration, L.servie].map((t) => h('th', {}, t)))),
                h('tbody', {}, ...c.ration.lignes.map((l) => h('tr', {}, h('td', {}, l.libelle), h('td', { class: 'num' }, h('input', { id: `cat-eff-${l.cle}`, type: 'text', disabled: true, value: String(l.effectif), style: 'width:56px;text-align:center' })), h('td', { class: 'num' }, `${l.ration} g/j`), h('td', { class: 'num', id: `cat-prov-${l.cle}-g` }, `${l.total_g} g`)))),
                h('tfoot', {}, h('tr', {}, h('td', { colspan: 3 }, L.totalProvende), h('td', { class: 'num', id: 'day-total-provende-g' }, `${c.ration.total_g} g (${c.ration.total_kg} Kg)`)))));
        autonomieZone.replaceChildren(rendreAutonomie(h, c.autonomie, 'aviculture'));
        etatEnvoi.textContent = ctx.enAttente ? messages.enAttente : '';
        return c;
    }

    const ctx0 = lire();
    const c0 = calculsPondeuses(ctx0.lot, ctx0.fiches, ctx0.jour, s, ctx0.rations, ctx0.autonomie, ctx0.produits);
    if (c0.cat.depart_requis) {
        departZone.append(h('div', { class: 'saisie-groupe', id: 'depart-requis' }, h('b', {}, L.departTitre), h('p', { class: 'muted' }, M.departRequis(c0.veille)),
            h('div', { class: 'saisie-quatre' }, ...STADES_SAISIE.map((st) => entier(`depart${st.suffixe}`, LIBELLES_STADES_PONDEUSE[st.cle]))),
            c0.cat.proposition ? h('button', { type: 'button', class: 'btn', id: 'depart-proposition', onclick: () => {
                for (const st of STADES_SAISIE) { const prop = `depart${st.suffixe}`; s[prop] = c0.cat.proposition[st.emp]; const el = champs.get(prop); if (el) el.value = String(s[prop]); }
                rafraichir();
            } }, M.proposition(c0.cat.proposition)) : null));
    } else if (c0.cat.depart) {
        departZone.append(h('div', { class: 'saisie-groupe' }, h('b', {}, L.departVerrouille), h('p', { class: 'muted' }, M.departFixe(jourFr(c0.cat.depart_date))),
            h('div', { class: 'saisie-quatre' }, ...STADES_SAISIE.map((st) => h('label', { class: 'saisie-champ' }, h('span', { class: 'muted' }, LIBELLES_STADES_PONDEUSE[st.cle]), h('input', { id: `depart-${st.emp}`, type: 'number', value: String(c0.cat.depart[st.emp]), disabled: true, class: 'fiche-select' })))),
            c0.cat.mode === 'avant_depart' ? h('p', { class: 'alerte', id: 'avant-depart' }, M.avantDepart(jourFr(c0.cat.depart_date))) : null));
    }

    const conflit = ctx0.conflit
        ? h('div', { class: 'bandeau refus', id: 'saisie-conflit', role: 'alert', style: 'margin:0' }, `Fiche refusée par le serveur : ${ctx0.conflit} `,
            h('button', { type: 'button', class: 'btn', id: 'saisie-renvoyer', onclick: () => actions.renvoyer() }, 'Renvoyer'),
            h('button', { type: 'button', class: 'btn danger', id: 'saisie-abandonner', onclick: () => actions.abandonner() }, 'Abandonner cette saisie'))
        : null;
    const coches = new Set();
    const observations = h('input', { type: 'text', id: 'saisie-observations', class: 'fiche-select', style: 'width:100%', placeholder: observationsExemple, disabled: Boolean(ctx0.lectureSeule) });
    const conflitsSoins = (ctx0.conflitsSoins ?? []).map((x) => h('div', { class: 'bandeau refus', role: 'alert', style: 'margin:6px 0 0', 'data-conflit-soin': x.id }, `Soin « ${x.soin.action_type} » refusé par le serveur : ${x.motif} `,
        h('button', { type: 'button', class: 'btn', onclick: () => actions.renvoyerSoin(x.id) }, 'Renvoyer'), h('button', { type: 'button', class: 'btn danger', onclick: () => actions.abandonnerSoin(x.id) }, 'Abandonner ce soin')));
    const message = (r) => { retour.textContent = r.refus ?? r.avertissement ?? r.message ?? ''; retour.className = r.refus ? 'alerte' : 'muted'; };
    prophyZone.append(rendreProphylaxie(h, { titre: titreProphylaxie, protocole: ctx0.protocole, coches, lectureSeule: ctx0.lectureSeule, actions: { valider: async () => message(await actions.validerTraitements([...coches], observations.value)) } }), ...conflitsSoins,
        h('label', { class: 'saisie-champ' }, h('span', { class: 'muted' }, observationsLibelle), observations));
    const bouton = h('button', { type: 'button', class: 'btn plein', id: 'saisie-enregistrer', disabled: Boolean(ctx0.lectureSeule) }, h('span', { class: 'material-symbols-outlined' }, 'save'), L.enregistrer);
    bouton.addEventListener('click', async () => {
        const r = await actions.enregistrer(s);
        retour.textContent = r.refus ?? messages.enregistre;
        retour.className = r.refus ? 'alerte' : 'muted';
        rafraichir();
    });

    const racine = h('div', { id: 'fiche-saisie', class: 'saisie-form' },
        ctx0.lectureSeule ? h('div', { class: 'bandeau neutre', id: 'saisie-lecture-seule', style: 'margin:0 0 8px' }, ctx0.lectureSeule) : null,
        conflit,
        h('div', { class: 'saisie-trois' }, entier('achat', L.achat), entier('ne', L.ne), h('div', { class: 'saisie-champ' }, h('span', { class: 'muted' }, `${L.vente} ${L.venteSuite}`), venteChamp, ventesStade)),
        h('div', { class: 'saisie-groupe' }, h('b', {}, L.oeufs),
            h('div', { class: 'saisie-quatre' }, entier('oeufsRecoltes', L.recoltes), entier('oeufsCasses', L.casses),
                h('div', { class: 'saisie-champ' }, h('span', { class: 'muted' }, L.commercialisables), commercialisables),
                h('div', { class: 'saisie-champ' }, h('span', { class: 'muted' }, L.tauxPonte), tauxPonte)),
            h('div', { class: 'saisie-trois' }, plateaux, incrementation)),
        groupe(L.morts, 'mort', s.mortEnregistre, M.mortEnregistre),
        groupe(L.dons, 'don', s.donEnregistre, M.donEnregistre),
        h('div', { class: 'saisie-trois' }, entier('passage1', L.passages[0]), entier('passage2', L.passages[1]), entier('passage3', L.passages[2])),
        departZone, alertes,
        h('div', { class: 'saisie-trois' },
            h('div', { class: 'saisie-champ' }, h('span', { class: 'muted' }, L.effectifFinal), finale),
            h('div', { class: 'saisie-champ' }, h('span', { class: 'muted' }, L.taux), taux)),
        provende, autonomieZone,
        h('div', { class: 'saisie-trois' }, entier('peseeTotal', L.pesee), h('div', { class: 'saisie-champ' }, h('span', { class: 'muted' }, L.taille), taille), h('div', { class: 'saisie-champ' }, h('span', { class: 'muted' }, `${L.poidsMoyen} ${L.poidsMoyenSuite}`), poidsMoyen)),
        h('div', { class: 'saisie-groupe', id: 'saisie-stock-oeufs' }, h('b', {}, L.stockTitre),
            h('div', { class: 'saisie-quatre' }, ...L.stockCases.map((libelle) => h('div', { class: 'saisie-champ' }, h('span', { class: 'muted' }, libelle), h('b', {}, '—')))),
            h('p', { class: 'muted' }, L.stockHorsLigne)),
        prophyZone, retour, etatEnvoi, h('div', { class: 'groupe', style: 'justify-content:flex-end' }, bouton));
    if (ctx0.lectureSeule) for (const el of racine.querySelectorAll('input')) el.disabled = true;
    rafraichir();
    return racine;
}
