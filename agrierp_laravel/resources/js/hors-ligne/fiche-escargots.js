/**
 * PWA-3 (fiche escargots) — LA SAISIE D'UN JOUR de la fiche Escargots / Héliciculture, hors ligne.
 *
 * Les escargots ne partagent PAS la vue commune Lapins / Porcs : pas d'effectif par catégorie calculé, pas de départ ni de passage de stade, pas de
 * rationnement (le Blade dit « sera alimenté … dès sa mise en œuvre »), pas de prophylaxie ni d'autonomie alimentaire au web. Transposition de
 * `Livewire\Elevage\FicheEscargots` : `loadDay` (`chargerJourEscargots`), `getEffectifFinalCalcProperty` & co (`calculsEscargots`) et `saveDay`
 * (`enregistrerJourEscargots`). Les morts et les dons se saisissent par catégorie (Reproducteur (Bordé), Engraissement, Naissain) mais seule leur SOMME
 * est enregistrée (`mort`, `don`) ; une somme déjà enregistrée sans répartition est conservée tant qu'aucune répartition n'est saisie
 * (`mortEnregistre`, `donEnregistre`). Les trois effectifs (Naissains, Engraissement, Bordés) restent SAISIS (colonnes `effectif_m`, `effectif_f`,
 * `effectif_sevres`) ; les œufs pondus sont la colonne `ponte_total`, les naissains nés la colonne `ne`.
 *
 * Le module Héliciculture doit être activé (`modules_config.helico`) : sinon l'écran dit « Module Héliciculture non activé » et la fiche n'offre aucune bande.
 * Parité avec le vrai PHP : `tests/Js/parite-fiche-escargots.test.mjs` ; phrases et libellés : `tests/Js/fiche-escargots.test.mjs`.
 */

import { computeEffectifFinal, effectifVeille, jourDe, recalculerEnCascade } from './chaine-effectif.js';
import { arrondiPhp } from './calculs-caisse.js';

export const ESPECE_ESCARGOTS = 'helico';

const n = (v) => Math.trunc(Number(v ?? 0)) || 0;
const nonNul = (v) => v !== null && v !== undefined;
const jours = (a, b) => Math.round((Date.UTC(+b.slice(0, 4), +b.slice(5, 7) - 1, +b.slice(8, 10)) - Date.UTC(+a.slice(0, 4), +a.slice(5, 7) - 1, +a.slice(8, 10))) / 86400000);

export const MOTIFS_ESCARGOTS = {
    aucuneBande: "Aucune bande active en héliciculture. Créez d'abord une bande.",
    moduleTitre: 'Module Héliciculture non activé',
    moduleTexte: "Ce module est disponible mais désactivé par défaut. Un administrateur peut l'activer depuis Paramètres > Modules Actifs.",
    mortEnregistre: (m) => `${m} mort(s) déjà enregistré(s) ce jour, sans répartition par catégorie : ils sont conservés tant qu'aucune répartition n'est saisie ci-dessous.`,
    donEnregistre: (d) => `${d} don(s) déjà enregistré(s) ce jour, sans répartition par catégorie : ils sont conservés tant qu'aucune répartition n'est saisie ci-dessous.`,
    rationnement: 'Le calcul du rationnement sera alimenté en données réelles dès sa mise en œuvre.',
    rationnementPrevu: "Prévu : qu'un barème officiel soit fourni pour l'héliciculture (absent de FeedRationStandards, ticket 2.7)",
    hygrometrie: 'Le suivi hygrométrique sera alimenté en données réelles dès sa mise en œuvre.',
    hygrometriePrevu: "Prévu : à planifier — aucune table de mesures d'hygrométrie n'existe encore ; le ticket 3.11 (soins vétérinaires) ne la fournit pas",
};

export const LIBELLES_ESCARGOTS = {
    achat: 'Achats du jour', vente: 'Ventes', venteSuite: '(POS, réel)',
    ponte: 'Workflow Ponte en Terre & Éclosion des Naissains', oeufs: 'Œufs Pondus (en terre)', naissains: 'Naissains Nés (Éclosion)', eclosion: "Taux d'Éclosion Naissains (%)",
    morts: 'Morts par catégorie', dons: 'Dons par catégorie', categories: ['Reproducteur (Bordé)', 'Engraissement', 'Naissain'],
    effectifs: ['Naissains', 'Engraissement', 'Bordés'],
    effectifFinal: 'Effectif Final du Jour', taux: 'Taux de Mortalité du Jour (%)',
    rationnementTitre: 'Rationnement Farine Calcique & Fourrage',
    pesee: 'Poids Général Pesé (g)', peseeExemple: 'ex : 4500', poidsMoyen: 'Poids Moyen Constaté', poidsMoyenSuite: '(Poids Général ÷ Effectif Final)',
    gmq: 'Poids moyen estimé (GMQ) :',
    entretien: 'Entretien & Hygrométrie', observations: 'Observations', observationsExemple: 'ex : RAS',
    enregistrer: 'Enregistrer ce Jour',
};

export const saisieVideEscargots = () => ({
    achat: 0, oeufsTerre: 0, naissainsNes: 0, mortBorde: 0, mortEngraissement: 0, mortNaissain: 0, donBorde: 0, donEngraissement: 0, donNaissain: 0,
    mortEnregistre: null, donEnregistre: null, effectifNaissains: 0, effectifEngraissement: 0, effectifBordes: 0, peseeTotal: null,
});

/** `loadDay` : le jour tel que le web l'ouvre (zéros sans fiche ; morts et dons déjà enregistrés signalés, la répartition repart à zéro). */
export function chargerJourEscargots(lot, fiches, jour) {
    const s = saisieVideEscargots();
    const f = lot ? fiches.find((x) => x.lot_id === lot.id && jourDe(x) === jour) : null;
    if (!f) return s;
    s.mortEnregistre = n(f.mort) > 0 ? n(f.mort) : null;
    s.donEnregistre = n(f.don) > 0 ? n(f.don) : null;
    s.achat = n(f.achat); s.oeufsTerre = n(f.ponte_total); s.naissainsNes = n(f.ne);
    s.effectifNaissains = n(f.effectif_m); s.effectifEngraissement = n(f.effectif_f); s.effectifBordes = n(f.effectif_sevres);
    const final = n(f.effectif_final);
    s.peseeTotal = f.weight_sample_avg_g && final > 0 ? Math.round(Number(f.weight_sample_avg_g) * final) : null;
    return s;
}

/** `mortDuJour` / `donDuJour` : la répartition saisie si elle n'est pas vide, sinon le total déjà enregistré. */
export const mortDuJour = (s) => { const x = n(s.mortBorde) + n(s.mortEngraissement) + n(s.mortNaissain); return x > 0 ? x : n(s.mortEnregistre); };
export const donDuJour = (s) => { const x = n(s.donBorde) + n(s.donEngraissement) + n(s.donNaissain); return x > 0 ? x : n(s.donEnregistre); };

/** `getPoidsMoyenEstimeProperty` (GMQ entre la première et la dernière pesée antérieure), `null` sans pesée ou avec une pesée saisie. */
export function poidsEstimeEscargots(lot, fiches, jour, s) {
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

/** Tout ce que l'écran calcule : veille, vente, effectif final, taux de mortalité, taux d'éclosion (`null` sans œufs), poids estimé. */
export function calculsEscargots(lot, fiches, jour, s) {
    const sortie = { veille: 0, vente: 0, effectifFinal: 0, taux: 0, eclosion: null, poidsEstime: null };
    if (!lot) return sortie;
    const duLot = fiches.filter((f) => f.lot_id === lot.id);
    const duJour = duLot.find((f) => jourDe(f) === jour) ?? null;
    sortie.veille = effectifVeille(lot, duLot, jour);
    sortie.vente = n(duJour?.vente);
    const mort = mortDuJour(s);
    sortie.effectifFinal = computeEffectifFinal(sortie.veille, n(s.achat), n(s.naissainsNes), mort, sortie.vente, donDuJour(s), n(duJour?.transfert_entree), n(duJour?.transfert_sortie));
    sortie.taux = sortie.veille > 0 ? arrondiPhp((mort / sortie.veille) * 100, 1) : 0;
    sortie.eclosion = n(s.oeufsTerre) > 0 ? arrondiPhp((n(s.naissainsNes) / n(s.oeufsTerre)) * 100, 1) : null;
    sortie.poidsEstime = poidsEstimeEscargots(lot, fiches, jour, s);
    return sortie;
}

/**
 * `saveDay` : seuls refus — droit, aucune bande, exercice clos (aucune écriture) ; puis la fiche (mise à jour ou création, colonnes de répartition
 * des morts et des dons NON touchées) et la cascade de l'effectif des jours suivants. `ctx` : `{exercices, idFiche, role, refusExercice, droit, roles}`.
 */
export function enregistrerJourEscargots(lot, fiches, jour, s, ctx = {}) {
    if (ctx.role !== undefined && ctx.role !== null && !(ctx.roles ?? ['admin', 'animalier']).includes(ctx.role)) return { refus: ctx.droit };
    if (!lot) return { refus: MOTIFS_ESCARGOTS.aucuneBande };
    const clos = ctx.refusExercice ? ctx.refusExercice(ctx.exercices ?? [], jour) : null;
    if (clos) return { refus: clos };
    const c = calculsEscargots(lot, fiches, jour, s);
    const donnees = {
        achat: n(s.achat), ne: n(s.naissainsNes), mort: mortDuJour(s), vente: c.vente, don: donDuJour(s), effectif_final: c.effectifFinal,
        ponte_total: n(s.oeufsTerre), effectif_m: n(s.effectifNaissains), effectif_f: n(s.effectifEngraissement), effectif_sevres: n(s.effectifBordes),
        weight_sample_avg_g: s.peseeTotal && c.effectifFinal > 0 ? arrondiPhp(n(s.peseeTotal) / c.effectifFinal, 0) : null,
    };
    const existante = fiches.find((f) => f.lot_id === lot.id && jourDe(f) === jour);
    const fiche = { ...(existante ?? { id: ctx.idFiche ?? globalThis.crypto.randomUUID(), lot_id: lot.id, entry_date: jour }), ...donnees, sync_status: 'pending' };
    const avec = existante ? fiches.map((f) => (f === existante ? fiche : f)) : [...fiches, fiche];
    const cascade = recalculerEnCascade(lot, avec.filter((f) => f.lot_id === lot.id), jour);
    return { refus: null, fiche, lot: cascade.lot, fiches: [...avec.filter((f) => f.lot_id !== lot.id), ...cascade.fiches] };
}

// ------------------------------------------------------------------------------------------------------------ formulaire

/** Le formulaire (DOM, jamais `innerHTML`). Mêmes `lire()` et `actions` que celui des lapins et des porcs (sans protocole, ration ni autonomie). */
export function rendreFormulaireEscargots(h, { s, lire, actions, retourInitial = null, messages }) {
    const L = LIBELLES_ESCARGOTS;
    const M = MOTIFS_ESCARGOTS;
    const champs = new Map();
    const entier = (cle, libelle) => {
        const input = h('input', { type: 'number', min: '0', id: `saisie-${cle}`, class: 'fiche-select', value: String(s[cle] ?? '') });
        input.addEventListener('input', () => { s[cle] = input.value === '' ? (cle === 'peseeTotal' ? null : 0) : Math.max(0, Math.trunc(Number(input.value)) || 0); rafraichir(); });
        champs.set(cle, input);
        return h('label', { class: 'saisie-champ' }, h('span', { class: 'muted' }, libelle), input);
    };
    const groupe = (titre, prefixe, enregistre, message) => h('div', { class: 'saisie-groupe' }, h('b', {}, titre),
        enregistre !== null && enregistre !== undefined ? h('p', { class: 'bandeau avert', role: 'status', style: 'margin:0' }, message(enregistre)) : null,
        h('div', { class: 'saisie-trois' }, ...['Borde', 'Engraissement', 'Naissain'].map((suffixe, i) => entier(`${prefixe}${suffixe}`, L.categories[i]))));
    const attente = (titre, texte, prevu) => h('div', { class: 'saisie-groupe' }, h('b', {}, titre), h('p', { class: 'muted' }, texte), h('p', { class: 'muted' }, prevu));
    const finale = h('b', { id: 'saisie-effectif-final' });
    const taux = h('b', { id: 'saisie-taux' });
    const eclosion = h('b', { id: 'saisie-eclosion' });
    const poidsMoyen = h('b', { id: 'saisie-poids-moyen' });
    const gmq = h('p', { id: 'saisie-gmq', class: 'muted' });
    const venteChamp = h('b', { id: 'saisie-vente' });
    const etatEnvoi = h('p', { id: 'saisie-etat', class: 'muted', role: 'status' });
    const retour = h('p', { id: 'saisie-retour', role: 'alert', class: 'muted' }, retourInitial);

    function rafraichir() {
        const ctx = lire();
        const c = calculsEscargots(ctx.lot, ctx.fiches, ctx.jour, s);
        finale.textContent = String(c.effectifFinal);
        taux.textContent = `${c.taux.toFixed(1).replace('.', ',')} %`;
        eclosion.textContent = c.eclosion === null ? '—' : `${c.eclosion.toFixed(1).replace('.', ',')} %`;
        poidsMoyen.textContent = s.peseeTotal && c.effectifFinal > 0 ? `${arrondiPhp(s.peseeTotal / c.effectifFinal, 0)} g` : '—';
        venteChamp.textContent = String(c.vente);
        gmq.replaceChildren(...(c.poidsEstime !== null ? [`${L.gmq} `, h('b', {}, `${c.poidsEstime} g / animal`)] : []));
        champs.get('peseeTotal')?.setAttribute('placeholder', c.poidsEstime !== null && c.effectifFinal > 0 ? `~${c.poidsEstime * c.effectifFinal} g (estimé)` : L.peseeExemple);
        etatEnvoi.textContent = ctx.enAttente ? messages.enAttente : '';
    }

    const ctx0 = lire();
    const conflit = ctx0.conflit
        ? h('div', { class: 'bandeau refus', id: 'saisie-conflit', role: 'alert', style: 'margin:0' }, `Fiche refusée par le serveur : ${ctx0.conflit} `,
            h('button', { type: 'button', class: 'btn', id: 'saisie-renvoyer', onclick: () => actions.renvoyer() }, 'Renvoyer'),
            h('button', { type: 'button', class: 'btn danger', id: 'saisie-abandonner', onclick: () => actions.abandonner() }, 'Abandonner cette saisie'))
        : null;
    const observations = h('input', { type: 'text', id: 'saisie-observations', class: 'fiche-select', style: 'width:100%', placeholder: L.observationsExemple, disabled: Boolean(ctx0.lectureSeule) });
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
        h('div', { class: 'saisie-trois' }, entier('achat', L.achat), h('div', { class: 'saisie-champ' }, h('span', { class: 'muted' }, `${L.vente} ${L.venteSuite}`), venteChamp)),
        h('div', { class: 'saisie-groupe' }, h('b', {}, L.ponte),
            h('div', { class: 'saisie-trois' }, entier('oeufsTerre', L.oeufs), entier('naissainsNes', L.naissains), h('div', { class: 'saisie-champ' }, h('span', { class: 'muted' }, L.eclosion), eclosion))),
        groupe(L.morts, 'mort', s.mortEnregistre, M.mortEnregistre),
        groupe(L.dons, 'don', s.donEnregistre, M.donEnregistre),
        h('div', { class: 'saisie-trois' }, entier('effectifNaissains', L.effectifs[0]), entier('effectifEngraissement', L.effectifs[1]), entier('effectifBordes', L.effectifs[2])),
        h('div', { class: 'saisie-trois' },
            h('div', { class: 'saisie-champ' }, h('span', { class: 'muted' }, L.effectifFinal), finale),
            h('div', { class: 'saisie-champ' }, h('span', { class: 'muted' }, L.taux), taux)),
        attente(L.rationnementTitre, M.rationnement, M.rationnementPrevu),
        h('div', { class: 'saisie-trois' }, entier('peseeTotal', L.pesee),
            h('div', { class: 'saisie-champ' }, h('span', { class: 'muted' }, `${L.poidsMoyen} ${L.poidsMoyenSuite}`), poidsMoyen)),
        gmq,
        attente(L.entretien, M.hygrometrie, M.hygrometriePrevu),
        h('label', { class: 'saisie-champ' }, h('span', { class: 'muted' }, L.observations), observations),
        retour, etatEnvoi, h('div', { class: 'groupe', style: 'justify-content:flex-end' }, bouton));
    if (ctx0.lectureSeule) for (const el of racine.querySelectorAll('input')) el.disabled = true;
    rafraichir();
    return racine;
}
