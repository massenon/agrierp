/**
 * PWA-1 — BASE LOCALE (IndexedDB, schéma VERSIONNÉ avec migration). Jamais `localStorage` ni cache HTTP pour des données.
 *
 * Magasins (DB_VERSION = 2) :
 *   - `meta`         { cle, valeur }                     réglages de l'appareil (jeton chiffré, sel, curseur `server_time`…)
 *   - `referentiels` { table, tire_le, iv, d }           copie CHIFFRÉE du catalogue, des clients… tirés par /api/sync/pull
 *   - `ventes`       { id, sync_status, cree_le, synced_le, tentatives, iv, d }   FILE D'ENVOI, vente chiffrée
 *   - `journal`      { id (auto), le, iv, d }            journal des refus, avec le motif français du serveur   (v2)
 *
 * v1 : meta + referentiels + ventes.  v2 : + `journal` et l'index `par_statut` de `ventes` (comptage sans clé).
 * Le statut, les dates et les identifiants restent EN CLAIR (aucune donnée de la ferme) pour compter sans déverrouiller.
 *
 * Règles : une base plus RÉCENTE que l'application est refusée (message français, rien n'est supprimé) ; une migration
 * qui échoue annule sa transaction (la file existante est intacte) ; toute écriture n'est « faite » qu'à `oncomplete`.
 */

export const NOM_BASE = 'agrierp_hors_ligne';
export const DB_VERSION = 2;

export class ErreurBase extends Error {
    constructor(message, code = 'base') {
        super(message);
        this.name = 'ErreurBase';
        this.code = code;
    }
}

/** Étapes de migration : `MIGRATIONS[n]` fait passer de n-1 à n. Exportées pour l'essai de migration. */
export const MIGRATIONS = {
    1(db) {
        db.createObjectStore('meta', { keyPath: 'cle' });
        db.createObjectStore('referentiels', { keyPath: 'table' });
        db.createObjectStore('ventes', { keyPath: 'id' });
    },
    2(db, tx) {
        db.createObjectStore('journal', { keyPath: 'id', autoIncrement: true });
        tx.objectStore('ventes').createIndex('par_statut', 'sync_status');
    },
};

function motifErreur(e) {
    if (e && (e.name === 'QuotaExceededError' || e.code === 22)) {
        return new ErreurBase("Espace de stockage de l'appareil plein : libérez de la place, puis recommencez. La vente n'est PAS enregistrée.", 'quota');
    }
    if (e && e.name === 'VersionError') {
        return new ErreurBase("Les données de cet appareil viennent d'une version plus récente de l'application. Rechargez la page pour la mettre à jour ; rien n'a été supprimé.", 'version-recente');
    }
    return new ErreurBase(`Le stockage de l'appareil a refusé l'opération (${e?.name || 'erreur'}). La vente n'est PAS enregistrée.`, 'stockage');
}

const promesse = (req) => new Promise((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
});

/** Ouvre la base (migrations comprises). `versionCible` n'existe que pour l'essai « base plus ancienne / plus récente ». */
export function ouvrirBase({ idb = globalThis.indexedDB, nom = NOM_BASE, version = DB_VERSION, migrations = MIGRATIONS } = {}) {
    return new Promise((resolve, reject) => {
        if (!idb) {
            reject(new ErreurBase("Ce navigateur n'offre pas de stockage local (IndexedDB) : le mode hors ligne est indisponible ici.", 'indisponible'));
            return;
        }
        let requete;
        try {
            requete = idb.open(nom, version);
        } catch (e) {
            reject(motifErreur(e));
            return;
        }
        requete.onupgradeneeded = (evenement) => {
            const db = requete.result;
            const tx = requete.transaction;
            try {
                for (let v = evenement.oldVersion + 1; v <= (evenement.newVersion ?? version); v++) {
                    migrations[v](db, tx);
                }
            } catch (e) {
                tx.abort(); // la base garde son ancien état : la file n'est jamais supprimée
                reject(new ErreurBase(`Migration du stockage local impossible (${e.message}). Vos ventes non envoyées sont intactes : n'effacez rien et prévenez l'administrateur.`, 'migration'));
            }
        };
        requete.onsuccess = () => resolve(new BaseLocale(requete.result, { idb, nom }));
        requete.onerror = () => reject(requete.error && requete.error.name === 'VersionError' ? motifErreur(requete.error) : (requete.error?.name === 'AbortError' ? new ErreurBase('Migration du stockage local annulée.', 'migration') : motifErreur(requete.error)));
        requete.onblocked = () => reject(new ErreurBase("Le stockage local est utilisé par un autre onglet d'une version plus ancienne : fermez-le puis rechargez.", 'bloque'));
    });
}

export function supprimerBase({ idb = globalThis.indexedDB, nom = NOM_BASE } = {}) {
    return new Promise((resolve, reject) => {
        const r = idb.deleteDatabase(nom);
        r.onsuccess = () => resolve(true);
        r.onerror = () => reject(r.error);
        r.onblocked = () => resolve(false);
    });
}

export class BaseLocale {
    constructor(db, { idb, nom }) {
        this.db = db;
        this.idb = idb;
        this.nom = nom;
        db.onversionchange = () => db.close();
    }

    get version() {
        return this.db.version;
    }

    magasins() {
        return [...this.db.objectStoreNames];
    }

    /** Exécute `fn(tx)` dans UNE transaction ; ne rend qu'à `oncomplete` (écriture réellement durable) ou refuse. */
    transaction(noms, mode, fn) {
        return new Promise((resolve, reject) => {
            let tx;
            try {
                tx = this.db.transaction(noms, mode);
            } catch (e) {
                reject(motifErreur(e));
                return;
            }
            let resultat;
            tx.oncomplete = () => resolve(resultat);
            tx.onerror = () => reject(motifErreur(tx.error));
            tx.onabort = () => reject(motifErreur(tx.error));
            try {
                Promise.resolve(fn(tx)).then((r) => { resultat = r; }, (e) => { try { tx.abort(); } catch { /* déjà close */ } reject(motifErreur(e)); });
            } catch (e) {
                try { tx.abort(); } catch { /* déjà close */ }
                reject(motifErreur(e));
            }
        });
    }

    lire(magasin, cle) {
        return this.transaction([magasin], 'readonly', (tx) => promesse(tx.objectStore(magasin).get(cle)));
    }

    tout(magasin) {
        return this.transaction([magasin], 'readonly', (tx) => promesse(tx.objectStore(magasin).getAll()));
    }

    ecrire(magasin, valeur) {
        return this.transaction([magasin], 'readwrite', (tx) => promesse(tx.objectStore(magasin).put(valeur)));
    }

    ecrireTout(magasin, valeurs) {
        return this.transaction([magasin], 'readwrite', async (tx) => {
            const s = tx.objectStore(magasin);
            for (const v of valeurs) {
                await promesse(s.put(v));
            }
        });
    }

    supprimer(magasin, cle) {
        return this.transaction([magasin], 'readwrite', (tx) => promesse(tx.objectStore(magasin).delete(cle)));
    }

    vider(magasins = this.magasins()) {
        return this.transaction(magasins, 'readwrite', async (tx) => {
            for (const m of magasins) {
                await promesse(tx.objectStore(m).clear());
            }
        });
    }

    async meta(cle) {
        return (await this.lire('meta', cle))?.valeur;
    }

    poserMeta(cle, valeur) {
        return this.ecrire('meta', { cle, valeur });
    }

    /** Comptage par statut SANS clé (le statut est en clair). */
    async compter() {
        const lignes = await this.tout('ventes');
        const c = { pending: 0, conflict: 0, synced: 0 };
        for (const l of lignes) {
            c[l.sync_status] = (c[l.sync_status] ?? 0) + 1;
        }
        return c;
    }

    fermer() {
        this.db.close();
    }
}
