/**
 * PWA-1 — CAISSE HORS LIGNE : le client JavaScript de la page STATIQUE `public/caisse-hors-ligne.html`.
 *
 * Il lit TOUT dans IndexedDB (chiffré, sous la clé du PIN) et n'écrit que des FAITS (ventes `pending`). Aucune règle de
 * stock, de numérotation ni de comptabilité : le serveur rejoue chaque vente comme le push d'un poste. Textes en français,
 * libellés copiés de la caisse du web. Le DOM est construit avec `textContent` (jamais `innerHTML` avec des données).
 */

import { ouvrirBase, ErreurBase } from './base-locale.js';
import { etatAppareil, deverrouiller, desactiver, purgerLocal, lireMarqueur, noterEnAttente, MARQUEUR_ACTIVE, MARQUEUR_EN_ATTENTE } from './appairage.js';
import { ErreurPin, dechiffrer } from './coffre.js';
import { ajouterVente, lister, remettreEnFile, abandonner } from './file-envoi.js';
import { validerClient, ajouterClient, clientsEnAttente, clientsVisibles } from './clients-hors-ligne.js';
import { creerSynchro } from './synchro.js';
import { etatAffiche, heureDuServeur, ageDuTirageEnJours } from './etat.js';
import { filtrerProduits, etatTuile, fourchetteDePrix, messageAgeTirage, messageBandeauPrix, messageConfirmationVente, niveauPrixPerimes, NIVEAUX_PRIX, LIBELLES_STATUT } from './catalogue.js';
import { construireVente, validerLigne, validerChoixFacture, validerLivraison, livraisonRetenue, lireNombre, sousTotal, totalVente, monnaieARendre, tvaIncluse, formaterFcfa, lireEntier, MODES_LIVRAISON } from './calculs-caisse.js';
import { decider, DUREE_PAR_DEFAUT } from '../verrou-logique.js';

const $ = (id) => document.getElementById(id);
const h = (tag, attrs = {}, ...enfants) => {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) {
        if (k === 'class') e.className = v; else if (k.startsWith('on')) e.addEventListener(k.slice(2), v); else if (v !== false && v !== null) e.setAttribute(k, v === true ? '' : v);
    }
    for (const c of enfants.flat()) if (c !== null && c !== undefined) e.append(c.nodeType ? c : document.createTextNode(String(c)));
    return e;
};

const app = {
    base: null, ctx: null, jeton: null, appareil: null, synchro: null,
    produits: [], categories: [], clients: [], entreprise: null,
    livraison: { concernee: false, mode: 'gratuite', frais: null, adresse: '', contact: '' },
    panier: [], produitEnCours: null, facture: { facture_type: 'simple', client_ifu: '', client_nom_facture: '', aib_taux: '5%' },
    enLigne: navigator.onLine, enCours: false, suspendu: false,
    lectureSeule: false, derniereActivite: Date.now(), minutesVerrou: DUREE_PAR_DEFAUT, requetes: 0,
    minuterieReessai: null, derniereSynchro: null, serverTime: null, decalage: 0,
};

// ------------------------------------------------------------------------------------------------ messages

function avis(texte, ton = 'neutre', delai = 0) {
    const b = $('avis');
    b.textContent = texte;
    b.className = `bandeau ${ton}`;
    b.hidden = texte === '';
    if (delai) setTimeout(() => { if (b.textContent === texte) b.hidden = true; }, delai);
}

function montrer(ecran) {
    for (const id of ['ecran-verrou', 'ecran-inactif']) $(id).hidden = id !== ecran;
    $('contenu').hidden = ecran !== null;
}

// ----------------------------------------------------------------------------------------------- démarrage

async function demarrer() {
    enregistrerServiceWorker();
    let base;
    try {
        base = await ouvrirBase();
    } catch (e) {
        $('inactif-titre').textContent = 'Stockage local indisponible';
        $('inactif-texte').textContent = e instanceof ErreurBase ? e.message : String(e);
        montrer('ecran-inactif');
        return;
    }
    app.base = base;
    const etat = await etatAppareil(base);

    if (!etat.active) {
        // A7 : le navigateur a-t-il purgé le stockage pendant que l'application était fermée ?
        if (lireMarqueur(MARQUEUR_ACTIVE) === '1') {
            const n = Number(lireMarqueur(MARQUEUR_EN_ATTENTE) ?? 0);
            $('inactif-titre').textContent = 'Les données de cet appareil ont disparu';
            $('inactif-texte').textContent = `Les saisies non envoyées de cet appareil ont disparu : ${n} vente(s) perdue(s) possible(s). Le navigateur a probablement vidé son stockage. Réactivez le mode hors ligne en ligne, puis vérifiez l'historique des ventes dans LogiAgriERP.`;
            try { localStorage.removeItem(MARQUEUR_ACTIVE); } catch { /* ignoré */ }
        }
        montrer('ecran-inactif');
        return;
    }
    app.appareil = etat;
    app.suspendu = etat.suspendu;
    $('nom-utilisateur').textContent = etat.utilisateur?.name ? `— ${etat.utilisateur.name}` : '';
    await verrouillerEcran(`Saisissez votre PIN pour ouvrir la caisse hors ligne.`);
    poserEcouteursGeneraux();
    await surveillerOnglets();
}

async function verrouillerEcran(texte) {
    app.ctx = null; app.jeton = null; app.synchro = null;
    $('verrou-texte').textContent = texte;
    $('erreur-pin').textContent = '';
    $('champ-pin').value = '';
    montrer('ecran-verrou');
    setTimeout(() => $('champ-pin').focus(), 50);
}

$('form-pin').addEventListener('submit', async (ev) => {
    ev.preventDefault();
    $('erreur-pin').textContent = '';
    try {
        const { cle, jeton } = await deverrouiller(app.base, $('champ-pin').value);
        app.ctx = { base: app.base, cle }; app.jeton = jeton;
        app.minutesVerrou = (await app.base.meta('verrou_minutes')) ?? DUREE_PAR_DEFAUT;
        app.derniereActivite = Date.now();
        montrer(null);
        await ouvrirCaisse();
    } catch (e) {
        $('champ-pin').value = '';
        if (e instanceof ErreurPin) {
            $('erreur-pin').textContent = e.message;
            if (/effacées/.test(e.message)) { $('inactif-titre').textContent = 'Appareil réinitialisé'; $('inactif-texte').textContent = e.message; montrer('ecran-inactif'); }
        } else {
            $('erreur-pin').textContent = e?.message ?? 'Déverrouillage impossible.';
        }
    }
});

async function ouvrirCaisse() {
    await chargerReferentiels();
    app.synchro = creerSynchro({
        base: app.base, cle: app.ctx.cle, jeton: app.jeton, deviceName: app.appareil.deviceName,
        avecVerrou: navigator.locks ? (fn) => navigator.locks.request('agrierp-synchro', { ifAvailable: true }, (v) => (v ? fn() : { statut: 'deja_en_cours' })) : null,
    });
    await app.synchro.charger();
    app.suspendu = app.synchro.etat().suspendu;
    await dessiner();
    if (app.suspendu) avis('Session expirée ou appareil révoqué : reconnectez-vous (Mode hors ligne) pour reprendre la synchronisation. Vos ventes restent sur cet appareil.', 'erreur');
    if (!app.appareil.persistant) avis('Le navigateur n\'a pas garanti la conservation durable des données de cet appareil : synchronisez souvent.', 'avert');
    lancerSynchro({ manuel: false });
}

async function chargerReferentiels() {
    const lire = async (t) => { const l = await app.base.lire('referentiels', t); return l ? dechiffrer(app.ctx.cle, l) : []; };
    app.produits = await lire('products');
    app.categories = await lire('product_categories');
    // PWA-1b : les clients du tirage, puis ceux créés sur cet appareil et pas encore acquittés.
    app.clients = clientsVisibles(await lire('customers'), await clientsEnAttente(app.ctx));
    app.entreprise = (await lire('company_settings'))[0] ?? null;
    app.serverTime = (await app.base.meta('curseur')) ?? null;
    app.decalage = (await app.base.meta('decalage_horloge_ms')) ?? 0;
    app.derniereSynchro = heureDuServeur(await app.base.meta('derniere_synchro'));
}

// ----------------------------------------------------------------------------------------------- affichage

async function dessiner() {
    dessinerCatalogue();
    dessinerPanier();
    await dessinerVentes();
    await dessinerEtat();
}

async function dessinerEtat() {
    const c = await app.base.compter();
    noterEnAttente(c.pending + c.conflict);
    const e = etatAffiche({ enLigne: app.enLigne, enCours: app.enCours, suspendu: app.suspendu, pending: c.pending, conflict: c.conflict, derniereSynchro: app.derniereSynchro });
    const p = $('etat-synchro');
    p.textContent = e.libelle;
    p.className = `pastille ${e.ton}`;
    $('btn-synchroniser').disabled = app.enCours;
}

/** Âge du dernier tirage RÉUSSI (curseur gardé en base locale), horloge corrigée du décalage serveur. */
function agePrix() {
    return ageDuTirageEnJours(app.serverTime, Date.now(), app.decalage);
}

/** Demande la confirmation « prix périmés » ; rend true si l'opérateur confirme quand même. */
function confirmerPrixPerimes(jours) {
    return new Promise((resolu) => {
        const dlg = $('dlg-prix-perimes');
        $('prix-perimes-texte').textContent = messageConfirmationVente(jours);
        const fin = (valeur) => { $('prix-perimes-confirmer').onclick = null; $('prix-perimes-annuler').onclick = null; dlg.onclose = null; if (dlg.open) dlg.close(); resolu(valeur); };
        $('prix-perimes-confirmer').onclick = () => fin(true);
        $('prix-perimes-annuler').onclick = () => fin(false);
        dlg.onclose = () => fin(false); // Échap = Annuler
        dlg.showModal();
    });
}

function dessinerCatalogue() {
    const select = $('categorie');
    const courante = select.value;
    select.replaceChildren(h('option', { value: '' }, 'Tous'), ...app.categories.filter((c) => c.is_active !== false).map((c) => h('option', { value: c.id }, c.label)));
    select.value = courante;
    const liste = filtrerProduits(app.produits, $('recherche').value, select.value);
    $('produits').replaceChildren(...liste.map((p) => {
        const t = etatTuile(p);
        return h('button', { type: 'button', class: 'produit', disabled: !t.vendable || app.lectureSeule, 'data-id': p.id, onclick: () => ouvrirPiece(p) },
            h('b', {}, p.name), h('small', {}, [fourchetteDePrix(p), p.stock_qty !== undefined ? `Stock : ${Number(p.stock_qty)} ${p.unit ?? ''}` : ''].filter(Boolean).join(' · ')), t.note ? h('small', {}, t.note) : null);
    }));
    $('produits-vide').hidden = liste.length > 0;
    const jours = agePrix();
    $('age-tirage').textContent = messageAgeTirage(jours);
    // CONF-3 (DV-21) : prix périmés = avertissement (3 j) puis avertissement fort (7 j) ; jamais un refus de vente.
    const texte = messageBandeauPrix(jours);
    const bandeau = $('bandeau-prix');
    bandeau.textContent = texte;
    bandeau.hidden = texte === '';
    bandeau.className = `bandeau ${niveauPrixPerimes(jours) === NIVEAUX_PRIX.confirmation ? 'erreur' : 'avert'}`;
    bandeau.dataset.niveau = niveauPrixPerimes(jours);
    // client
    const cc = $('client').value;
    $('client').replaceChildren(h('option', { value: '' }, 'Client Anonyme'), ...app.clients.map((c) => h('option', { value: c.id }, c.name)));
    $('client').value = cc;
    // facture : proposée seulement quand le module MeCeF est actif (comme la caisse du web)
    $('bloc-facture').hidden = !app.entreprise?.mecef_actif;
}

function lignesCalcul() {
    return app.panier.map((l) => ({ manual_total_amount: l.montant, tva_rate: Number(app.produits.find((p) => p.id === l.product_id)?.tva_rate ?? 0) }));
}

function dessinerPanier() {
    $('panier-vide').hidden = app.panier.length > 0;
    $('table-panier').hidden = app.panier.length === 0;
    $('corps-panier').replaceChildren(...app.panier.map((l, i) => h('tr', {},
        h('td', { 'data-label': 'Produit' }, l.name), h('td', { class: 'num', 'data-label': 'Qté' }, String(l.qty)), h('td', { class: 'num', 'data-label': 'Montant' }, formaterFcfa(l.montant)),
        h('td', { 'data-label': '' }, h('button', { type: 'button', class: 'btn danger', 'aria-label': 'Retirer du panier', onclick: () => { app.panier.splice(i, 1); dessinerPanier(); } }, h('span', { class: 'material-symbols-outlined' }, 'close'))))));
    const remise = lireEntier($('remise').value || '0') ?? 0;
    const lignes = lignesCalcul();
    const livraison = livraisonRetenue(app.livraison);
    const total = totalVente(lignes, remise, livraison);
    $('ligne-livraison').hidden = livraison === 0;
    $('frais-livraison').textContent = formaterFcfa(livraison);
    $('resume-livraison').textContent = app.livraison.concernee ? MODES_LIVRAISON[app.livraison.mode] ?? '' : '';
    $('sous-total').textContent = formaterFcfa(sousTotal(lignes));
    $('total').textContent = formaterFcfa(total);
    $('tva').textContent = formaterFcfa(tvaIncluse(lignes, remise > sousTotal(lignes) ? 0 : remise, Boolean(app.entreprise?.tva_enabled)).tva);
    const especes = $('mode').value === 'especes';
    $('bloc-especes').hidden = !especes;
    $('ligne-monnaie').hidden = !especes;
    $('monnaie').textContent = formaterFcfa(monnaieARendre($('mode').value, lireEntier($('recu').value || ''), total));
    $('btn-facture').hidden = $('facture-type').value !== 'normalisee';
    $('btn-valider').disabled = app.lectureSeule;
}

const heureLocale = (iso) => { const d = new Date(iso); return Number.isNaN(d.getTime()) ? '' : d.toLocaleString('fr-FR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }); };

async function dessinerVentes() {
    const ventes = (await lister(app.ctx)).reverse().slice(0, 50);
    $('ventes-vide').hidden = ventes.length > 0;
    $('table-ventes').hidden = ventes.length === 0;
    $('corps-ventes').replaceChildren(...ventes.map((l) => h('tr', { 'data-id': l.id, 'data-statut': l.sync_status },
        h('td', { 'data-label': 'Heure' }, heureLocale(l.vente.sold_at)),
        h('td', { class: 'num', 'data-label': 'Total' }, formaterFcfa(l.vente.total)),
        h('td', { 'data-label': 'Statut' }, h('span', { class: `statut ${l.sync_status}` }, LIBELLES_STATUT[l.sync_status] ?? l.sync_status)),
        h('td', { 'data-label': 'Motif' }, l.motif ?? ''),
        h('td', { 'data-label': '' }, l.sync_status === 'conflict' ? h('span', { class: 'groupe' },
            h('button', { type: 'button', class: 'btn', onclick: async () => { await remettreEnFile(app.ctx, l.id); await dessiner(); lancerSynchro({ manuel: true }); } }, 'Remettre en file'),
            h('button', { type: 'button', class: 'btn danger', onclick: () => demanderAbandon(l) }, 'Abandonner')) : null))));
}

function demanderAbandon(l) {
    $('abandon-texte').textContent = `La vente de ${formaterFcfa(l.vente.total)} refusée par le serveur (« ${l.motif} ») sera supprimée de cet appareil. Elle n'existera nulle part.`;
    $('abandon-confirmer').onclick = async () => { await abandonner(app.ctx, l.id); $('dlg-abandon').close(); await dessiner(); };
    $('dlg-abandon').showModal();
}

// ------------------------------------------------------------------------------------------------- saisie

function ouvrirPiece(p) {
    app.produitEnCours = p;
    $('piece-produit').textContent = p.name;
    $('piece-qte').value = '1';
    $('piece-montant').value = '';
    $('piece-erreur').textContent = '';
    $('dlg-piece').showModal();
}

$('piece-ajouter').addEventListener('click', () => {
    const r = validerLigne({ produit: app.produitEnCours, qty: $('piece-qte').value, montant: $('piece-montant').value });
    if (!r.ok) { $('piece-erreur').textContent = r.motif; return; }
    app.panier.push({ product_id: app.produitEnCours.id, name: app.produitEnCours.name, qty: r.qty, montant: r.montant });
    $('dlg-piece').close();
    dessinerPanier();
});

for (const b of document.querySelectorAll('[data-fermer]')) b.addEventListener('click', () => $(b.dataset.fermer).close());
for (const id of ['recherche', 'categorie']) $(id).addEventListener('input', dessinerCatalogue);
for (const id of ['remise', 'recu', 'mode']) $(id).addEventListener('input', dessinerPanier);
$('facture-type').addEventListener('change', () => { dessinerPanier(); if ($('facture-type').value === 'normalisee') ouvrirFacture(); });
$('btn-facture').addEventListener('click', ouvrirFacture);
$('client').addEventListener('change', () => { const c = app.clients.find((x) => x.id === $('client').value); if (c && $('facture-type').value === 'normalisee') { app.facture.client_nom_facture = c.name; app.facture.client_ifu = c.ifu ?? ''; } });

function ouvrirFacture() {
    const c = app.clients.find((x) => x.id === $('client').value);
    if (c && app.facture.client_nom_facture === '') { app.facture.client_nom_facture = c.name; app.facture.client_ifu = c.ifu ?? ''; }
    $('facture-nom').value = app.facture.client_nom_facture; $('facture-ifu').value = app.facture.client_ifu; $('facture-aib').value = app.facture.aib_taux;
    for (const id of ['erreur-facture-nom', 'erreur-facture-ifu', 'erreur-facture-aib']) $(id).textContent = '';
    $('dlg-facture').showModal();
}
$('facture-annuler').addEventListener('click', () => { $('facture-type').value = 'simple'; $('dlg-facture').close(); dessinerPanier(); });
$('facture-valider').addEventListener('click', () => {
    const donnees = { facture_type: 'normalisee', client_nom_facture: $('facture-nom').value, client_ifu: $('facture-ifu').value, aib_taux: $('facture-aib').value };
    const r = validerChoixFacture(donnees);
    for (const id of ['erreur-facture-nom', 'erreur-facture-ifu', 'erreur-facture-aib']) $(id).textContent = '';
    if (!r.ok) { $({ client_nom_facture: 'erreur-facture-nom', client_ifu: 'erreur-facture-ifu', aib_taux: 'erreur-facture-aib' }[r.champ]).textContent = r.motif; return; }
    app.facture = { facture_type: 'normalisee', client_nom_facture: donnees.client_nom_facture, client_ifu: donnees.client_ifu, aib_taux: donnees.aib_taux };
    $('dlg-facture').close();
});

$('btn-valider').addEventListener('click', async () => {
    $('erreur-vente').textContent = ''; $('erreur-client').textContent = '';
    if (app.lectureSeule) return;
    const decalage = (await app.base.meta('decalage_horloge_ms')) ?? 0;
    const type = $('bloc-facture').hidden ? 'simple' : $('facture-type').value;
    const r = construireVente({
        panier: app.panier, remise: lireEntier($('remise').value || '0') ?? -1, modePaiement: $('mode').value, clientId: $('client').value || null, livraison: app.livraison,
        especesRecues: $('mode').value === 'especes' && $('recu').value !== '' ? lireEntier($('recu').value) : null,
        facture: type === 'normalisee' ? { ...app.facture, facture_type: 'normalisee' } : { facture_type: 'simple' },
        id: crypto.randomUUID(), instant: new Date(Date.now() + decalage).toISOString(), deviceId: app.appareil.deviceName,
    });
    if (!r.ok) {
        if (r.champ === 'customer_id') $('erreur-client').textContent = r.motif; else $('erreur-vente').textContent = r.motif;
        if (r.champ.startsWith('delivery_')) ouvrirLivraison(r.motif);
        if (['client_nom_facture', 'client_ifu', 'aib_taux'].includes(r.champ)) ouvrirFacture();
        return;
    }
    // CONF-3 (DV-21) : à partir de 7 jours sans tirage, confirmation explicite avant CHAQUE vente (jamais un refus : le serveur reste l'autorité).
    app.decalage = (await app.base.meta('decalage_horloge_ms')) ?? 0;
    const joursPrix = agePrix();
    if (niveauPrixPerimes(joursPrix) === NIVEAUX_PRIX.confirmation && !(await confirmerPrixPerimes(joursPrix))) return; // annulé : le panier est gardé
    try {
        await ajouterVente(app.ctx, r.vente); // ne rend qu'une fois l'écriture DURABLE
    } catch (e) {
        $('erreur-vente').textContent = e?.message ?? "Le stockage de l'appareil a refusé la vente : elle n'est PAS enregistrée.";
        return; // refus de valider : le panier est gardé
    }
    app.panier = []; $('remise').value = '0'; $('recu').value = ''; $('client').value = ''; $('facture-type').value = 'simple';
    app.livraison = { concernee: false, mode: 'gratuite', frais: null, adresse: '', contact: '' };
    app.facture = { facture_type: 'simple', client_ifu: '', client_nom_facture: '', aib_taux: '5%' };
    avis(`Vente enregistrée sur cet appareil (${formaterFcfa(r.vente.total)}) — pas encore envoyée.`, 'info', 6000);
    demanderSynchroEnArrierePlan();
    await dessiner();
    lancerSynchro({ manuel: false });
});

// ------------------------------------------------------------------------------- livraison et client (PWA-1b)

function ouvrirLivraison(motif = '') {
    const l = app.livraison;
    $('liv-concernee').checked = l.concernee; $('liv-mode').value = l.mode; $('liv-frais').value = l.frais ?? ''; $('liv-adresse').value = l.adresse; $('liv-contact').value = l.contact;
    $('erreur-livraison').textContent = motif;
    majChampsLivraison();
    if (!$('dlg-livraison').open) $('dlg-livraison').showModal();
}
function majChampsLivraison() {
    $('liv-champs').hidden = !$('liv-concernee').checked;
    $('liv-frais').hidden = $('liv-mode').value !== 'facturee';
}
$('btn-livraison').addEventListener('click', () => ouvrirLivraison());
$('liv-concernee').addEventListener('change', majChampsLivraison);
$('liv-mode').addEventListener('change', majChampsLivraison);
$('liv-valider').addEventListener('click', () => {
    const l = { concernee: $('liv-concernee').checked, mode: $('liv-mode').value, frais: $('liv-frais').value === '' ? null : lireNombre($('liv-frais').value), adresse: $('liv-adresse').value, contact: $('liv-contact').value };
    if ($('liv-frais').value !== '' && l.frais === null) l.frais = Number.NaN; // saisie illisible : refusée par validerLivraison
    const r = validerLivraison(l);
    if (!r.ok) { $('erreur-livraison').textContent = r.motif; return; }
    app.livraison = l;
    $('dlg-livraison').close();
    dessinerPanier();
});

$('btn-nouveau-client').addEventListener('click', () => {
    for (const id of ['client-nom', 'client-tel', 'client-ifu']) $(id).value = '';
    for (const id of ['erreur-client-nom', 'erreur-client-tel', 'erreur-client-ifu']) $(id).textContent = '';
    $('dlg-client').showModal();
});
$('client-enregistrer').addEventListener('click', async () => {
    for (const id of ['erreur-client-nom', 'erreur-client-tel', 'erreur-client-ifu']) $(id).textContent = '';
    const r = validerClient({ name: $('client-nom').value, phone: $('client-tel').value, ifu: $('client-ifu').value });
    if (!r.ok) { $({ name: 'erreur-client-nom', phone: 'erreur-client-tel', ifu: 'erreur-client-ifu' }[r.champ]).textContent = r.motif; return; }
    const decalage = (await app.base.meta('decalage_horloge_ms')) ?? 0;
    let client;
    try {
        client = await ajouterClient(app.ctx, { id: crypto.randomUUID(), valeurs: r.valeurs, instant: new Date(Date.now() + decalage).toISOString(), deviceId: app.appareil.deviceName });
    } catch (e) {
        $('erreur-client-nom').textContent = e?.message ?? "Le stockage de l'appareil a refusé le client : il n'est PAS créé.";
        return;
    }
    $('dlg-client').close();
    await chargerReferentiels();
    dessinerCatalogue();
    $('client').value = client.id;
    avis('Client ajouté sur cet appareil — il sera envoyé au serveur à la synchronisation.', 'info', 6000);
    lancerSynchro({ manuel: false });
});

// ---------------------------------------------------------------------------------------- synchronisation

async function sonder() {
    try {
        const r = await fetch('/up', { cache: 'no-store', credentials: 'omit' });
        return r.ok;
    } catch { return false; }
}

async function demanderSynchroEnArrierePlan() {
    try { const reg = await navigator.serviceWorker?.ready; await reg?.sync?.register('sync-file-envoi'); } catch { /* repli : online, retour au premier plan, minuterie, bouton */ }
}

async function lancerSynchro({ manuel }) {
    if (!app.ctx || !app.synchro || app.lectureSeule) return;
    if (!navigator.onLine || !(await sonder())) { app.enLigne = false; await dessinerEtat(); planifier(30_000); return; }
    app.enLigne = true; app.enCours = true; app.requetes++;
    await dessinerEtat();
    let r;
    try {
        r = await app.synchro.synchroniser({ manuel });
    } catch (e) {
        r = { statut: 'erreur', message: e?.message ?? 'Synchronisation impossible.' };
    }
    app.requetes--; app.enCours = false;
    if (!app.ctx) return; // verrouillée entre-temps
    if (r.statut === 'ok') { app.suspendu = false; await chargerReferentiels(); avis(r.message, 'info', 6000); }
    else if (r.statut === 'suspendu') { app.suspendu = true; avis(r.message, 'erreur'); }
    else if (r.statut === 'hors_ligne') { app.enLigne = false; avis(r.message, 'neutre'); if (r.prochainEssaiMs) planifier(r.prochainEssaiMs); }
    else if (r.statut === 'erreur' || r.statut === 'refus') { avis(r.message, 'avert'); if (r.prochainEssaiMs) planifier(r.prochainEssaiMs); }
    else if (r.statut === 'deja_en_cours') { /* rien */ }
    await dessiner();
}

function planifier(ms) {
    clearTimeout(app.minuterieReessai);
    app.minuterieReessai = setTimeout(() => lancerSynchro({ manuel: false }), ms);
}

$('btn-synchroniser').addEventListener('click', async () => {
    if (app.suspendu) { try { await app.synchro.reprendre(); app.suspendu = false; } catch { /* ignoré */ } }
    lancerSynchro({ manuel: true });
});

let antiRebond = null;
function poserEcouteursGeneraux() {
    window.addEventListener('online', () => { app.enLigne = true; clearTimeout(antiRebond); antiRebond = setTimeout(() => lancerSynchro({ manuel: false }), 2000); dessinerEtat?.().catch(() => {}); });
    window.addEventListener('offline', () => { app.enLigne = false; if (app.ctx) dessinerEtat().catch(() => {}); });
    document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') lancerSynchro({ manuel: false }); });
    setInterval(() => lancerSynchro({ manuel: false }), 5 * 60_000);
    navigator.serviceWorker?.addEventListener('message', (ev) => { if (ev.data?.type === 'SYNCHRONISER') lancerSynchro({ manuel: false }); });
    for (const n of ['pointerdown', 'keydown', 'touchstart', 'click']) window.addEventListener(n, () => { app.derniereActivite = Date.now(); }, { passive: true });
    setInterval(() => {
        if (!app.ctx) return;
        const d = decider({ maintenant: Date.now(), derniereActivite: app.derniereActivite, minutes: app.minutesVerrou, requetesEnCours: app.requetes });
        if (d === 'verrouiller') verrouillerEcran('Application verrouillée après inactivité. Saisissez votre PIN.');
    }, 5000);
    $('btn-verrouiller').addEventListener('click', () => verrouillerEcran('Application verrouillée. Saisissez votre PIN.'));
}

// ---------------------------------------------------------------------------------- onglets, mises à jour

async function surveillerOnglets() {
    if (!navigator.locks) return;
    navigator.locks.request('agrierp-caisse-maitre', { ifAvailable: true }, (v) => {
        if (v) return new Promise(() => {}); // maître : tient le verrou tant que la page vit
        app.lectureSeule = true; $('avis-onglet').hidden = false;
        $('btn-valider').disabled = true;
        return undefined;
    });
}

function enregistrerServiceWorker() {
    if (!('serviceWorker' in navigator)) return;
    navigator.serviceWorker.register('/sw.js', { scope: '/' }).catch(() => {});
    let premiere = !navigator.serviceWorker.controller;
    navigator.serviceWorker.addEventListener('controllerchange', () => { if (premiere) { premiere = false; return; } $('avis-maj').hidden = false; });
}

// -------------------------------------------------------------------------------------------- déconnexion

$('btn-deconnecter').addEventListener('click', async () => {
    const c = await app.base.compter();
    const n = c.pending + c.conflict;
    $('deco-erreur').textContent = '';
    $('deco-n').value = '';
    $('deco-abandon').hidden = n === 0;
    $('deco-envoyer').hidden = n === 0;
    $('deco-texte').textContent = n === 0
        ? 'Les données de cet appareil (catalogue, clients, jeton) seront effacées. Aucune vente n\'est en attente.'
        : `${n} vente(s) ne sont pas encore envoyées au serveur. Envoyez-les d'abord, ou abandonnez-les explicitement : elles seraient perdues.`;
    $('deco-confirmer').textContent = n === 0 ? 'Déconnecter' : 'Abandonner ces ventes et déconnecter';
    $('deco-confirmer').dataset.n = String(n);
    $('dlg-deconnexion').showModal();
});
$('deco-envoyer').addEventListener('click', async () => {
    $('deco-erreur').textContent = 'Envoi en cours…';
    await lancerSynchro({ manuel: true });
    const c = await app.base.compter();
    if (c.pending + c.conflict === 0) { $('deco-erreur').textContent = ''; $('deco-confirmer').click(); }
    else $('deco-erreur').textContent = `Il reste ${c.pending + c.conflict} vente(s) non envoyée(s) (hors ligne ou refusées). Rien n'a été effacé.`;
});
$('deco-confirmer').addEventListener('click', async () => {
    const n = Number($('deco-confirmer').dataset.n ?? 0);
    const c = await app.base.compter();
    const reel = c.pending + c.conflict;
    if (reel > 0 && Number($('deco-n').value) !== reel) { $('deco-erreur').textContent = `Saisissez le nombre exact de ventes à abandonner (${reel}).`; return; }
    void n;
    await desactiver({ base: app.base, jeton: app.jeton });
    $('dlg-deconnexion').close();
    app.ctx = null; app.jeton = null;
    $('inactif-titre').textContent = 'Appareil déconnecté';
    $('inactif-texte').textContent = 'Les données locales de cet appareil ont été effacées.';
    montrer('ecran-inactif');
});

demarrer().catch((e) => { $('inactif-titre').textContent = 'Erreur'; $('inactif-texte').textContent = e?.message ?? String(e); montrer('ecran-inactif'); });
