# 31 — TESTING & QA : stratégie de tests, recette et prompts de vérification de LogiALVIA

> **USAGE**
> - **Quand l'utiliser** : (a) AVANT de coder un module, pour savoir quels tests écrire (prompt T1) ; (b) PENDANT, pour prouver qu'un test mord (prompt T2, mutation) ; (c) À LA FIN d'un ticket, pour appliquer la définition de « terminé » (section 11) ; (d) à la RECETTE client, avec les scénarios UAT (section 8) et le gabarit de rapport (section 12).
> - **Ordre** : lire les sections 1 à 3 → lancer T0 (mise en place de l'environnement de test) → pour chaque module `20_MODULES_*` lancer T1 puis T2 → T3 (parité web ↔ poste) → T4 (migration de bases) → T5 (essai multipostes) → UAT (section 8) → rapport (section 12).
> - **Entrées** : `30_DATABASE_ENGINEERING.md` (schéma, seeders, migration des données), `15_REGLES_METIER.md` (règles à prouver), `20_MODULES_*` (écrans), `03_DEVELOPMENT_STANDARDS.md` (qualité du code), `04_UI_UX_DESIGN_SYSTEM.md` (recette visuelle), `40`–`43` (PWA, MeCeF, SMTP, synchro), `GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md` (jeux de cas chiffrés, à lire sans le réécrire).
> - **Sorties** : tests PHP (`tests/Feature`, `tests/Browser`, `tests/Js`), tests Dart (`test/`), garde-fous, jeux de données, rapport de recette, matrice exigence → test (section 13).
> - **Règle d'or** : un test qui n'a jamais échoué ne prouve rien. Tout test de règle est accompagné de la preuve qu'il rougit quand on casse la règle (T2). Un chiffre (solde, stock, effectif) **n'est jamais vérifié en le lisant** : on recalcule indépendamment et on compare.
> - **Fichiers frères** : `01_MASTER_PROMPT.md`, `02_ARCHITECTURE_WEB_ET_STACK.md`, `03_DEVELOPMENT_STANDARDS.md`, `04_UI_UX_DESIGN_SYSTEM.md`, `15_REGLES_METIER.md`, `30_DATABASE_ENGINEERING.md`, `32_CLAUDE_CODE_SKILLS_LIBRARY.md`, `40_PWA_HORS_LIGNE.md`, `41_MECEF_EMECEF.md`, `42_CONFIG_MECEF_SMTP_LOGO_FAVICON.md`, `43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md`.

---

## Sommaire

1. Principes
2. Chemins de référence (vérifiés)
3. Pyramide de tests
4. Jeux de données
5. Commandes
6. Pièges d'environnement déjà payés
7. Critères d'acceptation types
8. UAT : scénarios de recette par rôle et par module
9. Check-list de recette visuelle (4 classes d'écran)
10. Cas particuliers des filières (pisciculture, pintades, goliaths)
11. Définition de « terminé »
12. Gabarit de rapport de recette
13. Matrice exigence → test
14. Prompts : T0 à T7
15. Questions ouvertes

---

## 1. Principes

1. **Écrire le test qui aurait attrapé le défaut.** Chaque garde-fou existant verrouille un défaut qui n'émet aucune erreur (`agrierp_flutter/CLAUDE.md` § Working rhythm).
2. **Un chiffre ne se vérifie jamais par lecture.** Soldes, stocks, effectifs, rations : recalcul indépendant dans le test (SQL ou PHP séparé de la formule testée), puis comparaison avec ce qu'affiche l'écran (`agrierp_laravel/CLAUDE.md` § Verification discipline).
3. **Jamais vert à vide.** Un test qui dépend d'un outil absent (PHP, dépôt Laravel, maquette, MariaDB, Chrome) se **saute avec sa raison**, il ne passe pas (`dart_test.yaml`, tag `integration` ; 16 tests de maquette sautés sans A8).
4. **Honnêteté du rapport.** Chaque rapport dit ce qui n'a PAS été vérifié (poste Windows réel, navigateur, MariaDB, base réelle). C'est une pratique du projet, pas une faiblesse.
5. **Le web est le maître** (doctrine, article 0) : un critère absent du web se construit d'abord sur le web, puis se teste des deux côtés.
6. **Aucune règle métier inventée dans un test.** Les valeurs attendues viennent d'un calcul à la main documenté (section 4.2) ou des sources de logialvia. Ce qui n'est pas défini est marqué « À DÉFINIR AVEC LE CLIENT » : le test correspondant est écrit `markTestIncomplete` / `skip: 'À DÉFINIR AVEC LE CLIENT : …'`, pas inventé.

## 2. Chemins de référence (vérifiés par `ls`)

| Sujet | Chemin |
|---|---|
| Tests Laravel (272 fichiers Feature) | `/home/user/agrierp/agrierp_laravel/tests/Feature/` ; `tests/Browser/` (Dusk, 8 parcours + `console/`, `screenshots/`) ; `tests/Js/` (`*.test.mjs`) ; `tests/TestCase.php`, `tests/DuskTestCase.php` |
| Garde-fou qui lit les sources PHP | `tests/Feature/AutorisationsMethodesMutantesTest.php`, `AuditToutesLesRoutesTest.php`, `AuditRbacRoutesTest.php`, `AuditLiensEtRessourcesTest.php` |
| Tests de synchronisation | `tests/Feature/Sync*Test.php`, `SyncCurseurTirageTest.php`, `SyncCurseurFuseauTest.php`, `ResynchronisationPostesTest.php`, `SupervisionSynchronisationTest.php` |
| Tests de sauvegarde | `tests/Feature/SauvegardesTest.php`, `SauvegardeCompteurEcrituresTest.php` |
| Tests de fiches d'élevage | `tests/Feature/FicheLapinsEffectifAutomatiqueTest.php`, `FichePondeusesStockTest.php`, `RationnementPorcsTest.php`, `AlerteAutonomieAlimentaireTest.php`, `FichesEspecesU12aTest.php` |
| Tests MeCeF / avoirs | `tests/Feature/AvoirMecefTest.php`, `ModuleMecefDesactiveTest.php` |
| Démo de ~5 mois d'activité | `agrierp_laravel/database/seeders/DemoDataSeeder.php` + `database/seeders/Demo/` (`DemoContexte`, `DemoTiersSeeder`, `DemoAchatsSeeder`, `DemoElevageSeeder`, `DemoVentesSeeder`, `DemoRhSeeder`, `DemoAdministrationSeeder`, `DemoComptabiliteSeeder`) ; `DemoUsersSeeder.php` |
| Tests Dart du poste (265 fichiers) | `/home/user/agrierp/agrierp_flutter/test/` ; chemins : `test/chemins_depot.dart` ; lancement du PHP réel : `test/php_laravel.dart` |
| Parités exécutées PHP ↔ Dart | `test/avoirs_parite_php_test.dart`, `bascule_exercice_parite_test.dart`, `cloture_exercice_parite_php_test.dart`, `paie_parite_php_test.dart`, `rappels_du_jour_parite_php_test.dart` (cité dans `agrierp_flutter/CLAUDE.md`) |
| Garde-fous de schéma / migration | `test/avoirs_schema_test.dart`, `corbeille_schema_test.dart`, `migration_toutes_versions_test.dart`, `migration_bases_reelles_test.dart` |
| Test de synchro réelle et essai multipostes | `test/sync_reel_test.dart` (tag `integration`), `test/essai_multipostes_test.dart`, `outils/essai_multipostes.sh`, `outils/essai_multipostes_serveur.php` |
| Outils de recette visuelle du poste | `agrierp_flutter/outils/` : `audit_fidelite.py`, `captures.py`, `audit_chrome.py`, `audit_jetons.py`, `inventaire.py`, `structure.py`, `libelles_audit.py`, `pages_orphelines.py` |
| Audit de fidélité des écrans | `/home/user/agrierp/docs/AUDIT_FIDELITE_ECRANS.md` |
| Plan et tickets | `/home/user/agrierp/docs/PLAN_FINALISATION.md`, `docs/DOCTRINE_PORTAGE.md`, `docs/COMPARAISON_METHODE_TATACORA.md` |
| Recette visuelle de logialvia | `/home/user/massenon/logialvia/docs/K2_Checklist_Recette_Visuelle.md` ; bugs réels : `K4_Retour_Experience_Bugs_Reels.md` ; exigences : `B5_NFRS_NonFunctional_Requirements.md`, `B6_Regles_Metier.md` ; dossier de tests de logialvia : `logialvia_app/test/` |
| Skills du dépôt | `/home/user/agrierp/.claude/skills/prd/SKILL.md`, `.claude/skills/plan/SKILL.md` |

## 3. Pyramide de tests

De la base (rapide, nombreuse) au sommet (lent, rare). Chaque étage a un **but unique** ; un défaut qui échappe à un étage est attrapé par le suivant.

| Étage | Outil | Ce que ça prouve | Ce que ça ne voit PAS |
|---|---|---|---|
| E1 **Garde-fous de source** | PHPUnit / `flutter_test` qui LISENT les fichiers (grep, regex, `glob`) | une convention tient partout : toute méthode Livewire qui écrit commence par `authorize()` ; aucun `increments()` ; une colonne existe des deux côtés ; un libellé web = libellé poste | le comportement à l'exécution |
| E2 **Unitaires de règle pure** | PHPUnit sans base / `flutter test` | une fonction pure (effectif, ration, TVA, arrondi) rend les valeurs calculées à la main | l'intégration, la base |
| E3 **Feature Livewire sur SQLite mémoire** | `Livewire::test()`, `RefreshDatabase`, `phpunit.xml` (`DB_CONNECTION=sqlite`, `:memory:`) | un composant, ses Actions, ses validations françaises, ses messages, ses droits (RBAC), sa persistance | tout JavaScript (Alpine, z-index, modales), MariaDB |
| E4 **Parité exécutée web ↔ poste** | test Dart qui lance le VRAI PHP (`php_laravel.dart`) sur SQLite mémoire, migrations réelles, et compare | le poste produit exactement ce que le serveur calcule/accepte/sert | l'interface |
| E5 **Tests Dart du poste** | `flutter test` (SQLite en mémoire, Drift) | dépôts Drift, absorbeur de synchro, migrations Drift, widgets | le serveur réel |
| E6 **Dusk (navigateur)** | Laravel Dusk + Chrome, `.env.dusk.local`, app servie sur `127.0.0.1:8002` | le JavaScript : modales Alpine, double instance, `$wire is not defined`, toasts qui interceptent des clics, responsive, sidebar RBAC | la charge |
| E7 **JS pur** | `tests/Js/*.test.mjs` (Node) | logique JS isolée (verrou de session, aide flottante) | l'intégration |
| E8 **Migration de bases réelles et anciennes versions** | `migration_toutes_versions_test.dart`, `migration_bases_reelles_test.dart` | une base de poste de n'importe quelle version monte jusqu'à la dernière sans perte ; clés UUID (voir `30`, §9.7) | la production serveur |
| E9 **MariaDB réel** | `agrierp_flutter/outils/essai_multipostes.sh` (MariaDB privé jetable, `utf8mb4_unicode_ci`) | collations, unicités, arrondis `decimal`, interblocages | la durée d'usage |
| E10 **Essai multipostes à coupures aléatoires** | même script : 5 postes, `PHP_CLI_SERVER_WORKERS=4`, coupures au hasard, graines rejouables | idempotence du push, absence de doublons, convergence, compteurs sous concurrence | le matériel réel |
| E11 **Recette humaine (UAT)** | sections 8–9 | le logiciel fait ce que la ferme attend | — |

Règles de la pyramide :
- Le gros des tests est en E1–E5 ; Dusk (E6) est RÉSERVÉ aux changements qui touchent Alpine, z-index ou empilement d'overlays (`agrierp_laravel/CLAUDE.md` § Tests).
- Un test E3 qui passe n'autorise JAMAIS à dire « le bouton marche » : seul E6 ou E11 le dit.
- E4 est la preuve de la doctrine : « un décalage de format (date, clé, statut) entre les deux côtés fait rougir ce test, alors que chaque moitié passe seule ».
- E9/E10 ne tournent pas à chaque commit : à chaque changement de schéma, de synchro, de compteur ou de transaction, et avant chaque livraison.

### 3.1 Garde-fous de source : les modèles à reproduire

| Garde-fou | Ce qu'il lit | Défaut qu'il verrouille |
|---|---|---|
| Autorisation des méthodes Livewire | tout `app/Livewire/**` | méthode qui écrit sans `authorize()` (rôle de lecture qui écrit) |
| Audit de toutes les routes / RBAC | `routes/*.php` + middleware | route sans droit |
| Aucun auto-incrément | `database/migrations/` | clé entière qui casse la synchro |
| Parité de schéma Laravel ↔ Drift | migrations + `app_database.dart` | colonne ajoutée d'un seul côté (`30` §11.2) |
| Libellés web = poste | Blade + Dart | texte divergent entre les deux surfaces (`test/verrou_parite_web_test.dart` lit le Blade) |
| Archivage → audit | `app/**` | un chemin d'archivage sans `AuditLog::record` (`CorbeilleArchiveParTest`) |
| Aucun secret dans Drift | `app_database.dart` | colonne `password`/`secret`/`token`/`api_key` |
| Aucun montant `real`/`float` | migrations + tables Drift | argent en virgule flottante |
| Aucun `DELETE` physique comptable | `app/**` | suppression d'une écriture ou d'une vente |

Chaque garde-fou : (1) échoue d'abord sur un échantillon cassé (T2), (2) donne un message **en français** qui nomme le fichier et la ligne, (3) a une liste d'exclusions **nominative et commentée** (jamais un motif large).

## 4. Jeux de données

### 4.1 Seeders de démonstration

- Modèle : `DemoDataSeeder` d'AgriERP. Principe fondateur : **tout passe par les vraies Actions, jamais par des insertions directes** (`AdjustStockAction`, `RecordPurchaseAccountingEntryAction`, `RecordSaleAccountingEntryAction`, …). Sinon rien ne garantit Σ débits = Σ crédits, le stock ne réconcilie pas ses mouvements, et la démonstration diverge du logiciel.
- Ordre porteur de dépendances (à reproduire pour LogiALVIA) : 1 Tiers → 2 Achats (établissent le PMP) → 3 Élevage (consomme la provende, produit les sujets vendus) → 4 Ventes → 5 RH (**seulement si décidé, Q2 de `30`**) → 6 Administration → 7 Comptabilité (arrêtée en dernier).
- Lancement : `php artisan migrate:fresh --seed && php artisan db:seed --class=DemoDataSeeder`.
- Jeu LogiALVIA : même structure `Demo/`, avec UNE ou plusieurs bandes **par filière** (poissons-chats, pintades, goliaths, + lapins, poulets, pondeuses) pour que chaque fiche, chaque ration et chaque vente ventilée soit exercée. Les produits de démonstration (alevins, pintadeaux, goliaths) portent le nom que le client emploie ; aucun tarif n'est inventé : **les prix de démonstration sont marqués « DÉMO » et jamais repris par le seeder de production**.
- Garde-fous du jeu : (a) `DemoDataSeeder` refuse de tourner si `APP_ENV=production` ; (b) un test lance le seeder sur SQLite mémoire et vérifie les invariants : Σ débit = Σ crédit par exercice, stock recalculé = stock lu, effectif du dernier jour = recalcul indépendant, aucune écriture orpheline ; (c) l'essai multipostes s'en sert pour avoir de vraies pages de tirage (`outils/essai_multipostes.sh`, étape 2).

### 4.2 Jeux calculés à la main, par règle métier (valeurs attendues)

Source : `GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md` § 2 et § 6, « calculé à la main, vérifié sur le code ». À recopier dans les tests, **avant** de brancher quoi que ce soit (TDD sur la fonction pure). Les règles de calcul y sont décrites ; elles ne sont pas redéfinies ici.

| Règle | Entrées | Sortie attendue |
|---|---|---|
| Effectif lapins, nominal | veille R=10, S=5, J=20 ; achat 3, né 4, vente 6, mort_R 1, mort_J 2, passage 5 | R=9, S=7, J=17 (total 33) ; S_avant = 12 |
| Effectif lapins, refus de passage | même jour, passage 15 | passage appliqué 12 ; S=0, J=24 ; message « Passage de stade refusé : 15 sujet(s) à faire passer, mais la catégorie source n'en compte que 12. » |
| Effectif lapins, inconnu | `vente` absente | J = inconnu (`null`), R=9 et S=7 connus |
| Départ lapins | (10, 5, 20) = 35 | valide ; avec total du jour 36 : « La somme des catégories de départ (35) ne correspond pas à l'effectif total au début du jour de départ (36). » |
| Volailles reproductrices | veille R=10, P=20, J=30 ; achat 5, éclosions 8, vente_R 1, vente_J 4, mort_J 2, mort_P 1, p=6 | R=9, J=35, P=21 (total 65) ; avec p=30 : appliqué 27, P=0, J=56 |
| Pondeuses (4 stades) | veille PP=100, PC=50, PL=30, PO=200 ; éclosions 20, achat 10, vente_PO 5, vente_PL 2, mort_PP 3, mort_PC 1, mort_PO 4, p1=40, p2=10, p3=5 | PP=77, PC=79, PL=43, PO=196 (total 395) |
| Plancher | mort > effectif | 0, jamais négatif (BR-ELV-001) |
| Rationnement pondeuses | effectifs 77/79/43/196 ; rations 30/60/80/110 | 2 310 / 4 740 / 3 440 / 21 560 g ; total 32 050 g = 32,05 kg |
| Rationnement reproducteurs | R=9, J=35, P=21 ; 130/80/30 | 1 170 / 2 800 / 630 g ; total 4 600 g = 4,6 kg |
| Rationnement, catégorie inconnue | lapins sans départ | total `null`, pas 0 |
| Clé de ration | « Poussin ponte (0 à 2 mois) » | clé `poussin_ponte` ; « Poussin » ne s'y confond jamais |

**Jeux à ÉCRIRE pour LogiALVIA** (valeurs à calculer à la main par l'agent, relues par un humain, avec la règle citée ; aucune valeur inventée) :

| Règle | Source de la règle | Statut |
|---|---|---|
| Fiche journalière d'une filière avec les catégories 30/60/110 (Alevin/Juvénile/Mature, Poussins/Pintadau/Mature, Poussins/Goliathau/Mature) : effectifs, mortalité, dons, ventes sur la catégorie commercialisée, achats/naissances sur la catégorie jeune | `configuration_espece.dart` + Doc 05 §1 de logialvia + GUIDE § 2 | À écrire : la règle générique existe, les chiffres sont à calculer |
| Alerte de maturité goliaths (2 800 g ET/OU 120 jours) | `configuration_espece.dart` (`poidsMaturiteGrammes`, `ageMaturiteJours`) | **La combinaison (ET ou OU) n'est pas tranchée dans mes sources : À DÉFINIR AVEC LE CLIENT** |
| Autonomie alimentaire | GUIDE § 6 : alerte rouge en rupture, sous 3 jours ou sans produit de provende | seuil 3 j : à confirmer pour LogiALVIA |
| Vente avec avance, créance, avoir | `docs/B6_Regles_Metier.md` de logialvia ; Actions AgriERP | à calculer au ticket |
| Montants FCFA entiers : conversion d'un `REAL` de logialvia | règle d'arrondi inconnue | **À DÉFINIR AVEC LE CLIENT** (Q9 de `30`) |
| TVA / groupes de taxe, e-MECeF | `41_MECEF_EMECEF.md` | voir ce fichier |
| Clôture d'exercice, balance | `J1_Bascule_Cloture_Exercice.md` de logialvia | à calculer |

## 5. Commandes

```bash
# Web (Laravel) — la seule entrée qui marche : `php artisan test` SANS argument ÉCHOUE
# (phpunit.xml déclare une suite tests/Unit qui n'existe pas)
cd <web LogiALVIA> && php artisan test --testsuite=Feature
php artisan test --testsuite=Feature --filter=NomDuTest
php artisan dusk                          # parcours navigateur
php artisan dusk --filter=PosSaleTest
node --test tests/Js                      # tests JS purs (si Node ≥ 20)

# Poste (Flutter)
cd <poste LogiALVIA> && flutter analyze && flutter test
flutter test --tags integration           # exige `php artisan serve --port=8002` ; sinon SAUTÉ

# Essai multipostes contre MariaDB réel, coupures au hasard
<poste>/outils/essai_multipostes.sh                 # graine au hasard
# (voir l'en-tête du script pour fixer une graine : les coupures de chaque poste se rejouent)

# Environnement
npm run build            # manifeste Vite (sinon des tests de vues échouent)
php artisan storage:link # sinon des tests de fichiers échouent
php artisan migrate:fresh --seed
```

Rappel (CLAUDE.md racine) : sans `npm run build` ni `storage:link`, 10 tests échouent **pour des raisons d'environnement**, pas de code. Les tests du poste trouvent le web et la maquette par `test/chemins_depot.dart` (variables `AGRIERP_LARAVEL`, `AGRIERP_PROTOTYPE`) ; pour LogiALVIA, prévoir des variables jumelles (`LOGIALVIA_WEB`, `LOGIALVIA_MAQUETTE`) dans un fichier `chemins_depot.dart` équivalent. Sans la maquette, les tests qui la lisent se sautent avec leur raison.

## 6. Pièges d'environnement déjà payés

Tirés des sections « Environment traps » et « Working rhythm » des `CLAUDE.md` (Laravel l. 322–342, Flutter l. 336–344 et suivants) et des fichiers d'essai.

| Piège | Conséquence | Parade |
|---|---|---|
| Apache local en PHP 8.1 alors que le projet exige ^8.3 | le site local renvoie 500, sans rapport avec ce qu'on vient de changer | développer avec `php artisan serve --port=8002` |
| Tuer `php artisan serve` ne libère pas le port | l'enfant `php -S 127.0.0.1:8002` survit | cibler le processus enfant / le groupe de processus ; **jamais `pkill`** (consigne de cette mission) ; le script d'essai arrête le groupe proprement |
| Livewire a besoin d'un instant pour s'hydrater | une connexion scriptée trop tôt envoie des identifiants vides et reste sur `/login` sans erreur | attendre l'hydratation, puis **asserter que l'URL a vraiment changé** |
| Connexion web limitée à 5 essais / 15 min par identifiant + IP | des connexions scriptées répétées verrouillent le compte de test | réutiliser une session, ne pas boucler sur le login |
| Cliquer par libellé dans Dusk : « Créances », « Commandes » existent aussi dans la barre latérale | le clic navigue ailleurs sans erreur | exclure `aside` et `header` avant de cliquer |
| Feature tests = `Livewire::test()`, **zéro JavaScript** | double instance Alpine, `$wire is not defined`, toasts qui interceptent les clics : invisibles | un passage Dusk pour tout changement touchant Alpine, z-index ou overlays |
| `php -l` ne valide pas les directives Blade | un `.blade.php` qui « lint » peut ne pas compiler | `php artisan route:list`, rendu réel par un test E3, `view:cache` |
| Dusk utilise `migrate:fresh` | pointer `.env.dusk.local` sur la base de développement la **détruit** | base dédiée `…_dusk`, `.env.dusk.local` non versionné |
| SQLite ne borne pas `decimal` (0,871 conservé) alors que MariaDB l'arrondit à 0,87 | écarts d'un centime en contrôle de cohérence uniquement sous SQLite | montants entiers FCFA ; quantités à 2 décimales arrondies à l'écriture ; essai sur MariaDB |
| Le Flutter récent casse la compilation Windows sans qu'un test le dise (promotion de nullité d'une variable capturée) | échec au build, pas à l'analyse | `.fvmrc` fixe la version ; copier la variable dans une `final` locale avant la fermeture |
| Dart : `$` dans une chaîne générée | « interpolation » : fichier illisible à la génération | échapper `$` |
| Tests `integration` sans serveur | rouge permanent qu'on finit par ignorer | ils se marquent SAUTÉS, jamais échoués ; le script d'essai exige `AGRIERP_ESSAI_URL` (jamais contre le serveur de développement par accident) |
| Deux copies du journal de tickets (`README_SPRINT0.md`) qui divergent | six tickets non livrés cachés | comparer les empreintes avant d'ajouter, jamais « à l'œil » ; **pour LogiALVIA : un seul journal, un seul emplacement** |
| Rejeu d'une graine d'essai multipostes | les coupures de chaque poste se rejouent fidèlement, **pas** l'entrelacement des cinq postes (dépend de l'horloge) | rejouer plusieurs graines, noter le fuseau (`TZ`) |
| Aucun dépôt git dans le poste AgriERP historique | pas d'historique à consulter | le journal de tickets fait foi ; LogiALVIA a un dépôt public : commits en français |
| `app_database.g.dart` | édité à la main = écrasé au prochain `build_runner` | `dart run build_runner build` |
| Mot de passe de démonstration | un compte démo en production | `DemoUsersSeeder` refuse en production ; changer le mot de passe à la livraison |

## 7. Critères d'acceptation types

À reprendre dans chaque ticket (adapter les valeurs) :

1. **Fonctionnel** : chaque bouton persiste réellement (jamais un succès affiché sans écriture) ; chaque suppression passe par la modale d'avertissement ; chaque erreur de formulaire est en français, **sous le champ**.
2. **Règle** : la valeur attendue du jeu de la section 4.2 sort de la fonction pure ET de l'écran ; un recalcul indépendant égale l'affichage.
3. **Droits** : l'écran est inaccessible ou limité pour au moins 2 rôles ; toute méthode qui écrit commence par `authorize()` (garde-fou E1).
4. **Données** : migrations rejouables ; `migrate:fresh --seed` réussit ; aucun `increments()` ; aucune colonne `real` pour un montant ; colonnes de synchro présentes (`30` §3.4).
5. **Synchronisation** : un envoi rejoué deux fois n'écrit rien de plus (idempotence par UUID) ; une ligne `pending` ou `conflict` n'est jamais écrasée par un tirage ; une demande refusée rend sa raison, mot pour mot, au poste.
6. **Parité** : pour chaque règle portée, un test E4 exécute le PHP réel ; pour chaque libellé commun, un garde-fou lit le Blade.
7. **Visuel** : section 9, sur les largeurs 1024 / 1280 / 1440 px et, pour le web, au format téléphone.
8. **Qualité** : `flutter analyze` sans avertissement non justifié ; `php artisan test --testsuite=Feature` vert ; tout test nouveau a sa preuve de mutation (T2).
9. **Honnêteté** : le rapport liste ce qui n'est pas vérifié.

## 8. UAT : scénarios de recette par rôle et par module

Les **rôles** de LogiALVIA sont ceux de `docs/I1_Matrice_RBAC.md` (dépôt logialvia) : ne pas supposer les noms d'AgriERP (`admin`, `compta`, `caisse`, `elevage`). Un compte par rôle, créé par `RolesAndPermissionsSeeder`. Colonne « Rôle » ci-dessous : **catégorie fonctionnelle** à rattacher aux rôles réels de la matrice.

Format d'un scénario : identifiant · rôle · pré-condition · étapes · résultat attendu · preuve (capture ou valeur relevée). Les valeurs chiffrées attendues viennent de la section 4.2 ; sinon « calculer avec le client avant la recette ».

### 8.1 Transverse

| ID | Rôle | Scénario | Résultat attendu |
|---|---|---|---|
| UAT-AUTH-01 | tous | connexion avec identifiant court ou e-mail ; mauvais mot de passe 5 fois | blocage temporaire, message français ; aucun détail sur l'existence du compte |
| UAT-AUTH-02 | administrateur | réinitialiser le mot de passe d'un utilisateur | mot de passe temporaire, changement forcé à la connexion suivante, ses sessions fermées (règle MDP-1, à confirmer Q3 de `30`) |
| UAT-AUTH-03 | tous | verrou de session après inactivité | écran de verrouillage ; reprise par mot de passe ; saisie non enregistrée perdue (comportement documenté) |
| UAT-RBAC-01 | chaque rôle | parcourir chaque entrée de la barre latérale | seuls les écrans autorisés apparaissent ; une URL directe interdite rend 403 |
| UAT-SYNC-01 | poste | saisir hors ligne (fiche, vente), reconnecter | tout part une fois, rien en double, statut `synced` |
| UAT-SYNC-02 | poste + serveur | couper le réseau pendant l'envoi | à la reprise, pas de doublon ni de perte (essai E10) |
| UAT-PWA-01 | web mobile | installer l'application, couper le réseau, saisir une fiche | la saisie est gardée et partira à la reconnexion (voir `40_PWA_HORS_LIGNE.md`) |

### 8.2 Élevage (par filière)

| ID | Rôle | Scénario | Résultat attendu |
|---|---|---|---|
| UAT-ELV-01 | éleveur | ouvrir la fiche d'une filière, saisir un jour (achat, nés, vente, mortalité, dons) | l'effectif et les sous-effectifs se calculent, **aucun champ d'effectif n'est éditable** (BR-ELV-007) |
| UAT-ELV-02 | éleveur | saisir une mortalité supérieure à l'effectif | effectif plancher 0, jamais négatif |
| UAT-ELV-03 | éleveur | rouvrir un jour déjà saisi | les valeurs saisies sont intactes (colonnes `oeufs_pondus`… conservées) |
| UAT-ELV-04 | éleveur | modifier un jour passé | les jours suivants sont recalculés (cascade unique) |
| UAT-ELV-05 | éleveur | rationnement du jour d'une fiche | tableau par catégorie × ration (valeurs de 4.2 pour un cas connu) ; barème « non confirmé » signalé par sa note |
| UAT-ELV-06 | éleveur | alerte d'autonomie alimentaire | rouge en rupture / sous le seuil ; n'empêche jamais l'enregistrement |
| UAT-ELV-07 | éleveur | mettre des œufs en couveuse puis enregistrer l'éclosion | `poussins_nés ≤ œufs couvés`, statut « Éclosion Effectuée » |
| UAT-ELV-08 | éleveur | planifier un soin ; fenêtre « Rappels du jour » | rappel affiché une fois par session, aucune fenêtre vide |
| UAT-ELV-09 | gérant | vendre un animal sous délai d'attente vétérinaire | vente bloquée ou signalée, jamais silencieuse |
| UAT-ELV-10 | éleveur | pisciculture : fiche « Poissons-Chats » | libellés Alevin / Juvénile / Mature, colonne « Nés » (sans couveuse), rations 30/60/110 avec note de barème non confirmé |
| UAT-ELV-11 | éleveur | pintades : fiche | Poussins / Pintadau / Mature, « Nés (Couveuse) » |
| UAT-ELV-12 | éleveur | goliaths : fiche | Poussins / Goliathau / Mature ; alerte de maturité (règle **À DÉFINIR AVEC LE CLIENT** : combinaison poids/âge) |

### 8.3 Ventes

| ID | Rôle | Scénario | Résultat attendu |
|---|---|---|---|
| UAT-VTE-01 | caissier | vente comptant espèces | stock, trésorerie, écriture comptable, effectif de la catégorie commercialisée mis à jour ; montants entiers FCFA |
| UAT-VTE-02 | caissier | vente à crédit puis règlement partiel | créance et solde client exacts |
| UAT-VTE-03 | caissier | vente avec avance du client | imputation, reste net correct |
| UAT-VTE-04 | gérant | annuler une vente avec motif | motif obligatoire ; stock, effectif et écriture contre-passés ; jamais restaurée |
| UAT-VTE-05 | caissier | devis → facture (une seule facture par devis) | second essai refusé |
| UAT-VTE-06 | caissier | facture normalisée e-MECeF (module actif) | code, NIM, compteur, lien de vérification renseignés (voir `41`) ; module inactif : registre sans colonne MeCeF |
| UAT-VTE-07 | caissier | avoir sur une vente normalisée | avoir lié, normalisé si le module est actif |
| UAT-VTE-08 | caissier | vente d'un produit sans catégorie d'effectif | refus AVANT toute écriture, message français |

### 8.4 Stocks et achats

| ID | Rôle | Scénario | Résultat attendu |
|---|---|---|---|
| UAT-STK-01 | magasinier | achat de provende | stock + mouvement + PMP recalculé (valeur calculée à la main) |
| UAT-STK-02 | magasinier | ajustement / inventaire | mouvement tracé avec motif |
| UAT-STK-03 | gérant | seuil critique | badge « Critique » sous le seuil |
| UAT-STK-04 | comptable | règlement fournisseur, retour, remboursement | dette fournisseur exacte |
| UAT-STK-05 | magasinier | recalcul du stock à partir des mouvements | égal au stock affiché (contrôle de cohérence) |

### 8.5 Comptabilité

| ID | Rôle | Scénario | Résultat attendu |
|---|---|---|---|
| UAT-CPT-01 | comptable | journal, grand livre, balance | Σ débits = Σ crédits par exercice ; la balance égale un recalcul SQL indépendant |
| UAT-CPT-02 | comptable | saisie d'une pièce manuelle | refus si déséquilibrée ; numéro attribué sans trou ni doublon |
| UAT-CPT-03 | comptable | compte portant des écritures | code et classe immuables |
| UAT-CPT-04 | comptable | clôture d'exercice puis consultation | exercice verrouillé, écritures non modifiables, nouveaux soldes reportés (« à-nouveaux ») |
| UAT-CPT-05 | comptable | plan comptable | empreinte conforme (`30` §11.3) |
| UAT-CPT-06 | comptable | rapprochement bancaire, import d'un relevé deux fois | idempotent (identifiant d'import) |

### 8.6 RH (seulement si décidé, Q2 de `30`)

Paie, pointage, attestations : scénarios à écrire après décision ; **aucun scénario inventé**.

### 8.7 Paramètres et administration

| ID | Rôle | Scénario | Résultat attendu |
|---|---|---|---|
| UAT-PAR-01 | administrateur | enregistrer SMTP, envoyer un e-mail d'essai | mot de passe SMTP chiffré en base, jamais renvoyé à l'écran ni au poste |
| UAT-PAR-02 | administrateur | téléverser logo et favicon | visibles sur le web et sur les documents PDF ; le poste les reçoit |
| UAT-PAR-03 | administrateur | activer / désactiver un module | écrans masqués, aucune erreur ; MeCeF désactivé par défaut |
| UAT-PAR-04 | administrateur | appairer un nouveau poste | jeton créé sous le nom du poste ; visible dans l'état de synchronisation des postes |
| UAT-PAR-05 | administrateur | sauvegarde puis restauration à blanc | données et compteur d'écritures retrouvés |
| UAT-PAR-06 | administrateur | corbeille : restaurer / supprimer définitivement | écritures comptables jamais restaurables ; mot « SUPPRIMER » exigé ; journal tenu |

## 9. Check-list de recette visuelle (4 classes d'écran)

⚠️ Mes sources ne nomment pas explicitement « quatre classes d'écran ». La classification ci-dessous est **déduite de l'inventaire des 31 écrans** (`docs/03_INVENTAIRE_31_ECRANS.md` : tableaux de bord, fiches `fiche-*`, hubs à onglets, listes avec modales) et de `K2_Checklist_Recette_Visuelle.md`. **À confirmer avec `04_UI_UX_DESIGN_SYSTEM.md`** : si ce fichier définit les 4 classes autrement, il fait foi et cette section s'aligne.

Pour **chaque écran**, cocher la partie commune (9.0) puis la partie de sa classe. Largeurs : 1024, 1280 et 1440 px (poste) ; téléphone ~390 px (web/PWA).

### 9.0 Commun à tous les écrans (repris de K2)
- [ ] Structure et ordre des sections identiques à la vue maître (Blade) ; aucune section réordonnée
- [ ] Espacements, rayons, ombres, typographie : uniquement les jetons du design system (aucune valeur en dur)
- [ ] Position des boutons identique (primaire à droite, secondaire à gauche dans les modales)
- [ ] KPI : toujours un texte, jamais une carte vide
- [ ] Aucun bouton n'affiche un succès sans persistance réelle
- [ ] Toute suppression passe par la modale d'avertissement
- [ ] Erreur de formulaire en français, sous le champ
- [ ] Données issues de la base réelle (pas de valeur factice)
- [ ] RBAC vérifié pour au moins 2 rôles
- [ ] Accessibilité : étiquettes sur modales, onglets et boutons-icônes
- [ ] Navigation aller et retour fonctionne
- [ ] Les 3 boutons Réduire / Agrandir / Fermer des modales (GUIDE, bloc 3)
- [ ] Sélecteur d'exercice et bandeau d'exercice présents où attendu (GUIDE, bloc 4)
- [ ] Responsive : aucun défilement horizontal de page, gouttière de 16 px sur téléphone
- [ ] Mode sombre lisible si le design system le prévoit

### 9.1 Classe A — Tableau de bord / pilotage (KPI, graphiques)
- [ ] Chaque KPI affiche sa valeur ET son libellé ; une valeur est confrontée à un recalcul SQL indépendant
- [ ] Accordéon KPI et animations conformes
- [ ] Aucune carte vide quand il n'y a pas de données (texte d'état)
- [ ] Graphiques : axes, légende, info-bulle ; couleurs du design system
- [ ] Filtre de période respecté par toutes les cartes

### 9.2 Classe B — Liste / DataTable avec modale CRUD
- [ ] En-tête, pied, recherche, filtres, tri, pagination
- [ ] Actions de ligne dans l'ordre de la vue maître (modifier, archiver…)
- [ ] Modale de création / édition : champs, validations, focus, fermeture
- [ ] Message de suppression / archivage conforme ; archivé = disparaît de la liste, visible en Corbeille
- [ ] Export (PDF / xlsx) présent là où attendu ; fichier ouvert et relu

### 9.3 Classe C — Fiche de saisie / formulaire (fiches journalières, point de vente, saisie de pièce)
- [ ] Champs calculés non éditables ; le résultat se met à jour à la saisie
- [ ] Refus motivés (départ, passage, plancher) avec les messages exacts
- [ ] Tableau des jours, calendrier mobile, bandeau « Rappel du Cycle » de la filière
- [ ] Libellés propres à la filière (Achats / Nés selon la filière, jamais le vocabulaire avicole partout)
- [ ] Un calcul est vérifié contre au moins 3 cas tracés à la main (section 4.2)
- [ ] Enregistrer persiste ; rouvrir restitue ; annuler ne persiste rien

### 9.4 Classe D — Hub à onglets (comptabilité, soins/vaccins, ventes)
- [ ] Les onglets sont des vues internes de l'écran (pas des pages séparées) ; l'onglet actif survit au rechargement si prévu
- [ ] Navigation clavier et ARIA des onglets
- [ ] Contenu de chaque onglet conforme à sa classe (B ou C)
- [ ] Un onglet sans droit est absent, pas désactivé en silence

### 9.5 Confrontation directe
Capture web et capture poste côte à côte à la même largeur : différences de couleur et de position perceptibles = 0. Outils du poste : `agrierp_flutter/outils/captures.py`, `audit_fidelite.py`, `audit_chrome.py`, `audit_jetons.py` (à adapter à LogiALVIA). Un écran qui n'a pas passé 9.0 + sa classe n'est **pas** « recetté ».

## 10. Cas particuliers des filières

| Filière | Tests spécifiques | Ce qui est À DÉFINIR AVEC LE CLIENT |
|---|---|---|
| Pisciculture (poissons-chats) | libellés Alevin/Juvénile/Mature ; colonne « Nés » ; rations 30/60/110 ; note de barème non confirmé visible ; l'achat d'alevins se saisit en « Achats » | bassins, qualité de l'eau, pesée/échantillonnage, récolte partielle (D-PIS-1 à 4 de `30`) : **aucun test inventé** ; écrire des tests `skip` portant la question |
| Pintades | libellés Poussins/Pintadau/Mature ; « Nés (Couveuse) » ; rations 30/60/110 | durée d'incubation propre (D-PIN-1) |
| Goliaths | libellés Poussins/Goliathau/Mature ; rations 30/60/110 avec note « barème générique non confirmé » ; seuils de maturité 2 800 g / 120 jours présents dans le code | barème validé, définition de la maturité, combinaison des seuils (D-GOL-1/2) |
| Toutes | ajouter une 6ᵉ filière = configuration, pas écran dupliqué : un garde-fou vérifie qu'il n'existe **qu'un** composant de fiche générique paramétré par la configuration | prophylaxie par filière (D-ALL-1) |

## 11. Définition de « terminé »

Un ticket est **terminé** quand TOUT ceci est vrai :

1. Le ticket a été planifié (skill `plan`) avant le code ; un ticket = une session.
2. Ordre de construction respecté : migration → modèle → Action/Service → composant Livewire → vue Blade (web) ; puis écran + dépôt Drift (poste).
3. `php artisan test --testsuite=Feature` vert (avec `npm run build` et `storage:link` faits) ; `flutter analyze` propre ; `flutter test` vert.
4. Chaque règle a : un test de valeur (jeu de 4.2), un test de refus, un test de droit ; chaque test a sa **preuve de mutation** (T2).
5. Parité exécutée E4 pour toute règle portée ; garde-fou E1 pour toute convention nouvelle.
6. Tout changement de table synchronisable : des deux côtés, migration Drift + `build_runner`, test de migration de bases (E8).
7. Changement Alpine / z-index / overlay : un passage Dusk.
8. Changement de schéma, compteur, transaction ou synchro : essai E9/E10 lancé, ou rapport écrivant « NON vérifié sur MariaDB / multipostes ».
9. Recette visuelle (section 9) cochée pour les écrans touchés.
10. Le ticket est consigné dans **le** journal du projet (un seul fichier, jamais deux copies), avec ses constats réels, y compris ce qui n'a pas été vérifié.
11. Messages de commit, tests, libellés, commentaires : en français.
12. Aucun export de base, archive ou `.env` versionné.

## 12. Gabarit de rapport de recette

```markdown
# Rapport de recette — <module / ticket> — <AAAA-MM-JJ>
**Version :** <commit, schéma web, schéma Drift> · **Environnement :** <SQLite mémoire | MariaDB 10.11 | poste Windows> · **Testeur :** <nom, rôle>

## 1. Périmètre
Écrans, règles, tickets couverts. Ce qui est HORS périmètre.

## 2. Résultats automatiques
| Commande | Résultat | Détail |
|---|---|---|
| `php artisan test --testsuite=Feature` | N tests, N verts, N sautés (raisons) | |
| `flutter analyze && flutter test` | | |
| `php artisan dusk` | | |
| `outils/essai_multipostes.sh` (graines : …) | | |

## 3. Matrice exigence → test (extrait)
| Exigence | Test | Statut | Preuve de mutation |

## 4. Scénarios UAT
| ID | Rôle | Résultat (OK / KO / non exécuté) | Valeur relevée | Valeur attendue | Capture |

## 5. Recette visuelle
| Écran | Classe | 9.0 | Classe | Capture web/poste | Écarts |

## 6. Anomalies
| N° | Gravité (bloquante / majeure / mineure) | Écran | Étapes | Attendu | Obtenu | Test qui la verrouille |

## 7. NON vérifié (obligatoire, ne jamais laisser vide)
- poste Windows réel : …
- navigateur (Dusk) : …
- MariaDB peuplée / essai multipostes : …
- base réelle d'un poste : …

## 8. Questions ouvertes pour le client
## 9. Décision : accepté / accepté avec réserves / refusé — signature
```

## 13. Matrice exigence → test

À tenir dans `docs/logialvia/MATRICE_EXIGENCES_TESTS.md` (créée par T6), alimentée à chaque ticket. Un test cite l'exigence dans son docblock (`@exigence BR-ELV-007`) ; un garde-fou vérifie qu'**aucune exigence « Must » n'est sans test**. Départ de matrice (identifiants de logialvia, `docs/B1`, `B6_Regles_Metier.md`, `B5`) :

| Exigence | Intitulé | Étage(s) | Test à écrire |
|---|---|---|---|
| BR-ELV-001 | effectif jamais négatif (plancher 0) | E2, E3, E4 | fonction pure + fiche + parité PHP ↔ Dart |
| BR-ELV-004 | mortalité par catégorie | E2, E3 | jeu 4.2 |
| BR-ELV-007 | effectif et sous-effectifs calculés, jamais saisis | E3, E6, E1 | champ non éditable (rendu + Dusk) + garde-fou |
| BR-ELV-008 | SRH, TS, stock final d'œufs (pondeuses) calculés | E2, E3 | cascade multi-jours |
| BR-ELV-010 | vente d'un animal décrémente la catégorie commercialisée | E3, E4 | vente ventilée |
| BR-VTE-003 | total respecte la remise | E2, E3 | CHECK `total = subtotal − discount` |
| BR-CPT-001 | exercice clôturé verrouillé | E3 | `ClotureGardeeTest`-équivalent |
| BR-CPT-003 | écriture générée automatiquement par la vente / l'achat | E3 | Σ débit = Σ crédit |
| RBAC (I1) | matrice de droits par rôle | E1, E3, E6 | audit des routes + `authorize()` |
| Synchro | idempotence, aucun doublon, convergence | E4, E10 | essai multipostes |
| Données | 25 clés entières → UUID | E8 | `30` §9.7 |
| Sécurité (I3) | secrets chiffrés, jamais synchronisés | E1, E3 | garde-fou Drift + test de sérialisation |

(Les identifiants BR-… sont repris de `configuration_espece.dart` et de `D1_Modele_Donnees_ERD_Dictionnaire.md` de logialvia ; compléter avec `B6_Regles_Metier.md` — non relu en totalité ici.)

## 14. Prompts

Règles communes à chaque prompt : tout en français, un ticket = une session, annoncer le plan avant d'écrire, ne rien committer sauf demande, ne jamais lancer `pkill`, ne rien inventer (« À DÉFINIR AVEC LE CLIENT » + question).

### T0 — Mise en place de l'environnement de test

```text
RÔLE : ingénieur qualité Laravel / Flutter.
CONTEXTE : web LogiALVIA (Laravel 12 + Livewire 3) et poste Flutter. Lis docs/logialvia/31_TESTING_QA.md (sections 3, 5, 6) puis agrierp_laravel/CLAUDE.md (§ Tests, § Verification discipline, § Environment traps) et agrierp_flutter/CLAUDE.md (§ Working rhythm).
TÂCHES :
1. phpunit.xml : suite Feature uniquement (pas de tests/Unit fantôme), sqlite en mémoire.
2. Créer tests/TestCase.php, un trait de connexion par rôle, tests/DuskTestCase.php avec .env.dusk.example (jamais .env.dusk.local versionné ; base dédiée *_dusk).
3. Poste : dart_test.yaml avec le tag `integration` (sauté sans serveur), test/chemins_depot.dart (variables LOGIALVIA_WEB, LOGIALVIA_MAQUETTE), test/php_laravel.dart pour lancer le PHP réel.
4. Documenter les commandes dans le CLAUDE.md du projet (section Tests).
CRITÈRES D'ACCEPTATION : `php artisan test --testsuite=Feature` s'exécute (même avec 1 test) ; `flutter test` saute avec raison les tests d'intégration sans serveur ; `.env.dusk.local` est dans .gitignore.
INTERDITS : pointer Dusk sur la base de développement ; test vert à vide ; committer.
```

### T1 — « Écris les tests du module X »

```text
RÔLE : ingénieur test, méthode du projet (le test qui aurait attrapé le défaut).
CONTEXTE : module <X> (fichier docs/logialvia/20_MODULES_<X>.md). Lis ce fichier, docs/logialvia/15_REGLES_METIER.md (règles du module), docs/logialvia/30_DATABASE_ENGINEERING.md (tables du module) et docs/logialvia/31_TESTING_QA.md (sections 3, 4, 7, 9). Modèles d'AgriERP à imiter : /home/user/agrierp/agrierp_laravel/tests/Feature/ (par ex. FicheLapinsEffectifAutomatiqueTest.php, AlerteAutonomieAlimentaireTest.php, ClotureGardeeTest.php, AutorisationsMethodesMutantesTest.php).
TÂCHES :
1. Liste les règles du module et pour chacune : valeur attendue CALCULÉE À LA MAIN (cite la règle ; si elle est absente des sources, écris « À DÉFINIR AVEC LE CLIENT » et un test `skip` portant la question).
2. Écris les tests E2 (fonctions pures), E3 (Feature Livewire sqlite mémoire : rendu, validation française sous le champ, persistance, droit refusé pour un rôle de lecture, refus motivé avec message exact).
3. Si le module est synchronisé : test E4 de parité exécutée (le poste fabrique l'envoi, le PHP réel le traite et le sert) ; test d'idempotence (même envoi deux fois = rien de plus).
4. Pour chaque chiffre affiché : un recalcul indépendant (SQL ou calcul séparé) comparé à l'affichage.
5. Garde-fou E1 si le module introduit une convention (autorisation, archivage → audit, absence d'auto-incrément).
6. Si le module touche Alpine / modale / z-index : un parcours Dusk, en excluant aside et header pour cliquer par libellé.
7. Complète la matrice exigence → test (docs/logialvia/MATRICE_EXIGENCES_TESTS.md).
CONTRAINTES : tout en français (noms de tests compris) ; aucun test dépendant de l'ordre ; données par les vraies Actions, jamais par insertions directes ; un test sauté dit POURQUOI.
CRITÈRES D'ACCEPTATION : (a) `php artisan test --testsuite=Feature --filter=<Module>` vert ; (b) chaque règle a un test de valeur, un de refus, un de droit ; (c) chaque test a sa preuve de mutation (lance ensuite le prompt T2) ; (d) rapport final avec la section « NON vérifié ».
INTERDITS : valeur attendue copiée de la sortie du code testé ; test qui ne peut pas échouer ; règle métier inventée ; committer.
```

### T2 — Mutation : prouve que le test échoue quand on casse la règle

```text
RÔLE : relecteur adverse. Ton travail est de faire ÉCHOUER les tests.
CONTEXTE : tests du module <X> écrits par T1. Lis docs/logialvia/31_TESTING_QA.md (principes 1 et 2) et le fichier de règle testé.
TÂCHES, pour CHAQUE règle testée, l'une après l'autre :
1. Annonce la mutation (une seule à la fois) : retirer le plancher à 0 ; inverser une comparaison ; oublier un `authorize()` ; supprimer la ventilation par catégorie ; arrondir un montant ; sauter la cascade des jours suivants ; omettre le motif obligatoire ; rejouer un envoi sans idempotence ; retirer une colonne d'un seul côté du schéma.
2. Applique-la dans une COPIE de travail (ou avec un patch que tu annules), lance le test ciblé (`php artisan test --testsuite=Feature --filter=…` / `flutter test test/….dart`) et note : ROUGE (le test a mordu) ou VERT (le test est faible).
3. Annule la mutation (`git diff` doit être vide hors tests) et relance : VERT.
4. Pour tout test resté vert sous mutation : renforce-le (valeur attendue calculée à la main, cas limite) et recommence.
5. Rends un tableau : règle · mutation · résultat sous mutation · résultat après annulation · test renforcé.
CRITÈRES D'ACCEPTATION : 100 % des mutations donnent ROUGE ; l'état final du code de production est strictement inchangé ; le tableau est dans le rapport.
INTERDITS : laisser une mutation dans le code ; modifier la règle « pour que le test passe » ; supprimer un test rouge ; committer ; `pkill`.
```

### T3 — Parité web ↔ poste

```text
RÔLE : ingénieur parité (doctrine article 0 : la vue web est le maître).
CONTEXTE : écran / règle <X>. Lis docs/DOCTRINE_PORTAGE.md, docs/logialvia/31_TESTING_QA.md (§3, E4) et un modèle : /home/user/agrierp/agrierp_flutter/test/avoirs_parite_php_test.dart, test/php_laravel.dart.
TÂCHES : (1) test Dart qui fabrique l'envoi avec les VRAIS dépôts et SyncEngine ; (2) fait traiter cet envoi par le PHP réel (SQLite mémoire, migrations réelles, vrai rôle du seeder) puis servir son vrai tirage que le poste absorbe ; (3) compare valeurs, messages de refus (mot pour mot) et statuts ; (4) garde-fou qui lit le Blade pour les libellés communs ; (5) se SAUTE avec sa raison sans PHP ni dépôt web.
CRITÈRES : changer un libellé, un format de date ou un statut d'un seul côté fait rougir le test (prouve-le).
INTERDITS : recopier la règle côté test ; test vert à vide ; committer.
```

### T4 — Migration de bases réelles et d'anciennes versions

```text
RÔLE : ingénieur migration.
CONTEXTE : docs/logialvia/30_DATABASE_ENGINEERING.md §9 ; modèles : agrierp_flutter/test/migration_toutes_versions_test.dart, migration_bases_reelles_test.dart.
TÂCHES : (1) pour chaque schemaVersion de Drift depuis la v1 : créer une base de cette version, la monter jusqu'à la dernière, vérifier lignes, montants, `PRAGMA foreign_key_check` vide ; (2) copie réelle d'une base de poste du client (si fournie, sinon « NON vérifié sur base réelle ») ; (3) totaux avant/après identiques à l'unité (ventes, achats, débits/crédits, stocks, effectif de la dernière fiche de chaque filière) ; (4) rejeu : deuxième passage sans effet ; (5) deux postes migrés séparément = mêmes UUID de référentiels.
CRITÈRES : tout vert ; rapport avec les valeurs non entières et pièces déséquilibrées rencontrées.
INTERDITS : arrondir un montant sans règle validée (Q9 de 30_DATABASE_ENGINEERING.md) ; modifier la base source ; committer.
```

### T5 — Essai multipostes à coupures aléatoires, MariaDB réel

```text
RÔLE : ingénieur fiabilité.
CONTEXTE : agrierp_flutter/outils/essai_multipostes.sh (lis son en-tête), essai_multipostes_serveur.php, test/essai_multipostes_test.dart ; docs/COMPARAISON_METHODE_TATACORA.md ; PLAN_FINALISATION.md ticket S-T9 (5 défauts réels trouvés).
TÂCHES : adapter le script à LogiALVIA (base jetable *_essai en utf8mb4_unicode_ci, migrate:fresh --seed puis DemoDataSeeder, serveur avec PHP_CLI_SERVER_WORKERS=4, cinq postes, coupures au hasard, graines rejouables, arrêt du GROUPE de processus du serveur) ; exécuter ≥ 8 graines ; lire les rapports (invariants, compteurs, doublons) ; chaque défaut trouvé devient un test E3/E4 permanent.
CRITÈRES : aucune perte, aucun doublon, convergence des postes, aucun interblocage non rejoué ; sans mariadbd le script se replie sur SQLite ET LE DIT (alors écrire « NON vérifié sur MariaDB »).
INTERDITS : lire ou modifier un .env ; ouvrir une base existante ; écrire sur le serveur de développement ; pkill ; committer.
```

### T6 — Matrice exigence → test et audit de couverture

```text
RÔLE : responsable qualité.
CONTEXTE : docs/logialvia/31_TESTING_QA.md §13 ; exigences : /home/user/massenon/logialvia/docs/B1_BRS_Business_Requirements.md, B6_Regles_Metier.md, B5_NFRS_NonFunctional_Requirements.md.
TÂCHES : créer docs/logialvia/MATRICE_EXIGENCES_TESTS.md (exigence · priorité · étage · fichier de test · statut · preuve de mutation) ; écrire le garde-fou qui lit les docblocks des tests et échoue si une exigence « Must » n'a aucun test ; lister les exigences sans test.
CRITÈRES : le garde-fou rougit quand on retire le test d'une exigence (prouve-le).
INTERDITS : cocher « couvert » sans test exécuté ; inventer une exigence.
```

### T7 — Recette : exécuter les UAT et rédiger le rapport

```text
RÔLE : recetteur.
CONTEXTE : docs/logialvia/31_TESTING_QA.md §8, §9, §12.
TÂCHES : dérouler les scénarios UAT du module avec le compte de chaque rôle (seeder de démonstration), relever les valeurs, confronter chaque chiffre à un recalcul indépendant, remplir la check-list visuelle (classe de chaque écran), remplir le gabarit §12 sans omettre « NON vérifié ».
CRITÈRES : chaque scénario a un résultat (OK / KO / non exécuté) et une preuve ; chaque KO a une anomalie avec le test qui la verrouillera.
INTERDITS : déclarer « fonctionne » pour ce qui n'a été vu qu'en test serveur (Livewire::test) ; omettre la section NON vérifié.
```

## 15. Questions ouvertes

1. Les **quatre classes d'écran** : confirmer la classification de la section 9 avec `04_UI_UX_DESIGN_SYSTEM.md` (mes sources ne les nomment pas).
2. **Rôles** de LogiALVIA : liste exacte tirée de `docs/I1_Matrice_RBAC.md` (non relue en détail ici) pour nommer les comptes de recette.
3. **Alerte de maturité des goliaths** : les deux seuils (2 800 g, 120 jours) se combinent-ils par ET ou par OU ?
4. **Seuil d'autonomie alimentaire** (3 jours chez AgriERP) : identique pour LogiALVIA ?
5. **Règle d'arrondi FCFA** (Q9 de `30`) : sans elle, le test de migration des montants échoue plutôt que d'arrondir.
6. **Base réelle d'un poste logialvia** : le client peut-il en fournir une copie pour T4 ?
7. **Poste Windows réel et matériel de la ferme** pour la recette finale : disponibles quand ?
