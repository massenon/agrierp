/**
 * PWA-1 — ÉTAT AFFICHÉ de la synchronisation : logique pure, testée par `node --test`.
 *
 * Libellés copiés de la modale « Synchronisation » du poste (`modale_synchronisation.dart`) et de la barre du haut du
 * web : « En attente d'envoi », « Refusés par le serveur », « Dernière synchronisation réussie »… Jamais deux couleurs
 * pour le même sens ; « Hors ligne » n'est JAMAIS une erreur rouge.
 *
 * Priorité d'affichage : Reconnexion requise (401/403) > Refus > Hors ligne > En attente > En cours > Synchronisé.
 */

export const TONS = { neutre: 'neutre', attention: 'attention', erreur: 'erreur', ok: 'ok' };

/**
 * @param {{enLigne:boolean, enCours:boolean, suspendu:boolean, pending:number, conflict:number, derniereSynchro:?string}} s
 * @returns {{cle:string, libelle:string, ton:string}}
 */
export function etatAffiche({ enLigne, enCours, suspendu, pending = 0, conflict = 0, derniereSynchro = null }) {
    if (suspendu) {
        return { cle: 'reconnexion', libelle: 'Reconnexion requise', ton: TONS.erreur };
    }
    if (conflict > 0) {
        return { cle: 'refus', libelle: `Refus (${conflict})`, ton: TONS.erreur };
    }
    if (!enLigne) {
        return { cle: 'hors_ligne', libelle: pending > 0 ? `Hors ligne — ${pending} en attente` : 'Hors ligne', ton: TONS.neutre };
    }
    if (pending > 0) {
        return { cle: 'en_attente', libelle: `En attente (${pending})`, ton: TONS.attention };
    }
    if (enCours) {
        return { cle: 'en_cours', libelle: 'Synchronisation…', ton: TONS.neutre };
    }
    return { cle: 'synchronise', libelle: derniereSynchro ? `Synchronisé — ${derniereSynchro}` : 'Synchronisé', ton: TONS.ok };
}

/** Réessais sur échec réseau ou 5xx : 30 s, 2 min, 5 min, 15 min, 1 h (puis 1 h). Un refus 4xx n'est PAS réessayé. */
export const DELAIS_DE_REESSAI_MS = [30_000, 120_000, 300_000, 900_000, 3_600_000];

export function delaiDeReessai(essai) {
    return DELAIS_DE_REESSAI_MS[Math.min(Math.max(essai, 0), DELAIS_DE_REESSAI_MS.length - 1)];
}

/** Classe une réponse HTTP du serveur : que doit faire la machine d'états ? */
export function classerReponse(statut) {
    if (statut >= 200 && statut < 300) return 'ok';
    if (statut === 401 || statut === 403) return 'suspendre';       // jeton révoqué / poste différent : reconnexion
    if (statut === 409) return 'reinitialisation';                  // données remises à zéro côté serveur
    if (statut === 413) return 'reduire_lot';
    if (statut === 429 || statut >= 500 || statut === 408) return 'reessayer';
    return 'refuser';                                               // 4xx : refus, pas de réessai automatique
}

/** Heure du SERVEUR (`server_time` du dernier tirage), « 14:46 » — jamais l'horloge de l'appareil. */
export function heureDuServeur(serverTime) {
    const m = /T(\d{2}):(\d{2})/.exec(serverTime ?? '');
    return m ? `${m[1]}:${m[2]}` : null;
}

/** Durée depuis le dernier tirage, pour refuser/avertir d'un prix périmé. */
export function ageDuTirageEnJours(serverTime, maintenantMs) {
    const t = Date.parse(serverTime ?? '');
    return Number.isFinite(t) ? Math.floor((maintenantMs - t) / 86_400_000) : null;
}
