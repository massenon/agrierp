/**
 * PWA-3 (fiche volailles REPRODUCTEURS, VOL-1) — LA SAISIE D'UN JOUR, hors ligne.
 *
 * Transposition de `Livewire\Elevage\FicheReproducteurs` : `loadDay` (`chargerJourVolailles`), les propriétés calculées (`calculsVolailles` : effectif de la veille,
 * effectif final, taux de mortalité et d'éclosion, catégories `categoriesJour`, ventes du jour par catégorie, rationnement `CategorieVolaille::tableauReproducteurs`,
 * autonomie) et `saveDay` (`enregistrerJourVolailles`). Différences avec les lapins et les porcs, lues dans le PHP et le Blade : trois catégories Reproducteur / Jeune /
 * Poussin (emplacements `repro` / `jeune` / `sevre`), JAMAIS de catégorie inconnue, DÉPART OBLIGATOIRE avant toute journée (proposé d'après le stade, jamais déduit), ventes
 * par catégorie posées par la caisse (lecture seule), passage Poussin → Jeune, couvoir (`ponte_total` = œufs couvés, `ne` = poussins nés), morts et dons saisis par
 * catégorie avec un total déjà enregistré conservé tant qu'aucune répartition n'est saisie.
 */

import { computeEffectifFinal, effectifVeille, etatPourJour, jourDe, recalculerEnCascade } from './chaine-effectif.js';
import { calculerJour, departDepuisStade, verifierDepart, VOLAILLES_REPRO } from './effectif-categories.js';
import { tableauReproducteurs } from './fiche-lapins-calculs.js';
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
const jours = (a, b) => Math.round((Date.UTC(+b.slice(0, 4), +b.slice(5, 7) - 1, +b.slice(8, 10)) - Date.UTC(+a.slice(0, 4), +a.slice(5, 7) - 1, +a.slice(8, 10))) / 86400000);
const COLONNES_TRANSFERT = ['transfert_entree', 'transfert_sortie', 'transfert_entree_repro', 'transfert_entree_sevre', 'transfert_entree_jeune', 'transfert_sortie_repro', 'transfert_sortie_sevre', 'transfert_sortie_jeune', 'transfert_entree_4', 'transfert_sortie_4'];

export const MOTIFS_VOLAILLES = {
    bande: "Sélectionnez d'abord une bande.",
    dateInvalide: 'Date invalide : choisissez un jour.',
    avantDepart: (jourFrancais) => `Jour antérieur à l'effectif de départ fixé le ${jourFrancais} : il n'est pas saisissable.`,
    departManquant: "Saisissez d'abord l'effectif de départ de la bande par catégorie (Reproducteur, Jeune, Poussin) : la journée ne peut pas être enregistrée sans lui.",
    ancienneFiche: "Cette fiche porte des morts ou des dons non ventilés par catégorie : ventilez-les (Reproducteur / Jeune / Poussin) avant d'enregistrer.",
    ventesNonVentilees: "Cette journée porte des ventes d'avant la mise en place des catégories, non ventilées : elle ne peut pas être ré-enregistrée. Saisissez le départ de la bande un autre jour.",
    ventesNonVentileesAvertissement: "Cette journée porte des ventes d'avant la mise en place des catégories, non ventilées : elle ne peut pas être ré-enregistrée.",
    sommeDifferente: (jourFrancais, somme, total) => `Avertissement — fiche du ${jourFrancais} : la somme des catégories (${somme}) diffère de l'effectif total (${total}). Un effectif de catégorie ne descend jamais sous 0 : vérifiez les ventes, morts et dons saisis.`,
    mortEnregistre: (m) => `${m} mort(s) déjà enregistré(s) ce jour, sans répartition par catégorie : ventilez-les ci-dessous (Reproducteur / Jeune / Poussin) avant d'enregistrer.`,
    donEnregistre: (d) => `${d} don(s) déjà enregistré(s) ce jour, sans répartition par catégorie : ventilez-les ci-dessous (Reproducteur / Jeune / Poussin) avant d'enregistrer.`,
    mortsAuDessus: (morts, veille) => `Morts du jour (${morts}) supérieurs à l'effectif de la veille (${veille}) : l'effectif est ramené à 0, vérifiez la saisie.`,
    aucuneProposition: "Aucune proposition pour le stade de cette bande : saisissez le départ de chaque catégorie.",
    departRequis: (veille) => `Cette bande n'a pas encore d'effectif de départ : saisissez l'effectif de chaque catégorie au DÉBUT de ce jour, avant les mouvements du jour. La somme des trois catégories doit égaler l'effectif total au début du jour (${veille}). Il est verrouillé au premier enregistrement ; la journée ne s'enregistre pas sans lui.`,
    departFixe: (jourFrancais) => `Effectif de départ fixé le ${jourFrancais} (au début de ce jour).`,
    proposition: (p) => `Reprendre la proposition d'après le stade de la bande (Reproducteur ${p.repro} · Jeune ${p.jeune} · Poussin ${p.sevre})`,
    rationDepart: "Saisissez l'effectif de départ de la bande pour calculer les effectifs par catégorie et la provende servie.",
};

export const LIBELLES_VOLAILLES_FICHE = {
    achat: 'Achats du jour', vente: 'Ventes', venteSuite: '(POS, réel)', ventesCategorie: (v) => `Reproducteur ${v.repro} · Jeune ${v.jeune} · Poussin ${v.sevre}`,
    couvoir: 'Workflow Couvoir & Éclosion (Incubation → Poussins Nés)', oeufs: 'Œufs Couvés (Mis en incubation)', nes: 'Poussins Nés (Éclosion du jour)', eclosion: "Taux d'Éclosion Calculé (%)",
    morts: 'Morts par catégorie', dons: 'Dons par catégorie', categories: ['Reproducteur', 'Jeune', 'Poussin'],
    passage: 'Passage du jour (Poussin → Jeune)',
    departTitre: 'Effectif de départ par catégorie (obligatoire)', departVerrouille: 'Effectif de départ par catégorie (verrouillé)',
    effectifFinal: 'Effectif Final', taux: 'Taux de Mortalité du Jour (%)',
    provende: 'Rationnement & Provende Servie par Catégorie (en Grammes g/j)', categorie: 'Catégorie', effectif: 'Effectif', ration: 'Ration Normative', servie: 'Provende Servie (g)',
    totalProvende: 'TOTAL PROVENDE SERVIE DU JOUR (CUMUL EN GRAMMES)',
    pesee: 'Poids Général Pesé (g)', peseeExemple: 'ex : 1800', poidsMoyen: 'Poids Moyen Constaté', poidsMoyenSuite: '(Poids Général ÷ Effectif Final)',
    gmq: 'Poids moyen estimé (GMQ) :', enregistrer: 'Enregistrer ce Jour',
};

export const saisieVideVolailles = () => ({
    achat: 0, oeufsCouves: 0, poussinsNes: 0, mortRepro: 0, mortPoulet: 0, mortPoussin: 0, donRepro: 0, donPoulet: 0, donPoussin: 0, passage: 0,
    departRepro: null, departSevre: null, departJeune: null, mortEnregistre: null, donEnregistre: null, peseeTotal: null,
});

/** `loadDay` : la fiche de LA bande à ce jour ; le départ n'est JAMAIS prérempli (il est proposé par un bouton). */
export function chargerJourVolailles(lot, fiches, jour) {
    const s = saisieVideVolailles();
    const f = lot ? fiches.find((x) => x.lot_id === lot.id && jourDe(x) === jour) : null;
    if (!f) return s;
    s.achat = n(f.achat); s.oeufsCouves = n(f.ponte_total); s.poussinsNes = n(f.ne);
    if (nonNul(f.mort_repro) && nonNul(f.mort_sevre) && nonNul(f.mort_jeune)) { s.mortRepro = n(f.mort_repro); s.mortPoussin = n(f.mort_sevre); s.mortPoulet = n(f.mort_jeune); }
    else s.mortEnregistre = n(f.mort) > 0 ? n(f.mort) : null;
    if (nonNul(f.don_repro) && nonNul(f.don_sevre) && nonNul(f.don_jeune)) { s.donRepro = n(f.don_repro); s.donPoussin = n(f.don_sevre); s.donPoulet = n(f.don_jeune); }
    else s.donEnregistre = n(f.don) > 0 ? n(f.don) : null;
    s.passage = n(f.passage_sevre_jeune);
    const final = n(f.effectif_final);
    s.peseeTotal = f.weight_sample_avg_g && final > 0 ? Math.round(Number(f.weight_sample_avg_g) * final) : null;
    return s;
}

export const mortDuJourVolailles = (s) => { const x = n(s.mortRepro) + n(s.mortPoulet) + n(s.mortPoussin); return x > 0 ? x : n(s.mortEnregistre); };
export const donDuJourVolailles = (s) => { const x = n(s.donRepro) + n(s.donPoulet) + n(s.donPoussin); return x > 0 ? x : n(s.donEnregistre); };

/** `getVentesDuJourProperty` : les ventes du jour par catégorie (posées par la caisse) ; `non_ventilee` : des ventes d'avant la mise en place des catégories. */
export function ventesDuJourVolailles(lot, fiches, jour) {
    const f = lot && dateValide(jour) ? fiches.find((x) => x.lot_id === lot.id && jourDe(x) === jour) ?? null : null;
    return { repro: n(f?.vente_repro), sevre: n(f?.vente_sevre), jeune: n(f?.vente_jeune), non_ventilee: f !== null && n(f.vente) > 0 && !nonNul(f.vente_repro) };
}

/** `getPoidsMoyenEstimeProperty` (identique aux lapins : GMQ entre la première et la dernière pesée antérieure). */
export function poidsEstimeVolailles(lot, fiches, jour, s) {
    if (nonNul(s.peseeTotal) || !lot) return null;
    const pesees = fiches.filter((f) => f.lot_id === lot.id && nonNul(f.weight_sample_avg_g) && jourDe(f) < jour).sort((a, b) => (jourDe(a) < jourDe(b) ? -1 : 1));
    if (pesees.length === 0) return null;
    const derniere = pesees.at(-1);
    const ecoules = jours(jourDe(derniere), jour);
    const poids = Number(derniere.weight_sample_avg_g);
    if (ecoules <= 0) return arrondiPhp(poids, 0);
    let gmq = 0;
    if (pesees.length >= 2) {
        const jg = jours(jourDe(pesees[0]), jourDe(derniere));
        gmq = jg > 0 ? (poids - Number(pesees[0].weight_sample_avg_g)) / jg : 0;
    }
    return arrondiPhp(poids + gmq * ecoules, 0);
}

/** Tout ce que l'écran calcule. `rations` : le barème de l'aviculture ; `autonomie(total_kg)` : l'évaluation d'autonomie. */
export function calculsVolailles(lot, fiches, jour, s, rations = [], autonomie = null) {
    const cat = { mode: 'depart_requis', repro: null, sevre: null, jeune: null, resultat: null, motif: null, refus_passage: null, avertissements: [], depart_requis: true, depart_date: null, depart: null, proposition: null };
    const sortie = { veille: 0, vente: 0, ventes: ventesDuJourVolailles(lot, fiches, jour), effectifFinal: 0, taux: 0, eclosion: null, avertissementMorts: null, poidsEstime: null, cat, ration: tableauReproducteurs(rations, {}), autonomie: { available: false } };
    if (!lot) return sortie;
    const duLot = fiches.filter((f) => f.lot_id === lot.id);
    const duJour = duLot.find((f) => jourDe(f) === jour) ?? null;
    sortie.veille = effectifVeille(lot, duLot, jour);
    sortie.vente = n(duJour?.vente);
    const transferts = Object.fromEntries(COLONNES_TRANSFERT.map((c) => [c, n(duJour?.[c])]));
    const mort = mortDuJourVolailles(s);
    sortie.effectifFinal = computeEffectifFinal(sortie.veille, n(s.achat), n(s.poussinsNes), mort, sortie.vente, donDuJourVolailles(s), transferts.transfert_entree, transferts.transfert_sortie);
    sortie.taux = sortie.veille > 0 ? arrondiPhp((mort / sortie.veille) * 100, 1) : 0;
    sortie.eclosion = n(s.oeufsCouves) > 0 ? arrondiPhp((n(s.poussinsNes) / n(s.oeufsCouves)) * 100, 1) : null;
    if (mort > sortie.veille) sortie.avertissementMorts = MOTIFS_VOLAILLES.mortsAuDessus(mort, sortie.veille);
    sortie.poidsEstime = poidsEstimeVolailles(lot, fiches, jour, s);

    if (dateValide(jour)) {
        const etat = etatPourJour(lot, duLot, jour);
        cat.depart_date = etat.depart_date; cat.depart = etat.depart; cat.motif = etat.refus;
        let veille = etat.veille;
        let continuer = true;
        if (etat.mode === 'sans_chaine') {
            cat.mode = 'depart_requis';
            cat.proposition = departDepuisStade(lot, sortie.veille) ?? null;
            const saisi = { repro: s.departRepro, sevre: s.departSevre, jeune: s.departJeune };
            if (Object.values(saisi).some((v) => v === null || v === undefined)) {
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
        if (continuer && veille !== null && veille !== undefined) {
            const v = sortie.ventes;
            const r = calculerJour(VOLAILLES_REPRO, veille, {
                achat: n(s.achat), ne: n(s.poussinsNes), vente_repro: v.repro, vente_sevre: v.sevre, vente_jeune: v.jeune,
                mort_repro: n(s.mortRepro), mort_sevre: n(s.mortPoussin), mort_jeune: n(s.mortPoulet),
                don_repro: n(s.donRepro), don_sevre: n(s.donPoussin), don_jeune: n(s.donPoulet), passage: n(s.passage), ...transferts,
            }, sortie.effectifFinal);
            cat.resultat = r; cat.repro = r.repro; cat.sevre = r.sevre; cat.jeune = r.jeune; cat.refus_passage = r.refus;
            if (r.sommeDifferente === true) cat.avertissements.push(MOTIFS_VOLAILLES.sommeDifferente(jourFr(jour), r.repro + r.sevre + r.jeune, sortie.effectifFinal));
        }
    }
    sortie.ration = tableauReproducteurs(rations, { repro: cat.repro, sevre: cat.sevre, jeune: cat.jeune });
    sortie.autonomie = autonomie ? autonomie(sortie.ration.total_kg) : { available: false };
    return sortie;
}

/**
 * `saveDay` : mêmes contrôles et même ORDRE que le PHP (droit, bande, exercice clos, date, jour avant le départ, départ refusé ou manquant, passage, répartition des
 * morts et dons, ventes non ventilées), AUCUNE écriture si un refus ; puis la fiche (ventilation des morts, dons ET ventes), le départ (une fois) et la cascade.
 */
export function enregistrerJourVolailles(lot, fiches, jour, s, ctx = {}) {
    if (ctx.role !== undefined && ctx.role !== null && !(ctx.roles ?? ['admin', 'animalier']).includes(ctx.role)) return { refus: ctx.droit };
    if (!lot) return { refus: MOTIFS_VOLAILLES.bande };
    const clos = ctx.refusExercice ? ctx.refusExercice(ctx.exercices ?? [], jour) : null;
    if (clos) return { refus: clos };
    if (!dateValide(jour)) return { refus: MOTIFS_VOLAILLES.dateInvalide };
    const c = calculsVolailles(lot, fiches, jour, s, ctx.rations ?? []);
    if (c.cat.mode === 'avant_depart') return { refus: MOTIFS_VOLAILLES.avantDepart(jourFr(c.cat.depart_date)) };
    if (c.cat.mode === 'refus') return { refus: c.cat.motif };
    let departAEcrire = false;
    if (c.cat.mode === 'depart_requis') {
        const saisi = { repro: s.departRepro, sevre: s.departSevre, jeune: s.departJeune };
        const aucun = Object.values(saisi).some((v) => v === null || v === undefined) && Object.values(saisi).filter(nonNul).length === 0;
        const refus = aucun ? MOTIFS_VOLAILLES.departManquant : verifierDepart(saisi, c.veille);
        if (refus !== null) return { refus };
        departAEcrire = true;
    }
    if (c.cat.refus_passage !== null && c.cat.refus_passage !== undefined) return { refus: c.cat.refus_passage };
    const mort = n(s.mortRepro) + n(s.mortPoulet) + n(s.mortPoussin);
    const don = n(s.donRepro) + n(s.donPoulet) + n(s.donPoussin);
    if ((nonNul(s.mortEnregistre) && mort === 0) || (nonNul(s.donEnregistre) && don === 0)) return { refus: MOTIFS_VOLAILLES.ancienneFiche };
    if (c.ventes.non_ventilee) return { refus: MOTIFS_VOLAILLES.ventesNonVentilees };

    const donnees = {
        achat: n(s.achat), ne: n(s.poussinsNes), mort, vente: c.vente, don, effectif_final: c.effectifFinal, ponte_total: n(s.oeufsCouves),
        mort_repro: n(s.mortRepro), mort_sevre: n(s.mortPoussin), mort_jeune: n(s.mortPoulet),
        don_repro: n(s.donRepro), don_sevre: n(s.donPoussin), don_jeune: n(s.donPoulet),
        vente_repro: c.ventes.repro, vente_sevre: c.ventes.sevre, vente_jeune: c.ventes.jeune,
        passage_sevre_jeune: n(s.passage),
        weight_sample_avg_g: s.peseeTotal && c.effectifFinal > 0 ? arrondiPhp(n(s.peseeTotal) / c.effectifFinal, 0) : null,
    };
    if (departAEcrire) Object.assign(donnees, { cat_depart_repro: s.departRepro, cat_depart_sevre: s.departSevre, cat_depart_jeune: s.departJeune });
    const existante = fiches.find((f) => f.lot_id === lot.id && jourDe(f) === jour);
    const fiche = { ...(existante ?? { id: ctx.idFiche ?? globalThis.crypto.randomUUID(), lot_id: lot.id, entry_date: jour }), ...donnees, sync_status: 'pending' };
    const avec = existante ? fiches.map((f) => (f === existante ? fiche : f)) : [...fiches, fiche];
    const cascade = recalculerEnCascade(lot, avec.filter((f) => f.lot_id === lot.id), jour);
    return { refus: null, fiche, lot: cascade.lot, fiches: [...avec.filter((f) => f.lot_id !== lot.id), ...cascade.fiches] };
}

// ------------------------------------------------------------------------------------------------------------ formulaire

/**
 * Le formulaire (DOM, jamais `innerHTML`). `lire()` rend `{lot, fiches, jour, rations, autonomie, protocole, conflitsSoins, lectureSeule, enAttente, conflit}` ;
 * `actions` : `enregistrer`, `renvoyer`, `abandonner`, `validerTraitements`, `renvoyerSoin`, `abandonnerSoin`. `rendreAutonomie` est injectée (`rendreAutonomie(h, a, filiere)`).
 */
export function rendreFormulaireVolailles(h, { s, lire, actions, retourInitial = null, messages, rendreAutonomie, titreProphylaxie = 'Traitements & Prophylaxie', observationsLibelle = 'Observations', observationsExemple = 'ex : RAS' }) {
    const L = LIBELLES_VOLAILLES_FICHE;
    const M = MOTIFS_VOLAILLES;
    const champs = new Map();
    const entier = (cle, libelle) => {
        const input = h('input', { type: 'number', min: '0', id: `saisie-${cle}`, class: 'fiche-select', value: String(s[cle] ?? '') });
        input.addEventListener('input', () => { s[cle] = input.value === '' ? (cle.startsWith('depart') || cle === 'peseeTotal' ? null : 0) : Math.max(0, Math.trunc(Number(input.value)) || 0); rafraichir(); });
        champs.set(cle, input);
        return h('label', { class: 'saisie-champ' }, h('span', { class: 'muted' }, libelle), input);
    };
    const groupe = (titre, prefixe, enregistre, message) => h('div', { class: 'saisie-groupe' }, h('b', {}, titre),
        nonNul(enregistre) ? h('p', { class: 'bandeau avert', role: 'status', style: 'margin:0' }, message(enregistre)) : null,
        h('div', { class: 'saisie-trois' }, ...['Repro', 'Poulet', 'Poussin'].map((suffixe, i) => entier(`${prefixe}${suffixe}`, L.categories[i]))));
    const departZone = h('div', { id: 'saisie-depart' });
    const alertes = h('div', { id: 'saisie-alertes', class: 'saisie-alertes', role: 'status' });
    const finale = h('b', { id: 'saisie-effectif-final' });
    const taux = h('b', { id: 'saisie-taux' });
    const eclosion = h('b', { id: 'saisie-eclosion' });
    const poidsMoyen = h('b', { id: 'saisie-poids-moyen' });
    const gmq = h('p', { id: 'saisie-gmq', class: 'muted' });
    const venteChamp = h('b', { id: 'saisie-vente' });
    const ventesCat = h('p', { id: 'ventes-par-categorie', class: 'muted' });
    const provende = h('div', { id: 'saisie-provende' });
    const autonomieZone = h('div', { id: 'saisie-autonomie' });
    const etatEnvoi = h('p', { id: 'saisie-etat', class: 'muted', role: 'status' });
    const retour = h('p', { id: 'saisie-retour', role: 'alert', class: 'muted' }, retourInitial);
    const prophyZone = h('div', { id: 'saisie-prophy-zone' });

    function rafraichir() {
        const ctx = lire();
        const c = calculsVolailles(ctx.lot, ctx.fiches, ctx.jour, s, ctx.rations, ctx.autonomie);
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
        eclosion.textContent = c.eclosion === null ? '—' : `${c.eclosion.toFixed(1).replace('.', ',')} %`;
        venteChamp.textContent = String(c.vente);
        ventesCat.textContent = L.ventesCategorie(c.ventes);
        poidsMoyen.textContent = s.peseeTotal && c.effectifFinal > 0 ? `${arrondiPhp(s.peseeTotal / c.effectifFinal, 0)} g` : '—';
        gmq.replaceChildren(...(c.poidsEstime !== null ? [`${L.gmq} `, h('b', {}, `${c.poidsEstime} g / animal`)] : []));
        champs.get('peseeTotal')?.setAttribute('placeholder', c.poidsEstime !== null && c.effectifFinal > 0 ? `~${c.poidsEstime * c.effectifFinal} g (estimé)` : L.peseeExemple);
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
    const c0 = calculsVolailles(ctx0.lot, ctx0.fiches, ctx0.jour, s, ctx0.rations, ctx0.autonomie);
    if (c0.cat.depart_requis) {
        departZone.append(h('div', { class: 'saisie-groupe', id: 'depart-requis' }, h('b', {}, L.departTitre), h('p', { class: 'muted' }, M.departRequis(c0.veille)),
            h('div', { class: 'saisie-trois' }, entier('departRepro', L.categories[0]), entier('departJeune', L.categories[1]), entier('departSevre', L.categories[2])),
            c0.cat.proposition ? h('button', { type: 'button', class: 'btn', id: 'depart-proposition', onclick: () => {
                for (const [prop, k] of [['departRepro', 'repro'], ['departSevre', 'sevre'], ['departJeune', 'jeune']]) { s[prop] = c0.cat.proposition[k]; const el = champs.get(prop); if (el) el.value = String(s[prop]); }
                rafraichir();
            } }, M.proposition(c0.cat.proposition)) : null));
    } else if (c0.cat.depart) {
        departZone.append(h('div', { class: 'saisie-groupe' }, h('b', {}, L.departVerrouille), h('p', { class: 'muted' }, M.departFixe(jourFr(c0.cat.depart_date))),
            h('div', { class: 'saisie-trois' }, ...[['repro', L.categories[0]], ['jeune', L.categories[1]], ['sevre', L.categories[2]]].map(([k, l]) => h('label', { class: 'saisie-champ' }, h('span', { class: 'muted' }, l), h('input', { type: 'number', value: String(c0.cat.depart[k]), disabled: true, class: 'fiche-select' })))),
            c0.cat.mode === 'avant_depart' ? h('p', { class: 'alerte', id: 'avant-depart' }, `Jour antérieur à l'effectif de départ fixé le ${jourFr(c0.cat.depart_date)} : il n'est pas saisissable.`) : null));
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
        h('div', { class: 'saisie-trois' }, entier('achat', L.achat), h('div', { class: 'saisie-champ' }, h('span', { class: 'muted' }, `${L.vente} ${L.venteSuite}`), venteChamp, ventesCat)),
        h('div', { class: 'saisie-groupe' }, h('b', {}, L.couvoir),
            h('div', { class: 'saisie-trois' }, entier('oeufsCouves', L.oeufs), entier('poussinsNes', L.nes), h('div', { class: 'saisie-champ' }, h('span', { class: 'muted' }, L.eclosion), eclosion))),
        groupe(L.morts, 'mort', s.mortEnregistre, M.mortEnregistre),
        groupe(L.dons, 'don', s.donEnregistre, M.donEnregistre),
        h('div', { class: 'saisie-trois' }, entier('passage', L.passage)),
        departZone, alertes,
        h('div', { class: 'saisie-trois' },
            h('div', { class: 'saisie-champ' }, h('span', { class: 'muted' }, L.effectifFinal), finale),
            h('div', { class: 'saisie-champ' }, h('span', { class: 'muted' }, L.taux), taux)),
        provende, autonomieZone,
        h('div', { class: 'saisie-trois' }, entier('peseeTotal', L.pesee), h('div', { class: 'saisie-champ' }, h('span', { class: 'muted' }, `${L.poidsMoyen} ${L.poidsMoyenSuite}`), poidsMoyen)),
        gmq, prophyZone, retour, etatEnvoi, h('div', { class: 'groupe', style: 'justify-content:flex-end' }, bouton));
    if (ctx0.lectureSeule) for (const el of racine.querySelectorAll('input')) el.disabled = true;
    rafraichir();
    return racine;
}
