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
    if (p.species_id) return { vendable: false, note: 'Rattaché à une espèce (bande source) — vente en ligne' };
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

/** Âge du tirage : avertit au-delà de `seuil` jours (prix peut-être périmés). */
export function messageAgeTirage(joursEcoules, seuil = 3) {
    if (joursEcoules === null || joursEcoules === undefined) return 'Catalogue jamais tiré : connectez-vous une fois pour le recevoir.';
    if (joursEcoules >= seuil) return `Dernier tirage du catalogue : il y a ${joursEcoules} jour(s) — vérifiez les prix avant de vendre.`;
    if (joursEcoules <= 0) return "Catalogue tiré aujourd'hui.";
    return `Dernier tirage du catalogue : il y a ${joursEcoules} jour(s).`;
}

/** Libellés de statut d'une vente locale (mots de la modale « Synchronisation » du poste). */
export const LIBELLES_STATUT = { pending: 'En attente d\'envoi', synced: 'Envoyée', conflict: 'Refusée par le serveur' };
