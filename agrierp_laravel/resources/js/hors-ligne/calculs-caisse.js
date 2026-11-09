/**
 * PWA-1 — CALCULS DE LA CAISSE HORS LIGNE, EN JAVASCRIPT PUR (aucune dépendance au navigateur).
 *
 * ⚠️ CE MODULE N'EST PAS UN MOTEUR MÉTIER. Le navigateur écrit des FAITS (une vente survenue) ; le serveur décide,
 * numérote, écrit le stock et la comptabilité (`SyncController::pushSales`). Seuls vivent ici les calculs que la caisse
 * du web (`Livewire\Ventes\PosInterface`) fait pour AFFICHER et pour REFUSER avant d'enregistrer :
 *
 *   - le montant d'une ligne est `manual_total_amount`, SOURCE DE VÉRITÉ (jamais prix unitaire × quantité) ;
 *   - tous les montants sont des ENTIERS en FCFA ; la quantité est un entier ≥ 1 (modale « Vente à la Pièce ») ;
 *   - sous-total = somme des lignes ; total = max(0, sous-total − remise) + livraison facturée (PWA-1b : `PosInterface::
 *     getLivraisonRetenueProperty`, FCFA entiers, jamais négative, seulement pour une livraison « facturée ») ;
 *   - prix unitaire d'affichage = arrondi à 2 décimales de montant / quantité (`round(montant / qty, 2)`) ;
 *   - TVA incluse : ligne à ligne (`VatDeclarationService::ht/tva`), remise répartie au prorata, exactement comme
 *     `RecordSaleAccountingEntryAction::ventilerHtEtTva` — affichage INDICATIF, la comptabilité reste au serveur ;
 *   - un panier vide, une vente à crédit sans client, un choix de facture invalide sont REFUSÉS avec les MÊMES mots que
 *     le web et le serveur.
 *
 * Parité : `tests/Js/parite-php.test.mjs` exécute le vrai PHP (`PosInterface`, `ChoixFactureService`,
 * `VatDeclarationService`, `SyncController::verifierCoherenceDuTotal`) sur la même grille de cas. Une divergence = test
 * rouge. Les valeurs de `tests/Js/calculs-caisse.test.mjs` sont calculées à la main.
 */

export const MODES_PAIEMENT = ['especes', 'mobile_money', 'virement', 'credit', 'avance'];

export const LIBELLES_PAIEMENT = {
    especes: 'Espèces',
    mobile_money: 'Mobile Money',
    virement: 'Virement',
    credit: 'Crédit',
    avance: "Déduire de l'avance",
};

/** Modes de livraison de la modale « Livraison » de la caisse web (`PosInterface::$deliveryMode`) et leurs libellés. */
export const MODES_LIVRAISON = {
    gratuite: 'Livraison gratuite (offerte)',
    client: 'Livraison assurée par le client',
    incluse: 'Prix de livraison inclus dans le montant',
    facturee: 'Livraison facturée (ajoutée au total de la vente)',
};
export const LIVRAISON_TEXTE_MAX = 255;

export const FACTURE_SIMPLE = 'simple';
export const FACTURE_NORMALISEE = 'normalisee';
export const AIB_TAUX = { '5%': '5 %', '1%': '1 %', 'N/A': 'Aucun (N/A)' };
export const AIB_DEFAUT = '5%';
export const NOM_FACTURE_MAX = 150;

/** Motifs : mot pour mot ceux de `PosInterface`, `ChoixFactureService` et `MotifsRefusPush` (garde : parité). */
export const MOTIFS = {
    panierVide: 'Le panier est vide.',
    venteACredit: 'Une vente à crédit exige un client : choisissez-le dans la liste ou créez-le avec le bouton « + ».',
    venteSurAvance: 'Une vente sur avance exige un client : choisissez-le dans la liste ou créez-le avec le bouton « + ».',
    livraisonMode: "La valeur du champ mode de livraison n'est pas autorisée.",
    livraisonFrais: 'Le champ frais de livraison doit être un nombre entier.',
    livraisonAdresse: 'Le champ adresse de livraison dépasse le maximum autorisé (255).',
    livraisonContact: 'Le champ contact du transporteur dépasse le maximum autorisé (255).',
    modeInconnu: "La valeur du champ mode de règlement n'est pas autorisée.",
    factureType: 'Type de facture inconnu : choisissez « Facture simple » ou « Facture normalisée ».',
    factureNom: 'Le nom et prénom du client sont obligatoires pour une facture normalisée.',
    factureIfu: "L'IFU du client doit comporter 13 chiffres (laissez-le vide pour un client sans IFU).",
    factureAib: "Choisissez le taux d'AIB : 5 %, 1 % ou Aucun (N/A).",
    quantite: 'Le champ quantité de la ligne doit être strictement supérieur à 0.',
    quantiteEntiere: 'La quantité doit être un nombre entier.',
    montant: 'Le champ montant de la ligne doit être un nombre.',
    montantNegatif: 'Le champ montant de la ligne est inférieur au minimum autorisé (0).',
    montantEntier: 'Le montant doit être un nombre entier de FCFA.',
    remise: 'Le champ remise est inférieur au minimum autorisé (0).',
    remiseEntiere: 'La remise doit être un nombre entier de FCFA.',
    remiseTropGrande: 'La remise ne peut pas dépasser le sous-total de la vente.',
    produitSansBande: "Ce produit est rattaché à une espèce d'élevage : sa vente exige la bande source et le contrôle vétérinaire. Vendez-le en ligne.",
    produitSurDevis: 'Ce produit se chiffre sur devis : il ne se vend pas à la caisse.',
    produitInconnu: 'Produit inconnu de la copie locale : synchronisez d’abord.',
    especesInsuffisantes: 'Le montant reçu est inférieur au total à payer.',
};

// ---------------------------------------------------------------------------------------------------------------
// Arrondis — `round()` de PHP 8.3 : demi-unité LOIN DE ZÉRO, après « pré-arrondi » à 15 chiffres significatifs.
// ---------------------------------------------------------------------------------------------------------------

export function arrondiPhp(valeur, decimales = 0) {
    if (!Number.isFinite(valeur)) {
        return valeur;
    }
    const facteur = 10 ** decimales;
    const brut = valeur * facteur;
    const prearrondi = Number(Math.abs(brut).toPrecision(15));
    const arrondi = Math.round(prearrondi); // Math.round arrondit la demi-unité vers +∞ ; ici prearrondi >= 0 : « loin de zéro »
    return (Math.sign(brut) * arrondi) / facteur;
}

/** `round(montant / qty, 2)` en arithmétique ENTIÈRE exacte (demi vers le haut, montants positifs) : jamais d'erreur binaire. */
export function prixUnitaire(montant, quantite) {
    if (!Number.isInteger(montant) || !Number.isInteger(quantite) || quantite <= 0) {
        return 0;
    }
    const numerateur = montant * 100;
    const centimes = Math.floor((2 * numerateur + quantite) / (2 * quantite));
    return centimes / 100;
}

// ---------------------------------------------------------------------------------------------------------------
// Lecture des saisies : texte → entier, jamais de flottant silencieux.
// ---------------------------------------------------------------------------------------------------------------

/**
 * Lit un entier saisi (« 11 800 », « 11800 »). Rend un entier ≥ 0, ou `null` si la saisie n'est pas un entier de FCFA
 * (virgule, point décimal, lettres, négatif, vide).
 */
export function lireEntier(saisie) {
    if (typeof saisie === 'number') {
        return Number.isInteger(saisie) ? saisie : null;
    }
    if (typeof saisie !== 'string') {
        return null;
    }
    const net = saisie.replace(/[\s  ]/g, '');
    return /^\d+$/.test(net) ? Number(net) : null;
}

export function formaterFcfa(montant) {
    const n = Number.isFinite(montant) ? Math.round(montant) : 0;
    const signe = n < 0 ? '-' : '';
    return `${signe}${String(Math.abs(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ' ')} FCFA`;
}

// ---------------------------------------------------------------------------------------------------------------
// Lignes, sous-total, total.
// ---------------------------------------------------------------------------------------------------------------

/** Le montant d'une ligne : SA source de vérité, `manual_total_amount`. */
export function montantLigne(ligne) {
    return ligne.manual_total_amount;
}

export function sousTotal(lignes) {
    return lignes.reduce((somme, ligne) => somme + montantLigne(ligne), 0);
}

/**
 * `PosInterface::getLivraisonRetenueProperty()` : les frais d'une livraison « facturée » (FCFA entiers, la demi-unité vers le haut
 * comme `MecefFactureBuilder::arrondi`), jamais négatifs ; les autres modes n'ajoutent rien. `frais` : nombre ou `null`.
 */
export function livraisonRetenue({ concernee = false, mode = 'gratuite', frais = null } = {}) {
    if (!concernee || mode !== 'facturee' || frais === null || frais === undefined || !Number.isFinite(frais)) {
        return 0;
    }
    return Math.max(0, arrondiPhp(frais));
}

/** Nombre saisi (virgule ou point) ; `null` si vide ou illisible. Négatifs admis (le total les ramène à 0, comme la caisse web). */
export function lireNombre(saisie) {
    if (typeof saisie === 'number') {
        return Number.isFinite(saisie) ? saisie : null;
    }
    if (typeof saisie !== 'string') {
        return null;
    }
    const net = saisie.replace(/[\s  ]/g, '').replace(',', '.');
    return /^-?\d+(\.\d+)?$/.test(net) ? Number(net) : null;
}

/** `PosInterface::getTotalProperty()` : `max(0, sous-total − remise) + livraison retenue`. */
export function totalVente(lignes, remise = 0, livraison = 0) {
    return Math.max(0, sousTotal(lignes) - remise) + livraison;
}

/** `PosInterface::getChangeDueProperty()` : seulement en espèces, jamais négative. */
export function monnaieARendre(mode, recu, total) {
    if (mode !== 'especes' || recu === null || recu === undefined) {
        return 0;
    }
    return Math.max(0, recu - total);
}

/**
 * TVA incluse dans la vente — port de `RecordSaleAccountingEntryAction::ventilerHtEtTva` (produits seulement).
 *
 * @param {{manual_total_amount:number, tva_rate:number}[]} lignes  `tva_rate` en pourcent (18 = 18 %)
 * @param {number} remise
 * @param {boolean} tvaActive  l'exploitation est-elle assujettie ? (`company_settings.tva_enabled`)
 * @returns {{ht:number, tva:number}}
 */
export function tvaIncluse(lignes, remise, tvaActive) {
    let ht = 0;
    let tva = 0;
    let ttcLignes = 0;
    for (const ligne of lignes) {
        const ttc = ligne.manual_total_amount;
        const taux = tvaActive ? Number(ligne.tva_rate ?? 0) / 100 : 0;
        const htLigne = arrondiPhp(ttc / (1 + taux));
        ttcLignes += ttc;
        ht += htLigne;
        tva += arrondiPhp(ttc - htLigne);
    }
    const total = totalVente(lignes, remise);
    if (ttcLignes > 0 && Math.abs(ttcLignes - total) >= 0.01) {
        const ratio = total / ttcLignes;
        ht = arrondiPhp(ht * ratio, 2);
        tva = arrondiPhp(tva * ratio, 2);
    }
    ht = arrondiPhp(total - tva, 2);
    return { ht, tva };
}

// ---------------------------------------------------------------------------------------------------------------
// Validation d'une ligne et du choix de facture.
// ---------------------------------------------------------------------------------------------------------------

/**
 * Valide la saisie d'une ligne (modale « Vente à la Pièce » : quantité entière ≥ 1, montant entier ≥ 0) et le produit.
 *
 * @returns {{ok:true, qty:number, montant:number}|{ok:false, motif:string}}
 */
export function validerLigne({ produit, qty, montant }) {
    if (!produit) {
        return { ok: false, motif: MOTIFS.produitInconnu };
    }
    if (produit.pricing_mode === 'quote') {
        return { ok: false, motif: MOTIFS.produitSurDevis };
    }
    if (produit.species_id) {
        return { ok: false, motif: MOTIFS.produitSansBande };
    }
    const quantite = lireEntier(qty);
    if (quantite === null) {
        return { ok: false, motif: MOTIFS.quantiteEntiere };
    }
    if (quantite < 1) {
        return { ok: false, motif: MOTIFS.quantite };
    }
    if (typeof montant === 'string' && /^\s*-/.test(montant)) {
        return { ok: false, motif: MOTIFS.montantNegatif };
    }
    const m = lireEntier(montant);
    if (m === null) {
        return { ok: false, motif: montant === '' || montant === null || montant === undefined ? MOTIFS.montant : MOTIFS.montantEntier };
    }
    return { ok: true, qty: quantite, montant: m };
}

/**
 * Le choix « Facture simple / normalisée » — copie de `ChoixFactureService::valider` (mêmes champs, mêmes motifs).
 *
 * @returns {{ok:true, choix:{facture_type:string, client_ifu:?string, client_nom_facture:?string, aib_taux:?string}}|{ok:false, champ:string, motif:string}}
 */
export function validerChoixFacture(donnees = {}) {
    let type = donnees.facture_type;
    type = typeof type === 'string' && type.trim() !== '' ? type.trim() : FACTURE_SIMPLE;

    if (type !== FACTURE_SIMPLE && type !== FACTURE_NORMALISEE) {
        return { ok: false, champ: 'facture_type', motif: MOTIFS.factureType };
    }
    if (type === FACTURE_SIMPLE) {
        return { ok: true, choix: { facture_type: type, client_ifu: null, client_nom_facture: null, aib_taux: null } };
    }

    const texte = (v) => (typeof v === 'string' || typeof v === 'number' ? String(v).trim() : '');
    const nom = texte(donnees.client_nom_facture);
    if (nom === '' || [...nom].length > NOM_FACTURE_MAX) {
        return { ok: false, champ: 'client_nom_facture', motif: MOTIFS.factureNom };
    }

    const ifu = texte(donnees.client_ifu).replace(/\s+/gu, '');
    if (ifu !== '' && !/^\d{13}$/.test(ifu)) {
        return { ok: false, champ: 'client_ifu', motif: MOTIFS.factureIfu };
    }

    const aib = donnees.aib_taux;
    if (typeof aib !== 'string' || !Object.hasOwn(AIB_TAUX, aib)) {
        return { ok: false, champ: 'aib_taux', motif: MOTIFS.factureAib };
    }

    return {
        ok: true,
        choix: { facture_type: type, client_ifu: ifu === '' ? null : ifu, client_nom_facture: nom, aib_taux: aib },
    };
}

const texteOuNull = (v) => (typeof v === 'string' && v.trim() !== '' ? v.trim() : null);

/** La modale « Livraison » : mode connu, frais numériques pour une livraison facturée, adresse et contact de 255 caractères au plus. */
export function validerLivraison(livraison = {}) {
    if (!livraison.concernee) {
        return { ok: true };
    }
    if (!Object.hasOwn(MODES_LIVRAISON, livraison.mode)) {
        return { ok: false, champ: 'delivery_mode', motif: MOTIFS.livraisonMode };
    }
    if (livraison.mode === 'facturee' && livraison.frais !== null && livraison.frais !== undefined && !Number.isFinite(livraison.frais)) {
        return { ok: false, champ: 'delivery_fee', motif: MOTIFS.livraisonFrais };
    }
    if ([...(livraison.adresse ?? '')].length > LIVRAISON_TEXTE_MAX) {
        return { ok: false, champ: 'delivery_address', motif: MOTIFS.livraisonAdresse };
    }
    if ([...(livraison.contact ?? '')].length > LIVRAISON_TEXTE_MAX) {
        return { ok: false, champ: 'delivery_contact', motif: MOTIFS.livraisonContact };
    }
    return { ok: true };
}

// ---------------------------------------------------------------------------------------------------------------
// La vente complète.
// ---------------------------------------------------------------------------------------------------------------

/**
 * Valide un panier et construit le FAIT « vente » tel que le serveur l'attend (mêmes clés que le poste Flutter).
 *
 * @param {object} entree
 * @param {{product_id:string, qty:number, montant:number}[]} entree.panier
 * @param {number} entree.remise  entier ≥ 0
 * @param {string} entree.modePaiement
 * @param {?string} entree.clientId
 * @param {?number} entree.especesRecues
 * @param {object} entree.facture  { facture_type, client_ifu, client_nom_facture, aib_taux }
 * @param {object} [entree.livraison]  { concernee, mode, frais, adresse, contact } — la modale « Livraison » (PWA-1b)
 * @param {string} entree.id  UUID généré par le navigateur (clé d'idempotence)
 * @param {string} entree.instant  ISO 8601 : l'instant de SAISIE (devient `sold_at` et `updated_at`)
 * @param {string} entree.deviceId  nom du jeton (« pwa-<uuid> »)
 * @returns {{ok:true, vente:object}|{ok:false, champ:string, motif:string}}
 */
export function construireVente(entree) {
    const { panier, remise = 0, modePaiement, clientId = null, especesRecues = null, facture = {}, livraison = {}, id, instant, deviceId } = entree;

    if (!Array.isArray(panier) || panier.length === 0) {
        return { ok: false, champ: 'panier', motif: MOTIFS.panierVide };
    }
    for (const ligne of panier) {
        if (!Number.isInteger(ligne.qty) || ligne.qty < 1) {
            return { ok: false, champ: 'panier', motif: MOTIFS.quantite };
        }
        if (!Number.isInteger(ligne.montant) || ligne.montant < 0) {
            return { ok: false, champ: 'panier', motif: MOTIFS.montantNegatif };
        }
    }
    if (!MODES_PAIEMENT.includes(modePaiement)) {
        return { ok: false, champ: 'payment_mode', motif: MOTIFS.modeInconnu };
    }
    if (modePaiement === 'credit' && !clientId) {
        return { ok: false, champ: 'customer_id', motif: MOTIFS.venteACredit };
    }
    if (modePaiement === 'avance' && !clientId) {
        return { ok: false, champ: 'customer_id', motif: MOTIFS.venteSurAvance };
    }
    if (!Number.isInteger(remise) || remise < 0) {
        return { ok: false, champ: 'discount', motif: Number.isInteger(remise) ? MOTIFS.remise : MOTIFS.remiseEntiere };
    }

    const lignes = panier.map((l) => ({
        product_id: l.product_id,
        lot_id: null,
        qty: l.qty,
        unit_price: prixUnitaire(l.montant, l.qty),
        manual_total_amount: l.montant,
    }));
    const sous = sousTotal(lignes);
    if (remise > sous) {
        return { ok: false, champ: 'discount', motif: MOTIFS.remiseTropGrande };
    }

    const choix = validerChoixFacture(facture);
    if (!choix.ok) {
        return choix;
    }

    const livraisonOk = validerLivraison(livraison);
    if (!livraisonOk.ok) {
        return livraisonOk;
    }
    const fraisRetenus = livraisonRetenue(livraison);

    const total = totalVente(lignes, remise, fraisRetenus);
    if (modePaiement === 'especes' && especesRecues !== null && especesRecues !== undefined && especesRecues < total) {
        return { ok: false, champ: 'cash_received', motif: MOTIFS.especesInsuffisantes };
    }

    return {
        ok: true,
        vente: {
            id,
            device_id: deviceId,
            sync_status: 'pending',
            customer_id: clientId || null,
            payment_mode: modePaiement,
            subtotal: sous,
            discount: remise,
            total,
            cash_received: modePaiement === 'especes' ? (especesRecues ?? total) : null,
            change_due: modePaiement === 'especes' ? monnaieARendre('especes', especesRecues ?? total, total) : null,
            status: 'validee',
            sold_at: instant,
            updated_at: instant,
            ...choix.choix,
            // PWA-1b — les colonnes de livraison de la caisse web ; le serveur RECALCULE les frais et le drapeau (jamais lus tels quels).
            delivery_mode: livraison.concernee ? livraison.mode : null,
            delivery_fee: fraisRetenus,
            delivery_in_total: fraisRetenus > 0,
            delivery_address: livraison.concernee ? (texteOuNull(livraison.adresse)) : null,
            delivery_contact: livraison.concernee ? (texteOuNull(livraison.contact)) : null,
            lines: lignes,
        },
    };
}
