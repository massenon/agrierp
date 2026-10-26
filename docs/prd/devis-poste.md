# PRD — « Devis & Proforma » au poste (onglet « Devis Prestations »)
**Statut :** brouillon (version courte, décisions tranchées sur les recommandations) · **Date :** 2026-10-21 · **Ticket(s) :** DEV1, DEV3 (`docs/PLAN_FINALISATION.md`) · **Amendé le 2026-10-21 : § 11 (conversion devis → facture, DEV-Q1 close)**

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

---

## 11. Amendement du 2026-10-21 — « Convertir en Facture » (DEV3, DEV-Q1 CLOSE)

> **Décision du client (21/10/2026) : OUI, construire la conversion devis → facture.** Elle remplace le toast d'attente du web (« arrive avec le module Facturation (Sprint 7) »). Ordre de la doctrine (article 5) : **web d'abord** (la vue Blade est le maître), poste identique ensuite. Cet amendement **remplace** : § 2 (« Convertir en Facture » absente), § 3 (« sans droit au web »), § 4 EF3 (icône « convertir »), EF4 (toast d'attente), § 8 (« la conversion réelle devis → facture ») et la question DEV-Q1 du § 9. Le reste du PRD est inchangé.
>
> ⚠️ **MeCeF est mis de côté par le client (D-MECEF-1).** Cet amendement ne construit **aucune** transmission MeCeF nouvelle : la facture issue d'un devis suit **exactement** le circuit d'une vente reçue du poste (`FacturationMecefService::facturer`, appelé après la transaction, comme pour toute vente) et n'ajoute rien côté DGI.

### 11.1 Existant relevé (audit)
- **Une facture EST une vente** (`Livewire\Facturation\Facturation` : « chaque vente validée EST une facture, jamais une table `invoices` »). Numéro affiché : `FV-AAAA-XXXXXX` (année de la date effective + 6 premiers caractères de l'UUID), calculé dans le Blade ; il n'existe aucune numérotation séquentielle.
- Une vente porte des **lignes** (`sale_lines.product_id` obligatoire) : la TVA en est dérivée ligne à ligne depuis `products.tva_rate` (`RecordSaleAccountingEntryAction`, `VatDeclarationService`) ; le stock, la cascade des effectifs et le contrôle de rémanence en dépendent. **Le projet n'a aucune structure de vente de « prestation sans produit »** (aucun produit de type service, aucune ligne libre) ; `Devis.php` le disait déjà : convertir « forcerait une réconciliation artificielle avec le catalogue ».
- Écriture de vente : D 411 (crédit) ou trésorerie / C 701 / C 443 si TVA, par `RecordSaleAccountingEntryAction` seul. Créance (`Receivable`, échéance +30 jours) pour une vente à crédit.
- Droits : `manage-ventes` (caissier, admin) ; `manage-facturation` (**admin seul** : le caissier ne l'a pas).

### 11.2 Règles posées (recommandations, justifiées)
| # | Règle | Justification |
|---|---|---|
| R1 | **Seul un devis `accepté` est convertible** (pas `envoyé`). | L'acceptation est l'accord du client ; facturer un devis seulement envoyé créerait une créance et une écriture de vente sur un accord non confirmé. C'est déjà la condition du bouton au web (EF3). |
| R2 | Le devis passe au statut **`facturé`** (statut existant, jamais posé jusqu'ici) et garde le lien `converted_sale_id` vers la facture. Il ne se modifie plus (`SaisieDevisAction` le traitait déjà comme figé). | Le cycle `brouillon → envoyé → accepté \| refusé → facturé` du modèle est complété, sans nouveau statut. |
| R3 | La facture reprend **client, total TTC** (HT + TVA du devis) ; la description et le HT restent lus sur le devis lié. Une exploitation **non assujettie** (`TvaSettingService`) est facturée au **montant HT**, sans TVA (le même drapeau pilote l'affichage et les écritures). | Une vente n'a pas de colonne description ni TVA : elles se lisent par le lien. |
| R4 | **Idempotence par l'UUID du devis** : convertir un devis déjà converti rend **la même facture** (aucune seconde vente, créance, écriture ni trace), au web (avertissement) comme au poste (acquittement d'un renvoi). Un index unique sur `converted_sale_id` double le verrou. | Une demande du poste dont la réponse s'est perdue est renvoyée. |
| R5 | **Exercice clos refusé**, deux fois : le devis d'un exercice clos est en lecture seule (EF6 : le passer à « facturé » le modifierait) ; la **date de la facture** est jugée par `VerifySaleDateAction` (future, mois clôturé, exercice absent ou clos), comme toute vente. | Cohérence avec les règles EX5 et EF6. |
| R6 | **Droits : `manage-ventes` ET `manage-facturation`** (web : `authorize()` des deux ; bouton masqué sans les deux ; poste : refus du serveur avec motif). | La conversion émet une facture : c'est un geste de facturation, pas seulement de vente. Conséquence réelle : **aujourd'hui seul l'administrateur convertit** (question DEV-Q5). |
| R7 | **La facture est une vente À CRÉDIT, SANS LIGNE** : `payment_mode = credit`, une créance (+30 jours) pour le total TTC, aucun `sale_lines`, **aucun mouvement de stock**, aucun effet sur les fiches. Écriture D 411 / C 701 (HT) / C 443 (TVA) par `RecordSaleAccountingEntryAction`, qui lit la TVA du devis quand la vente n'a aucune ligne (`VatDeclarationService` de même, pour la Déclaration TVA). | Un devis est une prestation libre (aucun produit) ; un devis se facture avant d'être payé, le règlement viendra par les créances. Question DEV-Q4. |
| R8 | Refus **avant toute écriture**, avec motif lisible : devis inconnu ; archivé ; statut non convertible ; client absent ou **archivé** ; exercice clos (devis ou date de facture) ; **plan comptable incomplet** (411, 701, et 443 si TVA : la conversion échoue, jamais de facture sans pièce). | Même discipline que les retours (AV1). |
| R9 | **La facture normalisée suit le circuit normal** : `FacturationMecefService::facturer`, après la transaction. Un échec ne défait rien (« Erreur MeCeF », à retransmettre depuis Facturation). | D-MECEF-1 : aucune règle DGI nouvelle. |

### 11.3 Exigences fonctionnelles ajoutées
- **EF9** (web) « Convertir en Facture » (visible : devis `accepté` + droits `manage-ventes` et `manage-facturation`) crée la facture par `ConvertirDevisEnFactureAction`. Toasts : « Devis converti en facture FV-… avec succès. » (succès) ; « Ce devis est déjà facturé : facture FV-…. » (avertissement) ; le motif du refus (erreur) ; si le dispositif MeCeF échoue, l'avertissement du POS (« … facture normalisée MeCeF non transmise … »).
- **EF10** (web) Un devis `facturé` montre sous son badge le numéro `FV-AAAA-XXXXXX` et une icône « Voir la facture » (`visibility`, droit `view-facturation`) vers Facturation filtrée sur cette facture. Facturation affiche la facture (client, date, montant TTC) au numéro `Sale::numero_facture` (point de vérité unique).
- **EF11** (contrat `/api/sync`) Le poste envoie la **DEMANDE** : `quote_conversions: [{ id: <uuid du devis>, requested_at?: <instant du clic, ISO 8601> }]`, traitée après `quotes`. Réponse : `{ accepted, rejected: [{ id, reason }], invoices: { <uuid du devis>: { sale_id, invoice_number } } }`. La facture est datée de `requested_at` (la demande hors ligne), jugée comme une vente antérieure. Chaque demande est jugée seule (un refus ne fait échouer ni l'envoi ni les autres), idempotente par l'UUID du devis. Le tirage de `quotes` sert `converted_sale_id` et `invoice_number` ; la facture descend avec les ventes.
- **EF12** (poste) Onglet Devis : « Convertir en Facture » aux **mêmes conditions de visibilité que le web** (devis accepté, droits `manage-ventes` et `manage-facturation`) ; au clic, la demande est écrite (`pending`) et le devis est figé : badge **« Conversion demandée »** (hors ligne, en attente d'envoi) ; à l'acquittement, statut « Facturé » + numéro de facture + icône « Voir la facture » vers l'écran Facturation ; un refus du serveur (« Conversion refusée » + motif mot pour mot) laisse « Annuler la demande » (le devis redevient libre) ou la relance depuis Synchronisation. Refus locaux avant d'écrire, avec les motifs du serveur.

### 11.4 Hors ligne et synchronisation
Table `quotes` (mixte, inchangée) ; **schemaVersion 57** : 3 colonnes (`conversion_requested_at`, `converted_sale_id`, `invoice_number`). Le poste n'invente jamais le numéro de facture. Règle de conflit : la demande est un **fait** rejoué par le serveur ; un devis local `pending` ou `conflict` n'est jamais écrasé par le tirage. Un renvoi du devis resté `accepté` après sa conversion (réponse perdue) est acquitté sans refus (identique à la version d'avant conversion).

### 11.5 Questions ouvertes pour le client (propositions recommandées)
- **DEV-Q4 — Mode de règlement de la facture d'un devis.** Retenu : **vente à crédit** (créance +30 jours), car un devis se facture avant d'être payé. Alternative : une facture payée comptant (choix du mode au moment de convertir). Le règlement se saisit ensuite par les créances.
- **DEV-Q5 — Qui convertit ?** `manage-facturation` n'est porté que par l'administrateur : **le caissier ne voit pas le bouton**. Proposition : donner `manage-facturation` au caissier, ou conserver (la facturation reste à la direction).
- **DEV-Q6 — Annuler la facture d'un devis.** Annuler la vente (Historique des ventes) ne remet pas le devis à « accepté » (il reste « facturé », lien conservé) ; l'annulation ne contre-passe déjà ni écriture ni créance (question ouverte existante). Proposition : à trancher avec la contre-passation.
- **DEV-Q7 — Devis d'un exercice clos converti dans l'exercice courant** (un devis de décembre 2025 accepté en janvier 2026). Retenu : **refusé** (le devis est en lecture seule, EF6). Alternative : autoriser, la facture étant datée du jour.
- **DEV-Q2 / DEV-Q3** restent ouvertes (lignes de devis structurées ; impression « document client ») : le client n'a décidé que la conversion.

### 11.6 Critères d'acceptation (DEV3)
Tests nommés : web `ConversionDevisFactureTest` (32 : conversion, créance, écriture, TVA à 18 % / 0 % / non assujetti, idempotence, refus de chaque règle, demande du poste, droits, tirage), `ConversionDevisWebTest` (11 : écran, toasts, droits, visibilité, Facturation, Déclaration TVA) ; poste `devis_conversion_test.dart` (dépôt, widget, absorbeur, acquittement, relance), `devis_blade_test.dart` mis à jour (parité Blade ↔ Dart des conditions, du contrat, du schéma), `migration_toutes_versions_test` (v57). Épreuve de mutation : voir `README_SPRINT0.md`, entrée DEV3.

