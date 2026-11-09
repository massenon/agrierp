/** PWA-1 — Logique PURE du catalogue de la caisse hors ligne (filtre, tuile, mise en forme). Testée par `node --test`. */

export function normaliser(texte) {
    return String(texte ?? '').normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().trim();
}

/** Produits vendables affichés : actifs, filtrés par recherche (sans accents ni casse) et catégorie. */
export function filtrerProduits(produits, recherche = '', categorieId = '') {
    const r = normaliser(recherche);
    return produits
        .filter((p) => p.is_active !== false)
        .filter((p) => categorieId === '' || p.category_id === categorieId)
        .filter((p) => r === '' || normaliser(p.name).includes(r) || normaliser(p.sku).includes(r))
        .sort((a, b) => normaliser(a.name).localeCompare(normaliser(b.name), 'fr'));
}

/** Ce que la tuile dit du produit, et si elle est cliquable. */
export function etatTuile(p) {
    if (p.pricing_mode === 'quote') return { vendable: false, note: 'Sur devis technique' };
    if (p.species_id) return { vendable: true, note: 'Sujet vivant : bande source obligatoire' };
    return { vendable: true, note: '' };
}

export function fourchetteDePrix(p) {
    const min = Number(p.price_min);
    const max = Number(p.price_max);
    const f = (n) => String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
    if (Number.isFinite(min) && Number.isFinite(max) && max > min) return `${f(min)} – ${f(max)} FCFA`;
    if (Number.isFinite(min) && min > 0) return `${f(min)} FCFA`;
    return '';
}

/** CONF-3 (DV-21) : dès ce nombre de jours sans tirage du catalogue, bandeau d'AVERTISSEMENT sur la caisse. */
export const SEUIL_AVERTISSEMENT_PRIX_JOURS = 3;

/** CONF-3 (DV-21) : dès ce nombre de jours, avertissement FORT et CONFIRMATION explicite avant chaque vente. Jamais un refus. */
export const SEUIL_CONFIRMATION_PRIX_JOURS = 7;

export const NIVEAUX_PRIX = { aucun: 'aucun', avertissement: 'avertissement', confirmation: 'confirmation' };

/** Niveau d'alerte « prix périmés » selon l'âge du tirage. Aucun tirage connu (null) : aucun niveau (la caisse est alors vide). */
export function niveauPrixPerimes(jours) {
    if (jours === null || jours === undefined || !Number.isFinite(jours)) return NIVEAUX_PRIX.aucun;
    if (jours >= SEUIL_CONFIRMATION_PRIX_JOURS) return NIVEAUX_PRIX.confirmation;
    if (jours >= SEUIL_AVERTISSEMENT_PRIX_JOURS) return NIVEAUX_PRIX.avertissement;
    return NIVEAUX_PRIX.aucun;
}

const duree = (n) => `${n} jour${n > 1 ? 's' : ''}`;

/** Texte du bandeau de la page de caisse ; chaîne vide sous le premier seuil (jamais de « 0 jour »). */
export function messageBandeauPrix(jours) {
    const niveau = niveauPrixPerimes(jours);
    if (niveau === NIVEAUX_PRIX.avertissement) return `Prix tirés il y a ${duree(jours)} : reconnectez-vous pour les actualiser.`;
    if (niveau === NIVEAUX_PRIX.confirmation) return `Attention : les prix datent de ${duree(jours)} et peuvent être périmés. Reconnectez-vous pour les actualiser ; chaque vente demandera une confirmation.`;
    return '';
}

/** Question posée avant CHAQUE vente à partir du second seuil. */
export function messageConfirmationVente(jours) {
    return `Les prix datent de ${duree(jours)} et peuvent être périmés. Confirmer la vente ?`;
}

/** Ligne d'information sur le dernier tirage (l'alerte « prix périmés » est portée par le bandeau, pas par cette ligne). */
export function messageAgeTirage(joursEcoules) {
    if (joursEcoules === null || joursEcoules === undefined) return 'Catalogue jamais tiré : connectez-vous une fois pour le recevoir.';
    if (joursEcoules <= 0) return "Catalogue tiré aujourd'hui.";
    return `Dernier tirage du catalogue : il y a ${duree(joursEcoules)}.`;
}

/** Libellés de statut d'une vente locale (mots de la modale « Synchronisation » du poste). */
export const LIBELLES_STATUT = { pending: 'En attente d\'envoi', synced: 'Envoyée', conflict: 'Refusée par le serveur' };
