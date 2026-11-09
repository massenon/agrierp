# 12 — SRS : exigences logicielles de LogiALVIA (web + poste + synchronisation)

## USAGE

- **Quand l'utiliser** : après le PRD ; avant de créer la première migration. Il fige le comportement du SYSTÈME (architecture, interfaces, données, sécurité, hors ligne) ; le FRS (`13_`) fige les fonctions testables par module.
- **Ordre** : `10_BRS` → `11_PRD` → **`12_SRS`** → `13_FRS` → `14_NFRS` → `15_REGLES_METIER` ; s'appuie sur `02_ARCHITECTURE_WEB_ET_STACK.md` (stack), `30_DATABASE_ENGINEERING.md` (schéma), `43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md` (appairage, synchro), `41_MECEF_EMECEF.md`, `40_PWA_HORS_LIGNE.md`.
- **Entrées** : `logialvia/docs/B3_SRS_Software_Requirements.md`, `C1_Architecture_Clean_DDD_Flutter.md`, `D1_Modele_Donnees_ERD_Dictionnaire.md`, `I1`, `I3_Security_Strict.md`, `docs/logialvia/GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md` (§14 à §21), `docs/BLUEPRINT_SYNCHRONISATION_MULTIPOSTES.md`, `agrierp_laravel/CLAUDE.md`, `agrierp_flutter/CLAUDE.md`.
- **Sorties** : ce fichier à jour (exigences `SR-nnn`), la liste des interfaces externes, la matrice « table → nature → règle de conflit » (section 5) complétée pour CHAQUE table de logialvia.
- **Chemins** : `logialvia/…` = `/home/user/massenon/logialvia/…` (lecture seule) ; `logialvia_app/…` idem ; sans préfixe = monorepo `/home/user/agrierp`.

---

## 1. PROMPT — « Rédige / mets à jour le SRS de LogiALVIA »

> **Rôle.** Architecte logiciel senior (Laravel 12/Livewire 3, Flutter/Drift, synchronisation offline-first).
> **Contexte.** B3 décrivait une application monoposte sans réseau. Le client a décidé (07/11/2026) de créer le web : le système devient « serveur Laravel + clients Flutter Windows + navigateurs ». Le schéma est partagé (UUID), le serveur est l'unique écrivain des règles sensibles (comptabilité, numéros de pièces, stock rejoué), le poste écrit des FAITS ou des DEMANDES.
> **Tâches.** (1) Mets à jour le contexte système (section 2) ; (2) vérifie chaque `SR-` contre sa source ; (3) complète la matrice de la section 5 en classant toute table de `logialvia_app/lib/*/data/tables/` : synchronisable / serveur seule / locale, + règle de conflit ; (4) précise les contrats d'interface (section 4) : routes, statuts HTTP, corps ; (5) ajoute les exigences de sécurité, hors ligne, PWA, MeCeF, import ; (6) liste les hypothèses et dépendances ; (7) marque À DÉFINIR ce que les sources ne tranchent pas.
> **Contraintes.** Mêmes conventions qu'LogiAgriERP (français partout ; UUID ; `app_database.g.dart` jamais à la main ; 1 point de passage par règle ; `authorize()` en première ligne de chaque méthode mutante ; `@can`/masquage = cosmétique). Aucun SQL concaténé. Aucun secret en dur ni versionné. Heure du pays.
> **Critères d'acceptation.** (a) chaque `SR-` : id, énoncé « DOIT », source, test de vérification ; (b) la matrice §5 couvre 100 % des 37 tables de logialvia (37 classes `extends Table`, voir §5) ; (c) chaque interface §4 a route, méthode, authentification, erreurs ; (d) les hypothèses §7 sont datées ; (e) aucune exigence ne contredit `15_REGLES_METIER.md`.
> **Interdits.** Concevoir un second protocole de synchronisation (PWA incluse) ; hasher un mot de passe en SHA-256+sel côté poste après la bascule ; servir le jeton e-MECeF au poste ; laisser le poste écrire `fiscal_years` ou un numéro de pièce.

---

## 2. Contexte système

```
 Navigateur (PWA)  ──HTTPS──┐
                            ▼
 Poste Windows Flutter ──HTTPS /api──►  SERVEUR  Laravel 12 + Livewire 3 + Sanctum
 (Drift/SQLite, hors ligne)             MariaDB/MySQL (prod) · SQLite :memory: (tests)
        │  PIN local, jeton nommé        │  planificateur (1 cron schedule:run)
        ▼                                ├─► DGI e-MECeF (HTTPS, jeton chiffré serveur)
 Imprimante / PDF / xlsx                 ├─► SMTP (envoi de documents)
                                         └─► sauvegardes (fichier téléchargeable)
```

Source : B3 §2 (poste seul) révisé par guide §0 et 14.2. Le poste n'est plus seul ; le navigateur est un client en ligne.

## 3. Exigences d'architecture et de données

| ID | Exigence | Source | Vérification |
|---|---|---|---|
| SR-001 | Le serveur DOIT être Laravel 12 + Livewire 3 + Alpine + Tailwind (CLI), PHP 8.3, MySQL/MariaDB ; arborescence plate `app/Actions`, `app/Services`, `app/Models`, `app/Livewire/{Module}` (pas de `Domain/`). | guide D-SRV-1 ; `agrierp_laravel/CLAUDE.md` « Layering » | revue d'arborescence |
| SR-002 | Le poste DOIT rester Flutter Windows, Drift/SQLite, architecture par module puis par couche `lib/<module>/{data,domain,presentation}` (existante). | guide §0 ; `logialvia_app/lib/` | `ls` |
| SR-003 | Toute table synchronisable DOIT avoir une clé primaire UUID (v4 générée au poste ou au serveur), jamais un entier auto-incrémenté. | `CLAUDE.md` racine ; guide D-SRV-3 | test de garde sur le schéma |
| SR-004 | Colonnes communes des tables synchronisables : `id` (UUID), `device_id`, `sync_status` (`pending`/`synced`/`conflict`, poste), `updated_at` (instant de SAISIE), `is_active` quand archivable. | guide D-SRV-2 | test « schéma identique des deux côtés » |
| SR-005 | Le schéma Laravel et le schéma Drift DOIVENT rester identiques pour les tables synchronisables : une migration d'un côté impose l'autre ; `dart run build_runner build --delete-conflicting-outputs` ; `app_database.g.dart` jamais édité. | `CLAUDE.md` racine | garde |
| SR-006 | La migration UUID des bases Drift existantes DOIT : (1) sauvegarder avant ; (2) tenir dans UNE transaction (palier `from < 27`, `versionSchema` = 26 aujourd'hui) ; (3) conserver les numéros de pièces déjà attribués (FV-2026-001, OD-2026-…) comme colonne de lecture ; (4) vérifier lignes avant = après et `PRAGMA foreign_key_check` vide ; (5) être idempotente. | guide D-SRV-3 ; `logialvia_app/lib/core/database/app_database.dart` | test sur vraie ancienne base |
| SR-007 | La suppression DOIT être logique (archivage `is_active=false` ou statut) ; aucun `DELETE` physique sur données comptables ou zootechniques ; les écritures comptables ne vont PAS en corbeille (contre-passation) : TRANCHÉ (DV-05). | `agrierp_laravel/CLAUDE.md` « Data model conventions » ; F8 | grep `->delete()` |
| SR-008 | Chaque règle métier DOIT avoir UN point de passage serveur (`Actions/`, `Services/`), appelé par l'écran web ET par la synchronisation. | guide 14.1 | revue + test de parité |
| SR-009 | Toute écriture comptable DOIT passer par `AccountingEntryService::record()` / `recordManual()` : Σ débit = Σ crédit à la décime (vérifié AVANT écriture), date dans un exercice OUVERT (résolu par date), débit ≠ crédit pour deux lignes. | `agrierp_laravel/CLAUDE.md` | tests d'équilibre |
| SR-010 | Tout mouvement de stock DOIT passer par `AdjustStockAction` (mouvement écrit dans le même appel) ; verrous de stock pris dans l'ordre des UUID croissants AVANT toute fiche. | idem ; `OrdreDesVerrous::stock` | test de concurrence |
| SR-011 | Les dates « métier » DOIVENT être à l'heure du Bénin (UTC+1 fixe, serveur `Africa/Porto-Novo`) ; jamais `DateTime.now()` ni l'horloge du poste pour un jour métier. | guide 14.1 ; `agrierp_flutter/lib/core/temps/heure_benin.dart` | test avec `TZ=America/New_York` |
| SR-012 | Les montants facturés DOIVENT être en FCFA entiers avec UNE fonction d'arrondi (au plus proche, moitié vers le haut). | guide bloc 19 | garde « aucun autre `round(` de montant » |

## 4. Interfaces externes et API de synchronisation

Contrat repris d'LogiAgriERP (`agrierp_laravel/routes/api.php` ; `agrierp_laravel/CLAUDE.md` « Offline sync »). Détail : `43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md` et `docs/BLUEPRINT_SYNCHRONISATION_MULTIPOSTES.md`.

| ID | Interface | Contrat | Source |
|---|---|---|---|
| SR-020 | `POST /api/auth/login` | limité à 5/min ; rend un jeton Sanctum NOMMÉ d'après le poste ; compte archivé refusé ; 1re connexion d'un poste exige le réseau | guide bloc 15 |
| SR-021 | `GET /api/auth/me`, `POST /api/auth/logout` | jeton ; 401 → le poste suspend et redemande une connexion | guide bloc 15, 16 |
| SR-022 | `GET /api/sync/pull?since=…&page=…` | curseur = `server_time` rendu par le SERVEUR, n'avance qu'à la dernière page ; ne sert que les tables que le compte peut lire ; jamais une ligne sans sa pièce | guide bloc 16 |
| SR-023 | `POST /api/sync/push` | toute la requête dans UNE transaction (rejouée 3 fois sur interblocage) ; idempotent par UUID ; réponse table par table (acceptés, refusés + motif français) ; lots sous la limite du mandataire (413) | guide bloc 16 |
| SR-024 | `GET /api/sync/demande` | le poste interroge toutes les 30 s ; drapeau valable 60 min, servi une fois par poste | guide bloc 16 |
| SR-025 | `POST /api/sync/resynchronisation/acquittement` | tirage complet puis acquittement | guide bloc 16 |
| SR-026 | Remise à zéro | marque `data_reset_at` ; un envoi portant une marque inconnue reçoit 409 | guide bloc 16 |
| SR-027 | `POST /api/notifications/{id}/read`, `DELETE /api/notifications/{id}` | exigent le réseau, jamais mis en file | guide bloc 18 |
| SR-028 | DGI e-MECeF | `POST /invoice` puis `PUT /invoice/{uid}/confirm` ; délai 12 s / connexion 5 s ; UN SEUL essai de création ; l'`uid` est gardé ; jeton JWT chiffré, jamais servi au poste | guide bloc 19 |
| SR-029 | SMTP | serveur, port, sécurité TLS/SSL/aucun ; mot de passe chiffré ; jamais journalisé | F8 onglet 2 |
| SR-030 | Export/impression | PDF généré par un générateur unique ; xlsx par un exporteur unique | E9 ; guide bloc 7 |

## 5. Synchronisation : règles de conflit par nature de donnée

| Donnée | Règle (jamais un « dernier écrivain gagne » global) | Source |
|---|---|---|
| Référentiels (produits, barèmes de ration, calendriers de prophylaxie, rôles) | le serveur gagne ; l'envoi du poste est ignoré et journalisé (`referentiels_ignored`) ; création au poste fusionnée par clé naturelle | guide bloc 16 |
| Fiche journalière | dernier écrivain par UUID, mais la colonne `vente` n'est JAMAIS prise du poste : chaque vente l'incrémente une fois | `agrierp_laravel/CLAUDE.md` |
| Vente de caisse | jamais fusionnée ; chaque vente hors ligne est un fait indépendant ; le serveur accepte et SIGNALE un stock négatif | guide bloc 16, 18 |
| Stock | le poste envoie un mouvement ou un comptage ; le serveur rejoue par `AdjustStockAction` | idem |
| Comptabilité, clôtures, immobilisations, paie | le poste envoie une DEMANDE ; le serveur décide, numérote, écrit ; le résultat redescend au tirage | idem |
| Numéros de pièces (FV, FA, OD, AV, DEV, FAB) | attribués par le serveur ; jamais inventés au poste | guide 14.2 |

Matrice de classement des **37 tables Drift** de logialvia (relevées par `grep "extends Table"` dans `logialvia_app/lib/*/data/tables/`, 28 fichiers) — proposition à valider à l'étape W0 du guide 14.3 :

| Table(s) logialvia | Nature proposée | Règle de conflit |
|---|---|---|
| `FicheJournee`, `FicheVentesJour`, `Bandes`, `SoinsCalendrier`, `Infirmerie`, `CycleCouveuse`, `MachinesIncubateur` | synchronisable (le poste écrit des faits) | fiche : dernier écrivain par UUID, colonne `vente` jamais prise du poste |
| `ProduitsVendables`, `Intrants`, `MouvementsIntrant` | synchronisable ; stock par mouvement rejoué | référentiel : serveur gagne ; stock : rejeu serveur |
| `Ventes`, `LignesVente`, `Clients`, `Achats`, `LignesAchat`, `Fournisseurs`, `Devis` | synchronisable | vente jamais fusionnée |
| `Factures`, `LignesFacture`, `GroupesTaxe` | synchronisable ; champs MeCeF écrits par le serveur seul | serveur |
| `ExerciceComptable`, `PlanComptable`, `EcritureComptable`, `NotesAnnexes`, `CloturesPeriodiques` | tirées au poste ; écriture = DEMANDE | serveur décide |
| `BaremesRation`, `CalendrierProphylaxie`, `ModulesActifs` | référentiel | serveur gagne |
| `Utilisateurs`, `Roles`, `PermissionsRole` | serveur ; le poste ne garde ni mot de passe ni hash | serveur |
| `ParametresEntreprise` | synchronisable ; jeton e-MECeF et mot de passe SMTP JAMAIS servis | serveur |
| `AuditLogs`, `SecurityLogs`, `Corbeille`, `MessagesEditeur` | serveur seule (copie en lecture selon droit) | serveur |
| `PreferencesPoste` | locale, non synchronisée | — |

Absences à noter : il n'existe PAS de table « sujets » dans logialvia (seule `Bandes`) ; les sujets nominatifs (registre des reproducteurs) sont une fonction d'LogiAgriERP (BS3) à décider (Q-ELV-8). Liste complète et dictionnaire : `30_DATABASE_ENGINEERING.md` et `logialvia/docs/D1_Modele_Donnees_ERD_Dictionnaire.md`.

## 6. Exigences de sécurité, hors ligne, PWA, import

| ID | Exigence | Source | Vérification |
|---|---|---|---|
| SR-040 | Mots de passe hachés au serveur (`Hash::make`, `Password::defaults()`, SANS `uncompromised()` : appel distant bloquant hors réseau) ; le poste ne stocke ni mot de passe ni hash ; PIN local PBKDF2-HMAC-SHA256 ≥ 100 000 itérations, sel 16 octets. | guide D-SRV-5 ; `agrierp_laravel/CLAUDE.md` | test de garde : aucune colonne `password`/`token`/`secret` dans une table du poste |
| SR-041 | Chaque route métier DOIT porter `auth` + `can:view-<module>` ; chaque méthode mutante DOIT commencer par `$this->authorize('manage-<module>')` ; aucun `Gate::before` admin ; une permission non semée est inaccessible à tous. | `agrierp_laravel/CLAUDE.md` « RBAC » | test par route directe |
| SR-042 | Le poste DOIT refléter la matrice des droits reçue du serveur (2e niveau) ; le serveur ne sert au poste que les tables que le compte peut lire. | guide D-SRV-4 | test de périmètre de tirage |
| SR-043 | Verrou de connexion : 5 échecs → 15 min, persisté côté serveur (le prototype ne persistait pas). | F1 ; I3 §6 | test |
| SR-044 | Journaux : `audit_logs` (actions significatives, auteur, entité) ; `security_logs` (`echec_connexion`, jamais le mot de passe). | I3 §6 ; B6 BR-ADM-003 | test |
| SR-045 | Téléversement logo/favicon : type réel par signature, taille ≤ 2 Mo, nom regénéré (UUID). | I3 §2 | test |
| SR-046 | Modales événementielles (`open-modal`), jamais `@if($showModal)` ; toasts `dispatch('toast', …)` ; classes Tailwind statiques ; Alpine démarré par Livewire. | `agrierp_laravel/CLAUDE.md` « Livewire / Blade » | garde sur les sources |
| SR-047 | Hors ligne au poste : toute saisie du périmètre B1 §5 fonctionne sans réseau ; une ligne non envoyée se dit « Pas encore envoyé » ; hors ligne n'est PAS une erreur. | B3 ; guide bloc 16 | test hors ligne |
| SR-048 | Déclencheurs de synchronisation : ouverture, retour du réseau, toutes les 5 min (réglable), 5 s après un geste, fermeture, sur demande ; réessais 30 s, 2 min, 5 min, 15 min, 1 h ; un refus 4xx n'est pas réessayé ; 401/403 suspend. | guide bloc 16 | test |
| SR-049 | PWA : `manifest.webmanifest` + `sw.js` ÉTROIT (statique seulement, page d'attente hors ligne, jamais d'HTML authentifié, `/api/` et `/livewire/` exclus, `VERSION` à chaque déploiement). Hors ligne navigateur : À CONCEVOIR. | guide bloc 20 ; `agrierp_laravel/public/sw.js` | `PwaEtPolicesLocalesTest` |
| SR-050 | Import en masse : modèle xlsx à télécharger, validation ligne à ligne avant écriture, aperçu, rapport d'erreurs en français, transaction unique par lot, idempotence par clé naturelle. À CONCEVOIR. | guide bloc 21 | tests du bloc 21 |
| SR-051 | Sauvegarde : fichier généré, jamais le jeton e-MECeF en clair (chiffré par `APP_KEY`) ; restauration différée au redémarrage avec 4 contrôles (signature SQLite, `integrity_check`, tables clés, `user_version` ≤ version). | F8 ; `agrierp_laravel/app/Services/SauvegardeService.php` | test |
| SR-052 | Remise à zéro des données de test : mode « Données de Test » (faux par défaut) + rôle admin ; aperçu avec nombre réel de lignes ; journaux d'audit conservés. | F8 | test |
| SR-053 | Aucun export de base (`*.sql`), aucune archive, aucun `.env` versionné ; la base se reconstruit par `php artisan migrate:fresh --seed`. | `CLAUDE.md` racine | `git ls-files` |
| SR-054 | Données du poisson : la ration se calcule sur la biomasse (`poids_moyen_g`, `biomasse_g` = effectif × poids moyen, barème en % de biomasse par classe de poids) ; une vente ou récolte de poisson porte `sold_weight_kg`, `sold_count` et `count_is_estimated` ; l'effectif baisse de `sold_count`. TRANCHÉ (DV-01, DV-02). | `16_` DV-01, DV-02 ; `30_` | test |
| SR-055 | Incubation : la durée (défaut 28 j), la fenêtre d'éclosion (26–28 j pour la pintade) et le mode (couveuse / couvaison naturelle) sont des PARAMÈTRES stockés, jamais des constantes ; mirages J7, J14 et transfert J25 génèrent des rappels. TRANCHÉ (DV-03). | `16_` DV-03 | test |
| SR-056 | Seuils d'autonomie de provende : `autonomy_alert_days` (défaut 7) et `autonomy_critical_days` (défaut 3), par ferme, modifiables par l'admin ; critique < alerte. TRANCHÉ (DV-04). | `16_` DV-04 | test |
| SR-057 | Quatre rôles (`admin`, `comptable`, `caissier`, `animalier`) ; la matrice des droits est la source unique et le code la suit : `/inventaire` exige `view-stocks` ; le caissier a `view-facturation` sans `manage-facturation` ; test par (rôle, route) pour 4 rôles. TRANCHÉ (DV-06, DV-07). | `16_` DV-06, DV-07 ; `20_` §3 | `RbacParRouteTest` |

## 7. Hypothèses et dépendances (à dater)

- Serveur d'hébergement et nom de domaine HTTPS : À DÉFINIR (Q-HEB-1).
- Windows 10/11 64 bits avec VC++ Redistributable (`sqlite3_flutter_libs`) [B3 §6, B5 NFRS-PORT-01].
- Imprimante ou export PDF de repli [B3 §6].
- Flutter figé (`.fvmrc`) ; PHP 8.3 ; Composer ; Node pour `npm run build` (manifeste Vite requis par la suite de tests) [`CLAUDE.md` racine].
- Boîtier MeCeF (Eltrade CC300) : À VENIR, non construit à LogiAgriERP ; ne PAS promettre.

## 8. Questions ouvertes

Nouvelles questions Q-DV-1 à Q-DV-8 (DV-08 à DV-15 : réponses et valeurs par défaut du 08/11/2026) : `16_DECISIONS_VALIDEES.md` §4. Q-HEB-1 (hébergement), Q-MEC-1 (mode e-MECeF/boîtier), Q-ADM-1 (politique de mot de passe), Q-PWA-1, Q-IMP-1 : voir `10_BRS_BUSINESS_REQUIREMENTS.md` §6. Spécifique : **Q-SYN-1** Amorce-t-on le serveur depuis la base Drift des postes déjà en service (import dédié) ou par le premier envoi (lignes `pending`) ? **Q-SYN-2** Format et reprise de la numérotation (`FV-AAAA-NNN`) attribuée par le serveur : continue-t-on la séquence existante ?
