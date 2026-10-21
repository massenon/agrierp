# PRD — « Devis & Proforma » au poste (onglet « Devis Prestations »)
**Statut :** brouillon (version courte, décisions tranchées sur les recommandations) · **Date :** 2026-10-21 · **Ticket(s) :** DEV1 (`docs/PLAN_FINALISATION.md`)

> **Demande du client (21/10/2026) :** « la saisie Devis & Proforma avec son tab panel et son CRUD doit être faite dans le poste », identique au web. Règle absolue : la vue Blade est le maître (Doctrine, article 5) ; le poste reprend structure, composants, libellés, retours et logique métier à 100 %, prouvés par un garde-fou. Périmètre : **le seul onglet Devis** (modèle `Quote`). « Retours et Avoirs » et « Historique des Ventes » relèvent d'un autre ticket.

## 1. Problème
Au poste, l'onglet « Devis Prestations » du hub « Ventes & Devis » n'était qu'une carte « non embarqué » : ni le catalogue de devis ni le fichier clients ne descendaient. Un devis (cages sur mesure, prestations) ne pouvait se faire qu'au bureau, sur le web, avec la liaison. Exemple : un caissier hors ligne devant un client qui demande « 2 cages galvanisées 6 compartiments, 150 000 F HT » ne pouvait rien saisir, rien envoyer, rien imprimer.

## 2. Existant
| Surface | Ce qui existe |
|---|---|
| Web | `Livewire\Ventes\Devis` + `devis.blade.php` (157 lignes) dans le hub `ventes-devis-hub.blade.php` (4 onglets : Enregistrer Vente · Devis Prestations · Historique des Ventes · Retours et Avoirs). Table `quotes` (UUID) ; **pas de lignes structurées** (`quote_lines` n'existe pas) : une description libre, un montant HT global, une TVA, une validité en jours. Numérotation `DEV-AAAA-NNN` (`Quote::generateQuoteNumber()`). Cycle `brouillon → envoyé → accepté | refusé` (+ `facturé`, jamais posé). Export PDF `exports/devis.blade.php`. |
| Web, écarts relevés | « Convertir en Facture » n'est **pas** implémenté (toast d'attente « arrive avec le module Facturation (Sprint 7) ») ; aucune garde sur les transitions de statut (l'UI seule les limite) ; aucun contrôle d'exercice (un devis daté d'un exercice clos s'enregistrait). |
| Poste | Aucune table `quotes`, aucun dépôt ; onglet remplacé par une carte « non embarqué » (`ventes_devis_screen.dart`). |
| Serveur | `SyncController` ne servait ni n'absorbait `quotes`. |

## 3. Utilisateurs et rôles
Les quatre rôles réels : `admin` (tout) et `caissier` (`view-ventes`, `manage-ventes`, `export-ventes`) voient l'onglet ; `comptable` et `animalier` n'ouvrent pas « Ventes & Devis ». Écrire (créer, modifier, avancer, archiver) : `manage-ventes`. « Exporter » : `export-ventes`. « Convertir en Facture » : sans droit au web (`convertToInvoice()` n'a pas d'`authorize()`), montré à tous.

## 4. Exigences fonctionnelles
- **EF1** L'onglet reprend le Blade : en-tête (« Devis & Proforma », sous-titre, « Exporter », « Nouveau Devis »), quatre cartes, barre de filtres (« N° devis, client... », « Statut : Tous », « Client : Tous »), tableau N° Devis · Client · Date · Validité · Montant · Statut · Actions, « Aucun devis pour le moment. ».
- **EF2** Modale « Nouveau Devis » / « Modifier le Devis » : Client *, Articles / Prestations *, Montant HT (FCFA) *, TVA (%) (0 % / 18 %), Validité (jours), Date du Devis (`ChampDateFormulaire`), Note (optionnel) ; erreurs sous les champs avec les messages français du web.
- **EF3** Icônes d'action selon le statut (brouillon : envoyer ; envoyé : accepter, refuser ; accepté : convertir ; toujours : modifier, archiver) ; archivage derrière la confirmation « Confirmer l'archivage ».
- **EF4** Toasts du web, mot pour mot (« Devis créé avec succès. », « Devis marqué comme envoyé. », etc.).
- **EF5** Le poste écrit le fait (`pending`) ; le serveur le rejoue. Table `quotes` synchronisable (UUID, `sync_status`, `device_id`), tirée et envoyée.
- **EF6** Un devis daté d'un exercice **clos** est en lecture seule (création, modification, statut, archivage refusés, motif R4).
- **EF7** Un changement de statut hors du cycle est refusé avec son motif ; un devis archivé ou facturé ne se modifie plus.
- **EF8** « Exporter » édite les devis affichés (mêmes colonnes que le PDF du web).

## 5. Règles métier et calculs
- Numéro : `DEV-AAAA-NNN`, **attribué par le serveur** à la réception (jamais par le poste : deux postes hors ligne produiraient le même numéro sur deux documents imprimés). Au poste : « — » jusqu'à l'acquittement puis au tirage suivant.
- Cartes (jeu calculé à la main, repris par `DevisSaisieWebTest` et `devis_poste_test.dart`) : brouillon 1 000 + envoyé 2 000 + accepté 3 000 + accepté de septembre 7 777 + refusé 500 + accepté archivé 9 999. **Devis Actifs** = brouillon + envoyé + accepté actifs = 4 ; **Valeur Totale** = 1 000 + 2 000 + 3 000 + 7 777 = 13 777 FCFA (montant HT) ; **Taux de Conversion** (mois du jour) = 1 accepté / (1 accepté + 1 refusé) = 50 % (arrondi PHP, 0 sans devis jugé) ; **En Attente de Relance** = envoyés = 1.
- Validité : date du devis + `validity_days`. Montant HT global ; la TVA n'entre ni dans « Montant » ni dans « Valeur Totale » (comme le web).
- Statut : pas autorisés `brouillon → envoyé`, `envoyé → accepté`, `envoyé → refusé` ; même statut redemandé : rien. Un poste hors ligne qui envoie puis accepte avant sa synchronisation envoie l'état final : le serveur parcourt le cycle pas à pas (une trace d'audit par étape).
- Aucun effet comptable, aucun effet stock, aucun effet effectif : un devis ne passe aucune écriture (d'où la règle d'exercice `refusExerciceClos`, pas `exerciceOuvertPour`).

## 6. Hors ligne et synchronisation
Table **mixte** `quotes` (comme `expenses`) : saisie au poste ET tirée (archivés compris, curseur `updated_at`, tous les comptes `view-ventes`). Règle de conflit : **dernier écrivain gagne sur les champs**, le statut n'avance que dans le cycle (un retour en arrière est refusé et rendu `conflict` avec son motif) ; une saisie locale `pending` ou `conflict` n'est jamais écrasée par le tirage ; idempotence par UUID (un renvoi identique n'écrit rien) ; le client d'un devis fusionné (S-T5) est traduit (`FusionReferentielsService::REFERENCES`). Sans réseau : tout fonctionne, la liste montre « À envoyer ».

## 7. Interface
Web d'abord (déjà là ; seul ajout : l'erreur sous « Date du Devis » et sous TVA / Validité), puis poste : `CarteKpi`, `ModaleAgri` / `ModaleConfirmation`, `ChampDateFormulaire`, `ToastAgri`. Libellés exacts du Blade, lus par le garde-fou.

## 8. Hors périmètre
« Retours et Avoirs » et « Historique des Ventes » ; la conversion réelle devis → facture (absente du web) ; les lignes structurées ; le Tableau de bord (onglet « Devis » des Transactions récentes : DEV-2) ; la pièce jointe.

## 9. Questions ouvertes pour le client (propositions recommandées)
- **DEV-Q1 — Conversion « Devis accepté → Facture / vente ».** Le web ne la fait pas. Proposition : la construire **d'abord sur le web** avec le module Facturation (statut `facture`, `converted_sale_id`), puis la porter. Décision requise : un devis facturé crée-t-il une vente à crédit (créance) ou une vente payée ?
- **DEV-Q2 — Lignes de devis structurées** (produits du catalogue, remises par ligne). Proposition : non tant que le web n'en a pas (description libre).
- **DEV-Q3 — Impression du devis** (une page « Devis N° … » à l'en-tête de la ferme, à remettre au client) en plus de l'état « Exporter ». Proposition : oui, web d'abord.

*Tranché sur recommandation, sans attendre :* numéro attribué par le serveur ; exercice clos refusé (construit au web d'abord) ; cycle contrôlé ; archivé et facturé non modifiables.

## 10. Critères d'acceptation
Tests nommés : web `DevisSaisieWebTest` (15), serveur `DevisPosteTest` (22), poste `test/devis_poste_test.dart` (65 : dépôt, KPI, moteur, écran) et garde-fou `test/devis_blade_test.dart` (14 : libellés, colonnes, statuts, icônes, messages, validations, PDF, droits, cartes lus dans le Blade et le composant). Gardes de schéma et de périmètre existants mis à jour : `perimetre_tirage_test`, `ecrivain_unique_test`, `migration_toutes_versions_test` (v53), `conformite_portage_test`, `SyncTiragePagineTest`, `SyncFusionReferentielsTest`. Épreuve de mutation : voir `README_SPRINT0.md`.
