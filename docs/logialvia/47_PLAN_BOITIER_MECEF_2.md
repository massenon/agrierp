# 47 — Plan : le boîtier fiscal Eltrade CC300 branché sur le poste (MECEF-2), en prompts réutilisables

> **USAGE**
>
> - **Quand l'utiliser.** Le jour où la ferme (ou une autre structure) possède le boîtier et demande que les factures normalisées passent par lui. **Pas avant** : MECEF-2 n'est pas construit (`BoitierMecefGateway` est un squelette) et le schéma du pilote n'a jamais été essayé sur un vrai appareil.
> - **Ordre.** `41_MECEF_EMECEF.md` (§ 3 le pilote, § 3.3 l'état exact) → **ce plan** (prompts B0 à B6, dans l'ordre) → `31_TESTING_QA.md` (T2 mutation, T3 parité) → procédure du premier essai réel (`41`, § 5, adaptée au boîtier). Le poste web (navigateur) vient APRÈS le poste Windows.
> - **Entrées requises.** Un boîtier CC300 branché et son pilote lancé (`http://localhost:38917`) ; un IFU d'essai ; la décision sur le point B1 (qui construit la charge) ; la réponse du client aux questions du § 3.
> - **Sorties.** Un `BoitierMecefClient` du poste (Dart), une transmission qui vérifie `qr_code`, des tests contre un faux pilote, un essai réel consigné, la mise à jour de la section « NON vérifié » de `41`.
> - **Rien d'inventé.** Chaque fait vient de `41_MECEF_EMECEF.md`, `docs/PLAN_FINALISATION.md` (MECEF-1 à MECEF-3), `agrierp_laravel/CLAUDE.md` (sections MECEF) et du code relu : `app/Services/Mecef/*`, `presentation/LISEZMOI.md`. Le pilote a été lu (`Readme.md`, `bill.spec.json`, `server/*.go`), jamais exécuté.
> - **Interdits permanents.** Aucun jeton au poste ; aucun appel réel à la DGI ; ne jamais lire le code HTTP du pilote comme un succès ; ne jamais exposer le port du boîtier hors `localhost` ; ne jamais commiter ; ne jamais `pkill`.

## 1. Rappel des faits (pour ne pas les redécouvrir)

1. Le pilote écoute `http://localhost:38917`, **sans authentification** ; commandes `GET /check`, `GET /info` (« cette requête prend 4 s »), `POST /bill`.
2. **`POST /bill` répond 200 même en échec** avec un `qr_code` vide : la seule preuve de succès est `qr_code` rempli. Schéma invalide : 400 `{"errors": …}` ; appareil absent : 503.
3. Le serveur hébergé ne peut pas joindre le boîtier : la transmission se fait par le POSTE.
4. Côté serveur, tout existe pour le contrat : mode `boitier` réglable, fabrique de passerelle, `BoitierMecefGateway` (squelette : « Mode boîtier : transmission par le poste non encore disponible. », état `en_attente`), `ChargeBoitierEltrade` (traduction PHP, jamais confrontée à un appareil), spécimen `presentation/ticket_essai_mecef.json`.
5. Au poste, les colonnes `mecef_*` des ventes et avoirs sont aujourd'hui TIRÉES, jamais écrites (garde `mecef_emecef_poste_test`) ; le jeton n'existe pas au poste.
6. États : `MecefEtat` = `en_attente` · `transmise` (affichée « Normalisée ») · `erreur` (« Refusée ») · `expiree`.

## 2. Prompts

### B0 — Cadrage et décision de contrat (aucun code)

```text
RÔLE : architecte. Aucune écriture de code.
CONTEXTE : lis docs/logialvia/41_MECEF_EMECEF.md (§ 3, § 3.2, § 3.3), docs/PLAN_FINALISATION.md (MECEF-1, MECEF-3, ligne « MECEF-2 »), agrierp_laravel/app/Services/Mecef/{MecefFactureBuilder,ChargeBoitierEltrade,BoitierMecefGateway}.php, agrierp_flutter/CLAUDE.md (sections MECEF-1 et MECEF-3).
TÂCHES :
1. Écris, en une page, les DEUX options pour construire la charge du boîtier : (A) porter MecefFactureBuilder + ChargeBoitierEltrade en Dart avec parité exécutée contre le vrai PHP ; (B) faire servir la charge traduite par le serveur au poste (route à ajouter, hors ligne impossible tant que la charge n'est pas servie). Pour chacune : hors ligne, parité, surface de code, risque d'écart d'arrondi.
2. Liste les changements de CONTRAT qu'implique l'écriture au poste des colonnes mecef_* aujourd'hui tirées seulement, et ce que l'envoi (`_venteEnJson`, `_avoirEnJson`) devrait porter.
3. Pose au client les questions du § 3 de ce fichier.
CRITÈRES D'ACCEPTATION : une recommandation motivée ; aucune promesse « même charge utile » (41, § 3.2).
INTERDITS : coder ; deviner une réponse du pilote.
```

### B1 — Le client du pilote au poste (Dart, derrière une interface)

```text
RÔLE : développeur Flutter. Le poste Windows est la RÉFÉRENCE ; le web viendra après.
CONTEXTE : décision de B0. Modèles de structure : agrierp_flutter/lib/core/systeme/*_poste*.dart (interface + implémentation native, remplaçable en test), lib/core/sync/sync_engine.dart.
TÂCHES :
1. Une interface `PasserelleBoitier` (check, info, facturer(charge) -> résultat) et une implémentation HTTP vers http://localhost:38917 (port NON modifiable à l'écran sans droit administrateur), avec délais explicites (GET /info prend 4 s).
2. `facturer` renvoie un succès SEULEMENT si `qr_code` est non vide ; 400 -> motif du pilote (`errors`) en français ; 503 ou connexion refusée -> « Boîtier injoignable » (hors ligne n'est pas une erreur rouge) ; jamais de réessai aveugle d'un POST /bill (risque de double facture : demander `/info` ou refuser tant que l'état n'est pas lu).
3. Un faux pilote de test (serveur local Dart) qui rejoue : succès, 200 + qr_code vide, 400, 503, délai dépassé.
CRITÈRES D'ACCEPTATION : le cas « 200 avec qr_code vide » est un ÉCHEC (test rouge si on lit le code HTTP) ; mutation prouvée (T2).
INTERDITS : jeton ; écouter un port ; appeler la DGI ; code spécifique au natif dans un fichier partagé avec le web (imports conditionnels, test `garde_imports_web_test`).
```

### B2 — La charge : portage ou service

```text
RÔLE : ingénieur parité (T3).
CONTEXTE : option retenue en B0.
TÂCHES (option A) : transposer `MecefFactureBuilder::pourVente` / `pourAvoir` et `ChargeBoitierEltrade::depuisChargeEnLigne` en Dart (prix entiers TTC, remise répartie, écart d'arrondi, groupes de taxe, libellés ≤ 60, vendeur ≤ 30) ; test de parité qui lance le VRAI PHP sur des jeux de ventes (remise, livraison, quantités décimales, avoir) et compare les charges octet pour octet.
TÂCHES (option B) : route serveur qui rend la charge traduite d'une vente du poste, droits comme `retransmettre-facture`, idempotente.
CRITÈRES : changer un arrondi d'un seul côté fait rougir le test.
INTERDITS : recopier la règle dans le test ; arrondir un montant au poste sans l'avoir prouvé identique.
```

### B3 — Transmission, résultat, synchronisation

```text
RÔLE : développeur Flutter + Laravel.
CONTEXTE : B1 et B2 terminés.
TÂCHES :
1. À la validation d'une vente « facture normalisée » en mode boîtier : appeler le boîtier ; succès -> enregistrer QR, code MeCeF/DGI, NIM, compteurs, date de normalisation sur la vente ; échec -> `en_attente` avec le motif ; hors boîtier -> la vente est enregistrée quand même, « demandée — en attente ».
2. Faire remonter ce résultat au serveur : colonnes mecef_* envoyées par le poste (changement de contrat : accepté UNIQUEMENT pour une vente en mode boîtier, refusé sinon, motif français), idempotent par UUID, jamais d'écrasement d'une normalisation déjà acquittée.
3. Facture PDF et QR : inchangés (`DocumentsFacturation.facture`).
CRITÈRES : une vente normalisée par le boîtier puis synchronisée apparaît « Normalisée » au web ; un renvoi ne double pas ; la vente reste verrouillée (annulation refusée, avoir seulement).
INTERDITS : transmettre depuis le serveur hébergé ; modifier la passerelle e-MECeF.
```

### B4 — Avoirs

```text
RÔLE : développeur.
TÂCHES : avoir sur une facture normalisée par le boîtier -> charge `rt` = FA + `rn` = référence du boîtier (« NIM-TC »), jamais l'`uid` de l'API en ligne ; mêmes garanties que B3.
CRITÈRES : test avec le faux pilote ; un avoir sur une facture simple ne transmet rien.
```

### B5 — Écrans et réglages

```text
RÔLE : développeur Livewire + Flutter.
TÂCHES : retirer « (à venir) » du mode boîtier SEULEMENT quand B3 est livré et essayé ; écran de diagnostic (état du boîtier : /check, /info : NIM, IFU, compteurs) lisible par l'administrateur ; libellés identiques au web (parité lue dans le Blade).
INTERDITS : afficher un jeton ; rendre le port modifiable par un rôle autre que l'administrateur.
```

### B6 — Premier essai RÉEL et consignation

```text
RÔLE : opérateur d'essai, avec le client présent.
CONTEXTE : procédure `41_MECEF_EMECEF.md` § 5 adaptée : boîtier branché, pilote lancé, vente d'essai uniquement, JAMAIS la production.
TÂCHES : (1) /check ; (2) /info (noter NIM, IFU, compteurs, durée) ; (3) une vente simple normalisée ; (4) client avec IFU ; (5) AIB 1 % puis « aucun » ; (6) remise + quantité décimale ; (7) avoir ; (8) boîtier éteint / débranché (503) ; (9) coupure réseau pendant la synchronisation ; (10) hors ligne puis synchronisation.
RAPPORT : date, version du pilote, réponses brutes SANS donnée sensible, ce qui devient « vérifié » dans `41` § 4 et § 3.3, ce qui reste.
```

## 3. Questions au client (avant B1)

1. Marque et modèle exacts du boîtier acheté ; version du pilote installée sur le poste de caisse.
2. Un seul poste de caisse porte le boîtier, ou plusieurs ? (un boîtier = un poste ; les autres postes ?)
3. La facture normalisée doit-elle s'imprimer HORS RÉSEAU (le boîtier est local) ou seulement après la synchronisation ?
4. Que fait-on quand le boîtier est en panne : vente refusée, ou vente en attente puis normalisation différée ?
5. Le poste web (navigateur) devra-t-il aussi piloter le boîtier ? (non étudié : voir `41` § 3.3, point 6.)

## 4. Contrôle de ce fichier

- Chaque chemin cité existe (`grep` des fichiers `app/Services/Mecef/*`, `presentation/ticket_essai_mecef.json`).
- Aucune promesse de fonction : le boîtier reste « à venir » tant que B3 n'est pas livré et essayé sur un vrai appareil.
