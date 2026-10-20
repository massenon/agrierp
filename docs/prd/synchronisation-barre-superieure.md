# PRD — Bouton « Synchroniser » dans la barre supérieure et modale de synchronisation (poste et web)
**Statut :** brouillon · **Date :** 2026-10-19 · **Ticket(s) :** H2 (absorbe B4), H3, décisions D-SYNC-1 à D-SYNC-5 (`PLAN_FINALISATION.md`)

> **Construit d'abord sur le web** (Doctrine, article 0). Ni le web ni le prototype n'ont cette modale. Côté web, **ce n'est pas un bouton qui synchronise** : le serveur EST la base. La décision du Sprint 0 (`README_SPRINT0.md:107`, `:9667`) a écarté du web un bouton « Synchroniser » « décor sans mécanisme ». Elle reste juste pour un bouton qui ferait semblant d'envoyer. La demande du client du 19/10/2026 lui donne un objet réel au web : **montrer l'état de synchronisation des postes de la ferme**. Les deux surfaces partagent le même bouton, la même modale et la même structure ; seul le contenu propre à chaque surface diffère, et il est dit à l'écran.

## 1. Problème
- **Au poste :**
  - Le seul bouton « Synchroniser » est en pied de barre latérale. Quand la barre déborde (petit écran, 11 groupes, 22 entrées, aucun défilement), il devient **inatteignable** (`RAPPORT_VISUEL.md:11`, `README_SPRINT0.md:17522`).
  - La barre supérieure n'affiche qu'une pastille « Sync · N en attente » **non cliquable** (`barre_superieure.dart:464-498`).
  - Le résultat d'une synchronisation tient dans un bandeau éphémère, qui ne montre que le premier motif de refus (`sync_button.dart:146`).
- **Le compteur « en attente » est faux.** `AppDatabase.pendingCount()` omet 8 tables pourtant envoyées : products, suppliers, customers, supplier_payments, customer_advances, advance_imputations, purchase_returns, supplier_refunds.
  - Exemple : un caissier crée hors ligne un client et un article ; le poste affiche « 0 en attente ».
  - S'il ferme l'application en croyant tout envoyé, les deux restent sur la machine sans que rien ne le dise.
  - La confirmation de fermeture s'appuie sur le même compteur (`barre_superieure.dart:503-540`).
- **Au web,** l'administrateur ne sait pas quel poste n'a pas synchronisé depuis trois jours. Le serveur connaît pourtant le dernier contact de chaque poste (`personal_access_tokens.last_used_at`, jeton nommé d'après l'identifiant du poste, `AuthController.php:84-86`), mais aucun écran ne le lit. Un envoi laisse une ligne `api.sync_push` sans poste ni compteur (`SyncController.php:1222`), et un tirage ne laisse rien.

## 2. Existant
| Surface | Ce qui existe | Fichier |
|---|---|---|
| Poste | Moteur `SyncEngine.synchroniser()` → `SyncOutcome {tire, accepte, rejete, motifs, avertissements, horsLigne}` | `lib/core/sync/sync_engine.dart:46-73, 122` |
| Poste | Bouton jaune en pied de barre latérale + « N en attente » | `lib/core/sync/sync_button.dart`, `main.dart:1152-1162` |
| Poste | Pastille non cliquable dans la barre supérieure | `lib/core/widgets/barre_superieure.dart:464-498` |
| Poste | Écran Synchronisation : en attente, dernière réception, dernier envoi, refusés avec motif et « Remettre en file » | `lib/features/sync/synchronisation_screen.dart` |
| Poste | `SyncState.lastPulledAt` (horloge serveur), `lastPushedAt` (écrit seulement s'il y avait à envoyer) | `app_database.dart:1380-1383` |
| Poste | Modale partagée `ModaleAgri` / `afficherModale` (sm 384, md 448, lg 512) | `lib/core/widgets/modale_agri.dart` |
| Web | Jetons Sanctum : `name` (identifiant du poste), `tokenable_id` (utilisateur), `last_used_at`, `expires_at` | migration `2026_03_10_000001` |
| Web | `AuditLog::record('api.sync_push', 'sync', user)` à chaque envoi, sans compteurs | `SyncController.php:1222` |
| Web | Modale partagée `<x-modal>` (événement `open-modal`) | `resources/views/components/modal.blade.php` |
| Web | Aucun bouton ni aucune page « état des postes » | — |

## 3. Utilisateurs et rôles
| Rôle | Poste | Web |
|---|---|---|
| admin, comptable, caissier, animalier | **Tous** voient le bouton et la modale ; tous peuvent lancer une synchronisation. Un caissier doit pouvoir pousser ses ventes. Cette règle reprend celle de l'écran Synchronisation (`permissions_poste.dart:351`) | — |
| admin (`manage-users`) | — | voit le bouton et la modale « État de synchronisation des postes » |
| comptable, caissier, animalier | — | le bouton n'est **pas** affiché. La liste des postes et de leurs utilisateurs relève de la gestion des comptes, sous la même permission que « Vider les sessions » (15.54) |

## 4. Exigences fonctionnelles

### Commun
- **EF1** Un bouton « Synchroniser » est placé dans la barre supérieure, entre la recherche globale et la cloche. Icône Material Symbols `sync`, même gabarit que la cloche, plus une pastille de compteur sur le modèle du badge de la cloche.
- **EF2** Un clic ouvre une modale titrée **« Synchronisation »**, avec le surtitre « Poste {identifiant} » (poste) ou « Postes de la ferme » (web).

### Poste
- **EF3** Le badge du bouton affiche le nombre d'enregistrements **à envoyer**, toutes tables envoyées comprises (EF10), plafonné à « 9+ » comme la cloche. Il est rouge s'il y a au moins un refus en attente de correction, émeraude sinon. Il est absent à 0.
- **EF4** La modale du poste montre, dans l'ordre :
  1. **État de la liaison :** « En ligne » ou « Hors ligne » (`estEnLigne()`). L'état hors ligne n'est pas une erreur rouge : c'est l'état normal de la ferme (`agrierp_flutter/CLAUDE.md`).
  2. **Trois cartes `CarteKpi` :**
     - « En attente d'envoi » : nombre hors refus ;
     - « Refusés par le serveur » : `conflits().length` ;
     - « Dernière synchronisation réussie » : date et heure, ou « — » si jamais.
  3. **Dernière réception** et **Dernier envoi** (`SyncState`), « Jamais » si vide, comme l'écran Synchronisation.
  4. **Résultat de la dernière tentative de la session :** reçus, acceptés, refusés, avec **tous** les motifs de refus (et non plus seulement le premier) et les avertissements.
- **EF5** La modale a trois boutons de pied :
  - « Fermer » (secondaire) ;
  - « Voir le détail » (ouvre l'écran Synchronisation, pour remettre un refus en file) ;
  - « Synchroniser maintenant » (primaire).
  Pendant l'envoi, le bouton primaire est désactivé et affiche un indicateur. À la fin, la modale se met à jour sans se fermer, et un toast conforme (EF14) résume le résultat.
- **EF6** « Dernière synchronisation réussie » = l'instant d'un `synchroniser()` terminé sans `horsLigne` et sans erreur HTTP, **refus compris** : la liaison a abouti. Cet instant est conservé en base locale (`SyncState`), à l'horloge du serveur (`server_time` du tirage), jamais à celle du poste.
- **EF7** La pastille non cliquable `pastille-sync` disparaît, remplacée par le bouton.
- **EF8** Le bouton jaune du pied de barre latérale disparaît : il n'existe ni au web ni au prototype dans la barre supérieure, et le doublon serait une seconde entrée pour la même action.
- **EF9** La barre latérale défile (`SingleChildScrollView`). C'est le correctif du débordement, traité au ticket H1.
- **EF10** `pendingCount()` couvre **exactement** les tables envoyées par `_envoyer` (`sync_engine.dart:2869-2911`). Un test compare les deux listes, pour que la prochaine table ajoutée à l'envoi ne soit pas oubliée du compteur.

### Web
- **EF11** La modale web liste **un poste par ligne**, à partir des jetons Sanctum non expirés. Colonnes, dans un tableau à en-tête clair comme le reste du web :

  | Colonne | Contenu |
  |---|---|
  | Poste | `name` du jeton |
  | Utilisateur | nom du compte |
  | Dernier contact | `last_used_at`, format `d/m/Y H:i`, « — » si jamais |
  | Dernier envoi | dernier `push` du journal (EF12) |
  | Acceptés / Refusés | compteurs de ce dernier envoi |
  | État | pastille |

  Règles de la pastille d'état, du plus grave au moins grave :
  - « Refus à corriger » (rouge) si le dernier envoi a au moins un refus ;
  - « Inactif depuis N jours » (jaune) si le dernier contact date de plus de 3 jours (D-SYNC-6) ;
  - « À jour » (émeraude) sinon.

  Pied de la modale : « Fermer » et « Actualiser ». Aucun bouton « Synchroniser » : le serveur n'envoie rien.
- **EF12** Le serveur **journalise chaque tirage et chaque envoi** dans une table `journal_synchronisation`. Elle est propre au serveur, **non synchronisée**, avec une clé UUID. Colonnes :
  - `id` ;
  - `user_id` ;
  - `poste` : nom du jeton courant, `currentAccessToken()->name` ;
  - `sens` : `tirage` ou `envoi` ;
  - `nb_recus` : enregistrements servis au tirage ;
  - `nb_acceptes`, `nb_refuses` : sommes sur les tables de la réponse d'envoi ;
  - `created_at`.

  L'écriture se fait **après** le calcul de la réponse. Un échec du journal ne fait jamais échouer la synchronisation : `try` / `report()`.
- **EF13** La ligne d'audit `api.sync_push` est conservée telle quelle (onglet Audit Logs).

### Retours
- **EF14** Les toasts suivent le composant web `toast-container` : en haut à droite, 3,5 s, icône, émeraude pour un succès, `error-red` pour une erreur, jaune pour un avertissement. Au poste, c'est un composant unique `ToastAgri` (ticket H1), qui remplace les SnackBar de `sync_button.dart`.
  - Succès : « Synchronisation terminée : {reçus} reçu(s), {acceptés} envoyé(s). »
  - Refus : « {n} enregistrement(s) refusé(s) — voir le détail. »
  - Hors ligne : avertissement « Serveur injoignable — les saisies restent sur ce poste et partiront à la prochaine synchronisation. »

## 5. Règles métier et calculs
Aucun effet comptable, stock ou effectif : la modale lit, le bouton appelle le moteur existant. Jeu d'exemple, calculé à la main, qui deviendra le test :

**Poste.** 2 fiches journalières `pending`, 1 client `pending`, 1 article `pending`, 1 vente `conflict`.
- Avant correctif : `pendingCount()` = 3 (fiches et vente) ; le client et l'article sont oubliés.
- Après correctif : 5 enregistrements non synchronisés.
- Badge : « 5 », **rouge** (un refus).
- Carte « En attente d'envoi » = 4 ; carte « Refusés par le serveur » = 1.

**Web.**

| Poste | Dernier contact | Dernier envoi | Acceptés / refusés | Pastille |
|---|---|---|---|---|
| P1 | il y a 1 h | 1 h | 12 / 0 | « À jour » |
| P2 | il y a 5 jours | — | — | « Inactif depuis 5 jours » |
| P3 | il y a 2 h | 2 h | 3 / 1 | « Refus à corriger » |

P3 montre que le refus l'emporte sur la date.

## 6. Hors ligne et synchronisation
- Aucune nouvelle table synchronisable.
- `journal_synchronisation` est **serveur seul** : elle n'est ni tirée ni poussée, et doit être classée dans `ReinitialisationDonneesService` (table technique vidée à la réinitialisation, ticket 15.50).
- Au poste, `SyncState` reçoit une colonne `lastSucceededAt` : palier de migration Drift et `build_runner`.
- Sans réseau, la modale du poste s'ouvre et lit la base locale. « Synchroniser maintenant » renvoie l'avertissement hors ligne, sans erreur rouge.

## 7. Interface
- **Web d'abord.**
  - `layouts/app.blade.php`, barre supérieure : bouton `sync` dans le gabarit de la cloche (`text-outline hover:text-brand-emerald`), visible sous `@can('manage-users')`.
  - Composant Livewire `Shared\EtatSynchronisationPostes`, avec la modale `<x-modal name="modal-etat-synchronisation">`.
- **Poste ensuite.**
  - `BarreSuperieure` : `_BoutonSynchroniser` (badge sur le modèle de la cloche).
  - Modale `ModaleSynchronisation` construite sur `ModaleAgri` (largeur md), avec `CarteKpi` pour les cartes et `afficherModale` pour l'ouverture.
- **Libellés exacts :**
  - « Synchronisation »
  - « En ligne » / « Hors ligne »
  - « En attente d'envoi »
  - « Refusés par le serveur »
  - « Dernière synchronisation réussie »
  - « Dernière réception »
  - « Dernier envoi »
  - « Synchroniser maintenant »
  - « Voir le détail »
  - « Fermer »
  - « Actualiser »
  - « Postes de la ferme »
  - « À jour »
  - « Inactif depuis N jours »
  - « Refus à corriger »

## 8. Hors périmètre
- La synchronisation automatique (B2) : retour du réseau, intervalle, fermeture.
- Les réessais exponentiels.
- L'envoi par lots.
- La table outbox.
- L'appairage.

Tous relèvent des décisions D-SYNC-1 à D-SYNC-5 ci-dessous.

## 9. Questions ouvertes pour le client
| Réf. | Question | Recommandation |
|---|---|---|
| D-SYNC-1 | Remplacer `/api/sync/pull` + `/push` par une route unique `POST /api/v1/sync`, avec une table outbox `operations_sync_local` et une déduplication serveur de 30 jours ? | **Non.** L'idempotence est déjà assurée par l'UUID de chaque enregistrement (vente déjà connue = succès silencieux, ajustement rejoué par `client_ref`). Réécrire le protocole ferait courir un risque à 20 tables qui marchent, sans corriger aucun défaut constaté. |
| D-SYNC-2 | Envoyer par lots de 50 ? | **Oui, plus tard.** Un poste resté hors ligne une semaine envoie aujourd'hui toute sa file en une requête, avec un délai de réception de 30 s (`main.dart:134-135`). Des lots réduisent le risque d'expiration. Ticket à part, après B2. |
| D-SYNC-3 | Synchronisation automatique avec réessais (30 s, 2 min, 5 min, 15 min, 1 h) ? | **Oui** : c'est B2. Réessais pour les échecs réseau seulement ; un refus reste en « Refusés » jusqu'à correction. |
| D-SYNC-4 | Une vente en rupture de stock reçue d'un poste : refuser, ou accepter et signaler ? | **Accepter et signaler.** Aujourd'hui le serveur accepte **en silence** et le stock peut devenir négatif (`SyncController.php:2988-3001`). Refuser casserait la caisse hors ligne. Proposition : notification « Stock négatif après synchronisation — {article} » à l'admin, plus une ligne dans le journal (EF12). |
| D-SYNC-5 | Appairage du poste par l'administrateur (URL, compte admin, une seule fois), au lieu de la connexion de chaque utilisateur ? | **Non pour l'instant.** Le jeton par utilisateur et par poste porte déjà les droits (`manage-*`) contrôlés table par table (S1). Un jeton d'appairage unique enverrait les saisies du caissier avec les droits de l'admin. |
| D-SYNC-6 | Seuil « Inactif depuis N jours » au web | **3 jours**, comme le rappel des soins. Réglable plus tard si besoin. |
| D-SYNC-7 | La modale du poste doit-elle aussi lister les autres postes de la ferme ? | **Non dans ce ticket.** Il faudrait servir le journal au tirage. À rouvrir si le client le veut. |

## 10. Critères d'acceptation
- **Laravel `tests/Feature/EtatSynchronisationPostesTest.php`** :
  - Le bouton est visible pour l'admin, et absent pour le caissier, le comptable et l'animalier.
  - Le jeu P1, P2, P3 donne les trois pastilles attendues ; un jeton expiré n'est pas listé.
  - Un `pull` puis un `push` écrivent 2 lignes de journal, avec le poste = nom du jeton et les compteurs exacts (une vente acceptée, une refusée → 1 / 1).
  - Un journal en échec (table renommée dans le test) ne fait pas échouer le `push`.
  - **Mutation :** retirer la journalisation du `push` doit rougir le test.
- **Flutter `test/synchronisation_barre_test.dart`** :
  - Le badge vaut « 5 » et est rouge sur le jeu de l'exemple §5.
  - La modale affiche 4 / 1 / « — ».
  - « Synchroniser maintenant » hors ligne affiche l'avertissement et pas d'erreur rouge.
  - La pastille `pastille-sync` et le bouton du pied de barre ont disparu.
  - La barre latérale défile : la dernière entrée est atteignable dans une fenêtre de 1280 × 600.
- **Flutter `test/compteur_attente_test.dart`** :
  - La liste des tables de `pendingCount()` est égale à celle de `_envoyer`.
  - **Mutation :** retirer `customers` du compteur doit rougir le test.
