/**
 * CAISSE-1 (volet animalier, décision du client du 09/11/2026) — CE QUE L'ÉCRAN MONTRE SUIT LES DROITS DU COMPTE.
 *
 * `POST /api/auth/login` rend `user.droits` (parmi `manage-ventes`, `view-elevage`, `manage-elevage`) ; l'appairage les garde avec l'utilisateur.
 * Caisse (panier, ventes, clients créés hors ligne, livraison) : `manage-ventes` SEULEMENT. Fiches d'élevage : `view-elevage` pour les voir,
 * `manage-elevage` pour écrire. Le SERVEUR reste le juge de chaque envoi et de chaque tirage : cet écran ne donne aucun droit, il évite seulement de
 * montrer ce que le compte ne peut pas faire. Appareil appairé AVANT ce changement (pas de `droits`) : l'ancien comportement (caisse visible, écriture
 * des fiches selon le rôle `admin` / `animalier`).
 */

export const ROLES_ECRITURE_FICHES = ['admin', 'animalier'];

/** @param {{role?:?string, droits?:?string[]}|null} utilisateur */
export function droitsDeLEcran(utilisateur) {
    const droits = Array.isArray(utilisateur?.droits) ? utilisateur.droits : null;
    if (droits === null) return { caisse: true, fiches: true, ecritureFiches: ROLES_ECRITURE_FICHES.includes(utilisateur?.role ?? '') };
    return { caisse: droits.includes('manage-ventes'), fiches: droits.includes('view-elevage'), ecritureFiches: droits.includes('manage-elevage') };
}
