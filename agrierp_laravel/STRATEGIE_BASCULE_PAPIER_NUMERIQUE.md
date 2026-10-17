# Stratégie de Bascule Papier → Numérique — AgriERP

Ticket 13.4 (Sprint 13, DERNIER TICKET DU PLAN D'EXÉCUTION), Document 08
Partie C. Ce document ne recopie pas la Partie C générique déjà fournie
— il vérifie, pour CHACUNE des données à reprendre au jour de bascule,
que l'application livrée dispose réellement d'un point de saisie propre
pour l'y entrer. Trois gaps réels ont été trouvés en le rédigeant ; l'un
a été corrigé dans ce ticket, deux restent honnêtement documentés.

---

## 1. Principe de bascule progressive (repris tel quel, aucun écart)

1. **Double-saisie transitoire (2 à 4 semaines)** : fiches papier
   références officielles, saisie parallèle dans AgriERP.
2. **Reprise de l'historique récent uniquement** (mois en cours), pas
   d'historique pluriannuel rétroactif sauf demande explicite.
3. **Bascule officielle** une fois la double-saisie jugée fiable par le
   Comptable et le Chef d'élevage — AgriERP devient source de vérité
   unique, les fiches papier restent une sauvegarde de terrain.

---

## 2. Vérification réelle : chaque donnée à reprendre a-t-elle un point de saisie ?

### ✅ Élevage — Effectif courant de chaque bande active
**Fonctionne réellement**, vérifié dans le code : `GestionBandes`
(`/gestion-bandes`) permet de créer une nouvelle bande avec
`initial_quantity`/`current_quantity` saisis directement — aucun
contournement nécessaire, l'effectif de départ au jour de bascule
s'entre normalement comme n'importe quelle nouvelle bande.

### 🔴→✅ Comptabilité — Solde d'ouverture du Plan Comptable (RAN initial)
**Gap critique trouvé en rédigeant ce document, corrigé dans ce même
ticket** : aucun seeder, aucune route, aucun bouton n'existait nulle
part dans ce projet pour créer le tout premier `FiscalYear`. Cette table
n'était créée que par `ClotureExercice::confirmCloture()` (ticket 10.6),
qui suppose qu'un exercice précédent existe déjà. Un
`php artisan migrate:fresh --seed` frais n'aurait donc jamais eu
d'exercice ouvert — `AccountingEntryService` aurait rejeté absolument
toute écriture comptable, y compris les écritures de solde d'ouverture
exigées le jour même de la bascule. **`FiscalYearSeeder` ajouté** :
l'exercice en cours est désormais créé au statut `ouvert` dès
l'installation.

Une fois l'exercice ouvert disponible, la saisie du RAN initial se fait
par le Journal Comptable (`/journal-comptable`), une écriture manuelle
par ligne de solde d'ouverture (compte débité = celui qui a un solde
actif, compte crédité = 101 Capital ou équivalent) — mécanisme déjà
pleinement réel depuis le ticket 10.4, `AccountingEntryService::recordManual()`
garantissant l'équilibre débit=crédit à chaque ligne.

### ⚠️ Clients/Fournisseurs — Soldes de créances/dettes en cours
**Gap réel, non corrigé dans ce ticket, documenté honnêtement** :
`Receivable`/`Payable` ne sont créées QUE comme effet de bord d'une
vraie vente (`PosInterface`) ou d'un vrai achat
(`EnregistrerAchat`/`BonsCommande`) — aucune saisie directe d'un solde
d'ouverture n'existe. Contourner ceci en créant une fausse vente/un faux
achat au jour de bascule pour chaque client/fournisseur avec un solde
réel serait trompeur : cela polluerait l'historique des ventes/achats
réels, pourrait affecter le stock à tort, et fausserait les rapports
`HistoriqueVentes`/`ListeAchats` dès le premier jour d'utilisation. **Ne
pas contourner ainsi** — ce gap nécessite un vrai point de saisie dédié
("Solde d'Ouverture Client/Fournisseur", hors périmètre de ce ticket de
documentation) avant la bascule officielle si des soldes en cours
existent réellement à reprendre. Si la ferme démarre l'utilisation
d'AgriERP sans encours (tous les comptes soldés au jour de bascule), ce
gap n'a aucun impact pratique.

### ✅ Stocks — Inventaire physique du jour de bascule
**Fonctionne réellement**, vérifié dans le code : l'onglet
"Ajustement / Correction" de `GestionStocks` (ticket 6.2) est construit
précisément pour ce cas d'usage (écart entre quantité système et
quantité physique constatée) — `AdjustStockAction` (ticket 6.1)
applique l'écart et journalise le mouvement. Utilisable directement le
jour de la bascule pour aligner chaque produit sur l'inventaire physique
réel.

### 🔴 RH — Solde de congés en cours par employé
**Gap réel, non corrigé, à signaler clairement avant toute promesse
faite à la ferme** : recherche explicite dans `Employee` et tout le
module RH — aucun champ, aucune table, aucune notion de solde de congés
n'existe nulle part dans ce projet (`employees.fillable` : prénom, nom,
poste, salaire, date d'embauche, statut, actif — rien d'autre).
Impossible de reprendre une donnée que le système ne modélise pas
encore. Si le suivi des congés est réellement nécessaire pour la ferme,
c'est une fonctionnalité à ajouter en amont de la bascule RH, pas un
simple point de saisie d'ouverture manquant.

---

## 3. Récapitulatif — statut réel de chaque donnée à reprendre

| Domaine | Donnée | Statut réel | Action |
|---|---|---|---|
| Élevage | Effectif courant par bande | ✅ Fonctionne | Aucune |
| Comptabilité | Solde d'ouverture Plan Comptable | 🔴→✅ Gap corrigé | `FiscalYearSeeder` ajouté ce ticket |
| Clients | Soldes de créances en cours | 🔴 Gap réel | Point de saisie dédié à construire si encours existants |
| Fournisseurs | Soldes de dettes en cours | 🔴 Gap réel | Idem |
| Stocks | Inventaire physique | ✅ Fonctionne | Aucune |
| RH | Solde de congés | 🔴 Gap réel | Fonctionnalité absente, à concevoir si nécessaire |

**3 domaines sur 6 pleinement prêts pour la bascule dès aujourd'hui, 1
corrigé dans ce ticket, 2 nécessitent un travail dédié avant la bascule
officielle si les soldes concernés sont non nuls au jour J** — signalé
clairement plutôt que de promettre une bascule sans accroc qui
achopperait en pratique sur ces deux points précis.

---

## 4. Formation et accompagnement (repris du document générique, sans écart)

- Formation par rôle (Comptable, Caissière, Chef d'élevage) sur ses
  écrans spécifiques uniquement, avant la double-saisie.
- Support de premier niveau FAGUEZ SARL pendant 4 à 8 semaines après la
  bascule officielle.
- Vocabulaire et captures de formation strictement alignés sur les
  libellés réels du produit final — jamais une reformulation simplifiée
  qui créerait un écart avec l'écran réel.

---

## 5. Fichiers ajoutés/modifiés dans ce ticket
- `database/seeders/FiscalYearSeeder.php` (nouveau)
- `database/seeders/DatabaseSeeder.php` (enregistrement du nouveau seeder)
