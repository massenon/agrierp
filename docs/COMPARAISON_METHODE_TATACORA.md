# Méthode de synchronisation TATACORA ↔ AgriERP — ce qui est déjà là, ce qui manque

**Date :** 19/10/2026 · **Source :** la note « reprendre la méthode et la structure » transmise par le client (7 sections).
**Règle de lecture :** la méthode et la structure se transposent ; le code se réécrit sur les tables d'AgriERP. Une
décision déjà prise par le client (D-SYNC-1 à D-SYNC-7, `PLAN_FINALISATION.md`) n'est pas rouverte sans lui.

Légende : ✅ en place · 🟡 en partie · ❌ absent · 🔴 défaut trouvé en comparant, corrigé.

## 1. Installateur Windows

| Point de la note | AgriERP | État |
|---|---|---|
| `build_windows.bat` + script Inno Setup | `agrierp_flutter/build_windows.bat`, `installer/agrierp.iss` | ✅ |
| `AppId` propre (sinon il remplace TATACORA sur le même PC) | GUID propre `69B3D13F-…` | ✅ |
| `AppName`, `AppPublisher`, `DefaultDirName`, `OutputBaseFilename` | AgriERP, Dr MASSENON Rhodes – Ferme École OLOUWACHEGOUN, `{autopf}\AgriERP`, `AgriERP-Setup-<version>` | ✅ |
| Version lue dans `pubspec.yaml`, vérification des outils (Inno Setup, VC++) | oui (ticket A7) | ✅ |
| Adresses des serveurs par version (dev, recette, production) | S-T8 : `lib/core/config/environnement.dart`, choisi par `--dart-define=AGRIERP_ENV` (`build_windows.bat --env`, défaut production) ; toujours réglable dans Paramètres du poste. Adresse de recette **à confirmer** | ✅ |
| Refus de la version démo | S-T8 : version `x.y.z-demo` de `pubspec.yaml` refusée en production par `build_windows.bat` et par `agrierp.iss` (`#error`) | ✅ |
| Icône `app_icon.ico` | à vérifier sur la machine de compilation | 🟡 |

## 2. Principes de synchronisation

| Principe | AgriERP | État |
|---|---|---|
| UUID né sur le poste, au geste | oui (règle du schéma, jamais régénéré par le serveur) | ✅ |
| Le poste lit sa base locale, aucune branche « si connecté » | oui pour les écrans métier ; quelques gestes passent par le serveur (export de fiche sujet, attestations, contact éditeur) et le disent | 🟡 |
| File écrite dans la même transaction que le geste | pas de file séparée : la ligne métier elle-même porte `sync_status = pending` — atomique par construction | ✅ (autre forme) |
| Le serveur écrit par ses services métier | oui (`Actions`, `AdjustStockAction`, rejeu comptable) | ✅ |
| Refus métier définitif (« À traiter ») ; bug serveur 500 → renvoi plus tard | refus → « Refusés » (`conflict`) avec motif ✅ ; une **500 n'est pas réessayée** par la synchronisation automatique (seuls les échecs réseau le sont) | 🟡 |
| La descente n'enfile rien et n'écrase jamais une saisie en attente | oui (absorbeurs stricts) | ✅ |
| Comptes, mots de passe, secrets jamais synchronisés | jeton dans le stockage sécurisé ; les utilisateurs descendent sans mot de passe | ✅ |

## 3. Serveur

| Élément | AgriERP | État |
|---|---|---|
| `POST /api/v1/sync`, lots de 50 opérations + table de déduplication par `uuid_operation` | `POST /api/sync/push` par tables, lots de 50 (H13b) ; idempotence par l'UUID de chaque enregistrement (vente connue = succès silencieux, ajustement rejoué par `client_ref`). **Décision D-SYNC-1 du client : ne pas réécrire le protocole** | ✅ (autre forme, décidé) |
| Registre des gestionnaires par table (droits, service, 4 cas) | un bloc par table dans `SyncController::push`, droits par table (S1), création / modification / inconnu / déjà enregistré traités table par table | ✅ (autre forme) |
| Fusion par clé naturelle + table de correspondances | S-T5 : `FusionReferentielsService` (clés : client et fournisseur = nom normalisé + téléphone d'au moins 8 chiffres, jamais sans téléphone ; produit = nom + catégorie + unité + filière — pas le SKU, engendré par le serveur), table `correspondances_identifiants`, réponse `merged: [{id, id_serveur}]` à côté de `accepted` ; références des envois traduites en un point (`REFERENCES`) ; le poste remplace l'identifiant partout en une transaction (`fusion_referentiels.dart`) | ✅ |
| Conflit : référentiels au dernier écrit (heure de saisie) ; argent arbitré au serveur | fiches au dernier écrivain ; ventes jamais fusionnées ; stock rejoué ; argent rejoué par les Actions | ✅ |
| Descente paginée, curseur (`updated_at` + `id`), horizon de 5 s | S-T4 : `page` / `curseur_page` (jeton chiffré), 1 000 lignes par page, tables d'historique découpées PAR PIÈCE au curseur (`updated_at`, `id`), pièces bornées au début du tirage ; `server_time` (début, horizon de 5 s) et `accounting_entry_ids` à la dernière page ; sans `page`, réponse complète d'avant (poste ancien) ; compteur de débit propre au tirage (120 / min). 🔴 **Le curseur était pris APRÈS les requêtes : une écriture faite pendant le tirage était perdue pour le poste.** Corrigé le 19/10 (curseur au début, recouvrement de 5 s, `SyncCurseurTirageTest`) | ✅ / 🔴 corrigé |
| Seules les tables que le compte lit | S-T4 : `SyncController::PERMISSIONS_DE_TIRAGE` (table → permission(s) de lecture, croisée avec les écrans du poste par `perimetre_tirage_test`) ; `tables_servies` à chaque page ; table ajoutée au périmètre → tirage complet, une fois (`PerimetreTirage`). Le tableau de bord étant ouvert aux quatre rôles, ventes, achats, élevage et trésorerie restent servis à tous | ✅ |
| Lignes d'un document descendues avec lui | oui depuis U4 / U8 (lignes de vente, d'achat, retours) | ✅ |
| Identifiant du poste lié à son jeton | le jeton est nommé d'après le poste, mais `device_id` envoyé n'est **pas comparé** au nom du jeton : un poste peut signer au nom d'un autre | ❌ |
| Bouton « Synchroniser » du serveur (demande lue toutes les 30 s) | S-T6 : « Demander la synchronisation des postes » (tous, ou un poste) dans la modale H3 ; `GET /api/sync/demande` lu toutes les 30 s par la session ouverte, silencieux hors ligne ; demande valable 60 min | ✅ |
| Contrôle de cohérence (nombre et total par table et par jour) | S-T6 : `GET /api/sync/coherence?depuis=`, table de correspondance unique (`CoherenceSynchronisationService::AGREGATS`, copiée et vérifiée au poste). Tables dont le poste tient un miroir complet (S-T4 : celles du périmètre du compte seulement) ; **dépenses hors contrôle** (non tirées) | ✅ / 🟡 |

## 4. Poste

| Élément | AgriERP | État |
|---|---|---|
| File `operations_sync` + ajout refusé hors transaction | colonnes `sync_status` sur chaque table (pas de file) | ✅ (autre forme, D-SYNC-1) |
| Contenu figé au contrat du serveur, conversions à un seul endroit | sérialiseurs `_xxxEnJson` du moteur, un par table | ✅ |
| Moteur d'envoi par lots | lots de 50, journées couplées (H13b) | ✅ |
| Réessais 30 s / 2 min / 5 min / 15 min / 1 h | oui pour les échecs réseau (H13) ; **pas pour une 5xx** | 🟡 |
| 401/403 : plus rien ne part jusqu'à un nouvel appairage | message « Session expirée / accès refusé » ; la synchronisation automatique continue de tenter à l'intervalle | 🟡 |
| 422 : lot coupé en deux jusqu'à isoler la ligne fautive ; 413 : lot plus petit | non (une ligne invalide est refusée avec motif par le serveur, mais une 422 / 413 de lot entier n'est pas découpée) | ❌ |
| Appairage par le nom du poste, jeton hors dépôt | connexion par utilisateur, jeton nommé d'après le poste (D-SYNC-5 : pas d'appairage administrateur) | ✅ (décidé) |
| Descente : une page = une transaction, un élément fautif n'emporte pas la page | S-T4 : une page = une transaction ; un absorbeur strict refuse **toute la page** si une ligne est incohérente (choix du projet, F0.51), et le curseur ne bouge pas | ✅ (autre choix) |
| Un aligneur par table, dépendance pas encore arrivée = attente | un absorbeur par table, ordre de tirage fixe | ✅ |
| Déclencheurs : démarrage, toutes les 5 min, après un geste important, demande du serveur | retour du réseau, intervalle (15 min par défaut, réglable), fermeture | 🟡 |
| Écran : compteurs, « À traiter », contrôle de cohérence | modale et écran Synchronisation (compteurs, refusés, « Remettre en file ») ; S-T6 : « Contrôle de cohérence » (Poste / Serveur / Écart, jours conformes repliés) ; dernier contrôle de chaque poste dans la modale web | ✅ |

## 5. Questions de PO

| Question | AgriERP |
|---|---|
| Comptabilité : chaque poste ses écritures, ou celles du serveur descendent ? | **Le serveur seul écrit les écritures** (rejeu des Actions) ; le journal descend au poste (F0.84) |
| Numérotation légale | attribuée par le **serveur** (factures MeCeF, courriers `CR-AAAA-NNN`) ; le poste affiche « — » en attendant |
| Annuler un document d'un autre poste | les ventes ne se modifient pas au poste ; annulation au web, avec droits |
| Ce qui est unique dans l'établissement | une fiche par (bande, jour) : refus motivé au second poste ; un exercice ouvert par date ; un code de bande |

## 6. Pièges de la note, vérifiés sur AgriERP

| Piège | AgriERP |
|---|---|
| Date métier ≠ date d'audit | ✅ `sold_at`, `updated_at` = instant de saisie (14.71, F0.31) |
| Table de liaison qui ne touche pas `updated_at` (matrice des droits) | S-T7 : le tirage sert `roles` en entier (le piège était masqué) ; toute écriture de `role_has_permissions` date désormais le rôle (`App\Models\Role`, `App\Models\Permission`) |
| Horizon et horloges dans les tests | 🔴 corrigé (curseur) ; les tests de synchronisation automatique utilisent une horloge simulée unique |
| Un seul écrivain par table au poste | S-T7 : `test/ecrivain_unique_test.dart` ; fiches (caisse, transferts) et archivage des soins ramenés à leur dépôt ; exception justifiée : `products.stock_qty` (miroir local du grand livre) |
| Tests contre le vrai serveur | `sync_reel_test` (sauté sans serveur) + parités exécutées PHP ↔ Dart ; pas d'essai à plusieurs postes avec coupures |

## 7. Ce que je propose (tickets S-T, dans l'ordre de la note)

1. **S-T1** — 5xx réessayée comme un échec réseau ; 401/403 : la synchronisation automatique s'arrête jusqu'à la reconnexion ; 422/413 : lot coupé en deux.
2. **S-T2** — `device_id` comparé au nom du jeton (refus 403 sinon).
3. **S-T3** — déclencheurs : au démarrage, après un geste important (vente, fiche du jour), intervalle par défaut 5 min.
4. **S-T4** — descente paginée (curseur `updated_at` + `id`) et limitée aux tables que le rôle lit.
5. **S-T5** — fusion par clé naturelle des référentiels saisis au poste (clients, fournisseurs, produits) avec table de correspondances.
6. **S-T6** — bouton « Synchroniser les postes » au web (demande lue par les postes toutes les 30 s) et contrôle de cohérence (nombre et total par table et par jour), au web et dans l'écran Synchronisation du poste.
7. **S-T7** — garde-fou « un seul écrivain par table » au poste ; datation de `roles` quand ses droits changent.
8. **S-T8** — installateur : refus de la version démo, adresses par environnement.
9. **S-T9** — essai à plusieurs postes contre le vrai serveur, avec coupures au hasard, avant la mise en production.

**Non proposé :** remplacer `/api/sync/pull` + `/push` par `POST /api/v1/sync` et une file `operations_sync` (décision D-SYNC-1 :
non — l'idempotence est déjà assurée par l'UUID de chaque enregistrement ; réécrire le protocole ferait courir un risque à
toutes les tables qui marchent, sans corriger un défaut constaté).
