# docs/logialvia — Dossier de prompts pour créer le WEB de LogiALVIA avec Claude Code

> Ce dossier est un jeu de **prompts réutilisables** : chaque fichier commence par un en-tête **USAGE** (quand l'utiliser, dans quel ordre, entrées requises, sorties attendues), puis un prompt prêt à copier (rôle, contexte, tâches numérotées, contraintes, critères d'acceptation vérifiables, interdits), avec les chemins de référence RÉELS de LogiAgriERP et de LogiALVIA.
> Il complète, sans le réécrire, `GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md` (le guide des 21 blocs de portage d'AgriERP vers LogiALVIA) : on y renvoie, on ne le duplique pas.

Convention de chemins : `logialvia/` = le dépôt public `massenon/logialvia` (cloné en LECTURE SEULE dans `/home/user/massenon/logialvia`) ; `agrierp_laravel/`, `agrierp_flutter/`, `docs/` = le monorepo LogiAgriERP (`/home/user/agrierp`) ; « (à créer) » = n'existe pas encore.

---

## 1. Réponse en tête : quelle architecture, quel stack, quelles librairies, quelle conformité de design ?

1. **Architecture** : application Laravel 12 + Livewire 3, plate et pragmatique (`app/Livewire/{Module}`, `Actions`, `Services`, `Models`, `Support`) ; PAS d'hexagonal/DDD au web (le Flutter garde ses trois couches par module).
2. **Points de passage uniques** : `AccountingEntryService::record()` pour toute écriture comptable, `AdjustStockAction::execute()` pour tout mouvement de stock, passerelle MeCeF résolue par sa fabrique ; contourner l'un d'eux casse un invariant invisible.
3. **Données** : MySQL/MariaDB, clés UUID partout (`users.id` compris, `uuidMorphs` pour Spatie), suppression logique seulement, schéma PARTAGÉ avec le poste Drift.
4. **Droits à deux niveaux** : route `auth` + `can:view-*`, puis `$this->authorize('manage-*')` en première ligne de toute méthode qui écrit ; quatre rôles (`admin`, `comptable`, `caissier`, `animalier` : TRANCHÉ DV-07).
5. **Navigation rapide « comme Vue/Node »** : `wire:navigate` de Livewire 3 (mode SPA-like) + barre de progression + `@persist` pour les toasts, le verrou de session, l'invitation PWA ; ni Vue, ni Inertia, ni Node en production.
6. **Stack** : PHP 8.3, Laravel 12.65, Livewire 3.8, Sanctum 4 (jeton par poste), Spatie Permission 7, Tailwind 3.4 + PostCSS + Vite 5, Alpine fourni par Livewire (jamais démarré à la main), Material Symbols Outlined local.
7. **Librairies Composer (liste fermée)** : `laravel/framework`, `livewire/livewire`, `laravel/sanctum`, `spatie/laravel-permission`, `barryvdh/laravel-dompdf` ; conditionnelles : `simple-qrcode` (QR), `maatwebsite/excel` (tableur, seulement si le client le confirme) ; dev : Dusk, Pint, PHPUnit. **Pas** de Reverb (jamais câblé chez AgriERP).
8. **Librairies npm** : `vite`, `laravel-vite-plugin`, `tailwindcss`, `postcss`, `autoprefixer`, `@tailwindcss/forms`, `alpinejs` + `@alpinejs/collapse` (plugin sur l'instance Livewire), `node --test` pour la logique JS pure. Toute autre dépendance demande une justification écrite.
9. **Hors ligne et synchro** : le poste Flutter Windows (Drift/SQLite) reste le client hors ligne ; il synchronise par `/api/sync/pull` et `/api/sync/push` ; la PWA web est volontairement étroite (aucune page authentifiée en cache).
10. **Hébergement** : cPanel mutualisé présumé (à confirmer), racine du document = `public/`, `.htaccess` canonique, un seul cron `schedule:run`, `.env.production.example`, files et cache en base.
11. **Aucun CDN** : polices (Roboto variable, locale) et icônes (sous-ensemble Material Symbols) servies par le site ; aucune requête externe au chargement.
12. **Conformité de design** : chaque conteneur, ligne, colonne, espacement, alignement, animation et hiérarchie visuelle est IDENTIQUE au poste LogiALVIA : charte marine `#1F3864` + or `#B58B2A` (15 couleurs), espacements `xs/sm/md/lg/xl` = 4/8/16/24/32 px, `text-xs` = 13,6 px, rayon 8 px, modale ombre `shadow-xl`.
13. **Responsive sur 4 classes** : Desktop ≥ 1280, Laptop 1024–1279, Tablet 641–1023, Mobile ≤ 640 (tableaux en cartes à 640 px exactement, barre latérale à `lg`=1024, KPI en 4 colonnes dès 768).
14. **Preuve de conformité** : jetons partagés comparés par test, gardes qui lisent les sources (`conformite_structure`, `fidelite_libelles`), captures de référence à cinq largeurs, check-list K2 écran par écran, audit de conformité par écran (prompt B de `04_UI_UX_DESIGN_SYSTEM.md`).
15. **Règle d'or** : rien d'inventé. Toute règle absente des sources et des décisions validées (`16_DECISIONS_VALIDEES.md`) (barème Goliaths, taux de ration des poissons, plan comptable, périmètre du comptable…) est marquée « À DÉFINIR AVEC LE CLIENT » avec une question précise ; les valeurs d'AgriERP ne remplacent JAMAIS celles de LogiALVIA.

---

## 2. Index des fichiers

| Fichier | Rôle | Quand le lancer | Dépend de |
|---|---|---|---|
| `README.md` | Index, ordre d'exécution, convention d'usage, glossaire | En premier, pour s'orienter | — |
| `GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md` | Guide des 21 blocs de portage (existant, ne pas réécrire) : état des lieux de logialvia, tableau récapitulatif, ordre de portage, pièges, questions au client | Avant tout ticket de portage ; relu à chaque bloc | — |
| `01_MASTER_PROMPT.md` | Instructions de base de Claude Code pour le web : mission, hiérarchie des sources, méthode, contraintes, interdits, format de rapport, définition de « terminé », particularités des filières | Début de CHAQUE session (ou dans le `CLAUDE.md` racine) | guide de portage |
| `02_ARCHITECTURE_WEB_ET_STACK.md` | Architecture à respecter, stack, dépendances exactes, `wire:navigate`/`@persist`, sécurité de base, hébergement, schéma web-poste, arbre de dossiers | Au socle serveur (W0) et à chaque ajout de dépendance | 01 |
| `03_DEVELOPMENT_STANDARDS.md` | Conventions Laravel/Livewire/JS/Tailwind, validation, sécurité, notifications, git, tests, qualité, revue | Au socle puis comme grille de revue de chaque ticket | 01, 02 |
| `04_UI_UX_DESIGN_SYSTEM.md` | Charte (jetons, typo, grille, composants, animations), responsive 4 classes, règle de conformité web-poste, recette visuelle, prompt d'audit de conformité | Au socle (création du design system) puis à chaque écran (audit) | 01, 02, 03 |
| `10_BRS_BUSINESS_REQUIREMENTS.md` | Exigences métier (BR-nnn) | Après 01-02, avant les modules | 01, 02 |
| `11_PRD_PRODUCT_REQUIREMENTS.md` | Exigences produit | Après 10 | 10 |
| `12_SRS_SOFTWARE_REQUIREMENTS.md` | Exigences logicielles | Après 11 | 11 |
| `13_FRS_FUNCTIONAL_REQUIREMENTS.md` | Exigences fonctionnelles | Après 12 | 12 |
| `14_NFRS_NON_FUNCTIONAL_REQUIREMENTS.md` | Exigences non fonctionnelles (performance, sécurité, disponibilité…) | Après 12-13 | 12, 13 |
| `15_REGLES_METIER.md` | Règles métier numérotées (BR-XXX-NNN : effectifs, ventes, stocks, comptabilité…) | Avant tout module qui calcule | 10 à 14 |
| `16_DECISIONS_VALIDEES.md` | Registre des décisions validées par le client le 08/11/2026 (DV-01 à DV-22 : ration des poissons en % de biomasse, vente de poisson kg + sujets, pintades/incubation 28 j, seuils d'autonomie 7 j/3 j, corbeille sans écritures, droits du caissier, 4 rôles ; DV-08 à DV-11 validées par le client : retours du caissier, libellé « Poussins », départ par stade à l'ouverture de la fiche, règles d'incubation modifiables ; DV-12 à DV-14 recommandées, à confirmer avec le technicien ; DV-15 valeurs par défaut, remplacées par DV-20 ; DV-16 à DV-22 recommandées et ADOPTÉES par le client (« je vais suivre »), à confirmer sur le terrain : phase 0 PWA, incubation et protocole, délai fournisseur de provende, barème poissons provisoire, responsable stock et comptable, prix périmés, libellés des modes de règlement) ; ce qui reste À DÉFINIR ; repères zootechniques = ordres de grandeur à valider | Avant tout calcul de ration, de vente de poisson, d'incubation, d'autonomie, et avant toute matrice de droits | 10 à 15 |
| `20_MODULES_*` | Un prompt PAR MODULE (pilotage, élevage, commercial, stocks, achats, comptabilité, rapports, administration, compte) | Un module par session, dans l'ordre du guide de portage | 01 à 04, 15, 30 |
| `30_DATABASE_ENGINEERING.md` | Schéma partagé UUID, migrations, migration des données existantes du poste, seeders | Avant la première migration métier | 02, 15 |
| `31_TESTING_QA.md` | Stratégie de tests, jeux de cas, parité web-poste, recette, mutation | Avant de coder un module, puis à chaque ticket | 03, 15, 20 |
| `32_SKILLS_LIBRARY.md` | Skills Claude Code du dépôt (`prd`, `plan`, audit…) adaptés à LogiALVIA | Une fois au démarrage, avant le premier ticket | 01, 03 |
| `40_PWA_HORS_LIGNE.md` | PWA étroite existante et conception d'un éventuel hors ligne (à valider) | Seulement si le client le confirme | 02, 30, 43 |
| `41_MECEF_EMECEF.md` | Facturation normalisée e-MECeF : passerelle, modes, construction de la charge utile | Module Ventes/Facturation | 02, 15, 20 |
| `42_CONFIG_MECEF_SMTP_LOGO_FAVICON.md` | Réglages d'administration : MeCeF, SMTP, logo, favicon (secrets chiffrés) | Module Administration | 02, 03, 41 |
| `43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md` | Appairage du poste, synchronisation, modale de synchro, alertes | Après le socle et les premiers modules | 02, 30, 15 |

Les fichiers 10 à 16, 20 à 32 et 40 à 43 sont rédigés par d'autres sessions ; on les désigne ici par leur nom, sans en recopier le contenu. Un fichier cité mais absent du dossier est « à produire » : ne PAS l'inventer, le demander.

---

## 3. Ordre d'exécution des prompts

```
Phase 0  Cadrage          README -> GUIDE_PORTAGE -> 01_MASTER_PROMPT
Phase 1  Exigences        10 BRS -> 11 PRD -> 12 SRS -> 13 FRS -> 14 NFRS -> 15 REGLES_METIER -> 16 DECISIONS_VALIDEES
Phase 2  Socle web (W0)   02 ARCHITECTURE -> 03 STANDARDS -> 04 DESIGN SYSTEM -> 30 DATABASE -> 31 TESTING -> 32 SKILLS
Phase 3  Modules          20_MODULES_* (un module = une session, ordre du guide de portage)
Phase 4  Intégrations     43 APPAIRAGE/SYNCHRO -> 41 MECEF -> 42 CONFIG -> 40 PWA (si confirmé)
Phase 5  Recette          audit de conformité écran par écran (04, prompt B) + 31 recette + corrections
```

Ordre de portage des blocs (repris du guide, §1) : socle serveur + schéma UUID (14, 8) -> appairage (15) -> synchronisation (16) -> modale de synchronisation (17, avec 3 et 4) -> bandes (12) -> fiches par filière (1) -> rationnement (5) -> prophylaxie et rappels (6) -> clôture, seuils, aide (11, 13) -> import/export (7) -> notifications (18) -> MeCeF (19) -> installateur (10) -> PWA (20) et import xlsx (21) seulement si confirmés. Voir le tableau récapitulatif du guide pour les dépendances exactes.

Règles de séquencement :
- Aucun module (`20_MODULES_*`) avant que 01, 02, 03, 04, 15, 16 et 30 aient été exécutés et relus.
- Aucune migration métier avant la décision sur la langue des noms de tables (voir `03_DEVELOPMENT_STANDARDS.md`, « À DÉFINIR ») et sur les UUID du poste.
- Aucun écran « terminé » sans l'audit de conformité de design (prompt B de `04_UI_UX_DESIGN_SYSTEM.md`) et sans la définition de terminé de `01_MASTER_PROMPT.md`.

---

## 4. Convention d'usage avec Claude Code

1. **Une session = un ticket = un prompt.** Ouvrir une session neuve par ticket. Coller en premier le bloc « PROMPT (à copier) » du fichier choisi (ou le référencer par son chemin : « suis `docs/logialvia/02_ARCHITECTURE_WEB_ET_STACK.md`, PROMPT, tâche T3 »). Le `CLAUDE.md` du dépôt LogiALVIA (à créer) renvoie au MASTER PROMPT, de sorte que chaque session en hérite.
2. **Lire avant d'écrire.** Chaque prompt demande de lire les fichiers sources EN ENTIER. Un chemin cité qui n'existe pas (`ls`) est une erreur à signaler, pas à contourner.
3. **Plan avant code.** Skills `prd` puis `plan` (modèles : `.claude/skills/prd/SKILL.md`, `.claude/skills/plan/SKILL.md` du monorepo AgriERP ; à copier et adapter dans le dépôt LogiALVIA). Annoncer le plan, attendre l'accord si le ticket est ambigu.
4. **Vérifier avant de dire « terminé ».** Tests exécutés (`php artisan test --testsuite=Feature`, Pint, `npm run build`) ; un chiffre se vérifie par recalcul indépendant ; un défaut qui vit dans le navigateur se vérifie en navigateur (Dusk), pas par `Livewire::test()`.
5. **Rien d'inventé.** Question précise au client plutôt que valeur plausible : marquer « À DÉFINIR AVEC LE CLIENT ».
6. **Périmètre strict.** Ne toucher que les fichiers du ticket. Ne pas modifier `logialvia/` (cloné en lecture seule). Pas de commit, pas de push, pas de PR sans demande ; jamais `pkill` ; jamais d'action destructive sur une base réelle.
7. **Rapport au format du MASTER PROMPT** (ticket, fait, vérifié, non fait, écarts, questions, risques), court et factuel.
8. **Documentation vivante.** Un doc faux découvert en route se corrige dans le même ensemble de changements (A2 §7 de logialvia) ; ces prompts eux-mêmes se mettent à jour quand une source change.
9. **Sources en conflit** : on suit la hiérarchie du MASTER PROMPT (web validé -> poste/prototype -> docs de logialvia -> règles d'AgriERP) ; une contradiction se documente et se fait trancher, elle ne se résout pas en silence.
10. **Particularités LogiALVIA** : six filières déjà configurées (`goliaths`, `pintades`, `lapins`, `poissons-chats`, `poulets`, `pondeuses`) pilotées par UN écran générique ; le barème Goliaths est « non confirmé » dans les sources (question au client avant tout calcul de ration) ; la ration des poissons-chats est TRANCHÉE en % de biomasse (DV-01), ses taux restent des repères à valider.

---

## 5. Glossaire court

| Terme | Sens |
|---|---|
| **LogiALVIA** | Gestion intégrée d'ALLMANY ET COMPAGNIE (Natitingou, Bénin) : élevage, commerce annexe, stocks, achats, comptabilité, rapports ; Flutter Windows aujourd'hui, web à créer. |
| **LogiAgriERP / AgriERP** | Produit jumeau (Ferme École OLOUWACHEGOUN) : web Laravel + poste Flutter ; réservoir de patrons et de pièges déjà payés. |
| **Poste** | Client Flutter Windows hors ligne (Drift/SQLite). |
| **Web** | Application Laravel + Livewire, serveur de référence une fois un module validé. |
| **Doctrine de portage** | `docs/DOCTRINE_PORTAGE.md` : fidélité web <-> poste, « la vue web est la référence ». |
| **Filière** | Famille d'élevage : pisciculture (poissons-chats), pintades, goliaths, poulets, pondeuses, lapins. |
| **Fiche (journalière)** | Écran de saisie d'une filière : achats, nés, mortalité, ventes, effectif par catégorie, rationnement. |
| **Catégorie** | Tranche d'âge d'une filière (ex. Poussins / Goliathau / Mature), avec sa ration normative en g/j. |
| **Bande / lot** | Groupe d'animaux suivi ensemble. |
| **Point de passage unique** | Entrée obligatoire d'un mécanisme partagé (écriture comptable, stock, facture normalisée, mot de passe). |
| **UUID** | Identifiant unique universel : clé primaire de toute table synchronisable. |
| **Suppression logique** | Archivage (`is_active`/`status`), jamais de `DELETE` sur une donnée comptable ou zootechnique. |
| **Contre-passation** | Écriture inverse qui annule une écriture comptable (on ne la restaure pas). |
| **Livewire / `wire:navigate`** | Composants serveur réactifs ; navigation de page sans rechargement complet. |
| **`@persist`** | Marque un élément Blade qui survit au remplacement de la page par `wire:navigate`. |
| **Alpine** | Micro-framework JS embarqué par Livewire ; ne jamais le démarrer soi-même. |
| **Jeton (de design)** | Valeur nommée unique (couleur, espacement, rayon) dans `tailwind.config.js`, reflétée dans le poste. |
| **`data-label`** | Attribut de cellule qui donne son libellé à la vue mobile en cartes d'un tableau. |
| **Sanctum** | Jetons d'API, un par poste appairé. |
| **MeCeF / e-MECeF** | Facturation électronique normalisée (Bénin), via passerelle. |
| **Appairage** | Association d'un poste à un compte serveur (jeton + PIN local). |
| **PWA étroite** | Manifeste + service worker limité aux fichiers statiques ; ne rend pas le web utilisable hors ligne. |
| **À DÉFINIR AVEC LE CLIENT** | Marqueur obligatoire d'une règle absente des sources, avec une question précise. |
| **`ECART_DELIBERE:`** | Marqueur d'un écart assumé avec sa raison (convention de logialvia). |
| **BR-XXX-NNN** | Identifiant d'une règle métier dans `logialvia/docs/B6_Regles_Metier.md` (BR-ELV-001…). |
| **K2** | `logialvia/docs/K2_Checklist_Recette_Visuelle.md` : recette visuelle par écran. |
| **Desktop / Laptop / Tablet / Mobile** | Quatre classes d'écran du web : ≥ 1280, 1024–1279, 641–1023, ≤ 640 px. |

---

## 6. Constats importants à connaître avant de commencer

- Le prototype HTML de LogiALVIA (31 pages) n'est PAS dans le dépôt cloné (`logialvia/` ne contient que `docs/`, `logialvia_app/`, `logo/`) : plusieurs mesures visuelles restent « à confirmer » tant qu'il n'est pas fourni.
- Les outils `audit_typographie.py` / `apparier_typographie.py` cités par les docs de logialvia sont absents de `logialvia/logialvia_app/outils/`.
- LogiALVIA est en Roboto (variable, locale), marine/or ; AgriERP en Inter, vert/jaune : ne pas mélanger les chartes.
- Quatre rôles (TRANCHÉ DV-07, 08/11/2026 : `admin`, `comptable`, `caissier`, `animalier`) ; LogiALVIA n'en avait que trois (comptabilité réservée à `admin`).
- Aucun CSP ni analyse statique chez AgriERP : ce sont des propositions nouvelles, pas des acquis.
- Reverb et `maatwebsite/excel` figurent dans le `composer.json` d'AgriERP sans usage réel : ne pas les copier par réflexe.
- Contrastes mesurés sous le seuil AA dans la charte de LogiALVIA (or sur blanc 3,14:1, `outline` sur fond de page 4,32:1, `success-deep` sur son fond 4,24:1) : décision du client requise (`04_UI_UX_DESIGN_SYSTEM.md`, §2 et Q-DS-2).

## 7. Questions ouvertes majeures au client (détail dans chaque fichier)

1. Hébergement, sous-domaine, PHP 8.3, accès SSH (02).
2. Police : Roboto (poste) ou Inter (AgriERP) (02, 04).
3. Contrastes de la charte : or lisible sur fond clair, texte secondaire, badge succès (04).
4. Classes d'écran validées ; usage réel en tablette/mobile (04).
5. Barèmes de rationnement Goliaths ; taux de ration des poissons-chats en % de biomasse à valider par le technicien (DV-01) ; stades de passage ; plusieurs bandes par filière (01).
6. ~~Rôle `comptable` : oui/non~~ TRANCHÉ (DV-07) ; périmètre du comptable arrêté par DV-20 (Q-DV-7 tranchée par défaut recommandé). Autres questions nées des décisions : `16_DECISIONS_VALIDEES.md` §4 (fermées : Q-DV-6, Q-DV-8 ; fermées en « recommandé » : Q-DV-1, Q-DV-2, Q-DV-3, Q-DV-4 ; tranchées par défaut recommandé : Q-DV-5, Q-DV-7 (DV-20)).
7. Plan comptable (SYSCOHADA ?), PWA hors ligne, import xlsx, mode sombre (02).
8. Langue des noms de tables du schéma partagé (03).
9. Copie du prototype HTML (04).
