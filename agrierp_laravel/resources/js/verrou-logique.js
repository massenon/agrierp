/**
 * Sprint VW (VW2) — LOGIQUE PURE de la minuterie d'inactivité du verrou de session web.
 *
 * Aucune dépendance au navigateur : testable avec `node --test tests/Js` (valeurs attendues calculées à la main,
 * PRD docs/prd/verrou-web.md § 5). Les durées sont celles du poste (`ReglageInactivite.choix`) et du serveur
 * (`VerrouSessionService::DUREES`) : `VerrouSessionBladeTest` vérifie qu'elles sont identiques.
 */

/** Minutes ; 0 = « Jamais ». */
export const DUREES = [0, 1, 5, 15, 30];
export const DUREE_PAR_DEFAUT = 5;

export function dureeValide(minutes) {
    return Number.isInteger(minutes) && DUREES.includes(minutes);
}

/**
 * Que faire à cet instant ?
 *  - 'rien'       : pas d'échéance (Jamais, déjà verrouillé, ou délai pas atteint) ;
 *  - 'attendre'   : l'échéance est passée mais une opération est en cours (requête Livewire en vol, export ou
 *                   téléchargement suspendu) — on ne coupe jamais une opération, on revérifie plus tard ;
 *  - 'verrouiller': échéance passée, rien en cours.
 * Une durée inconnue vaut le défaut (mieux vaut verrouiller à 5 minutes que ne jamais verrouiller par accident).
 */
export function decider({ maintenant, derniereActivite, minutes, requetesEnCours = 0, suspenduJusqua = 0, verrouille = false }) {
    if (verrouille) {
        return 'rien';
    }
    const duree = dureeValide(minutes) ? minutes : DUREE_PAR_DEFAUT;
    if (duree === 0) {
        return 'rien';
    }
    if (maintenant - derniereActivite < duree * 60_000) {
        return 'rien';
    }
    if (requetesEnCours > 0 || maintenant < suspenduJusqua) {
        return 'attendre';
    }
    return 'verrouiller';
}

/** « 1 min 05 s », « 42 s » : la mise en forme du poste (`_formater` de l'écran de verrouillage). */
export function formaterAttente(secondes) {
    if (secondes >= 60) {
        return `${Math.floor(secondes / 60)} min ${String(secondes % 60).padStart(2, '0')} s`;
    }
    return `${secondes} s`;
}
