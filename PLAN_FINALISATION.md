# PLAN DE FINALISATION — AgriERP

**Ferme École OLOUWACHEGOUN · état au 17/10/2026 · monorepo `massenon/agrierp`**

Ce plan ordonne ce qui reste à faire pour livrer un poste Windows **100 % autonome hors ligne**, fidèle à l'application web. Il s'appuie sur :
- les règles de [`DOCTRINE_PORTAGE.md`](DOCTRINE_PORTAGE.md) ;
- le journal des tickets `agrierp_laravel/README_SPRINT0.md` (tickets web jusqu'à 15.42, poste jusqu'à F0.95) ;
- `agrierp_flutter/AUDIT_FIDELISATION.md`.

> Convention : ✅ fait · 🔧 à faire · ❓ décision client requise avant de coder. Un ticket = une session, terminé seulement quand les tests sont verts des deux côtés et que le ticket est consigné dans `README_SPRINT0.md`.

---

## Point de départ

| Surface | État |
|---|---|
| Web Laravel 12 + Livewire 3 | Sprints 1 à 15 livrés ; 62 routes nommées ; suite Feature verte. En production, la version déployée est celle du ticket 15.4. |
| Poste Flutter Windows | Tous les écrans de la barre latérale du prototype sont portés ; schéma Drift v38 ; environ 2 000 tests ; synchronisation pull/push opérationnelle avec écran **Synchronisation**. |
| Sprint 3 (Élevage) | Livré au ticket 3.14, puis repris par 14.x/15.x (effectif par catégorie, cascade). **Défaut de production corrigé le 17/10/2026, voir A1.** |

---

## Sprint A — Correctifs de production (immédiat)

### A1 ✅ « Effectif Total Vivant » faux après saisie d'une fiche journalière

- **Symptôme.** Après création d'une bande de reproduction puis saisie dans la fiche journalière, le KPI « Effectif Total Vivant » (Gestion des Bandes, Gestion Élevage, Tableau de bord) devenait faux.
- **Cause.** Les fiches web **Reproducteurs, Pondeuses, Escargots** écrivaient `current_quantity` = effectif du jour **édité**. Saisir ou corriger une fiche antérieure à la dernière ramenait donc la bande à ce jour-là, sans recalculer les jours suivants.
  - `EnregistrerSujets` partait de `current_quantity` pour une date passée et faisait `increment()` sans cascade.
  - Le poste (`FicheJournaliereRepository.enregistrer`) avait le même défaut.
  - Les fiches Porcs et Lapins passaient déjà par la cascade (ticket 15.42).
- **Correctif.** Toutes les écritures passent par la **cascade unique** : `RecordSaleOnFicheElevageAction::recalculerEnCascade()` côté web, `FicheJournaliereRepository.recalculerEnCascade()` côté poste. Les jours suivants sont recalculés et la bande prend l'effectif de la **dernière** fiche.
- **Tests.** `tests/Feature/EffectifTotalVivantCascadeTest.php` (4 tests) et un test dans `test/fiche_journaliere_test.dart`. Tous sont **rouges sans le correctif, verts avec** (épreuve de mutation faite).
- **Reste à vérifier.** La fiche Escargots n'a pas de test dédié (module `helico` à activer dans le test) ; ticket A1-bis.

### A2 ❓ Bandes « issues d'une bande » comptées deux fois

- **Constat probable** (à confirmer avec l'exploitant) :
  1. Les naissances sont saisies dans la fiche de la bande mère (`ne`), qui augmente son effectif.
  2. Une **nouvelle bande** est ensuite créée dans Gestion des Bandes pour la portée ou les sevrés, avec un effectif initial égal à ces mêmes animaux.
  3. Ils sont alors comptés **deux fois** dans « Effectif Total Vivant ».
- **Aucun mécanisme de transfert** entre bandes n'existe aujourd'hui, ni sur le web ni sur le poste.
- **Proposition.** Un mouvement « Transfert vers bande » : sortie de la bande source et entrée dans la bande cible, le même jour, dans une transaction, avec cascade des deux côtés. Il porte un `lot_source_id` sur la bande créée.
- **Décision client avant code :**
  - Le transfert est-il une colonne de la fiche (`transfert_sortie`) ou un écran dédié ?
  - Faut-il corriger les bandes déjà saisies (D6) ?

### A3 ❓ « Don » dans Enregistrer des Sujets

- L'origine « Don » (animal **reçu**) est écrite dans la colonne `don`.
- La formule du Document 05 **soustrait** cette colonne, qui sert pour les animaux **donnés**.
- Un don reçu de 5 sujets **baisse** donc l'effectif de 5 au lieu de l'augmenter.
- **Décision :** créer une colonne `don_recu` (entrée), ou ranger les dons reçus avec les achats ?

### A4 🔧 Transformation (abattage) hors fiche

- `TransformationForm` fait `decrement('current_quantity')` sans écrire de fiche journalière.
- La sauvegarde de fiche suivante réaligne la bande sur la dernière fiche et **efface** donc l'abattage. Ce comportement existait déjà avant A1.
- **Proposition :** inscrire la transformation comme sortie dans la fiche du jour, puis lancer la cascade.

### A5 🔧 Autorisation des fiches journalières

- Les cinq méthodes `saveDay()` des fiches web n'appellent pas `$this->authorize('manage-elevage')`, contrairement à la règle du projet (« première ligne de toute méthode mutante »).
- Ajouter l'appel et un test par fiche, après vérification que chaque rôle qui saisit des fiches a bien `manage-elevage`.

### A6 ✅ Compilation avec le Flutter stable actuel

- `sync_engine.dart` ne compilait pas avec Dart 3.13 (promotion de nullité d'une variable capturée), alors que `pubspec.yaml` autorise ce SDK.
- **Corrigé** par une copie finale locale, sans changement de règle.
- 🔧 Figer la version de Flutter du poste de compilation (`.fvmrc` ou mention dans `build_windows.bat`) pour éviter la prochaine dérive.

### A7 🔧 Chemins Windows absolus dans les tests du poste

- 19 fichiers de `agrierp_flutter/test` et `outils/` lisent `C:/laragon/www/agrierp/...` ou `C:/Projects/agrierp_laravel/prototype_html/...`.
- Dans le monorepo, ces chemins n'existent plus. Hors du poste du développeur, `export_comptabilite_test.dart` échoue (3 tests) et d'autres tests se mettent en saut (32 sautés).
- **Proposition :** un seul résolveur de chemins (`test/chemins_depot.dart`) qui pointe sur `../agrierp_laravel/`.

### A8 ❓ Le prototype HTML n'est pas dans le monorepo

- Les `CLAUDE.md`, les outils de fixtures et plusieurs tests s'appuient sur `prototype_html/`, qui n'a pas été importé dans `massenon/agrierp`.
- Sans lui, la fidélité « prototype » n'est plus vérifiable que sur le poste du développeur.
- **Décision :** l'ajouter au dépôt (`prototype_html/` à la racine), ou acter que la vue Blade est désormais la seule référence (Doctrine, article 0) et retirer les dépendances au prototype.

### A9 ✅ Empreinte du plan comptable SYSCOHADA

- Le CSV du client (`database/data/plan-comptable-syscohada-revise.csv`) est en CRLF. Le premier commit l'avait converti en LF, ce qui faisait échouer `ImportPlanSyscohadaTest`.
- Rétabli octet pour octet et protégé par `-text` dans `.gitattributes`.

---

## Sprint 3 — Finalisation Élevage (web ↔ poste)

| # | Ticket | Statut |
|---|---|---|
| 3.F1 | **F0.96** — fiche Lapins du poste : saisie ventilée (morts et dons par catégorie, passage sevré → jeune), miroir du ticket 15.41 | 🔧 Bloquant : tant qu'il n'est pas livré, une fiche du poste avec morts ou dons sur une bande « à départ » est **refusée** (D7). |
| 3.F2 | **F0.97** — fiche Porcs du poste : même chose, miroir du ticket 15.42 | 🔧 Bloquant (même motif) |
| 3.F3 | Décisions D5 (qui déverrouille un départ erroné), D6 (bandes déjà saisies), D15 (« Porc Marchand » / « Jeune porc »), confirmation de D2/D8/D9/D12 | ❓ |
| 3.F4 | Mise en service **simultanée** du serveur (15.39–15.42) et du poste (F0.95–F0.97) | 🔧 À planifier avec l'exploitant |
| 3.F5 | Tests de cascade pour Escargots et Reproducteurs en parité exécutée PHP ↔ Dart (`test/php_laravel.dart`) | 🔧 |
| 3.F6 | A2, A3, A4 ci-dessus (transferts, dons reçus, transformation) | ❓ puis 🔧 |
| 3.F7 | Suivi de reproduction : la mise-bas (`saveMiseBas`) n'alimente aucune fiche. Les nés vivants restent à saisir à la main dans la fiche du jour. Décider si la mise-bas écrit `ne` dans la fiche de la bande. | ❓ |

---

## Sprint B — Offline-first robuste et synchronisation

| # | Ticket | Statut |
|---|---|---|
| B1 | Écran **Synchronisation** (`lib/features/sync/synchronisation_screen.dart`) | ✅ existe : en attente, conflits avec motif, dernier état, bouton « Synchroniser ». |
| B2 | Synchronisation **déclenchée automatiquement** : au retour du réseau, à intervalle (15 min, configurable dans Paramètres du poste) et à la fermeture de l'application. Jamais bloquante ; hors ligne = état normal, pas une erreur rouge. | 🔧 |
| B3 | Écran Synchronisation : historique des dernières tentatives (date, poussés / tirés / refusés), filtre des conflits par table, relance d'un conflit après correction, export du journal pour le support. | 🔧 |
| B4 | Indicateur permanent dans `BarreSuperieure` : nombre d'enregistrements en attente et âge de la dernière synchronisation réussie. | 🔧 |
| B5 | Sauvegarde locale de la base Drift (copie datée dans `Documents\AgriERP\sauvegardes`, rotation 7 jours) avant toute migration de schéma et chaque jour. | 🔧 |
| B6 | Couches DDD : migrer progressivement les repositories qui renvoient des lignes Drift vers des entités de domaine (Doctrine §1.3), écran par écran et jamais en lot. | 🔧 continu |

---

## Sprint C — Clôture de caisse ❓

> ⚠️ **Fonctionnalité absente du prototype ET de l'application web.** Aucune « clôture de caisse » n'existe aujourd'hui. Par l'article 0 de la doctrine, elle doit être **définie et construite d'abord sur le web**, puis portée. À valider par le client avant tout code.

**Proposition à valider :**

| # | Ticket |
|---|---|
| C1 | Web : écran « Clôture de caisse » (caissier). Ventes du jour par mode de paiement, fond de caisse, montant compté et écart. L'écart passe par une Action dédiée qui génère l'écriture SYSCOHADA (perte ou gain de caisse) via `AccountingEntryService::record()`. |
| C2 | API : table `cash_closures` (UUID), poussée par le poste et **jamais fusionnée** (comme les ventes). |
| C3 | Poste : écran porté à l'identique. La validation de la clôture **déclenche une synchronisation** (B2). Hors ligne, la clôture reste `pending` et l'écran le dit. Une clôture validée verrouille les ventes du jour sur le poste. |
| C4 | Tests : écriture d'écart équilibrée au centime ; synchronisation déclenchée ; clôture hors ligne conservée puis envoyée. |

---

## Sprint D — Build et distribution Windows

| # | Ticket | Statut |
|---|---|---|
| D1 | `agrierp_flutter/build_windows.bat` : enchaîne dépendances, génération Drift, analyse, tests, `flutter build windows --release`, copie du runtime VC++, puis installateur Inno Setup (`installer/agrierp.iss`) → `installer\Output\AgriERP-Setup-<version>.exe` | ✅ écrit le 17/10/2026, **pas encore exécuté sur une machine Windows** |
| D2 | Première exécution réelle sur le poste de compilation ; vérifier l'installation sur un Windows 10 vierge, sans redistribuable VC++ | 🔧 |
| D3 | CI GitHub Actions `windows-latest` : analyse, tests, build, installateur publié en artefact à chaque tag `v*` | 🔧 |
| D4 | Signature du code de l'exécutable (certificat éditeur), pour éviter l'alerte SmartScreen | ❓ achat du certificat |
| D5 | Mise à jour du poste : l'installateur réutilise le même `AppId` ; la base locale (profil utilisateur) n'est jamais touchée par une mise à jour ou une désinstallation | ✅ prévu dans `agrierp.iss`, 🔧 à vérifier en réel |

**Cloner et compiler** (sur le poste Windows de compilation) :

```bat
git clone https://github.com/massenon/agrierp.git
cd agrierp\agrierp_flutter
build_windows.bat
```

Prérequis : Flutter stable, Visual Studio 2022 (charge « Développement Desktop en C++ »), Inno Setup 6.

---

## Sprint E — Design system unifié

| # | Ticket |
|---|---|
| E1 | `BaseButton` unique (taille, padding, rayon), mesuré sur la vue web. Migration de tous les boutons d'action, puis garde-fou dans `conformite_portage_test.dart`. |
| E2 | Pagination standard (10 ou 25 lignes). ⚠️ Absente du web : la construire d'abord en composant Blade, puis la porter. |
| E3 | ❓ Charte des en-têtes de tableau. La consigne mentionne un fond `#0f172a` que ni le web ni le prototype n'utilisent : décider sur le web d'abord (voir Doctrine §2). |
| E4 | Contrôle des libellés de cartes KPI sur toutes les pages (faiblesse connue n° 2 du `CLAUDE.md` Flutter). |

---

## Sprint F — Localisation (zéro chaîne en dur)

| # | Ticket |
|---|---|
| F1 | Web : créer `lang/fr/*.php` et migrer les libellés Blade **module par module**, en commençant par Élevage. |
| F2 | Poste : fichiers ARB (`lib/l10n/app_fr.arb`) générés depuis `lang/fr` par un script, pour garantir la parité des clés. |
| F3 | Adapter `fidelite_libelles_test.dart` pour comparer les **clés** et non plus les littéraux. |

Les deux côtés migrent **ensemble**, module par module, sinon la parité est perdue.

---

## Sprint G — Production web

| # | Ticket |
|---|---|
| G1 | Pointer la racine documentaire de l'hébergement sur `public/` (aujourd'hui la racine du projet, protégée seulement par le `.htaccess` racine). |
| G2 | Déployer les tickets 15.5 à 15.42 (la production tourne avec le build du ticket 15.4). |
| G3 | Vérifier **sur le disque** du serveur que `agrierp.zip` (qui contient `.env`) est supprimé, puis régénérer les clés exposées (`APP_KEY`). Les archives et `.env.dusk.local` ont été retirés du dépôt Git le 17/10/2026, mais restent dans l'historique. |

---

## Décisions client en attente (récapitulatif)

| Ref. | Question |
|---|---|
| A2 / D6 | Transfert entre bandes (portées, sevrés) ; correction des bandes déjà saisies. |
| A3 | Les dons **reçus** sont-ils des entrées (nouvelle colonne) ou des achats ? |
| 3.F7 | La mise-bas alimente-t-elle automatiquement la fiche du jour ? |
| D5, D15, D2/D8/D9/D12 | Voir ticket F0.95 dans `README_SPRINT0.md`. |
| C | Périmètre exact de la clôture de caisse (absente du prototype). |
| E3 | En-têtes de tableau sombres ou charte actuelle du web. |
| RBAC | 7 rôles (CDC) contre 4 implémentés. |

---

## Ordre recommandé

1. A1 ✅, A6 ✅ et A9 ✅, puis A5 et A7.
2. Décisions A2, A3 et 3.F7 avec l'exploitant.
3. F0.96 et F0.97, puis mise en service simultanée (3.F4).
4. D2 : premier installateur réel.
5. B2 à B4 : synchronisation automatique et visibilité.
6. C : clôture de caisse, une fois validée.
7. E, F et G en continu.
