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
import { ECRAN_COMMUN, LAPINS_F, FAMILLE_PAR_DEFAUT } from './fiche-familles.js';

export const ESPECE = 'cuniculture';

/** Libellés et ordre du Blade (garde : `fiche-lapins-ecran.test.mjs`). */
/** Libellés de l'écran des lapins (communs + propres aux lapins), lus dans le Blade par la garde de sources. */
export const MODULE_DESACTIVE = { titre: 'Module Héliciculture non activé', texte: "Ce module est disponible mais désactivé par défaut. Un administrateur peut l'activer depuis Paramètres > Modules Actifs." };
export const ECRAN = { ...ECRAN_COMMUN, ...LAPINS_F.ecran };

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
export function modeleFiche(donnees, { bandeId = null, date, aujourdhui, famille = FAMILLE_PAR_DEFAUT }) {
    // Escargots : sans le module `helico` activé (`modules_config`), aucune bande (`FicheEscargots::getLotsProperty`).
    const moduleDesactive = Boolean(famille.module) && !(donnees.modules ?? []).some((x) => x.species_code === famille.module && x.is_enabled);
    const lots = moduleDesactive ? [] : donnees.lots.filter((l) => (famille.accepte ? famille.accepte(l) : l.species_code === famille.espece) && l.status === 'actif' && l.is_active !== false);
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
    const taux = totalDepart > 0 ? arrondiPhp((totalMorts / totalDepart) * 100, 1) : 0;
    const totalOeufs = sommeNum(moisDesLots, (e) => e.ponte_total);
    const naissains = sommeNum(moisDesLots, (e) => e.ne);
    const totalCouves = totalOeufs;
    const kpis = famille.id === 'reproducteurs'
        ? { effectif_total: sommeNum(lots, (l) => l.current_quantity), taux_eclosion: totalCouves > 0 ? arrondiPhp((naissains / totalCouves) * 100, 1) : null, poussins_nes: naissains, taux_mortalite_mois: taux }
        : famille.id === 'escargots'
        ? { effectif_total: sommeNum(lots, (l) => l.current_quantity), naissains_mois: naissains, taux_eclosion: totalOeufs > 0 ? arrondiPhp((naissains / totalOeufs) * 100, 1) : null, taux_mortalite_mois: taux }
        : famille.id === 'porcs'
        ? { effectif_total: sommeNum(lots, (l) => l.current_quantity), truies: sommeNum(derniereParLot, (e) => e.effectif_f), verrats: sommeNum(derniereParLot, (e) => e.effectif_m), porcelets_sous_mere: sommeNum(derniereParLot, (e) => e.effectif_sevres), taux_mortalite_mois: taux }
        : { effectif_total: sommeNum(lots, (l) => l.current_quantity), geniteurs_m: sommeNum(derniereParLot, (e) => e.effectif_m), geniteurs_f: sommeNum(derniereParLot, (e) => e.effectif_f), naissances_mois: sommeNum(moisDesLots, (e) => e.ne), taux_mortalite_mois: taux };

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
                // Lapins : grammes entiers (`poids_general_g`) ; porcs : Kg à une décimale (`round(avg × final / 1000, 1)` du Blade).
                poids_general_g: f.weight_sample_avg_g && f.effectif_final
                    ? (famille.kg ? arrondiPhp((Number(f.weight_sample_avg_g) * Number(f.effectif_final)) / 1000, 1) : Math.round(Number(f.weight_sample_avg_g) * Number(f.effectif_final)))
                    : null,
            },
            traitements: traitementsDuJour(d, f, soinsParJour.get(d) ?? [], donnees.produits),
        };
    });

    const duJour = dateChoisie === null ? null : fichesBande.find((f) => jourDe(f) === dateChoisie) ?? null;
    const t = (c) => Math.trunc(Number(duJour?.[c] ?? 0)) || 0;

    return {
        famille, moduleDesactive, lots, bande, dateAffichee, debutMois: debut,
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
    const F = m.famille;
    const E = { ...ECRAN_COMMUN, ...F.ecran };
    const kpi = (libelle, valeur, icone, couleur, legende = null) => h('div', { class: `kpi fiche-kpi ${couleur}` }, h('div', { class: 'groupe', style: 'justify-content:space-between' }, h('span', { class: 'kpi-libelle' }, libelle), h('span', { class: 'material-symbols-outlined' }, icone)), h('span', { class: 'kpi-valeur' }, valeur), legende ? h('small', { class: 'muted' }, legende) : null);

    if (m.moduleDesactive) {
        return [h('div', { class: 'carte', id: 'fiche-module-desactive', style: 'text-align:center' }, h('span', { class: 'material-symbols-outlined', style: 'font-size:56px;color:#9ca3af' }, 'lock'), h('h2', {}, MODULE_DESACTIVE.titre), h('p', { class: 'muted' }, MODULE_DESACTIVE.texte))];
    }
    const noeuds = [
        h('div', { class: 'fiche-entete' },
            h('div', {}, h('h2', {}, h('span', { class: 'material-symbols-outlined' }, F.icone), E.titre), h('p', { class: 'muted' }, E.sousTitre)),
            h('button', { type: 'button', class: 'btn', disabled: true, title: E.exportPdfHorsLigne, 'data-export-pdf': true }, h('span', { class: 'material-symbols-outlined' }, 'picture_as_pdf'), E.exportPdf)),
        h('div', { class: 'fiche-kpis' },
            ...F.kpiValeurs(m.kpis).map((v, i) => kpi(E.kpis[i], v, E.kpiIcones[i], ['emerald', 'blue', 'maize', 'red'][i], E.kpiLegendes?.[i] ?? null)),
            ),
    ];

    if (m.lots.length === 0) {
        noeuds.push(h('div', { class: 'carte', style: 'text-align:center' }, h('span', { class: 'material-symbols-outlined', style: 'font-size:44px;color:#9ca3af' }, 'inbox'), h('p', { style: 'font-weight:600;margin:8px 0 0' }, E.aucuneBande)));
        return noeuds;
    }

    const selecteurs = [];
    if (m.lots.length > 1 || E.bandeToujours) {
        const select = h('select', { id: 'fiche-bande', class: 'fiche-select' }, ...m.lots.map((l) => h('option', { value: l.id }, E.bandeToujours ? `${l.code} (${F.libelleStade(l.stage)} — ${l.current_quantity} têtes)` : l.code)));
        select.value = m.bande.id;
        select.addEventListener('change', () => actions.choisirBande(select.value));
        selecteurs.push(h('span', { class: 'muted' }, E.bandeLabel ?? E.bande), select);
    }
    const champDate = h('input', { type: 'date', id: 'fiche-date', class: 'fiche-select', value: m.dateAffichee });
    champDate.addEventListener('change', () => actions.choisirDate(champDate.value));
    selecteurs.push(h('span', { class: 'muted' }, E.date), champDate, h('span', { class: 'muted' }, E.mois),
        h('div', { class: 'groupe', 'data-mois-de-fiche': true, style: 'gap:0;border:1px solid #d1d5db;border-radius:8px;overflow:hidden' },
            h('button', { type: 'button', class: 'btn', title: E.moisPrecedent, 'aria-label': E.moisPrecedent, id: 'fiche-mois-precedent', onclick: actions.moisPrecedent }, '‹'),
            h('span', { id: 'fiche-libelle-mois', style: 'padding:0 8px;font-weight:700' }, m.libelleMois),
            h('button', { type: 'button', class: 'btn', title: E.moisSuivant, 'aria-label': E.moisSuivant, id: 'fiche-mois-suivant', disabled: m.estMoisCourant, onclick: actions.moisSuivant }, '›')));
    noeuds.push(h('div', { class: 'carte' },
        h('div', { class: 'groupe', style: 'justify-content:space-between;border-bottom:1px solid #e5e7eb;padding-bottom:8px;margin-bottom:12px' },
            h('h3', {}, h('span', { class: 'material-symbols-outlined' }, 'edit_note'), E.saisieTitre), h('div', { class: 'groupe' }, ...selecteurs)),
        m.bandeau ? h('div', { class: 'bandeau neutre', 'data-bandeau-exercice': true }, h('span', { class: 'material-symbols-outlined' }, 'lock'), h('b', {}, m.bandeau.texte)) : null,
        texteTransferts(m.transferts) ? h('div', { class: 'bandeau neutre', id: 'fiche-transferts', role: 'status' }, h('span', { class: 'material-symbols-outlined' }, 'swap_horiz'), `${E.transferts} ${texteTransferts(m.transferts)} ${E.transfertsSuite} ${E.transfertsEcran}.`) : null,
        actions.formulaire ? actions.formulaire() : null));

    // Tableau mensuel : en-têtes sur deux lignes, comme le Blade.
    const groupes = E.groupes.map(([libelle, taille]) => h('th', taille === 'rowspan' ? { rowspan: 2 } : { colspan: taille }, libelle));
    const sous = E.sousColonnes.map((libelle) => h('th', {}, libelle));
    const ligne = (j) => {
        const f = j.fiche;
        if (E.cellules) {
            // Famille à tableau propre (reproducteurs) : les cellules suivent l'ordre du Blade.
            const valeur = (champ) => (champ === 'taux' ? (f ? f.taux : E.vide) : cellule(f?.[champ]));
            const classe = (style) => (style === 'alerte' ? ((f?.mort ?? 0) > 0 ? 'alerte' : '') : style === 'tauxAlerte' ? (f?.tauxPositif ? 'alerte' : '') : style ?? '');
            return h('tr', { 'data-jour': j.date, class: j.choisi ? 'choisi' : '', onclick: () => actions.choisirDate(j.date) },
                h('td', { class: 'sticky' }, j.jourMois), ...E.cellules.map(([champ, style]) => h('td', { class: classe(style) }, valeur(champ))));
        }
        return h('tr', { 'data-jour': j.date, class: j.choisi ? 'choisi' : '', onclick: () => actions.choisirDate(j.date) },
            h('td', { class: 'sticky' }, j.jourMois),
            h('td', {}, cellule(f?.achat)), h('td', {}, cellule(f?.ne)),
            h('td', { class: (f?.mort ?? 0) > 0 ? 'alerte' : '' }, cellule(f?.mort)),
            h('td', {}, cellule(f?.vente)), h('td', {}, cellule(f?.don)),
            ...E.colonnesEffectif.map((c) => h('td', {}, cellule(f?.[c]))),
            h('td', { class: 'gras' }, cellule(f?.effectif_final)),
            h('td', { class: f?.tauxPositif ? 'alerte' : '' }, f ? f.taux : E.vide),
            h('td', { class: 'num' }, cellule(f?.poids_general_g)),
            h('td', {}, j.traitements));
    };
    noeuds.push(h('div', { class: 'carte fiche-tableau' },
        h('div', { style: 'overflow-x:auto' }, h('table', { id: 'fiche-mensuel' }, h('thead', {}, h('tr', {}, ...groupes), h('tr', {}, ...sous)), h('tbody', {}, ...m.jours.map(ligne)))),
        E.note ? h('p', { class: 'muted', id: 'fiche-note' }, E.note) : null));

    // Cartes (petits écrans) : un jour = une carte, mêmes libellés de colonnes.
    const noms = E.cartes ? [...E.cartes] : [...E.sousColonnes];
    noeuds.push(h('div', { class: 'fiche-cartes', id: 'fiche-cartes' }, ...m.jours.map((j) => {
        const f = j.fiche;
        if (E.cellules) {
            return h('div', { class: `fiche-carte${j.choisi ? ' choisi' : ''}`, 'data-jour': j.date, onclick: () => actions.choisirDate(j.date) },
                h('b', {}, j.jourMois),
                h('div', { class: 'fiche-carte-grille' }, ...E.cellules.map(([champ], i) => h('span', {}, h('small', {}, noms[i]), ' ', champ === 'taux' ? (f ? f.taux : E.vide) : cellule(f?.[champ])))));
        }
        const valeurs = f ? [f.achat, f.ne, f.mort, f.vente, f.don, ...E.colonnesEffectif.map((c) => f[c]), f.effectif_final] : [];
        return h('div', { class: `fiche-carte${j.choisi ? ' choisi' : ''}`, 'data-jour': j.date, onclick: () => actions.choisirDate(j.date) },
            h('b', {}, j.jourMois),
            h('div', { class: 'fiche-carte-grille' }, ...noms.map((n, i) => h('span', {}, h('small', {}, n), ' ', cellule(valeurs[i])))),
            h('small', {}, `${E.groupes[4][0]} ${f ? f.taux : E.vide} · ${E.groupes[5][0]} ${cellule(f?.poids_general_g)}`),
            h('small', {}, `${E.groupes[6][0]} : ${j.traitements}`));
    })));
    return noeuds;
}
