# PRD — « Corbeille » : voir, restaurer et supprimer définitivement les enregistrements archivés (version courte)
**Statut :** brouillon (livré par les tickets ARC1 à ARC5) · **Date :** 2026-10-21 · **Ticket(s) :** ARC1 à ARC5 (`docs/PLAN_FINALISATION.md`, Sprint ARC)

> Demande du client : « CRÉER UNE PAGE/SCREEN (WEB ET POSTE) pour afficher les enregistrements archivés (supprimés) et permettre de les RESTAURER et/ou de les SUPPRIMER DÉFINITIVEMENT. » **Le web est le maître** (Doctrine, articles 0 et 5) : ce qui manque au web se construit d'abord au web, le poste le reprend à l'identique.
> **Nom :** le projet dit déjà « Corbeille » (`CorbeilleService`, ticket 14.55 ; l'onglet de Paramètres s'appelait « Restauration »). On garde « Corbeille » et on renomme l'onglet.

## 1. Problème
- Depuis le ticket 14.55, une **Corbeille** existe au web (Paramètres Généraux › « Restauration ») : liste, filtre par type, bouton « Restaurer ». Elle n'existe **pas au poste**, ne permet **aucune suppression définitive**, n'a ni recherche, ni filtre de date, et son tri n'est pas le seul défaut (voir § 2).
- Exemple chiffré : la ferme archive un client « Kossi Adjovi » créé par erreur (aucune vente), un client « SOGEA » (3 ventes) et une dépense de 45 000 FCFA saisie en double. Aujourd'hui : l'administrateur peut « restaurer » la dépense — ce qui la remet dans les listes **sans** rejouer l'écriture ni la trésorerie que son archivage avait défaites (le solde de caisse sera faux de 45 000 FCFA) — mais il ne peut pas retirer définitivement « Kossi Adjovi », qui encombre la liste des clients pour toujours.

## 2. Existant (audit du 21/10/2026)
| Surface | Ce qui existait | Fichier |
|---|---|---|
| Web | Onglet « Restauration » : 14 types (`produits`, `fournisseurs`, `clients`, `depenses`, `bandes`, `soins`, `rations`, `provendes`, `prophylaxie`, `absences`, `documents`, `pieces`, `courriers`, `comptes`), liste triée par `updated_at`, filtre de type, « Restaurer » (`is_active = true` pur), `AuditLog corbeille.restored`, droit `manage-parametres` sur chaque méthode | `CorbeilleService.php`, `Livewire/Parametres/Restauration.php` |
| Web | **Défauts trouvés** : (1) une dépense archivée se « restaure » sans rejouer la contre-passation ni la trésorerie (`SaisieDepenseAction::archiver` contre-passe l'écriture **et** réintègre le montant en trésorerie : la restauration brute est comptablement fausse) ; (2) le titre de « Type de provende » (`label`) et d'« Absence de stagiaire » (`motif`) lit une colonne qui n'existe pas : le libellé est « — » ; (3) aucun contrôle d'exercice clos, ni de code déjà pris (la bande a pourtant sa règle BS-Q7 dans `SaisieBandeAction::restaurer`, que la Corbeille ne consulte pas) ; (4) quatre types archivables absents (devis, avances client, employés, pointages) ; (5) ventes annulées et transferts annulés invisibles |
| Écrans qui restaurent déjà | **Bandes & Sujets** (`GestionBandes`, BS-Q7, onglet « Bandes archivées » : code unique vérifié) ; **Gestion des Utilisateurs** (réactivation d'un compte). Aucun autre écran ne restaure ; **aucun écran ne supprime physiquement** un enregistrement métier | `SaisieBandeAction.php` |
| Poste | Rien (la bande archivée se restaure dans Bandes & Sujets, BS-Q7). Le poste archive : clients, fournisseurs, produits, dépenses, bandes, soins, devis, avances, courriers, documents, pièces, barèmes d'élevage | — |

### Inventaire des entités « archivées » du projet
| Mécanisme | Entités | Dans la Corbeille |
|---|---|---|
| `is_active = false` | produits, fournisseurs, clients, dépenses, bandes, soins, barèmes (rations, provendes, protocoles prophylactiques), absences de stagiaires, documents administratifs, pièces archivées, courriers, comptes du plan, **devis, avances client, employés, pointages** | OUI (14 existants + 4 ajoutés) |
| `is_active = false` (annulation) | transferts entre bandes | OUI, **consultation seule** (rien à restaurer : un transfert annulé a rendu les sujets aux deux bandes) |
| `status = 'annulee'` | ventes annulées | OUI, **consultation seule** (le stock a été réintégré) |
| `is_active = false` | écritures comptables | **NON** (décision 14.55 conservée : on contre-passe, on ne restaure pas ; le Journal les montre) |
| `is_active = false` | comptes utilisateurs | **NON** (réactivation = Gestion des Utilisateurs, avec contrôle de rôle ; ne pas créer une seconde porte) |
| `is_active = false` | catégories de produit, centres de coût, comptes de trésorerie, barème ITS, immobilisations, sujets | NON : aucun écran ne les archive (pas d'archive à montrer) ; à rouvrir si un écran le fait |
| `SoftDeletes` / `deleted_at` / `archived_at` / statut `archive` | **aucun** dans le projet | — |

## 3. Utilisateurs et rôles
Un seul rôle : **administrateur** (`manage-parametres`, que seul `admin` porte). La Corbeille agrège les archives de TOUS les modules : un caissier y verrait des dépenses, un animalier des documents administratifs. Contrôle posé sur **chaque méthode** (`authorize('manage-parametres')`), pas seulement sur l'onglet ; au poste, `GardeEcran` + la même permission côté serveur à l'envoi.

## 4. Exigences fonctionnelles
- **EF1** Une page « Corbeille » liste TOUS les types archivables (tableau ci-dessus), avec : cartes (Éléments archivés, Restaurables, Suppression définitive possible), recherche (titre, détail, type), filtre de type, période d'archivage (Du / Au), « Réinitialiser », pagination de 25. Colonnes : Type · Élément · Détail · Module · Archivé le · Actions.
- **EF2** « Archivé le » = dernière modification de la ligne (`updated_at`). **L'auteur de l'archivage n'est pas connu** (`audit_logs` ne retient pas l'enregistrement visé) : aucune colonne « Archivé par » n'est affichée plutôt qu'une colonne de tirets (question Q2).
- **EF3 Restaurer** : bouton par ligne ; refus **dit à l'écran** par une phrase (pas de bouton mort) quand la règle de § 5 l'interdit. Succès : toast, trace `AuditLog corbeille.restored` et ligne du journal de la Corbeille.
- **EF4 Supprimer définitivement** : bouton par ligne seulement pour les types admis ; ouvre une modale **en deux temps** (1. le bouton ; 2. saisir le mot `SUPPRIMER`, le bouton rouge reste grisé tant que le mot n'est pas exact) ; le serveur **revérifie** le mot et les dépendances (le grisé n'est qu'un confort). Irréversible, `AuditLog corbeille.deleted` avec le titre de l'élément supprimé.
- **EF5** Le serveur refuse (web ET envoi du poste), sans rien écrire : type inconnu (jamais lu comme un nom de classe), élément introuvable ou déjà actif, droit insuffisant, règle de § 5.
- **EF6 Poste** : la même page (onglet « Corbeille » de Paramètres Général, même place qu'au web). Restaurer et Supprimer définitivement y sont des **DEMANDES** synchronisées ; le serveur fait les effets et renvoie le résultat ou le refus (motif conservé et affiché).

## 5. Règles métier
### 5.1 Restauration, par type
| Type | Règle |
|---|---|
| Produit, fournisseur, client, employé, document, pièce, courrier, protocole, ration, provende, absence | Libre (aucun effet comptable ni de stock à l'archivage). |
| Produit, compte du plan | Refusée si un autre enregistrement **actif** porte déjà le même code (`CleUnicite` : casse, accents, espaces ignorés) : « Le code « X » est déjà porté par un produit actif. » |
| **Bande** | Passe par `SaisieBandeAction::restaurer` (BS-Q7) : refusée si une autre bande **en cours** porte déjà le code (`LivestockLot::messageCodePris`). |
| Devis, avance client, soin, pointage | Refusée si leur date tombe dans un **exercice clos** (motif R4, `AccountingEntryService::refusExerciceClos`). |
| **Dépense** (comptabilisée ou non) | **INTERDITE.** Son archivage a contre-passé l'écriture (exacte, du jour) **et** réintégré le montant en trésorerie : la restaurer ne rejouerait ni l'un ni l'autre (une dépense restaurée sans sa charge fausserait le Bilan, sans son décaissement fausserait la caisse) et ne **doit pas** effacer la contre-passation. Message : « Cette dépense a été contre-passée au grand livre et son montant réintégré en trésorerie : la restaurer ne rejouerait ni l'un ni l'autre. Saisissez une nouvelle dépense. » |
| **Vente annulée** | **INTERDITE** : « Une vente annulée a réintégré son stock : elle ne se restaure pas. Saisissez une nouvelle vente. » |
| **Transfert annulé** | **INTERDIT** : « Un transfert annulé a rendu leurs sujets aux deux bandes : le restaurer ne rejouerait pas le mouvement. Saisissez un nouveau transfert. » |
| Écriture comptable, compte utilisateur | Hors Corbeille (§ 2). |

### 5.2 Suppression définitive
Conditions cumulatives : l'élément est **archivé** ; son type est **admis** ; **aucune référence** (clé étrangère ou colonne `<entité>_id` d'une autre table) ne le vise ; droit administrateur ; mot `SUPPRIMER`.

| Type | Suppression définitive |
|---|---|
| Produit, fournisseur, client, employé | **Admise seulement si aucune table ne le référence** (lignes de vente, mouvements de stock, achats, dépenses, créances, avances, devis, bulletins de paie, pointages…). Sinon refus nominatif : « … est référencé par 12 ligne(s) de vente et 2 mouvement(s) de stock : il ne peut pas être supprimé, il reste archivé. » |
| Ration, provende, protocole prophylactique, absence de stagiaire, document administratif, pièce archivée | **Admise** (référentiels et pièces sans conséquence ni référence). |
| Dépense, vente annulée, devis, avance, courrier, pointage, bande, soin, compte du plan, transfert | **INTERDITE** : pièce ou fait comptable / zootechnique / numéroté (une suppression ouvrirait un trou dans la numérotation `DEV-`, `CR-` ou effacerait un fait que les rapports relisent). « Jamais d'effacement physique d'un enregistrement comptable ou zootechnique » (CLAUDE.md du web). |

Aucune suppression n'est **jamais** un écrasement du grand livre : aucun des types admis n'a d'écriture.

### 5.3 Exemple calculé à la main (devient le test)
Archivés : client A « Kossi Adjovi » (0 vente) ; client B « SOGEA » (3 ventes) ; dépense D 45 000 FCFA ; produit P « Maïs » (2 mouvements de stock). → Liste : 4 éléments ; cartes : Éléments archivés **4**, Restaurables **3** (A, B, P ; D refusée), Suppression définitive possible **1** (A seul). Restaurer D : refusé (§ 5.1), D reste archivée. Supprimer B : refusé « référencé par 3 ligne(s) de vente ». Supprimer A avec « supprimer » (minuscules) : refusé ; avec « SUPPRIMER » : A disparaît de la base, `AuditLog corbeille.deleted`.

## 6. Hors ligne et synchronisation
- **Liste au poste : un instantané servi par le serveur** (table `corbeille_elements`, lecture seule), plus une **surcouche locale** : les entités archivées AU poste (`is_active = false`, `pending` / `conflict`, pas encore dans l'instantané) apparaissent dès l'archivage. *Choix (le plus simple et sûr) :* une vue dérivée des seules tables locales obligerait le poste à recalculer les règles de § 5 (dépendances dans 20 tables qu'il ne possède pas toutes) — deux implémentations qui divergeraient ; l'instantané garde **une seule** règle, celle du serveur.
- **Demandes** : table mixte `corbeille_demandes` (UUID né au poste, `pending` → `synced` / `conflict` avec motif). Le poste n'écrit **jamais** `is_active` ni ne supprime une ligne métier : le serveur fait les effets (`CorbeilleService`, le point de passage UNIQUE de la page web et de l'envoi), dans une transaction, et répond par table (`accepted` / `rejected` + motif). Traitée **après** toutes les autres clés de l'envoi (l'archivage du même envoi est connu du serveur avant la demande). Idempotente par UUID (journal serveur `corbeille_operations`).
- Tirage : clé `corbeille` (page 1, remplacée en entier, `manage-parametres`). Envoi : clé `corbeille_demandes` (`manage-parametres`). Drift **v58**.
- Sans réseau : on voit ce qui est déjà descendu et ce qui vient d'être archivé ici ; on peut poser des demandes (« en attente d'envoi ») ; aucun effet avant la synchronisation, et l'écran le dit.
- Résidu connu : une ligne supprimée définitivement au serveur reste, archivée donc invisible, dans la base locale des postes qui la détenaient (aucune « pierre tombale » dans le contrat de tirage) ; la purge de réinitialisation l'efface.

## 7. Interface
Web (maître) : `Livewire\Parametres\Corbeille` + vue `corbeille.blade.php`, composants `x-kpi-card`, `x-modal`, `x-pagination`. Poste : `CorbeilleOnglet` (`CarteKpi` / `GrilleKpi`, `ChampDateFormulaire`, `SymbolesAgri`, `ModaleAgri`, `PaginationAgri`). Libellés exacts : voir `corbeille.blade.php` (le garde-fou de parité les **lit**).

**Menu :** onglet « Corbeille » de **Paramètres Généraux**, entre « Audit Logs » et « Réinitialisation » (la place de l'ancienne « Restauration »), identique au poste. *Pourquoi pas « Administration & Documents » ?* ce module est ouvert à `view-administration` (l'animalier n'y entre pas, mais un compte futur le pourrait) et la Corbeille agrège aussi les dépenses et les clients ; Paramètres est le seul hub réservé à l'administrateur.

## 8. Hors périmètre
Archivage automatique à échéance, purge programmée de la Corbeille, restauration par lot, « Archivé par » (Q2), corbeille des écritures (jamais), restauration d'une dépense par re-comptabilisation (Q1).

## 9. Questions ouvertes pour le client (recommandation entre parenthèses)
- **ARC-Q1** Une dépense archivée ne se restaure plus (décision de prudence comptable, plus stricte que 14.55). Faut-il une « restauration avec re-comptabilisation » (nouvelle écriture datée du jour + nouveau décaissement, jamais l'effacement de la contre-passation) ? (NON pour l'instant : « Dupliquer » une dépense depuis la saisie suffit ; à construire au web d'abord si le cabinet FAGUEZ le demande.)
- **ARC-Q2** Faut-il savoir **qui** a archivé ? (OUI : ajouter `entity_id` à `audit_logs` ; sans cela, l'écran n'affiche pas d'auteur. Les restaurations et suppressions, elles, sont journalisées avec leur auteur.)
- **ARC-Q3** Admettre la suppression définitive d'un devis / d'un courrier (aujourd'hui interdite : trou de numérotation) ? (NON.)
- **ARC-Q4** Imposer un **délai** (30 jours d'archive) avant la suppression définitive ? (NON : la double confirmation et l'absence de référence suffisent ; à confirmer.)
- **ARC-Q5** La Corbeille doit-elle aussi montrer les écritures contre-passées (consultation seule) ? (NON : le Journal les montre.)
- **ARC-Q6** Le poste n'efface pas la ligne d'un poste tiers après une suppression définitive (résidu § 6). Acceptable ? (OUI ; sinon, ajouter des « pierres tombales » au contrat de tirage.)

## 10. Critères d'acceptation
Tests : Laravel `CorbeilleArchivesTest` (liste de chaque type, restauration autorisée / refusée par règle, suppression autorisée / refusée, confirmation, droits, audit, exercice clos, code pris) + `CorbeilleSyncTest` (tirage, envoi, idempotence, droits) + `CorbeilleRestaurationTest` (existant, adapté) ; Flutter `corbeille_poste_test`, `corbeille_sync_poste_test`, `corbeille_blade_test` (parité Blade ↔ Dart : libellés, colonnes, actions, messages), `corbeille_schema_test` (v58), `migration_toutes_versions_test`. Épreuve de mutation : voir le rapport du ticket (`agrierp_laravel/README_SPRINT0.md`).
