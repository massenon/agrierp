import { ouvrirBase, totalEnAttente, listeEnAttente } from './base-locale.js';
import { lireMarqueur, purgerLocal, decisionDeconnexion, MARQUEUR_ACTIVE } from './appairage.js';

/**
 * PWA-1 — DÉCONNEXION WEB = PURGE DE L'APPAREIL (comme au poste), sans jamais perdre une vente en silence.
 *
 * Intercepte le formulaire de déconnexion du menu de profil :
 *  - ce navigateur n'est pas appairé : la déconnexion part telle quelle (aucune surcoût) ;
 *  - des ventes `pending` / `conflict`, des fiches d'élevage ou des clients créés hors ligne attendent sur l'appareil : la déconnexion est REFUSÉE (toast) tant qu'elles ne sont
 *    pas envoyées ou explicitement abandonnées dans la caisse hors ligne ;
 *  - sinon : base IndexedDB, caches du service worker, marqueurs sont effacés, PUIS la déconnexion part.
 * Le jeton de l'appareil est chiffré par le PIN : il ne peut pas être révoqué ici ; il reste révocable dans Paramètres,
 * Postes & Appairage, et expire sous 90 jours.
 */
document.addEventListener('submit', async (ev) => {
    const f = ev.target;
    if (!(f instanceof HTMLFormElement) || f.dataset.horsLigneOk === '1') return;
    let chemin = '';
    try { chemin = new URL(f.action, window.location.href).pathname; } catch { return; }
    if (!/\/logout$/.test(chemin) || lireMarqueur(MARQUEUR_ACTIVE) !== '1') return;

    ev.preventDefault();
    const partir = () => { f.dataset.horsLigneOk = '1'; f.submit(); };
    let base = null;
    try {
        base = await ouvrirBase();
        const c = await base.compterTout();
        const n = totalEnAttente(c);
        // CAISSE-1 (DV-32) : sur un appareil PERSONNEL, la déconnexion efface TOUT après confirmation (le nombre d'éléments perdus est dit) ; sur un appareil de l'entreprise, elle est refusée tant que des éléments attendent.
        const decision = decisionDeconnexion((await base.meta('appareil'))?.type_appareil, n);
        if (decision === 'confirmer') {
            if (!window.confirm(`Appareil personnel : ${listeEnAttente(c)} ne sont pas encore envoyé(e)s et seront PERDU(E)S. Toutes les données hors ligne de cet appareil seront effacées. Se déconnecter quand même ?`)) { base.fermer(); return; }
        } else if (decision === 'refuser') {
            base.fermer();
            window.dispatchEvent(new CustomEvent('toast', { detail: {
                message: `${listeEnAttente(c)} de la caisse hors ligne ne sont pas encore envoyé(e)s : ouvrez la caisse hors ligne pour les envoyer (ou les abandonner) avant de vous déconnecter.`,
                type: 'warning',
            } }));
            return;
        }
    } catch { /* base illisible : on ne bloque pas la déconnexion, on purge au mieux */ }
    await purgerLocal({ base });
    partir();
});
