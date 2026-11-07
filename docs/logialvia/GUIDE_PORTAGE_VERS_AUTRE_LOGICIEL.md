# GUIDE DE PORTAGE LogiAgriERP → LogiALVIA (dépôt `massenon/logialvia`)

Rédigé le 07/11/2026 depuis le monorepo AgriERP (branche `claude/sleepy-dijkstra-uvt68t`), pour une session Claude Code qui ne connaît PAS LogiAgriERP. Il a été adapté après lecture du dépôt cible, cloné en lecture seule dans `/home/user/massenon/logialvia`.

> **Décision du client, 07/11/2026 : « on va CRÉER LE WEB » de LogiALVIA** (aujourd'hui Flutter seul). Ce guide change donc de posture : LogiALVIA aura un serveur web (Laravel recommandé, pour réutiliser le code), et la doctrine d'AgriERP « la vue web est le maître, le poste lui est fidèle, la parité est exécutée contre le vrai serveur » **s'applique de nouveau à la cible**. Les blocs 1 à 13 décrivent des règles métier qui valent avec ou sans serveur ; leurs mentions « sans serveur » décrivent l'état ACTUEL de logialvia (Flutter seul) et cèdent la place aux règles du bloc 14 dès que le serveur existe. Sept blocs s'ajoutent (15 à 21) : appairage, synchronisation, modale de synchronisation, notifications et alertes, MeCeF, PWA hors connexion (**À CONCEVOIR : n'existe pas dans LogiAgriERP**), importation en masse par tableur (**À CONCEVOIR : n'existe pas dans LogiAgriERP**). Tout ce qui est marqué « À CONCEVOIR » est une proposition à valider, jamais un constat.

**Convention de chemins.** Sans préfixe d'origine, un chemin est dans LogiAgriERP, relatif à la racine du monorepo (`agrierp_laravel/…` = web, `agrierp_flutter/…` = poste). `logialvia_app/…` et `logialvia/docs/…` = dépôt cible. `NEW:` = fichier à créer dans la cible. Tous les chemins hors `NEW:` ont été vérifiés par `ls` à la rédaction.

**Ce que la session cible peut ne pas avoir sous la main.** Elle n'a, au départ, ni PHP ni le web AgriERP. Les règles Laravel citées ici sont donc données EN CLAIR (formules, messages, jeux de cas calculés à la main) : le jeu de cas de chaque bloc se recopie tel quel en test unitaire Dart, et il reste utile après coup comme entrée de la parité. **Dès que le web de LogiALVIA existe (bloc 14), la parité est EXÉCUTÉE contre son vrai PHP** (`agrierp_flutter/test/php_laravel.dart` est le modèle) ; les jeux de cas à la main ne disparaissent pas. Le code source d'AgriERP reste la référence si le dépôt est joignable.

## Sommaire

0. État des lieux de logialvia (filières, écrans, écarts, contradictions de doctrine)
1. Tableau récapitulatif et ordre de portage
2. Bloc 1 — Fiches journalières par filière (effectif calculé)
3. Bloc 2 — Gestion des utilisateurs
4. Bloc 3 — Boutons Réduire / Agrandir / Fermer
5. Bloc 4 — Sélecteur d'exercice et modes N / N+1 / consultation
6. Bloc 5 — Rationnement automatique
7. Bloc 6 — Prophylaxie automatique et fenêtre « Rappels du jour »
8. Bloc 7 — Import et export (ce qui existe VRAIMENT)
9. Bloc 8 — Compilation avec le Flutter stable, version figée
10. Bloc 9 — Empreinte du plan comptable SYSCOHADA
11. Bloc 10 — Build et distribution Windows
12. Bloc 11 — Bascule et clôture d'exercice
13. Bloc 12 — Bandes et sujets, toutes les actions
14. Bloc 13 — Seuils, plan comptable, écriture manuelle, clôture, immobilisations, aide
15. Bloc 14 — Transversal : doctrine, architecture serveur (schéma partagé, UUID, rôles, mots de passe), ordre de construction du web
16. Bloc 15 — Appairage web ↔ poste
17. Bloc 16 — Synchronisation envoi / réception
18. Bloc 17 — Modale de synchronisation dans la barre du haut (web ET poste)
19. Bloc 18 — Notifications, alertes de stock et rappels VMS automatiques
20. Bloc 19 — Module MeCeF, poste ET web
21. Bloc 20 — PWA du poste avec travail hors connexion — À CONCEVOIR (n'existe pas)
22. Bloc 21 — Importation en masse par tableur xlsx — À CONCEVOIR (n'existe pas), priorité haute
23. Check-list de démarrage

---

## 0. État des lieux de logialvia

**Nature.** Application Flutter SEULE AUJOURD'HUI, « Gestion intégrée ALLMANY ET COMPAGNIE » (Natitingou), 31 écrans issus d'un prototype HTML (`logialvia/docs/03_INVENTAIRE_31_ECRANS.md`), Windows en priorité, hors ligne par construction (`logialvia/docs/A1_MASTER_PROMPT.md` §5 : « pas de backend serveur pour cette phase »). **Cette phase est close par la décision du client du 07/11/2026 : le web va être créé** (voir le cadre ci-dessous et le bloc 14) ; la mention « pas de backend » de A1 §5 est à amender dans les documents de logialvia. Pubspec `logialvia_app/pubspec.yaml` : `sdk: ^3.12.2`, Drift 2.34.3 (lock), `provider`, `go_router`, `window_manager`, `pdf`/`printing`, `fl_chart`, `crypto`, `flutter_secure_storage`, `http` (utilisé UNIQUEMENT pour e-MECeF, `logialvia_app/lib/commercial/domain/services/transmission_mecef.dart` : aucune synchronisation de données ; avec le web, le module e-MECeF passe côté serveur : bloc 19). Schéma Drift v26 (`logialvia_app/lib/core/database/app_database.dart`, `versionSchema`). 62 fichiers de test dans `logialvia_app/test/`.

**Architecture réelle** (≠ celle décrite dans `logialvia/docs/02_ARCHITECTURE.md`, qui montre `data/domain/presentation` à la racine) : par MODULE puis par couche, `logialvia_app/lib/<module>/{data,domain,presentation}` avec modules `administration`, `approvisionnement`, `commercial`, `comptabilite`, `core`, `elevage`, `pilotage`, `rapports`. `domain/{entities,repositories,services,usecases}` sans Flutter ni Drift ; `data/{tables,repositories,seed}` (Drift) ; `presentation/{screens,viewmodels}` (ChangeNotifier). Injection manuelle par constructeur (pas de get_it). Résultat typé : `logialvia_app/lib/core/resultat/resultat.dart` (`Succes` / `Echec`).

**Filières présentes dans l'élevage** (`logialvia_app/lib/elevage/domain/entities/configuration_espece.dart`, `ConfigurationsEspeces`) : les SIX identifiants `goliaths`, `pintades`, `lapins`, `poissons-chats`, `poulets`, `pondeuses` existent DÉJÀ, pilotés par UN SEUL écran générique (`logialvia_app/lib/elevage/presentation/screens/fiche_espece_screen.dart` + `logialvia_app/lib/elevage/presentation/viewmodels/fiche_espece_view_model.dart`, exigence de `logialvia/docs/A2_STRICT_AVOID.md` §5 et §15).

| Filière | Catégories de logialvia (ration g/j) | Catégorie « commercialisée » | Catégories d'AgriERP pour comparaison |
|---|---|---|---|
| Goliaths | Poussins 30 · Goliathau 60 · Mature 110 | Goliathau | VOL-1 : Poussin 30 · Jeune 80 · Reproducteur 130 |
| Pintades | Poussins 30 · Pintadau 60 · Mature 110 | Pintadau | idem (aucune pintade dans AgriERP, voir bloc 1) |
| Lapins | Lapereau 30 · Chair 60 · Reproducteur 110 | Chair | Sous-mères 30 · Jeune 60 · Reproducteur 120 |
| Poissons-Chats | Alevin 30 · Juvénile 60 · Mature 110 (barème « non confirmé ») | Juvénile | AUCUNE (pisciculture absente d'AgriERP) |
| Poulets | Poussin 30 · Poulette 60 · Adulte 110 | Poulette | VOL-1 : Poussin · Jeune · Reproducteur |
| Pondeuses | Poussin Ponte 30 · Poussin Croissance 60 · Poulette 80 · Pondeuse 110 (4) | Pondeuse | VOL-2 : mêmes 4 stades, libellés « Poussin ponte », « Poussin en croissance » |

**Mécanisme d'effectif de logialvia aujourd'hui** (`logialvia_app/lib/elevage/domain/services/calcul_fiche_journaliere.dart`, `logialvia_app/lib/elevage/domain/usecases/enregistrer_journee_usecase.dart`) : effectif par catégorie CALCULÉ (BR-ELV-001 à 007 dans `logialvia/docs/B6_Regles_Metier.md`), achats ET naissances → catégorie la plus jeune, ventes → UNE seule catégorie « commercialisée », morts et dons par catégorie, cascade jusqu'au premier jour non saisi, jamais de pourcentage fixe. Stock d'œufs des pondeuses (`CalculStockOeufs`, SRH(J+1) = Stock final(J)) déjà correct.

**Écarts avec ce que le client attend** (donc ce que ce guide apporte) :

| # | Manque dans logialvia | Bloc |
|---|---|---|
| E1 | Aucun DÉPART par catégorie : le 1er jour part de 0 (`repartitionInitiale(0)`) ; la répartition 35/35/30 existe mais n'est pas appelée en production | 1 |
| E2 | Fiche unique par ESPÈCE et par jour (`UNIQUE(espece, date)` dans `logialvia_app/lib/elevage/data/tables/fiche_journee_table.dart`), pas par bande : plusieurs bandes d'une filière se mélangent | 1, 12 |
| E3 | Ventes non ventilées par catégorie (toute vente va à la catégorie commercialisée) ; compteur `fiche_ventes_jour` par espèce seulement ; aucun lien produit → catégorie | 1 |
| E4 | Pas de passage de stade (une catégorie ne se vide jamais vers la suivante) : les effectifs des catégories dérivent | 1 |
| E5 | Pas de refus motivés, pas de stade de bande, pas de colonnes génériques repro/sevre/jeune/quatre | 1 |
| E6 | Bandes : entité `Bande` + dépôt minimal (`bandesRepository` : charger, couvrant, créer, clôturer) ; pas d'écran « Gestion des Bandes », ni transferts, transformation, dons ventilés, sujets | 12 |
| E7 | Utilisateurs : création et suppression seulement ; pas de modification, archivage, réinitialisation par l'administrateur ; la modale « Mot de passe oublié » est informative | 2 |
| E8 | Fenêtre : `WS_OVERLAPPEDWINDOW` + `window_manager` (barre système) ; pas de boutons dans la barre du haut | 3 |
| E9 | Sélecteur d'exercice : seulement dans le module Comptabilité (`SelecteurExercice` de `logialvia_app/lib/comptabilite/presentation/screens/widgets/communs_compta.dart`) ; pas de barre du haut, pas de N+1, pas de lecture seule globale | 4 |
| E10 | Rappels : « Prophylaxie du Jour » s'ouvre une fois par processus depuis le tableau de bord ; pas de soins planifiés ni délais d'attente fusionnés, pas de « Ne plus afficher aujourd'hui », pas de droit | 6 |
| E11 | Aucun export tableur (xlsx/csv), aucun import (relevé bancaire, plan), pas de version Flutter figée, pas de `build_windows.bat` ni d'installateur (et aucun import en masse : bloc 21) | 7, 8, 10, 21 |
| E12 | Clôture d'exercice = verrou simple (`cloturerExercice`) sans gardes ni étapes ; pas de registre d'immobilisations ; pas d'aide flottante | 11, 13 |
| E13 | **Aucun serveur web** (décision du 07/11/2026 : il sera créé) : ni appairage, ni synchronisation, ni modale de synchronisation, clés entières au lieu d'UUID, mots de passe hachés en SHA-256 + sel au poste | 14, 15, 16, 17 |
| E14 | Alertes entièrement calculées au poste (aucune notification persistée ni planifiée) ; e-MECeF transmis par le POSTE avec un seul `POST`, sans confirmation, sans prix entiers, sans choix simple / normalisée | 18, 19 |
| E15 | Fonctions que le client croit présentes dans LogiAgriERP et qui N'Y SONT PAS : PWA avec travail hors connexion (bloc 20) et importation en masse par xlsx (bloc 21) : conceptions à valider, pas des portages | 20, 21 |

**Décision du client du 07/11/2026 : « on va CRÉER LE WEB ».** Effets sur ce paragraphe : les contradictions 2, 5, 6 et 9 ci-dessous sont RÉVISÉES (elles supposaient « aucun serveur ») ; la doctrine « web = maître, poste fidèle, parité exécutée » s'applique de nouveau à la cible ; le schéma devient partagé (UUID, voir bloc 14) ; les mots de passe se hachent côté serveur, avec un jeton par poste (bloc 15), et JAMAIS de SHA-256 + sel en base ; e-MECeF se fait côté serveur (bloc 19). Ordre de construction : bloc 14, §14.3. Tant que le web d'un module n'existe pas, les lignes de ce guide qui disent « sans serveur » restent le mode de travail provisoire.

**Contradictions entre la doctrine de logialvia (A1/A2) et les habitudes d'AgriERP — à trancher AVANT de porter** (ne rien résoudre en silence) :

1. **Langue du code.** A1 §5 : noms de variables/fonctions en anglais par convention. Le code réel de logialvia est en réalité en FRANÇAIS (`CalculFicheJournaliere`, `enregistrerJour`). AgriERP exige le français partout. → Suivre le code existant de logialvia (français), ne pas mélanger.
2. **Source de vérité (RÉVISÉE le 07/11/2026).** AgriERP : « la vue web est le maître » ; logialvia : le prototype HTML (`logialvia/docs/A1_MASTER_PROMPT.md` §1) et ses documents. Le web va exister : **dès qu'un module a son écran web, la vue web est le maître et le poste lui est fidèle** (doctrine d'AgriERP, bloc 14 §14.1). Jusque-là, le maître d'une règle portée est le document de logialvia s'il existe (`B6`, `05_LOGIQUE_CALCUL_FORMULAIRES.md`), sinon la règle d'AgriERP donnée ici, sinon DEMANDER. Une règle d'AgriERP qui contredit un BR de B6 est signalée au client, jamais appliquée seule ; une règle de B6 qui change à cause du web est d'abord changée dans B6.
3. **Marqueurs d'écart.** AgriERP : `⚠️ ÉCART` ; logialvia : `// ECART_DELIBERE:` et `// TODO(dette):` (A1 §3.3, A2 §4). → Utiliser les marqueurs de logialvia.
4. **Traçabilité.** logialvia exige l'identifiant `BR-XXX-NNN` au-dessus de chaque règle codée (B6, Traçabilité). → Ajouter les nouvelles règles à B6 (nouveaux numéros, ex. BR-ELV-011…) puis les citer dans le code.
5. **Identifiants (RÉVISÉE le 07/11/2026).** AgriERP : UUID obligatoires (synchro). logialvia : `integer().autoIncrement()` partout. Le web impose la synchronisation : → **PASSER AUX UUID** pour les tables synchronisables, avec **migration des données existantes de logialvia** à planifier (bloc 14, D-SRV-3). Jusqu'à ce palier, ne pas ajouter de nouvelle table à clé entière si elle devra se synchroniser. Renvoi : `docs/BLUEPRINT_SYNCHRONISATION_MULTIPOSTES.md`, blocs 15 et 16.
6. **Mot de passe (RÉVISÉE le 07/11/2026).** AgriERP : le mot de passe n'est JAMAIS en base du poste (il part au serveur, qui le hache ; le poste garde un jeton et un PIN). logialvia : SHA-256 + sel en base, choix confirmé quand il n'y avait pas de serveur (`logialvia_app/lib/administration/domain/services/hachage_mot_de_passe.dart`, doc F1). Avec le web : **hash côté serveur, un jeton par poste, un PIN local PBKDF2 (≥ 100 000 itérations, `agrierp_flutter/lib/core/auth/verrou_local.dart`), et JAMAIS de SHA-256 + sel en base** (bloc 14, D-SRV-5 ; reprise des comptes existants par mots de passe temporaires). Jusqu'à la bascule, le hash local de logialvia reste en place ; ne pas le renforcer à part.
7. **Rôles.** logialvia : 3 rôles (admin, caissier, animalier ; `logialvia_app/lib/administration/domain/entities/role_utilisateur.dart`, « aucun rôle comptable »). AgriERP : 4 rôles (admin, comptable, caissier, animalier). → ✅ TRANCHÉ le 08/11/2026 (DV-07, `16_DECISIONS_VALIDEES.md`) : le client valide 4 RÔLES (admin, comptable, caissier, animalier). Ne plus lire « garder 3 ».
8. **Drift.** AgriERP : Drift 2.31, `&` indéfini sur `Expression<bool>` donc `.and()`. logialvia : Drift 2.34.3, c'est l'INVERSE (`&`, et `.and()` ne compile pas ; `logialvia/docs/K4_Retour_Experience_Bugs_Reels.md`). → Ne pas recopier les requêtes d'AgriERP : réécrire dans l'API de la version de logialvia.
9. **Tests (RÉVISÉE le 07/11/2026).** AgriERP : parité PHP exécutée (`agrierp_flutter/test/php_laravel.dart`). logialvia : tests unitaires Dart (A2 §6 : 100 % des `domain/usecases` de calcul testés). → **Les deux** : A2 §6 reste la règle (jeux de cas à la main, propriété, mutation) ET la parité exécutée contre le vrai PHP s'ajoute dès que le web du module existe. Voir bloc 14, §14.1.
10. **Documentation obsolète.** `logialvia/docs/02_ARCHITECTURE.md` (arborescence) et `logialvia/docs/11_SETUP_INSTALLATION.md` (Flutter 3.19+, sdk >=3.3.0) ne décrivent plus le code ; A2 §7 demande de les corriger quand l'écart est découvert.

---

## 1. Tableau récapitulatif et ordre de portage

Effort : S ≤ 1 jour · M 2 à 4 jours · L 5 à 10 jours · XL plus de 10 jours, à découper en jalons (une session Claude + relecture, base de la cible déjà montée ; ce sont des ORDRES DE GRANDEUR, jamais un engagement). Dépendances en numéros de bloc. **Depuis la décision du 07/11/2026 (le web sera créé)**, les blocs 14 à 17 forment le socle commun : presque tout module qui touche une donnée partagée en dépend.

| Bloc | Effort | Dépend de | Fichiers clés dans LogiAgriERP |
|---|---|---|---|
| 8 Compilation / version figée | S | — | `agrierp_flutter/lib/core/sync/sync_engine.dart` (l. 2783), `agrierp_flutter/.fvmrc`, `agrierp_flutter/build_windows.bat` |
| 14 Transversal : doctrine, socle serveur, schéma UUID (migration des données existantes), rôles, mots de passe | XL (jalons W0 à W2 : L ; migration UUID : L) | — | `agrierp_flutter/test/conformite_portage_test.dart`, `agrierp_flutter/test/php_laravel.dart`, `agrierp_flutter/test/migration_bases_reelles_test.dart`, `agrierp_laravel/app/Http/Controllers/Api/AuthController.php` |
| 3 Boutons de fenêtre | M | — | `agrierp_flutter/windows/runner/win32_window.cpp`, `agrierp_flutter/lib/core/fenetre/fenetre_poste.dart`, `agrierp_flutter/test/fenetre_poste_test.dart` |
| 2 Utilisateurs | M | 14 | `agrierp_laravel/app/Actions/SaisieUtilisateurAction.php`, `agrierp_flutter/lib/features/parametres/parametres_generaux_repository.dart` |
| 9 Empreinte plan comptable | S | — | `agrierp_laravel/app/Services/ImporterPlanSyscohadaService.php`, `agrierp_laravel/tests/Feature/ImportPlanSyscohadaTest.php` |
| 4 Exercice N / N+1 / consultation | L | 9 | `agrierp_laravel/app/Support/ExerciceChoisi.php`, `agrierp_flutter/lib/core/comptabilite/exercice_choisi.dart` |
| 11 Clôture d'exercice | L | 4 | `agrierp_laravel/app/Services/ClotureExerciceService.php`, `agrierp_flutter/lib/features/comptabilite/cloture_exercice_repository.dart` |
| 12 Bandes et sujets | L | 14 | `agrierp_laravel/app/Actions/SaisieBandeAction.php`, `agrierp_flutter/lib/features/elevage/bandes_repository.dart` |
| 1 Fiches par filière | L | 12 | `agrierp_laravel/app/Services/EffectifParCategorieService.php`, `agrierp_flutter/lib/features/elevage/effectif_par_categorie.dart` |
| 5 Rationnement | M | 1 | `agrierp_laravel/app/Support/StadePondeuse.php`, `agrierp_laravel/app/Services/AlerteAutonomieFicheService.php` |
| 6 Prophylaxie + Rappels du jour | M | 12 | `agrierp_laravel/app/Services/RappelsDuJourService.php`, `agrierp_flutter/lib/features/verrou/porte_session.dart` |
| 13 Seuils, plan, écriture, immo, aide | L | 4, 11 | `agrierp_flutter/lib/features/comptabilite/immobilisations_repository.dart`, `agrierp_flutter/lib/core/aide/aide_ecrans.dart` |
| 7 Import / export | M | 4 | `agrierp_flutter/lib/core/export/document_officiel.dart`, `agrierp_flutter/lib/core/export/export_tableur.dart` |
| 10 Build / installateur | M | 8 | `agrierp_flutter/build_windows.bat`, `agrierp_flutter/installer/agrierp.iss` |
| 15 Appairage web ↔ poste (jeton par poste, PIN, révocation, 401) | M | 14, 2 | `agrierp_laravel/app/Http/Controllers/Api/AuthController.php`, `agrierp_flutter/lib/core/auth/auth_service.dart`, `agrierp_flutter/lib/features/parametres/appairage_poste.dart` |
| 16 Synchronisation envoi / réception | XL (moteur minimal : L ; chaque table : S à M) | 14, 15 | `agrierp_laravel/app/Http/Controllers/Api/SyncController.php`, `agrierp_flutter/lib/core/sync/sync_engine.dart`, `agrierp_flutter/lib/core/sync/synchronisation_automatique.dart`, `docs/BLUEPRINT_SYNCHRONISATION_MULTIPOSTES.md` |
| 17 Modale de synchronisation (web ET poste) | M | 16, 3 | `agrierp_flutter/lib/core/sync/modale_synchronisation.dart`, `agrierp_laravel/app/Livewire/Shared/EtatSynchronisationPostes.php` |
| 18 Notifications, alertes de stock, rappels automatiques | M | 14, 16, 6 | `agrierp_laravel/app/Services/AlertesElevageService.php`, `agrierp_laravel/routes/console.php`, `agrierp_flutter/lib/features/notifications/notifications_repository.dart` |
| 19 MeCeF (poste ET web), e-MECeF côté serveur | L (boîtier : L, À VENIR) | 14, 16, 4 | `agrierp_laravel/app/Services/Mecef/MecefFactureBuilder.php`, `agrierp_laravel/app/Services/Mecef/EmecefGateway.php`, `agrierp_flutter/lib/features/ventes/choix_facture.dart` |
| 20 PWA hors connexion — À CONCEVOIR (n'existe pas), seulement si le client le confirme | XL | 14, 15, 16 | `agrierp_laravel/public/sw.js`, `agrierp_laravel/public/manifest.webmanifest`, `agrierp_laravel/tests/Feature/PwaEtPolicesLocalesTest.php` (le PWA ÉTROIT existant) |
| 21 Importation en masse par xlsx — À CONCEVOIR (n'existe pas), priorité haute | L (socle) + M pour les stocks + S à M par autre module | 14, 16 (et 12/1 pour les bandes) | `agrierp_flutter/lib/core/export/export_tableur.dart` (export seulement), `agrierp_laravel/app/Services/ProductCatalogService.php`, `agrierp_laravel/app/Services/FusionReferentielsService.php` |

**Ordre conseillé (révisé le 07/11/2026, le web sera créé)** : **socle serveur + schéma UUID** (14, 8, ossature de 2) → **appairage** (15) → **synchronisation** (16) → **modale de synchronisation** (17, avec 3 et 4 qui partagent la barre du haut) → **fiches, stocks, alertes** (12 bandes, 1 fiches par filière, 5 rationnement, 6 prophylaxie et rappels, 13a seuils, 18 notifications) → **importation en masse** (21, stocks d'abord) → **MeCeF** (19) → **comptabilité et exercices** (9, 4, 11, 13b à 13e, 7 export, 13f aide) → **build** (10) → **PWA hors connexion** (20) seulement si le client la confirme. Raison : tout module partagé exige l'identité (UUID), l'appairage et la synchronisation ; la fiche calculée suppose une bande propre (12) ; le rationnement lit l'effectif calculé ; l'import réutilise les points de passage des modules déjà construits ; MeCeF suppose le serveur et les ventes ; la comptabilité ne s'écrit au poste que par DEMANDES rejouées par le serveur ; le build clôt la chaîne. L'ordre « sans web » d'origine (socle → fenêtre → utilisateurs → plan comptable → exercices → bandes → fiches → rationnement → prophylaxie → import/export → aide → build) reste valable pour les blocs qui ne partagent aucune donnée.

---

## 2. Bloc 1 — Fiches journalières par filière (effectif calculé)

### Objectif
L'effectif de chaque catégorie est CALCULÉ à partir d'un DÉPART obligatoire et des mouvements du jour ; l'éleveur ne saisit jamais un effectif. Les ventes sont ventilées par catégorie d'après le produit vendu ; les passages de stade déplacent des sujets d'une catégorie à la suivante ; les refus sont motivés.

### Règle (exacte, rien d'inventé)

**Vocabulaire générique AgriERP.** Trois emplacements `repro`, `sevre`, `jeune`, plus `quatre` pour les pondeuses. Colonnes par emplacement : `mort_<e>`, `don_<e>`, `vente_<e>` (volailles), `cat_depart_<e>` (départ), `cat_eff_<e>` (effectif calculé, jamais saisi), `passage_*`, `transfert_entree_<e>` / `transfert_sortie_<e>` (dérivés des transferts entre bandes). `quatre` s'écrit `*_4` ; `mort4` serait `mort4` en Drift : nommer `.named('mort_4')`. La somme des morts / dons / ventes ventilés = la colonne totale (`vente`, `mort`, `don`) ; les effectifs « bande » = ceux de la DERNIÈRE fiche, jamais du jour édité.

**Cascade unique.** Toute écriture d'une fiche (saisie, vente de la caisse, transfert, sujet) passe par UNE fonction de recalcul en chaîne de la bande : veille = dernière fiche ANTÉRIEURE de la même bande (un jour sauté est franchi, différence avec logialvia qui s'arrête au premier jour non saisi : à trancher, voir Questions), puis recalcul de tous les jours suivants.

**Départ (D4).** Effectif de départ par catégorie, saisi UNE fois par bande (tête de chaîne) ; somme des catégories = effectif total AU DÉBUT du jour de départ. Refus (messages exacts) :
- « Effectif de départ incomplet : les trois catégories doivent être renseignées (0 si la catégorie est vide). » (quatre stades : « … les quatre stades doivent être renseignés (0 si le stade est vide). »)
- « La somme des catégories de départ (35) ne correspond pas à l'effectif total au début du jour de départ (36). » (pondeuses : « La somme des stades de départ … »).
Le départ n'est JAMAIS déduit à l'insu de l'éleveur : le stade de la bande donne une PROPOSITION (`departDepuisStade` : stade `reproduction` → tout en `repro`, `croissance` → `sevre`, `engraissement` → `jeune` ; pondeuses : tout en Pondeuse = `repro`) reprise par un bouton « Reprendre la proposition… ». La fiche demande le départ À L'OUVERTURE (pas à la création de la bande : décision client 05/11/2026), affiche cette demande à la place de l'effectif, refuse d'enregistrer sans lui ; les jours antérieurs au départ ne sont pas saisissables ; les anciennes fiches restent consultables.

**Passage (D3).** Transfert d'une catégorie source vers la suivante, total inchangé ; refusé au-delà de la source APRÈS ses autres mouvements du jour (veille + entrées − morts − dons − ventes, plancher 0, entrée du passage précédent incluse). Message lapins : « Passage de stade refusé : 15 sujet(s) à faire passer, mais la catégorie source n'en compte que 12. » ; le passage appliqué est ramené à la source ; plusieurs refus se joignent par une espace.

**Formules — Lapins** (`agrierp_laravel/app/Services/EffectifParCategorieService.php`, `calculerJour`, chaque catégorie bornée à 0 ; v = veille, p = passage Sous-mères → Jeune ; `sevre` = Sous-mères, `jeune` = Jeune) :
- R = max(0, Rv − mort_R − don_R + transfert_entrée − transfert_sortie)
- S_avant = Sv + achat + né − mort_S − don_S (+ transferts) ; passage appliqué = min(p, max(0,S_avant)) ; S = max(0, S_avant − passage appliqué)
- J = max(0, Jv + passage appliqué − vente − mort_J − don_J (+ transferts))
- ⚠️ Le commentaire de tête du fichier dit « achat de lapins → Jeune » : OBSOLÈTE (écrit avant le glossaire du 17/10/2026). Le CODE envoie achats et nés en `sevre` (Sous-mères). Le code fait foi.
- **Lapins seulement : `null` = INCONNU**, jamais lu comme 0. Un mouvement absent rend inconnues les seules catégories qu'il touche, et l'inconnu se propage aux jours suivants. Une bande sans départ n'a pas de chaîne. Somme ≠ total = avertissement (D8), pas un blocage. Glossaire : Reproducteur (barème « Lapine Mère / Reproducteur » 120 g/j), Sous-mères 30, Jeune 60 (ancien « Lapin de Chair » renommé « Jeune », ancien « Jeune » renommé « Sous-mères », 17/10/2026). Le passage s'appelle « Sevrage du jour (Sous-mères → Jeune) ».

**Formules — Volailles reproductrices VOL-1** (`calculerJourVolailles`, aviculture hors stade `ponte`) : R = Rv − vente_R − mort_R − don_R ; J = Jv + achat − vente_J − mort_J − don_J + p ; P = Pv + éclosions − vente_P − mort_P − don_P − p (planchers à 0 ; ACHATS → Jeune, ÉCLOSIONS → Poussin ; p = Poussin → Jeune). `repro` = Reproducteur, `jeune` = **Jeune** (jamais « Poulet », jamais « Jeune à maturité »), `sevre` = Poussin. **JAMAIS de catégorie inconnue** (différence voulue avec les lapins) : un mouvement absent vaut 0 ; départ obligatoire.

**Formules — Pondeuses VOL-2** (`calculerJourPondeuses`, stade `ponte`, quatre stades aux libellés EXACTS du barème : « Poussin ponte (0 à 2 mois) », « Poussin en croissance (2 à 4 mois) », « Poulette (4 à 5.5 mois) », « Pondeuse (6 à 18 mois) ») : PP = PPv + éclosions − vente − mort − don − p1 ; PC = PCv − vente − mort − don + p1 − p2 ; PL = PLv + **achat** − vente − mort − don + p2 − p3 ; PO = POv − vente − mort − don + p3. Emplacements : PP=`quatre`, PC=`sevre`, PL=`jeune`, PO=`repro`. Passages : p1=`passage_4_sevre`, p2=`passage_sevre_jeune`, p3=`passage_jeune_repro`. Œufs, casse et stock d'œufs INCHANGÉS.

**Ventes ventilées.** `products.categorie_effectif` (nullable ; valeurs `reproducteur|jeune|poussin` et, pondeuses, `poussin_ponte|poussin_croissance|poulette|pondeuse`) dit dans quelle catégorie une vente décrémente. La FAMILLE de la bande décide laquelle s'applique. Refus AVANT toute écriture (caisse ET import) : produit sans catégorie ; bande sans départ ; vente datée avant le départ ; catégorie d'une autre famille. Défaut posé à la migration d'après le nom (`CategorieVolaille::devinerDepuisLeNom`, `StadePondeuse::devinerDepuisLeNom` : un nom ambigu comme « Poussin d'un jour » reste sans stade). Vente des fiches connues : la colonne `vente` reste la SOMME ; la vente d'un produit « abattage » (transformation) range ses sujets en Jeunes (reproducteurs) ou en Pondeuse (pondeuses). Un don se saisit sur la fiche (ventilé), pas dans le journal des sujets.

**Stade de bande.** `stage` de la bande ∈ `reproduction|croissance|engraissement|ponte` (aviculture) ; `especeDuLot` : aviculture + `ponte` → famille `volailles_ponte`, aviculture sinon → `volailles_repro`.

### Jeu de cas à recopier (calculé à la main, vérifié sur le code)
Ces valeurs doivent sortir de la fonction Dart pure, par TDD, avant de brancher quoi que ce soit.

- Lapins nominal : veille R=10, S=5, J=20 ; achat 3, né 4, vente 6, mort_R 1, mort_J 2, passage 5, autres 0 → **R=9, S=7, J=17** (total 33). S_avant = 5+3+4 = 12.
- Lapins refus : même jour, passage 15 → passage appliqué 12, **S=0, J=24**, refus = message ci-dessus (12).
- Lapins inconnu : `vente` absente → J = inconnu (`null`), R=9 et S=7 restent connus.
- Départ lapins : (10, 5, 20) total 35 → valide ; total 36 → le message « La somme … (35) … (36). ».
- Volailles repro : veille R=10, P=20, J=30 ; achat 5, éclosions 8, vente_R 1, vente_J 4, mort_J 2, mort_P 1, p=6 → **R=9, J=35, P=21** (total 65). Refus si p=30 : source P après autres mouvements = 20+8−1 = 27 → appliqué 27, **P=0, J=56**.
- Pondeuses : veille PP=100, PC=50, PL=30, PO=200 ; éclosions 20, achat 10, vente_PO 5, vente_PL 2, mort_PP 3, mort_PC 1, mort_PO 4, p1=40, p2=10, p3=5 → **PP=77, PC=79, PL=43, PO=196** (total 395).
- Plancher : mort supérieure à l'effectif → 0, jamais négatif (BR-ELV-001 de logialvia).

### Fichiers de référence (AgriERP)
- Serveur (règle maître, à lire pour les messages) : `agrierp_laravel/app/Services/EffectifParCategorieService.php`, `agrierp_laravel/app/Support/EffectifCategoriesJour.php`, `agrierp_laravel/app/Support/CategorieVolaille.php`, `agrierp_laravel/app/Support/StadePondeuse.php`, `agrierp_laravel/app/Support/CategorieRationLapin.php`, `agrierp_laravel/app/Support/MotifsRefusPush.php`, `agrierp_laravel/app/Actions/RecordSaleOnFicheElevageAction.php` (cascade, ventilation), `agrierp_laravel/app/Actions/TransferBetweenLotsAction.php`, `agrierp_laravel/app/Livewire/Elevage/FicheLapins.php`, `agrierp_laravel/app/Livewire/Elevage/FicheReproducteurs.php`, `agrierp_laravel/app/Livewire/Elevage/FichePondeuses.php`.
- Migrations du schéma : `agrierp_laravel/database/migrations/2026_10_15_000001_add_effectif_par_categorie_to_livestock_daily_entries_table.php`, `…/2026_11_05_000001_add_vente_par_categorie_to_livestock_daily_entries_table.php`, `…/2026_11_05_000002_add_categorie_effectif_to_products_table.php`, `…/2026_11_05_000003_ajouter_rations_reproducteurs_volaille.php`, `…/2026_11_05_000004_add_stades_pondeuses_to_livestock_daily_entries_table.php`, `…/2026_11_05_000005_add_quatre_to_livestock_transfers_categorie.php`, `…/2026_11_05_000006_ajouter_stades_pondeuses_produits.php` (chemins relatifs à `agrierp_laravel/database/migrations/`).
- Traduction Dart déjà faite (modèle de code pur, à relire avant d'écrire le vôtre) : `agrierp_flutter/lib/features/elevage/effectif_par_categorie.dart`, `agrierp_flutter/lib/features/elevage/categorie_volaille.dart`, `agrierp_flutter/lib/features/elevage/stade_pondeuse.dart`, `agrierp_flutter/lib/features/elevage/categorie_ration_lapin.dart`, `agrierp_flutter/lib/features/elevage/jour_categories.dart`, `agrierp_flutter/lib/features/elevage/fiche_journaliere_repository.dart`, `agrierp_flutter/lib/features/elevage/fiche_categories_vue.dart`, `agrierp_flutter/lib/features/elevage/fiche_reproducteurs_screen.dart`, `agrierp_flutter/lib/features/elevage/fiche_pondeuses_screen.dart`.

### (a) Ce qui existe déjà dans logialvia
`logialvia_app/lib/elevage/domain/entities/configuration_espece.dart` (6 filières, glossaire par filière), `logialvia_app/lib/elevage/domain/services/calcul_fiche_journaliere.dart` (`CalculFicheJournaliere.calculerJour`, `MouvementsJour`, `EffectifsJour`, `provendeTotaleGrammes`, `CalculStockOeufs`), `logialvia_app/lib/elevage/domain/usecases/enregistrer_journee_usecase.dart` (cascade), `logialvia_app/lib/elevage/data/tables/fiche_journee_table.dart`, `logialvia_app/lib/elevage/data/tables/bandes_table.dart`, `logialvia_app/lib/elevage/domain/entities/bande.dart`, `logialvia_app/lib/elevage/presentation/screens/fiche_espece_screen.dart`, `logialvia_app/lib/elevage/presentation/screens/page_poulets_pondeuses.dart` (2 onglets). Tests : `logialvia_app/test/elevage/calcul_fiche_journaliere_test.dart` (28 cas), `logialvia_app/test/elevage/enregistrer_journee_usecase_test.dart`, `logialvia_app/test/elevage/glossaire_filieres_test.dart`, `logialvia_app/test/elevage/stock_oeufs_cascade_test.dart`.

### (b) Ce qui manque
Départ par catégorie (E1), fiche par bande (E2), ventes ventilées + `categorie_effectif` du produit (E3), passages (E4), refus motivés / stade de bande / colonnes génériques (E5), inconnu des lapins, écran de demande de départ.

### (c) Comment le porter dans l'architecture de logialvia
1. **Domain pur d'abord** (aucun Flutter, aucun Drift) : étendre `ConfigurationEspece` avec, par catégorie, un `emplacement` générique (`repro|sevre|jeune|quatre`) plutôt qu'un index nu, et une `famille` (`lapins`, `volaillesRepro`, `volaillesPonte`, `neutre`). Créer `NEW:logialvia_app/lib/elevage/domain/services/effectif_par_categorie.dart` (fonctions pures `calculerJour…`, `verifierDepart`, `departDepuisStade`) à partir de `calculer_fiche_journaliere.dart` SANS le casser : garder la forme actuelle (`CalculFicheJournaliere`, BR-ELV-002/003) comme famille « neutre » tant que la filière n'a pas reçu sa décision client ; ne basculer une filière qu'avec son jeu de cas.
2. **Entités** : `MouvementsJour` gagne `ventesParCategorie`, `passages` (liste), `transfertsEntree/Sortie` ; `JourneeElevage` gagne `departParCategorie` (tête de chaîne) et `bandeId`. Résultat de calcul riche (valeur + refus), comme `EffectifCategoriesJour` : `Resultat<…>` de `core/resultat` pour les refus.
3. **Drift** : migration `from < 27` (cf. règle de migration explicite de `logialvia_app/lib/core/database/app_database.dart`, `versionSchema`) : `fiche_journee` ajoute `bande_id` (nullable puis rempli par une bande implicite par espèce pour les données existantes), `cat_depart_1..4`, `vente_cat_1..4`, `passage_1`, `passage_2`, `passage_3`, `transfert_*` ; clé unique `(bande_id, date)` ; `produits_vendables` ajoute `categorie_effectif` (texte nullable). Nommer à la main les colonnes `_4`. `dart run build_runner build --delete-conflicting-outputs` ; JAMAIS d'édition du `.g.dart`. Test de migration idempotente sur le modèle de `logialvia_app/test/core/migration_idempotente_test.dart` et `migration_v15_test.dart`.
4. **Use case unique** : `EnregistrerJourneeUseCase` reste le seul écrivain d'une fiche ; la cascade devient « recalculer la chaîne de la bande » appelée aussi par le POS (`VenteValideeEvent`, `logialvia_app/lib/core/events/domain_event.dart`) et par les transferts. Aucun calcul dans `fiche_espece_view_model.dart` ni dans `fiche_espece_screen.dart`.
5. **Vente → catégorie** : `ventes_repository_drift.dart` (écrit via l'événement) ne touche plus `fiche_ventes_jour` seul ; un `RepercuterVenteUseCase` NEW lit `categorie_effectif`, refuse avec le motif AVANT toute écriture (BR-VTE-002 : atomique), appelle la cascade.
6. **Écran** : un seul `FicheEspeceScreen` générique ; ajouter le bloc « Effectif de départ par catégorie (obligatoire) » (affiché à la place de l'effectif tant que la bande n'a pas de départ), les champs de passage (selon la famille), les ventes par catégorie en LECTURE SEULE. Filière sans configuration décidée = comportement actuel.
7. **Déclinaison par filière du client :**
   - **Lapins** : porter 15.39 à 15.42 tels que décrits (3 catégories, `null` = inconnu, passage Sous-mères → Jeune). ⚠️ logialvia a « Lapereau / Chair / Reproducteur » (30/60/110) : le glossaire du 17/10/2026 d'AgriERP (Reproducteur 120 / Sous-mères 30 / Jeune 60) est une décision de l'AUTRE client ; ne pas renommer sans accord (questions Q1, Q2).
   - **Poulets / Pondeuses** : logialvia a une page à deux onglets. Pondeuses = VOL-2 (4 stades déjà aux bonnes valeurs de ration 30/60/80/110 ; libellés de logialvia « Poussin Ponte » / « Poussin Croissance » ≠ « Poussin ponte » / « Poussin en croissance » d'AgriERP : prendre ceux de logialvia, la règle ne dépend pas du libellé). Poulets (chair) : « Poussin / Poulette / Adulte » ne correspond PAS à VOL-1 (Reproducteur / Jeune / Poussin) : mécanisme réutilisable (départ, ventes ventilées, passage Poussin → suivante), catégories et rations à confirmer (Q3, Q4).
   - **Goliaths** : « poulet goliath » = volaille : réutiliser VOL-1 TEL QUEL (mécanisme), avec les trois catégories de logialvia (Poussins / Goliathau / Mature). AgriERP range « Poulet goliath (sujet vif) » en Jeune par défaut (nom du produit) ; la catégorie commercialisée de logialvia est Goliathau (milieu) — même place.
   - **Pintades** : volaille, mécanisme VOL-1 à l'identique (Poussins / Pintadau / Mature). ZONE NON COUVERTE par AgriERP : aucune règle pintade n'y existe (seul un produit « Pintade », SKU AVI-002, est semé : `agrierp_laravel/database/seeders/ProductsSeeder.php`). Aucune ration ni durée de stade ne s'en déduit.
   - **Poissons-Chats** : ZONE NON COUVERTE (aucune pisciculture dans AgriERP). logialvia a déjà Alevin / Juvénile / Mature et un barème « non confirmé ». Ne PAS inventer de règle ; voir Questions.
8. **Décisions à garder (AgriERP)** : effectif jamais « inconnu » pour les volailles ; départ demandé à l'ouverture de la fiche, pas à la création de la bande ; libellé « Jeune » jamais « Poulet » (vocabulaire de l'autre client : pour logialvia, voir Q3) ; libellés du barème en égalité stricte ; un don ne se saisit pas dans le journal des sujets.

### Pièges (déjà payés)
- Effectif de bande = dernière fiche, pas le jour édité.
- Jour sauté : la cascade doit franchir le trou ; l'absorbeur ne doit pas recalculer un jour d'une AUTRE bande.
- Une vente et une fiche créées au même instant pour le même (bande, jour) : un seul écrivain, transaction unique (au poste : deux ViewModels concurrents ; avec le web, deux postes : le serveur fusionne sous verrou, bloc 16).
- Un test de migration depuis une VRAIE ancienne base : ajouter les colonnes avec `_ajouterColonneSiAbsente`-équivalent ; un `TableMigration` recopie TOUTES les colonnes du schéma courant (colonnes ajoutées plus tard absentes → « no such column »).
- Données sans chaîne : ne rien réécrire ; demander le départ à l'ouverture.
- Une journée portant des ventes d'avant la ventilation ne peut pas recevoir le départ : le saisir un autre jour.
- Fixtures de tests génériques : tout test dont l'objet est autre doit poser un départ ou utiliser une filière neutre, sans contourner un refus.

### Tests à reprendre
- Jeu de cas ci-dessus, en `NEW:logialvia_app/test/elevage/effectif_par_categorie_test.dart` ; plus un test « propriété » : sur 500 jours aléatoires, somme des catégories = total pour les volailles (AgriERP : parité PHP sur 500 jours / 600 combinaisons ; ici propriété + cas écrits à la main, jamais produits par le code testé).
- Tests de référence AgriERP à lire : `agrierp_flutter/test/effectif_par_categorie_test.dart`, `agrierp_flutter/test/cascade_categories_test.dart`, `agrierp_flutter/test/volailles_effectif_test.dart`, `agrierp_flutter/test/fiche_pondeuses_stades_test.dart`, `agrierp_flutter/test/fiches_ventilation_sync_test.dart`, `agrierp_laravel/tests/Feature/EffectifParCategorieServicePurTest.php`, `agrierp_laravel/tests/Feature/VolaillesEffectifParCategorieTest.php`, `agrierp_laravel/tests/Feature/PondeusesEffectifParStadeTest.php`.
- Test de mutation (doctrine) : retirer la règle (ex. le plancher, le refus de passage) doit faire rougir au moins un test.

### Questions à poser au client
- **Q1 Lapins** : garde-t-on « Lapereau / Chair / Reproducteur » (logialvia) ou adopte-t-on Reproducteur / Sous-mères / Jeune ? Où vont les achats et les naissances ? Les catégories lapins peuvent-elles être « inconnues » ?
- **Q2 Rations lapins** : 30/60/110 (logialvia) ou 30/60/120 (AgriERP) ?
- **Q3 Poulets** : Poussin / Poulette / Adulte est-il confirmé ? Le client AgriERP a imposé « Jeune » (jamais « Poulet ») ; le prototype de logialvia garde « Poulet ». Poulets de chair ou reproducteurs ?
- **Q4** Où vont les ACHATS d'une volaille (catégorie la plus jeune, règle B6 BR-ELV-002 ; AgriERP : Jeune pour les reproducteurs, Poulette pour les pondeuses) ?
- **Q5 Départ** : obligatoire avant toute journée (AgriERP) ou conserver la saisie libre actuelle ? Demandé à la création de la bande ou à l'ouverture de la fiche ?
- **Q6 Cascade** : s'arrête-t-elle au premier jour non saisi (BR-ELV-006 de logialvia) ou franchit-elle les jours sautés (AgriERP) ?
- **Q7 Ventes** : chaque produit vendable doit-il porter une catégorie d'effectif ? Que faire des ventes sans catégorie (refus, comme AgriERP) ?
- **Pisciculture (Poissons-Chats)** : stades Alevin / Juvénile / Mature ou alevin / grossissement / géniteur ? Mortalité à saisir par stade ? Notion de biomasse, poids moyen cible, taux de conversion ? Cycle par bassin ou étang (bande = bassin ?) ? Passage de stade : à quelle règle (poids, âge, tri) ? Ration : par poids de biomasse (% du poids vif) ou g/j/sujet comme aujourd'hui ? Achat d'alevins (empoissonnement) = quelle catégorie ? Vente au poids ou à la pièce ?
- **Pintades** : stades et durées (pintadeau, pintade adulte), ration par stade (aujourd'hui copiée du barème avicole générique : à valider avec la Gérante), reproducteurs distincts ?
- **Goliaths** : confirme-t-on que la vente se déduit de Goliathau et non de Mature (note de `calcul_fiche_journaliere.dart`) ?

---

## 3. Bloc 2 — Gestion des utilisateurs (CRUD)

### Objectif
L'administrateur crée, modifie, archive et réactive des comptes, et réinitialise un mot de passe oublié. Plus aucune réinitialisation par e-mail.

### Règle
- **Point de passage unique** de saisie (`SaisieUtilisateurAction` côté web, `ParametresGenerauxRepository` côté poste) : règles et messages identiques. Règles : identifiant SANS arobase, unique ; rôle existant ; mot de passe selon la politique (`Password::defaults()` côté web : voir `agrierp_laravel/app/Support/PolitiqueMotDePasse.php`, `agrierp_flutter/lib/features/parametres/parametres_generaux_repository.dart` pour `motDePasseRefuse`) ; mot de passe facultatif à la modification (absent = conservé) ; jamais journalisé ni servi.
- **Suppression logique seulement** (`is_active = false`) : le compte connecté ne s'archive pas lui-même ; un compte archivé ne se modifie pas ; réactivation possible. (logialvia supprime physiquement : `supprimerUtilisateur`. À remplacer par l'archivage, BR-ADM-003 de B6 exige la journalisation.)
- **Mot de passe au coffre, jamais en base** (AgriERP, parce qu'il part au serveur) : `SyncEngine.cleMotDePasse` dans `flutter_secure_storage`, effacé après envoi. ⚠️ **Avec le web (décision du 07/11/2026), cette règle S'APPLIQUE à logialvia** : le mot de passe part au serveur, qui le hache ; le poste garde un jeton et un PIN, jamais un hash de mot de passe, et jamais de SHA-256 + sel en base (bloc 14, D-SRV-5 ; bloc 15). Le hash local actuel de logialvia n'est valable que tant que le serveur n'existe pas (contradiction 6 du §0). Dans tous les cas : jamais le mot de passe en clair, jamais journalisé, jamais dans une sauvegarde lisible.
- **MDP-1 (29/10/2026)** : plus de « Mot de passe oublié ? » par e-mail. La connexion affiche le texte NON cliquable « Contactez l'administrateur » (clé de widget `login-contacter-administrateur`). L'administrateur utilise l'icône « Réinitialiser le mot de passe » (clé `utilisateur-reinitialiser-N`) : mot de passe TEMPORAIRE (soumis à la politique), `must_change_password = true`, sessions et jetons du compte détruits, audit `user.password_reset` (auteur + compte visé, jamais le mot de passe). Refus (mêmes messages partout) : son propre compte, un compte archivé. À la connexion suivante, `EcranChangementMotDePasseObligatoire` s'ouvre AVANT le code PIN et l'accueil ; le nouveau mot de passe ne peut pas être identique au temporaire.
- **Code de secours** (dernier administrateur) : 24 caractères, affiché UNE fois, empreinte SHA-256 seule stockée, un seul code actif, usage unique, 5 échecs = blocage 15 min, nouveau code affiché après usage. Procédure imprimable : `docs/CODE_SECOURS_ADMIN.md`. Côté logialvia, l'équivalent existe en script : `logialvia_app/outils/reinitialiser_mot_de_passe_admin.dart`.

### Fichiers de référence (AgriERP)
`agrierp_laravel/app/Actions/SaisieUtilisateurAction.php`, `agrierp_laravel/app/Livewire/Parametres/GestionUtilisateurs.php`, `agrierp_laravel/app/Services/CodeSecoursService.php`, `agrierp_laravel/app/Actions/ChangerMotDePasseAction.php`, `agrierp_laravel/app/Http/Middleware/ChangementMotDePasseObligatoire.php`, `agrierp_laravel/app/Livewire/Auth/ChangementMotDePasseObligatoire.php`, `agrierp_flutter/lib/features/parametres/parametres_generaux_repository.dart`, `agrierp_flutter/lib/features/parametres/parametres_generaux_screen.dart`, `agrierp_flutter/lib/features/auth/ecran_changement_mot_de_passe.dart`, `agrierp_flutter/lib/features/auth/login_screen.dart`, `agrierp_flutter/lib/features/verrou/porte_session.dart`, `agrierp_flutter/lib/core/auth/auth_service.dart`.

### (a) Existe dans logialvia
`logialvia_app/lib/administration/domain/repositories/parametres_repository.dart` (`creerUtilisateur`, `identifiantExiste`, `supprimerUtilisateur`), `logialvia_app/lib/administration/data/tables/utilisateurs_table.dart` (nom, identifiant, roleId, hash, sel), `logialvia_app/lib/administration/domain/services/hachage_mot_de_passe.dart`, `logialvia_app/lib/administration/domain/entities/compte_utilisateur.dart`, `logialvia_app/lib/administration/domain/usecases/connecter_utilisateur_usecase.dart`, `logialvia_app/lib/administration/presentation/viewmodels/parametres_generaux_view_model.dart`, `logialvia_app/lib/administration/presentation/screens/parametres_generaux_screen.dart`, `logialvia_app/lib/administration/presentation/screens/auth/widgets/modale_mot_de_passe_oublie.dart` (informative), `logialvia_app/lib/administration/presentation/viewmodels/corbeille_view_model.dart`, tests `logialvia_app/test/administration/*` (11 fichiers). Seul `admin` n'est pas créable (seeder).

### (b) Manque
`modifierUtilisateur`, `archiverUtilisateur` / `reactiverUtilisateur`, colonne `is_active` et `doit_changer_mot_de_passe` (v27+), `reinitialiserMotDePasseUtilisateur`, écran de changement forcé, texte « Contactez l'administrateur », journal d'audit des gestes.

### (c) Dans l'architecture de logialvia
Use cases `ModifierUtilisateurUseCase`, `ArchiverUtilisateurUseCase`, `ReinitialiserMotDePasseUtilisateurUseCase` dans `NEW:logialvia_app/lib/administration/domain/usecases/` ; les règles de refus (messages) vivent en `domain`, pas dans le ViewModel ; `ParametresRepository` étend son contrat ; la table `Utilisateurs` reçoit `isActive` et `doitChangerMotDePasse` (migration explicite) ; `ConnecterUtilisateurUseCase` renvoie un résultat « changement obligatoire » que le routeur (`logialvia_app/lib/core/router/app_router.dart`) traite AVANT toute route métier (équivalent du middleware : tout est redirigé tant que le drapeau est vrai). Remplacer le texte de `modale_mot_de_passe_oublie.dart` par « Contactez l'administrateur » (non cliquable).

### Pièges
- Le seul rôle `admin` n'étant jamais créable, le « dernier administrateur » ne peut s'archiver ni se réinitialiser lui-même : prévoir le script `outils/reinitialiser_mot_de_passe_admin.dart` comme code de secours.
- Un mot de passe temporaire ne doit pas être réutilisable comme définitif (refus d'un nouveau mot de passe identique).
- Les colonnes d'une table de comptes ne doivent contenir aucun nom `password` en clair, `token`, `secret` (test de garde d'AgriERP : `agrierp_flutter/test/parametres_generaux_test.dart`).
- Un compte archivé ne se connecte plus ; ses sessions en cours se ferment.

### Tests à reprendre
`agrierp_flutter/test/utilisateurs_poste_test.dart`, `agrierp_flutter/test/reinitialisation_mot_de_passe_test.dart` (connexion, dépôt, écran, changement forcé, porte), `agrierp_laravel/tests/Feature/ReinitialisationMotDePasseAdminTest.php`, `agrierp_laravel/tests/Feature/ChangementMotDePasseObligatoireTest.php`, `agrierp_laravel/tests/Feature/CodeSecoursAdminTest.php`, `agrierp_laravel/tests/Feature/ConnexionSansReinitialisationParEmailTest.php`. Dans logialvia : étendre `logialvia_app/test/administration/parametres_generaux_test.dart`, `logialvia_app/test/administration/compte_utilisateur_test.dart`, `logialvia_app/test/administration/service_reinitialisation_test.dart` (⚠️ ce nom désigne la remise à zéro des données, pas celle d'un mot de passe).

### Questions à poser au client
Politique de mot de passe (longueur, majuscule, chiffre) ? PBKDF2 au lieu de SHA-256 ? Le rôle « comptable » doit-il exister ? Qui peut réinitialiser (admin seul) ? Où imprimer et ranger le code de secours ?

---

## 4. Bloc 3 — Les trois boutons Réduire / Agrandir / Fermer

### Objectif
Fenêtre Windows sans bordure : la barre du haut de l'application est la barre de titre (glisser pour déplacer, double-clic pour agrandir) et porte « Réduire », « Agrandir / Restaurer », « Fermer ».

### Règle
- ⚠️⚠️ **« Agrandir » = la ZONE DE TRAVAIL du moniteur (`rcWork`), JAMAIS `SW_MAXIMIZE` / `SW_SHOWMAXIMIZED` / `SM_CYSCREEN`** sur une fenêtre `WS_POPUP` : cela couvre tout l'écran et cache la barre des tâches Windows (défaut du client, ticket ENV1).
- La géométrie est NATIVE (C++) : `Win32Window::GetWorkArea()` (`MonitorFromWindow` + `GetMonitorInfo` → `rcWork`, repli `SPI_GETWORKAREA`), `MaximizeToWorkArea()` / `RestoreFromMaximized()` / `ToggleMaximize()` avec drapeau `maximized_` et rectangle de restauration (ramené dans la zone de travail courante). Recalage sur `WM_DISPLAYCHANGE`, `WM_SETTINGCHANGE` + `SPI_SETWORKAREA`, `WM_DPICHANGED`, `WM_SIZE`/`SIZE_RESTORED`. `WM_GETMINMAXINFO` borne aussi un agrandissement système et pose une taille minimale (640×480 logiques plafonnée à la zone de travail). Dart ne calcule AUCUNE géométrie.
- Canal `MethodChannel('agrierp/fenetre')` : `reduire`, `fermer`, `etat`, `basculerAgrandissement` (les deux répondent `{agrandie, x, y, largeur, hauteur}`), `deplacer`. Une panne du canal ne plante pas l'écran (`FenetrePoste` avale `MissingPluginException` : en test il n'y a pas de côté natif).
- L'agrandissement se fait APRÈS l'affichage (`SetNextFrameCallback` → `MaximizeToWorkArea(); Show();`), pas dans `main.cpp` (la fenêtre est créée cachée ; un appel plus tôt est écrasé par `Show()`).
- « Fermer » demande confirmation ; l'icône de l'application = logo généré (bloc 10).

### Fichiers de référence (AgriERP)
`agrierp_flutter/windows/runner/win32_window.cpp`, `agrierp_flutter/windows/runner/win32_window.h`, `agrierp_flutter/windows/runner/flutter_window.cpp`, `agrierp_flutter/windows/runner/main.cpp`, `agrierp_flutter/lib/core/fenetre/fenetre_poste.dart`, `agrierp_flutter/lib/core/widgets/barre_superieure.dart`, `agrierp_flutter/test/fenetre_poste_test.dart`, `agrierp_flutter/test/commandes_fenetre_test.dart`.

### (a) Existe dans logialvia
`logialvia_app/lib/main.dart` (`windowManager`, `WindowOptions` 1440×900, minimum 1024×700), `logialvia_app/windows/runner/win32_window.cpp` (créé en `WS_OVERLAPPEDWINDOW`, donc barre système), `logialvia_app/lib/core/widgets/shell/app_top_bar.dart`, `logialvia_app/lib/administration/presentation/screens/widgets/onglet_sauvegardes.dart` (utilise déjà `windowManager.destroy()`).

### (b) Manque
Fenêtre sans bordure, boutons de la barre du haut, zone glissable, double-clic, test de lecture du C++.

### (c) Dans cette architecture
Deux voies, à trancher avec le client (NON vérifiées sur Windows ici) : **(A)** reproduire la voie native d'AgriERP (copier les fichiers `windows/runner` ci-dessus après relecture, les adapter au nom `logialvia_app` ; `NEW:logialvia_app/lib/core/fenetre/fenetre_poste.dart` = client du canal) ; **(B)** rester sur `window_manager` avec `TitleBarStyle.hidden` + `windowManager.minimize()/maximize()/close()`. La voie B n'a pas été éprouvée contre le défaut de la barre des tâches : si on la choisit, le test doit prouver le comportement sur une machine réelle (barre des tâches en bas, à gauche, en haut, masquée ; deux moniteurs d'échelles différentes). Quelle que soit la voie : les boutons vivent dans `app_top_bar.dart` (widget) qui appelle un SERVICE injecté (`FenetrePoste`), jamais la plateforme directement (testabilité). Pas de logique de fenêtre dans un ViewModel.

### Pièges
- `ShowWindow(SW_SHOWMAXIMIZED)` sur `WS_POPUP` cache la barre des tâches.
- Aucun effet visible tant que le test ne lit pas le C++ ; le test d'AgriERP REFUSE les trois symboles dans les sources.
- Le comportement natif d'AgriERP n'a jamais tourné sur Windows réel au moment de l'écriture (compilé/typé sur Linux avec en-têtes simulés) ; à essayer : barre des tâches bas / gauche / haut / masquée, 2 moniteurs, changement de résolution pendant l'agrandissement, réduction-restauration, glisser, double-clic, confirmation de fermeture.
- Le canal doit répondre même sans plugin (tests de widget).

### Tests à reprendre
`agrierp_flutter/test/fenetre_poste_test.dart` (contrat Dart avec canal simulé `NativeSimule` ET lecture du C++ interdisant `SW_SHOWMAXIMIZED`, `SW_MAXIMIZE`, `SM_CYSCREEN`), `agrierp_flutter/test/commandes_fenetre_test.dart`.

### Questions à poser au client
Garder la barre de titre Windows (aucun développement) ou la barre sans bordure d'AgriERP ? Voie A ou B ? Confirmation à la fermeture ?

---

## 5. Bloc 4 — Sélecteur d'exercice et modes N / N+1 / consultation

### Objectif
Un sélecteur d'exercice dans la barre du haut, global ; l'exercice AFFICHÉ pilote les écrans de consultation ; un exercice clos est en lecture seule avec bandeau ; N+1 peut être provisoire.

### Règle (EX1 à EX8)
- **Afficher ≠ écrire.** L'exercice choisi ne décide JAMAIS l'exercice d'une saisie : une saisie appartient à l'exercice qui contient SA DATE (R4), jugé au moment d'écrire, quel que soit l'exercice affiché.
- **Défaut** : l'exercice qui contient la date du jour à l'heure du pays, sinon le plus récent. Choix mémorisé (AgriERP : session web ; poste : clé `poste.exercice_choisi` d'`app_settings`). Choix inconnu → défaut.
- **Statuts** (libellés des badges, mot pour mot) : « Ouvert », « Provisoire », « Clôturé ». `cloture` = clos ; `ouvert` = pas d'exercice antérieur, ou l'exercice contenant la veille de son premier jour est clos ; `provisoire` sinon (N+1 ouvert alors que N n'est pas clos : à-nouveaux provisoires, EX2).
- **Lecture seule** : exercice affiché clos → boutons de saisie grisés avec motif en info-bulle « Exercice 2026 clôturé — lecture seule » ; le grisé est un CONFORT, la garantie est le refus à l'écriture. **Bandeau** (texte unique) : « Exercice 2026 clôturé — lecture seule. Les saisies se font dans l'exercice 2027. » (second membre absent si aucun exercice ouvert), avec lien « Passer à … ». Exercice de saisie = l'exercice OUVERT qui contient le jour, sinon le plus récent ouvert.
- **Fiches d'élevage (EX8/EF12)** : le bandeau d'une fiche suit l'exercice de LA DATE choisie (pas l'exercice affiché) ; une fiche datée dans un exercice clos est refusée à l'enregistrement.
- **`arreteDe(annee)`** (règle unique de la date d'arrêté des états) : aujourd'hui (heure du pays) si l'exercice est en cours ; sa date de fin s'il est passé ; son premier jour s'il est à venir ; `annee-01-01`/`annee-12-31` si non enregistré. Les colonnes N et N-1 du Bilan et du Compte de résultat suivent l'exercice affiché ; N-1 = l'exercice précédent À SA CLÔTURE (pas « à date égale »).
- **Listes** paginées dans l'exercice affiché : 25 lignes (« 27 lignes dans l'exercice 2026 — page 1 sur 2 », Précédent / Suivant).
- **Indicateurs « du mois »** : mois de référence = le mois du jour s'il est dans l'exercice affiché, sinon le dernier mois de l'exercice. Déclaration de TVA et Rapport mensuel ne proposent que les mois de l'exercice affiché.
- Ouverture de N+1 : le 1er janvier (tâche + filet à la première saisie) et par bouton dès le 1er décembre ; deux exercices ouverts au plus (R2).

### Fichiers de référence (AgriERP)
`agrierp_laravel/app/Support/ExerciceChoisi.php`, `agrierp_laravel/app/Support/ComparatifNMoinsUn.php`, `agrierp_laravel/app/Models/FiscalYear.php`, `agrierp_laravel/app/Livewire/Shared/SelecteurExercice.php`, `agrierp_laravel/app/Livewire/Shared/BandeauExercice.php`, `agrierp_laravel/resources/views/components/bandeau-lecture-seule.blade.php`, `agrierp_laravel/app/Services/OuvertureExerciceService.php`, `agrierp_flutter/lib/core/comptabilite/exercice_choisi.dart` (`EtatExercice`, `ExerciceChoisi`, `PorteeExerciceChoisi`, `arreteDe`), `agrierp_flutter/lib/core/comptabilite/exercice_de_saisie.dart`, `agrierp_flutter/lib/core/widgets/selecteur_exercice.dart`, `agrierp_flutter/lib/core/widgets/bandeau_exercice.dart`, `agrierp_flutter/lib/core/widgets/lecture_seule.dart`, `agrierp_flutter/lib/core/widgets/pagination_agri.dart`, `agrierp_flutter/lib/features/comptabilite/etats_comparatifs.dart`.

### (a) Existe dans logialvia
`logialvia_app/lib/comptabilite/data/tables/comptabilite_tables.dart` (`ExerciceComptable` : `annee`, `isCloture`, `dateCloture` — année civile, pas de dates de début/fin), `logialvia_app/lib/comptabilite/data/repositories/comptabilite_repository_drift.dart` (`chargerExercices`, `exerciceEstCloture`, `chargerCloturesPeriodiques`, `_verifierVerrouillage`), `SelecteurExercice` local à la Comptabilité (`logialvia_app/lib/comptabilite/presentation/screens/widgets/communs_compta.dart`) avec pastille « clos », `logialvia_app/lib/comptabilite/presentation/viewmodels/comptabilite_view_model.dart` (`changerExercice`), `logialvia_app/lib/core/widgets/shell/app_top_bar.dart`.

### (b) Manque
Sélecteur dans la barre du haut (global), statut « Provisoire », bandeau unique + grisé des boutons, `arreteDe`, N / N-1 des états, pagination par exercice, exercice de la date d'une fiche.

### (c) Dans cette architecture
`NEW:logialvia_app/lib/comptabilite/domain/services/exercice_choisi.dart` : fonctions PURES (`statutDe`, `arreteDe`, `motifLectureSeuleDe`, `bandeauDe`, `exerciceDuJour`, `moisDeReference`) sur une liste d'entités `Exercice` (ajouter `debut`/`fin` à la table, migration ; pour l'existant : 01/01 – 31/12 de `annee`). L'état (exercice choisi) = UN `ChangeNotifier` global fourni au sommet (`MultiProvider`), persisté dans `preferences_poste` (`logialvia_app/lib/administration/data/tables/preferences_poste_table.dart`, `logialvia_app/lib/administration/data/repositories/preferences_poste_repository.dart`). Le widget de la barre du haut lit ce notifier ; chaque ViewModel de consultation reçoit l'exercice par constructeur (jamais l'inverse). Le grisé : un widget `BoutonSaisie` unique qui lit le notifier (au lieu de tester `isCloture` dans chaque écran). Le refus d'écriture reste dans le dépôt/le use case (déjà en partie : `_verifierVerrouillage`).

### Pièges
- Un écran qui affiche N+1 et écrit à la date du jour : l'écriture appartient à l'exercice de SA date.
- Bandeau en doublon (page + fiche) : un seul composant.
- Le fuseau : « aujourd'hui » à l'heure du pays, jamais `DateTime.now()` d'un Windows mal réglé (AgriERP : `HeureBenin`, UTC+1 fixe — `agrierp_flutter/lib/core/temps/heure_benin.dart`).
- Mois d'un exercice dont l'étape 2 est passée : l'écriture de solde fausse le chiffre d'affaires du mois (EX-Q14, non corrigé à AgriERP).

### Tests à reprendre
`agrierp_flutter/test/selecteur_exercice_test.dart`, `agrierp_flutter/test/bascule_exercice_parite_test.dart`, `agrierp_flutter/test/refus_exercice_clos_test.dart`, `agrierp_flutter/test/refus_exercice_ecrans_test.dart`, `agrierp_flutter/test/fiches_mois_passes_test.dart`, `agrierp_flutter/test/heure_benin_test.dart`, `agrierp_laravel/tests/Feature/SelecteurExerciceTest.php`, `agrierp_laravel/tests/Feature/BasculeExerciceEtatsTest.php`, `agrierp_laravel/tests/Feature/ExerciceClosLectureSeuleTest.php`. Les valeurs attendues d'`arreteDe` : exercice 2026 (01/01–31/12), « aujourd'hui » = 15/03/2026 → 15/03/2026 ; aujourd'hui = 10/01/2027 → 31/12/2026 ; aujourd'hui = 10/06/2025 → 01/01/2026 ; exercice non enregistré 2030 → 2030-12-31 si aujourd'hui est postérieur, sinon règle ci-dessus avec bornes civiles.

### Questions à poser au client
Exercice = année civile toujours (ou exercice décalé) ? Veut-on N+1 « provisoire » avant la clôture de N ? La caisse et les fiches d'élevage se grisent-elles quand un exercice clos est affiché (AgriERP : non, pilotés seulement les écrans de consultation) ?

---

## 6. Bloc 5 — Rationnement automatique

### Objectif
La provende servie et l'autonomie alimentaire d'une fiche se calculent sans saisie : effectif CALCULÉ de chaque catégorie × ration du barème, avec une alerte d'autonomie.

### Règle
- **Tableau par catégorie / stade** : pour chaque catégorie dans l'ordre de la chaîne : effectif calculé × ration (g/j/sujet) ; `total_g` = somme (null si une catégorie est inconnue : ni 0 ni valeur devinée) ; `total_kg` = `round(total_g / 1000, 2)`. Le total somme TOUTES les catégories (bug historique : seule la catégorie vendue était sommée).
- **Clé stable par libellé en ÉGALITÉ STRICTE** : libellé du barème normalisé (minuscules, sans accents, tranche d'âge entre parenthèses ignorée) — « poussin ponte », « poussin en croissance », « poulette », « pondeuse » ; jamais par sous-chaîne (« Poussin » n'est pas « Poussin ponte » ; « Reproducteur » et « Jeune » ne sont jamais des stades de pondeuse). Si une ligne manque au barème : valeur de repli (pondeuses 30/60/80/110 ; lapins 120/30/60 ; reproducteurs 130/80/30), jamais un 0 silencieux.
- **Barème `feed_ration_standards`** éditable (créer, modifier, archiver) dans « Paramètres Élevage » (web et poste). Valeurs confirmées par le client le 05/11/2026 : reproducteurs 130 / 80 / 30 ; pondeuses 30 / 60 / 80 / 110 ; lapins 120 / 30 / 60 (le commentaire « PROVISOIRES » de `agrierp_laravel/database/seeders/FeedRationStandardsSeeder.php` et de `agrierp_flutter/lib/features/elevage/categorie_volaille.dart` est PÉRIMÉ). Une migration d'ajout est idempotente et ne réécrit jamais une ration ajustée.
- **Alerte d'autonomie alimentaire** (`AlerteAutonomieFicheService`) : aprés enregistrement d'une fiche, comparer la provende disponible (stock du produit de provende de la filière) à la provende journalière calculée ; alerte **rouge** en rupture, sous 3 jours ou sans produit de provende ; n'empêche JAMAIS l'enregistrement ; une alerte par objet et par jour. Calculée sur la SOMME de toutes les catégories (pas une seule).
- Le tableau et l'alerte lisent l'effectif CALCULÉ ; une catégorie à départ non saisi → « — ».

### Fichiers de référence (AgriERP)
`agrierp_laravel/app/Support/StadePondeuse.php` (`tableau`, `ration`, `cleDuLibelle`), `agrierp_laravel/app/Support/CategorieVolaille.php` (`tableauReproducteurs`), `agrierp_laravel/app/Support/CategorieRationLapin.php`, `agrierp_laravel/app/Support/CategorieRationPorc.php`, `agrierp_laravel/app/Services/AlerteAutonomieFicheService.php`, `agrierp_laravel/app/Services/AutonomieAlimentaireService.php`, `agrierp_laravel/app/Actions/RaiseFeedAutonomyAlertAction.php`, `agrierp_laravel/app/Models/FeedRationStandard.php`, `agrierp_laravel/app/Livewire/Elevage/ParametresElevage.php`, `agrierp_laravel/database/seeders/FeedRationStandardsSeeder.php`, `agrierp_flutter/lib/features/elevage/stade_pondeuse.dart`, `agrierp_flutter/lib/features/elevage/categorie_ration_lapin.dart`, `agrierp_flutter/lib/features/elevage/autonomie_alimentaire_carte.dart`, `agrierp_flutter/lib/features/elevage/parametres_elevage_repository.dart`, `agrierp_flutter/lib/features/elevage/parametres_elevage_screen.dart`.

### (a) Existe dans logialvia
`logialvia_app/lib/elevage/data/tables/parametres_elevage_tables.dart` (`BaremesRation` : espèce, stade, ration, `confirme`), `logialvia_app/lib/elevage/data/repositories/parametres_elevage_repository_drift.dart` (`creerBareme`, `modifierRation`, `supprimerBareme`), `logialvia_app/lib/elevage/presentation/screens/parametres_elevage_screen.dart`, `CalculFicheJournaliere.rationsConfigurees` / `rationCategorie` / `provendeTotaleGrammes` (indexé par libellé exact), `logialvia_app/lib/pilotage/presentation/viewmodels/alertes_view_model.dart` (alertes globales, mention d'autonomie), tests `logialvia_app/test/elevage/parametres_elevage_test.dart`.

### (b) Manque
Rapprochement tolérant à la tranche d'âge (« Poussin ponte (0 à 2 mois) » ≠ « Poussin Ponte » aujourd'hui : clé exacte seulement), `total_kg` arrondi, tableau par catégorie sur la fiche, alerte d'autonomie PAR fiche, barème par filière complet (Pintades, Poissons-Chats), suppression remplacée par archivage.

### (c) Dans cette architecture
`NEW:logialvia_app/lib/elevage/domain/services/rationnement.dart` : `cleStable(String libelle)` (normalisation) + `tableauRationnement(config, effectifs, bareme)` pur, renvoyant lignes et total ; `CalculFicheJournaliere.rationCategorie` l'utilise (un seul point). `NEW:…/domain/services/autonomie_alimentaire_fiche.dart` : fonction pure `autonomie(provendeDisponibleG, provendeJourG)` → jours ; le ViewModel de la fiche la présente, l'alerte réelle passe par `AlertesViewModel`. Aucun calcul dans le widget (A2 §3). Les rations de repli vivent dans `ConfigurationEspece`.

### Pièges
- Ration retrouvée par sous-chaîne : renommer un libellé retombe en silence sur la valeur de secours.
- Total qui ne somme que la catégorie vendue (bug historique de `provendeTotal`).
- Alerte qui bloque la saisie : interdit.
- Un barème « non confirmé » (`confirme = false`) doit rester visible (note de `ConfigurationEspece.noteRationnement`).

### Tests à reprendre
- Jeu de cas : Pondeuses (77, 79, 43, 196 ; rations 30/60/80/110) → lignes 2 310 / 4 740 / 3 440 / 21 560 g ; **total 32 050 g = 32,05 kg**. Reproducteurs (R=9, J=35, P=21 ; 130/80/30) → 1 170 / 2 800 / 630 ; **total 4 600 g = 4,6 kg**. Catégorie inconnue (lapins sans départ) → total `null`, pas 0.
- Clés : « Poussin ponte (0 à 2 mois) » ↔ clé `poussin_ponte` ; « Poussin » ↔ clé de reproducteurs, jamais celle de la ponte.
- Tests de référence : `agrierp_flutter/test/ration_volaille_test.dart`, `agrierp_flutter/test/categorie_ration_lapin_test.dart`, `agrierp_flutter/test/provende_autonomie_parite_test.dart`, `agrierp_flutter/test/rationnement_infobulles_test.dart`, `agrierp_laravel/tests/Feature/RationVolailleTest.php`, `agrierp_laravel/tests/Feature/RationnementLapinsTest.php`, `agrierp_laravel/tests/Feature/AlerteAutonomieAlimentaireTest.php`, `agrierp_laravel/tests/Feature/AutonomieProduitProvendeTest.php`.

### Questions à poser au client
Barèmes à confirmer par filière (Goliaths, Pintades : « barème générique réutilisé de l'aviculture » ; Poissons-Chats : « non confirmé »). Seuil d'autonomie : 3 jours (AgriERP) ? Produit de provende rattaché à quelle filière ?

---

## 7. Bloc 6 — Prophylaxie automatique et fenêtre « Rappels du jour »

### Objectif
Les traitements prophylactiques du barème se projettent sur chaque bande ; une fenêtre à l'ouverture de l'application liste les rappels (soins planifiés, traitements dus, fins de délai d'attente) — jamais vide, jamais au déverrouillage.

### Règle
- **Jour de cycle (règle unique, `ProtocoleDuJourService`)** : J1 = le jour de référence ; jour de référence = la DERNIÈRE saillie pour une bande au stade `reproduction`, la date de mise en bande sinon ; bande en reproduction sans saillie connue → INDÉTERMINÉE (à afficher telle quelle). Un traitement est dû si `jour_debut <= J <= jour_fin`. Les entrées « le 1er du mois » (bornes nulles) ne sont JAMAIS évaluées mais comptées. Calcul en jours CALENDAIRES entiers (minuit à minuit) : `diffInDays` flottant de Carbon 3 faisait manquer les traitements d'un seul jour.
- **H3 — R-SOINS-01** : tout soin du calendrier au statut « planifié » rattaché à une bande vivante → « Soin à venir » dès qu'il reste N jours ou moins ; « Soin en retard » dès que la date est dépassée ; N = `rappel_soins_jours` (0 à 30, 3 par défaut ; 0 = le jour même seulement) ; une alerte par soin et par jour.
- **R-RAPPELS-01 (POP1–4)** : horizon N = R-SOINS-01. Sources : (1) soins planifiés (« En retard » / « Aujourd'hui » / « À venir ») ; (2) traitements du barème dus et non administrés pour J…J+N (« Aujourd'hui » / « À venir », jamais « En retard ») ; (3) fins de délai d'attente de J à J+N. Bandes vivantes seulement ; filière désactivée dans Modules Actifs = aucun rappel ; droit d'élevage requis (le caissier ne la reçoit pas). Tri : urgence, date croissante, code de bande, type (soin, prophylaxie, délai d'attente), libellé.
- **Quand** : `PorteSession.surOuverture`, appelé UNE fois par session : au lancement (après le PIN) et à chaque connexion — JAMAIS à un déverrouillage (manuel ou par inactivité). Erreur de la fenêtre avalée (`debugPrint`), elle ne bloque rien. **« Ne plus afficher aujourd'hui »** : jour `AAAA-MM-JJ` par utilisateur dans le coffre (pas de migration de base). **Jamais de fenêtre vide** : aucun rappel, masqué, sans droit ou en erreur → pas de fenêtre.
- **H8 infirmerie / calendrier** : l'infirmerie n'a pas de date prévue → aucun rappel ; le calendrier vétérinaire ne porte aucun produit (colonne « Produit » = « — » pour un soin).

### Fichiers de référence (AgriERP)
`agrierp_laravel/app/Services/ProtocoleDuJourService.php`, `agrierp_laravel/app/Services/ProtocoleDuJour.php`, `agrierp_laravel/app/Services/RappelsDuJourService.php`, `agrierp_laravel/app/Services/AlertesElevageService.php` (R-SOINS-01), `agrierp_laravel/app/Livewire/Shared/RappelsDuJour.php`, `agrierp_laravel/app/Jobs/DailyProphylaxyReminderJob.php`, `agrierp_laravel/app/Actions/ValidateProphylaxisTreatmentsAction.php`, `agrierp_laravel/app/Actions/RecordVeterinaryCareAction.php`, `agrierp_flutter/lib/features/elevage/soins_repository.dart` (`protocoleDuJour`), `agrierp_flutter/lib/features/elevage/rappels_du_jour_repository.dart`, `agrierp_flutter/lib/features/elevage/rappels_du_jour_ouverture.dart` (`OuvertureRappels.aMontrer`, `ReglageRappels`), `agrierp_flutter/lib/features/elevage/rappels_du_jour_modale.dart`, `agrierp_flutter/lib/features/verrou/porte_session.dart` (`surOuverture`), `docs/prd/popup-rappels.md`.

### (a) Existe dans logialvia
`logialvia_app/lib/elevage/domain/services/prophylaxie_de_la_bande.dart` (projection du calendrier sur les dates réelles : jour de cycle depuis la mise en bande, `EcheanceProjetee`, fin de délai d'attente), `logialvia_app/lib/elevage/domain/services/rappels_prophylaxie.dart` (échéances échues jamais planifiées), `logialvia_app/lib/elevage/presentation/screens/widgets/modale_prophylaxie_du_jour.dart` (`ouvrirSiNecessaire`, une fois par processus via `_reportee` statique), `logialvia_app/lib/elevage/presentation/screens/widgets/bloc_bande_prophylaxie.dart`, `logialvia_app/lib/elevage/presentation/viewmodels/soins_view_model.dart`, `logialvia_app/lib/elevage/data/tables/soins_calendrier_table.dart`, `logialvia_app/lib/elevage/data/tables/infirmerie_table.dart`, `logialvia_app/lib/elevage/data/tables/parametres_elevage_tables.dart` (`CalendrierProphylaxie`), `logialvia_app/lib/elevage/domain/usecases/reporter_deces_infirmerie_usecase.dart`. Tests : `logialvia_app/test/elevage/prophylaxie_du_jour_test.dart`, `logialvia_app/test/elevage/rappels_prophylaxie_test.dart`, `logialvia_app/test/elevage/bande_prophylaxie_test.dart`, `logialvia_app/test/elevage/soins_test.dart`.

### (b) Manque
Jour de référence = dernière saillie pour une bande en reproduction ; calcul en jours entiers (à vérifier : `Bande.jourDeCycle` utilise déjà `difference().inDays` sur des minuits, donc OK) ; paramètre `rappel_soins_jours` ; fusion des trois sources ; ouverture au lancement/connexion (aujourd'hui : à l'ouverture du tableau de bord, une fois par processus) ; « Ne plus afficher aujourd'hui » ; droit d'élevage ; aucune fenêtre vide quand erreur.

### (c) Dans cette architecture
Un use case pur `NEW:logialvia_app/lib/elevage/domain/usecases/rappels_du_jour_usecase.dart` qui COMPOSE les services existants (`prophylaxie_de_la_bande`, `rappels_prophylaxie`, le calendrier des soins) et renvoie `List<RappelDuJour>` triée ; le ViewModel de la fenêtre n'a aucune règle. Le déclencheur est un seul point : le flux « splash → connexion → application » (`logialvia_app/lib/administration/presentation/viewmodels/splash_view_model.dart`, `logialvia_app/lib/administration/presentation/viewmodels/auth_view_model.dart`) appelle `surOuverture` une fois par session ; PAS un `initState` d'écran. « Ne plus afficher aujourd'hui » : table `preferences_poste` (`logialvia_app/lib/administration/data/repositories/preferences_poste_repository.dart`) ou `flutter_secure_storage` (déjà dépendance) ; clé `rappels.masque.<utilisateur>` = jour.

### Pièges
- La fenêtre s'ouvrait aussi à chaque déverrouillage : interdit.
- Fenêtre vide quand rien à signaler : interdit.
- Un rappel calculé sur le jour du mois au lieu du jour de cycle rejoue les traitements chaque 1er.
- Recopier la règle au lieu d'appeler le service unique (une seconde copie d'une règle sanitaire diverge toujours).

### Tests à reprendre
`agrierp_flutter/test/rappels_du_jour_test.dart`, `agrierp_flutter/test/rappels_du_jour_blade_test.dart` (libellés lus dans la source), `agrierp_flutter/test/protocole_du_jour_test.dart`, `agrierp_flutter/test/protocole_du_jour_parite_test.dart`, `agrierp_flutter/test/soins_infirmerie_calendrier_test.dart`, `agrierp_laravel/tests/Feature/RappelsDuJourTest.php`, `agrierp_laravel/tests/Feature/ProtocoleDuJourServiceTest.php`. Cas à écrire à la main : traitement J5–J5 dû le jour 5 d'une bande dont le jour de référence est le 1er ; soin planifié à J−1 → « En retard » ; N=3 : soin à J+3 → « À venir », à J+4 → rien ; aucun rappel → `aMontrer` rend `null`.

### Questions à poser au client
Fenêtre au lancement et à chaque connexion ? Délai N (3 jours) ? Le caissier la reçoit-il ? Les entrées « le 1er du mois » du calendrier : décision client NON tranchée à AgriERP (non évaluées).

---

## 8. Bloc 7 — Import et export (ce qui existe VRAIMENT)

### Objectif
Décrire sans le surévaluer ce qui est importé et exporté dans AgriERP, puis ce qu'il faut à logialvia.

### Ce qui existe dans AgriERP (vérifié)
- **PDF** (poste) : `ExportOfficiel.construire(DocumentOfficiel, polices:)` dans `agrierp_flutter/lib/core/export/document_officiel.dart` — transposition de l'export PDF du prototype ; le DOCUMENT est une structure pure (`BandeDocument`, `EnteteDocument`, `DonneesDocument`, `TotalDocument`). **`chargerPolices()` est OBLIGATOIRE** : Helvetica par défaut n'a pas Unicode, « — » et « ’ » sortent en carré barré sans erreur. Roboto est embarquée. Pied de page : trois structures. Effets de bord (boîte d'impression, écriture) injectés par `EditeursRapports`. `agrierp_flutter/lib/core/export/pdf_attestation.dart`, `agrierp_flutter/lib/core/export/pdf_recu.dart` : PDF propres.
- **Tableur xlsx** (poste) : `ExportTableur.construire(DocumentOfficiel)` dans `agrierp_flutter/lib/core/export/export_tableur.dart`, paquet `excel`. **Ajout assumé au-delà de la maquette** (les six boutons « Excel » du prototype ne font qu'un toast). Cellules = texte tel qu'affiché (aucun montant reformaté) ; nom d'onglet ≤ 31 caractères, sans `: \ / ? * [ ]`. Boutons d'export de Soins & Vaccins et Ventes & Devis : inertes à l'origine.
- **Web** : PDF par `PdfExportService` (`agrierp_laravel/app/Services/PdfExportService.php`), méthodes `export…Pdf` des écrans ; **le bouton « Excel » du web produit un CSV** (`exportReport(format: 'csv')` dans `agrierp_laravel/app/Livewire/Rapports/StocksSynth.php`, `Creances.php`, `Dettes.php`, `Tresorerie.php`, `RecettesDepenses.php`, `ElevageSynth.php`, pilotés par `agrierp_laravel/app/Livewire/Rapports/RapportsExportsHub.php`). Pas de xlsx au web. Droit `export-rapports`.
- **Imports** : (1) **relevé bancaire CSV idempotent** : `BankReconciliationService::importCsv(compte, contenu, importId)` (`agrierp_laravel/app/Services/BankReconciliationService.php`) — séparateur `;` puis `,`, trois colonnes date / libellé / montant, lignes invalides comptées `skipped`, **un `import_id` déjà joué n'est pas rejoué** ; poste : `RapprochementRepository.importerReleve` (`agrierp_flutter/lib/features/comptabilite/rapprochement_repository.dart`), UUID d'import, taille max 2 048 ko (message « Le fichier relevé ne doit pas dépasser 2048 kilo-octets. »). (2) **Import d'un module depuis une sauvegarde** : `ImportModuleService` (`agrierp_laravel/app/Services/ImportModuleService.php`, ticket 14.58) n'exécute JAMAIS le SQL téléversé : il l'analyse, ne garde que les `INSERT INTO`, vers les tables du module choisi (liste du module, jamais déduite du fichier), valeurs LIÉES ; le reste est compté et rejeté. (3) **Plan SYSCOHADA** : `php artisan comptabilite:importer-plan-syscohada` (insertion seule, bloc 9). Il n'existe PAS d'import tableur de données métier (xlsx : bloc 21, À CONCEVOIR), ni d'import au poste d'un module (`ImportModuleService` ne lit que des sauvegardes SQL déposées sur le serveur).
- **Sauvegardes / restauration (AUT-4)** : `AdministrationLocale` (`agrierp_flutter/lib/features/parametres/administration_locale.dart`) : `generer` = `VACUUM INTO` (sauvegarde COMPLÈTE de la base SQLite), export de module en JSON, **restauration installée AU PROCHAIN LANCEMENT** par `appliquerRestaurationEnAttente` avant l'ouverture de la base (fichier `agrierp.restauration`, ancienne base gardée sous `agrierp.avant-restauration.sqlite`) ; seule une sauvegarde complète se restaure. Web : `agrierp_laravel/app/Services/SauvegardeService.php` (`mysqldump`) et `agrierp_laravel/app/Livewire/Parametres/Sauvegardes.php`.

### (a) Existe dans logialvia
PDF : `logialvia_app/lib/core/pdf/document_pdf.dart`, `logialvia_app/lib/core/pdf/generateur_pdf.dart`, `logialvia_app/lib/core/pdf/service_impression.dart`, `logialvia_app/lib/core/pdf/bouton_export_pdf.dart` (+ police Roboto embarquée, test `logialvia_app/test/core/pdf_police_roboto_test.dart`, `logialvia_app/test/core/generateur_pdf_test.dart`) ; documents par module (`logialvia_app/lib/elevage/presentation/screens/documents_elevage.dart`, etc.) ; manuel PDF généré (`logialvia_app/lib/core/pdf/manuel/`). Sauvegarde/restauration : `logialvia_app/lib/administration/domain/services/service_sauvegarde.dart` (`genererBaseComplete`, `exporterTable`), `logialvia_app/lib/administration/domain/services/service_restauration.dart` (`preparer`, `appliquerSiDemandee`), test `logialvia_app/test/administration/restauration_test.dart`, `logialvia_app/test/administration/service_sauvegarde_test.dart`. AUCUN xlsx/csv dans `lib/` (grep négatif), aucun import.

### (b) Manque
Export tableur (E11), import de relevé bancaire idempotent, import de plan SYSCOHADA, garde de taille d'import.

### (c) Dans cette architecture
Réutiliser le MÊME `DocumentPdf` de logialvia comme structure pure et ajouter `NEW:logialvia_app/lib/core/export/export_tableur.dart` (builder pur `Uint8List construire(DocumentPdf)`, aucune E/S ; l'effet de bord — enregistrer — dans un service injecté). Import de relevé : `ImporterReleveBancaireUseCase` dans `NEW:logialvia_app/lib/comptabilite/domain/usecases/` (parse pur + `import_id` mémorisé en table pour l'idempotence, lignes rejetées comptées et montrées). Tant qu'il n'y a pas de serveur, l'idempotence se garde par l'empreinte du fichier ou un UUID d'import conservé en table ; avec le web, le relevé s'envoie par la table `bank_statement_imports` (UUID d'import, droit `manage-comptabilite`) et le serveur ne rejoue jamais un `import_id` connu. L'IMPORT TABLEUR de données métier (xlsx) est un autre sujet, À CONCEVOIR : bloc 21.

### Pièges
- Export tableur ≠ copie du PDF (un tableur sert à recalculer ; ne jamais reformater un montant).
- Un import qui exécute du SQL ou accepte une table non listée : interdit.
- Restauration d'une base ouverte : impossible (installation au lancement suivant).
- Chiffres et libellés « — » en PDF sans police Unicode.

### Tests à reprendre
`agrierp_flutter/test/export_comptabilite_test.dart`, `agrierp_flutter/test/rapports_exports_test.dart`, `agrierp_flutter/test/export_administration_test.dart`, `agrierp_flutter/test/rapprochement_poste_test.dart`, `agrierp_flutter/test/rapprochement_pdf_test.dart`, `agrierp_flutter/test/administration_locale_test.dart`, `agrierp_flutter/test/liste_achats_detail_test.dart` (compte les glyphes manquants dans les flux PDF), `agrierp_laravel/tests/Feature/ImportModuleTest.php`, `agrierp_laravel/tests/Feature/RapprochementBancaireTest.php`, `agrierp_laravel/tests/Feature/SauvegardesTest.php`.

### Questions à poser au client
Quels écrans doivent s'exporter en Excel (xlsx) ou CSV ? L'import d'un relevé bancaire est-il voulu (banque, format de colonnes) ? Sauvegarde automatique à la fermeture ?

---

## 9. Bloc 8 — Compilation avec le Flutter stable actuel

### Objectif
Le code compile avec le Flutter/Dart stable CIBLÉ ; la version est figée ; un piège de promotion de nullité est prévenu.

### Règle
- **Le correctif** (introduit au commit `ca8bd83`, « compatibilité Dart 3.13 ») : `agrierp_flutter/lib/core/sync/sync_engine.dart`, vers la ligne 2783, commentaire « Copie FINALE » : `final annoncees = actives;` posé AVANT `await _db.transaction(() async { … })`, puis `if (annoncees != null)` et `annoncees.difference(presentes)` à l'intérieur. Sans changement de règle : même valeur, même test de nullité.
- **Motif général** : une variable locale non finale (`Set<String>? actives;` assignée dans un `if`), un champ ou un paramètre modifiable, lue DANS une fermeture (`transaction(() async { … })`, `map`, `then`, `forEach`), n'est pas PROMUE en non-nulle par un test `if (actives != null)` fait à l'intérieur ou avant la fermeture : le compilateur ne peut pas garantir qu'elle n'est pas réassignée entre l'appel et l'exécution. Une erreur de compilation « property 'difference' can't be accessed on 'Set<String>?' » apparaît alors, uniquement sur certains SDK : le build Windows d'un SDK stable récent (Dart 3.13) échouait alors que `pubspec.yaml` l'autorisait.
- **Avant / après** :
```dart
// AVANT — refusé sous Dart 3.13 : `actives` est capturée par la fermeture et n'est pas finale
Set<String>? actives;
if (idsBruts != null) { actives = {...}; }
await _db.transaction(() async {
  if (actives != null) {
    _manquants = actives.difference(presentes).length; // erreur : toujours `Set<String>?`
  }
});

// APRÈS — copie finale avant la fermeture : la promotion marche sur une variable finale
final annoncees = actives;
await _db.transaction(() async {
  if (annoncees != null) {
    _manquants = annoncees.difference(presentes).length;
  }
});
```
- **Règle de prévention** : (1) tester la nullité d'une variable capturée sur une COPIE `final` posée avant la fermeture ; (2) préférer `final` + valeur calculée (`final actives = idsBruts == null ? null : {...};`) plutôt qu'une assignation conditionnelle ; (3) un nouveau SDK s'essaie par `flutter analyze` + `flutter test` AVANT de relever le plancher de `pubspec.yaml` ; (4) la version testée est figée (ci-dessous).
- **Version de Flutter figée dans AgriERP** (constat : AUCUNE version n'était figée ; `pubspec.yaml` ne porte que `sdk: ^3.12.2`, `pubspec.lock` `dart: ">=3.12.2 <4.0.0"`, `flutter: ">=3.38.4"`). Ajouts faits à AgriERP lors de cette session : `agrierp_flutter/.fvmrc` = `{"flutter": "3.47.7"}` (valeur lue de `flutter --version --machine` : Flutter 3.47.7, Dart 3.13.5, canal stable, révision `abaf9c523780`) ; dans `agrierp_flutter/build_windows.bat` un contrôle qui compare `flutter --version --machine` à `.fvmrc` et AVERTIT sans jamais échouer ; un test de garde dans `agrierp_flutter/test/environnement_test.dart` ; une section dans `agrierp_flutter/CLAUDE.md`.

### Fichiers de référence (AgriERP)
`agrierp_flutter/lib/core/sync/sync_engine.dart`, `agrierp_flutter/.fvmrc`, `agrierp_flutter/pubspec.yaml`, `agrierp_flutter/pubspec.lock`, `agrierp_flutter/build_windows.bat`, `agrierp_flutter/test/environnement_test.dart`.

### (a) Existe dans logialvia
`logialvia_app/pubspec.yaml` : `sdk: ^3.12.2` (donc le correctif reste utile : le Dart stable ≥ 3.13 est dans la plage), `logialvia_app/pubspec.lock` commité (A2 §9), `logialvia_app/analysis_options.yaml` (`avoid_print`, `prefer_const_constructors`, `require_trailing_commas`…). Aucun `.fvmrc`, aucun script de build.

### (b) Manque
Version de Flutter figée, contrôle dans le script, test de garde, revue des fermetures asynchrones.

### (c) Dans cette architecture
(1) Lancer `flutter analyze` sur le Flutter stable installé ; corriger tout `property … can't be accessed on …?` par copie `final` avant la fermeture. Cibles probables à relire : les use cases et ViewModels qui font `await _db.transaction(() async { … })` (ex. `logialvia_app/lib/comptabilite/data/repositories/comptabilite_repository_drift.dart`, `logialvia_app/lib/elevage/data/repositories/fiche_elevage_repository_drift.dart`). (2) Écrire `NEW:logialvia_app/.fvmrc` avec la version RÉELLEMENT installée (`flutter --version --machine`, champ `flutterVersion`) — ne jamais recopier « 3.47.7 » sans l'avoir lue. (3) Mettre à jour `logialvia/docs/11_SETUP_INSTALLATION.md` (« Flutter 3.19+ », `sdk >=3.3.0` : périmés). (4) Test de garde `NEW:logialvia_app/test/environnement_test.dart` : `.fvmrc` présent, valeur au format x.y.z.

### Pièges
- Une erreur de ce type n'apparaît que sur le SDK qui la durcit : le CI/poste de build doit avoir la même version que le poste du développeur.
- `^3.12.2` autorise tout 3.x suivant : « compile chez moi » ne prouve rien sur le Flutter du poste de build.
- Windows : version figée mais Visual Studio 2022 requis (bloc 10).

### Tests à reprendre
`agrierp_flutter/test/environnement_test.dart` (lit `build_windows.bat` : CRLF, ASCII, étiquettes définies, parenthèses équilibrées, aucun tube dans un bloc, `--dart-define` de l'environnement) ; test de garde de la version.

### Questions à poser au client
Aucune règle métier. Décision technique : qui met à jour `.fvmrc` et quand (à chaque montée de Flutter, après analyse et tests verts).

---

## 10. Bloc 9 — Empreinte du plan comptable SYSCOHADA

### Constat (le nom exact n'est pas « hash du plan » mais une EMPREINTE SHA-256 du CSV)
Il n'existe pas de « hash du plan embarqué » : le poste n'embarque AUCUNE copie du plan, il le reçoit du serveur. L'équivalent exact est l'**empreinte SHA-256 du fichier CSV officiel du client**, gardée en constante et vérifiée par test :
- fichier : `agrierp_laravel/database/data/plan-comptable-syscohada-revise.csv` (1 332 lignes, « Code;Libellé », UTF-8, CRLF d'origine) ;
- constante : `ImporterPlanSyscohadaService::EMPREINTE_SHA256 = '4103f4efc474fd6ffd5755575732d0eba7289a71f8364f51462e25924e9df143'` (`agrierp_laravel/app/Services/ImporterPlanSyscohadaService.php`) — empreinte revérifiée à la rédaction : `sha256sum` du fichier = cette valeur ;
- garde : `ImportPlanSyscohadaTest::test_le_csv_du_depot_est_octet_pour_octet_celui_du_client` (`agrierp_laravel/tests/Feature/ImportPlanSyscohadaTest.php`) compare `hash_file('sha256', csv)` à la constante ET à une copie littérale dans le test, et exige 1 332 lignes ;
- protection du fichier : `.gitattributes` à la racine du monorepo : `agrierp_laravel/database/data/*.csv -text` (aucune conversion de fin de ligne ; sinon l'empreinte change) ;
- parité du poste : `agrierp_flutter/test/plan_comptable_syscohada_test.dart` relit le CSV du dépôt Laravel (jamais copié) et le compare à ce que le poste stocke et affiche.
- Règle de l'import (`php artisan comptabilite:importer-plan-syscohada`, `agrierp_laravel/app/Console/Commands/ImporterPlanSyscohada.php`) : INSERTION SEULE (ne modifie, ne renomme, ne désactive jamais un compte existant) ; libellés tronqués à 255 (historique 150) ; trois libellés à corriger par le cabinet (`'54'`, `'603'`, `'66'`) ; un compte sans écriture n'apparaît jamais comme solde 0 dans la balance ; le Grand Livre s'ouvre sur « 531 ».

### Objectif
Garantir que le plan embarqué est octet pour octet celui du client, et que 1 300 comptes de plus n'altèrent aucun état.

### (a) Existe dans logialvia
`logialvia_app/lib/comptabilite/data/seed/plan_comptable_seeder.dart` (plan semé dans la base, `classe` de '1' à '7'), `logialvia_app/lib/comptabilite/data/tables/comptabilite_tables.dart` (`PlanComptable`, `isArchive`), `creerCompte` / `modifierCompte` / `archiverCompte` / `nombreEcrituresDuCompte` dans `logialvia_app/lib/comptabilite/data/repositories/comptabilite_repository_drift.dart`, `logialvia_app/test/comptabilite/moteur_comptable_test.dart`. Aucune empreinte, aucun CSV client.

### (b) Manque
Fichier de référence du client, empreinte, test d'intégrité, import par insertion seule.

### (c) Dans cette architecture
Placer le CSV du client dans `NEW:logialvia_app/assets/data/plan-comptable-syscohada-revise.csv` (déclaré dans `pubspec.yaml`, marqué `-text` dans `.gitattributes`) ; constante `EMPREINTE_SHA256` dans `NEW:logialvia_app/lib/comptabilite/domain/services/importer_plan_syscohada.dart` ; test `NEW:logialvia_app/test/comptabilite/plan_comptable_empreinte_test.dart` (package `crypto`, déjà dépendance : `sha256.convert(bytes)` ; le nombre de comptes ATTENDU est recalculé par lecture brute du CSV dans le test, jamais par le service). Le seeder existant reste intact (insertion seule).

### Pièges
- Un éditeur ou Git qui convertit CRLF → LF change l'empreinte sans changer un compte.
- Un import qui écrase un libellé de la ferme.
- Compter les comptes dans le test avec le code testé.

### Tests à reprendre
`agrierp_laravel/tests/Feature/ImportPlanSyscohadaTest.php`, `agrierp_flutter/test/plan_comptable_syscohada_test.dart`, `agrierp_flutter/test/plan_comptable_poste_test.dart`.

### Questions à poser au client
Disposez-vous du CSV officiel (SYSCOHADA révisé) et du libellé de validation du cabinet ? Les comptes déjà semés dans logialvia doivent-ils être conservés tels quels ?

---

## 11. Bloc 10 — Build et distribution Windows

### Objectif
Une commande produit l'installateur Windows ; les mises à jour ne touchent jamais aux données ; la désinstallation propose une sauvegarde.

### Règle
- `agrierp_flutter/build_windows.bat` (CRLF, ASCII) : arguments `--sans-tests`, `--sans-installateur`, `--env dev|recette|production` ; ordre : `flutter pub get` → `dart run build_runner build --delete-conflicting-outputs` → `flutter analyze` (doit finir par « No issues found! ») → `flutter test --concurrency=2` → `flutter build windows --release --dart-define=AGRIERP_ENV=<env>` → copie des DLL du runtime VC++ (`msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll` depuis System32 ; absence = ERREUR, un installateur sans elles livre une application qui ne démarre pas, sans message) → Inno Setup (`ISCC`). `--sans-installateur` : sans Inno Setup, produit seulement le dossier Release et sort en succès ; sans ce drapeau, Inno Setup absent = ÉCHEC. Version lue dans `pubspec.yaml` ; `-demo` refusé en production.
- `agrierp_flutter/installer/agrierp.iss` : **AppId stable** (`{{69B3D13F-4283-4B8E-ABD1-456845FC5182}`, le MÊME pour tous les environnements : une mise à jour, même AppId, ne touche jamais aux données), base locale dans `%APPDATA%\OLOUWACHEGOUN\donnees` (jamais dans le dossier d'installation). **DES-1** : la désinstallation supprime la base locale après avertissement Oui/Non (les saisies non synchronisées sont perdues). **DES-2** : la désinstallation PROPOSE une sauvegarde automatique (`Documents\AgriERP-Sauvegarde-AAAA-MM-JJ_HHMM`, jamais supprimée) puis retire les données ; la sauvegarde ferme d'abord le poste (`taskkill /F /IM agrierp.exe` : une base ouverte ne se copie pas de façon cohérente). Le coffre du système (PIN, mots de passe) n'est pas touché. Non compilé ni exécuté sur Windows à la rédaction.
- **Icône** : `agrierp_flutter/outils/generer_icone.py` génère `agrierp_flutter/windows/runner/resources/app_icon.ico` (16, 24, 32, 48, 64, 128, 256 px) depuis `assets/images/logo.png`, octets reproductibles, logo non carré centré sur un carré de sa couleur de coin (jamais étiré) ; `--verifier` contrôle qu'il est à jour ; `Runner.rc` l'embarque ; le script de build s'arrête s'il manque. Test : `agrierp_flutter/test/icone_application_test.dart`. Windows met les icônes en cache : un raccourci peut garder l'ancienne.
- **Démarrage** : toute panne avant `runApp` donne un ÉCRAN « ne peut pas démarrer » et une ligne dans `demarrage.log` (`agrierp_flutter/lib/core/demarrage/demarrage_poste.dart`) ; au-delà de 45 s la préparation est tenue pour bloquée.
- **Migration d'une VRAIE base** (réinstallation : la base reste dans le profil) : `user_version` ne dit pas ce que la base contient ; réconcilier les colonnes manquantes en fin de migration ; test avec d'anciennes bases (`agrierp_flutter/test/migration_bases_reelles_test.dart`, `agrierp_flutter/test/migration_toutes_versions_test.dart`).
- Documentation d'installation : `docs/INSTALLATION_LOCALE.md`, `docs/GUIDE_DEPLOIEMENT.md` (web, cPanel : applicable au futur serveur web de LogiALVIA, bloc 14 D-SRV-7).

### Fichiers de référence (AgriERP)
`agrierp_flutter/build_windows.bat`, `agrierp_flutter/installer/agrierp.iss`, `agrierp_flutter/outils/generer_icone.py`, `agrierp_flutter/windows/runner/Runner.rc`, `agrierp_flutter/lib/core/config/environnement.dart`, `agrierp_flutter/lib/core/demarrage/demarrage_poste.dart`, `agrierp_flutter/lib/core/demarrage/dossier_donnees.dart`, `agrierp_flutter/test/environnement_test.dart`, `agrierp_flutter/test/icone_application_test.dart`, `docs/INSTALLATION_LOCALE.md`.

### (a) Existe dans logialvia
`logialvia_app/outils/generer_icone.py`, `logialvia_app/windows/runner/Runner.rc`, `logialvia_app/windows/runner/resources`, `logialvia_app/lib/core/database/reprise_dossier_precedent.dart` (reprise de la base d'un dossier précédent), `logialvia_app/test/core/reprise_dossier_precedent_test.dart`, `logialvia/docs/11_SETUP_INSTALLATION.md`, `logialvia_app/outils/generer_manuel.dart`. Aucun `build_windows.bat`, aucun `installer/`.

### (b) Manque
Script de build, installateur Inno Setup, désinstallation avec sauvegarde, dossier de données unique (`DossierDonnees`), écran de panne au démarrage, contrôle de version de Flutter (bloc 8).

### (c) Dans cette architecture
Copier `build_windows.bat` et `agrierp.iss`, puis ADAPTER : nom de l'application, chemin des données (`ServiceSauvegarde` de logialvia utilise `DossierDocuments`, `logialvia_app/lib/administration/domain/services/service_sauvegarde.dart`), nouvel AppId (GUID NOUVEAU : ne JAMAIS réutiliser celui d'AgriERP), éditeur, icône. La sauvegarde proposée à la désinstallation = la sauvegarde COMPLÈTE de `ServiceSauvegarde.genererBaseComplete`. `reprise_dossier_precedent.dart` couvre déjà un changement de dossier de données : relire avant d'imposer un dossier.

### Pièges
- DLL verrouillée (ex. `sqlite3.dll`) pendant `flutter build` / `flutter clean` quand l'application tourne encore : fermer `agrierp.exe` (`taskkill /F /IM agrierp.exe`, présent dans `agrierp.iss` mais seulement dans l'étape de sauvegarde de la désinstallation) puis `flutter clean`. ⚠️ Ce piège « sqlite3.dll » n'est PAS écrit dans le dépôt AgriERP (grep négatif sur `sqlite3.dll` et `flutter clean`) : il est cité par le client ; seul le `taskkill` de l'installateur existe.
- Runtime VC++ absent → l'application ne démarre pas sans message.
- Un `.bat` en LF ou en UTF-8 : cmd.exe le lit mal (garde de test).
- `--sans-installateur` n'est PAS une livraison (le script le dit).
- Désinstallation : les données locales disparaissent (DES-1) ; la sauvegarde est PROPOSÉE, pas imposée.
- Jamais vérifié sur Windows réel : installateur, fenêtre sans bordure, désinstallation avec sauvegarde.

### Tests à reprendre
`agrierp_flutter/test/environnement_test.dart` (script et installateur lus, jamais exécutés), `agrierp_flutter/test/icone_application_test.dart`, `agrierp_flutter/test/migration_bases_reelles_test.dart`.

### Questions à poser au client
Nom de l'installateur et de l'éditeur ; dossier des données ; la désinstallation supprime-t-elle les données (DES-1) ? Sauvegarde automatique proposée (DES-2) ? Un poste ou plusieurs (avec le web, plusieurs postes se synchronisent par leur jeton, blocs 15 et 16 ; sans lui chaque poste serait indépendant) ?

---

## 12. Bloc 11 — Bascule et clôture d'exercice

### Objectif
Clôturer un exercice par étapes gardées, ouvrir le suivant, sans jamais corrompre le bilan.

### Règle (CP-4, EX1 à EX5)
- **Étapes** : confirmer l'étape 1 (`confirmer_etape1`), solder les comptes de gestion classes 6 et 7 (`solder_comptes_gestion`, étape 2 ; la classe 8 n'est pas soldée : un compte HAO avec solde rend l'à-nouveau déséquilibré et la clôture est REFUSÉE avec son motif), clôturer l'exercice (`cloturer_exercice`), rouvrir (`rouvrir_exercice`, droit d'administration), ouvrir le suivant (`ouvrir_exercice_suivant`), ouvrir le premier (`ouvrir_exercice`), clôturer / déclôturer une période mensuelle. Clôture GARDÉE : échéance passée (clôture refusée avant la fin de l'exercice), étapes 1 et 2 faites, N-1 clos, à-nouveau équilibré ; à-nouveau verrouillé (ni modifiable ni archivable).
- **États justes après clôture (R1)** : jamais historique + à-nouveau ; l'écriture de solde (étape 2) est écartée du Bilan et du Compte de résultat (le résultat reste sur la ligne « Résultat de l'exercice »), mêmes totaux. À-nouveaux provisoires tant que N est ouvert.
- **Exercice clos verrouillé (EX5)** : stock, fiches d'élevage (Q3), paie (Q4), déplacement d'écriture, date d'une dépense comptabilisée refusés ; messages en JJ/MM/AAAA.
- **Poste (CP-4)** : le poste n'écrit JAMAIS `fiscal_years` ni `periodic_closures` directement — il écrit une DEMANDE (`fiscal_closure_requests`, `kind` + `payload`) après avoir refusé ce qu'il sait juger (`CalculCloture`, parité exécutée avec `ClotureExerciceService`) ; le serveur rejoue, dans l'ordre d'INSERTION (`rowid`, car `updated_at` n'a que la seconde), et l'état redescend au tirage. ⚠️ **Avec le web (décision du 07/11/2026), cette indirection S'APPLIQUE à logialvia** : le poste écrit une DEMANDE rejouée par le serveur, jamais l'état d'exercice. Tant que le serveur n'existe pas, le use case ÉCRIT directement l'exercice (mode provisoire), en gardant les MÊMES refus et le même ordre d'étapes ; le principe « un seul écrivain de l'état d'exercice » reste dans les deux cas.
- Heure : toute date « du jour » à l'heure du pays.

### Fichiers de référence (AgriERP)
`agrierp_laravel/app/Services/ClotureExerciceService.php`, `agrierp_laravel/app/Services/OuvertureExerciceService.php`, `agrierp_laravel/app/Actions/ReopenFiscalYearAction.php`, `agrierp_laravel/app/Livewire/Comptabilite/ClotureExercice.php`, `agrierp_laravel/app/Services/AnouveauInitialService.php`, `agrierp_flutter/lib/features/comptabilite/cloture_exercice_repository.dart` (`CalculCloture`), `agrierp_flutter/lib/features/comptabilite/cloture_exercice_page.dart`, `agrierp_flutter/lib/features/comptabilite/soldes_exercice.dart`, `agrierp_flutter/lib/features/comptabilite/mention_anouveaux.dart`, `agrierp_flutter/lib/features/demarrage/premier_demarrage_repository.dart`.

### (a) Existe dans logialvia
`cloturerExercice(int annee)` / `cloturerMois` / `decloturerMois` dans `logialvia_app/lib/comptabilite/data/repositories/comptabilite_repository_drift.dart` (lignes ~434 à ~509) : verrouille les écritures de l'exercice (`isLocked`) et ouvre l'exercice suivant s'il n'existe pas ; écran `logialvia_app/lib/comptabilite/presentation/screens/cloture_exercice_screen.dart`, `logialvia_app/lib/comptabilite/domain/services/bilan_entreprise.dart`, `logialvia_app/lib/comptabilite/domain/services/moteur_comptable.dart`. BR-CPT-001/002/006 de `B6_Regles_Metier.md`. ⚠️ Écart assumé de logialvia : « verrouillage DÉFINITIF, aucun mécanisme de déclôture » (`comptabilite_tables.dart`) pour l'exercice annuel ; AgriERP a `rouvrir_exercice` (H4).

### (b) Manque
Gardes de clôture, étape 1 / étape 2 / solde des classes 6-7, à-nouveau, écriture de solde écartée des états, réouverture, contrôle « ouverture N+1 = clôture N ».

### (c) Dans cette architecture
`NEW:logialvia_app/lib/comptabilite/domain/services/calcul_cloture.dart` : fonctions pures (`peutCloturer(exercice, aujourdhui, ecritures)` → refus ou null ; `ecrituresDeSolde(ecritures)` ; `anouveau(balance)`) ; `NEW:…/domain/usecases/cloturer_exercice_usecase.dart` orchestre dans UNE transaction Drift via le dépôt ; le ViewModel de `cloture_exercice_screen.dart` n'a aucune règle. `BR-CPT-002` (écritures de report) y est implémentée une seule fois.

### Pièges
- Mois de décembre qui affiche un chiffre d'affaires négatif quand l'écriture de solde est comptée (EX-Q14).
- Demandes envoyées dans l'ordre de `updated_at` à la seconde : trois gestes enchaînés se départagent au hasard → ordre d'insertion.
- Clôturer sans à-nouveau équilibré.
- Ouvrir N+2 quand N n'est pas clos (au plus deux exercices ouverts).

### Tests à reprendre
`agrierp_flutter/test/cloture_exercice_poste_test.dart`, `agrierp_flutter/test/cloture_exercice_parite_php_test.dart` (ses cas sont à réécrire en valeurs écrites à la main), `agrierp_laravel/tests/Feature/ClotureExerciceTest.php`, `agrierp_laravel/tests/Feature/ClotureGardeeTest.php`, `agrierp_laravel/tests/Feature/ReouvertureExerciceTest.php`, `agrierp_laravel/tests/Feature/OuvertureExerciceAutomatiqueTest.php`, `agrierp_laravel/tests/Feature/TauxLettrageClotureTest.php`, `agrierp_laravel/tests/Feature/ErreursExerciceSans500Test.php`.

### Questions à poser au client
Réouverture d'un exercice clos autorisée (admin) ou définitive (état actuel de logialvia) ? Échéance de clôture (refusée avant la fin d'exercice) ? Classe 8 soldée ou non ? À valider avec le cabinet comptable.

---

## 13. Bloc 12 — Bandes et sujets, avec toutes les actions

### Objectif
Gérer les bandes (créer, modifier, archiver, restaurer), les sujets (entrées, sorties), les transferts entre bandes, la transformation (abattage), les dons, et corriger les bandes existantes.

### Règle
**Bande (`SaisieBandeAction`, un seul point de passage)** :
- Création : effectif initial = effectif courant = quantité saisie, statut `actif` ; une bande datée dans un exercice CLOS est refusée. La bande d'origine (constitution) relève du transfert, jamais de la création.
- Modification : stade, statut, et effectif actuel SEULEMENT s'il est fourni ; l'espèce et l'effectif initial ne changent jamais ; le code non plus, SAUF pour corriger un doublon (ticket UNI : se renomme vers un code libre). Une bande archivée n'est plus modifiable ; une modification identique n'écrit rien.
- **BS-Q4** : dès qu'une bande a des fiches, son effectif n'est plus modifiable par « Modifier la Bande » — la cascade des fiches en est l'UNIQUE écrivain : « L'effectif de cette bande est tenu par ses fiches journalières : corrigez-le depuis la fiche, la bande suit automatiquement. » (info-bulle du champ grisé : « Cette bande a des fiches journalières : son effectif se corrige depuis la fiche (la bande suit automatiquement). »)
- **BS-Q3** : une bande à effectif vivant > 0 ne s'archive pas : « Cette bande compte encore 200 sujets vivants : archivez-la après avoir sorti ou transféré les sujets restants. » (singulier à 1 : « sujet vivant »).
- **BS-Q7** : une bande archivée se restaure, sauf si son code est déjà porté par une bande en cours : « Le code « X » est déjà utilisé par une bande en cours : cette bande ne peut pas être restaurée. » Jamais deux bandes en cours sous le même code. Archivage = `is_active = false`, la ligne est gardée.

**Transferts (15.46)** : un transfert est un FAIT daté, jamais supprimé, annulé. Contrôles : bandes existantes, distinctes, de la même espèce, non archivées ; date ni future ni antérieure à la création d'une bande ; source suffisante CE JOUR et chaque jour suivant (sinon un effectif deviendrait négatif et serait ramené à 0 en silence) ; catégorie obligatoire pour une bande à chaîne, la même à l'arrivée. **Constitution** : une bande créée pour accueillir une portée compte déjà ces sujets ; le transfert « constitution » inscrit la SORTIE de la bande mère à la date de création, sans entrée dans la cible ⇒ chaque sujet n'est compté qu'une fois (c'est la CORRECTION DES BANDES EXISTANTES). Effets écrits sur les fiches des deux bandes (colonnes `transfert_*` dérivées) puis cascade.

**Sujets (`SaisieSujetAction`)** : ajouter / modifier / archiver une entrée (naissance, achat…) ; refus : exercice clos ; un don s'y refuse (se saisit sur la fiche, ventilé) ; une entrée exige le départ (volailles) ; naissance → catégorie la plus jeune, achat → Jeune (reproducteurs) ou Poulette (pondeuses).

**Transformation EL-1** (bon d'abattage) : n'écrit QUE le fait (bande, sujets, produit, quantité produite, jour) ; refus avant d'écrire : effectif disponible relu, bande et produit connus, exercice clos sur le jour saisi ET sur aujourd'hui, messages de la validation (`lotId`, `qtyAnimals`, `productId`, `qtyProduced`, `transformationDate`) ; effets : sortie de la bande (Jeunes pour des reproducteurs, Pondeuse pour des pondeuses), entrée du produit fini au stock, audit. Verrous de stock avant toute fiche (ordre unique).

**Dons (I1)** sur toutes les fiches, ventilés par catégorie, sortent de l'effectif.

### Fichiers de référence (AgriERP)
`agrierp_laravel/app/Actions/SaisieBandeAction.php`, `agrierp_laravel/app/Actions/SaisieSujetAction.php`, `agrierp_laravel/app/Actions/TransferBetweenLotsAction.php`, `agrierp_laravel/app/Actions/SaisieTransformationAction.php`, `agrierp_laravel/app/Livewire/Elevage/GestionBandes.php`, `agrierp_laravel/app/Livewire/Elevage/EnregistrerSujets.php`, `agrierp_laravel/app/Livewire/Elevage/TransfertsBandes.php`, `agrierp_laravel/app/Livewire/Elevage/TransformationForm.php`, `agrierp_laravel/app/Support/OrdreDesVerrous.php`, `agrierp_flutter/lib/features/elevage/bandes_repository.dart`, `agrierp_flutter/lib/features/elevage/gestion_bandes_screen.dart`, `agrierp_flutter/lib/features/elevage/sujets_entrees_repository.dart`, `agrierp_flutter/lib/features/elevage/sujets_repository.dart`, `agrierp_flutter/lib/features/elevage/transferts_repository.dart`, `agrierp_flutter/lib/features/elevage/transferts_bandes_screen.dart`, `agrierp_flutter/lib/features/elevage/transformation_repository.dart`, `agrierp_flutter/lib/features/elevage/transformation_screen.dart`, `agrierp_flutter/lib/features/elevage/enregistrer_sujets_screen.dart`.

### (a) Existe dans logialvia
`logialvia_app/lib/elevage/domain/entities/bande.dart` (code, espèce, date de mise en bande, effectif initial, date de clôture, `jourDeCycle`, `couvre`), `logialvia_app/lib/elevage/domain/repositories/bandes_repository.dart` (`chargerBandes`, `bandeCouvrant`, `creerBande`, `cloturerBande`), `logialvia_app/lib/elevage/data/repositories/bandes_repository_drift.dart`, `logialvia_app/lib/elevage/data/tables/bandes_table.dart`, `logialvia_app/lib/elevage/data/tables/cycle_couveuse_table.dart` (couveuse), `logialvia_app/lib/elevage/domain/entities/cycle_incubation.dart`. Pas d'écran « Gestion des Bandes » listé dans les 31 écrans (`logialvia/docs/03_INVENTAIRE_31_ECRANS.md`) : l'écran n'existe pas dans le prototype, donc A1 (§1 « traducteur fidèle ») impose de le faire valider avant de le créer.

### (b) Manque
Modifier / archiver / restaurer, écran de gestion, transferts, constitution, transformation, entrées de sujets, dons ventilés, correction des bandes existantes, doublons de code, parité des refus.

### (c) Dans cette architecture
Use cases NEW dans `logialvia_app/lib/elevage/domain/usecases/` : `CreerBandeUseCase`, `ModifierBandeUseCase`, `ArchiverBandeUseCase`, `RestaurerBandeUseCase`, `TransfererSujetsUseCase`, `EnregistrerTransformationUseCase`, `EnregistrerEntreeSujetUseCase` ; entités `TransfertBande`, `Transformation` ; tables Drift `transferts_bandes`, `transformations`, colonne `isActive` des bandes (migration explicite) ; les messages de refus sont des `static String message…` de `domain` (comme `BandesRepository.messageEffectifVivant` d'AgriERP), lus par les tests. Le seul écrivain de l'effectif d'une bande est la cascade de fiche (bloc 1).

### Pièges
- Deux écrivains de l'effectif de la bande (fiche ET modification) : l'effectif dérive en silence.
- Archiver une bande vivante.
- Transfert accepté qui rend négatif un effectif futur de la source.
- Transformation : poser l'exercice clos sur le jour saisi ET sur aujourd'hui ; idempotence par identifiant.
- Doublons de code : ne jamais corriger à la place du client (renommage explicite).
- Bande sans fiche : l'effectif reste modifiable librement.

### Tests à reprendre
`agrierp_flutter/test/bandes_poste_crud_test.dart`, `agrierp_flutter/test/bandes_parite_test.dart`, `agrierp_flutter/test/bandes_decisions_parite_test.dart`, `agrierp_flutter/test/bandes_blade_test.dart`, `agrierp_flutter/test/sujets_poste_crud_test.dart`, `agrierp_flutter/test/sujets_blade_test.dart`, `agrierp_flutter/test/transferts_bandes_test.dart`, `agrierp_flutter/test/transformation_poste_test.dart`, `agrierp_laravel/tests/Feature/BandesSaisieWebTest.php`, `agrierp_laravel/tests/Feature/BandesSujetsPosteTest.php`, `agrierp_laravel/tests/Feature/TransfertsEntreBandesTest.php`, `agrierp_laravel/tests/Feature/SyncTransformationsTest.php`, `agrierp_laravel/tests/Feature/DonsToutesFichesTest.php`, `agrierp_laravel/tests/Feature/OrdreDesVerrousTest.php`. Cas à écrire à la main : transfert de 30 sujets d'une source à 100 → 70 et cible +30 ; source à 20 → refus ; archive d'une bande à 200 → message BS-Q3 ; restauration avec code pris → message BS-Q7.

### Questions à poser au client
Écran « Gestion des Bandes » absent du prototype : voulu ? Une filière peut-elle avoir plusieurs bandes en cours ? Pisciculture : une bande = un bassin / un étang ? Les bandes existantes (une par espèce implicite) : comment les répartir ?

---

## 14. Bloc 13 — Seuils, plan comptable, écriture manuelle, clôture au poste, immobilisations, aide

Les cinq sous-blocs sont indépendants ; chacun garde les sous-titres du format.

### 13a — Seuils d'alerte (ST-1 / ST-2)
- **Objectif / Règle** : archiver un produit (jamais le supprimer) et configurer son seuil d'alerte. `ProduitsRepository.archiver` / `definirSeuil` ; l'envoi porte `is_active` (faux = archivage, jamais une réactivation déduite) ; le crayon de l'onglet « Seuils d'Alerte » ouvre une modale ; un produit archivé ne se propose plus à la vente mais reste dans l'historique.
- **Fichiers (AgriERP)** : `agrierp_flutter/lib/features/stocks/produits_repository.dart`, `agrierp_flutter/lib/features/stocks/catalogue_produits_screen.dart`, `agrierp_flutter/lib/features/stocks/gestion_stocks_screen.dart`, `agrierp_laravel/app/Services/ProductCatalogService.php`.
- **logialvia** : `threshold` existe dans `logialvia_app/lib/approvisionnement/data/tables/intrants_table.dart` et `logialvia_app/lib/commercial/data/tables/produits_vendables_table.dart` ; `logialvia_app/test/pilotage/stock_critique_test.dart`. À ajouter : archivage logique, modale de seuil (écran `logialvia_app/lib/commercial/presentation/screens/catalogue_screen.dart`, `logialvia_app/lib/approvisionnement/presentation/screens/gestion_stocks_screen.dart`).
- **Pièges** : stock négatif (H14 : message et drapeau) ; seuil non numérique (`logialvia_app/lib/core/saisie/formats_saisie.dart`).
- **Tests** : `agrierp_flutter/test/produits_archive_seuil_test.dart`.
- **Questions** : seuil par produit ou par catégorie ? Alerte en cloche et au tableau de bord ?

### 13b — Plan comptable (CP-1) : nouveau compte, modifier, archiver
- **Règle** : `creerCompte` / `modifierCompte` / `archiverCompte` REFUSENT avant d'écrire, avec les messages du web ; l'archivage est refusé si une ligne d'écriture cite le compte ; jamais de suppression ; le libellé de classe (« 6 - Charges ») est unique pour écran, sélecteur et PDF ; un compte saisi au poste est créé tel quel (pas de synchro ici).
- **Fichiers (AgriERP)** : `agrierp_laravel/app/Services/PlanComptableService.php`, `agrierp_flutter/lib/features/comptabilite/comptabilite_repository.dart`, `agrierp_flutter/lib/features/comptabilite/plan_comptable_modales.dart`, `agrierp_flutter/lib/features/comptabilite/nature_compte.dart`.
- **logialvia** : DÉJÀ présent (`creerCompte`, `modifierCompte`, `archiverCompte`, `nombreEcrituresDuCompte`, `logialvia_app/lib/comptabilite/presentation/screens/plan_comptable_screen.dart`). À vérifier : refus d'archivage d'un compte mouvementé, unicité du numéro, classe cohérente avec le premier chiffre.
- **Tests** : `agrierp_flutter/test/plan_comptable_poste_test.dart`, `agrierp_laravel/tests/Feature/SyncPlanComptableTest.php`.
- **Questions** : numéro libre ou imposé (classe + longueur) ?

### 13c — Écriture manuelle « Saisie d'Écriture » (CP-2)
- **Règle** : opération diverse équilibrée (débit = crédit à la décime, vérifié AVANT écriture), débit ≠ crédit pour une écriture à deux lignes, date dans un exercice OUVERT et un mois non clôturé, écriture non verrouillée ; numéro `OD-AAAA-NNNN` attribué par le serveur (l'année de l'écriture) — **tant qu'il n'y a pas de serveur : numérotation séquentielle locale à l'enregistrement, dans la même transaction que l'écriture, jamais recalculée ; avec le web, le numéro est attribué par le serveur (jamais inventé au poste)** (logialvia a déjà `comptabilite_view_model.dart` qui forme « OD-2026-… » : déplacer la numérotation en `domain`/dépôt, hors du ViewModel) ; une écriture à plus de deux lignes, verrouillée ou d'à-nouveau ne se retouche pas ; archivage = contre-passation exacte, jamais suppression. Source unique de toute écriture : `AccountingEntryService::record()` / `recordManual()`.
- **Fichiers (AgriERP)** : `agrierp_laravel/app/Actions/SaisieEcritureManuelleAction.php`, `agrierp_laravel/app/Services/AccountingEntryService.php`, `agrierp_flutter/lib/features/comptabilite/comptabilite_repository.dart` (`creerEcriture`, `modifierEcriture`, `archiverEcriture`).
- **logialvia** : `enregistrerPiece`, `remplacerPiece`, `supprimerPiece`, `supprimerEcriture` dans `logialvia_app/lib/comptabilite/data/repositories/comptabilite_repository_drift.dart` ; `logialvia_app/lib/comptabilite/domain/services/moteur_comptable.dart`, `logialvia_app/lib/comptabilite/domain/usecases/generer_ecritures_automatiques.dart`. ⚠️ « supprimer » une écriture contredit « archiver / contre-passer » d'AgriERP : à arbitrer (B6 BR-ADM-003 : journalisation).
- **Tests** : `agrierp_flutter/test/ecritures_manuelles_poste_test.dart`, `agrierp_laravel/tests/Feature/SyncEcrituresManuellesTest.php`, `agrierp_laravel/tests/Feature/NumerotationEcrituresTest.php`, `logialvia_app/test/comptabilite/moteur_comptable_test.dart`.
- **Questions** : suppression d'écriture autorisée ou contre-passation seulement ? Format du numéro ?

### 13d — Clôture d'exercice au poste (CP-4)
Voir bloc 11 (avec le web : DEMANDE rejouée par le serveur ; en mode provisoire sans serveur : écriture directe, mêmes refus).

### 13e — Immobilisations (CP-3)
- **Règle** : registre ; enregistrer (capitalisation : contrepartie vide / `credit` / compte de trésorerie), modifier (valeur figée si comptabilisée), **sortir** (cession ou réforme, jamais une suppression), dotation demandée à une date d'arrêté (écart recalculé contre le grand livre, idempotente). `isCapitalized` posé par le point de passage unique, jamais par l'écran. ⚠️ **`CalculAmortissement.moisEntre` reproduit `Carbon::diffInMonths` de Carbon 3 : des mois À VIRGULE** (31/01 → 28/02 = 0,903 mois), sinon le cumul affiché diffère du web ; AgriERP le prouve par 95 cas (`immobilisations_parite_php_test`, mutation vérifiée). Pour logialvia (pas de web) : décider UNE règle de mois (entiers ou à virgule) AVEC le client et l'écrire comme règle B6.
- **Fichiers (AgriERP)** : `agrierp_laravel/app/Services/ImmobilisationService.php`, `agrierp_laravel/app/Actions/RecordAssetAcquisitionEntryAction.php`, `agrierp_laravel/app/Actions/RecordDepreciationEntryAction.php`, `agrierp_flutter/lib/features/comptabilite/immobilisations_repository.dart`, `agrierp_flutter/lib/features/comptabilite/immobilisations_page.dart`.
- **logialvia** : AUCUN registre (seules des lignes « Dotations aux Amortissements » dans `logialvia_app/lib/comptabilite/domain/services/moteur_comptable.dart` et le bilan).
- **Pièges** : mois à virgule ; dotation qui double une écriture déjà passée ; sortie d'un bien déjà sorti.
- **Tests** : `agrierp_flutter/test/immobilisations_poste_test.dart`, `agrierp_flutter/test/immobilisations_parite_php_test.dart` (95 cas : récupérer le principe, pas les valeurs PHP), `agrierp_laravel/tests/Feature/ImmobilisationsTest.php`, `agrierp_laravel/tests/Feature/SyncImmobilisationsTest.php`.
- **Questions** : méthode d'amortissement (linéaire seule ?), durées par catégorie, prorata temporis au mois ou au jour, date d'acquisition et de mise en service.

### 13f — Aide (AIDE-1)
- **Règle** : MODULE éteint par défaut (`assistant_demarrage` dans Modules Actifs) ; bouton flottant d'aide posé 148 px au-dessus d'« Accès rapide » ; panneau d'aide PAR ÉCRAN ; visite guidée à VRAI overlay (`CustomPainter` percé aux rectangles des cibles repérées par `GlobalKey`) ; placement des bulles en fonction transposée d'un fichier JS ; **un fichier de textes unique** (clé = chemin de la route ; `ecrans` / `poste_seul` / `defaut` / `visite` / `panneau`), une COPIE Dart GÉNÉRÉE (jamais éditée) et un test de parité ; chaque route authentifiée ajoutée DOIT avoir son entrée (test) ; « Relancer l'assistant » réservé à l'admin ; assistant de démarrage relançable (étapes dont « Exercice comptable »).
- **Fichiers (AgriERP)** : `agrierp_laravel/lang/fr/aide_ecrans.php`, `agrierp_laravel/app/Support/AideEcrans.php`, `agrierp_flutter/lib/core/aide/aide_ecrans.dart` (généré), `agrierp_flutter/lib/core/aide/placement_visite.dart`, `agrierp_flutter/lib/core/widgets/aide_flottante.dart`, `agrierp_flutter/outils/generer_aide_ecrans.php`, `agrierp_flutter/lib/features/demarrage/premier_demarrage_screen.dart`.
- **logialvia** : visite guidée DÉJÀ présente (`logialvia_app/lib/core/tour/tour_guide.dart`, `scenarios_tour.dart`, `superposition_tour.dart`, test `logialvia_app/test/core/tour_guide_test.dart`), modules actifs (`logialvia_app/lib/administration/data/tables/modules_actifs_table.dart`, `logialvia_app/lib/administration/presentation/viewmodels/modules_actifs_view_model.dart`), `logialvia_app/lib/administration/presentation/screens/compte/aide_a_propos_screen.dart`.
- **Dans cette architecture** : sans PHP, la « source unique + copie générée + parité » devient : un seul fichier Dart `NEW:logialvia_app/lib/core/aide/aide_ecrans.dart` écrit à la main (ou JSON dans `assets/`) + un test de garde qui lit `app_router.dart` et exige une entrée pour chaque route ; plus de génération.
- **Pièges** : un `addEventListener`/écouteur global hors cycle de vie ; bouton posé quand le module est éteint ; l'overlay ne doit pas bloquer les clics hors de la visite.
- **Tests** : `agrierp_flutter/test/aide_flottante_test.dart`, `agrierp_flutter/test/aide_ecrans_parite_test.dart` (à adapter : routes ↔ textes), `agrierp_laravel/tests/Feature/AideFlottanteTest.php`, `logialvia_app/test/core/tour_guide_test.dart`.
- **Questions** : texte d'aide à fournir par écran (le client rédige ou Claude propose) ? Module éteint par défaut ?

---

## 15. Bloc 14 — Transversal : doctrine, architecture serveur, ordre de construction du web

> **Révisé le 07/11/2026 — décision du client : « on va CRÉER LE WEB » de LogiALVIA** (aujourd'hui Flutter seul). LogiALVIA aura donc un serveur web (Laravel recommandé, pour réutiliser le code d'AgriERP). La doctrine d'AgriERP — **la vue web est le maître, le poste lui est fidèle à 100 %, la parité est EXÉCUTÉE contre le vrai serveur** (`docs/DOCTRINE_PORTAGE.md`, articles 0 et 5) — **s'applique de nouveau à la cible**. Les anciennes traductions « pour une application sans serveur » (tests unitaires Dart à la place des parités PHP, entiers `autoIncrement`, hash local obligatoire, écritures directes à la place des demandes rejouées) restent valables **tant que le web n'existe pas**, et seulement jusque-là : chaque module bascule dès que son écran web et son point de passage serveur existent (voir 14.3).

### 14.1 Doctrine : règles d'AgriERP et traduction pour LogiALVIA

| Règle AgriERP | Traduction pour LogiALVIA (web créé) |
|---|---|
| Web = maître, fidélité 100 % (art. 0 et 5) | **Dès qu'un module a son écran web**, la vue web (Blade/Livewire) est le maître et le poste lui est fidèle : structure, libellés, retours, logique métier, prouvés par un garde-fou. Un critère absent du web se construit d'abord sur le web, puis se porte. **Tant que le web d'un module n'existe pas** : le maître est le document de logialvia (`logialvia/docs/B6_Regles_Metier.md`, `05_LOGIQUE_CALCUL_FORMULAIRES.md`, fiche F/H du module) ; à défaut, la règle donnée ici ; à défaut, DEMANDER. Le prototype HTML (`logialvia/docs/A1_MASTER_PROMPT.md` §1) reste la source visuelle des DEUX surfaces (le dépôt cloné ne le contient pas : à demander au client). Écart assumé : `// ECART_DELIBERE:` (marqueur de logialvia), y compris dans le PHP |
| Gardes qui lisent les sources | Inchangé, et étendu au web : les tests lisent le CODE (`File(...).readAsStringSync()`), pas seulement l'exécution. Modèles : `agrierp_flutter/test/conformite_portage_test.dart` (interdit `fontSize: 12`, `AlertDialog`, `showDialog` sans modale unique, `constraints.maxWidth` pour choisir une mise en page), `agrierp_flutter/test/fidelite_libelles_test.dart` (libellés = littéraux de chaînes, JAMAIS commentaires : `chainesDe`), `agrierp_flutter/test/conformite_structure_test.dart` (ordre des colonnes), et `agrierp_flutter/test/rappels_du_jour_blade_test.dart` (les libellés du poste sont LUS dans la vue Blade). Ne jamais les affaiblir pour faire passer un écran |
| Absorbeurs stricts | **S'applique** : l'absorbeur du tirage (poste) REFUSE une ligne incohérente au lieu de la lisser ; une table « mixte » (saisie au poste ET tirée) n'écrase jamais une ligne `pending`/`conflict` ; un test garantit que chaque table envoyée est comptée « à envoyer » (`agrierp_flutter/test/compteur_attente_test.dart`). La restauration de logialvia (`logialvia_app/lib/administration/domain/services/service_restauration.dart`) garde sa propre rigueur |
| UUID | **S'applique** (changement de décision, voir 14.2 D-SRV-3) : clés primaires des tables synchronisables = UUID générés au poste, jamais d'entiers auto-incrémentés |
| `app_database.g.dart` jamais à la main | Inchangé (`dart run build_runner build --delete-conflicting-outputs`), et **règle du schéma partagé** (`CLAUDE.md` racine) : une table synchronisable modifiée côté Laravel (migration) l'est aussi côté Drift, et inversement ; chaque palier = `versionSchema` + bloc `if (from < N)` explicite + test de migration (`logialvia_app/test/core/migration_idempotente_test.dart`) |
| Tout en français | Prose, libellés, commentaires, noms de tests, messages de commit, messages de refus du serveur (même texte au web, au poste et à l'envoi) |
| Un écrivain par table / un point de passage par règle | **Côté serveur : UN point de passage par règle métier** (`Actions/` et `Services/` d'AgriERP : `SaisieUtilisateurAction`, `ProductCatalogService`, `AdjustStockAction`, `AccountingEntryService::record()`…), appelé par l'écran web ET par la synchronisation. Côté poste : un seul dépôt écrit une table, vérifié par un test qui lit les sources |
| Parité PHP exécutée (`agrierp_flutter/test/php_laravel.dart`) | **RÉTABLIE dès que le web existe.** Le test envoie ses entrées en JSON au VRAI PHP du dépôt Laravel (aucune règle recopiée), compare au résultat Dart et à un littéral calculé à la main ; sans PHP ni dépôt, le test est SAUTÉ AVEC SA RAISON (jamais vert à vide, jamais rouge hors ligne) ; chemins par `NEW:logialvia_app/test/chemins_depot.dart` (modèle : `agrierp_flutter/test/chemins_depot.dart`, variable d'environnement dédiée à LogiALVIA). **On garde** les jeux de cas écrits à la main (ceux de ce guide), le test « propriété » (somme des catégories = total, jamais négatif, idempotence de la cascade) et le test de mutation manuel : ils restent la vérité de départ, puis deviennent les entrées de la parité. Tant qu'un module n'a pas son PHP : jeux de cas à la main seuls |
| Donnée inconnue = `'—'` jamais `0` | À appliquer aux effectifs inconnus (lapins), aux totaux non calculables et à un compteur dont le serveur ne sait rien (« Jamais synchronisé » : « — », jamais 0) |
| Fuseau : heure du pays | Poste : `HeureBenin` (UTC+1 fixe, `agrierp_flutter/lib/core/temps/heure_benin.dart`, test `agrierp_flutter/test/heure_benin_test.dart`, doit passer avec `TZ=America/New_York`). Serveur : fuseau `Africa/Porto-Novo` pour les dates métier (planificateur compris), UTC pour les instants techniques ; jamais `DateTime.now()` ni l'horloge du poste pour un jour métier |
| Modales / composants uniques | Un `AppModal`, un `KpiCard`, un tableau mensuel (déjà `logialvia_app/lib/core/widgets/app_modal.dart`, `kpi_card.dart`), et côté web UN composant Blade par rôle (`<x-modal>`, jamais de variante locale ; A2 §12) |
| Définition de « terminé » | `flutter analyze` sans erreur, `flutter test` vert, **`php artisan test --testsuite=Feature` vert**, règle écrite dans B6 avec son `BR-…`, et ce qui n'a PAS été vérifié dit explicitement |

### 14.2 Décisions d'architecture serveur (à valider avec le client AVANT de coder)

Recommandations tirées d'AgriERP ; aucune n'est une règle métier, toutes sont des choix de plomberie qui conditionnent le reste. Chacune se consigne dans un ADR de `logialvia/docs/`.

**D-SRV-1 — Pile du serveur : Laravel 12 + Livewire 3 + Sanctum, recommandé.** C'est ce qui permet de reprendre `Actions/`, `Services/`, la matrice de rôles, le contrôleur de synchronisation et ses tests. Autre pile possible (le blueprint dit que ce sont les règles qui comptent, pas les frameworks), mais on perd le code réutilisable. Référence : `agrierp_laravel/CLAUDE.md` (« Layering », « Single points of passage »). ⚠️ Ce que le web d'AgriERP porte et que logialvia n'a pas à copier tel quel : tout ce qui est propre à la Ferme École (filières, données semées, textes). Chaque module serveur se construit d'après le DOCUMENT de logialvia, pas d'après les données d'AgriERP.

**D-SRV-2 — Schéma partagé.** Une base serveur (MariaDB/MySQL en production, SQLite en test) et une base Drift locale ont le MÊME schéma pour les tables synchronisables : mêmes noms de colonnes, mêmes types, mêmes contraintes. Colonnes de synchronisation communes : `id` (UUID), `device_id`, `sync_status` (`pending` · `synced` · `conflict`, utile au poste), `updated_at` (instant de SAISIE, pas d'envoi). Tables propres au serveur (non synchronisées) : journal de synchronisation, curseurs par poste, demandes de synchronisation, marque de remise à zéro (`agrierp_laravel/app/Services/JournalSynchronisationService.php`). Tables propres au poste (non synchronisées) : préférences du poste, état de synchronisation. Pour CHAQUE table de logialvia, décider (et écrire) si elle est synchronisable, serveur seule ou locale, et sa règle de conflit : bloc 16, étape S0.

**D-SRV-3 — UUID à la place des entiers `autoIncrement` (changement de décision).** logialvia n'a que des clés entières : 25 colonnes `autoIncrement` dans 22 fichiers de `logialvia_app/lib/*/data/tables/` (comptage fait à la rédaction), plus des clés texte (`Factures.ref` dans `logialvia_app/lib/commercial/data/tables/facturation_mecef_tables.dart`, `GroupesTaxe.code`, 12 déclarations `primaryKey` en tout). **Migration des données existantes de logialvia — à PLANIFIER, c'est le gros morceau du changement** :
1. **Sauvegarde automatique avant migration** (`logialvia_app/lib/administration/domain/services/service_sauvegarde.dart`, `genererBaseComplete`) et refus de migrer si elle échoue.
2. **Un palier Drift unique** (`from < 27`, `versionSchema` est à 26 aujourd'hui) qui, dans UNE transaction : ajoute à chaque table synchronisable une colonne `uuid` ; la remplit d'un UUID v4 pour CHAQUE ligne existante ; reporte l'UUID dans chaque clé étrangère (table de correspondance temporaire entier → UUID) ; reconstruit la table avec l'UUID pour clé primaire (un `TableMigration` recopie TOUTES les colonnes du schéma courant : piège déjà payé au bloc 1) ; supprime la table de correspondance.
3. **Pièces numérotées** (`FV-2026-001`, `OD-2026-…`, références de la table `Factures`) : les numéros déjà attribués ne changent JAMAIS (ce sont des données comptables) ; ils deviennent une colonne de lecture, l'identifiant technique est l'UUID. Désormais les numéros sont attribués par le serveur (jamais inventés au poste, `docs/BLUEPRINT_SYNCHRONISATION_MULTIPOSTES.md` §4) : le format et la reprise de la séquence se décident avec le client (question ci-dessous).
4. **Contrôles** : nombre de lignes par table avant = après ; `PRAGMA foreign_key_check` vide ; chaque FK résout ; test avec une VRAIE ancienne base (modèles : `agrierp_flutter/test/migration_bases_reelles_test.dart`, `agrierp_flutter/test/migration_toutes_versions_test.dart`, `logialvia_app/test/core/migration_idempotente_test.dart`) ; migration idempotente (relancée, elle ne refait rien).
5. **Premier tirage après migration** : les lignes migrées sont `pending` ; le serveur reçoit l'historique par le push normal (idempotent par UUID). Alternative à écarter ou retenir avec le client : amorcer le serveur depuis la base de logialvia par un import dédié (c'est une décision de mise en service, pas de schéma).

**D-SRV-4 — Rôles.** ✅ TRANCHÉ le 08/11/2026 (DV-07) : 4 rôles, voir `16_DECISIONS_VALIDEES.md` ; le texte qui suit date d'avant la décision. logialvia : 3 rôles (admin, caissier, animalier ; `logialvia_app/lib/administration/domain/entities/role_utilisateur.dart`, « aucun rôle comptable »), AgriERP : 4 rôles (`agrierp_laravel/database/seeders/RolesAndPermissionsSeeder.php`) vérifiés à DEUX niveaux (serveur ET masquage à l'écran du poste, `agrierp_flutter/lib/core/auth/permissions_poste.dart`). Décision : **garder les 3 rôles**, la matrice rôle → droits vit au SERVEUR (une seule source), le poste la reçoit et la reflète ; tout droit « comptable » d'un bloc est rattaché à l'admin tant que le client n'arbitre pas (contradiction 7 du §0). La matrice de logialvia existe déjà en base (`logialvia_app/lib/administration/data/tables/permissions_role_table.dart`) : elle devient la graine du seeder serveur. Le serveur ne sert au poste que les tables que le compte a le droit de lire (matrice testée contre les écrans : `agrierp_flutter/test/perimetre_tirage_test.dart`).

**D-SRV-5 — Mots de passe : hashés côté serveur, jeton par poste, JAMAIS de SHA-256 + sel en base.** Le serveur hache avec l'algorithme du framework (`Hash::make`, politique `Password::defaults()` : `agrierp_laravel/app/Support/PolitiqueMotDePasse.php`). Le poste ne garde NI le mot de passe NI son hash : il garde un **jeton Sanctum nommé d'après le poste** et, pour rouvrir sa session hors ligne, un **PIN local** (4 à 6 chiffres, PBKDF2-HMAC-SHA256 ≥ 100 000 itérations, sel de 16 octets, `agrierp_flutter/lib/core/auth/verrou_local.dart`). La première connexion d'un poste exige le réseau (aucune vérification locale du mot de passe). Conséquences :
- `Utilisateurs.motDePasseHash` / `sel` de logialvia (`logialvia_app/lib/administration/data/tables/utilisateurs_table.dart`) disparaissent de la base du poste après la bascule ; un test de garde interdit toute colonne nommée `password`, `token`, `secret` dans une table du poste (`agrierp_flutter/test/parametres_generaux_test.dart`).
- **Reprise des comptes existants** : un SHA-256 + sel ne se convertit pas en hash du serveur (sens unique). Deux voies — (a) RECOMMANDÉE : l'administrateur crée les comptes au serveur avec un mot de passe TEMPORAIRE (`must_change_password`, bloc 2 « MDP-1 »), l'utilisateur le change à sa première connexion ; (b) à écarter sauf avis du client : envoyer le mot de passe saisi à la première connexion pour qu'il soit haché côté serveur (il quitte le poste une fois, sous HTTPS).
- Bloc 2 (utilisateurs, mot de passe temporaire, code de secours) et bloc 15 : renvoi, rien n'est recopié ici.

**D-SRV-6 — e-MECeF passe côté serveur** (bloc 19) : le jeton est un secret du serveur, jamais servi au poste.

**D-SRV-7 — Hébergement et exploitation.** Non traité par ce guide : hébergeur, nom de domaine, HTTPS obligatoire (le jeton et le mot de passe circulent), sauvegardes de la base serveur (`agrierp_laravel/app/Services/SauvegardeService.php`), un seul cron `php artisan schedule:run` (`agrierp_laravel/routes/console.php`), ordre de mise en production « serveur d'abord, postes ensuite » (`docs/GUIDE_DEPLOIEMENT.md`). À poser au client.

### 14.3 Ordre de construction du web (jalons, web d'abord puis poste)

Ordre par écran de la doctrine (§4) : **web** = migration → modèle → Action/Service → composant Livewire → vue Blade ; **poste** = table Drift → dépôt → écran → tests. Un jalon se termine par ses tests verts des deux côtés et la liste de ce qui n'est pas vérifié.

| Jalon | Contenu | Preuve de sortie |
|---|---|---|
| W0 | Décisions du client (14.2) consignées en ADR ; liste des tables de logialvia classées (synchronisable / serveur seule / locale) et règle de conflit de chacune | Document relu par le client |
| W1 | Squelette Laravel 12 dans le dépôt cible (dossier dédié), `.env` jamais versionné, `migrate:fresh --seed` fonctionnel, rôles et droits semés (D-SRV-4), journal d'audit, fuseau, `php artisan test` vert | Suite Feature verte sur base vide |
| W2 | Schéma serveur des tables d'un premier lot (référentiels : produits, clients, fournisseurs, paramètres) en UUID ; même lot en Drift ; **palier de migration UUID du poste** (D-SRV-3) | Test de migration sur vraie ancienne base ; garde « schéma identique des deux côtés » |
| W3 | Appairage : `POST /api/auth/login` à jeton nommé, `me`, déconnexion, compte désactivé, mot de passe temporaire (bloc 15) | `SyncPosteJetonTest`-équivalent vert |
| W4 | Synchronisation minimale (bloc 16) : tirage paginé + envoi idempotent sur les référentiels | Rejeu du même lot ; réponse perdue ; 401 puis reconnexion |
| W5 | Barre du haut : bouton et modale de synchronisation web ET poste (bloc 17) | Tests de libellés lus dans la vue web |
| W6 | Modules, UN à la fois, dans l'ordre du §1 : utilisateurs, stocks/produits, clients/fournisseurs, ventes/caisse, élevage (bandes, fiches, rationnement, rappels), notifications (bloc 18) | Pour chaque module : écran web, écran poste fidèle, parité exécutée sur ses calculs |
| W7 | Importation en masse (bloc 21), puis MeCeF (bloc 19) | Tests du plan de tests de ces blocs |
| W8 | Comptabilité et exercices (blocs 4, 9, 11, 13) : au poste, les gestes comptables deviennent des DEMANDES rejouées par le serveur (CP-2, CP-3, CP-4), jamais des écritures directes | Parité exécutée de la clôture et des immobilisations |
| W9 | Essai à plusieurs postes automatisé (bloc 16), build et installateur (bloc 10), mise en production serveur puis postes ; PWA si le client la confirme (bloc 20) | Essai multipostes vert sur plusieurs graines |

### 14.4 Questions à poser au client
Pile du serveur (Laravel) et hébergeur ? Nom de domaine et HTTPS ? Reprise des comptes (mots de passe temporaires) ? Amorçage du serveur depuis la base existante des postes déjà en service ? Format et reprise de la numérotation des pièces (`FV-AAAA-NNN`) attribuée par le serveur ? Qui administre le serveur et les sauvegardes ?

**Ordre de portage conseillé** : voir le §1 (révisé le 07/11/2026). **Synchronisation** : bloc 16 (Bloc 15 à 17 : appairage, envoi/réception, modale). Le reste du transversal (gardes, conventions, définition de « terminé ») se reprend avec chaque bloc.

---

## 16. Bloc 15 — Appairage web ↔ poste

### Objectif
Rattacher chaque poste Windows au serveur web de façon TRAÇABLE et RÉVOCABLE : un jeton par poste, nommé d'après le poste ; le poste ne conserve jamais le mot de passe ; l'administrateur voit les postes et peut en couper un. Ce bloc suppose le socle serveur du bloc 14 (D-SRV-5).

### Règle (résumé ; la référence complète est `docs/BLUEPRINT_SYNCHRONISATION_MULTIPOSTES.md` §2 et §8, rien n'est recopié ici)
- **Appairage = connexion.** `POST /api/auth/login {identifiant, password, device_name}` (`agrierp_laravel/app/Http/Controllers/Api/AuthController.php`). Limiteur : 5 tentatives par minute (`agrierp_laravel/routes/api.php`). Le serveur accepte le nom d'utilisateur court OU l'e-mail (la colonne est choisie selon la présence d'un « @ » : d'où l'interdiction de l'arobase dans un identifiant, bloc 2) ; un compte inactif est refusé. Réponse : `token`, `user`, `must_change_password`.
- **Un jeton par poste, nommé d'après le poste.** `device_name` = l'**identifiant du poste** (UUID), pas le nom de la machine. Se reconnecter depuis le même poste **supprime l'ancien jeton du même nom** : un seul jeton actif par poste. Durée de vie : 90 jours (`agrierp_laravel/config/sanctum.php`, `SANCTUM_EXPIRATION`). Le serveur exige que le `device_id` envoyé à la synchronisation soit le nom du jeton courant (403 sinon : `SyncController`, ticket S-T2) : c'est le jeton, et lui seul, qui dit quel poste parle.
- **Identifiant du poste** : un UUID tiré UNE fois à la première ouverture, gardé en base locale, jamais régénéré (`agrierp_flutter/lib/core/config/parametres_poste.dart`, clé `poste.identifiant`). Une constante partagée rendrait deux postes indiscernables (c'était le défaut `'poste-dev'`). Une réinstallation repart d'un NOUVEAU poste (nouvel UUID) ; l'ancien jeton se révoque depuis le web.
- **Adresse du serveur** : réglage du poste (clé `poste.adresse_serveur`), normalisée (schéma ajouté, `/` final retiré : sinon `//api/sync/pull`), modifiable dans Paramètres › Appairage ; effective au redémarrage, et le dit. Valeur de départ = l'environnement de construction (`agrierp_flutter/lib/core/config/environnement.dart`) : pour LogiALVIA, l'adresse du serveur du client.
- **Jeton au coffre, mot de passe nulle part.** Le poste garde le jeton et le profil dans `flutter_secure_storage` ; le mot de passe n'est jamais conservé ni journalisé (`agrierp_flutter/lib/core/auth/auth_service.dart`). **PIN local** (4 à 6 chiffres, PBKDF2, sel au coffre, 10 échecs = reconnexion en ligne exigée, `agrierp_flutter/lib/core/auth/verrou_local.dart`) : il ne remplace pas le mot de passe, il rouvre une session déjà ouverte, SANS réseau (`reprendreSession` fait confiance au jeton conservé, sans le revalider). Textes et durées du verrou communs au web et au poste : `docs/DOCTRINE_PORTAGE.md` § 5.6.
- **Révocation d'un poste.** L'administrateur (`manage-users`) supprime les jetons du poste : `POST /api/parametres/postes/revoquer` (`agrierp_laravel/app/Http/Controllers/Api/AdministrationEnLigneController.php`, audit `sync.appairage_revoque`) et l'onglet web `agrierp_laravel/app/Livewire/Parametres/PostesAppairage.php`. Le poste reçoit alors **401**.
- **401 / 403 → la synchronisation automatique s'ARRÊTE** (`SynchronisationAutomatique.suspendue`, `agrierp_flutter/lib/core/sync/synchronisation_automatique.dart`, ticket S-T1) jusqu'à une nouvelle connexion : une session révoquée ou un compte désactivé ne se répare pas en retentant. Les saisies `pending` RESTENT sur le poste ; « Synchroniser maintenant » reste possible et dit pourquoi. L'onglet Appairage affiche l'état du jeton (Présent / Session refusée / Absent / « — » si le coffre est illisible : jamais une affirmation) et propose « réappairer » = déconnexion propre puis écran de connexion (`agrierp_flutter/lib/features/parametres/appairage_poste.dart`, `onglet_appairage.dart`).
- **Mot de passe temporaire / compte désactivé** : le serveur répond 403 avec un motif français à tout, sauf au changement de mot de passe (`CompteActif`, `ChangementMotDePasseObligatoireApi`). Mécanisme complet (réinitialisation par l'administrateur, écran de changement forcé AVANT le PIN, jetons détruits) : **bloc 2**, MDP-1 ; sécurité générale : blueprint §8.

### Fichiers de référence (AgriERP)
Serveur : `agrierp_laravel/app/Http/Controllers/Api/AuthController.php`, `agrierp_laravel/app/Http/Middleware/CompteActif.php`, `agrierp_laravel/app/Http/Middleware/ChangementMotDePasseObligatoireApi.php`, `agrierp_laravel/app/Http/Controllers/Api/AdministrationEnLigneController.php`, `agrierp_laravel/app/Livewire/Parametres/PostesAppairage.php`, `agrierp_laravel/config/sanctum.php`, `agrierp_laravel/routes/api.php`. Poste : `agrierp_flutter/lib/core/auth/auth_service.dart`, `agrierp_flutter/lib/core/config/parametres_poste.dart`, `agrierp_flutter/lib/core/config/environnement.dart`, `agrierp_flutter/lib/core/auth/verrou_local.dart`, `agrierp_flutter/lib/features/parametres/appairage_poste.dart`, `agrierp_flutter/lib/features/parametres/onglet_appairage.dart`, `agrierp_flutter/lib/features/verrou/porte_session.dart`, `agrierp_flutter/lib/features/auth/login_screen.dart`, `agrierp_flutter/lib/core/sync/synchronisation_automatique.dart`.

### Pièges (déjà payés)
- Un identifiant de poste partagé (constante) : deux postes indiscernables, révocation impossible.
- Appeler `Hash::check` sur un mot de passe temporaire sans le refus 403 du reste de l'API : le compte contourne le changement forcé.
- Exiger un aller-retour serveur au démarrage : l'application devient inutilisable les jours de coupure. La reprise de session ne revalide pas le jeton.
- Réessayer à l'infini après un 401 : chaque tentative est un refus de plus au journal et martèle le serveur.
- Adresse du serveur sans normalisation : une panne déroutante parce que l'adresse « a l'air bonne ».
- Un appairage unique au nom de l'administrateur enverrait les saisies du caissier avec les droits de l'admin : AgriERP a REFUSÉ cette idée (D-SYNC-5, `docs/prd/synchronisation-barre-superieure.md` §9) ; le jeton est par utilisateur ET par poste, les droits sont contrôlés table par table.

### Tests à reprendre
Serveur : `agrierp_laravel/tests/Feature/SyncPosteJetonTest.php`, `agrierp_laravel/tests/Feature/SyncPullDroitsEtCompteActifTest.php`, `agrierp_laravel/tests/Feature/SupervisionSynchronisationTest.php`, `agrierp_laravel/tests/Feature/ReinitialisationMotDePasseAdminTest.php`. Poste : `agrierp_flutter/test/verrou_local_test.dart`, `agrierp_flutter/test/echec_synchronisation_test.dart`, `agrierp_flutter/test/synchronisation_automatique_test.dart` (401 → suspension), `agrierp_flutter/test/migration_bases_reelles_test.dart`. À écrire pour LogiALVIA : deux postes, deux jetons ; reconnexion = ancien jeton mort ; révocation → 401 → synchronisation suspendue puis reprise après réappairage ; compte désactivé → 403 motivé ; première connexion hors ligne → message clair.

### (a) Ce qui existe dans logialvia
Aucun appairage, aucune connexion réseau (le seul usage réseau est e-MECeF, `logialvia_app/lib/commercial/domain/services/transmission_mecef.dart`). Authentification LOCALE : `logialvia_app/lib/administration/domain/usecases/connecter_utilisateur_usecase.dart`, `logialvia_app/lib/administration/domain/services/hachage_mot_de_passe.dart` (SHA-256 + sel), `logialvia_app/lib/administration/presentation/viewmodels/auth_view_model.dart`, `logialvia_app/lib/administration/presentation/viewmodels/splash_view_model.dart`, `logialvia_app/lib/administration/data/repositories/preferences_poste_repository.dart` (table `preferences_poste`), `flutter_secure_storage` déjà dépendance. Pas de PIN, pas de jeton.

### (b) Ce qui manque
Tout : identifiant de poste, réglage d'adresse, client HTTP du serveur, jeton au coffre, PIN, onglet Appairage, état « session refusée », côté serveur login à jeton nommé et révocation. Dépendances à ajouter au pubspec de logialvia : `dio`, `uuid`, `connectivity_plus` (versions d'AgriERP : `agrierp_flutter/pubspec.yaml`) ; `http` reste réservé à e-MECeF… jusqu'à ce que le bloc 19 le retire du poste (si le client retient la recommandation « e-MECeF côté serveur »).

### (c) Comment le reporter
1. Serveur (bloc 14, W1/W3) : copier le contrôleur d'authentification et ses deux middlewares, adapter les rôles (3) ; jeton nommé, un par nom ; mots de passe temporaires (bloc 2).
2. Poste : `NEW:logialvia_app/lib/core/config/parametres_poste.dart` (UUID tiré une fois, adresse normalisée) stocké dans `preferences_poste` ; `NEW:logialvia_app/lib/core/auth/auth_service.dart` (login, jeton au coffre, reprise de session hors ligne) ; `NEW:logialvia_app/lib/core/auth/verrou_local.dart` (PBKDF2) ; le routeur (`logialvia_app/lib/core/router/app_router.dart`) traite connexion → changement forcé → PIN → application, dans cet ordre (équivalent de `PorteSession`).
3. Remplacer `ConnecterUtilisateurUseCase` : plus de vérification locale du mot de passe (D-SRV-5) ; l'ancien hash est abandonné après migration des comptes.
4. Onglet « Appairage » de Paramètres (`logialvia_app/lib/administration/presentation/screens/parametres_generaux_screen.dart`) : identifiant, adresse, état du jeton, test de connexion (`GET /api/auth/me`), réappairage.

### Questions au client
Durée de vie du jeton (90 jours) ? Un poste par utilisateur ou plusieurs utilisateurs sur un même poste (jeton par utilisateur ET par poste, comme AgriERP) ? Qui révoque (admin seul) ? Un poste neuf doit-il pouvoir être amorcé hors ligne (non : première connexion en ligne) ?

---

## 17. Bloc 16 — Synchronisation envoi / réception

### Objectif
Chaque poste travaille hors ligne sur sa base locale et se met d'accord avec le serveur : il REÇOIT d'abord, il ENVOIE ensuite, sans doublon, sans perte silencieuse, sans conflit non arbitré. **Le serveur est la vérité** ; le poste écrit un FAIT ou une DEMANDE que le serveur rejoue par le même code que l'écran web. Ce bloc est un résumé opérationnel : **la référence est `docs/BLUEPRINT_SYNCHRONISATION_MULTIPOSTES.md`** (règles, pièges, check-list), à lire en entier avant de coder.

### Règle (résumé opérationnel — renvois au blueprint)
- **Ordre : pull puis push** (blueprint §3) : sinon le serveur travaille sur des référentiels que le poste n'a pas encore reçus. `SyncEngine.synchroniser()` tire, puis envoie ; jamais deux synchronisations en même temps (la seconde reçoit la tentative en cours).
- **Pull** : `GET /api/sync/pull?since=…&page=…` ; **curseur = `server_time` rendu par le SERVEUR** (jamais l'horloge du poste), n'avance qu'à la DERNIÈRE page ; paginé (petites tables entières, historiques découpés par pièce, jamais une ligne sans sa pièce) ; ne sert que les tables que le compte peut lire (`SyncController::PERMISSIONS_DE_TIRAGE`) ; chaque page absorbée dans UNE transaction locale par des **absorbeurs stricts** (ligne incohérente REFUSÉE, jamais lissée ; une table mixte n'écrase jamais un `pending`/`conflict`).
- **Push** : `POST /api/sync/push`, un lot de tables dans l'ordre des dépendances, **toute la requête dans UNE transaction serveur** (`traiterEnvoi`, rejouée 3 fois sur interblocage) ; **idempotent par l'UUID du poste** : renvoyer ce que le serveur connaît ne fait rien (une réponse perdue après traitement est un cas normal) ; réponse table par table (acceptés, refusés avec le motif en français, `MotifsRefusPush`). Le poste marque `synced` **seulement après l'accusé** ; un refus devient `conflict` avec son motif ; jamais d'échec silencieux ; hors ligne n'est PAS une erreur. Envoi découpé en lots sous la limite du mandataire (413, S-T12).
- **Statuts locaux** : `pending` (à envoyer) · `synced` · `conflict` (refusé, relançable ou abandonnable par l'utilisateur) ; colonnes communes `id` (UUID), `device_id`, `sync_status`, `updated_at` (instant de SAISIE).
- **Règle de conflit PAR NATURE DE DONNÉE** (blueprint §4, jamais un « dernier écrivain gagne » global) :

| Donnée | Règle |
|---|---|
| Référentiels (produits, barèmes, rôles) | le serveur gagne ; un envoi du poste est ignoré et journalisé (`referentiels_ignored`) ; création au poste fusionnée par clé naturelle (`agrierp_laravel/app/Services/FusionReferentielsService.php`) |
| Fiche journalière | dernier écrivain gagne (upsert par UUID) ; les compteurs dérivés (ventes) sont augmentés par le serveur |
| Vente de caisse | jamais fusionnée : chaque vente hors ligne est un fait indépendant |
| Stock | le poste envoie un mouvement ou un comptage ; le serveur le REJOUE par son action unique (`AdjustStockAction`) |
| Comptabilité, clôtures, paie | le poste envoie une DEMANDE ; le serveur décide, numérote, écrit ; le résultat redescend au tirage |
| Numéros de pièces | jamais inventés au poste : attribués par le serveur |

- **Déclencheurs** (`agrierp_flutter/lib/core/sync/synchronisation_automatique.dart`) : à l'ouverture, au retour du réseau, toutes les 5 minutes par défaut (réglable), après un geste (agrégé sur 5 s), à la fermeture, sur demande ; réessais après échec réseau ou 5xx : 30 s, 2 min, 5 min, 15 min, 1 h ; un refus (4xx) n'est PAS réessayé ; 401/403 suspend (bloc 15).
- **Demande de synchronisation du web** (blueprint §5) : le serveur ne joint jamais un poste ; il dépose un drapeau (`DemandeSynchronisationService`, valable 60 min) que chaque poste connecté lit toutes les 30 s (`GET /api/sync/demande`) et sert une seule fois par poste.
- **Renvoi complet** (« Renvoyer vers ce poste », `ResynchronisationPostesService`) : le serveur mémorise le curseur rendu à chaque poste ; l'écran web compte ce qui reste à recevoir ; « Renvoyer » lève un drapeau qui reste levé JUSQU'À l'acquittement ; le poste repart d'un tirage COMPLET puis acquitte (`POST /api/sync/resynchronisation/acquittement`).
- **Remise à zéro** (blueprint §6) : le serveur vide les données d'activité (comptes, rôles, référentiels, audit préservés) derrière trois verrous et pose une marque `data_reset_at` ; **chaque envoi du poste porte la marque qu'il connaît, marque inconnue ⇒ 409** (des données d'avant la remise à zéro ne ressuscitent pas) ; le poste purge ses tables d'activité à son prochain tirage et compte ses saisies perdues.
- **Mise à jour / désinstallation / migrations de base locale** : blueprint §7 (même AppId = données intactes ; réconciliation de fin de migration).

### Ordre de construction MINIMAL (étapes S0 à S5)
- **S0 — Tables d'abord.** Pour chaque table de logialvia : synchronisable ou non, sa règle de conflit (tableau ci-dessus), son droit de lecture et d'écriture, sa dépendance d'envoi. Schéma serveur + Drift identiques, UUID, colonnes de synchro (bloc 14, D-SRV-2/3). Aucune ligne de moteur avant ce tableau.
- **S1 — Le moteur sur UNE table de référence** (ex. produits) : login (bloc 15), tirage paginé, absorbeur strict, envoi idempotent, accusé, statuts, curseur serveur. Tests : renvoi du même lot, réponse perdue, deux postes sur la même ligne, 401 puis reconnexion.
- **S2 — Les déclencheurs** (`SynchronisationAutomatique`) et le compteur « à envoyer » dont la liste de tables est PROUVÉE égale à celle de l'envoi (`agrierp_flutter/test/compteur_attente_test.dart`).
- **S3 — L'extension table par table**, par ordre de dépendance, chacune avec sa règle de conflit : référentiels, puis clients/fournisseurs, puis ventes et lignes (faits indépendants), puis mouvements de stock (rejoués), puis fiches d'élevage (dernier écrivain), puis les demandes (comptabilité, clôtures). Un bloc de code par table sur le modèle du contrôleur (« le contrôleur démontre chaque règle sur un sous-ensemble représentatif : étendre à une table suit le même motif »).
- **S4 — Le web fait revenir les données vers les postes** : demande de synchronisation, renvoi complet, curseur mémorisé par poste (bloc 17 pour l'écran).
- **S5 — Remise à zéro, essai à plusieurs postes, migration depuis vieilles bases, désinstallation/réinstallation.**

### Fichiers de référence (AgriERP)
Serveur : `agrierp_laravel/app/Http/Controllers/Api/SyncController.php`, `agrierp_laravel/app/Http/Controllers/Api/SupervisionSynchronisationController.php`, `agrierp_laravel/app/Services/DemandeSynchronisationService.php`, `agrierp_laravel/app/Services/ResynchronisationPostesService.php`, `agrierp_laravel/app/Services/ReinitialisationDonneesService.php`, `agrierp_laravel/app/Services/JournalSynchronisationService.php`, `agrierp_laravel/app/Services/FusionReferentielsService.php`, `agrierp_laravel/app/Services/CoherenceSynchronisationService.php`, `agrierp_laravel/app/Support/OrdreDesVerrous.php`, `agrierp_laravel/routes/api.php`. Poste : `agrierp_flutter/lib/core/sync/sync_engine.dart`, `agrierp_flutter/lib/core/sync/synchronisation_automatique.dart`, `agrierp_flutter/lib/core/sync/perimetre_tirage.dart`, `agrierp_flutter/lib/core/sync/fusion_referentiels.dart`, `agrierp_flutter/lib/core/database/app_database.dart`. Documentation : `docs/BLUEPRINT_SYNCHRONISATION_MULTIPOSTES.md`, `agrierp_laravel/CLAUDE.md` (« Offline sync »), `agrierp_flutter/CLAUDE.md` (« Sync Engine », « Essai à plusieurs postes »).

### Pièges (déjà payés — liste complète : blueprint §10)
Curseur lu à l'heure murale du serveur au lieu de l'UTC ; compteur incrémenté sans verrou (deux ventes comptées une) ; colonne ajoutée par un palier mais absente de la copie de table d'une migration ; **une table d'envoi oubliée dans la liste « à envoyer » : elle ne part jamais, sans erreur** ; marquer `synced` à l'envoi au lieu de l'accusé ; un référentiel du poste mis à jour en bloc qui fait perdre une bascule non acquittée ; un envoi plus gros que la limite du mandataire (413) sur une journée indivisible ; verrous pris dans un ordre qui varie (le stock d'abord, toujours) ; marque de remise à zéro non portée par un envoi (le serveur ne peut alors pas refuser les données d'avant la remise).

### Tests à reprendre
Serveur : `agrierp_laravel/tests/Feature/SyncEssaiMultipostesTest.php`, `agrierp_laravel/tests/Feature/ResynchronisationPostesTest.php`, `agrierp_laravel/tests/Feature/ReinitialisationCompleteTest.php`, `agrierp_laravel/tests/Feature/SyncPosteAbsentTest.php`, `agrierp_laravel/tests/Feature/SyncTiragePagineTest.php`, `agrierp_laravel/tests/Feature/SyncCurseurFuseauTest.php`, `agrierp_laravel/tests/Feature/SyncFusionReferentielsTest.php`, `agrierp_laravel/tests/Feature/SyncVenteHorsLigneTest.php`, `agrierp_laravel/tests/Feature/SyncMouvementsStockTest.php`. Poste : `agrierp_flutter/test/essai_multipostes_test.dart` (cinq postes réels, coupures aléatoires : requête perdue, réponse perdue après traitement, délai, 500, 413, puis réseau parfait jusqu'à ce que plus rien ne soit `pending` ; lancé par `agrierp_flutter/outils/essai_multipostes.sh`, il écrit sur le serveur et se SAUTE sans `AGRIERP_ESSAI_URL`), `agrierp_flutter/test/sync_engine_test.dart`, `agrierp_flutter/test/synchronisation_automatique_test.dart`, `agrierp_flutter/test/resynchronisation_serveur_test.dart`, `agrierp_flutter/test/demande_synchronisation_test.dart`, `agrierp_flutter/test/perimetre_tirage_test.dart`, `agrierp_flutter/test/compteur_attente_test.dart`, `agrierp_flutter/test/migration_bases_reelles_test.dart`. Les invariants de l'essai (trésorerie, stock, dettes égaux partout) se choisissent pour LogiALVIA avec ses règles de B6.

### (a) Ce qui existe dans logialvia
Rien : aucune synchronisation de données. Les briques voisines utiles : sauvegarde/restauration (`logialvia_app/lib/administration/domain/services/service_sauvegarde.dart`, `service_restauration.dart`), événements de domaine (`logialvia_app/lib/core/events/domain_event.dart`, `VenteValideeEvent`), tables Drift par module, `Resultat<T>` (`logialvia_app/lib/core/resultat/resultat.dart`).

### (b) Ce qui manque
Tout le moteur côté poste et côté serveur, les colonnes de synchro, les UUID (bloc 14), le client réseau, l'écran de synchronisation, l'essai multipostes.

### (c) Comment le reporter
Respecter l'ordre S0 → S5. Le moteur du poste est un fichier long (`sync_engine.dart`) : ne pas le recopier d'un bloc, le relire section par section (tirer, absorber, envoyer, accuser, reprendre) et le bâtir table par table dans l'architecture de logialvia (`NEW:logialvia_app/lib/core/sync/…`, dépôts dans `data/repositories`, aucun accès réseau dans un ViewModel). Un point de passage serveur unique par règle, appelé par l'écran web et par la synchronisation (bloc 14). Le piège de compilation du bloc 8 (promotion de nullité dans une fermeture) concerne justement ce fichier.

### Questions au client
Intervalle de synchronisation automatique (5 min) ? Seuil d'« inactivité » d'un poste au web (AgriERP : 3 jours) ? Une vente en rupture de stock reçue d'un poste : accepter et signaler (recommandation d'AgriERP, D-SYNC-4) ou refuser ? Quels postes (nombre, lieux) et quelle qualité de réseau (taille des lots) ?

---

## 18. Bloc 17 — Modale de synchronisation dans la barre du haut (web ET poste)

### Objectif
Un bouton « Synchroniser » dans la barre du haut ouvre la modale « Synchronisation » : au poste l'état de CE poste (liaison, file, refus) et le geste « Synchroniser maintenant » ; au web l'état de tous les postes de la ferme et les gestes pour les faire se resynchroniser. Même bouton, même titre, mêmes libellés des deux côtés ; seul le contenu propre à chaque surface diffère. PRD de référence : `docs/prd/synchronisation-barre-superieure.md` (§1 à §10 livrés le 19/10/2026, amendé au §11 le 21/10/2026 : le web fait AUSSI revenir les données vers les postes) et `docs/prd/modal-synchronisation-reduit.md`.

### Règle
- **Bouton** : entre la recherche globale et la cloche (le sélecteur d'exercice, bloc 4, est à sa gauche) ; icône `sync` au gabarit de la cloche, badge de compteur plafonné à « 9+ ». Poste : `Key('bouton-synchroniser')`, badge `bouton-synchroniser-badge` ; il remplace la pastille non cliquable et le bouton de la barre latérale (supprimés : `sync_button.dart` n'existe plus). Web : visible pour `manage-users` seulement.
- **Poste — contenu de la modale, dans l'ordre** : liaison « En ligne » / « Hors ligne » (hors ligne n'est pas une erreur rouge) ; trois cartes `CarteKpi` : « En attente d'envoi », « Refusés par le serveur », « Dernière synchronisation réussie » (heure du serveur, « — » si jamais) ; « Dernière réception », « Dernier envoi » (« Jamais » si vide) ; résultat de la dernière tentative de la session (reçus, acceptés, refusés, TOUS les motifs, avertissements) ; « Resynchronisation demandée par le serveur » entre la lecture du drapeau et son acquittement. Pied : « Fermer », « Voir le détail » (écran Synchronisation : refus détaillés, « Remettre en file »), « Synchroniser maintenant » (désactivé pendant l'envoi, la modale se met à jour sans se fermer).
- **Badge du poste** : nombre d'enregistrements à envoyer, TOUTES tables envoyées comprises (le compteur d'origine en oubliait huit : un caissier croyait tout envoyé) ; rouge s'il existe au moins un refus, émeraude sinon, absent à 0. **Jeu d'exemple calculé à la main** (PRD §5) : 2 fiches `pending`, 1 client `pending`, 1 article `pending`, 1 vente `conflict` → badge « 5 » rouge ; carte « En attente d'envoi » = 4, « Refusés par le serveur » = 1.
- **Web — contenu** : « Postes de la ferme » ; un poste par ligne, à partir des jetons non expirés : Poste, Utilisateur, Dernier contact, Dernier envoi, Acceptés / Refusés, État, plus « Modifications du site depuis son dernier tirage : N » (détail par type) et « Dernier tirage ». Pastille, du plus grave au moins grave : « Refus à corriger » (rouge) · « Inactif depuis N jours » (jaune, plus de 3 jours) · « À jour » (émeraude) ; côté retard : « En retard de N jours », « À recevoir », « Jamais synchronisé » (N affiché « — », jamais 0). Gestes (admin) : « Demander la synchronisation de ce poste » / « Demander la synchronisation des postes », « Renvoyer vers ce poste » / « Renvoyer vers tous les postes », « Actualiser », « Fermer ». Audit : `sync.renvoi_poste:{poste}`, `sync.renvoi_tous`.
- **Journal serveur** `journal_synchronisation` (serveur seul, non synchronisé, UUID) : une ligne par tirage et par envoi (poste = nom du jeton, sens, `nb_recus`, `nb_acceptes`, `nb_refuses`) écrite APRÈS le calcul de la réponse ; un échec du journal ne fait jamais échouer la synchronisation. Curseur de chaque poste : `poste_synchronisations` (serveur seul), mémorisé à la dernière page d'un tirage.
- **Toasts** : succès « Synchronisation terminée : N reçu(s), N envoyé(s). » ; refus « N enregistrement(s) refusé(s) — voir le détail. » ; hors ligne, avertissement « Serveur injoignable — les saisies restent sur ce poste et partiront à la prochaine synchronisation. »
- **Demande de synchronisation du web** : c'est ce bouton web qui dépose le drapeau décrit au bloc 16 ; le poste le lit (30 s) et synchronise ; « Renvoyer » force un tirage complet. Un poste au jeton expiré ne reçoit aucun drapeau (toast d'erreur) : il doit d'abord se reconnecter.
- **Piège d'affichage (web)** : la modale vit dans l'en-tête (`sticky z-30`), qui crée son propre empilement : la barre latérale la recouvrait et rognait titre et colonne « Poste ». Correctif livré : `<x-modal>` accepte `teleport` (déplacée sous `<body>`), largeur réduite (`xl`), introduction de ≈ 55 mots.

### Fichiers de référence (AgriERP)
Web : `agrierp_laravel/app/Livewire/Shared/EtatSynchronisationPostes.php`, `agrierp_laravel/resources/views/livewire/shared/etat-synchronisation-postes.blade.php`, `agrierp_laravel/resources/views/layouts/app.blade.php` (placement du composant), `agrierp_laravel/resources/views/components/modal.blade.php`, `agrierp_laravel/app/Services/JournalSynchronisationService.php`, `agrierp_laravel/app/Services/ResynchronisationPostesService.php`, `agrierp_laravel/app/Services/DemandeSynchronisationService.php`. Poste : `agrierp_flutter/lib/core/sync/modale_synchronisation.dart`, `agrierp_flutter/lib/features/sync/synchronisation_screen.dart`, `agrierp_flutter/lib/core/widgets/barre_superieure.dart` (`bouton-synchroniser`), `agrierp_flutter/lib/core/widgets/modale_agri.dart`, `agrierp_flutter/lib/core/widgets/carte_kpi.dart`, `agrierp_flutter/lib/core/widgets/toast_agri.dart`, `agrierp_flutter/lib/core/sync/sync_engine.dart` (`SyncOutcome`). PRD : `docs/prd/synchronisation-barre-superieure.md`, `docs/prd/modal-synchronisation-reduit.md`.

### Pièges
- Compteur « en attente » faux (tables omises) : prouvé par `compteur_attente_test.dart`.
- Dernière synchronisation = horloge du poste : elle doit être celle du serveur (`server_time`).
- Un bouton web qui ferait semblant d'envoyer : la modale web ne synchronise rien elle-même, elle demande et renvoie.
- Modale rognée par la barre latérale (voir ci-dessus) ; modale du poste ouverte sous la barre latérale (`agrierp_flutter/test/modale_au_dessus_barre_laterale_test.dart`).
- « Dernier tirage » inconnu affiché 0 au lieu de « — ».

### Tests à reprendre
Web : `agrierp_laravel/tests/Feature/EtatSynchronisationPostesTest.php` (bouton visible pour l'admin seul ; jeu P1/P2/P3 ; journal d'un pull et d'un push ; échec du journal sans effet ; mutation : retirer la journalisation fait rougir), `agrierp_laravel/tests/Feature/ResynchronisationPostesTest.php`, `agrierp_laravel/tests/Feature/SupervisionSynchronisationTest.php`. Poste : `agrierp_flutter/test/synchronisation_barre_test.dart` (badge « 5 » rouge, 4 / 1 / « — », hors ligne sans rouge), `agrierp_flutter/test/modale_synchronisation_avertissement_test.dart`, `agrierp_flutter/test/resynchronisation_serveur_test.dart` (libellés du web relus), `agrierp_flutter/test/compteur_attente_test.dart`, `agrierp_flutter/test/synchronisation_screen_test.dart`.

### (a) Ce qui existe dans logialvia
La barre du haut `logialvia_app/lib/core/widgets/shell/app_top_bar.dart` (recherche, cloche des alertes, aucun bouton de synchronisation), la modale unique `logialvia_app/lib/core/widgets/app_modal.dart`, `kpi_card.dart`, `app_toast.dart`. Rien côté synchronisation.

### (b) Ce qui manque
Le bouton, la modale poste, l'écran Synchronisation (refus + « Remettre en file »), le compteur « à envoyer », et tout le web : composant de la modale, journal serveur, curseurs par poste, gestes de demande et de renvoi.

### (c) Comment le reporter
Web d'abord (doctrine) : composant Livewire de la modale + journal + curseurs, `manage-users`. Puis le poste : `NEW:logialvia_app/lib/core/sync/modale_synchronisation.dart` construite sur `AppModal`, lue par la barre du haut ; le bouton dans `app_top_bar.dart` appelle un service injecté (jamais le moteur directement dans le widget) ; libellés copiés du web et prouvés par un test qui les lit dans la vue. Le bloc 3 (boutons de fenêtre) et le bloc 4 (sélecteur d'exercice) touchent la même barre : les poser ensemble.

### Questions au client
Qui voit le bouton au web (admin seul, comme AgriERP) ? Seuil d'inactivité (3 jours) ? La modale du poste doit-elle lister les autres postes (AgriERP : non, D-SYNC-7) ?

---

## 19. Bloc 18 — Notifications, alertes de stock et rappels VMS automatiques

### Objectif
Dire précisément ce qui est AUTOMATIQUE dans AgriERP et par QUI : ce qui est planifié au serveur, ce qui est calculé au poste, ce qui se déclenche à l'ouverture. Vérifié dans le code à la rédaction (07/11/2026) ; rien n'est supposé.

### Règle — la vérité, par mécanisme

| Mécanisme | Où et quand | Qui le calcule |
|---|---|---|
| **Cloche du web** (`NotificationBell`, table `notifications`) | relue à chaque rendu Livewire de la page (⚠️ aucun `wire:poll` dans `agrierp_laravel/resources` : le commentaire du poste qui cite un `wire:poll.30s` du web n'a pas de pendant dans les vues, donc pas de rafraîchissement automatique démontré au web) ; n'affiche que les notifications visibles du rôle (`visibleTo`) ; Centre de notifications `agrierp_laravel/app/Livewire/Notifications/Index.php` | le **serveur** écrit les lignes, la cloche les lit |
| **Alertes de la cloche, quotidiennes** | `DailyElevageAlertsJob` planifié à **06:05, fuseau Africa/Porto-Novo** (`agrierp_laravel/routes/console.php`) → `AlertesElevageService::emettre()` : **stock sous seuil** (`stock_qty <= alert_threshold`, produits actifs, adressée au rôle `admin`, critique à stock ≤ 0, lien Seuils d'Alerte), **mortalité anormale** (pire jour des 7 derniers jours ≥ 5 %, rôle `animalier`), **soins planifiés** à venir ou en retard (R-SOINS-01, délai N = `rappel_soins_jours`, 3 par défaut), **échecs de reproduction** (une seule fois) | **planifié au serveur** ; une notification par objet et par jour (même `type` + même `link_url`) : relancer la tâche ne réempile rien |
| **Prophylaxie du jour** | `DailyProphylaxyReminderJob` à **06:00 Africa/Porto-Novo** : pour chaque bande vivante dont l'espèce est active, traitement du barème dû au jour de cycle (règle unique `ProtocoleDuJourService`, bloc 6) | **planifié au serveur** ; ⚠️ le push instantané (Reverb) n'est PAS câblé : la notification est persistée et se voit au prochain rafraîchissement |
| **Autonomie de provende** | `RaiseFeedAutonomyAlertAction` appelée à l'enregistrement d'une fiche (web, et fiche acceptée d'un poste à l'envoi), jamais bloquante (bloc 5) | **événementiel, au serveur** |
| **Stock négatif après synchronisation**, **vente sous délai d'attente** | `FlagNegativeStockFromSyncAction`, `FlagSaleUnderWithdrawalAction` : à la RÉCEPTION d'une vente envoyée par un poste (stock passé sous zéro ; bande sous délai d'attente) | **événementiel, au serveur** (le serveur accepte et signale, il ne refuse pas une vente de caisse hors ligne) |
| **Ouverture de l'exercice de l'année** | commande `agrierp:ouvrir-exercice` le 1er janvier 00:00 + notification | **planifié au serveur** |
| **Entretien** | purge hebdomadaire des notifications lues depuis plus de 90 jours ; rappel hebdomadaire (lundi 08:00) de télécharger la sauvegarde, adressé au rôle `admin` (pas à une personne) ; sauvegarde quotidienne 02:00 | **planifié au serveur** (un seul cron `schedule:run` en production) |
| **Fenêtre « Rappels du jour »** (web) | composant `RappelsDuJour` monté dans le layout ; ouverture décidée CÔTÉ SERVEUR (testée) : une fois par session de navigateur, rouverte à chaque connexion, « Ne plus afficher aujourd'hui » l'emporte, jamais vide | **calculée à l'ouverture** par `RappelsDuJourService` (règle R-RAPPELS-01) |
| **Cloche du poste** | `ApercuNotification` dans `agrierp_flutter/lib/core/widgets/barre_superieure.dart`, relue toutes les 30 s depuis la base LOCALE (`BarreSuperieure.rafraichissementCloche`) ; `notifications` est une **copie** du serveur : chaque tirage la remplace en entier (`SyncEngine._absorberNotifications`) ; **le poste n'émet AUCUNE notification** (aucun `insert` local hors absorbeur) ; « marquer lue » et « supprimer » EXIGENT le réseau (`POST /api/notifications/{id}/read`, `DELETE`) et ne sont PAS mis en file (hors ligne : refus avec une phrase, jamais appliqué en silence) | **émise au serveur**, **arrive au poste à la synchronisation** : hors ligne, pas de NOUVELLE notification |
| **Tableau de bord du poste, « Alertes critiques »** | `agrierp_flutter/lib/features/pilotage/tableau_de_bord_repository.dart` recalcule LOCALEMENT, hors ligne, les mêmes règles que le serveur (stock critique, 5 articles au plus ; mortalité ≥ 5 % via `AlertesElevageService::SEUIL_MORTALITE_JOUR`) | **calculé au poste** (parité avec le web) |
| **Fenêtre « Rappels du jour »** (poste) | décrite au **bloc 6**, sans la dupliquer ici : calcul LOCAL (`agrierp_flutter/lib/features/elevage/rappels_du_jour_repository.dart`), `PorteSession.surOuverture` UNE fois par session (lancement après le PIN, chaque connexion, JAMAIS un déverrouillage), « Ne plus afficher aujourd'hui » au coffre, parité PHP exécutée | **déclenchée à l'ouverture**, calculée au poste |

**Ce qui est donc automatique, en une phrase par cas.** Planifié serveur : alertes de stock, de mortalité, de soins, d'échec de reproduction (06:05), prophylaxie du jour (06:00), ouverture d'exercice, entretien. Calculé au poste : « Alertes critiques » du tableau de bord, contenu de « Rappels du jour ». Déclenché à l'ouverture : la fenêtre « Rappels du jour » (poste et web). Aucune alerte de stock n'est une notification émise par le poste : au poste, une alerte de stock se VOIT au tableau de bord (immédiat, hors ligne) et dans la cloche (après synchronisation).

### Fichiers de référence (AgriERP)
Serveur : `agrierp_laravel/routes/console.php`, `agrierp_laravel/app/Jobs/DailyElevageAlertsJob.php`, `agrierp_laravel/app/Jobs/DailyProphylaxyReminderJob.php`, `agrierp_laravel/app/Services/AlertesElevageService.php`, `agrierp_laravel/app/Services/RappelsDuJourService.php`, `agrierp_laravel/app/Services/ProtocoleDuJourService.php`, `agrierp_laravel/app/Actions/RaiseFeedAutonomyAlertAction.php`, `agrierp_laravel/app/Actions/FlagNegativeStockFromSyncAction.php`, `agrierp_laravel/app/Actions/FlagSaleUnderWithdrawalAction.php`, `agrierp_laravel/app/Livewire/Shared/NotificationBell.php`, `agrierp_laravel/app/Livewire/Notifications/Index.php`, `agrierp_laravel/app/Livewire/Shared/RappelsDuJour.php`, `agrierp_laravel/app/Models/Notification.php`. Poste : `agrierp_flutter/lib/features/notifications/notifications_repository.dart`, `agrierp_flutter/lib/features/notifications/notifications_screen.dart`, `agrierp_flutter/lib/core/widgets/barre_superieure.dart`, `agrierp_flutter/lib/features/pilotage/tableau_de_bord_repository.dart`, `agrierp_flutter/lib/features/elevage/rappels_du_jour_repository.dart`, `agrierp_flutter/lib/features/elevage/rappels_du_jour_ouverture.dart`, `agrierp_flutter/lib/features/elevage/rappels_du_jour_modale.dart`, `agrierp_flutter/lib/core/sync/sync_engine.dart` (`_absorberNotifications`). PRD : `docs/prd/popup-rappels.md`.

### Pièges (déjà payés)
- Des alertes qui n'étaient que AFFICHÉES sur leurs écrans (stock, mortalité, soins) : personne n'en était averti ; la cloche ne recevait que l'autonomie. Ticket 15.49 : tâche quotidienne.
- Aucun seuil inventé : chaque règle est celle que l'application affiche déjà (la divergence de formule de mortalité avec le cumul hebdomadaire reste un arbitrage client OUVERT).
- Colonne `type` / `severity` hors des valeurs autorisées : MySQL strict refusait l'écriture (`backup.reminder`, `error`, `warning` n'existent pas ; utiliser `system` et les gravités du référentiel).
- Fuseau : le planificateur et « aujourd'hui » à l'heure du Bénin (test `agrierp_laravel/tests/Feature/FuseauHorairesNotificationsTest.php`).
- Un « lu / supprimé » appliqué localement hors ligne ferait réapparaître la notification non lue au tirage suivant : refuser hors ligne plutôt que mentir.
- Un cron par tâche sur l'hébergement : NON, un seul cron `schedule:run` chaque minute. ⚠️ CORRECTION (relecture du 07/11/2026) : `DailyElevageAlertsJob` et `DailyProphylaxyReminderJob` sont `ShouldQueue` et `QUEUE_CONNECTION=database` : il faut AUSSI un travailleur de file (`php artisan queue:work --stop-when-empty` par cron chaque minute sur un hébergement partagé, voir `docs/GUIDE_DEPLOIEMENT.md` §5). Sans lui, les alertes ne partent jamais, sans aucune erreur.
- Reverb non câblé : ne pas promettre de notification instantanée.

### Tests à reprendre
Serveur : `agrierp_laravel/tests/Feature/AlertesClocheTest.php`, `agrierp_laravel/tests/Feature/ApiNotificationsTest.php`, `agrierp_laravel/tests/Feature/FuseauHorairesNotificationsTest.php`, `agrierp_laravel/tests/Feature/RappelsDuJourTest.php`, `agrierp_laravel/tests/Feature/AlerteAutonomieAlimentaireTest.php`, `agrierp_laravel/tests/Feature/StockNegatifTest.php`, `agrierp_laravel/tests/Feature/VenteStockNegatifRecueTest.php`. Poste : `agrierp_flutter/test/notifications_test.dart`, `agrierp_flutter/test/rappels_du_jour_test.dart`, `agrierp_flutter/test/rappels_du_jour_parite_php_test.dart`, `agrierp_flutter/test/rappels_du_jour_blade_test.dart`, `agrierp_flutter/test/barre_superieure_test.dart`.

### (a) Ce qui existe dans logialvia
Tout est CALCULÉ au poste, rien n'est persisté ni planifié : `logialvia_app/lib/pilotage/presentation/viewmodels/alertes_view_model.dart` (une seule source pour la cloche de la barre du haut ET le panneau « Alertes Critiques », articles sous seuil, rappels de prophylaxie), la cloche `_CloctheNotifications` de `logialvia_app/lib/core/widgets/shell/app_top_bar.dart`, `logialvia_app/lib/pilotage/presentation/screens/widgets/modale_stock_critique.dart`, `logialvia_app/test/pilotage/stock_critique_test.dart`, `logialvia_app/test/pilotage/tableau_bord_repository_test.dart`, `logialvia_app/lib/elevage/domain/services/rappels_prophylaxie.dart`, `logialvia_app/lib/elevage/presentation/screens/widgets/modale_prophylaxie_du_jour.dart` (une fois par processus). Seuils : colonne `threshold` des intrants et des produits vendables.

### (b) Ce qui manque
Table de notifications persistée, émission planifiée (serveur), notification par rôle, « marquer lue », Centre de notifications, mortalité et soins dans la cloche, rappel de sauvegarde, tout le planificateur serveur ; côté poste, la cloche lue depuis une copie tirée. Le reste des manques (fenêtre « Rappels du jour », droit d'élevage, « Ne plus afficher aujourd'hui ») est au bloc 6.

### (c) Comment le reporter
1. Serveur : table `notifications` (UUID, `target_role`, `type`, `severity`, `title`, `message`, `icon`, `link_url`, `is_read`) ; un service d'émission (modèle `AlertesElevageService`) qui REPREND les règles que logialvia calcule déjà dans `AlertesViewModel`/`TableauBordRepository` (jamais un seuil nouveau) ; une tâche planifiée à l'heure du Bénin ; `routes/console.php` + un seul cron.
2. Synchronisation : `notifications` est une table du serveur seul, TIRÉE et remplacée en entier au poste ; « lue/supprimée » = appel en ligne (bloc 16).
3. Poste : la cloche de `app_top_bar.dart` lit la copie locale ET garde le calcul local de `AlertesViewModel` pour le tableau de bord (hors ligne) : les deux sources doivent donner le MÊME seuil (un seul service de domaine, jamais deux formules).
4. Fenêtre « Rappels du jour » : bloc 6, rien de plus.

### Questions au client
Qui reçoit quelle alerte (stock → admin, élevage → animalier, comme AgriERP) ? Heure d'émission quotidienne (06:00 / 06:05) ? Notification instantanée (Reverb) voulue ? E-mail ou SMS en plus de la cloche ? Délai de rappel des soins (3 jours) ?

---

## 20. Bloc 19 — Module MeCeF, poste ET web

### Objectif
Décrire EXACTEMENT ce qui est livré dans AgriERP (e-MECeF en ligne par le serveur) et ce qui est À VENIR (boîtier par le poste), puis dire comment aligner le module e-MECeF déjà écrit dans logialvia, **côté serveur plutôt que côté poste**.

> ⚠️ **AVERTISSEMENTS, à lire avant tout.** (1) **AUCUN essai réel contre la DGI n'a été fait** (ni jeton ni IFU) : tout est testé contre des simulations (`Http::fake`). (2) Les adresses de l'API (`https://developper.impots.bj/sygmef-emcf/api` essai, `https://api.impots.bj/sygmef-emcf/api` production) et les noms de champs viennent d'un paquet non officiel (Banelsems/laraSgmefQR, lu, jamais une dépendance) : **aucune documentation de la DGI n'a pu être consultée**. (3) Le traitement de l'**AIB** (champ `aib` `B`/`A`/omis, montant jamais calculé par nous, règlement envoyé SANS AIB) est une lecture de ce paquet : **à confirmer** ; la DGI peut refuser un total avec AIB, son motif s'affichera tel quel. (4) Le rendu Windows réel du QR du PDF du poste n'a pas été vérifié. (5) La Déclaration de TVA ne retient que les ventes normalisées (règle M14) : une facture simple n'y figure pas — **à confirmer avec le cabinet comptable**.

### Règle — ce qui est LIVRÉ (MECEF-1, MECEF-3 ; 07/11/2026)
- **Modes** : `company_settings.mecef_mode` = `desactive` (défaut) · `emecef` (transmission par le SERVEUR, API en ligne de la DGI, sans boîtier) · `boitier` (SQUELETTE : la passerelle répond « Mode boîtier : transmission par le poste non encore disponible. » et ne transmet RIEN). Valeur NULLE = jamais réglé : `config/mecef.php` (`MECEF_ACTIF`) décide (faux = désactivé ; vrai = `simule` : `FakeMecefGateway`, développement et tests). **Lecture unique : `MecefReglage`** ; `mecef_actif` est DÉRIVÉ (tout mode sauf `desactive`). La FABRIQUE `MecefGatewayFactory::make()` choisit la passerelle à CHAQUE demande (changer de mode s'applique à la transmission suivante).
- **`EmecefGateway`** : `POST /invoice` puis `PUT /invoice/{uid}/confirm`, délai 12 s / connexion 5 s, UN SEUL essai de création ; l'`uid` est GARDÉ (une confirmation perdue se reprend par `GET /invoice/{uid}` puis la confirmation seule, jamais une nouvelle création) ; une vente normalisée n'est JAMAIS retransmise (relue sous verrou) ; aucune exception ne bloque la vente. États : `en_attente` (réseau, 401/403, 5xx, jeton ou IFU absent : à retenter), `transmise` = « Normalisée », `erreur` = « Refusée » (4xx de la DGI), `expiree`. ⚠️ Les clés stockées gardent leurs anciens noms (`transmise`, `erreur`).
- **`MecefFactureBuilder`** — LE constructeur unique (partagé avec le futur MECEF-2) : groupe de taxe d'après le taux (0 % = A, 18 % = B, tout autre taux REFUSÉ avec son motif) ; **prix ENTIERS et UNE SEULE fonction d'arrondi** (`MecefFactureBuilder::arrondi`, au plus proche, moitié vers le haut, gardée par la source : aucun autre `round(` de montant) ; remise globale répartie au plus fort reste ; ligne « Frais de livraison » (livraison facturée incluse dans le total pour les nouvelles ventes) ; écart d'arrondi absorbé par la plus grande ligne, facture REFUSÉE si l'écart dépasse le nombre de lignes ; prix unitaire = montant ÷ quantité quand la division tombe juste, sinon quantité 1 et la quantité réelle au libellé (60 caractères au plus).
- **Choix « facture simple / normalisée » à la vente** (`sales.facture_type`, UN point de passage `ChoixFactureService`, appelé par la caisse web ET l'envoi du poste) : **facture simple = JAMAIS transmise** ; **normalisée** : nom du client obligatoire, IFU facultatif (vide = client sans IFU : le champ est omis) ou 13 chiffres, taux AIB (5 % par défaut, 1 %, N/A), via la **modale** « Facture normalisée » (IFU + nom + AIB, ouverte par événement, jamais par un `@if`/`if` d'écran). Le serveur REVALIDE tout. Au poste : `ChoixFacture` (transposition, parité exécutée : 22 cas contre le vrai PHP). Une facture issue d'un devis est simple.
- **Facture normalisée verrouillée** : plus modifiable ni annulable (modèle, lignes, annulation, web ET poste, même message « Facture normalisée : corrigez-la par un avoir. ») ; toute correction passe par un **AVOIR `FA`** lié à la facture d'origine (`reference` = `mecef_uid`), transmis par le même mécanisme ; vente non normalisée : l'avoir n'est pas transmis.
- **QR sur la facture** : QR de la DGI + code MeCeF/DGI, NIM, compteurs, date et heure (PDF web : `simplesoftwareio/simple-qrcode` ; poste : `qr_flutter` à l'écran, `pw.BarcodeWidget` dans le PDF) ; sans normalisation : « Facture émise sans certification MeCeF. » et rien d'autre.
- **Formulaire de réglage e-MECeF** (onglet « Facturation normalisée (e-MECeF) » de Paramètres, web ET poste, point de passage unique `MecefReglageService`) : mode, IFU à 13 chiffres (même colonne que les Informations Légales : une seule saisie), adresse avec deux préréglages (essai par défaut, production), opérateur, jeton. **« Tester la configuration »** (`MecefConfigurationTesteur`) : contrôles locaux puis UN `GET {url}/info/status` (lecture sans effet, jamais `POST /invoice`), résultat français, jamais le jeton.
- **Jeton JWT = SECRET, chiffré, WEB SEULEMENT** : cast `encrypted`, masqué à l'écran (« •••• », « Remplacer », « Effacer »), JAMAIS servi au poste (le tirage ne sert que le mode, l'adresse, l'opérateur et le booléen `mecef_jeton_configure`), jamais journalisé ; le poste ne le saisit pas, ne l'envoie pas, ne peut pas le vider. ⚠️ La sauvegarde du serveur le contient chiffré par `APP_KEY`.
- **Poste** : tire les champs `mecef_*` des ventes et des avoirs (JAMAIS écrits par le poste) ; écran Facturation avec statuts Normalisée / En attente / Refusée / Expirée et motif ; module désactivé = comportement « registre » ; la transmission part à la synchronisation (hors ligne comprise).

### Règle — ce qui est À VENIR (MECEF-2, NON construit, faute de boîtier)
Mode `boitier` : le **boîtier Eltrade CC300** est un serveur HTTP LOCAL (`http://localhost:38917`) : le serveur hébergé ne peut pas l'atteindre, la transmission se fera **PAR LE POSTE**. Contrat déjà défini : le poste appelle `http://localhost:38917/check` puis `/bill` avec le MÊME `MecefFactureBuilder`, **vérifie que `qr_code` est rempli (le pilote répond 200 MÊME EN ÉCHEC)**, puis synchronise le résultat ; le pilote (`issotina/eltrade-cc300-driver`) n'a aucune authentification : n'écouter que `localhost`. Question ouverte d'AgriERP : le builder étant en PHP, MECEF-2 le fera soit porter en Dart avec parité exécutée, soit servir la charge par le serveur (à trancher).

### Fichiers de référence (AgriERP)
Serveur : `agrierp_laravel/config/mecef.php`, `agrierp_laravel/app/Services/Mecef/MecefGatewayFactory.php`, `agrierp_laravel/app/Services/Mecef/EmecefGateway.php`, `agrierp_laravel/app/Services/Mecef/BoitierMecefGateway.php`, `agrierp_laravel/app/Services/Mecef/FakeMecefGateway.php`, `agrierp_laravel/app/Services/Mecef/MecefFactureBuilder.php`, `agrierp_laravel/app/Services/Mecef/FacturationMecefService.php`, `agrierp_laravel/app/Services/Mecef/ChoixFactureService.php`, `agrierp_laravel/app/Services/Mecef/MecefReglage.php`, `agrierp_laravel/app/Services/Mecef/MecefReglageService.php`, `agrierp_laravel/app/Services/Mecef/MecefConfigurationTesteur.php`, `agrierp_laravel/app/Support/MecefMode.php`, `agrierp_laravel/app/Support/MecefEtat.php`, `agrierp_laravel/app/Livewire/Parametres/FacturationEmecef.php`, migrations `agrierp_laravel/database/migrations/2026_11_07_000001_add_mecef_reglage_to_company_settings.php` à `…000005_add_delivery_in_total_to_sales_table.php`. Poste : `agrierp_flutter/lib/features/ventes/choix_facture.dart`, `agrierp_flutter/lib/features/ventes/caisse_screen.dart`, `agrierp_flutter/lib/features/parametres/reglages_ferme_repository.dart`, `agrierp_flutter/lib/features/parametres/reglages_ferme_ui.dart`. Documentation : `agrierp_laravel/CLAUDE.md` (MECEF-1, MECEF-3), `agrierp_flutter/CLAUDE.md` (idem), `docs/PLAN_FINALISATION.md` (MECEF-1, MECEF-3, MECEF-2).

### Pièges (déjà payés)
- Une facture simple transmise « à l'insu » du client : une vieille vente « à facturer » ne doit pas partir à la DGI (la migration range en `simple` tout ce qui n'était pas déjà normalisé).
- Prix décimaux envoyés à une API qui attend des entiers : un seul arrondi, un écart d'arrondi absorbé de façon déterministe, jamais plusieurs `round()` dispersés.
- Création réussie + confirmation perdue = doublon fiscal si on recrée : garder l'`uid`.
- Jeton dans une file locale en clair, dans une sauvegarde lisible ou dans un journal : une fuite.
- Appeler « production » une adresse d'essai (MECEF-1 l'avait fait).
- Normaliser dans la transaction de la vente : une panne de la DGI ne doit JAMAIS bloquer ni annuler une vente.
- Le pilote du boîtier répond 200 même en échec : lire `qr_code`, pas le code HTTP.

### Tests à reprendre
Serveur : `agrierp_laravel/tests/Feature/MecefModeReglageTest.php`, `MecefEmecefGatewayTest.php` (`Http::fake` : succès, refus, 401, 5xx, expiration, réseau coupé, double clic, reprise, jeton absent, IFU invalide, modes désactivé et boîtier, charge utile, PDF), `MecefEntiersTest.php`, `MecefChoixFactureTest.php`, `MecefLivraisonTest.php`, `MecefTestConfigurationTest.php`, `FactureNormaliseeVerrouTest.php`, `AvoirMecefTest.php`, `ModuleMecefDesactiveTest.php`, `EchecMecefEnvoiAuditTest.php` (tous dans `agrierp_laravel/tests/Feature/`). Poste : `agrierp_flutter/test/mecef_emecef_poste_test.dart`, `agrierp_flutter/test/mecef_tirage_test.dart`, `agrierp_flutter/test/choix_facture_parite_php_test.dart`, `agrierp_flutter/test/caisse_choix_facture_test.dart`, `agrierp_flutter/test/clients_ifu_test.dart`, `agrierp_flutter/test/facturation_choix_test.dart`, `agrierp_flutter/test/facturation_test.dart`, `agrierp_flutter/test/reglages_ferme_poste_test.dart`, `agrierp_flutter/test/migration_toutes_versions_test.dart`.

### (a) Ce qui existe dans logialvia (relu dans `/home/user/massenon/logialvia`)
Un module MeCeF COMPLET CÔTÉ POSTE, qui transmet lui-même : `logialvia_app/lib/commercial/domain/services/transmission_mecef.dart` (`ClientMecefHttp`, paquet `http`, **UN seul `POST {url}/invoice`** avec jeton porteur, délai 20 s ; `ReponseMecef.depuisJson` qui essaie plusieurs noms de champs ; `DepotJetonMecef` dans `flutter_secure_storage`), `logialvia_app/lib/commercial/domain/entities/facture_mecef.dart` (`TypeFacture` FV/FA, `StatutFacture` : `a_transmettre` · `normalisee` · `rejetee`), `logialvia_app/lib/commercial/data/tables/facturation_mecef_tables.dart` (tables `Factures` à clé texte `ref`, `GroupesTaxe` modifiable, lettres de groupes « non figées »), `logialvia_app/lib/commercial/data/repositories/factures_mecef_repository_drift.dart`, `logialvia_app/lib/commercial/presentation/viewmodels/factures_mecef_view_model.dart` (`transmettre`), `logialvia_app/lib/commercial/presentation/screens/factures_mecef_screen.dart`, `documents_mecef.dart`, `widgets/modale_facture_vente.dart`, `widgets/onglet_pos.dart`, réglages `mecefActif` / `mecefUrl` / `mecefNim` dans `logialvia_app/lib/administration/data/tables/parametres_entreprise_table.dart` (BR-ADM-004 : activable seulement si IFU ET RCCM), test `logialvia_app/test/commercial/factures_mecef_test.dart`. Ce fichier DIT lui-même que son contrat « n'a pas été éprouvé contre le service réel ».

### (b) Ce qui manque (par rapport à AgriERP)
Étape de confirmation `PUT /invoice/{uid}/confirm` et garde de l'`uid` ; prix entiers et une seule fonction d'arrondi (logialvia envoie `prixUnitaireHt`) ; modes (`desactive` / `emecef` / `boitier`) et fabrique de passerelles ; choix facture simple / normalisée avec modale IFU + nom + AIB ; IFU du client ; verrou de la facture normalisée + avoir lié par l'`uid` ; QR sur la facture ; test de configuration ; états `en_attente` / `expiree` ; idempotence prouvée (jamais de recréation) ; échec de transmission sans effet sur la vente.

### (c) Comment l'aligner : côté SERVEUR plutôt que côté poste
1. **Pourquoi le serveur** : (a) le jeton doit être UN secret du serveur, chiffré, jamais sur les postes ni dans leurs sauvegardes ; (b) un seul `MecefFactureBuilder` en PHP (déjà éprouvé, avec ses tests) au lieu d'une réécriture Dart à tenir en parité ; (c) l'idempotence (`uid` gardé, verrou, jamais de retransmission) se garantit mieux là où l'état est unique, avec plusieurs postes ; (d) un poste hors ligne n'a de toute façon pas accès à la DGI : il émet une facture « en attente » qui part à la synchronisation. Cela suppose le web (bloc 14) et la synchronisation (bloc 16) : **avant eux, ne pas toucher au module actuel de logialvia** (il marche comme « à transmettre » et reste utilisable).
2. **Bascule** : reprendre côté serveur `MecefGatewayFactory`, `EmecefGateway`, `MecefFactureBuilder`, `ChoixFactureService`, `MecefReglageService`, `MecefConfigurationTesteur` et leurs tests ; le poste ne fait plus d'appel `http` à la DGI : il écrit son choix (type, IFU, nom, AIB), tire les champs `mecef_*`, dessine le QR. `ClientMecefHttp` et `DepotJetonMecef` sont RETIRÉS du poste (le paquet `http` redevient inutile) ; le jeton migre vers le web (saisie au serveur, jamais relue). Les factures déjà dans la table `Factures` de logialvia se migrent avec leurs statuts (`a_transmettre` → `en_attente`, `normalisee` → `transmise`, `rejetee` → `erreur`) ; un test de migration le prouve ; ne JAMAIS retransmettre une facture déjà normalisée.
3. **Mode boîtier** : seulement si le client achète un boîtier. Contrat de MECEF-2 ci-dessus ; non construit même dans AgriERP ; ne pas le promettre.
4. Les GROUPES DE TAXE : AgriERP code 0 % = A, 18 % = B et REFUSE tout autre taux ; logialvia les garde modifiables et « non figés » : trancher avec le client et la DGI, ne pas copier A/B sans confirmation.

### Questions au client (à régler avec LogiALVIA)
Compte e-MECeF existant (IFU, jeton, environnement d'essai puis production) ? Boîtier (modèle, achat prévu) ou seulement l'API en ligne ? Qui saisit le jeton (admin, au web) ? Taux de TVA autres que 0 % et 18 % ? **AIB** : taux (5 % / 1 %), qui le décide, sur quelle assiette (à confirmer avec la DGI ou le cabinet) ? Les ventes sans client identifié : facture simple par défaut ? La Déclaration de TVA doit-elle inclure les factures simples (à confirmer avec le cabinet comptable) ? Numérotation de la facture normalisée : celle du serveur, celle de la DGI ? Livraison facturée incluse au total ? Reprise des factures existantes de logialvia ?

---

## 21. Bloc 20 — PWA du poste avec travail hors connexion puis synchronisation à la reconnexion — **À CONCEVOIR**

> ⚠️⚠️ **LA FONCTION N'EXISTE PAS dans LogiAgriERP.** Le client pense que LogiAgriERP « fait une PWA qui travaille hors connexion puis se synchronise à la reconnexion » : **c'est faux, vérifié dans le code**. Ce que LogiAgriERP a est un PWA **volontairement étroit** ; le travail hors ligne, lui, est le rôle du **poste Windows Flutter**. Ce bloc dit la vérité, puis propose une conception RÉALISTE **si le client la veut quand même** pour LogiALVIA. Tout ce qui suit la section « Ce qui existe » est **À CONCEVOIR** : rien n'en est construit ni éprouvé.

### Ce qui existe VRAIMENT dans LogiAgriERP (vérifié)
Un PWA **installable**, rien de plus :
- `agrierp_laravel/public/manifest.webmanifest` : `display: standalone`, `start_url: /dashboard`, `scope: /`, icônes, trois raccourcis (dont « Enregistrer une vente » et « Fiches d'élevage ») ; servi avec le bon type MIME par `public/.htaccess` (Apache ne connaît pas l'extension : sans cela le navigateur l'ignore en silence).
- `agrierp_laravel/public/sw.js` (service worker, `VERSION = 'agrierp-v5'`) : **trois règles de sûreté** écrites en tête du fichier. (1) **Seules les requêtes `GET` sont interceptées** (`if (request.method !== 'GET') return;`) : les `POST` de Livewire vers `/livewire/update` ne sont JAMAIS touchés, ni mis en cache ni mis en file. (2) **Aucune page HTML authentifiée n'est stockée** : les navigations passent par le réseau et ne retombent sur `public/offline.html` (une page d'attente statique) qu'en cas d'échec réel. (3) **Seuls les fichiers statiques sont mis en cache** (`/build/`, `/assets/fonts/`, `/assets/icons/`, `/assets/images/` : polices, icônes, CSS et JS compilés, aucune donnée de la ferme) ; sont exclus explicitement `/livewire/`, `/api/`, `/login`, `/logout`, `/reset-password`, `/broadcasting/`, `/storage/`. Incrémenter `VERSION` à chaque déploiement qui change un fichier mis en cache (`activate` purge les anciens caches).
- `agrierp_laravel/public/offline.html` : page d'attente. `agrierp_laravel/resources/views/components/pwa-install.blade.php` : l'invitation à installer (en bas à gauche).
- **Il n'existe NI IndexedDB, NI file d'envoi, NI Background Sync, NI `/api/sync` appelé depuis le navigateur** : recherche faite dans `agrierp_laravel/resources` et `agrierp_laravel/public` (aucune occurrence de `indexedDB`, `SyncManager`, `registration.sync` ; seul `navigator.serviceWorker.register('/sw.js')` des deux layouts).
- **La position de LogiAgriERP est écrite** (`agrierp_laravel/CLAUDE.md`, section « PWA ») : « **Ce PWA ne rend PAS AgriERP utilisable hors ligne, et ce n'est pas une lacune** : le travail hors ligne est le rôle du client dédié, via `/api/sync/*`. Un cache de navigateur qui prétendrait prendre des ventes hors ligne créerait deux sources de vérité. »
- **Le garde-fou** : `agrierp_laravel/tests/Feature/PwaEtPolicesLocalesTest.php` (11 tests) : manifeste valide et complet, icônes présentes, fichiers précachés existants, `sw.js` ignore tout ce qui n'est pas `GET` et exclut `/livewire/`, fenêtre d'installation en bas à gauche, aucune police distante. ⚠️ Précision : le test garde `GET` seul et l'exclusion de `/livewire/` ; la règle « aucun HTML authentifié » est dans le code de `sw.js` mais n'est pas assertée mot pour mot par ce test.
- **Le travail hors ligne d'AgriERP, c'est le poste Windows** (`agrierp_flutter/`, Drift/SQLite, blocs 15 à 17 de ce guide). `agrierp_flutter/pubspec.yaml` ne déclare aucune cible web (« Client Windows offline-first »).

### Pourquoi LogiAgriERP a REFUSÉ le hors ligne dans le navigateur
1. **Deux sources de vérité.** Une vente prise dans un cache de navigateur et une vente du poste, avec des règles de stock, de numérotation et de conflit à tenir deux fois (DOCTRINE : « on ne redérive jamais une règle côté client »).
2. **HTML authentifié en cache.** Le cache d'un navigateur n'est pas cloisonné par utilisateur : un tableau de bord mis en cache peut réapparaître après une déconnexion.
3. **Session partagée sur un poste commun.** La caisse de la ferme est un comptoir partagé ; un navigateur y garde cookies, cache et stockage entre deux utilisateurs.
4. **Livewire** pilote toute l'application par des `POST` sérialisés qui supposent le serveur : rien d'utilisable hors ligne sans réécrire le front.
5. Le besoin hors ligne existait déjà, couvert par le client dédié.

### (a) Ce qui existe dans logialvia
Aucun PWA (application Flutter Windows) ; aucun serveur. Rien à reprendre côté logialvia.

### (b) Ce qui manque
Tout : le web (bloc 14), la synchronisation (bloc 16), puis, SI le client le confirme, l'un des deux clients hors ligne décrits ci-dessus.

### (c) Comment le reporter — CONCEPTION À CONCEVOIR pour LogiALVIA, SI le client la veut quand même

**Deux voies (à choisir, jamais les deux) :**

| | Voie 1 — PWA (navigateur) | Voie 2 — Flutter Web ou Windows + base locale |
|---|---|---|
| Stockage local | **IndexedDB** (file d'envoi + copie réduite des référentiels), jamais le cache HTTP pour des données | Drift/SQLite : sur Windows, c'est le poste actuel ; sur le web, Drift sur **SQLite WASM** (OPFS/IndexedDB) |
| Envoi différé | **Service worker + Background Sync** (`SyncManager`) ; ⚠️ Background Sync n'existe pas dans tous les navigateurs (Safari/iOS : non) → repli : synchronisation au retour au premier plan et à l'événement `online` | Moteur de synchronisation du poste (bloc 16), déclencheurs identiques |
| Interface hors ligne | À RÉÉCRIRE en JavaScript : l'écran de caisse Livewire ne marche pas sans serveur | Le MÊME code Flutter que le poste, recompilé pour le web |
| Coût | Un second client à construire et à tenir en parité (le plus cher) | Faible pour Windows (déjà fait) ; pour le web, risques propres à Flutter Web + SQLite WASM (taille, performances, stockage purgé par le navigateur) |
| Réutilisation | Le protocole de synchronisation seulement | Le protocole ET le moteur ET les écrans |

**Périmètre MINIMAL (le seul raisonnable) — saisies hors ligne :** ventes de caisse et fiches journalières d'élevage ; **pas** la comptabilité, **pas** les clôtures, **pas** l'administration (utilisateurs, rôles), **pas** la paie, **pas** les modifications de référentiels, **pas** MeCeF (la transmission part à la synchronisation, bloc 19). Lecture hors ligne : seulement des référentiels réduits (produits vendables, clients, catalogue de la caisse) tirés à la connexion.

**Même protocole que le poste, sans en inventer un second :** `GET /api/sync/pull` et `POST /api/sync/push` (bloc 16) avec le **même jeton nommé** (bloc 15, un « poste navigateur » est un poste), des **UUID générés côté client** (`crypto.randomUUID()` en Voie 1), idempotence par UUID (une vente renvoyée = succès silencieux), statuts `pending` / `synced` / `conflict` en IndexedDB, **mêmes règles de conflit par nature de donnée** (vente jamais fusionnée, fiche = dernier écrivain, stock rejoué par le serveur, numéros attribués par le serveur : un reçu hors ligne porte un numéro PROVISOIRE, jamais définitif), **mêmes motifs de refus en français**. Reconnexion → synchronisation automatique (événement `online` + minuterie + Background Sync si disponible), pull d'abord puis push, comme au bloc 16.

**Garde-fous obligatoires (sinon, ne pas le faire) :**
1. **Chiffrement au repos** des données locales (WebCrypto, clé dérivée d'un PIN/mot de passe de l'utilisateur, jamais stockée en clair) et **verrou/PIN local** à la reprise, comme le poste (`agrierp_flutter/lib/core/auth/verrou_local.dart`).
2. **Purge à la déconnexion** : IndexedDB, caches, jeton, clé effacés ; refus de se déconnecter s'il reste des saisies `pending` sans choix explicite (les envoyer d'abord, ou les perdre en le sachant).
3. **JAMAIS d'HTML authentifié en cache** (règle 2 du `sw.js` actuel, conservée) ; ne mettre en cache que du statique ; exclure `/api/`, `/livewire/` et les pages de session.
4. **Versionnage du cache** (`VERSION` incrémentée à chaque déploiement, purge à `activate`) ET **versionnage du schéma IndexedDB** avec migration ; refus d'envoyer une file écrite par une version incompatible de l'application.
5. **Résolution de conflits identique** à celle du poste (aucune règle propre au navigateur).
6. **Quota de stockage et purge par le navigateur** : demander `navigator.storage.persist()`, afficher le nombre de saisies non envoyées, ne jamais laisser croire que « c'est sauvegardé » (le navigateur peut vider le stockage d'un site peu visité : risque de PERTE de ventes non envoyées).
7. **Limite de durée hors ligne** annoncée à l'écran (au-delà : le jeton expire, 90 jours, bloc 15 ; les référentiels vieillissent).
8. **Une seule session par appareil navigateur** pour une caisse partagée (pas de multi-utilisateur sur le même profil de navigateur).

**Ce qu'on NE fait PAS hors ligne :** comptabilité et écritures manuelles, clôtures et exercices, paie, gestion des utilisateurs, modification du plan comptable ou des barèmes, réinitialisation, sauvegardes, normalisation MeCeF (e-MECeF est en ligne), toute lecture de rapports qui dépend de données non tirées.

**Effort estimé (ordre de grandeur, après le socle serveur + synchronisation du poste) :** Voie 1 : XL (> 10 jours) — client JavaScript de caisse et de fiche, file IndexedDB, Background Sync + replis, chiffrement, purge, tests multi-navigateurs ; Voie 2 sur Windows : S (c'est le poste), sur le web : L à XL (Flutter Web + SQLite WASM, à éprouver sur les navigateurs du client avant tout engagement).

**Risques :** perte de saisies si le navigateur purge le stockage ; conflits de numérotation (numéro provisoire) ; secrets en clair dans un navigateur partagé ; deux clients à garder en parité (Voie 1) ; Safari/iOS sans Background Sync ; données de la ferme sur des téléphones personnels.

### Recommandation
**Garder le poste Windows comme client hors ligne** (c'est ce qu'AgriERP fait et prouve) et le **PWA comme client « consultation + saisie simple EN LIGNE »** (installable, rapide, avec le service worker étroit d'AgriERP : fichiers statiques seulement, page d'attente hors ligne). **Ne construire le travail hors ligne dans le navigateur que sur besoin EXPLICITE du client**, après avoir répondu aux questions ci-dessous ; et si le besoin porte seulement sur « quelques ventes quand le réseau tombe », la caisse du poste Windows le couvre déjà.

### Pièges (si la voie est ouverte)
Mettre `/api/` ou `/livewire/` dans un cache ; intercepter un `POST` ; stocker un jeton en clair dans `localStorage` ; oublier de purger à la déconnexion ; compter sur Background Sync partout ; croire qu'IndexedDB est durable ; oublier le versionnage du schéma ; inventer un second protocole de synchronisation.

### Tests à reprendre / à écrire
À reprendre : `agrierp_laravel/tests/Feature/PwaEtPolicesLocalesTest.php` (à étendre, pas à affaiblir) ; pour le protocole : les tests du bloc 16 (idempotence, réponse perdue, 401, essai multipostes `agrierp_flutter/test/essai_multipostes_test.dart` dont un « poste navigateur » devient un participant de plus). **À ÉCRIRE** : vente hors ligne → reconnexion → une seule vente au serveur (même UUID renvoyé deux fois) ; stockage purgé par le navigateur simulé ; déconnexion avec `pending` ; deux onglets ; cache d'une ancienne version refusé ; aucun HTML authentifié dans les caches après déconnexion.

### Questions au client
Quels appareils sont visés (PC Windows de la caisse, tablette, téléphone) ? **Mobile ?** (si oui : Android seul ou aussi iPhone — Background Sync absent d'iOS) ? Combien de temps travaille-t-on hors connexion (heures, jours) ? Quel volume de saisies (ventes par jour, fiches par jour) ? Quelle perte est tolérable si le navigateur vide son stockage ? La caisse est-elle partagée entre plusieurs utilisateurs sur le même appareil ? Le poste Windows ne suffit-il pas ? Qui rapproche un reçu au numéro provisoire ?

---

## 22. Bloc 21 — Importation en masse par tableur xlsx (modèle à télécharger) — **À CONCEVOIR, priorité haute**

> ⚠️⚠️ **LA FONCTION N'EXISTE PAS dans LogiAgriERP.** Le client pense que LogiAgriERP « importe en masse les stocks et les autres modules par un tableur xlsx (modèle à télécharger), avec un écran dédié dans le Flutter » : **c'est faux, vérifié dans le code** (recherche : `import`, `xlsx`, `Excel`, `csv`, `ImportCsv`, `importCsv`, `rapprochement`, `ExportTableur`, `maatwebsite`, `PhpSpreadsheet`, `excel` dans `composer.json`, `pubspec.yaml`, routes, Livewire, Services). Le client dit que c'est **« très important »** : ce bloc écrit donc la CONCEPTION COMPLÈTE d'un module « Importation en masse » à construire EN PRIORITÉ (stocks d'abord). Tout ce qui suit la section « Ce qui existe VRAIMENT » est **À CONCEVOIR** : rien n'en est construit.

### Ce qui existe VRAIMENT dans LogiAgriERP (vérifié)
- **Export xlsx au poste** (et seulement là) : `ExportTableur.construire(DocumentOfficiel)` (`agrierp_flutter/lib/core/export/export_tableur.dart`, paquet `excel ^4.0.6` de `agrierp_flutter/pubspec.yaml`), branché sur l'écran Rapports & Exports (`agrierp_flutter/lib/features/rapports/rapports_exports_screen.dart`, `rapports_repository.dart`). « Ajout assumé au-delà de la maquette » ; cellules = texte tel qu'affiché ; nom d'onglet ≤ 31 caractères. C'est un EXPORT : le même paquet sait lire un xlsx, mais **aucun code ne le fait**.
- **Web : le bouton « Excel » produit un CSV**, pas un xlsx (`agrierp_laravel/app/Livewire/Rapports/RapportsExportsHub.php`, `exportReport(format: 'csv')`) ; pas d'export xlsx au web.
- **Import CSV d'un relevé bancaire, idempotent** — le SEUL import de données par fichier : `BankReconciliationService::importCsv(compte, contenu, importId)` (`agrierp_laravel/app/Services/BankReconciliationService.php`, écran `agrierp_laravel/app/Livewire/Comptabilite/RapprochementBancaire.php`, droit `manage-comptabilite`, audit `bank_statement.imported`) : séparateur `;` puis `,`, trois colonnes date / libellé / montant, lignes invalides comptées `skipped`, **un `import_id` déjà joué n'est pas rejoué** ; poste : `agrierp_flutter/lib/features/comptabilite/rapprochement_repository.dart` (`importerReleve`, UUID d'import) et `rapprochement_page.dart` (`FilePicker`, `csv`/`txt`, 2 048 ko au plus : « Le fichier relevé ne doit pas dépasser 2048 kilo-octets. »), envoi par la table `bank_statement_imports`.
- **Import d'un module depuis une SAUVEGARDE SQL du serveur** (ticket 14.58) : `ImportModuleService` (`agrierp_laravel/app/Services/ImportModuleService.php`) n'exécute JAMAIS le SQL : il l'analyse, ne garde que les `INSERT INTO` vers les tables du module choisi (liste du module, jamais déduite du fichier), valeurs liées ; web `agrierp_laravel/app/Livewire/Parametres/Sauvegardes.php`, API `POST /api/parametres/sauvegardes/importer` (le poste ne l'appelle pas : aucune occurrence dans `agrierp_flutter/lib`). Ce n'est pas un import tableur.
- **Plan SYSCOHADA** : `php artisan comptabilite:importer-plan-syscohada` (CSV du client, insertion seule, empreinte SHA-256, bloc 9).
- **Les boutons « Importer »** : absents du web (`agrierp_laravel/app/Livewire/Stocks/GestionStocks.php`, « zéro placeholder ») ; absent de Gestion des stocks au poste (`agrierp_flutter/lib/features/stocks/gestion_stocks_screen.dart`, ticket U9) ; **inerte** (désactivé, sans action) dans Soins et vaccins (`agrierp_flutter/lib/features/elevage/soins_vaccins_screen.dart`, `_boutonInerte(…, 'Importer')`).
- **Bibliothèques réellement présentes** : Dart `excel ^4.0.6`, `file_picker ^11.0.3`, `crypto`, `uuid` (`agrierp_flutter/pubspec.yaml`). PHP : **`maatwebsite/excel ^3.1` est DÉCLARÉ dans `agrierp_laravel/composer.json` (deux fois : clé en double, à nettoyer) et INSTALLÉ (`agrierp_laravel/vendor/maatwebsite/excel`, `vendor/phpoffice/phpspreadsheet`, `composer.lock`) mais n'est utilisé NULLE PART dans `agrierp_laravel/app`** (aucune occurrence de `Maatwebsite` ni de `Excel::`). ⚠️ Le commentaire de `GestionStocks.php` qui affirme qu'« aucune librairie d'import n'est même présente dans `composer.json` » est PÉRIMÉ : la bibliothèque est là, il n'y manque que le code.
- **Les « points de passage uniques »** que l'import devra réutiliser existent tous : `ProductCatalogService` (`agrierp_laravel/app/Services/ProductCatalogService.php`, `creer` pose le stock initial par `AdjustStockAction` en mouvement « Stock initial »), `CustomerCatalogService`, `SupplierCatalogService`, `SaisieEmployeAction` (`agrierp_laravel/app/Actions/SaisieEmployeAction.php`), `SaisieUtilisateurAction`, `PlanComptableService`, `SaisieBandeAction`, `FusionReferentielsService` (`agrierp_laravel/app/Services/FusionReferentielsService.php` : fusion par clé naturelle des référentiels créés au poste).

### (a) Ce qui existe dans logialvia
Aucun import ni export tableur (grep négatif sur `xlsx`/`csv` dans `logialvia_app/lib`). Pas de `excel`, ni de `file_picker`, ni de `uuid` dans `logialvia_app/pubspec.yaml` (présents : `crypto`, `flutter_secure_storage`, `pdf`/`printing`, `http`). Les pièces voisines : `DocumentPdf` (`logialvia_app/lib/core/pdf/document_pdf.dart`), sauvegarde/restauration (`logialvia_app/lib/administration/domain/services/service_sauvegarde.dart`, `service_restauration.dart`), formats de saisie (`logialvia_app/lib/core/saisie/formats_saisie.dart`). Deux familles de stock : intrants (`logialvia_app/lib/approvisionnement/data/tables/intrants_table.dart`) et produits vendables (`logialvia_app/lib/commercial/data/tables/produits_vendables_table.dart`), chacune avec un seuil ; clients (`logialvia_app/lib/commercial/data/tables/clients_table.dart`), fournisseurs (`logialvia_app/lib/approvisionnement/data/tables/fournisseurs_table.dart`), plan comptable (`logialvia_app/lib/comptabilite/data/tables/comptabilite_tables.dart`), barème de rationnement (`logialvia_app/lib/elevage/data/tables/parametres_elevage_tables.dart`).

### (b) Ce qui manque
Tout : lecteur de xlsx, fichiers modèles, écran, validation ligne par ligne, rapport d'import, journal d'import, journal d'idempotence. Et d'abord la décision de l'architecture serveur (bloc 14) : sans web, l'import écrirait directement dans les dépôts de logialvia (voir « Comment le reporter », état 1).

### (c) Comment le reporter — CONCEPTION COMPLÈTE (À CONCEVOIR)

#### 1. Principes (aucune règle métier nouvelle)
1. **Un import n'ajoute AUCUNE règle** : chaque ligne passe par le point de passage unique qui sert déjà l'écran web ET la synchronisation (`ProductCatalogService`, `CustomerCatalogService`, `SupplierCatalogService`, `SaisieEmployeAction`, `PlanComptableService`…). Les refus de l'import sont les refus de ces services, mot pour mot ; le fichier ne contourne ni droit, ni exercice clos, ni audit.
2. **Web d'abord** (doctrine, article 5 : un critère absent du web se construit d'abord sur le web) : écran web d'import (Livewire, téléversement), puis écran Flutter fidèle. L'écran Flutter reste prioritaire pour le client (hors ligne) : le jalon web est court (même lecteur de lignes et mêmes services).
3. **Création SEULE, jamais d'écrasement** (comme l'import du plan comptable : « insertion seule ») : un ré-import ne modifie ni ne renomme une fiche existante. La mise à jour en masse est une phase ultérieure, à décider avec le client.
4. **Idempotence** : voir 5.

#### 2. Écran Flutter dédié « Importation en masse » (étapes)
Entrée : Paramètres › Importation en masse (ou entrée de menu dédiée), visible selon le droit du module visé. Cinq étapes dans UNE page à étapes (composants uniques `ModaleAgri`, `CarteKpi`, `ToastAgri` ; libellés lus dans la vue web par un test) :
1. **Choisir le module** (cartes : Produits et stock initial, Clients, Fournisseurs, Employés, Plan comptable, Barème de rationnement ; Bandes en phase 3). Les modules non autorisés par le rôle sont absents (masquage) ET refusés au serveur.
2. **Télécharger le modèle .xlsx** du module (bouton « Télécharger le modèle ») : fichier versionné, voir 4.
3. **Déposer le fichier** (`FilePicker`, extension `xlsx` ; glisser-déposer facultatif). Contrôles immédiats : taille, extension, lisibilité, modèle et version reconnus (cellule/feuille de métadonnées), sinon message français (« Ce fichier n'est pas le modèle « Clients » (version 1) : téléchargez le modèle à jour. »).
4. **Aperçu avec validation ligne par ligne** : tableau paginé (25 lignes, `PaginationAgri`), une ligne = son numéro dans le fichier, ses valeurs, un état (**Valide** · **Ignorée (déjà présente)** · **Refusée** avec le motif français du service), compteurs « N lignes lues · N valides · N ignorées · N refusées », filtre « Refusées seulement ». AUCUNE écriture à cette étape. Contrôle préalable de l'exercice (voir 6) : si l'import ne peut pas s'écrire, il est refusé ICI, avant la confirmation.
5. **Confirmer → rapport d'import** : bouton « Importer N lignes » (désactivé à 0) ; progression ; résumé (créées, ignorées, refusées) ; **rapport téléchargeable** (xlsx : une ligne par ligne du fichier avec son résultat et son motif, produit par `ExportTableur`) ; « Corriger le fichier puis ré-importer » (le ré-import ne recrée rien : voir 5). Hors ligne, l'écriture réussit localement et la ligne passe `pending` : le rapport dit « créée sur ce poste, à synchroniser », puis le statut réel (acceptée / refusée par le serveur) apparaît dans la modale de synchronisation (bloc 17).

#### 3. Modules importables et colonnes (reprises des règles de validation existantes)
Légende : * obligatoire. Les règles citées sont celles des services ; les montants sont des **FCFA entiers** (le modèle impose l'entier : durcissement du FORMAT du fichier, à confirmer car le web accepte `numeric` ; les QUANTITÉS restent décimales).

| Module (priorité) | Point de passage | Colonnes du modèle | Clé de ligne / idempotence | Droit |
|---|---|---|---|---|
| **Produits et stock initial (1)** | `ProductCatalogService::creer` → `AdjustStockAction` (« Stock initial », mouvement daté du jour, sans écriture comptable) | Nom* (≤ 150) · Catégorie* (liste des catégories du catalogue) · Unité* (≤ 20) · Filière (espèce, facultatif) · Mode de prix* (`fourchette` / `quote`) · Prix min / Prix max (entiers ; exigés si fourchette, max ≥ min) · TVA % * (0 à 100) · Seuil d'alerte* (≥ 0) · Stock initial* (≥ 0) · Catégorie d'effectif (aviculture seulement) · Description | clé naturelle du serveur : nom normalisé + catégorie + unité normalisée + filière (`FusionReferentielsService`) ; un produit déjà au catalogue est **Ignoré** et son **stock initial n'est PAS ajouté** (deux déclarations du même article = le même stock physique ; l'écart se corrige par un inventaire) | `manage-stocks` |
| **Clients (2)** | `CustomerCatalogService::creer` | Nom* (≤ 150) · Téléphone (≤ 30) · E-mail · Ville · IFU (13 chiffres) | nom normalisé + téléphone normalisé (≥ 8 chiffres) ; ⚠️ SANS téléphone, le serveur ne fusionne jamais : l'idempotence repose sur l'UUID déterministe (voir 5) | `manage-ventes` (lu dans `pushCustomers`) |
| **Fournisseurs (3)** | `SupplierCatalogService::creer` | Nom* (≤ 150) · Catégorie* · Téléphone* (≤ 30) · Adresse · E-mail | nom normalisé + téléphone normalisé | `manage-achats` (lu dans `pushSuppliers`) |
| **Employés (4)** | `SaisieEmployeAction::creer` | Prénom* · Nom* (≤ 100) · Poste* (≤ 100) · Date d'embauche* · Salaire de base (≥ 0, entier) · Statut* (`actif` / `conge` / `suspendu`) | pas de fusion par le serveur : clé = nom + prénom + date d'embauche, via l'UUID déterministe (voir 5) | `manage-rh` |
| **Plan comptable : comptes complémentaires (5)** | `PlanComptableService::creer` | Code* (≤ 20, UNIQUE) · Libellé* (≤ 255) · Classe* (1 à 9) | le code (règle `unique`) : un code existant est **Ignoré** ; le plan SYSCOHADA officiel, lui, s'importe par la commande du bloc 9 | `manage-comptabilite` |
| **Barème de rationnement (6)** | le chemin de l'écran Paramètres Élevage (`agrierp_laravel/app/Livewire/Elevage/ParametresElevage.php`, `agrierp_flutter/lib/features/elevage/parametres_elevage_repository.dart`) — à relire pour son chemin d'envoi | Filière* · Catégorie / stade* (libellé EXACT du barème : la clé est l'égalité stricte du libellé normalisé, bloc 5) · Ration g/j* (≥ 0) | (filière, libellé normalisé) ; un barème existant n'est jamais réécrit | `manage-elevage` |
| **Bandes (phase 3, si pertinent)** | `SaisieBandeAction` | Code* · Espèce* · Stade · Date de mise en bande* · Effectif initial* | code de bande unique (« jamais deux bandes en cours sous le même code ») | `manage-elevage` |

- **Utilisateurs : EXCLUS de la v1.** Un fichier de comptes demanderait des mots de passe dans un tableur (fuite). `SaisieUtilisateurAction` reste le seul chemin (création unitaire, mot de passe temporaire, bloc 2). Option v2 si le client y tient : Nom, Identifiant (sans arobase), E-mail, Rôle ; mots de passe temporaires GÉNÉRÉS par le serveur, affichés UNE fois à l'écran, jamais écrits dans le rapport téléchargeable.
- **Historique de fiches journalières, ventes, écritures comptables : EXCLUS** (faits datés qui passent par des règles de cascade, de stock et de comptabilité : ce serait inventer un chemin parallèle).
- **Bandes** : n'a de sens qu'après les blocs 12 et 1 (départ par catégorie, effectif tenu par les fiches) ; sans cela, un effectif importé serait écrasé par la première fiche.
- **logialvia a DEUX familles de stock** (intrants et produits vendables) alors qu'AgriERP n'a qu'une table `products` : le modèle « Produits et stock initial » est à décliner en deux feuilles de modèles (« Produits vendables », « Intrants ») ou une colonne « Type » ; à décider avec le client (question ci-dessous). Les colonnes ci-dessus sont celles d'AgriERP ; pour logialvia, partir des colonnes de ses propres tables et de B6, jamais de ce tableau seul.

#### 4. Fichier modèle versionné
- **Un fichier .xlsx par module**, nommé et versionné (`Modele_Produits_v1.xlsx`), contenant : une feuille **« Instructions »** (nom et version du modèle, date, rôle de chaque colonne, formats, exemples de lignes remplies, limites, avertissement « ne renommez pas les en-têtes ») ; une feuille **« Données »** (en-têtes figés, obligatoires marqués d'un `*`, **vide** : les lignes d'exemple vivent dans « Instructions » pour qu'aucune ne soit importée par erreur) ; des **listes déroulantes de validation** (catégories, statuts, mode de prix, classe) alimentées par une feuille « Listes » ; une feuille de **métadonnées** (modèle, version, empreinte) lue par l'import.
- **Qui fabrique le modèle** : au serveur par `PhpSpreadsheet` (déjà installé, il sait écrire des listes déroulantes et protéger les en-têtes), puis **le fichier est versionné comme actif** (`NEW:logialvia_app/assets/modeles/…`) et téléchargeable aussi au web. ⚠️ **À vérifier** : le paquet Dart `excel` sait écrire et lire un classeur, mais je n'ai pas établi qu'il écrit des validations de données (listes déroulantes) ; si non, le poste ne FABRIQUE pas le modèle (il distribue le fichier produit au serveur), et à défaut une feuille « Listes » + un contrôle strict à l'aperçu remplace la liste déroulante.
- **Garde d'intégrité** : l'empreinte SHA-256 du modèle en constante et un test (même principe que l'empreinte du plan comptable, bloc 9) ; un fichier d'une autre version est REFUSÉ avec son motif ; le changement d'un modèle augmente sa version.
- **Formats** : montants FCFA ENTIERS (refus d'un décimal : « Montant invalide à la ligne N : un nombre entier de FCFA est attendu. ») ; quantités décimales (virgule ou point normalisés, espaces et espaces insécables de milliers retirés avant lecture, documenté dans « Instructions ») ; dates `JJ/MM/AAAA` (cellule date ou texte) ; téléphones : texte (le zéro initial ne se perd pas) ; encodage : un xlsx est Unicode natif, aucun problème d'accents ; un CSV de repli (UTF-8 avec BOM, séparateur `;` puis `,`, comme `importCsv`) est possible plus tard, jamais en v1.
- **Taille maximale** : à fixer ; proposition 5 000 lignes et 5 Mo par fichier (précédent : le relevé bancaire, 2 048 ko), avec un message dédié ; lecture par morceaux hors du fil d'interface (gros fichier sans gel de l'écran).

#### 5. Idempotence : ré-import sans doublon
Trois filets, du plus sûr au plus fin :
1. **Le serveur** : fusion par clé naturelle (`FusionReferentielsService`) pour produits, clients (avec téléphone), fournisseurs ; code unique pour le plan comptable. Un doublon est rendu « acquitté », sans écriture.
2. **UUID DÉTERMINISTE** (UUID v5, espace de noms propre à l'import) dérivé de `module + clé de ligne normalisée` : relire le même fichier produit les MÊMES identifiants, et un identifiant déjà connu est acquitté sans rejeu (c'est ce qui rend idempotents les clients sans téléphone et les employés, que le serveur ne fusionne pas). ⚠️ Deux lignes distinctes de même clé dans UN fichier = doublon interne, REFUSÉ à l'aperçu (« Ligne N : doublon de la ligne M »).
3. **Le journal d'import** : empreinte SHA-256 du fichier + module + version ; un fichier identique déjà importé affiche « Ce fichier a déjà été importé le … par … » (avertissement, pas un refus : on peut vouloir ré-importer les lignes refusées après correction).

#### 6. Transaction : ligne par ligne (choix justifié)
**Validation INTÉGRALE avant toute écriture (aperçu) ; écriture LIGNE PAR LIGNE, une transaction par ligne (celle du service), les refusées exclues et listées ; jamais de demi-ligne.** Justification : (a) les services existants sont chacun une transaction (stock initial inclus) ; (b) la synchronisation accuse déjà ligne par ligne (acceptées / refusées avec motif), un « tout ou rien » ne s'y représenterait pas ; (c) un fichier d'initialisation de plusieurs centaines de lignes ne doit pas être bloqué par une faute de frappe : les refusées se corrigent et se ré-importent SANS doublon (5) ; (d) le rapport dit exactement ce qui est entré. Option : une case « Tout ou rien : ne rien importer s'il reste une ligne refusée » (désactivée par défaut) ; à proposer au client, pas à imposer. **Exercice clos (lecture seule)** : le stock initial est daté du jour (heure du Bénin) et `AdjustStockAction` refuse tout mouvement dans un exercice clos (`refuserSiExerciceClos`) : l'aperçu vérifie qu'un exercice OUVERT contient le jour et, sinon, refuse tout l'import produits avec le motif du service (R4) ; l'import de clients, fournisseurs, employés ne touche aucun exercice.

#### 7. Transport poste → serveur (décision justifiée)
**Décision : le poste importe par ses dépôts habituels et envoie les lignes validées par la SYNCHRONISATION ordinaire (faits `pending` à UUID), PAS par un endpoint d'import dédié en ligne.** Justification : (a) l'import doit marcher HORS LIGNE comme tout le poste ; (b) l'idempotence par UUID, les accusés, les motifs de refus en français, le droit par table, l'audit et la fusion par clé naturelle EXISTENT déjà dans `POST /api/sync/push` ; (c) aucune nouvelle surface d'API à sécuriser ; (d) un endpoint en ligne serait une SECONDE porte d'écriture à tenir en parité. Limites assumées : un gros fichier fait un gros lot (le moteur découpe sous la limite du mandataire, bloc 16) ; le résultat serveur (acceptée / refusée) n'est connu qu'à la synchronisation. **Côté web** : l'écran d'import web appelle directement les MÊMES services, sans passer par la synchronisation.

#### 8. Droits, audit, journal d'import
- **Droits** : celui du module (`manage-stocks`, `manage-ventes`, `manage-achats`, `manage-rh`, `manage-comptabilite`, `manage-elevage`), vérifié au serveur ET masqué à l'écran ; l'import est un geste d'administration : proposer en plus un droit `import-donnees` seulement si le client le demande (sinon, rien de nouveau).
- **Audit** : chaque création garde son audit (`product.created`…) ; ajouter UNE ligne `import.masse` par fichier (module, version du modèle, compteurs, jamais le contenu) via `AuditLog::record`.
- **Journal d'import** : table propre (UUID, module, version, nom et empreinte du fichier, auteur, date à l'heure du Bénin, lignes lues / créées / ignorées / refusées) ; au serveur pour le web ; au poste, journal local non synchronisé ou synchronisé (à décider) + rapport téléchargeable ; le rapport n'est JAMAIS un moyen de relire des données sensibles.

#### 9. Bibliothèques
Poste : le paquet `excel` déjà utilisé pour l'export (lecture : classeur, feuilles, cellules typées), `file_picker`, `crypto`, `uuid` (v5 déterministe) ; **pour logialvia, ces dépendances sont À AJOUTER** (`excel`, `file_picker`, `uuid` ; `crypto` y est). Serveur : `phpoffice/phpspreadsheet` via `maatwebsite/excel`, **déjà installés dans AgriERP (jamais utilisés)** ; pour LogiALVIA, les ajouter au `composer.json` du nouveau serveur seulement si le client confirme le web (bloc 14) ; nettoyer le doublon de clé de `agrierp_laravel/composer.json`.

#### 10. Plan de tests
Cas à écrire (valeurs littérales, calculées à la main) pour CHAQUE module, côté serveur (services) ET poste (parité exécutée avec le vrai PHP dès que le web existe) :
- **Fichier valide** : N lignes → N créées ; stock initial = mouvement « Stock initial » égal à la colonne ; seuil et prix enregistrés ; audit présent.
- **Colonnes manquantes ou renommées** → refus du fichier entier, message français nommant la colonne ; mauvais modèle / mauvaise version → refus.
- **Doublon** : dans le fichier (refusé à l'aperçu) ; contre la base (ignoré, **stock non ajouté**) ; clients sans téléphone ré-importés (UUID v5 : pas de doublon).
- **Ligne erronée** : montant décimal, TVA 120, date impossible, code de plan existant, catégorie inconnue, statut hors liste, IFU de 12 chiffres → refusée avec le motif du SERVICE ; les autres lignes entrent.
- **Gros fichier** : 5 000 lignes (limite) → passe sans gel ; 5 001 → refus avec message ; classeur de plusieurs milliers de lignes vides.
- **Ré-import** du même fichier → zéro création, N ignorées, avertissement « déjà importé » ; ré-import après correction des refusées → seules celles-ci entrent.
- **Exercice clos** : stock initial refusé avec le motif d'exercice clos ; clients importés quand même.
- **Droits** : un caissier ne voit pas l'import de plan comptable ; un push d'import sans le droit est refusé au serveur.
- **Hors ligne** : import, puis synchronisation ; une ligne refusée au serveur devient `conflict` avec son motif.
- **Mutation** : retirer la fusion par clé, l'UUID v5 ou la validation du service doit faire rougir au moins un test.
- **Garde de lecture de sources** : l'import n'écrit QUE par les services/dépôts listés (aucun `INSERT` direct), et le modèle a son empreinte attendue.

#### 11. Effort estimé et ordre
Ordre : **stocks d'abord**, puis clients et fournisseurs, employés, plan comptable, barème ; bandes en phase 3. Ordres de grandeur (S ≤ 1 jour · M 2 à 4 · L 5 à 10), après le socle serveur, l'appairage et la synchronisation (blocs 14 à 16) : socle du module (lecteur xlsx, modèle versionné, écran à étapes, aperçu, rapport, journal, UUID v5) : **L** ; **Produits et stock initial : M** (le plus de règles) ; Clients : S ; Fournisseurs : S ; Employés : S à M ; Plan comptable : S ; Barème : S à M ; Bandes : M (après les blocs 12 et 1) ; web (écran Livewire + droits) : M. Avant ces blocs (logialvia sans web), un import « stocks » par xlsx PEUT se faire dans les dépôts locaux, avec les mêmes règles de B6, mais sans idempotence serveur : à éviter si le web est décidé.

### Fichiers de référence (AgriERP)
`agrierp_flutter/lib/core/export/export_tableur.dart`, `agrierp_flutter/lib/core/export/document_officiel.dart`, `agrierp_flutter/lib/features/comptabilite/rapprochement_repository.dart`, `agrierp_flutter/lib/features/comptabilite/rapprochement_page.dart`, `agrierp_flutter/lib/features/rapports/rapports_exports_screen.dart`, `agrierp_flutter/lib/features/stocks/produits_repository.dart`, `agrierp_laravel/app/Services/BankReconciliationService.php`, `agrierp_laravel/app/Services/ImportModuleService.php`, `agrierp_laravel/app/Services/ImporterPlanSyscohadaService.php`, `agrierp_laravel/app/Services/ProductCatalogService.php`, `agrierp_laravel/app/Services/CustomerCatalogService.php`, `agrierp_laravel/app/Services/SupplierCatalogService.php`, `agrierp_laravel/app/Services/PlanComptableService.php`, `agrierp_laravel/app/Services/FusionReferentielsService.php`, `agrierp_laravel/app/Actions/SaisieEmployeAction.php`, `agrierp_laravel/app/Actions/SaisieBandeAction.php`, `agrierp_laravel/app/Actions/AdjustStockAction.php`, `agrierp_laravel/app/Http/Controllers/Api/SyncController.php` (`pushProducts`, `PERMISSION_PAR_TABLE`), `agrierp_laravel/composer.json`.

### Pièges (déjà payés ailleurs dans AgriERP)
Un import qui exécute du SQL ou accepte une table non listée (interdit : bloc 7) ; un stock initial écrit dans `stock_qty` SANS mouvement (le grand livre l'ignore : défaut S-T12, trouvé par l'essai multipostes) ; `id` non remplissable : `create(['id'=>…])` l'ignore en silence et le serveur forge son UUID (poser l'`id` hors de `create()`) ; additionner un stock initial déjà déclaré ailleurs (il serait compté deux fois) ; un montant reformaté à l'import ; un zéro initial de téléphone perdu par la cellule numérique ; un nom d'onglet de plus de 31 caractères ; un fichier dont l'en-tête a été renommé ; confondre « ligne ignorée » (déjà là) et « ligne refusée » (erreur).

### Tests à reprendre
`agrierp_laravel/tests/Feature/RapprochementBancaireTest.php`, `agrierp_laravel/tests/Feature/SyncReleveBancaireTest.php` (idempotence par `import_id`), `agrierp_laravel/tests/Feature/ImportModuleTest.php`, `agrierp_laravel/tests/Feature/SyncFusionReferentielsTest.php` (clé naturelle), `agrierp_laravel/tests/Feature/ImportPlanSyscohadaTest.php` (insertion seule, empreinte), `agrierp_laravel/tests/Feature/ApiProduitsTest.php` (stock initial au grand livre), `agrierp_flutter/test/rapprochement_poste_test.dart`, `agrierp_flutter/test/export_comptabilite_test.dart` (export xlsx), `agrierp_flutter/test/rapports_exports_test.dart`.

### Questions au client
Quels modules importer en premier (stocks : produits vendables, intrants, ou les deux) ? D'où viennent les données (cahiers, Excel existants : quelles colonnes) ? Le stock initial se déclare-t-il à une date précise (date d'ouverture) ? Les produits déjà présents : ignorer (recommandé) ou mettre à jour ? Faut-il aussi importer des mouvements de stock ou un inventaire (règle d'inventaire du bloc 16, à part) ? Taille maximale d'un fichier ? « Tout ou rien » ou ligne par ligne ? Qui a le droit d'importer ? Rapport d'import à conserver où ? Les comptes utilisateurs en masse : confirmé non ?

---

## 23. Check-list de démarrage pour la session de l'autre projet

**Posture (07/11/2026) : LogiALVIA aura un serveur web.** La doctrine « web = maître, poste fidèle, parité exécutée » s'applique (bloc 14). Les blocs 1 à 13 se portent d'abord dans l'état « Flutter seul » seulement pour ce qui ne dépend pas du serveur ; tout module qui touche une donnée partagée attend le socle (bloc 14), l'appairage (15) et la synchronisation (16).

**À lire d'abord (dans cet ordre).**
1. `logialvia/docs/A1_MASTER_PROMPT.md`, `logialvia/docs/A2_STRICT_AVOID.md`, `logialvia/docs/B6_Regles_Metier.md`, `logialvia/docs/05_LOGIQUE_CALCUL_FORMULAIRES.md`, `logialvia/docs/K4_Retour_Experience_Bugs_Reels.md`, `logialvia/docs/F3_Module_Production_Elevage.md`.
2. Le code d'élevage : `logialvia_app/lib/elevage/domain/entities/configuration_espece.dart`, `…/domain/services/calcul_fiche_journaliere.dart`, `…/domain/usecases/enregistrer_journee_usecase.dart`, `…/data/tables/fiche_journee_table.dart`.
3. Ce guide, §0 (contradictions et décision du 07/11/2026) AVANT tout code ; poser les questions du client regroupées (liste ci-dessous).
4. Dans AgriERP, si joignable : `docs/DOCTRINE_PORTAGE.md`, `docs/BLUEPRINT_SYNCHRONISATION_MULTIPOSTES.md`, `docs/PLAN_FINALISATION.md`, `agrierp_laravel/CLAUDE.md`, `agrierp_flutter/CLAUDE.md`, `agrierp_laravel/app/Services/EffectifParCategorieService.php` (messages exacts).

**Ordre recommandé (révisé le 07/11/2026).**
1. **Socle serveur + schéma UUID** : décisions D-SRV-1 à D-SRV-7, jalons W0 à W2 (bloc 14), plus le bloc 8 (compilation, version figée) et l'ossature du bloc 2 (utilisateurs, rôles, mots de passe temporaires, au serveur).
2. **Appairage** (bloc 15).
3. **Synchronisation** (bloc 16, étapes S0 à S5).
4. **Modale de synchronisation** (bloc 17) avec les boutons de fenêtre (bloc 3) et le sélecteur d'exercice (bloc 4), qui partagent la barre du haut.
5. **Fiches, stocks, alertes** : bandes (12), fiches par filière (1), rationnement (5), prophylaxie et rappels (6), seuils (13a), notifications et alertes (18) ; un module à la fois, web d'abord puis poste fidèle, parité exécutée.
6. **Importation en masse** (bloc 21), stocks d'abord.
7. **MeCeF** (bloc 19), côté serveur.
8. **Comptabilité et exercices** : plan comptable (9, 13b), exercices et clôture (4, 11), écriture manuelle, immobilisations (13c à 13e), export (7), aide (13f) ; au poste, les gestes comptables sont des DEMANDES rejouées par le serveur.
9. **Build et installateur** (bloc 10), essai à plusieurs postes, mise en production (serveur d'abord, postes ensuite).
10. **PWA hors connexion (bloc 20) : SEULEMENT si le client la confirme** après ses réponses.

**À copier tel quel (puis adapter noms et chemins).**
- Le jeu de cas du bloc 1 et du bloc 5 (valeurs numériques) en tests, qui deviennent aussi les entrées de la parité exécutée.
- Côté serveur : le contrôleur d'authentification et ses middlewares, le contrôleur de synchronisation (par morceaux, table par table), les services de supervision, `FusionReferentielsService`, `OrdreDesVerrous`, les services Mecef, le planificateur `routes/console.php` ; avec leurs tests.
- `build_windows.bat`, `installer/agrierp.iss` (AppId NOUVEAU), `outils/generer_icone.py` (déjà présent), `.fvmrc` (valeur lue localement).
- Les C++ de la fenêtre (`agrierp_flutter/windows/runner/win32_window.cpp`, `flutter_window.cpp`) si la voie A du bloc 3 est choisie.
- `agrierp_flutter/lib/core/export/export_tableur.dart` (structure : adapter à `DocumentPdf`).
- Les messages de refus (départ, passage, bande, transfert, exercice clos) mot pour mot, avec leur source citée.
- La liste des tests de garde de lecture de sources (`conformite_portage_test.dart`) et `php_laravel.dart` + `chemins_depot.dart` pour la parité exécutée.

**À réécrire dans l'architecture de logialvia.**
- Tout le calcul d'effectif, de rationnement, de clôture, de rappels : fonctions pures dans `domain/services`, use cases dans `domain/usecases`, dépôts Drift dans `data/repositories`, ViewModels sans règle ; la MÊME règle existe en PHP au serveur (un seul point de passage), la parité est exécutée.
- Les migrations Drift (palier explicite, nommage manuel des colonnes `_4`, test de migration), dont le palier UUID (D-SRV-3).
- La numérotation des pièces : désormais attribuée par le SERVEUR (plus de numérotation locale transactionnelle une fois la synchronisation en place).
- Les écritures « demande rejouée par le serveur » (CP-2, CP-3, CP-4, EL-1) : DEMANDES du poste rejouées par le serveur (blueprint §4), pas des écritures directes.
- L'aide (un fichier de textes) : sans génération PHP tant que le web n'a pas ses textes ; ensuite source unique + copie générée + test de parité, comme AgriERP.

**Avant de coder, obtenir du client** (liste consolidée) : **web** : pile et hébergeur, domaine, HTTPS, reprise des comptes, amorçage depuis les bases existantes, numérotation des pièces par le serveur ; glossaire et rations par filière (lapins Q1/Q2, poulets Q3/Q4) ; départ obligatoire et cascade (Q5/Q6) ; ventes par catégorie (Q7) ; pisciculture (stades, biomasse, bassin, aliment, passage, vente) ; pintades (stades, rations) ; politique de mot de passe et rôle comptable ; barre de fenêtre native ou système ; exercice civil / décalé et réouverture ; amortissement ; export Excel / CSV ; **import en masse (modules, source des données, date du stock initial, taille, droit)** ; **MeCeF (IFU, jeton, AIB, boîtier, taux de TVA)** ; **PWA hors ligne (appareils, mobile, durée, volume)** ; nom de l'installateur, données à la désinstallation ; texte de l'aide.

**Zones NON couvertes par AgriERP (ne rien inventer).** Pisciculture / Poissons-Chats (aucune règle ni donnée : seul le mécanisme générique est réutilisable) ; Pintades (aucune règle propre : volaille, mécanisme VOL-1) ; Goliaths (seul produit « Poulet goliath (sujet vif) » rangé en Jeune par nom ; aucune règle de stade) ; poulets de chair en tant que filière distincte (AgriERP a des reproducteurs et des pondeuses) ; **export xlsx au web, import en masse par tableur, PWA hors connexion** (n'existent pas : blocs 20 et 21, À CONCEVOIR) ; mode boîtier MeCeF (MECEF-2, non construit) ; fenêtre native et installateur jamais exécutés sur Windows ; MeCeF réel jamais éprouvé contre la DGI.

**Ce qui n'a PAS été vérifié en rédigeant ce guide.** Aucun code de logialvia n'a été compilé ni testé ici ; `flutter analyze` n'a pas été lancé sur le dépôt cible ; le comportement de `window_manager` contre le défaut de la barre des tâches est inconnu ; les jeux de cas ont été calculés à la main d'après les formules du code PHP lu (non exécuté) ; les tests de parité PHP cités n'ont pas été relancés ; **les blocs 15 à 21 ont été rédigés par lecture du code d'AgriERP (aucun test relancé)** : le PWA hors connexion et l'import tableur sont des conceptions, pas des constats ; le paquet Dart `excel` n'a pas été vérifié sur les listes déroulantes de validation ; les droits `manage-*` de chaque table sont ceux lus dans `SyncController`, pas rejoués.


---
**Correctif (07/11/2026) — bloc 19, boîtier.** Ne pas lire « le même `MecefFactureBuilder` » comme « le même JSON » : la LOGIQUE (arrondi entier, groupes de taxe, répartition des remises) est partagée, mais le JSON du constructeur suit l'API e-MECeF en ligne ; le pilote CC300 attend un autre schéma (`products`/`tax`/`payments`, `vt` ou `rt`, `rn` au format `NIM-TC`, `aib` en `"5%"`) : prévoir une COUCHE DE TRADUCTION (détail : `41_MECEF_EMECEF.md` §3.2). Voir aussi les écarts relevés dans `42_CONFIG_MECEF_SMTP_LOGO_FAVICON.md` (logo et favicon d'AgriERP non utilisés au web, ICO refusé par la validation `image`, etc.).
