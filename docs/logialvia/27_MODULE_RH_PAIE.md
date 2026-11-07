# 27 — MODULE RH & PAIE (OPTION : employés, stagiaires, pointage, paie) — absent de logialvia, présent dans AgriERP

## USAGE

- **Statut du module : CONDITIONNEL.** B1 §6 déclare « module de paie et ressources humaines » HORS PÉRIMÈTRE de logialvia (« non présent dans le prototype de référence »). AgriERP possède ce module complet. Ce fichier est donc une **proposition de portage à ne construire QUE si le client répond OUI à Q-RH-1** (`10_BRS_BUSINESS_REQUIREMENTS.md` §6, BR-033). Tant que non tranché : ne rien construire, ne rien promettre ; aucune route `/rh` dans `20_MODULES_INDEX.md`.
- **Quand l'utiliser** : après décision du client, au jalon W8 (la paie écrit en comptabilité) ; prérequis : `26_` (écriture de paie, exercice ouvert), `29_` (droits), `25_` (compte de trésorerie).
- **Ordre** : `26_` → **`27_`** → `28_` (états de paie).
- **Entrées (toutes AgriERP, aucune règle ALLMANY)** : `docs/prd/rh-crud-poste.md`, `agrierp_laravel/app/Services/{PayrollCalculationService,ReglementPaieService,BaremeItsService}.php`, `agrierp_laravel/app/Actions/{SaisieEmployeAction,SaisieStagiaireAction,RecordPayrollAccountingEntryAction}.php`, `agrierp_laravel/app/Livewire/RH/{PersonnelStagesHub,RegistreEmployes,RegistreStagiaires,FeuillePointage,GestionPaie,Attestations}.php`, `agrierp_laravel/database/seeders/IncomeTaxBracketsSeeder.php`, `agrierp_flutter/test/paie_parite_php_test.dart` (cité par le PRD), `docs/prd/attestation-fidelite-signataires.md`. Règle de logialvia correspondante : `15_REGLES_METIER.md` §6.
- **Sorties (si accepté)** : migrations `employees`, `internships`, `internship_absences`, `attendance_records`, `payslips`, `payslip_requests`, `income_tax_brackets` + taux dans `company_settings` ; Actions/Services ; composants Livewire ; vues ; poste ; tests.
- **Chemins** : sans préfixe = `/home/user/agrierp` ; `logialvia/…` = `/home/user/massenon/logialvia/…`.

---

## 1. Objectif (si le module est retenu)

Tenir le registre du personnel, pointer, calculer la paie selon le droit béninois (CNSS, ITS), émettre un bulletin et son écriture comptable. **Rien ci-dessous n'est confirmé par ALLMANY.**

## 2. Écrans proposés (hub « Personnel & Stages », 5 onglets d'AgriERP)

| Route proposée | Écran | Rôles | Droit web | Note |
|---|---|---|---|---|
| `/rh` | Hub Personnel & Stages | A | view-rh | nouveau droit `view-rh`/`manage-rh` ; le rôle « comptable » existe (DV-07) mais son accès RH n'est pas défini (Q-DV-7, Q-RH-1) → admin seul en attendant |
| (onglet) | Registre Employés | A | manage-rh | |
| (onglet) | Registre Stagiaires | A | manage-rh | |
| (onglet) | Feuille de Pointage | A | manage-rh | |
| (onglet) | Gestion de la Paie | A | manage-rh | écrit en comptabilité |
| (onglet) | Attestations | A | view-rh | document officiel, signataires |

## 3. Composants, formulaires et validations (reprise du PRD d'AgriERP ; libellés des Blade)

**Registre Employés** : 2 cartes (effectifs, masse) ; 6 colonnes (prénom/nom, fonction, embauche, salaire, statut, actions) ; modale « Nouvel Employé » : Prénom * (≤ 100), Nom * (≤ 100), Fonction * (5 valeurs d'AgriERP : à redéfinir pour ALLMANY, Q-RH-2), Date d'embauche *, Salaire de base (FCFA) (≥ 0 ou vide), Statut (actif / congé / suspendu) ; archivage logique (`is_active = false`, audit `employee.archived`) ; un employé archivé est en lecture et n'est ni compté ni pointable ; filtre « Archivé ».
**Registre Stagiaires** : Prénom *, Nom *, Établissement * (≤ 150), Date de début *, Date de fin (vide ou ≥ début), Frais (≥ 0 ou vide), Frais réglés ; statut « En cours / Terminé » DÉRIVÉ de la date de fin ; absences saisies/archivées. Pas de pointage de stagiaire (décision AgriERP 8.1).
**Feuille de Pointage** : employé *, date * (≤ aujourd'hui), arrivée/départ `HH:mm`, statut (présent, absent, retard, congé, maladie) ; un seul pointage par (employé, jour) (upsert) ; archivable ; un pointage archivé ne retient plus d'absence ; aucune limite d'ancienneté (RH-Q3 d'AgriERP).
**Gestion de la Paie** : lignes par employé actif pour le mois choisi ; 9 colonnes (brut, absences, retenue, salaire dû, CNSS salariale, net imposable, ITS, net, état) ; 4 cartes (Masse salariale = Σ brut ; Charges CNSS = Σ CNSS salariale ; Bulletins émis = lignes réglées ; En attente = lignes non réglées) ; « Valider le règlement » par employé : bulletin + mouvement de trésorerie + écriture + audit dans UNE transaction (`ReglementPaieService`) ; refus : exercice clos, employé archivé ; jours d'absence = pointages `absent` ACTIFS du mois.

## 4. Règles de calcul

Formules, barème et cas calculés à la main (A : brut 200 000 → net 177 380 ; B : brut 130 000, 2 absences → net 110 112 ; C : brut 50 000 → net 48 200) : **`15_REGLES_METIER.md` §6** (ne pas les recopier ici). Écritures de paie : uniquement au serveur (`RecordPayrollAccountingEntryAction`), charge au dernier jour de la période (ou au jour du règlement s'il est antérieur), exercice ouvert exigé pour les DEUX dates. Barème ITS en base (modifiable), jamais en dur ; si aucun barème n'est renseigné : l'afficher (`bareme_its_renseigne = faux`), jamais un ITS nul silencieux. **À DÉFINIR AVEC LE CLIENT** : Q-RH-1 (le module entre-t-il ?), Q-RH-2 (fonctions, effectif, rôles), Q-PAI-2 (barème ITS et taux CNSS/VPS d'ALLMANY : ceux d'AgriERP sont validés par un AUTRE client), Q-PAI-3 (jours ouvrés, 26 chez AgriERP), Q-PAI-4 (stagiaires et pointage utiles ?), Q-PAI-5 (compte de trésorerie du règlement : le premier actif comme AgriERP ou un choix ?).

## 5. Hors ligne et synchronisation (proposé)

| Table | Poste | Règle |
|---|---|---|
| `employees`, `internships`, `internship_absences` | mixtes, hors ligne | `SaisieEmployeAction`/`SaisieStagiaireAction` (points uniques) ; ligne identique acquittée sans écrire ; archivé non modifiable |
| `attendance_records` | mixte | upsert (employé, jour) ; `is_active=false` archive ; famille paginée servie en entier |
| `payslip_requests` | DEMANDES locales | `ReglementPaieService::valider()` idempotent (bulletin déjà là = acquitté) ; refus avec motif |
| `payslips` | tirée (vue réduite pour `view-rapports`, colonnes RH pour `view-rh`) | jamais écrite au poste |
| `income_tax_brackets`, taux de paie | référentiel tiré | serveur gagne |
Le salaire de base ne descend qu'aux comptes `view-rh`.

## 6. Critères d'acceptation (si retenu)

- [ ] Cas A, B, C de `15_` §6 exacts au centime.
- [ ] Un règlement refusé dans un exercice clos n'écrit ni bulletin, ni écriture, ni trésorerie.
- [ ] Un pointage archivé ne retient plus d'absence (test de mutation : inverser `is_active` fait rougir un test).
- [ ] Sans barème en base : indication visible, pas d'ITS nul silencieux.
- [ ] Un caissier/animalier : aucun accès, ni au web ni au poste.

## 7. Tests (modèles AgriERP à lire)

`agrierp_laravel/tests/Feature/{SyncRhCrudTest,SyncPointageTest,SyncPaieDemandeTest,CyclePaieComptableTest,SyncDepensesPaieTirageTest,AttestationSignatairesTest,ApiAttestationsTest}.php` ; poste : `agrierp_flutter/test/personnel_crud_test.dart`, `paie_parite_php_test.dart` (20 cas aléatoires contre le vrai PHP) — vérifier par `ls agrierp_flutter/test | grep -i -E 'paie|personnel'`.

## 8. PROMPT de construction (à n'exécuter qu'après « OUI » du client à Q-RH-1)

> Construis le module **RH & Paie** de LogiALVIA d'après ce fichier et `15_REGLES_METIER.md` §6, en reprenant la structure d'AgriERP sans en reprendre aucune valeur non validée par ALLMANY. Lis `20_` §7, `docs/prd/rh-crud-poste.md`. **Ordre** : **(1) migration** (UUID partout, `device_id`, `sync_status`, `is_active` ; `income_tax_brackets` seedé VIDE ou avec le barème validé par ALLMANY) ; **(2) modèles** ; **(3) Actions/Services** : `PayrollCalculationService::calculer(brut, joursAbsence, joursOuvres)` (UNE source du bulletin), `SaisieEmployeAction`, `SaisieStagiaireAction`, `ReglementPaieService` (bulletin + trésorerie + écriture + audit, une transaction), `RecordPayrollAccountingEntryAction` ; **(4) composants Livewire** `RH\{PersonnelStagesHub,RegistreEmployes,RegistreStagiaires,FeuillePointage,GestionPaie}` ; **(5) vues** ; **(6) poste** : tables Drift UUID, `payslip_requests` locales, calcul Dart avec parité exécutée contre le vrai PHP ; **(7) tests** du §7 et cas A/B/C. **Interdits** : barème ou taux en dur, ITS calculé sur le brut, charge patronale placée en retenue (ou l'inverse), écriture de paie écrite au poste, salaire servi à un compte sans `view-rh`, suppression physique d'un employé.
