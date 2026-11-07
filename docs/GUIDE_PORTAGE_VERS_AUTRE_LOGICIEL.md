# GUIDE DE PORTAGE LogiAgriERP → LogiALVIA (dépôt `massenon/logialvia`)

Rédigé le 07/11/2026 depuis le monorepo AgriERP (branche `claude/sleepy-dijkstra-uvt68t`), pour une session Claude Code qui ne connaît PAS LogiAgriERP. Il a été adapté après lecture du dépôt cible, cloné en lecture seule dans `/home/user/massenon/logialvia`.

**Convention de chemins.** Sans préfixe d'origine, un chemin est dans LogiAgriERP, relatif à la racine du monorepo (`agrierp_laravel/…` = web, `agrierp_flutter/…` = poste). `logialvia_app/…` et `logialvia/docs/…` = dépôt cible. `NEW:` = fichier à créer dans la cible. Tous les chemins hors `NEW:` ont été vérifiés par `ls` à la rédaction.

**Ce que la session cible peut ne pas avoir sous la main.** Elle n'a ni PHP ni le web AgriERP. Les règles Laravel citées ici sont donc données EN CLAIR (formules, messages, jeux de cas calculés à la main) : le jeu de cas de chaque bloc se recopie tel quel en test unitaire Dart. Le code source d'AgriERP reste la référence si le dépôt est joignable.

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
15. Bloc 14 — Transversal (doctrine traduite pour une application sans serveur)
16. Check-list de démarrage

---

## 0. État des lieux de logialvia

**Nature.** Application Flutter SEULE, « Gestion intégrée ALLMANY ET COMPAGNIE » (Natitingou), 31 écrans issus d'un prototype HTML (`logialvia/docs/03_INVENTAIRE_31_ECRANS.md`), Windows en priorité, hors ligne par construction (`logialvia/docs/A1_MASTER_PROMPT.md` §5 : « pas de backend serveur pour cette phase »). Pubspec `logialvia_app/pubspec.yaml` : `sdk: ^3.12.2`, Drift 2.34.3 (lock), `provider`, `go_router`, `window_manager`, `pdf`/`printing`, `fl_chart`, `crypto`, `flutter_secure_storage`, `http` (utilisé UNIQUEMENT pour e-MECeF, `logialvia_app/lib/commercial/domain/services/transmission_mecef.dart` : aucune synchronisation de données). Schéma Drift v26 (`logialvia_app/lib/core/database/app_database.dart`, `versionSchema`). 62 fichiers de test dans `logialvia_app/test/`.

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
| E11 | Aucun export tableur (xlsx/csv), aucun import (relevé bancaire, plan), pas de version Flutter figée, pas de `build_windows.bat` ni d'installateur | 7, 8, 10 |
| E12 | Clôture d'exercice = verrou simple (`cloturerExercice`) sans gardes ni étapes ; pas de registre d'immobilisations ; pas d'aide flottante | 11, 13 |

**Contradictions entre la doctrine de logialvia (A1/A2) et les habitudes d'AgriERP — à trancher AVANT de porter** (ne rien résoudre en silence) :

1. **Langue du code.** A1 §5 : noms de variables/fonctions en anglais par convention. Le code réel de logialvia est en réalité en FRANÇAIS (`CalculFicheJournaliere`, `enregistrerJour`). AgriERP exige le français partout. → Suivre le code existant de logialvia (français), ne pas mélanger.
2. **Source de vérité.** AgriERP : « la vue web est le maître » ; logialvia : le prototype HTML (`logialvia/docs/A1_MASTER_PROMPT.md` §1) et ses documents. Ici AUCUN web : le maître d'une règle portée est le document de logialvia s'il existe (`B6`, `05_LOGIQUE_CALCUL_FORMULAIRES.md`), sinon la règle d'AgriERP donnée ici, sinon DEMANDER. Une règle d'AgriERP qui contredit un BR de B6 est signalée au client, jamais appliquée seule.
3. **Marqueurs d'écart.** AgriERP : `⚠️ ÉCART` ; logialvia : `// ECART_DELIBERE:` et `// TODO(dette):` (A1 §3.3, A2 §4). → Utiliser les marqueurs de logialvia.
4. **Traçabilité.** logialvia exige l'identifiant `BR-XXX-NNN` au-dessus de chaque règle codée (B6, Traçabilité). → Ajouter les nouvelles règles à B6 (nouveaux numéros, ex. BR-ELV-011…) puis les citer dans le code.
5. **Identifiants.** AgriERP : UUID obligatoires (synchro). logialvia : `integer().autoIncrement()` partout, sans serveur. → NE PAS passer aux UUID sans besoin de synchronisation ; garder les entiers. (Renvoi : `docs/BLUEPRINT_SYNCHRONISATION_MULTIPOSTES.md` seulement si logialvia ajoute un jour une synchro.)
6. **Mot de passe.** AgriERP : jamais en base (il part au serveur via le coffre). logialvia : SHA-256 + sel en base, choix confirmé (`logialvia_app/lib/administration/domain/services/hachage_mot_de_passe.dart`, doc F1). Sans serveur, le hash local est obligatoire ; seule la FORCE du hash diffère (le PIN d'AgriERP utilise PBKDF2-HMAC-SHA256 ≥ 100 000 itérations, `agrierp_flutter/lib/core/auth/verrou_local.dart`). → Proposer PBKDF2 au client, ne pas l'imposer.
7. **Rôles.** logialvia : 3 rôles (admin, caissier, animalier ; `logialvia_app/lib/administration/domain/entities/role_utilisateur.dart`, « aucun rôle comptable »). AgriERP : 4 rôles (admin, comptable, caissier, animalier). → Garder 3 ; tout droit « comptable » d'un bloc est rattaché à l'admin tant que le client n'arbitre pas.
8. **Drift.** AgriERP : Drift 2.31, `&` indéfini sur `Expression<bool>` donc `.and()`. logialvia : Drift 2.34.3, c'est l'INVERSE (`&`, et `.and()` ne compile pas ; `logialvia/docs/K4_Retour_Experience_Bugs_Reels.md`). → Ne pas recopier les requêtes d'AgriERP : réécrire dans l'API de la version de logialvia.
9. **Tests.** AgriERP : parité PHP exécutée (`agrierp_flutter/test/php_laravel.dart`). logialvia : tests unitaires Dart (A2 §6 : 100 % des `domain/usecases` de calcul testés). → Voir bloc 14.
10. **Documentation obsolète.** `logialvia/docs/02_ARCHITECTURE.md` (arborescence) et `logialvia/docs/11_SETUP_INSTALLATION.md` (Flutter 3.19+, sdk >=3.3.0) ne décrivent plus le code ; A2 §7 demande de les corriger quand l'écart est découvert.

---

## 1. Tableau récapitulatif et ordre de portage

Effort : S ≤ 1 jour · M 2 à 4 jours · L 5 à 10 jours (une session Claude + relecture, base de la cible déjà montée). Dépendances en numéros de bloc.

| Bloc | Effort | Dépend de | Fichiers clés dans LogiAgriERP |
|---|---|---|---|
| 8 Compilation / version figée | S | — | `agrierp_flutter/lib/core/sync/sync_engine.dart` (l. 2783), `agrierp_flutter/.fvmrc`, `agrierp_flutter/build_windows.bat` |
| 14 Transversal (gardes, conventions) | M | — | `agrierp_flutter/test/conformite_portage_test.dart`, `agrierp_flutter/test/fidelite_libelles_test.dart` |
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

**Ordre conseillé** : socle (8, 14) → fenêtre (3) → utilisateurs (2) → plan comptable (9) → exercices et comptabilité (4, 11, 13 partie comptable) → bandes (12) → fiches par filière (1) → rationnement (5) → prophylaxie et rappels (6) → import/export (7) → aide (13) → build (10). Raison : la fiche calculée suppose une bande propre (12) et un exercice qui peut être clos (4) ; le rationnement lit l'effectif calculé ; le build clôt la chaîne.

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
- Une vente et une fiche créées au même instant pour le même (bande, jour) : un seul écrivain, transaction unique (sans serveur : risque limité à deux ViewModels concurrents).
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
- **Mot de passe au coffre, jamais en base** (AgriERP, parce qu'il part au serveur) : `SyncEngine.cleMotDePasse` dans `flutter_secure_storage`, effacé après envoi. ⚠️ NON TRANSPOSABLE tel quel : sans serveur, logialvia doit conserver un hash en base (contradiction 6 du §0) ; la règle à reprendre est « jamais le mot de passe en clair, jamais journalisé, jamais dans une sauvegarde lisible ».
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
- **Imports** : (1) **relevé bancaire CSV idempotent** : `BankReconciliationService::importCsv(compte, contenu, importId)` (`agrierp_laravel/app/Services/BankReconciliationService.php`) — séparateur `;` puis `,`, trois colonnes date / libellé / montant, lignes invalides comptées `skipped`, **un `import_id` déjà joué n'est pas rejoué** ; poste : `RapprochementRepository.importerReleve` (`agrierp_flutter/lib/features/comptabilite/rapprochement_repository.dart`), UUID d'import, taille max 2 048 ko (message « Le fichier relevé ne doit pas dépasser 2048 kilo-octets. »). (2) **Import d'un module depuis une sauvegarde** : `ImportModuleService` (`agrierp_laravel/app/Services/ImportModuleService.php`, ticket 14.58) n'exécute JAMAIS le SQL téléversé : il l'analyse, ne garde que les `INSERT INTO`, vers les tables du module choisi (liste du module, jamais déduite du fichier), valeurs LIÉES ; le reste est compté et rejeté. (3) **Plan SYSCOHADA** : `php artisan comptabilite:importer-plan-syscohada` (insertion seule, bloc 9). Il n'existe PAS d'import tableur de données métier, ni d'import au poste d'un module.
- **Sauvegardes / restauration (AUT-4)** : `AdministrationLocale` (`agrierp_flutter/lib/features/parametres/administration_locale.dart`) : `generer` = `VACUUM INTO` (sauvegarde COMPLÈTE de la base SQLite), export de module en JSON, **restauration installée AU PROCHAIN LANCEMENT** par `appliquerRestaurationEnAttente` avant l'ouverture de la base (fichier `agrierp.restauration`, ancienne base gardée sous `agrierp.avant-restauration.sqlite`) ; seule une sauvegarde complète se restaure. Web : `agrierp_laravel/app/Services/SauvegardeService.php` (`mysqldump`) et `agrierp_laravel/app/Livewire/Parametres/Sauvegardes.php`.

### (a) Existe dans logialvia
PDF : `logialvia_app/lib/core/pdf/document_pdf.dart`, `logialvia_app/lib/core/pdf/generateur_pdf.dart`, `logialvia_app/lib/core/pdf/service_impression.dart`, `logialvia_app/lib/core/pdf/bouton_export_pdf.dart` (+ police Roboto embarquée, test `logialvia_app/test/core/pdf_police_roboto_test.dart`, `logialvia_app/test/core/generateur_pdf_test.dart`) ; documents par module (`logialvia_app/lib/elevage/presentation/screens/documents_elevage.dart`, etc.) ; manuel PDF généré (`logialvia_app/lib/core/pdf/manuel/`). Sauvegarde/restauration : `logialvia_app/lib/administration/domain/services/service_sauvegarde.dart` (`genererBaseComplete`, `exporterTable`), `logialvia_app/lib/administration/domain/services/service_restauration.dart` (`preparer`, `appliquerSiDemandee`), test `logialvia_app/test/administration/restauration_test.dart`, `logialvia_app/test/administration/service_sauvegarde_test.dart`. AUCUN xlsx/csv dans `lib/` (grep négatif), aucun import.

### (b) Manque
Export tableur (E11), import de relevé bancaire idempotent, import de plan SYSCOHADA, garde de taille d'import.

### (c) Dans cette architecture
Réutiliser le MÊME `DocumentPdf` de logialvia comme structure pure et ajouter `NEW:logialvia_app/lib/core/export/export_tableur.dart` (builder pur `Uint8List construire(DocumentPdf)`, aucune E/S ; l'effet de bord — enregistrer — dans un service injecté). Import de relevé : `ImporterReleveBancaireUseCase` dans `NEW:logialvia_app/lib/comptabilite/domain/usecases/` (parse pur + `import_id` mémorisé en table pour l'idempotence, lignes rejetées comptées et montrées). Sans serveur l'idempotence se garde par l'empreinte du fichier ou un UUID d'import conservé en table.

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
- Documentation d'installation : `docs/INSTALLATION_LOCALE.md`, `docs/GUIDE_DEPLOIEMENT.md` (web, cPanel : non applicable à logialvia).

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
Nom de l'installateur et de l'éditeur ; dossier des données ; la désinstallation supprime-t-elle les données (DES-1) ? Sauvegarde automatique proposée (DES-2) ? Un poste ou plusieurs (sans synchro, chaque poste est indépendant) ?

---

## 12. Bloc 11 — Bascule et clôture d'exercice

### Objectif
Clôturer un exercice par étapes gardées, ouvrir le suivant, sans jamais corrompre le bilan.

### Règle (CP-4, EX1 à EX5)
- **Étapes** : confirmer l'étape 1 (`confirmer_etape1`), solder les comptes de gestion classes 6 et 7 (`solder_comptes_gestion`, étape 2 ; la classe 8 n'est pas soldée : un compte HAO avec solde rend l'à-nouveau déséquilibré et la clôture est REFUSÉE avec son motif), clôturer l'exercice (`cloturer_exercice`), rouvrir (`rouvrir_exercice`, droit d'administration), ouvrir le suivant (`ouvrir_exercice_suivant`), ouvrir le premier (`ouvrir_exercice`), clôturer / déclôturer une période mensuelle. Clôture GARDÉE : échéance passée (clôture refusée avant la fin de l'exercice), étapes 1 et 2 faites, N-1 clos, à-nouveau équilibré ; à-nouveau verrouillé (ni modifiable ni archivable).
- **États justes après clôture (R1)** : jamais historique + à-nouveau ; l'écriture de solde (étape 2) est écartée du Bilan et du Compte de résultat (le résultat reste sur la ligne « Résultat de l'exercice »), mêmes totaux. À-nouveaux provisoires tant que N est ouvert.
- **Exercice clos verrouillé (EX5)** : stock, fiches d'élevage (Q3), paie (Q4), déplacement d'écriture, date d'une dépense comptabilisée refusés ; messages en JJ/MM/AAAA.
- **Poste (CP-4)** : le poste n'écrit JAMAIS `fiscal_years` ni `periodic_closures` directement — il écrit une DEMANDE (`fiscal_closure_requests`, `kind` + `payload`) après avoir refusé ce qu'il sait juger (`CalculCloture`, parité exécutée avec `ClotureExerciceService`) ; le serveur rejoue, dans l'ordre d'INSERTION (`rowid`, car `updated_at` n'a que la seconde), et l'état redescend au tirage. ⚠️ SANS SERVEUR (logialvia) cette indirection disparaît : le use case ÉCRIT directement l'exercice, mais en gardant les MÊMES refus et le même ordre d'étapes ; le principe « un seul écrivain de l'état d'exercice » reste.
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
- **Règle** : opération diverse équilibrée (débit = crédit à la décime, vérifié AVANT écriture), débit ≠ crédit pour une écriture à deux lignes, date dans un exercice OUVERT et un mois non clôturé, écriture non verrouillée ; numéro `OD-AAAA-NNNN` attribué par le serveur (l'année de l'écriture) — **sans serveur : numérotation séquentielle locale à l'enregistrement, dans la même transaction que l'écriture, jamais recalculée** (logialvia a déjà `comptabilite_view_model.dart` qui forme « OD-2026-… » : déplacer la numérotation en `domain`/dépôt, hors du ViewModel) ; une écriture à plus de deux lignes, verrouillée ou d'à-nouveau ne se retouche pas ; archivage = contre-passation exacte, jamais suppression. Source unique de toute écriture : `AccountingEntryService::record()` / `recordManual()`.
- **Fichiers (AgriERP)** : `agrierp_laravel/app/Actions/SaisieEcritureManuelleAction.php`, `agrierp_laravel/app/Services/AccountingEntryService.php`, `agrierp_flutter/lib/features/comptabilite/comptabilite_repository.dart` (`creerEcriture`, `modifierEcriture`, `archiverEcriture`).
- **logialvia** : `enregistrerPiece`, `remplacerPiece`, `supprimerPiece`, `supprimerEcriture` dans `logialvia_app/lib/comptabilite/data/repositories/comptabilite_repository_drift.dart` ; `logialvia_app/lib/comptabilite/domain/services/moteur_comptable.dart`, `logialvia_app/lib/comptabilite/domain/usecases/generer_ecritures_automatiques.dart`. ⚠️ « supprimer » une écriture contredit « archiver / contre-passer » d'AgriERP : à arbitrer (B6 BR-ADM-003 : journalisation).
- **Tests** : `agrierp_flutter/test/ecritures_manuelles_poste_test.dart`, `agrierp_laravel/tests/Feature/SyncEcrituresManuellesTest.php`, `agrierp_laravel/tests/Feature/NumerotationEcrituresTest.php`, `logialvia_app/test/comptabilite/moteur_comptable_test.dart`.
- **Questions** : suppression d'écriture autorisée ou contre-passation seulement ? Format du numéro ?

### 13d — Clôture d'exercice au poste (CP-4)
Voir bloc 11 (sans serveur : écriture directe, mêmes refus).

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

## 15. Bloc 14 — Transversal (doctrine traduite pour une application sans serveur)

Règles d'AgriERP à reporter AVEC chaque bloc, et leur traduction pour logialvia.

| Règle AgriERP | Traduction logialvia |
|---|---|
| Web = maître, fidélité 100 % | Le MAÎTRE d'une règle = document de logialvia (`logialvia/docs/B6_Regles_Metier.md`, `05_LOGIQUE_CALCUL_FORMULAIRES.md`, fiche F/H du module) ; à défaut, la règle donnée ici ; à défaut, DEMANDER. Un écart est marqué `// ECART_DELIBERE:` |
| Gardes qui lisent les sources | Les tests lisent le CODE (`File(...).readAsStringSync()`), pas seulement l'exécution : modèle `agrierp_flutter/test/conformite_portage_test.dart` (interdit `fontSize: 12`, `AlertDialog`, `showDialog` sans modale unique, `constraints.maxWidth` pour choisir une mise en page), `agrierp_flutter/test/fidelite_libelles_test.dart` (libellés = littéraux de chaînes, JAMAIS commentaires : `chainesDe`), `agrierp_flutter/test/conformite_structure_test.dart` (ordre des colonnes). Ne jamais les affaiblir pour faire passer un écran |
| Absorbeurs stricts | Sans synchro : la même idée = un DÉPÔT strict qui REFUSE une ligne incohérente à l'insertion/restauration (restauration `logialvia_app/lib/administration/domain/services/service_restauration.dart`) plutôt que la lisser ; un test garantit que chaque dépôt déclaré est utilisé |
| UUID | Non applicable (entiers `autoIncrement` conservés). Si une synchro est un jour ajoutée : `docs/BLUEPRINT_SYNCHRONISATION_MULTIPOSTES.md` |
| `app_database.g.dart` jamais à la main | Idem : `logialvia_app/lib/core/database/app_database.g.dart` est généré (`dart run build_runner build --delete-conflicting-outputs`) ; chaque palier = `versionSchema` + bloc `if (from < N)` explicite + test de migration (`logialvia_app/test/core/migration_idempotente_test.dart`) |
| Tout en français | Déjà la règle de logialvia pour l'interface (A1 §5) ; code en français comme l'existant |
| Un écrivain par table | Un seul dépôt écrit une table (ex. la cascade de fiche pour `fiche_journee`), vérifié par un test qui lit les sources |
| Parité PHP exécutée (`php_laravel.dart`) | **Remplacée** par : (1) fonctions de calcul PURES dans `domain/`, (2) jeux de cas écrits à la main (ceux de ce guide), jamais produits par le code testé, (3) test « propriété » sur entrées aléatoires (somme des catégories = total ; jamais négatif ; idempotence de la cascade), (4) test de mutation manuel : retirer la règle doit rougir un test. Si le dépôt AgriERP est joignable, les jeux de cas PHP peuvent être exportés en JSON et lus par un test Dart (c'est ce que faisait `php_laravel.dart`) — sinon non |
| Donnée inconnue = `'—'` jamais `0` | À appliquer aux effectifs inconnus (lapins) et aux totaux non calculables |
| Fuseau : heure du pays | `HeureBenin` (UTC+1 fixe, `agrierp_flutter/lib/core/temps/heure_benin.dart`, test `agrierp_flutter/test/heure_benin_test.dart`, doit passer avec `TZ=America/New_York`) ; jamais `DateTime.now()` pour un jour métier |
| Modales / composants uniques | Un `AppModal`, un `KpiCard`, un tableau mensuel (déjà `logialvia_app/lib/core/widgets/app_modal.dart`, `kpi_card.dart`) : jamais de variante locale ; A2 §12 (duplication > 5 lignes) |
| Définition de « terminé » | `flutter analyze` sans erreur, `flutter test` vert, règle écrite dans B6 avec son `BR-…`, et ce qui n'a PAS été vérifié dit explicitement |

**Ordre de portage conseillé (rappel)** : socle → exercices / comptabilité → bandes → fiches par filière → modules → aide → build (voir §1).

**Synchronisation** : sans objet pour logialvia aujourd'hui (le seul usage réseau est e-MECeF). Si une synchro est décidée plus tard : `docs/BLUEPRINT_SYNCHRONISATION_MULTIPOSTES.md` (règles de conflit par nature de donnée, pull avant push, accusés, UUID).

---

## 16. Check-list de démarrage pour la session de l'autre projet

**À lire d'abord (dans cet ordre).**
1. `logialvia/docs/A1_MASTER_PROMPT.md`, `logialvia/docs/A2_STRICT_AVOID.md`, `logialvia/docs/B6_Regles_Metier.md`, `logialvia/docs/05_LOGIQUE_CALCUL_FORMULAIRES.md`, `logialvia/docs/K4_Retour_Experience_Bugs_Reels.md`, `logialvia/docs/F3_Module_Production_Elevage.md`.
2. Le code d'élevage : `logialvia_app/lib/elevage/domain/entities/configuration_espece.dart`, `…/domain/services/calcul_fiche_journaliere.dart`, `…/domain/usecases/enregistrer_journee_usecase.dart`, `…/data/tables/fiche_journee_table.dart`.
3. Ce guide, §0 (contradictions) AVANT tout code ; poser les questions du client regroupées (liste ci-dessous).
4. Dans AgriERP, si joignable : `docs/DOCTRINE_PORTAGE.md`, `agrierp_laravel/app/Services/EffectifParCategorieService.php` (messages exacts), `agrierp_flutter/CLAUDE.md`.

**À copier tel quel (puis adapter noms et chemins).**
- Le jeu de cas du bloc 1 et du bloc 5 (valeurs numériques) en tests.
- `build_windows.bat`, `installer/agrierp.iss` (AppId NOUVEAU), `outils/generer_icone.py` (déjà présent), `.fvmrc` (valeur lue localement).
- Les C++ de la fenêtre (`agrierp_flutter/windows/runner/win32_window.cpp`, `flutter_window.cpp`) si la voie A est choisie.
- `agrierp_flutter/lib/core/export/export_tableur.dart` (structure : adapter à `DocumentPdf`).
- Les messages de refus (départ, passage, bande, transfert, exercice clos) mot pour mot, avec leur source citée.
- La liste des tests de garde de lecture de sources (`conformite_portage_test.dart`).

**À réécrire dans l'architecture de logialvia.**
- Tout le calcul d'effectif, de rationnement, de clôture, de rappels : fonctions pures dans `domain/services`, use cases dans `domain/usecases`, dépôts Drift dans `data/repositories`, ViewModels sans règle.
- Les migrations Drift (palier explicite, nommage manuel des colonnes `_4`, test de migration).
- La numérotation `OD-AAAA-NNNN` (locale, transactionnelle).
- Les écritures « demande rejouée par le serveur » (CP-2, CP-3, CP-4, EL-1) : écritures directes, mêmes refus.
- L'aide (un fichier de textes, sans génération PHP).

**Avant de coder, obtenir du client** (liste consolidée) : glossaire et rations par filière (lapins Q1/Q2, poulets Q3/Q4) ; départ obligatoire et cascade (Q5/Q6) ; ventes par catégorie (Q7) ; pisciculture (stades, biomasse, bassin, aliment, passage, vente) ; pintades (stades, rations) ; politique de mot de passe et rôle comptable ; barre de fenêtre native ou système ; exercice civil / décalé et réouverture ; amortissement ; export Excel / CSV et import de relevé ; nom de l'installateur, données à la désinstallation ; texte de l'aide.

**Zones NON couvertes par AgriERP (ne rien inventer).** Pisciculture / Poissons-Chats (aucune règle ni donnée : seul le mécanisme générique est réutilisable) ; Pintades (aucune règle propre : volaille, mécanisme VOL-1) ; Goliaths (seul produit « Poulet goliath (sujet vif) » rangé en Jeune par nom ; aucune règle de stade) ; poulets de chair en tant que filière distincte (AgriERP a des reproducteurs et des pondeuses) ; export xlsx au web ; fenêtre native et installateur jamais exécutés sur Windows ; MeCeF (hors périmètre de ce guide : logialvia a déjà son propre module `logialvia_app/lib/commercial/domain/services/transmission_mecef.dart`).

**Ce qui n'a PAS été vérifié en rédigeant ce guide.** Aucun code de logialvia n'a été compilé ni testé ici ; `flutter analyze` n'a pas été lancé sur le dépôt cible ; le comportement de `window_manager` contre le défaut de la barre des tâches est inconnu ; les jeux de cas ont été calculés à la main d'après les formules du code PHP lu (non exécuté) ; les tests de parité PHP cités n'ont pas été relancés.
