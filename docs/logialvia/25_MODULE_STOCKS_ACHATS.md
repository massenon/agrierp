# 25 — MODULE STOCKS & ACHATS (stocks d'intrants, catalogue, fabrication de provende, achats, fournisseurs, dépenses, inventaire)

## USAGE

- **Quand l'utiliser** : pour construire/auditer les stocks, achats et dépenses ; au jalon W6b, AVANT les ventes (`24_`) et l'élevage (`23_`) : produits, stock par mouvement et PMP sont des prérequis. Le futur import en masse (`28_`) commence par ce module (« stocks d'abord »).
- **Ordre** : `20_MODULES_INDEX` → **`25_`** → `24_` → `23_` → `26_`.
- **Entrées** : `logialvia/docs/F5_Module_Stocks_Achats.md`, `F4_Module_Ventes_Clients.md` (catalogue, coût de revient), `F7_Module_Rapports.md` (écran Inventaire), `F6_Module_Comptabilite.md` §10.4–10.17 (dépenses), `B4_FRS_Functional_Requirements.md` (FRS-STK-01…04), `B6_Regles_Metier.md` (BR-VTE-005/006), `E5_Modales_CRUD.md`, `docs/logialvia/GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md` blocs 13a, 16, 21 ; code `logialvia_app/lib/approvisionnement/` (`data/tables/{intrants,mouvements_intrant,achats,fournisseurs}_table.dart`), `logialvia_app/lib/commercial/data/tables/produits_vendables_table.dart`, `logialvia_app/lib/rapports/presentation/screens/inventaire_screen.dart` ; AgriERP : `agrierp_laravel/app/Actions/AdjustStockAction.php`, `agrierp_laravel/app/Services/ProductCatalogService.php`, `agrierp_laravel/app/Services/ReceptionBonCommandeService.php`, `agrierp_laravel/app/Services/SupplierCatalogService.php`, `agrierp_laravel/app/Services/DetteFournisseurService.php`, `agrierp_laravel/app/Services/InventaireAuComptageService.php`, `docs/prd/depenses-multilignes.md` ; libellés `logialvia/docs/manuel/libelles/{14,15,16,17,18,24,m05,m06,m07,m09}*.json`.
- **Sorties** : migrations, `AdjustStockAction`, `ReceptionCommandeService`, `FabricationProvendeAction`, `SaisieDepenseAction`, composants Livewire `Stocks\…`, `Achats\…`, vues, dépôts Drift, tests.
- **Chemins** : `logialvia/…` = `/home/user/massenon/logialvia/…` ; sans préfixe = `/home/user/agrierp`.

---

## 1. Objectif

Deux stocks distincts (BR-011) : **produits vendables** (catalogue de la caisse) et **intrants** (provende, vétérinaire, marchandises) ; stock toujours exact parce que TOUT mouvement est tracé ; valorisation honnête (PMP, coût de revient, « Non valorisé ») ; achats et dettes fournisseurs ; dépenses comptabilisées ; inventaire daté qui se justifie.

## 2. Écrans

| Route | Écran | Rôles | Droit web | Surface |
|---|---|---|---|---|
| `/stocks` | Gestion des Stocks (intrants) | A | view/manage-stocks | W+P |
| `/catalogue` | Catalogue & Seuils (produits vendables) | A | view/manage-stocks | W+P |
| `/achats` | Achats & Commandes | A | view/manage-achats | W+P |
| `/fournisseurs` | Fournisseurs | A | view/manage-achats | W+P |
| `/depenses` | Saisie des Dépenses | A | view/manage-achats | W+P |
| `/inventaire` | Inventaire daté et valorisé | A seul (DV-15 : pas de cinquième rôle ; droit dédié plus tard si un responsable stock existe ; Q-DV-5 ouverte) | **view-stocks** (TRANCHÉ DV-06 : plus `view-ventes`, caissier exclu) | W+P (lecture) |

## 3. Gestion des Stocks (`/stocks`) — intrants

**KPI** : ARTICLES SUIVIS · VALEUR TOTALE STOCK (Σ stock × PMP) · INTRANTS SOUS SEUIL · MOUVEMENTS (7J). **2 tableaux** : (1) articles : Code (`INT-NNN`) · Désignation · Catégorie · Stock · Seuil Alerte · Valeur · Statut (« Critique » si stock ≤ seuil, sinon « OK ») · Actions (infobulles « Ajustement d'inventaire », « Modifier », « Supprimer ») ; (2) « Journal des Mouvements » : Date / Heure · Référence · Article · Type (Entrée / Sortie) · Motif (« Réception commande », « Fabrication de provende — 18 kg (FAB-2026-0001) », ajustement…) · Quantité signée. Recherche « Désignation ou code… » ; filtre catégorie « Toutes » (Intrants Provende / Marchandises / Vétérinaire) ; boutons « Ajouter un Intrant », « Fabrication de Provende » (icône `blender`), « Exporter PDF ».
**Modale « Ajouter / Modifier un Intrant »** : DÉSIGNATION *, CATÉGORIE *, QUANTITÉ, UNITÉ, SEUIL D'ALERTE, PRIX UNITAIRE (PMP). Suppression : modale de confirmation avec avertissement d'irréversibilité ; « supprimer » ARCHIVE (corbeille) ; la suppression peut échouer si l'article est référencé (message explicatif, jamais une erreur technique).
**Modale « Ajustement d'inventaire »** : stock théorique (pré-rempli) vs stock physique constaté → écart = physique − théorique ; à la validation le physique REMPLACE le théorique et l'écart est journalisé (type, signe, motif, auteur ; BR-ADM-003). Persistance prouvée en rouvrant l'écran.
**Modale « Fabrication de Provende »** : une ligne par intrant de catégorie « Intrants Provende » (les 5 semés : Maïs, Soja, Coquille d'huître, Poudre de poisson, Tourteau de palmiste ; un 6e ajouté au stock apparaît) : nom, unité, stock disponible (rouge si sous seuil), champ de quantité ; composition par défaut 25 / 10 / 5 / 3 / 2 kg ; alerte DÈS LA SAISIE (« Maïs (18 kg dispo) ») ; « TOTAL PROVENDE FABRIQUÉE » recalculé à chaque frappe ; bouton « Valider la Fabrication » : première passe de contrôle de TOUS les stocks puis décrément atomique ; sorties négatives signées avec référence commune `FAB-AAAA-NNNN` séquencée sur l'exercice et motif portant le total. Toute sortie d'intrant de provende passe par cette opération (« jamais une simple sortie de stock isolée », CDCT §6.2, §8.3). **Non défini** : aucun article « Provende » fabriqué n'est créé en sortie, aucune recette n'est mémorisée, aucune écriture comptable (transfert interne) : **Q-STK-2, Q-STK-3**.
**Règles** : PMP' = (stock × PMP + qté × prix) ÷ (stock + qté) (RM-STK-01 ; Q-STK-1) ; critique si stock ≤ seuil (RM-STK-02) ; stock négatif : message et drapeau (H14) ; tout `stock_qty` ne bouge que par `AdjustStockAction` (mouvement écrit dans le MÊME appel) ; verrous de stock par UUID croissants avant toute fiche. **Seuils d'autonomie de provende (TRANCHÉ DV-04)** : deux seuils paramétrables par ferme (`29_` §4) : **alerte à 7 jours** (défaut = délai d'approvisionnement du fournisseur + marge de sécurité) et **critique à 3 jours** ; autonomie = stock de provende ÷ ration journalière calculée (`15_` RM-ELV-10) ; jamais bloquant. Le seuil d'alerte par article (`seuil d'alerte`, stock ≤ seuil) reste un mécanisme distinct (RM-STK-02).

## 4. Catalogue & Seuils (`/catalogue`) — produits vendables

**KPI** : PRODUITS ACTIFS · VALEUR TOTALE DU CATALOGUE (Σ stock × prix) · PRODUITS EN STOCK CRITIQUE. **2 tableaux** : « Catalogue » : SKU (`PRD-NNN`, jamais réécrit) · Désignation · Catégorie (Avicole / Commerce Annexe / Cuniculture / Pisciculture) · Stock · Tarif (ou fourchette) · Actions ; « Seuils d'Alerte » : Désignation · Stock Actuel · Seuil d'Alerte · Statut · Action (crayon → modale de seuil). Recherche « Désignation ou SKU… ».
**Modale « Ajouter / Modifier un Produit »** : DÉSIGNATION *, CATÉGORIE, TARIF INDICATIF (FCFA) *, TARIF HAUT (FACULTATIF), UNITÉ, STOCK (initial), SEUIL D'ALERTE, COÛT DE REVIENT (FCFA), espèce liée (facultative, filières actives), **catégorie d'effectif** (`categorie_effectif`, nullable : lie le produit à la catégorie qu'une vente décrémente, RM-ELV-05 ; Q-ELV-7).
**Règles** : coût de revient ≥ 0 et ≤ tarif (égal accepté ; supérieur refusé : « chaque vente serait à perte ») ; produit présent dans des ventes : non supprimable (message explicatif), archivage seulement (`is_active = false`, jamais réactivation déduite) ; un produit archivé ne se propose plus à la vente mais reste dans l'historique ; seuil non numérique refusé ; valeur à la vente (`valeurStock`) ≠ valeur au coût (`valeurStockAuCout`), marge unitaire `null` sans coût (RM-STK-03). Les produits existants gardent un coût `null` (reconduire le prix de vente perpétuerait la surévaluation). Q-STK-4 : seuil par produit ou par catégorie ?
**Sync** : référentiel, serveur gagne ; création au poste fusionnée par clé naturelle (SKU/désignation).

## 5. Achats & Commandes (`/achats`)

**KPI** : COMMANDES EN COURS · MONTANT TOTAL ENGAGÉ · LIVRAISONS ATTENDUES CETTE SEMAINE (F5 ; libellés réels du poste : « Commandes non encore réceptionnées »). **Structure** : « Intrants à Commander » (cartes avec stock « 16 kg · seuil 25 » et « PMP 600 F ») → « Panier d'Achat » (texte vide « Cliquez sur un intrant pour l'ajouter. ») avec FOURNISSEUR * (« -- Sélectionner -- » ; « Créez d'abord un fournisseur depuis l'écran Fournisseurs. »), MODE DE RÈGLEMENT (Espèces · Mobile Money · Crédit), MONTANT RÉGLÉ, case « Livrée immédiatement (met à jour stock et PMP) », bouton « Valider la Commande » ; tableau « Commandes » : Référence · Fournisseur · Date · Statut (Commandé / Livré / Partiel) · Montant · Actions ; texte vide « Aucune commande enregistrée. Composez un panier ci-dessus pour en créer une. »
**Règles** : réception = stock + , PMP recalculé, mouvement « Réception commande » écrit, dette fournisseur = total − réglé (`paye`, `mode` ajoutés à `ACHATS`), échéance facultative (`echeance`, jamais inventée), exercice clos refusé ; **écriture comptable** D 601/602 (+ TVA déductible 445 si assujetti) / C 401 ou caisse (F5 « Réserve » : NON générée dans logialvia tant que la comptabilité n'était pas branchée → à brancher avec `26_`, BR-CPT-003). Retours/avoirs fournisseurs : AgriERP `PurchaseReturnService`, `SupplierRefundService` : PROPOSÉ, non défini dans logialvia.

## 6. Fournisseurs (`/fournisseurs`)

Miroir exact de Clients (F5). **KPI** : FOURNISSEURS ACTIFS · DETTE TOTALE · ACHATS CUMULÉS (MOIS) · DETTES SOLDÉES (MOIS). Tableaux : « Fournisseurs » : Nom · Téléphone · **Fournit** · Total Achats · Solde Dû ; « Dettes » : Fournisseur · Référence achat · Montant Total · Déjà Réglé · Solde Dû · Ancienneté · Action (saisir le règlement). Modale « Ajouter un Fournisseur » : NOM *, TÉLÉPHONE, ADRESSE, FOURNIT. Clic sur une ligne : panneau avec l'historique des commandes. Même règle d'échéance que les créances (RM-VTE-04).

## 7. Saisie des Dépenses (`/depenses`)

Formulaire (ordre du prototype, en tête de page) : LIBELLÉ DE LA DÉPENSE * (« ex : Transport livraison ou Entretien groupe électrogène »), MONTANT DÉCAISSÉ (FCFA) * (« ex : 12000 »), DATE DE LA TRANSACTION *, CATÉGORIE DE CHARGES (SYSCOHADA) *, COMPTE DE TRÉSORERIE **CRÉDITÉ** * (le prototype disait « Débité » : libellé inversé corrigé), CENTRE ANALYTIQUE (FACULTATIF), REÇU / FACTURE (PHOTO) ; boutons « Enregistrer la Dépense », « Réinitialiser », « Exporter PDF » ; **KPI** : DÉPENSES DU MOIS · CHARGES FIXES · CHARGES VARIABLES ; liste filtrable (« Tous les statuts » — le filtre du prototype était décoratif ; il n'est gardé que s'il filtre réellement). Écriture générée : D compte de charge / C compte de trésorerie (RM-CPT-01) ; date refusée dans un exercice clos ; une dépense comptabilisée garde montant, compte de charge et compte de trésorerie. **Reçu/photo** : logialvia ne stocke aucun fichier (champ non repris) ; au web la chaîne de validation de fichier (SR-045) le permet — **Q-DEP-1** : justificatif joint voulu ? **PROPOSÉ (AgriERP DEP1–DEP3)** : une dépense = un en-tête + N lignes, total = Σ lignes, une écriture (`docs/prd/depenses-multilignes.md`).

## 8. Inventaire (`/inventaire`, ajout hors prototype, demandé par la Gérante)

Répond à « que détenait l'exploitation à une date, et d'où vient l'écart ? ». Périodes : « Journalier » (défaut), « Hebdomadaire » (depuis le lundi), « Mensuel » (depuis le 1er), « Plage personnalisée » (la dernière borne choisie fait foi). Recherche « Rechercher un article, un code… ». Colonnes : ARTICLE · CATÉGORIE · STOCK INITIAL · ENTRÉES · SORTIES · STOCK FINAL · PMP · VALEUR (intrants) ; PRODUIT · COÛT DE REVIENT · SORTIES (VENTES) · VALEUR (produits finis) ; FILIÈRE · EFFECTIF · DERNIÈRE SAISIE (animaux sur pied). KPI/totaux : TOTAL INTRANTS · TOTAL PRODUITS FINIS · TOTAL ANIMAUX SUR PIED · VALEUR TOTALE DU STOCK · « DONT INTRANTS » · « DONT PRODUITS FINIS ». **Règle** : stock à la date T = stock actuel − mouvements postérieurs à T (jamais le stock d'aujourd'hui sous une date passée) ; l'égalité stock initial + entrées − sorties = stock final doit tenir, sinon la ligne est signalée en tête (« un inventaire qui ne se justifie pas ne se signe pas ») ; intrants au PMP, produits finis au coût de revient, animaux et œufs en incubation COMPTÉS non valorisés ; un produit sans coût : « Non valorisé », hors totaux (« Hors N article(s)… ») ; export PDF paysage avec la base de valorisation. **Accès : TRANCHÉ (DV-06)** : administrateur seul (valeur par défaut DV-15 ; un droit dédié sera créé plus tard si un responsable stock existe, jamais un cinquième rôle ; Q-DV-5 ouverte) ; le caissier n'y accède NI par le menu NI par l'URL (redirection `/dashboard`) : il ne voit ni les coûts de revient ni la valorisation ; l'« arbitrage de la Gérante » consigné dans `permission_service.dart` est annulé, le code suit la matrice (`20_` §3). Au poste : hors ligne (lecture sur la base locale). AgriERP : l'inventaire au comptage (`InventaireAuComptageService`, écart calculé contre le grand livre à l'instant du comptage) est une règle distincte, PROPOSÉE (Q-STK-5).

## 9. Hors ligne et synchronisation

| Table | Nature | Règle |
|---|---|---|
| `intrants`, `produits_vendables` | référentiel + stock | serveur gagne sur le référentiel ; le stock ne se synchronise JAMAIS comme une valeur : le poste envoie un MOUVEMENT ou un COMPTAGE, le serveur rejoue par `AdjustStockAction` |
| `mouvements_intrant` | fait | idempotent par UUID |
| `achats`, `lignes_achat` | fait | réception rejouée par `ReceptionCommandeService` |
| `fournisseurs` | référentiel mixte | fusion par clé naturelle |
| `depenses` | fait/demande | `SaisieDepenseAction` (point unique) ; modification/archivage depuis le poste sans second chemin |
Un inventaire (comptage) du poste porte `counted_quantity` + `counted_at` ; l'écart est calculé à l'instant du comptage ; un comptage dépassé par un inventaire plus récent est acquitté sans effet (AgriERP S-T10).

## 10. Notifications

Stock sous seuil (06:05, rôle admin), stock négatif après synchronisation, autonomie de provende (alerte ≤ 7 j, critique ≤ 3 j par défaut ; DV-14 recommandé : critique = délai fournisseur, alerte = délai + 4 j : DV-04), achat en retard de réception (À DÉFINIR, Q-STK-6).

## 11. Critères d'acceptation

- [ ] 18 kg à 600 F + 82 kg reçus à 700 F → PMP 682, valeur 68 200 F.
- [ ] Ajustement théorique 18 / physique 15 → mouvement −3 journalisé ; l'écran rouvert montre 15.
- [ ] Fabrication 25/10/5/3/2 avec Maïs 18 kg : refusée en bloc, aucun stock bougé ; avec stocks suffisants : 5 sorties négatives de référence commune `FAB-AAAA-NNNN`.
- [ ] Coût 7 000 sur tarif 6 000 refusé ; coût 6 000 accepté ; produit sans coût : « Non valorisé », hors total.
- [ ] Produit vendu : non supprimable, archivable.
- [ ] Inventaire à une date passée = stock actuel − mouvements postérieurs ; ligne injustifiée signalée.
- [ ] Un animalier ou un caissier en URL directe `/stocks` : refus.
- [ ] Un caissier en URL directe `/inventaire` : refus (redirection `/dashboard`), entrée de menu absente ; un comptable aussi (DV-06, matrice `20_` §3).
- [ ] Autonomie de provende : alerte à ≤ 7 j, critique à ≤ 3 j, seuils modifiés dans Paramètres suivis par l'alerte (DV-04).

## 12. Tests

Modèles AgriERP : `agrierp_laravel/tests/Feature/` (`ls | grep -i -E 'stock|achat|fournisseur|depense|inventaire|produit'`), `agrierp_flutter/test/produits_archive_seuil_test.dart`. Poste logialvia : `logialvia_app/test/approvisionnement/`, `logialvia_app/test/pilotage/stock_critique_test.dart`. À écrire : cas RM-STK-01 à 04 ; test d'atomicité de la fabrication (3e intrant en dépassement) ; test « chaque mouvement porte son `stock_movements` » (jamais l'un sans l'autre).

## 13. PROMPT de construction du module

> Construis le module **Stocks & Achats** d'après ce fichier, EN PREMIER des modules métier (avant Ventes et Élevage). Lis `20_` §7, `F5`, `F4` (catalogue, coût), `15_REGLES_METIER.md` §4, guide blocs 13a, 16, 21. **Ordre** : **(1) migration** `products` (UUID, `sku`, `name`, `category`, `unit`, `price`, `price_max`, `cost_price` nullable, `stock_qty`, `alert_threshold`, `categorie_effectif` nullable, `species` nullable, `is_active`), `intrants`/`supplies` (UUID, `code`, catégorie, `stock_qty`, `pmp`, seuil, `is_active`), `stock_movements` (UUID, article, type, quantité signée, motif, référence, auteur, instant), `suppliers`, `purchases` + `purchase_lines` (`paye`, `mode`, `echeance`, statut), `expenses` + `expense_lines` ; **(2) modèles** ; **(3) Actions/Services** : `AdjustStockAction` (SEUL écrivain de `stock_qty`, mouvement dans le même appel, verrous UUID croissants), `ReceptionCommandeService` (stock + PMP + mouvement + dette + écriture), `FabricationProvendeAction` (contrôle de TOUS les stocks puis décrément atomique, référence `FAB-AAAA-NNNN`), `ProductCatalogService` (archivage, seuil, coût), `SaisieDepenseAction`, `InventaireService` (reconstitution à rebours) ; **(4) composants Livewire** `Stocks\GestionStocks`, `Stocks\Catalogue`, `Achats\AchatsCommandes`, `Achats\Fournisseurs`, `Achats\SaisieDepenses`, `Stocks\Inventaire` ; **(5) vues** (`x-datatable`, `x-kpi-card`, `x-modal`, `x-modal-confirm-delete`, `data-label`) ; **(6) poste** : tables Drift UUID (migration `from < 27`), `ParametresRepository`/dépôts, le poste n'écrit jamais `stock` directement (mouvement/comptage), `plan_comptable` requis pour l'écriture d'achat ; **(7) tests** du §12. **Interdits** : modification directe de `stock_qty`, sortie de provende hors fabrication, valorisation d'un produit à son prix de vente, suppression physique d'un article référencé, stock « d'aujourd'hui » présenté sous une date passée, article de provende fabriquée créé sans décision Q-STK-2.
