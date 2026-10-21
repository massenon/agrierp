# PRD — « Retours et Avoirs » et « Historique des Ventes » au poste (version courte)
**Statut :** livré (21/10/2026) · **Date :** 2026-10-21 · **Ticket(s) :** AV1, AV2 (`docs/PLAN_FINALISATION.md`, Sprint AV)

> Demande du client : « l'écran Retours et Avoirs doit être la même chose que celle de la version web » ; « même chose pour le screen Historique des Ventes ». **La vue Blade est le maître** (Doctrine, articles 0 et 5). Les critères absents du web sont construits d'abord sur le web.

## 1. Problème
- Au poste, l'onglet « Retours et Avoirs » du hub Ventes & Devis était un message « module non embarqué » : un retour ne se saisissait qu'au web.
- L'onglet « Historique des Ventes » existait mais avait dérivé de la maquette : phrase fausse (« Ventes encaissées sur ce poste » alors que `sales` descend), numéro de facture « — », client « Client non synchronisé », filtre Client inerte, filtre de statut sur le mauvais champ, deux boutons « Excel / PDF » que le web n'a pas, cartes sur toutes les ventes (le web : sur la période), pas de période, pas de recherche, pas de détail, pas d'annulation.
- Exemple chiffré : vente de 10 plaquettes à 5 900 FCFA (59 000) ; le client en rapporte 2 abîmées. Au web : avoir `AV-2026-001` de 11 800 (HT 10 000 + TVA 1 800), stock +2, écriture D 701 + D 443 / C 411. Au poste hors ligne, rien de tout cela n'était possible.

## 2. Existant
| Surface | Ce qui existait | Fichier |
|---|---|---|
| Web | Formulaire « Nouveau Retour », tableau, cartes, « Marquer comme traité » ; **aucun contrôle** de quantité (retour de 50 sur 10 vendus accepté), de montant, d'exercice clos (« Retour enregistré SANS écriture comptable ») | `RetoursAvoirs.php`, `retours-avoirs.blade.php` |
| Web | Historique : cartes sur la période, liste de l'exercice (25 par page), tiroir de détail, annulation (stock réintégré), ticket PDF | `HistoriqueVentes.php`, `historique-ventes.blade.php` |
| Serveur | Aucune table `credit_notes` au tirage ni à l'envoi ; `sales` servi sans remise ni sous-total | `SyncController.php` |
| Poste | `_ongletIndisponible` (avoirs) ; `_ongletHistorique` dans `ventes_devis_screen.dart` | `ventes_devis_screen.dart` |

## 3. Utilisateurs et rôles
Voir l'écran : `view-ventes` (admin, caissier). Écrire (retour, « traité », annulation) : `manage-ventes`. Ticket PDF : `export-ventes`. **Comme au web** : les boutons sont visibles de tout compte qui voit l'écran, le refus est « Votre rôle ne permet pas cette action. » (le `authorize()`), jamais une écriture.

## 4. Exigences fonctionnelles
- **EF1** Retours et Avoirs : en-tête, quatre cartes (Retours du mois, Montant Avoirs, Produits Retournés, Taux de Retour), tableau de neuf colonnes, modale « Nouveau Retour » en cinq sections, « Marquer comme traité », états vides et toasts du web.
- **EF2** Historique : en-tête + « Nouvelle Vente » + période (deux champs Date bornés à l'exercice), quatre cartes sur la période, recherche / Statut / Mode (cinq modes, dont « Avance») / Client / « Réinitialiser », tableau de onze colonnes, pagination de 25 dans l'exercice, tiroir de détail, modale « Annuler cette vente ? », « Télécharger PDF ».
- **EF3** Le serveur **refuse** (web ET envoi du poste) : quantité au-delà de « vendu − déjà retourné », montant au-delà de « ligne − déjà crédité », vente annulée ou inconnue, produit hors vente, date future ou antérieure à la vente, exercice absent ou clos, plan comptable incomplet. Un refus n'écrit **rien** (une transaction).
- **EF4** Idempotence : un avoir porte l'UUID né au poste ; un renvoi ne rejoue rien. « Marquer comme traité » : une seule fois. Une vente déjà annulée n'est pas rejouée.

## 5. Règles métier et calculs
- Retournable d'un produit sur une vente = Σ quantités vendues − Σ quantités des avoirs (réintégrés ou réformés, en attente ou reçus). Exemple : 10 vendus, 6 retournés → 4 restants ; 5 refusé (« … 10 vendu(s), 6 déjà retourné(s), 4 restant(s). »).
- Montant crédité : au plus Σ montants de la ligne − Σ déjà crédités (59 000 − 50 000 = 9 000 restants).
- Écriture inverse (inchangée, 14.27) : D 701 HT, D 443 TVA, C 411 TTC, datée du **jour du retour** ; jamais 531 (un avoir est une dette, pas un décaissement).
- Cartes Retours : mois courant ; produits retournés = somme **tronquée** ; taux = `round(retours / ventes validées du mois × 100, 1)`, 0,0 sans vente.
- Cartes Historique : ventes **validées** de la période ; panier moyen `round`, « 0 FCFA » sans vente ; encours = Σ (montant − payé) des créances non soldées, toutes périodes. Tableau : exercice affiché, **indépendant** de la période. Statut « En attente » du filtre = validée **à crédit** ; la pastille = reste dû > 0.
- Annulation d'une vente : stock des lignes réintégré une fois (`AdjustStockAction`), statut `annulee`. **Ni l'écriture de la vente, ni sa créance ne sont défaites** (comme au web, depuis 4.4) : question ouverte Q2.

## 6. Hors ligne et synchronisation
- Table `credit_notes` (Drift v54, UUID, `sync_status`, `device_id`) : **mixte**, comme `expenses`. Le poste enregistre la DEMANDE ; le serveur numérote (`AV-AAAA-NNN`), réintègre, comptabilise. **Jamais** d'ajustement de stock ni d'écriture au poste.
- Envoi : clé `credit_notes` (`manage-ventes`) traitée après `sales` ; tirage : famille paginée `credit_notes` (`view-ventes`). Un avoir `pending` / `conflict` n'est jamais écrasé par le tirage ; refus du serveur → `conflict` avec son motif, « Relancer ».
- Annulation : la vente passe à `annulee` au poste et repart `pending` ; le serveur annule une vente connue (une fois) ou reçoit puis annule une vente inconnue.
- `sales` descend désormais avec `subtotal` et `discount`.
- Sans réseau : tout s'enregistre ; le ticket PDF exige le réseau (produit par le serveur).

## 7. Interface
Voir `docs/AUDIT_FIDELITE_ECRANS.md` § 11 (écarts et ÉCARTS ASSUMÉS : numéro « — » d'une demande non reçue, mention « Non envoyé », toasts qui ne promettent pas un effet pas encore fait, ticket PDF enregistré dans Documents\AgriERP).

## 8. Hors périmètre
Imputation de l'avoir sur la créance du client, remboursement (trésorerie), contre-passation d'une vente annulée, export Excel / PDF en masse de l'historique : **le web ne le fait pas** (article 0) — ils se construisent d'abord au web (questions ci-dessous).

## 9. Questions ouvertes pour le client (recommandation entre parenthèses)
- **AV-Q1** Le web crée l'avoir mais ne touche pas la créance de la vente : un retour sur une vente à crédit laisse le reste dû inchangé. Imputer l'avoir sur la créance ? (OUI — sinon le client reste « débiteur » d'un montant qu'il a rendu.)
- **AV-Q2** Annuler une vente ne contre-passe ni son écriture, ni sa créance, ni l'encaissement : seul le stock revient. Contre-passer ? (OUI, par une écriture inverse datée du jour, comme l'avoir.)
- **AV-Q3** Rembourser un avoir (débit 411 / crédit trésorerie) : à construire au web d'abord. (OUI, avec le choix du compte.)
- **AV-Q4** Décision tranchée à la place du client, à confirmer : un retour en exercice clos ou sur plan comptable incomplet est désormais **refusé** (avant : enregistré sans écriture, ou 500). (À confirmer par le cabinet FAGUEZ.)
- **AV-Q5** Export Excel / PDF de l'historique : absent du web comme du poste ; en vouloir un ? (Au web d'abord.)

## 10. Critères d'acceptation
Tests : Laravel `AvoirsClientsSyncTest` (30) ; poste `avoirs_poste_test`, `avoirs_sync_poste_test`, `avoirs_blade_test`, `avoirs_schema_test`, `avoirs_parite_php_test` (vrai serveur), `historique_ventes_poste_test`, `historique_ventes_blade_test`, migration vers la v54. Épreuve de mutation : voir le rapport du ticket (`agrierp_laravel/README_SPRINT0.md`).
