# PRD — CRUD RH au poste : Registre Employés, Registre Stagiaires, Feuille de Pointage, Gestion de la Paie
**Statut :** brouillon (livré par les tickets RH-1 à RH-4 le 27/10/2026 ; RH-Q1 à RH-Q3 en attente du client) · **Date :** 2026-10-27 · **Ticket(s) :** RH-1, RH-2, RH-3, RH-4 (nouveaux ; aucun ticket du `PLAN_FINALISATION.md` ne couvrait ces quatre onglets)

## 1. Problème
Le hub « Personnel & Stages » du poste a cinq onglets, mais **un seul écrit** : la feuille de pointage ne sait que *créer* un pointage du jour. Tout le reste est en lecture seule, avec une mention « se fait sur la surface web » :
- **Registre Employés** : impossible d'embaucher, de modifier un salaire, d'archiver (`personnel_stages_screen.dart`, `_actionInerte`, mention l. 253).
- **Registre Stagiaires** : impossible d'inscrire un stagiaire, de noter ses frais réglés, ni ses absences (`internship_absences` n'est pas tirée).
- **Feuille de Pointage** : pas de modification ni d'archivage d'un pointage, pas de date (toujours le jour).
- **Gestion de la Paie** : quatre cartes à « — », neuf colonnes dont six à « — », aucun bouton « Valider le règlement ».

Exemple réel : le 27/10/2026 à 7 h, le chef d'élevage pointe 12 employés hors ligne ; un nouvel ouvrier embauché la veille n'est pas dans la liste (créé au web seulement) — il n'est pas pointé, son absence sera retenue sur sa paie. Le même jour, un stagiaire absent n'est noté nulle part avant le retour du réseau.

La raison historique (ticket F0.55) était que ces écritures « ne laisseraient pas de trace d'audit » et que la paie « se calcule avec un barème que le poste ne reçoit pas ». Depuis, le modèle **« fait + rejeu serveur »** (dépenses U14, devis DEV, bandes BS1, avoirs AV1) répond aux deux objections : le poste écrit le fait, le serveur rejoue la règle dans son point de passage unique, audit compris.

## 2. Existant
| Onglet | Web (maître) | Poste |
|---|---|---|
| Employés | `Livewire\RH\RegistreEmployes` : `saveEmployee()` (prénom, nom, fonction parmi 5, embauche, salaire, statut actif/congé/suspendu), `archiveEmployee()` (`is_active=false`, audit `employee.archived`), export PDF. Blade : 2 cartes, 6 colonnes, modale. | Tirage `employees` (actifs seuls, salaire nul sans `view-rh`), remplacé à chaque tirage. Lecture seule. |
| Stagiaires | `RegistreStagiaires` : `saveInternship()` (prénom, nom, établissement, début, fin ≥ début, frais, frais réglés), `saveAbsence()` / `deleteAbsence()` (archivage, audit `internship_absence.archived`). Statut « En cours / Terminé » **dérivé** de `end_date` (`Internship::getIsActiveAttribute`). | Tirage `internships` (tous), remplacé. `internship_absences` non tirée. Lecture seule. |
| Pointage | `FeuillePointage` : `savePointage()` (employé, date, arrivée, départ, statut présent/absent/retard/congé), `updateOrCreate` sur (employé, jour), `archiveRecord()` (`is_active=false`, audit `attendance.archived`). | `PersonnelRepository.pointer()` (création du jour seulement) ; `pushAttendance` au serveur (upsert (employé, jour), date ≤ aujourd'hui) ; tirage des 60 derniers jours actifs. Pas de modification de date, pas d'archivage, `is_active` inconnu. |
| Paie | `GestionPaie` : lignes par employé actif pour `periodMonth` ; `PayrollCalculationService::calculer(brut, joursAbsence)` (CNSS salariale, ITS progressif sur `income_tax_brackets`, charges patronales depuis `company_settings`) ; `validerReglement()` : bulletin + décrément du **premier compte de trésorerie actif** + écriture 661 (`RecordPayrollAccountingEntryAction`), exercice ouvert exigé pour la charge (dernier jour de la période, EX5-Q4) et pour le règlement ; audit `payslip.paid`. | Tirage `payslips` réduit (nom, net, instant) aux seuls `view-rapports` (protection S3). Ni barème, ni taux. Cartes et colonnes à « — ». |

Prototype : `personnel-stages.html` (hub), `registre-employes.html`, `registre-stagiaires.html`, `feuille-pointage.html`, `gestion-paie.html` — tous avec boutons « + Nouveau », « Modifier », « Archiver » / « Valider ».

## 3. Utilisateurs et rôles
- `view-rh` : voit les quatre onglets (admin, comptable). `manage-rh` : écrit (admin ; comptable selon le seeder).
- Le caissier et l'animalier n'ont pas `view-rh` : ni au web ni au poste (RBAC du prototype, `PermissionsPoste`).
- Le salaire de base ne descend qu'aux comptes `view-rh` (déjà le cas) ; les bulletins complets (brut, retenues) ne descendront qu'à `view-rh` ; `view-rapports` garde la vue réduite actuelle.

## 4. Exigences fonctionnelles
- **EF1** Au poste, un employé se crée, se modifie et s'archive, hors ligne, avec les champs, listes et messages du web. Un employé créé au poste est pointable immédiatement.
- **EF2** Un stagiaire se crée et se modifie au poste (mêmes champs que le web) ; ses absences se notent et s'archivent au poste.
- **EF3** Un pointage se crée pour une date passée ou du jour, se modifie (heures, statut) et s'archive au poste. Un pointage archivé ne compte plus (cartes, absences de la paie).
- **EF4** L'onglet Paie du poste montre, pour le mois choisi, les mêmes neuf colonnes que le web avec les mêmes montants (ITS compris), les quatre cartes calculées, et « Valider le règlement » par employé.
- **EF5** Le règlement validé au poste est une **demande** : le serveur crée le bulletin, l'écriture, le mouvement de trésorerie, l'audit ; refus (exercice clos, employé archivé) → motif au poste.
- **EF6** Tout ce qui est écrit au poste part à la synchronisation suivante par les points de passage uniques du web (Actions partagées), jamais par une seconde implémentation.
- **EF7** Hors ligne est le mode normal : aucune action ne demande le réseau ; une ligne non envoyée se dit « Pas encore envoyé ».

## 5. Règles métier et calculs
- **Validation employé** (web, reprise) : prénom et nom requis (≤ 100), fonction requise, date d'embauche requise, salaire ≥ 0 ou vide, statut ∈ {actif, conge, suspendu}.
- **Validation stagiaire** : prénom, nom, établissement (≤ 150) requis, début requis, fin vide ou ≥ début, frais ≥ 0 ou vide.
- **Pointage** : un seul par (employé, jour) ; jour ≤ aujourd'hui ; statut ∈ {present, absent, retard, conge, maladie} ; heures « HH:mm ».
- **Paie** (`PayrollCalculationService`, jours ouvrés 26) :
  - retenue_absence = arrondi(brut / 26 × jours_absents, 2) ; salaire_dû = max(0, brut − retenue_absence)
  - cnss_salariale = salaire_dû × taux_cnss_salarié (3,6 % par défaut) ; net_imposable = salaire_dû − cnss_salariale
  - ITS = somme par tranche de (min(net_imposable, plafond) − plancher) × taux ; net = net_imposable − ITS
  - charges patronales = salaire_dû × (VPS 4 % + pensions 6,4 % + prestations familiales 9 % + risques 2 %) (taux de `company_settings`)
  - jours_absents = pointages `absent` **actifs** du mois.
  - **Exemple à la main** (taux par défaut, barème : 0–60 000 à 0 %, 60 000–150 000 à 10 %, > 150 000 à 15 %) : brut 120 000, 2 absences → retenue 9 230,77 ; dû 110 769,23 ; CNSS 3 987,69 ; imposable 106 781,54 ; ITS = (106 781,54 − 60 000) × 10 % = 4 678,15 ; net 102 103,39 ; charges patronales = VPS 4 430,77 + pensions 7 089,23 + prestations familiales 9 969,23 + risques 2 215,38 = **23 704,61** (somme des quatre parts arrondies, comme `PayrollCalculationService` ; 21,4 % du dû donnerait 23 704,615).
  - Masse salariale = Σ brut ; Charges CNSS = Σ cnss_salariale ; Bulletins émis = lignes réglées ; En attente = lignes non réglées.
- **Effets comptables** : uniquement au serveur (`RecordPayrollAccountingEntryAction`, charge au dernier jour de la période ou au jour du règlement s'il est antérieur ; exercice ouvert exigé pour les deux dates). Le poste n'écrit ni écriture ni trésorerie.
- **Archivage** : logique (`is_active=false`), audit `employee.archived` / `attendance.archived` / `internship_absence.archived` avec l'entité (Corbeille, ARC-Q2).

## 6. Hors ligne et synchronisation
| Table | Nature au poste | Envoi | Règle serveur |
|---|---|---|---|
| `employees` | **mixte** (+ `device_id`, `sync_status`, `updated_at`, `is_active`) | `pushEmployees` (`manage-rh`) | `SaisieEmployeAction` (créer / modifier / archiver) — point de passage de `RegistreEmployes` ; ligne identique acquittée sans écrire ; archivé ne se modifie pas |
| `internships` | mixte | `pushInternships` | `SaisieStagiaireAction` |
| `internship_absences` | mixte (nouvelle, tirée à `view-rh`) | `pushInternshipAbsences` | `SaisieStagiaireAction::absence()` / `archiverAbsence()` |
| `attendance_records` | mixte (+ `is_active`) | `pushAttendance` (existant, + `is_active`) | upsert (employé, jour) ; `is_active=false` archive |
| `payslip_requests` | demandes du poste (nouvelle, locale) | `pushPayslipRequests` | `ReglementPaieService::valider()` — point de passage de `GestionPaie::validerReglement()` ; idempotent (bulletin déjà là = acquitté) ; refus avec motif |
| `payslips` | tirée : vue réduite (`view-rapports`) + colonnes RH (`view-rh`) | jamais | — |
| `income_tax_brackets`, taux de paie de `company_settings` | référentiel tiré (`view-rh`) | jamais | serveur gagne |

Clés UUID créées au poste. Absorbeurs **stricts** ; une ligne `pending` / `conflict` n'est jamais écrasée par le tirage. Sans réseau : tout s'enregistre, part plus tard ; un refus devient `conflict` avec son motif et se relance (« Relancer »).

## 7. Interface
Web : inchangé (déjà complet). Poste : modales `ModaleAgri` avec les libellés exacts des Blade (« Nouvel Employé », « Prénom * », « Nom * », « Fonction * », « Date d'embauche * », « Salaire de base (FCFA) », « Statut » ; « Nouveau Stagiaire », « Établissement * », « Date de début * », « Date de fin », « Frais de stage (FCFA) », « Frais réglés » ; « Absences », « Date * », « Motif » ; « Enregistrer un Pointage », « Employé * », « Date * », « Heure d'arrivée », « Heure de départ », « Statut * » ; paie : sélecteur de mois, « Valider le règlement », pastilles « Réglé » / « En attente » / « Demande envoyée »). Colonnes et cartes inchangées ; icônes Modifier / Archiver remplacent `_actionInerte`.

## 8. Hors périmètre
- Export PDF des quatre onglets au poste (chaîne `ExportOfficiel` existante : ticket séparé).
- Pointage des stagiaires (un stagiaire n'est pas un employé : décision 8.1, inchangée).
- Choix du compte de trésorerie au règlement (le web prend le premier actif ; inchangé).

## 9. Questions ouvertes pour le client
- **RH-Q1** Le poste doit-il montrer les employés archivés (avec filtre) ou seulement les actifs comme le web ? *Proposition : actifs seuls, comme le web.*
- **RH-Q2** Le barème ITS semé n'a jamais été validé (note de `PayrollCalculationService`). Avant toute paie réelle, le faire valider par le cabinet FAGUEZ. *Proposition : afficher « barème ITS non renseigné » au poste comme au web tant qu'il est vide.*
- **RH-Q3** La paie d'un mois dont les pointages ont plus de 60 jours ne peut pas compter les absences au poste (seuls 60 jours sont tirés). *Proposition : limiter la validation au poste aux deux derniers mois ; au-delà, le web.*

## 10. Critères d'acceptation
- Laravel : `SyncRhCrudTest` (création / modification / archivage d'un employé, d'un stagiaire, d'une absence depuis le poste : effets, audit, idempotence, refus par rôle), `SyncPointageTest` (modification, archivage, `is_active` au tirage), `SyncPaieDemandeTest` (demande → bulletin + écriture + trésorerie ; renvoi acquitté ; exercice clos refusé avec motif ; tirage des colonnes RH à `view-rh` seulement).
- Flutter : `personnel_crud_test.dart` (dépôt : créer / modifier / archiver, `pending`, jamais écrasé par le tirage), `paie_parite_php_test.dart` (calcul Dart = PHP réel sur l'exemple du §5 et sur 20 cas aléatoires), `personnel_stages_test.dart` mis à jour (modales, boutons, pastilles), `migration_toutes_versions_test` (palier 67), `perimetre_tirage_test` (nouvelles tables).
- Mutation : inverser `is_active` dans l'absorbeur des pointages fait rougir le test « un pointage archivé ne retient plus d'absence ».
