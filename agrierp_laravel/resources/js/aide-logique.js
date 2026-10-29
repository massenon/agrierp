/**
 * Ticket AIDE-1 — LOGIQUE PURE de la visite guidée : où mettre le trou lumineux et où poser la carte.
 *
 * Aucune dépendance au navigateur : testable avec `node --test tests/Js` (valeurs attendues calculées à la main).
 * Un rectangle est `{ top, left, width, height }` en pixels de la fenêtre (comme `getBoundingClientRect`).
 */

/** Marge laissée autour de l'élément mis en valeur, et distance carte ↔ élément. */
export const MARGE_TROU = 6;
export const ECART_CARTE = 12;
export const BORD_ECRAN = 16;

/**
 * L'élément est-il réellement visible dans la fenêtre ? Un menu replié (`display: none`, rectangle nul) ou hors champ
 * (tiroir mobile fermé, décalé à gauche) n'a rien à mettre en valeur : l'étape s'affiche alors sans trou, sur le
 * seul voile.
 */
export function rectUtilisable(rect, largeurFenetre, hauteurFenetre) {
    if (!rect) {
        return false;
    }
    if (rect.width < 1 || rect.height < 1) {
        return false;
    }
    const droite = rect.left + rect.width;
    const bas = rect.top + rect.height;

    return droite > 0 && bas > 0 && rect.left < largeurFenetre && rect.top < hauteurFenetre;
}

/** Le trou lumineux : le rectangle élargi de la marge, rogné à la fenêtre. */
export function trouAutour(rect, largeurFenetre, hauteurFenetre, marge = MARGE_TROU) {
    const gauche = Math.max(0, rect.left - marge);
    const haut = Math.max(0, rect.top - marge);
    const droite = Math.min(largeurFenetre, rect.left + rect.width + marge);
    const bas = Math.min(hauteurFenetre, rect.top + rect.height + marge);

    return { top: haut, left: gauche, width: droite - gauche, height: bas - haut };
}

/**
 * Position de la carte (coin haut-gauche) : sous le trou, sinon au-dessus, sinon à droite, sinon à gauche ; si rien ne
 * tient (élément qui remplit l'écran), carte centrée en bas. Sans trou : carte centrée dans la fenêtre.
 * La carte ne sort jamais de la fenêtre (`BORD_ECRAN`).
 */
export function placerCarte(trou, carte, largeurFenetre, hauteurFenetre) {
    const maxGauche = Math.max(BORD_ECRAN, largeurFenetre - carte.width - BORD_ECRAN);
    const maxHaut = Math.max(BORD_ECRAN, hauteurFenetre - carte.height - BORD_ECRAN);
    const borner = (valeur, max) => Math.min(Math.max(valeur, BORD_ECRAN), max);

    if (!trou) {
        return {
            top: borner((hauteurFenetre - carte.height) / 2, maxHaut),
            left: borner((largeurFenetre - carte.width) / 2, maxGauche),
            lieu: 'centre',
        };
    }

    const sousLeTrou = trou.top + trou.height + ECART_CARTE;
    if (sousLeTrou + carte.height + BORD_ECRAN <= hauteurFenetre) {
        return { top: sousLeTrou, left: borner(trou.left, maxGauche), lieu: 'dessous' };
    }

    const auDessus = trou.top - ECART_CARTE - carte.height;
    if (auDessus >= BORD_ECRAN) {
        return { top: auDessus, left: borner(trou.left, maxGauche), lieu: 'dessus' };
    }

    const aDroite = trou.left + trou.width + ECART_CARTE;
    if (aDroite + carte.width + BORD_ECRAN <= largeurFenetre) {
        return { top: borner(trou.top, maxHaut), left: aDroite, lieu: 'droite' };
    }

    const aGauche = trou.left - ECART_CARTE - carte.width;
    if (aGauche >= BORD_ECRAN) {
        return { top: borner(trou.top, maxHaut), left: aGauche, lieu: 'gauche' };
    }

    return { top: maxHaut, left: borner((largeurFenetre - carte.width) / 2, maxGauche), lieu: 'bas' };
}

/** « Étape 1 sur 4 » : le gabarit du fichier de langue (`:numero`, `:total`) rempli. */
export function indicateur(gabarit, etape, total) {
    return gabarit.replace(':numero', String(etape + 1)).replace(':total', String(total));
}
