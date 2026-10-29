# Plan type : synchronisation multi-postes hors ligne (web + postes) — à reprendre dans un autre projet

Tiré du code réel d'AgriERP (Laravel 12 + Flutter/Drift). Chaque règle ci-dessous a coûté un défaut réel ; les fichiers
cités sont les références à relire. Tout est adaptable à une autre pile (le serveur peut être Node, Django…, le poste
Electron, Android…) : ce sont les **règles**, pas les frameworks, qui comptent.

## 1. Architecture en une phrase

Le **serveur est la vérité**. Chaque **poste** garde une copie locale (SQLite) où il travaille **hors ligne** ; il
**envoie** ses saisies (`push`) et **reçoit** les changements des autres (`pull`). Le poste écrit un **fait** ou une
**demande** ; le serveur le rejoue par le **même code** que l'écran web, et seul le serveur calcule (stock, comptabilité).

## 2. Identité : appairage et plusieurs postes

- **Identifiant du poste** : un UUID tiré UNE fois à la première ouverture, gardé en base locale, jamais régénéré
  (`ParametresPoste`, clé `poste.identifiant`). Une constante partagée rendrait deux postes indiscernables.
- **Adresse du serveur** : réglage du poste (normalisée : schéma ajouté, `/` final retiré), modifiable dans
  Paramètres > Appairage ; un changement exige un redémarrage et le dit.
- **Appairage = connexion** : `POST /api/auth/login {identifiant, password, device_name}`. Le serveur crée un **jeton
  nommé d'après le poste** (`device_name`) ; **un seul jeton actif par nom** (se reconnecter révoque l'ancien).
  Le mot de passe n'est jamais gardé par le poste ; après connexion il garde le jeton, et un **PIN local** (PBKDF2)
  rouvre la session hors ligne.
- **Un jeton par poste = on sait qui parle** : la supervision liste les postes (jeton, dernier tirage, retard),
  l'administrateur peut **révoquer** un poste (`postes/revoquer`) : son jeton meurt, il reçoit 401, suspend sa
  synchronisation automatique et redemande une connexion.
- Compte désactivé ou mot de passe temporaire : le serveur refuse (403 avec motif français) tout sauf le changement
  de mot de passe.

## 3. Envoyer / recevoir (le cœur)

Ordre **toujours** : **pull d'abord, push ensuite** (sinon le serveur travaille sur des référentiels que le poste n'a
pas encore reçus). Déclencheurs : à l'ouverture, toutes les N secondes, après un geste, à la fermeture, sur demande.

**Pull** (`GET /sync/pull?since=…&page=…`)
- Curseur = `server_time` rendu par le SERVEUR (jamais l'horloge du poste : trop lente = on re-reçoit tout, trop
  rapide = on saute des lignes). Il n'avance qu'après la DERNIÈRE page.
- Paginé : petites tables entières, tables d'historique découpées par pièce (jamais une ligne sans sa pièce).
- Le serveur ne sert que les tables que le compte a le droit de lire (matrice rôle → tables, testée contre les
  écrans du poste).
- Chaque page est absorbée dans UNE transaction locale. **Absorbeurs stricts** : une ligne incohérente est REFUSÉE
  (pas lissée) ; une table « mixte » (saisie au poste ET tirée) n'écrase jamais une ligne `pending`/`conflict`.

**Push** (`POST /sync/push`) — un lot de tables dans l'ordre des dépendances (clients avant ventes…).
- Tout le lot dans **une transaction** serveur, rejouée 3 fois sur interblocage.
- **Idempotent par l'UUID du poste** : renvoyer ce que le serveur a déjà ne fait rien (réponse perdue après
  traitement = cas normal).
- Réponse **table par table** : ids acceptés ET refusés avec le motif en français.
- Le poste marque `synced` **seulement après l'accusé** ; un refus devient `conflict` (+ motif) et est relancé ou
  abandonné par l'utilisateur ; jamais d'échec silencieux. Hors ligne n'est PAS une erreur.

**Statuts locaux** : `pending` (à envoyer) · `synced` · `conflict` (refusé). Colonnes de synchro communes :
`id` (UUID), `device_id`, `sync_status`, `updated_at` (instant de SAISIE, pas d'envoi : un poste hors ligne 3 jours
ne doit pas battre une saisie plus récente faite ailleurs).

## 4. Zéro conflit : une règle par nature de donnée

| Donnée | Règle |
|---|---|
| Référentiels (produits, barèmes) | le serveur gagne ; un envoi du poste est ignoré et journalisé |
| Fiche journalière | dernier écrivain gagne (upsert par UUID) ; les compteurs dérivés (ventes) sont augmentés par le serveur |
| Vente de caisse | jamais fusionnée : chaque vente hors ligne est un fait indépendant |
| Stock | le poste envoie un mouvement/comptage ; le serveur le REJOUE par son action unique (jamais appliqué tel quel) |
| Comptabilité, clôtures, paie | le poste envoie une **DEMANDE** ; le serveur décide, numérote, écrit, et le résultat redescend au tirage |
| Compteurs, numéros (`FV-2026-001`) | **jamais inventés au poste** : attribués par le serveur |

Règles de robustesse : UUID générés côté poste (clés jamais auto-incrémentées) ; verrous pris dans un **ordre
fixe** (stock d'abord) ; un même (lot, jour) créé au même instant par deux postes est fusionné sous verrou ; les
dates métier sont en heure du pays (fuseau fixe), les instants techniques en UTC.

## 5. « Renvoyer vers tous les postes » (le web pousse vers les postes)

Le serveur **ne joint jamais** un poste (il peut être éteint, derrière un NAT) : il dépose un drapeau que le poste lit.
1. **Demander la synchronisation** (`DemandeSynchronisationService`) : le serveur écrit une demande (`poste` = un nom
   ou `null` = tous), valable 60 min. Chaque poste connecté interroge `GET /sync/demande` toutes les 30 s ; s'il y
   trouve une demande non servie pour lui, il synchronise (pull puis push). La lecture marque la demande servie par
   poste : une seule synchro par demande.
2. **Resynchroniser / « Renvoyer vers ce poste »** (`ResynchronisationPostesService`) : à chaque tirage terminé, le
   serveur mémorise le curseur rendu au poste (`poste_synchronisations`) ; l'écran web compte, par type, ce qui reste à
   recevoir (`updated_at > curseur`). « Renvoyer » lève `resync_demandee_le` ; le poste, au prochain tirage/ping, repart
   d'un tirage **COMPLET** (sans `since`) puis **acquitte** (`POST /sync/resynchronisation/acquittement`).
Cas d'usage : le portable a servi au web pendant la panne du poste de bureau.

## 6. Réinitialisation (remise à zéro) sans conflit

- Le serveur vide les données d'activité (comptes, rôles, référentiels, journal d'audit **préservés**) derrière trois
  verrous (bascule activée, mot de confirmation, audit), et pose une **marque** `data_reset_at`.
- **Chaque envoi du poste porte la marque qu'il connaît.** Marque inconnue ⇒ **409** : le serveur refuse de recevoir
  des données d'avant la remise à zéro (elles ressusciteraient).
- Le poste, à son prochain **tirage**, découvre la nouvelle marque, **purge** ses tables d'activité (stock et
  trésorerie remis à 0, curseur effacé), note la marque et compte les saisies non envoyées PERDUES (il le dit).
- Lancée **depuis un poste** : il appelle le serveur, reçoit la marque, purge immédiatement.
- Tous les jetons sont révoqués à cette occasion si besoin (reconnexion).

## 7. Installation neuve, mise à jour, désinstallation

- **Poste neuf** : base vide → connexion (appairage) → premier tirage complet paginé → prêt. Un « assistant de
  démarrage » facultatif guide l'administrateur.
- **Migrations de base locale** : numéro de version (`user_version`) + **réconciliation** de fin de migration qui crée
  toute table/colonne manquante (les numéros de paliers peuvent différer entre branches : la version ne dit pas ce
  que la base contient). Toute panne au démarrage affiche un ÉCRAN et un journal, jamais une fenêtre qui ne s'ouvre pas.
- **Mise à jour** : même identifiant d'application (AppId) ⇒ les données locales ne sont jamais touchées.
- **Désinstallation** : avertissement Oui/Non qui dit que les saisies non synchronisées seront PERDUES, proposition de
  **sauvegarde automatique** (copie hors du dossier supprimé), puis suppression du dossier des données. Une
  réinstallation repart d'un **nouveau poste** (nouvel UUID) ; l'ancien jeton est révoqué depuis le web.
- **Aucun poste ne casse un autre** : chacun a son UUID, son jeton, son curseur ; le serveur seul arbitre.

## 8. Sécurité

Jeton par poste révocable ; limiteurs (connexion 5/15 min, tirage/envoi throttlés) ; verrou de session local (PIN) ;
mot de passe jamais stocké ni journalisé ; réinitialisation de mot de passe **par l'administrateur** (temporaire +
changement forcé + jetons révoqués + audit) plutôt que par e-mail ; code de secours imprimé pour le dernier admin ;
rôles vérifiés au serveur ET masqués à l'écran ; journal d'audit de tout geste sensible.

## 9. Checklist pour un nouveau projet

1. Schéma commun : UUID partout, colonnes `device_id`, `sync_status`, `updated_at` ; table `poste_synchronisations`,
   `demande_synchronisations`, marque de remise à zéro.
2. API : `login` (jeton nommé), `pull` paginé, `push` transactionnel et idempotent, `demande`, `acquittement`, `me`.
3. Un **point de passage unique** serveur par règle métier, appelé par l'écran web ET par la synchro.
4. Poste : un seul écrivain par table (dépôt), absorbeurs stricts, garde « rien à envoyer » à jour.
5. Décider pour chaque table sa règle de conflit (§4) AVANT de coder.
6. Tests clés : renvoi du même lot (idempotence), réponse perdue, deux postes sur la même ligne, 401 puis
   reconnexion, remise à zéro (409 + purge), migration depuis une vieille base, désinstallation/réinstallation.
7. Essai multi-postes automatisé : cinq postes réels avec coupures aléatoires (réponse perdue, délai, 500, 413) puis
   réseau parfait jusqu'à ce que plus rien ne soit `pending` ; invariants (trésorerie, stock, dettes) égaux partout.

## 10. Pièges déjà payés

Curseur lu à l'heure murale du serveur au lieu de l'UTC ; compteur incrémenté sans verrou (deux ventes comptées une) ;
colonne ajoutée par un palier mais absente de la copie de table dans une migration ; une table d'envoi oubliée dans
la liste « à envoyer » (ne part jamais, sans erreur) ; marquer `synced` à l'envoi au lieu de l'accusé ; mettre à jour
un référentiel du poste en bloc et perdre une bascule non acquittée ; un envoi plus gros que la limite du mandataire
(413) sur une journée indivisible.

## Fichiers de référence (AgriERP)

Serveur : `app/Http/Controllers/Api/{AuthController,SyncController,SupervisionSynchronisationController}.php`,
`app/Services/{DemandeSynchronisationService,ResynchronisationPostesService,ReinitialisationDonneesService}.php`,
`routes/api.php`. Poste : `lib/core/sync/sync_engine.dart`, `lib/core/config/parametres_poste.dart`,
`lib/core/auth/auth_service.dart`, `lib/core/database/app_database.dart`, `installer/agrierp.iss`.
Tests : `SyncEssaiMultipostesTest`, `ResynchronisationPostesTest`, `ReinitialisationCompleteTest`,
`test/essai_multipostes_test.dart`, `test/migration_bases_reelles_test.dart`.
