/**
 * PWA-3 (fiche lapins) — LA PROPHYLAXIE DU JOUR, validable hors ligne.
 *
 * Transposition de `ProtocoleDuJourService` (jour de cycle, calendaires non évalués, traitements dus), de `ValidateProphylaxisTreatmentsAction`
 * (un soin par traitement coché, avec sa rémanence) et de `AvecProphylaxieDuJour::validerTraitements` (refus et messages). Le rendu reprend
 * `components/prophylaxie-du-jour.blade.php`. La validation est une saisie `pending` chiffrée (`soins_a_envoyer`, un soin par traitement, UUID
 * du navigateur) envoyée comme le poste Flutter (`_soinEnJson`, clé `veterinary_records` : le serveur crée lui-même la période de rémanence) ;
 * en attendant, le soin et la rémanence sont rejoués sur la copie tirée : une bande sous rémanence n'est plus vendable hors ligne non plus.
 * Parité avec le vrai PHP : `tests/Js/parite-prophylaxie.test.mjs` ; phrases et libellés : `tests/Js/fiche-lapins-prophylaxie.test.mjs`.
 */

import { chiffrer, dechiffrer } from './coffre.js';
import { META_AUTRES_EN_ATTENTE } from './base-locale.js';

export const TABLE_SOINS_A_ENVOYER = 'soins_a_envoyer';
export const ESPECE = 'cuniculture';
/** Espèce du barème et des bandes ; `cuniculture` par défaut (lapins), `porciculture` pour les porcs. */

export const LIBELLES = {
    titre: 'Traitements & Prophylaxie',
    jour: (n) => `Jour ${n} du cycle de la bande`,
    jourInconnu: 'Jour de cycle inconnu',
    nonCalculable: (motif) => `Protocole non calculable — ${motif} Consultez le registre avant toute administration.`,
    aucun: '— Aucun traitement récurrent programmé pour ce jour —',
    remanence: (n) => `Rémanence ${n}j`,
    calendaires: (n) => `${n} entrée(s) du protocole sans jour de cycle (calendaires, ex. « Le 1er du mois ») ne sont pas évaluées ici.`,
    blocage: "Valider un traitement rémanent bloque la vente de cette bande jusqu'à la fin du délai d'attente.",
    valider: "Valider l'Administration de tous ces Traitements Aujourd'hui",
    indice: (n) => `Indice Rouge : ${n} soin(s) en attente`,
    observations: 'Observations / Notes Additionnelles',
    observationsExemple: "ex : RAS, légère perte d'appétit cage C3...",
    etats: { indetermine: 'Indéterminé', libre: 'Libre', valide: 'Validé / Effectué', prevus: (n) => `${n} Prévu(s)` },
};

export const MOTIFS = {
    aucuneBande: 'Aucune bande active : aucun traitement à valider.',
    jourAVenir: 'Un traitement ne peut pas être validé pour un jour à venir.',
    rien: 'Aucun traitement à enregistrer (déjà validés, ou non prévus ce jour-là).',
    enregistres: (n) => `${n} traitement(s) enregistré(s) au registre vétérinaire.`,
    reproduction: "Bande en reproduction : le cycle se compte depuis la dernière saillie, et aucune saillie n'est enregistrée pour cette bande.",
    miseEnLot: 'Date de mise en lot inconnue : le jour du cycle ne peut pas être calculé.',
    droit: "Votre profil ne permet pas de valider un traitement : lecture seule.",
};

const j10 = (d) => String(d).slice(0, 10);
const jours = (a, b) => Math.round((Date.UTC(+b.slice(0, 4), +b.slice(5, 7) - 1, +b.slice(8, 10)) - Date.UTC(+a.slice(0, 4), +a.slice(5, 7) - 1, +a.slice(8, 10))) / 86400000);
const ajouterJours = (d, n) => { const x = new Date(Date.UTC(+d.slice(0, 4), +d.slice(5, 7) - 1, +d.slice(8, 10) + n)); return `${x.getUTCFullYear()}-${String(x.getUTCMonth() + 1).padStart(2, '0')}-${String(x.getUTCDate()).padStart(2, '0')}`; };
const parCleTexte = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
const actifs = (standards, espece = ESPECE) => standards.filter((s) => s.species_code === espece && s.is_active !== false);

/** `ProtocoleDuJourService::dateDeReference` puis `jourDeCycle` : le jour du cycle (1 le jour de référence), `null` si la référence est inconnue. */
export function jourDeCycle(lot, evenements, jour) {
    const reference = lot.stage === 'reproduction'
        ? evenements.filter((e) => e.lot_id === lot.id && e.saillie_date).map((e) => j10(e.saillie_date)).sort().at(-1) ?? null
        : (lot.created_date ? j10(lot.created_date) : null);
    return reference ? jours(reference, jour) + 1 : null;
}

export const motifIndetermine = (lot) => (lot.stage === 'reproduction' ? MOTIFS.reproduction : MOTIFS.miseEnLot);

/** `ProtocoleDuJourService::pourBande`. `soins` : les soins connus (tirés et en attente) ; `deja_administre` = un soin actif du jour porte ce traitement. */
export function protocoleDuJour({ lot, evenements, standards, soins, jour, espece = ESPECE }) {
    const cycle = jourDeCycle(lot, evenements, jour);
    const faits = new Set(soins.filter((s) => s.lot_id === lot.id && s.is_active !== false && j10(s.record_date) === jour).map((s) => s.action_type));
    const pool = actifs(standards, espece).filter((s) => s.cycle_day_start !== null && s.cycle_day_start !== undefined);
    const ordre = (l) => l.sort((a, b) => Number(a.cycle_day_start) - Number(b.cycle_day_start) || parCleTexte(a.treatment, b.treatment));
    const dus = cycle === null ? ordre([...pool]) : ordre(pool.filter((s) => Number(s.cycle_day_start) <= cycle && Number(s.cycle_day_end) >= cycle));
    return {
        traitements: dus.map((standard) => ({ standard, deja_administre: faits.has(standard.treatment) })),
        jourDeCycle: cycle,
        motifIndetermine: cycle === null ? motifIndetermine(lot) : null,
        calendairesNonEvalues: actifs(standards, espece).filter((s) => s.cycle_day_start === null || s.cycle_day_start === undefined).length,
    };
}

export const determinable = (p) => p.jourDeCycle !== null;
export const enAttente = (p) => p.traitements.filter((t) => !t.deja_administre).length;
/** `ProtocoleDuJour::etat`. */
export function etatProtocole(p) {
    if (!determinable(p)) return LIBELLES.etats.indetermine;
    if (p.traitements.length === 0) return LIBELLES.etats.libre;
    return enAttente(p) === 0 ? LIBELLES.etats.valide : LIBELLES.etats.prevus(p.traitements.length);
}

/**
 * `validerTraitements` : refus et messages du web, puis un soin par traitement coché non encore administré (`ValidateProphylaxisTreatmentsAction`).
 * Aucune écriture si un refus. Les soins rendus portent la rémanence (`withdrawal_days`) que le serveur transformera en période.
 */
export function validerTraitements({ lot, evenements, standards, soins, jour, aujourdhui, espece = ESPECE, idsCoches, observations = null, nouvelId = () => globalThis.crypto.randomUUID(), role = null, rolesEcriture = ['admin', 'animalier'] }) {
    if (role !== null && !rolesEcriture.includes(role)) return { refus: MOTIFS.droit };
    if (!lot) return { refus: MOTIFS.aucuneBande };
    if (jour > aujourdhui) return { refus: MOTIFS.jourAVenir };
    const p = protocoleDuJour({ lot, evenements, standards, soins, jour, espece });
    const notes = observations !== null && String(observations).trim() !== '' ? String(observations).trim() : null;
    const crees = [];
    for (const ligne of p.traitements) {
        if (ligne.deja_administre || !idsCoches.map(String).includes(String(ligne.standard.id))) continue;
        const s = ligne.standard;
        crees.push({ id: nouvelId(), lot_id: lot.id, action_type: s.treatment, product_used: s.product_recommended ?? null, dose: s.dosage ?? null, vet_name: null, symptomes: notes, cost: null, record_date: jour, withdrawal_days: Math.trunc(Number(s.withdrawal_days ?? 0)) || 0, is_active: true });
    }
    if (crees.length === 0) return { refus: null, avertissement: MOTIFS.rien, soins: [] };
    return { refus: null, message: MOTIFS.enregistres(crees.length), soins: crees };
}

/** La période de rémanence que le serveur crée pour un soin (`RecordVeterinaryCareAction`) : jouée localement pour bloquer la vente. */
export function remanenceDuSoin(soin) {
    if (!(soin.withdrawal_days > 0) || !soin.product_used) return null;
    return { id: `local-${soin.id}`, lot_id: soin.lot_id, product_used: soin.product_used, start_date: soin.record_date, withdrawal_days: soin.withdrawal_days, end_date: ajouterJours(soin.record_date, soin.withdrawal_days) };
}

// ------------------------------------------------------------------------------------------------ file d'envoi des soins

const ecrire = async ({ base, cle }, liste, maintenant = () => new Date()) => {
    if (liste.length === 0) await base.supprimer('referentiels', TABLE_SOINS_A_ENVOYER);
    else await base.ecrire('referentiels', { table: TABLE_SOINS_A_ENVOYER, tire_le: maintenant().toISOString(), ...(await chiffrer(cle, liste)) });
    const actuel = (await base.meta(META_AUTRES_EN_ATTENTE)) ?? {};
    await base.poserMeta(META_AUTRES_EN_ATTENTE, { ...actuel, soins: liste.filter((x) => x.sync_status !== 'synced').length });
};
export async function soinsEnAttente({ base, cle }) {
    const ligne = await base.lire('referentiels', TABLE_SOINS_A_ENVOYER);
    return ligne ? dechiffrer(cle, ligne) : [];
}
const modifier = async (ctx, f, maintenant) => { await ecrire(ctx, f(await soinsEnAttente(ctx)), maintenant); };

/** Garde les soins validés (un élément par soin) ; ne rend qu'une fois l'écriture DURABLE. */
export async function garderSoins(ctx, soins, maintenant = () => new Date()) {
    const liste = [...(await soinsEnAttente(ctx)), ...soins.map((soin) => ({ id: soin.id, lot_id: soin.lot_id, jour: soin.record_date, soin, cree_le: maintenant().toISOString(), sync_status: 'pending' }))];
    await ecrire(ctx, liste, maintenant);
    return liste;
}
export const aEnvoyerSoins = (liste) => liste.filter((x) => x.sync_status === 'pending');
export const marquerSoinsSynced = (ctx, ids, maintenant = () => new Date()) => modifier(ctx, (l) => l.map((x) => (ids.includes(x.id) ? { ...x, sync_status: 'synced', synced_le: maintenant().toISOString(), motif: null } : x)), maintenant);
export const marquerSoinConflit = (ctx, id, motif, maintenant = () => new Date()) => modifier(ctx, (l) => l.map((x) => (x.id === id ? { ...x, sync_status: 'conflict', motif } : x)), maintenant);
export const remettreSoinEnFile = (ctx, id, maintenant = () => new Date()) => modifier(ctx, (l) => l.map((x) => (x.id === id && x.sync_status === 'conflict' ? { ...x, sync_status: 'pending', motif: null } : x)), maintenant);
export const abandonnerSoin = (ctx, id, maintenant = () => new Date()) => modifier(ctx, (l) => l.filter((x) => x.id !== id), maintenant);
export const retirerSoinsSynced = (ctx, avant, maintenant = () => new Date()) => modifier(ctx, (l) => l.filter((x) => !(x.sync_status === 'synced' && Date.parse(x.synced_le ?? 0) < avant)), maintenant);

/** Le soin tel que le poste l'envoie (`_soinEnJson`) : la rémanence part avec lui, le serveur crée la période. */
export const soinEnJson = (item, deviceId) => ({ ...item.soin, device_id: deviceId, updated_at: item.cree_le });

/** Soins tirés + soins en attente (hors refusés) : ce que « déjà administré » et le tableau mensuel voient. */
export function soinsAvecLocaux(tires, items) {
    const connus = new Set(tires.map((s) => s.id));
    return [...tires, ...items.filter((x) => x.sync_status !== 'conflict' && !connus.has(x.id)).map((x) => x.soin)];
}
export const remanencesAvecLocales = (tirees, items) => [...tirees, ...items.filter((x) => x.sync_status !== 'conflict').map((x) => remanenceDuSoin(x.soin)).filter((r) => r !== null && !tirees.some((t) => t.id === r.id))];

// ----------------------------------------------------------------------------------------------------------------- rendu

/** Le bloc « Traitements & Prophylaxie » (DOM, jamais `innerHTML`). `coches` : Set des identifiants du barème cochés ; `actions.valider()`. */
export function rendreProphylaxie(h, { protocole: p, coches, lectureSeule, actions, titre = LIBELLES.titre }) {
    const cle = !determinable(p) ? 'indetermine' : (p.traitements.length === 0 ? 'libre' : (enAttente(p) === 0 ? 'valide' : 'prevus'));
    const classes = { indetermine: 'refus', libre: 'neutre', prevus: 'avert', valide: 'info' };
    const lignes = p.traitements.map(({ standard: s, deja_administre: fait }) => {
        const details = [s.product_recommended, s.dosage].filter(Boolean).join(' — ');
        const caseACocher = h('input', { type: 'checkbox', value: String(s.id), checked: fait || coches.has(String(s.id)), disabled: fait || Boolean(lectureSeule), 'data-prophy': String(s.id) });
        caseACocher.addEventListener('change', () => { if (caseACocher.checked) coches.add(String(s.id)); else coches.delete(String(s.id)); });
        return h('div', { class: 'prophy-ligne' },
            h('label', {}, caseACocher, ' ', h('b', { style: fait ? 'text-decoration:line-through' : '' }, s.treatment), details !== '' ? ` (${details})` : ''),
            Number(s.withdrawal_days) > 0 ? h('span', { class: 'pastille neutre' }, LIBELLES.remanence(Number(s.withdrawal_days))) : null);
    });
    return h('div', { id: 'saisie-prophylaxie', class: 'saisie-groupe' },
        h('b', {}, titre),
        h('div', { class: 'groupe', style: 'justify-content:space-between' },
            h('span', { class: 'muted', id: 'prophy-cycle' }, determinable(p) ? LIBELLES.jour(p.jourDeCycle) : LIBELLES.jourInconnu),
            h('span', { class: `pastille ${classes[cle]}`, id: 'prophy-etat' }, etatProtocole(p))),
        !determinable(p) ? h('p', { class: 'alerte', id: 'prophy-indetermine' }, LIBELLES.nonCalculable(p.motifIndetermine)) : null,
        p.traitements.length === 0 && determinable(p) ? h('p', { class: 'muted', id: 'prophy-aucun' }, LIBELLES.aucun) : h('div', { id: 'prophy-lignes' }, ...lignes),
        p.calendairesNonEvalues > 0 ? h('p', { class: 'muted', id: 'prophy-calendaires' }, LIBELLES.calendaires(p.calendairesNonEvalues)) : null,
        enAttente(p) > 0 ? h('div', {}, h('p', { class: 'alerte' }, LIBELLES.blocage),
            h('button', { type: 'button', class: 'btn plein', id: 'prophy-valider', disabled: Boolean(lectureSeule), onclick: () => actions.valider() }, h('span', { class: 'material-symbols-outlined' }, 'check_circle'), LIBELLES.valider)) : null,
        p.traitements.length > 0 ? h('span', { class: enAttente(p) > 0 ? 'pastille refus' : 'pastille info', id: 'prophy-indice' }, LIBELLES.indice(enAttente(p))) : null);
}
