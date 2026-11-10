/**
 * CAISSE-2 (DV-33) — LE REÇU PROVISOIRE d'une vente enregistrée HORS LIGNE.
 *
 * Un document « Reçu provisoire » SANS numéro de facture légal : le numéro est attribué par le serveur à la synchronisation (jamais par le navigateur). Il porte
 * l'identifiant court de la vente (8 premiers caractères de l'UUID, en majuscules), la date et l'heure du Bénin, le client, les lignes, la remise, la livraison
 * facturée, le mode de règlement lisible (libellés de `App\Support\ModePaiement`, DV-22), le montant reçu / rendu et la mention exacte ci-dessous. Offert
 * tant que la vente attend son envoi (`pending`) ; après la synchronisation, le numéro légal vit sur la facture du serveur (écran Facturation du web).
 * Impression par le navigateur (iframe `srcdoc`, jamais une page authentifiée ni une ressource mise en cache).
 */

import { formaterFcfa } from './calculs-caisse.js';

export const TITRE_RECU = 'Reçu provisoire';
export const MENTION_RECU = 'Facture n° attribué à la synchronisation.';
export const BOUTON_RECU = 'Imprimer le reçu provisoire';
export const CLIENT_ANONYME = 'Client Anonyme';

/** `App\Support\ModePaiement::LIBELLES` (garde de sources : `recu-provisoire.test.mjs`). */
export const LIBELLES_MODE = { especes: 'Espèces', mobile_money: 'Mobile Money', virement: 'Virement bancaire', cheque: 'Chèque', credit: 'Crédit client', avance: 'Avance' };

/** `ModePaiement::libelle` : clé inconnue = la clé capitalisée (`_` lus comme des espaces), vide = « — ». */
export function libelleMode(cle) {
    const c = String(cle ?? '').trim();
    if (c === '') return '—';
    if (LIBELLES_MODE[c]) return LIBELLES_MODE[c];
    const lisible = c.replaceAll('_', ' ').trim();
    if (lisible === '') return c;
    return `${lisible[0].toUpperCase()}${lisible.slice(1)}`;
}

/** L'identifiant court de la vente. */
export const idCourt = (id) => String(id ?? '').slice(0, 8).toUpperCase();

const deux = (n) => String(n).padStart(2, '0');
/** Date et heure du Bénin (UTC+1) : `JJ/MM/AAAA à HH:MM`. */
export function dateHeureBenin(iso) {
    const d = new Date(Date.parse(iso) + 3600000);
    if (Number.isNaN(d.getTime())) return '—';
    return `${deux(d.getUTCDate())}/${deux(d.getUTCMonth() + 1)}/${d.getUTCFullYear()} à ${deux(d.getUTCHours())}:${deux(d.getUTCMinutes())}`;
}

/** Offert tant que la vente attend son envoi (`pending`) : une vente refusée par le serveur (`conflict`) n'aura pas de facture, une vente `synced` a son numéro au serveur. */
export const recuProvisoireDisponible = (item) => item?.sync_status === 'pending';

/**
 * Le contenu du reçu, en données. `donnees` : `{entreprise, produits, clients}` (copies tirées).
 */
export function contenuRecu(vente, { entreprise = null, produits = [], clients = [] } = {}) {
    const nom = (id) => produits.find((p) => p.id === id)?.name ?? 'Produit';
    const client = vente.client_nom_facture || clients.find((c) => c.id === vente.customer_id)?.name || CLIENT_ANONYME;
    const lignes = (vente.lines ?? []).map((l) => ({ produit: nom(l.product_id), quantite: l.qty, prix: formaterFcfa(l.unit_price), total: formaterFcfa(l.manual_total_amount) }));
    const frais = Number(vente.delivery_fee) || 0;
    return {
        entete: entreprise?.company_name || 'LogiAgriERP',
        titre: TITRE_RECU,
        identifiant: idCourt(vente.id),
        dateHeure: dateHeureBenin(vente.sold_at),
        client,
        lignes,
        remise: Number(vente.discount) > 0 ? formaterFcfa(vente.discount) : null,
        livraison: vente.delivery_in_total && frais > 0 ? formaterFcfa(frais) : null,
        total: formaterFcfa(vente.total),
        mode: libelleMode(vente.payment_mode),
        recu: vente.payment_mode === 'especes' && vente.cash_received != null ? formaterFcfa(vente.cash_received) : null,
        rendu: vente.payment_mode === 'especes' && vente.change_due != null ? formaterFcfa(vente.change_due) : null,
        mention: MENTION_RECU,
    };
}

const echapper = (t) => String(t).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

/** Le reçu en DOM (aperçu de la boîte de dialogue) : `h(tag, attrs, ...enfants)` est le constructeur de la page. */
export function rendreRecu(h, c) {
    return h('div', { id: 'recu-provisoire', class: 'recu' },
        h('h3', { id: 'recu-entete' }, c.entete),
        h('h4', { id: 'recu-titre' }, c.titre),
        h('p', { id: 'recu-identifiant' }, `Vente n° ${c.identifiant}`),
        h('p', { id: 'recu-date' }, `Date : ${c.dateHeure}`),
        h('p', { id: 'recu-client' }, `Client : ${c.client}`),
        h('table', { class: 'rtable' },
            h('thead', {}, h('tr', {}, ...['Produit', 'Qté', 'Prix', 'Total'].map((t) => h('th', {}, t)))),
            h('tbody', {}, ...c.lignes.map((l) => h('tr', {}, h('td', {}, l.produit), h('td', { class: 'num' }, String(l.quantite)), h('td', { class: 'num' }, l.prix), h('td', { class: 'num' }, l.total))))),
        c.remise ? h('p', { id: 'recu-remise' }, `Remise : ${c.remise}`) : null,
        c.livraison ? h('p', { id: 'recu-livraison' }, `Frais de livraison (facturée) : ${c.livraison}`) : null,
        h('p', { id: 'recu-total' }, h('b', {}, `Total : ${c.total}`)),
        h('p', { id: 'recu-mode' }, `Mode de règlement : ${c.mode}`),
        c.recu !== null ? h('p', { id: 'recu-montants' }, `Montant reçu : ${c.recu} — Rendu : ${c.rendu}`) : null,
        h('p', { id: 'recu-mention' }, h('i', {}, c.mention)));
}

/** Le reçu en page HTML autonome pour l'impression (tout est échappé ; aucune ressource externe). */
export function recuEnHtml(c) {
    const lignes = c.lignes.map((l) => `<tr><td>${echapper(l.produit)}</td><td class="n">${echapper(l.quantite)}</td><td class="n">${echapper(l.prix)}</td><td class="n">${echapper(l.total)}</td></tr>`).join('');
    return `<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>${echapper(c.titre)} ${echapper(c.identifiant)}</title>`
        + '<style>body{font-family:Arial,sans-serif;font-size:13px;margin:24px;color:#111}h1{font-size:18px;margin:0}h2{font-size:15px;margin:4px 0 12px}table{border-collapse:collapse;width:100%;margin:10px 0}th,td{border-bottom:1px solid #999;padding:4px;text-align:left}.n{text-align:right}p{margin:4px 0}</style></head><body>'
        + `<h1>${echapper(c.entete)}</h1><h2>${echapper(c.titre)}</h2>`
        + `<p>Vente n° <b>${echapper(c.identifiant)}</b></p><p>Date : ${echapper(c.dateHeure)}</p><p>Client : ${echapper(c.client)}</p>`
        + `<table><thead><tr><th>Produit</th><th class="n">Qté</th><th class="n">Prix</th><th class="n">Total</th></tr></thead><tbody>${lignes}</tbody></table>`
        + (c.remise ? `<p>Remise : ${echapper(c.remise)}</p>` : '')
        + (c.livraison ? `<p>Frais de livraison (facturée) : ${echapper(c.livraison)}</p>` : '')
        + `<p><b>Total : ${echapper(c.total)}</b></p><p>Mode de règlement : ${echapper(c.mode)}</p>`
        + (c.recu !== null ? `<p>Montant reçu : ${echapper(c.recu)} — Rendu : ${echapper(c.rendu)}</p>` : '')
        + `<p><i>${echapper(c.mention)}</i></p></body></html>`;
}

/** Imprime le reçu par le navigateur : iframe cachée en `srcdoc`, puis `print()`, retirée ensuite. */
export function imprimerRecu(c, doc = globalThis.document) {
    const cadre = doc.createElement('iframe');
    cadre.setAttribute('aria-hidden', 'true');
    cadre.style.cssText = 'position:fixed;width:0;height:0;border:0;visibility:hidden';
    cadre.srcdoc = recuEnHtml(c);
    cadre.addEventListener('load', () => {
        try { cadre.contentWindow.focus(); cadre.contentWindow.print(); } finally { setTimeout(() => cadre.remove(), 60000); }
    });
    doc.body.append(cadre);
    return cadre;
}
