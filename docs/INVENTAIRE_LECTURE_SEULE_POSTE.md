# Inventaire des fonctions d'écriture du web absentes du poste

**Date :** 2026-10-27 · **Demande du client :** « Faire l'inventaire des modules en lecture seule au niveau du poste et les convertir en CRUD, même logique que le web. Le poste doit avoir toutes les fonctions actives. » · **Doctrine :** article 5 (la vue Blade est le maître ; le poste reprend structure, composants, retours et logique métier à 100 %).

Méthode : chaque méthode mutante d'un composant Livewire (`$this->authorize(`, écritures Eloquent, appels d'Action / Service) a été croisée avec les méthodes des dépôts du poste qui écrivent en Drift ou appellent l'API, avec `AppDatabase.tablesEnvoyees`, `SyncController::CLES_DE_PUSH` et la liste `referentiels_ignored`. Chemins relatifs à la racine du dépôt ; P = `agrierp_flutter/lib/features/`, L = `agrierp_laravel/app/Livewire/`.

**Conclusion.** Le poste écrit déjà l'essentiel de l'Élevage, des RH (RH-1 à RH-4), de l'Administration, des Devis, des Retours / Avoirs, des fiches clients et fournisseurs, et — depuis UT-1 — les comptes utilisateurs. **Les vrais trous** : toute la **Comptabilité**, les autres **Paramètres de la ferme** (rôles, entreprise, modes de paiement, sauvegardes), les **Bons de commande**, l'**encaissement d'une créance** et les **relances**, l'archivage d'un **produit** et les **seuils d'alerte**, la modification / l'archivage d'une **avance**, la relance **MeCeF**, et plusieurs écrans web **sans équivalent** au poste (Immobilisations, Barème ITS, Intégrations SMS, Transformation, Profil client, Sauvegardes).

## 1. Comptabilité — entièrement en lecture au poste

| Écran web | Fonction d'écriture web | Poste | Table / synchro | Ticket |
|---|---|---|---|---|
| `Comptabilite\PlanComptable` | newAccount, editAccount, saveAccount, archiveAccount | **PRÉSENT depuis CP-1 (28/10/2026)** : `ComptabiliteRepository.creerCompte` / `modifierCompte` / `archiverCompte` ; serveur `PlanComptableService` | `chart_of_accounts` (v73, envoyée) | CP-1 ✅ |
| `JournalComptable` | newEntry, editEntry, saveEntry, archiveEntry (écriture manuelle) | **PRÉSENT depuis CP-2 (28/10/2026)** : `ComptabiliteRepository.creerEcriture` / `modifierEcriture` / `archiverEcriture` (demandes) ; serveur `SaisieEcritureManuelleAction` | `manual_entry_requests` (v74, envoyée) | CP-2 ✅ |
| `Immobilisations` | nouveau, editer, enregistrer, ouvrirCession, confirmerCession, passerDotation | **PRÉSENT depuis CP-3 (28/10/2026)** : carte « Immobilisations » du hub (`immobilisations_page.dart`), `ImmobilisationsRepository` (enregistrer, modifier, sortir, demander la dotation) ; serveur `ImmobilisationService` | `fixed_assets` (v75, mixte), `depreciation_requests` (v75, envoyée) | CP-3 ✅ |
| `ClotureExercice` | cloturerPeriode, decloturerPeriode, rouvrirExercice, ouvrirExerciceSuivant, soldeComptesGestion, confirmCloture | ABSENT : page de texte seul (`motifs[cloture]` l. 110-114) | `fiscal_years` — « jamais synchronisée » (en-tête du `SyncController`) | CP-4 (en ligne, par API) |
| `RapprochementBancaire` | importReleve | ABSENT : `motifs[rapprochement]` l. 123-125 | aucune | CP-5 ✅ (28/10/2026) |
| `DeclarationTva`, `ComptabiliteAnalytique` | aucune écriture (exports) | pages absentes, l. 115-122 | — | aucune écriture perdue |
| `Parametres\AssistantDemarrage` | ouvrirExercice (premier exercice), terminer | ABSENT : P `demarrage/premier_demarrage_screen.dart` ne fait que constater | `fiscal_years` | CP-4 |

## 2. Paramètres

| Écran web | Fonction web | Poste | Table / synchro | Ticket |
|---|---|---|---|---|
| `GestionUtilisateurs` | newUser, editUser, saveUser (rôle, mot de passe), archiveUser, reactivateUser | **PRÉSENT depuis UT-1 (27/10/2026)** : `ParametresGenerauxRepository.enregistrerUtilisateur` / `archiverUtilisateur` / `reactiverUtilisateur` ; serveur `SaisieUtilisateurAction` + `pushUsers` | `users` (mixte, Drift v68) | UT-1 ✅ |
| `GestionUtilisateurs` | viderSessions | ABSENT (geste en ligne : sessions web et jetons des postes) | API | PA-1 ✅ (28/10/2026, local : AUT-4) |
| `RolesPermissions` | newRole, editRole, saveRole, deleteRole, generateBackup, downloadBackup | ABSENT : l. 362 (inerte), mention l. 373-378 | `roles` (refusé) | PA-2 ✅ (28/10/2026) |
| `DonneesEntreprise` | save (identité, IFU, RCCM, logo, favicon) | ABSENT : « consultation pure » l. 56-58, mention l. 463-469 | `company_settings` (seul `rappel_soins_jours` accepté : `RecordParametresElevageFromDeviceAction`) | PA-3 ✅ (28/10/2026 ; logo et favicon : AUT-2) |
| `EmailSmtp` | save, effacerMotDePasse, sendTestEmail | PARTIEL : SMTP **local** du poste (`onglet_email_smtp.dart`) ; celui du site reste au web | aucune | écart de plateforme assumé (CFG-2) |
| `ModulesActifs` | toggleModule | PRÉSENT : `definirModule` | `modules_config` | — |
| `ModesPaiement` | saveBank, saveMomo, openTransfer, submitTransfer (virement) | ABSENT : mention l. 917-921 | `treasury_accounts` (non envoyée) | PA-4 ✅ (28/10/2026) |
| `AuditLogs` | export | ABSENT : mention l. 1065-1067 | `audit_logs` | hors périmètre (export) |
| `PostesAppairage` | demander, revoquer (autres postes) | ABSENT : `onglet_appairage.dart:20-21` — le poste ne voit que lui-même | — | PA-5 ✅ (28/10/2026, « Ce poste » : AUT-4) |
| `Sauvegardes` | genererComplete, genererModule, telecharger, importerModule | ABSENT : pas d'onglet (le hub web en a 11, le poste 9) ; carte « Dernière sauvegarde » = « — » | — | PA-6 ✅ (28/10/2026, local : AUT-4) |
| `Corbeille` | restaurer, demanderSuppression, supprimerDefinitivement | PRÉSENT : `CorbeilleRepository` | `corbeille_demandes` | — |
| `ReinitialisationDonnees` | basculerModeDemo, reinitialiser | PRÉSENT (en ligne) | API | — |
| `BaremeIts` (`/bareme-its`) | ajouterTranche, retirerTranche, enregistrer | ABSENT, aucun écran (seule mention : « barème non renseigné », RH) | `income_tax_brackets` (tirage seul) | PA-7 ✅ (28/10/2026) |
| `Integrations` (`/parametres-integrations`) | saveSms, sendTestSms | ABSENT, aucun écran | — | PA-8 ✅ remplacé (AUT-3 : le SMS disparaît, e-mail SMTP du poste + appel `tel:`) |

## 3. Achats et fournisseurs

| Écran web | Fonction web | Poste | Table / synchro | Ticket |
|---|---|---|---|---|
| `BonsCommande` | generateBc, confirmReceiveOrder | **PRÉSENT depuis AC-1 (28/10/2026)** : `AchatsRepository.creerBon` / `recevoirBon` ; serveur `SaisieBonCommandeAction`, `ReceptionBonCommandeService` | `purchase_orders` (v71, envoyée), `purchase_order_lines` | AC-1 ✅ |
| `EnregistrerAchat` | saveNewSupplier, saveNewProduct (boutons « + ») | **PRÉSENT depuis AC-2** : `achats_creation_rapide.dart` | `suppliers`, `products` | AC-2 ✅ |
| `EnregistrerAchat` | pièce justificative (fichier) | **PRÉSENT depuis AC-3** : sélecteur + envoi `POST /api/sync/receipts` | `purchases.receipt_path` | AC-3 ✅ |
| `DettesFournisseurs` | colonne Actions | **PRÉSENT depuis AC-4** : « Régler » par ligne (web et poste) | `supplier_payments` | AC-4 ✅ |
| `SaisieDepenses` | justificatif | **PRÉSENT depuis AC-3** : le fichier part au serveur (`receipt_sent`) | `expenses.receipt_path` | AC-3 ✅ |
| `EnregistrerAchat`, `ListeAchats`, `AjouterFournisseur`, `ProfileFournisseur` | submitAchat, retours, remboursements, fournisseurs, règlements | PRÉSENT | `purchases`, `purchase_returns`, `supplier_refunds`, `suppliers`, `supplier_payments` | — |

## 4. Ventes, clients, facturation

| Écran web | Fonction web | Poste | Table / synchro | Ticket |
|---|---|---|---|---|
| `SuiviDettes` | confirmPayment (encaisser une créance) | **PRÉSENT depuis VC-1 (28/10/2026)** : `ClientsCreancesRepository.encaisserCreance` ; serveur `CustomerSettlementService` + `pushReceivablePayments` | `receivable_payments` (Drift v69) | VC-1 ✅ |
| `SuiviDettes` | sendReminder | **PRÉSENT depuis VC-2 (28/10/2026)** : `ClientsCreancesRepository.relancer`, serveur `RelanceClientService` | `customer_reminders` (v70, envoyée) | VC-2 ✅ |
| `RelancesClients` | sendMailReminder, sendWhatsappReminder, sendSmsReminder, exportCourrierPdf | **PRÉSENT depuis VC-2** : e-mail/SMS envoyés par le serveur au push, WhatsApp via `wa.me`, courrier PDF existant | `customer_reminders` | VC-2 ✅ |
| `ProfileClient` | confirmRegularisation, sendQuickReminder | **PRÉSENT depuis VC-3 (28/10/2026)** : `profil_client_page.dart`, `encaisserSolde`, `relancer(clientId:)` | `receivable_payments`, `customer_reminders` | VC-3 ✅ |
| `HistoriqueAvances` | editAdvance, archiveAdvance | **PRÉSENT depuis VC-4 (28/10/2026)** : `ClientsCreancesRepository.modifierAvance` / `archiverAvance`, modale « Modifier l'Avance » et confirmation d'archivage (`avances_modales.dart`) ; serveur `CustomerAdvanceService::appliquerDuPoste` + `pushCustomerAdvances` (D4/D5 revues sur décision du client) | `customer_advances` (`is_active`, pas de nouveau palier) | VC-4 ✅ |
| `Facturation` | retryMecef | ABSENT (QR : mention `ventes/facturation_screen.dart:466-471`) | `sales` | VC-5 (en ligne) |
| `PosInterface`, `HistoriqueVentes`, `RetoursAvoirs`, `Devis`, `ListeClients`, `HistoriqueAvances` (création, imputation, modification, archivage) | — | PRÉSENT | — | — |

## 5. Stocks

| Écran web | Fonction web | Poste | Table / synchro | Ticket |
|---|---|---|---|---|
| `CatalogueProduits` | archive | **PRÉSENT depuis ST-1 (28/10/2026)** : `ProduitsRepository.archiver` ; serveur `ProductCatalogService::archiver` | `products` (`is_active` envoyé) | ST-1 ✅ |
| `SeuilsAlerte` | saveThreshold | **PRÉSENT depuis ST-2** : `ProduitsRepository.definirSeuil`, modale « Configurer un Seuil » | `products` | ST-2 ✅ |
| `AjouterProduit`, `GestionStocks` | save, submitAjouterStock, validateAdjustment | PRÉSENT | `products`, `stock_adjustments` | — |

## 6. Élevage — tout est présent, Transformation comprise (EL-1)

Bandes, sujets, reproducteurs, cinq fiches, prophylaxie du jour, soins / infirmerie / calendrier, reproduction, transferts, paramètres élevage : PRÉSENTS (dépôts `BandesRepository`, `SujetsEntreesRepository`, `ReproducteursRepository`, `FicheJournaliereRepository`, `SoinsRepository`, `SoinsVaccinsRepository`, `SuiviReproductionRepository`, `TransfertsRepository`, `ParametresElevageRepository`).

| Écran web | Fonction web | Poste | Ticket |
|---|---|---|---|
| `TransformationForm` (`/transformation`) | validateTransformation | **PRÉSENT depuis EL-1 (28/10/2026)** : entrée « Transformation » du menu web ET du poste (`transformation_screen.dart`), `TransformationRepository` (le fait seul ; le serveur sort les sujets et entre le stock) ; serveur `SaisieTransformationAction` | `transformations` (v79, mixte) | EL-1 ✅ |

## 7. RH, Administration, divers — présents

RH (RH-1 à RH-4) ; modèles et réglages d'attestation (**en ligne** : `PUT /api/attestation-templates/{type}`) ; Administration (courriers, archives, documents) ; mot de passe du profil, notifications, contact (en ligne, **sans capture d'écran** : `contact_editeur_screen.dart:466-470`).

## 8. Écrans du poste entièrement en lecture seule (état au 27/10/2026)

1. **Comptabilité**, tout le hub (et aucune page Immobilisations).
2. **Facturation & MeCeF.**
3. **Paramètres** : Rôles & Permissions, Données de l'Entreprise, Modes de Paiement, Audit Logs (export). *Gestion Utilisateurs écrit depuis UT-1.*
4. **Achats** : Bons de commande.
5. **Clients & Créances** : Suivi des Dettes, Relances.
6. **Catalogue** : Seuils d'Alerte.
7. Lecture seule aussi au web (aucune écriture perdue) : Tableau de bord, Dashboard Élevage, Bilan technico-économique, Fiche sujet, Rapports & Exports.

## 9. Commentaires périmés à corriger (ils contredisent le code)

- `core/auth/permissions_poste.dart:61` : « Paramètres Élevage en LECTURE SEULE au poste » — faux depuis H9b.
- `pilotage/tableau_de_bord_screen.dart:827` : « `quotes` ne descend pas » — faux depuis DEV.
- `clients/clients_creances_repository.dart:213-214` : « le serveur ignore tout envoi sur ces trois référentiels » — faux pour `customers` et `customer_advances`.
- `catalogue_produits_screen.dart:20-26` : `products` présenté comme ignoré — faux depuis 15.15 (reste vrai pour les catégories).
- `docs/PLAN_FINALISATION.md:428` : « restauration d'une bande non portée » — portée (`BandesRepository.restaurer`).
- `docs/AUDIT_FIDELITE_ECRANS.md:204` et `:215` : dépassés (archivage des soins U3, Paramètres Élevage H9b).

## 10. Ordre de conversion proposé (Sprint CRUD-P)

Chaque ticket = un PRD court (skill `prd`), le web d'abord quand le point de passage unique manque, puis le poste, parité exécutée, docs. Ordre par valeur terrain : **VC-1** (encaisser une créance au comptoir), **AC-1** (bons de commande), **ST-1 / ST-2** (archiver un produit, seuils), **CP-1 / CP-2** (plan comptable, journal manuel), **PA-3 / PA-4** (entreprise, modes de paiement), **CP-3** (immobilisations), **VC-2 / VC-3** (relances, profil client), **PA-2 / PA-7** (rôles, barème ITS), **AC-2 / AC-3 / AC-4**, **~~VC-4~~ ✅ / VC-5**, **CP-4 / CP-5**, **PA-1 / PA-5 / PA-6 / PA-8**, **EL-1**. Points à trancher avec le client : EL-1 (route web orpheline), CP-4 (clôture par le poste, en ligne seulement).

**Incertitudes de l'inventaire :** `pushProducts` et `is_active` d'un produit envoyé par le poste n'ont pas été vérifiés ; les cartes « — » n'ont pas été relues une à une, écran par écran.
