/**
 * PWA-3 (fiche lapins, É2) — L'ÉCRAN « FICHE DU MOIS » DES LAPINS, EN LECTURE : en-tête, quatre KPI, sélecteurs de bande / date / mois,
 * bandeau de lecture seule d'un exercice clos, transferts du jour, tableau mensuel de 31 jours (et cartes pour les petits écrans).
 *
 * La vue Blade `livewire/elevage/fiche-lapins.blade.php` est le MAÎTRE : libellés, ordre des colonnes et messages sont lus dans le Blade par
 * `tests/Js/fiche-lapins-ecran.test.mjs` (garde de sources). Le MODÈLE (`modeleFiche`) est une transposition de `Livewire\Elevage\FicheLapins`
 * (`kpis`, `bande`, `monthlyEntries`, `daysInMonth`, `traitementsDuJour`, `transfertsDuJour`, `libelleMois`, `estMoisCourant`) et de
 * `ExerciceChoisi` (bandeau de lecture seule) ; son égalité avec le vrai PHP est prouvée par `tests/Js/parite-fiche-ecran.test.mjs`.
 *
 * AUCUNE saisie ici (É3), aucune file d'envoi (É4). Écart assumé avec le web : l'export PDF n'existe pas hors ligne (bouton grisé) ; le tableau
 * mensuel a des cartes sous 640 px (le Blade le masque sous le seuil `lg`) ; le tri des bandes est celui du tirage.
 */

import { arrondiPhp } from './calculs-caisse.js';
import { effectifVeille, jourDe } from './chaine-effectif.js';

export const ESPECE = 'cuniculture';

/** Libellés et ordre du Blade (garde : `fiche-lapins-ecran.test.mjs`). */
export const ECRAN = {
    titre: 'Fiches Lapins - Cuniculture',
    sousTitre: 'Fiche de suivi mensuel du cheptel — transcription fidèle du registre de la ferme.',
    exportPdf: 'Exporter PDF',
    exportPdfHorsLigne: 'Export PDF disponible en ligne seulement.',
    kpis: ['Effectif Total Vivant', 'Géniteurs (M/F)', 'Naissances du Mois', 'Taux de Mortalité'],
    aucuneBande: 'Aucune bande active en cuniculture pour le moment.',
    saisieTitre: 'Saisie Journalière du Cheptel',
    bande: 'Bande :',
    date: 'Date :',
    mois: 'Mois :',
    moisPrecedent: 'Mois précédent',
    moisSuivant: 'Mois suivant',
    transferts: 'Transferts entre bandes ce jour :',
    transfertsSuite: "— compris dans l'effectif final. Ils se modifient depuis l'écran",
    transfertsEcran: 'Transferts entre Bandes',
    // En-têtes du tableau mensuel : groupes (libellé, colspan/rowspan) puis sous-colonnes.
    groupes: [['Date', 'rowspan'], ['Entrées', 2], ['Sorties', 3], ['Effectif Final du Jour', 5], ['Taux Mort %', 'rowspan'], ['Poids Général (g)', 'rowspan'], ['Traitements & Prophylaxie', 'rowspan']],
    sousColonnes: ['Achat', 'Né', 'Mort', 'Vente', 'Don', 'M', 'F', 'Jeunes', 'S/Mères', 'Total'],
    vide: '—',
};

const MOIS = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
const FORMAT_JOUR = /^\d{4}-\d{2}-\d{2}$/;

const dateValide = (d) => {
    if (typeof d !== 'string' || !FORMAT_JOUR.test(d)) return false;
    const [a, m, j] = d.split('-').map(Number);
    const x = new Date(Date.UTC(a, m - 1, j));
    return x.getUTCFullYear() === a && x.getUTCMonth() === m - 1 && x.getUTCDate() === j;
};
const deux = (n) => String(n).padStart(2, '0');
const nbJours = (a, m) => new Date(Date.UTC(a, m, 0)).getUTCDate();
const sommeNum = (liste, f) => liste.reduce((s, x) => s + (Number(f(x)) || 0), 0);

/** Premier jour du mois du jour affiché (`debutMoisFiche`), repli sur le mois d'AUJOURD'HUI si la date est invalide. */
export function debutMois(date, aujourdhui) {
    const j = dateValide(date) ? date : aujourdhui;
    return `${j.slice(0, 7)}-01`;
}

/** `moisPrecedent` : le premier jour du mois précédent. */
export function moisPrecedent(date, aujourdhui) {
    const [a, m] = debutMois(date, aujourdhui).split('-').map(Number);
    return m === 1 ? `${a - 1}-12-01` : `${a}-${deux(m - 1)}-01`;
}

/** `moisSuivant` : `null` sur le mois en cours (pas de mois à venir) ; sinon le premier jour du mois suivant, ou AUJOURD'HUI s'il l'est. */
export function moisSuivant(date, aujourdhui) {
    const debut = debutMois(date, aujourdhui);
    if (debut.slice(0, 7) >= aujourdhui.slice(0, 7)) return null;
    const [a, m] = debut.split('-').map(Number);
    const suivant = m === 12 ? `${a + 1}-01-01` : `${a}-${deux(m + 1)}-01`;
    return suivant.slice(0, 7) === aujourdhui.slice(0, 7) ? aujourdhui : suivant;
}

/** `ExerciceChoisi::exerciceDuJour` : le premier exercice (par début) qui couvre le jour. */
export const exerciceDuJour = (exercices, jour) => [...exercices].sort((a, b) => (String(a.start_date) < String(b.start_date) ? -1 : 1))
    .find((e) => String(e.start_date).slice(0, 10) <= jour && String(e.end_date).slice(0, 10) >= jour) ?? null;

/** `ExerciceChoisi::parDefaut` (l'exercice qui couvre aujourd'hui, sinon le plus récent) — le « choisi » de la PWA, qui n'a pas de session. */
export function exerciceParDefaut(exercices, aujourdhui) {
    return exerciceDuJour(exercices, aujourdhui) ?? [...exercices].sort((a, b) => Number(b.year) - Number(a.year))[0] ?? null;
}

/** `ExerciceChoisi::exerciceDeSaisie` : l'exercice OUVERT qui couvre aujourd'hui, sinon l'ouvert le plus récent. */
export function exerciceDeSaisie(exercices, aujourdhui) {
    const ouverts = exercices.filter((e) => e.status === 'ouvert');
    return ouverts.find((e) => String(e.start_date).slice(0, 10) <= aujourdhui && String(e.end_date).slice(0, 10) >= aujourdhui)
        ?? [...ouverts].sort((a, b) => Number(b.year) - Number(a.year))[0] ?? null;
}

/** Le bandeau de lecture seule du jour choisi (`getBandeauLectureSeuleProperty`), ou `null`. */
export function bandeauLectureSeule(exercices, date, aujourdhui) {
    if (!dateValide(date)) return null;
    const exercice = exerciceDuJour(exercices, date);
    const choisi = exerciceParDefaut(exercices, aujourdhui);
    if (exercice === null || (choisi !== null && choisi.id === exercice.id)) return null;
    if (exercice.status !== 'cloture') return null;
    const saisie = exerciceDeSaisie(exercices, aujourdhui);
    return { texte: `Exercice ${exercice.year} clôturé — lecture seule.${saisie ? ` Les saisies se font dans l'exercice ${saisie.year}.` : ''}`, cible: saisie ? Number(saisie.year) : null };
}

/** Les libellés de traitement d'un jour (`traitementsDuJour`) : soins actifs de la bande ce jour, produit de traitement de la fiche, sinon symptômes. */
export function traitementsDuJour(date, entree, soinsDuJour, produits) {
    const libelles = [];
    const vus = new Set();
    const ajouter = (l) => { if (l !== '' && !vus.has(l)) { vus.add(l); libelles.push(l); } };
    for (const r of soinsDuJour) ajouter(`${r.action_type ?? ''}${r.product_used ? ` (${r.product_used})` : ''}`.trim());
    const produit = entree?.treatment_product_id ? produits.find((p) => p.id === entree.treatment_product_id) : null;
    if (produit?.name) ajouter(produit.name);
    if (libelles.length > 0) return libelles.join(', ');
    return entree?.symptomes || ECRAN.vide;
}

/** Le taux de mortalité d'une fiche (`getMortalityRateAttribute`) : `round(mort / veille × 100, 2)`, 0 si la veille est nulle. */
export function tauxMortaliteFiche(fiche, veille) {
    return veille <= 0 ? 0 : arrondiPhp((Number(fiche.mort) / veille) * 100, 2);
}

/**
 * Le modèle de l'écran.
 *
 * @param {{lots:object[], fiches:object[], soins:object[], produits:object[], exercices:object[]}} donnees  données tirées
 * @param {{bandeId:?string, date:string, aujourdhui:string}} etat  `aujourdhui` : le jour du Bénin (AAAA-MM-JJ)
 */
export function modeleFiche(donnees, { bandeId = null, date, aujourdhui }) {
    const lots = donnees.lots.filter((l) => l.species_code === ESPECE && l.status === 'actif' && l.is_active !== false);
    const bande = (bandeId !== null ? lots.find((l) => l.id === bandeId) : null) ?? lots[0] ?? null;
    const dateChoisie = dateValide(date) ? date : null; // sans date lisible : aucun jour surligné, aucun transfert (comme le composant)
    const dateAffichee = dateChoisie ?? aujourdhui;
    const debut = debutMois(dateAffichee, aujourdhui);
    const [annee, moisNum] = debut.split('-').map(Number);
    const fin = `${debut.slice(0, 7)}-${deux(nbJours(annee, moisNum))}`;
    const dansLeMois = (f) => jourDe(f) >= debut && jourDe(f) <= fin;

    // KPI : toutes les bandes de l'espèce (le mois AFFICHÉ).
    const idsLots = new Set(lots.map((l) => l.id));
    const fichesDesLots = donnees.fiches.filter((f) => idsLots.has(f.lot_id));
    const derniereParLot = lots.map((l) => fichesDesLots.filter((f) => f.lot_id === l.id).sort((a, b) => (jourDe(a) < jourDe(b) ? -1 : 1)).at(-1)).filter(Boolean);
    const moisDesLots = fichesDesLots.filter(dansLeMois);
    const totalMorts = sommeNum(moisDesLots, (e) => e.mort);
    const totalDepart = moisDesLots.reduce((s, e) => s + effectifVeille(donnees.lots.find((l) => l.id === e.lot_id), donnees.fiches.filter((f) => f.lot_id === e.lot_id), jourDe(e), e.id), 0);
    const kpis = {
        effectif_total: sommeNum(lots, (l) => l.current_quantity),
        geniteurs_m: sommeNum(derniereParLot, (e) => e.effectif_m),
        geniteurs_f: sommeNum(derniereParLot, (e) => e.effectif_f),
        naissances_mois: sommeNum(moisDesLots, (e) => e.ne),
        taux_mortalite_mois: totalDepart > 0 ? arrondiPhp((totalMorts / totalDepart) * 100, 1) : 0,
    };

    // Tableau mensuel : LA bande de la fiche.
    const fichesBande = bande ? donnees.fiches.filter((f) => f.lot_id === bande.id) : [];
    const parJour = new Map(fichesBande.filter(dansLeMois).map((f) => [jourDe(f), f]));
    const soinsParJour = new Map();
    if (bande) {
        for (const r of donnees.soins.filter((x) => x.lot_id === bande.id && x.is_active !== false && String(x.record_date).slice(0, 10) >= debut && String(x.record_date).slice(0, 10) <= fin)
            .sort((a, b) => (String(a.created_at ?? '') < String(b.created_at ?? '') ? -1 : 1))) {
            const j = String(r.record_date).slice(0, 10);
            soinsParJour.set(j, [...(soinsParJour.get(j) ?? []), r]);
        }
    }

    const jours = Array.from({ length: nbJours(annee, moisNum) }, (_, k) => {
        const d = `${debut.slice(0, 7)}-${deux(k + 1)}`;
        const f = parJour.get(d) ?? null;
        return {
            date: d,
            jourMois: `${deux(k + 1)}/${deux(moisNum)}`,
            choisi: d === dateChoisie,
            fiche: f === null ? null : {
                achat: f.achat ?? null, ne: f.ne ?? null, mort: f.mort ?? null, vente: f.vente ?? null, don: f.don ?? null,
                effectif_m: f.effectif_m ?? null, effectif_f: f.effectif_f ?? null, effectif_sevres: f.effectif_sevres ?? null, effectif_smeres: f.effectif_smeres ?? null,
                effectif_final: f.effectif_final ?? null,
                taux: arrondiPhp(tauxMortaliteFiche(f, effectifVeille(bande, fichesBande, d, f.id)), 1).toFixed(1),
                tauxPositif: tauxMortaliteFiche(f, effectifVeille(bande, fichesBande, d, f.id)) > 0,
                poids_general_g: f.weight_sample_avg_g && f.effectif_final ? Math.round(Number(f.weight_sample_avg_g) * Number(f.effectif_final)) : null,
            },
            traitements: traitementsDuJour(d, f, soinsParJour.get(d) ?? [], donnees.produits),
        };
    });

    const duJour = dateChoisie === null ? null : fichesBande.find((f) => jourDe(f) === dateChoisie) ?? null;
    const t = (c) => Math.trunc(Number(duJour?.[c] ?? 0)) || 0;

    return {
        lots, bande, dateAffichee, debutMois: debut,
        libelleMois: `${MOIS[moisNum - 1][0].toUpperCase()}${MOIS[moisNum - 1].slice(1)} ${annee}`,
        estMoisCourant: debut.slice(0, 7) >= aujourdhui.slice(0, 7),
        kpis, jours,
        bandeau: bandeauLectureSeule(donnees.exercices, dateAffichee, aujourdhui),
        transferts: { transfert_entree: t('transfert_entree'), transfert_sortie: t('transfert_sortie') },
    };
}

const nombre = (n) => String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
const virgule = (n, d = 1) => Number(n).toFixed(d).replace('.', ',');
const cellule = (v) => (v === null || v === undefined ? ECRAN.vide : String(v));

/** Texte « +N entré(s) ; −N sorti(s) » du composant `transferts-du-jour`, ou `null` sans transfert. */
export function texteTransferts(t) {
    const e = t.transfert_entree > 0; const s = t.transfert_sortie > 0;
    if (!e && !s) return null;
    return `${e ? `+${t.transfert_entree} entré(s)` : ''}${e && s ? ' ; ' : ''}${s ? `−${t.transfert_sortie} sorti(s)` : ''}`;
}

/**
 * Construit le DOM de l'écran (jamais `innerHTML`) ; `h(tag, attrs, ...enfants)` est le constructeur de la page. `actions` : `{choisirBande, choisirDate, moisPrecedent, moisSuivant}`.
 */
export function rendreFiche(m, h, actions) {
    const kpi = (libelle, valeur, icone, couleur) => h('div', { class: `kpi fiche-kpi ${couleur}` }, h('div', { class: 'groupe', style: 'justify-content:space-between' }, h('span', { class: 'kpi-libelle' }, libelle), h('span', { class: 'material-symbols-outlined' }, icone)), h('span', { class: 'kpi-valeur' }, valeur));

    const noeuds = [
        h('div', { class: 'fiche-entete' },
            h('div', {}, h('h2', {}, h('span', { class: 'material-symbols-outlined' }, 'cruelty_free'), ECRAN.titre), h('p', { class: 'muted' }, ECRAN.sousTitre)),
            h('button', { type: 'button', class: 'btn', disabled: true, title: ECRAN.exportPdfHorsLigne, 'data-export-pdf': true }, h('span', { class: 'material-symbols-outlined' }, 'picture_as_pdf'), ECRAN.exportPdf)),
        h('div', { class: 'fiche-kpis' },
            kpi(ECRAN.kpis[0], nombre(m.kpis.effectif_total), 'pets', 'emerald'),
            kpi(ECRAN.kpis[1], `${m.kpis.geniteurs_m} / ${m.kpis.geniteurs_f}`, 'favorite', 'blue'),
            kpi(ECRAN.kpis[2], String(m.kpis.naissances_mois), 'child_care', 'maize'),
            kpi(ECRAN.kpis[3], `${virgule(m.kpis.taux_mortalite_mois)} %`, 'trending_down', 'red')),
    ];

    if (m.lots.length === 0) {
        noeuds.push(h('div', { class: 'carte', style: 'text-align:center' }, h('span', { class: 'material-symbols-outlined', style: 'font-size:44px;color:#9ca3af' }, 'inbox'), h('p', { style: 'font-weight:600;margin:8px 0 0' }, ECRAN.aucuneBande)));
        return noeuds;
    }

    const selecteurs = [];
    if (m.lots.length > 1) {
        const select = h('select', { id: 'fiche-bande', class: 'fiche-select' }, ...m.lots.map((l) => h('option', { value: l.id }, l.code)));
        select.value = m.bande.id;
        select.addEventListener('change', () => actions.choisirBande(select.value));
        selecteurs.push(h('span', { class: 'muted' }, ECRAN.bande), select);
    }
    const champDate = h('input', { type: 'date', id: 'fiche-date', class: 'fiche-select', value: m.dateAffichee });
    champDate.addEventListener('change', () => actions.choisirDate(champDate.value));
    selecteurs.push(h('span', { class: 'muted' }, ECRAN.date), champDate, h('span', { class: 'muted' }, ECRAN.mois),
        h('div', { class: 'groupe', 'data-mois-de-fiche': true, style: 'gap:0;border:1px solid #d1d5db;border-radius:8px;overflow:hidden' },
            h('button', { type: 'button', class: 'btn', title: ECRAN.moisPrecedent, 'aria-label': ECRAN.moisPrecedent, id: 'fiche-mois-precedent', onclick: actions.moisPrecedent }, '‹'),
            h('span', { id: 'fiche-libelle-mois', style: 'padding:0 8px;font-weight:700' }, m.libelleMois),
            h('button', { type: 'button', class: 'btn', title: ECRAN.moisSuivant, 'aria-label': ECRAN.moisSuivant, id: 'fiche-mois-suivant', disabled: m.estMoisCourant, onclick: actions.moisSuivant }, '›')));
    noeuds.push(h('div', { class: 'carte' },
        h('div', { class: 'groupe', style: 'justify-content:space-between;border-bottom:1px solid #e5e7eb;padding-bottom:8px;margin-bottom:12px' },
            h('h3', {}, h('span', { class: 'material-symbols-outlined' }, 'edit_note'), ECRAN.saisieTitre), h('div', { class: 'groupe' }, ...selecteurs)),
        m.bandeau ? h('div', { class: 'bandeau neutre', 'data-bandeau-exercice': true }, h('span', { class: 'material-symbols-outlined' }, 'lock'), h('b', {}, m.bandeau.texte)) : null,
        texteTransferts(m.transferts) ? h('div', { class: 'bandeau neutre', id: 'fiche-transferts', role: 'status' }, h('span', { class: 'material-symbols-outlined' }, 'swap_horiz'), `${ECRAN.transferts} ${texteTransferts(m.transferts)} ${ECRAN.transfertsSuite} ${ECRAN.transfertsEcran}.`) : null));

    // Tableau mensuel : en-têtes sur deux lignes, comme le Blade.
    const groupes = ECRAN.groupes.map(([libelle, taille]) => h('th', taille === 'rowspan' ? { rowspan: 2 } : { colspan: taille }, libelle));
    const sous = ECRAN.sousColonnes.map((libelle) => h('th', {}, libelle));
    const ligne = (j) => {
        const f = j.fiche;
        return h('tr', { 'data-jour': j.date, class: j.choisi ? 'choisi' : '', onclick: () => actions.choisirDate(j.date) },
            h('td', { class: 'sticky' }, j.jourMois),
            h('td', {}, cellule(f?.achat)), h('td', {}, cellule(f?.ne)),
            h('td', { class: (f?.mort ?? 0) > 0 ? 'alerte' : '' }, cellule(f?.mort)),
            h('td', {}, cellule(f?.vente)), h('td', {}, cellule(f?.don)),
            h('td', {}, cellule(f?.effectif_m)), h('td', {}, cellule(f?.effectif_f)), h('td', {}, cellule(f?.effectif_sevres)), h('td', {}, cellule(f?.effectif_smeres)),
            h('td', { class: 'gras' }, cellule(f?.effectif_final)),
            h('td', { class: f?.tauxPositif ? 'alerte' : '' }, f ? f.taux : ECRAN.vide),
            h('td', { class: 'num' }, cellule(f?.poids_general_g)),
            h('td', {}, j.traitements));
    };
    noeuds.push(h('div', { class: 'carte fiche-tableau' },
        h('div', { style: 'overflow-x:auto' }, h('table', { id: 'fiche-mensuel' }, h('thead', {}, h('tr', {}, ...groupes), h('tr', {}, ...sous)), h('tbody', {}, ...m.jours.map(ligne))))));

    // Cartes (petits écrans) : un jour = une carte, mêmes libellés de colonnes.
    const noms = [...ECRAN.sousColonnes];
    noeuds.push(h('div', { class: 'fiche-cartes', id: 'fiche-cartes' }, ...m.jours.map((j) => {
        const f = j.fiche;
        const valeurs = f ? [f.achat, f.ne, f.mort, f.vente, f.don, f.effectif_m, f.effectif_f, f.effectif_sevres, f.effectif_smeres, f.effectif_final] : [];
        return h('div', { class: `fiche-carte${j.choisi ? ' choisi' : ''}`, 'data-jour': j.date, onclick: () => actions.choisirDate(j.date) },
            h('b', {}, j.jourMois),
            h('div', { class: 'fiche-carte-grille' }, ...noms.map((n, i) => h('span', {}, h('small', {}, n), ' ', cellule(valeurs[i])))),
            h('small', {}, `${ECRAN.groupes[4][0]} ${f ? f.taux : ECRAN.vide} · ${ECRAN.groupes[5][0]} ${cellule(f?.poids_general_g)}`),
            h('small', {}, `${ECRAN.groupes[6][0]} : ${j.traitements}`));
    })));
    return noeuds;
}
