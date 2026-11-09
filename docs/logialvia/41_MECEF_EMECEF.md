# 41 — Facturation normalisée e-MECeF et machine MeCeF (poste ET web)

> **USAGE**
>
> - **Quand l'utiliser.** (1) Pour **comprendre** la facture normalisée du Bénin et dire au client ce qui est livré dans LogiAgriERP, ce qui ne l'est pas et ce qui n'a jamais été vérifié. (2) Pour **construire** le module MeCeF de LogiALVIA côté serveur et retirer la transmission du poste (prompt de la section 7).
> - **Ordre.** Après le socle web (`02_ARCHITECTURE_WEB_ET_STACK.md`), l'appairage et la synchronisation (`43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md`, S0 à S5) et les écrans de configuration (`42_CONFIG_MECEF_SMTP_LOGO_FAVICON.md`, écran (a)). **Avant le web : ne PAS toucher au module actuel de `logialvia_app/`** (il marche comme « à transmettre »).
> - **Entrées requises.** Réponses du client (section 8) ; compte e-MECeF existant (IFU, jeton, environnement d'essai) ; règles de TVA de LogiALVIA (`15_REGLES_METIER.md`) ; le guide `GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md` bloc 19.
> - **Sorties.** Un module MeCeF serveur (passerelle, constructeur unique, choix simple/normalisée, réglage, test de configuration), la migration des factures existantes, le poste allégé, les tests `Http::fake`, la procédure du premier essai réel.
> - **Avertissements en tête (à répéter au client).** **AUCUN essai réel contre la DGI n'a été fait**, ni dans LogiAgriERP ni dans LogiALVIA (ni jeton ni IFU de test). Les adresses de l'API et les noms de champs viennent d'un paquet **non officiel** ; aucune documentation DGI n'a pu être consultée. Le traitement de l'**AIB** est une lecture de ce paquet : **à confirmer**.
> - **Voir aussi.** `15_REGLES_METIER.md` (TVA, ventes), `20_MODULES_*` (Ventes, Facturation), `30_DATABASE_ENGINEERING.md`, `31_TESTING_QA.md`, `42_CONFIG_MECEF_SMTP_LOGO_FAVICON.md`, `40_PWA_HORS_LIGNE.md` (hors ligne : « demandée — en attente »), `47_PLAN_BOITIER_MECEF_2.md` (plan du boîtier par le poste).

---

## 1. Explication fonctionnelle

### 1.1 Ce que c'est
Au Bénin, la **facture normalisée** est une facture **certifiée par la DGI** (Direction générale des impôts) au moment de son émission : le système de facturation de l'entreprise transmet la facture à un **module de contrôle de facturation (MeCeF, « Module électronique de contrôle de facturation »)**, qui la signe, lui donne un **code MeCeF/DGI**, un **QR code**, des **compteurs** et un horodatage, qui s'impriment sur la facture. Ce paragraphe est un contexte général ; **l'obligation légale précise (qui, à partir de quel seuil, quelles sanctions) n'est pas établie ici : à confirmer avec le cabinet comptable ou la DGI**.

Deux façons d'obtenir cette certification (les deux existent, d'après les décisions du client dans `docs/PLAN_FINALISATION.md`, MECEF-1) :

| | **e-MECeF (en ligne)** | **Boîtier physique (ex. Eltrade CC300)** |
|---|---|---|
| Principe | API en ligne de la DGI : le logiciel envoie la facture, la DGI la certifie | Un appareil branché à un PC, piloté en HTTP local |
| Qui transmet | le **serveur** (jeton secret, jamais sur les postes) | le **poste** où le boîtier est branché (le serveur hébergé ne peut pas joindre `localhost`) |
| Prérequis | compte e-MECeF de l'IFU, **jeton** (JWT) délivré par le portail de la DGI | boîtier acheté et déclaré, pilote installé |
| État dans LogiAgriERP | **livré** (MECEF-1, MECEF-3) | **construit sans l'appareil** (MECEF-2), NON vérifié avec un vrai boîtier |

### 1.2 Vocabulaire
- **IFU** : Identifiant Fiscal Unique, **13 chiffres** (celui de l'entreprise vendeuse ; celui du client, **facultatif**).
- **NIM** : Numéro d'Identification de la Machine, attribué par la DGI ; il s'imprime sur chaque facture normalisée (`mecef_nim`). Exemple de réponse du pilote CC300 : `"NIM": "ED04000623"`.
- **AIB** : taux appliqué à l'acheteur « si applicable » ; valeurs du boîtier : `1%`, `5%`, `N/A` (`bill.spec.json`). Développement du sigle, assiette et décideur : **à confirmer avec la DGI ou le cabinet** (LogiAgriERP propose **5 % par défaut**, 1 %, ou « Aucun (N/A) »).
- **Groupes de taxe** (lettres imprimées en face de chaque ligne), d'après `bill.spec.json` du pilote : **A** Exonéré · **B** Taxable · **C** Exportation de produits taxables · **D** TVA régime d'exception · **E** Régime fiscal TPS · **F** Réservé (taxe de séjour : l'article doit s'appeler « TAXE DE SEJOUR »). **LogiAgriERP n'utilise que A (0 %) et B (18 %)** et **refuse tout autre taux avec son motif** (`MecefFactureBuilder::GROUPES_TAXE`).
- **Types de facture** (champ `vt` / `rt` du boîtier) : vente **FV** (copie CV) · vente à l'exportation **EV** (copie EC) · avoir **FA** (copie CA) · avoir à l'exportation **EA** (copie ER). **LogiAgriERP n'émet que FV et FA.** EV/EA (exportation) : non construits, à décider avec le client s'il exporte.
- **Avoir** : une facture normalisée **ne se modifie ni ne s'annule** ; elle se corrige par un **avoir FA lié à la facture d'origine**. Côté API en ligne, la référence de l'avoir est l'`uid` de la facture d'origine (`reference` = `mecef_uid`). Côté boîtier, la référence attendue est au format **« NIM-TC »** (NIM de la machine d'origine, TC de la facture d'origine) : ce n'est **pas** le même champ ni la même valeur (voir 4.3).
- **QR code** : donnée renvoyée par la DGI (`qrCode`), dessinée sur la facture avec le code MeCeF/DGI, le NIM, les compteurs, la date et l'heure. Exemple de forme renvoyée par le pilote : `F;ED04000623;NW34NID6ZHANFNMZ2IU7LL3H;3201910768821;20200503135002`.
- **Facture simple** (LogiAgriERP) : facture PDF **sans certification**, mention « Facture simple — non normalisée DGI » ; **jamais transmise**. **Facture normalisée** : choisie à la caisse ; nom et prénom du client obligatoires, IFU facultatif, taux d'AIB.

---

## 2. Ce qui est LIVRÉ dans LogiAgriERP (07/11/2026) — vérifié dans le code

Sources : `agrierp_laravel/CLAUDE.md` (MECEF-1, MECEF-3, VC-5), `docs/PLAN_FINALISATION.md` (MECEF-1, MECEF-3, MECEF-2), code sous `agrierp_laravel/app/Services/Mecef/`.

### 2.1 Modes et fabrique
- `company_settings.mecef_mode` : `desactive` (défaut) · `emecef` · `boitier`. Valeur NULLE = jamais réglé : `agrierp_laravel/config/mecef.php` (`MECEF_ACTIF`) décide (faux = désactivé ; vrai = `simule` : `FakeMecefGateway`, développement et tests ; `phpunit.xml` l'allume).
- Lecture unique : `MecefReglage` ; `mecef_actif` est **dérivé** (tout mode sauf `desactive`). `MecefGatewayFactory::make()` choisit la passerelle **à chaque demande** : changer de mode s'applique à la transmission suivante.
- Mode `boitier` : `BoitierMecefGateway` répond « Mode boîtier : transmission par le poste non encore disponible. » avec l'état `en_attente` et ne transmet **rien**.

### 2.2 Passerelle e-MECeF (`EmecefGateway`)
- `POST /invoice` (création, renvoie l'`uid`) puis `PUT /invoice/{uid}/confirm` (code MeCeF/DGI, `qrCode`, NIM, compteurs, horodatage). Délai 12 s, connexion 5 s, **UN SEUL essai de création** ; une facture créée mais non confirmée **expire côté DGI** (~2 minutes, d'après le commentaire de la classe, non confirmé).
- **L'`uid` est GARDÉ** : une confirmation perdue se reprend par `GET /invoice/{uid}` puis la confirmation **seule**, **jamais une nouvelle création** (sinon deux factures pour une vente = doublon fiscal). `expiree` oublie l'`uid` (nouvelle création légitime).
- Jamais d'exception qui bloque la vente ; la transmission est faite **après** la transaction de la vente (`FacturationMecefService`, ticket S-T13 : une transaction rejouée sur interblocage appellerait la DGI deux fois).
- États (`App\Support\MecefEtat`) : `en_attente` (réseau, 401/403, 5xx, jeton ou IFU absent : à retenter), `transmise` = « Normalisée », `erreur` = « Refusée » (4xx de la DGI, motif français), `expiree`. ⚠️ **Les clés stockées gardent leurs anciens noms** (`transmise`, `erreur`) : ne pas les copier tels quels dans LogiALVIA, choisir des clés propres dès le départ (`normalisee`, `refusee`).
- Une vente **normalisée n'est JAMAIS retransmise** (relue **sous verrou**) ; un second clic, une page restée ouverte, deux appels simultanés : le second attend le premier puis voit « Normalisée ».
- **Pas de retransmission automatique planifiée** : `agrierp_laravel/routes/console.php` ne contient aucune tâche MeCeF. Une facture restée « En attente » attend le bouton **« Retransmettre »** de l'écran Facturation (web, `agrierp_laravel/app/Livewire/Facturation/Facturation.php`) ou de la liste des avoirs. À décider pour LogiALVIA (section 8).

### 2.3 Constructeur unique (`MecefFactureBuilder`)
- Champs de l'API en ligne produits : `ifu` (émetteur), `type` (`FV`/`FA`), `client` {`name`, `ifu` si présent}, `operator` {`id`, `name`}, `items` (`name`, `price` **TTC**, `quantity`, `taxGroup`, `originalPrice`, `priceModification`), `payment` [{`name`, `amount`}], `reference` (avoir), `aib` (`B`=5 %, `A`=1 %, omis pour N/A).
- **Prix ENTIERS** (FCFA), **UNE seule fonction d'arrondi** (`MecefFactureBuilder::arrondi`, au plus proche, moitié vers le haut ; `MecefEntiersTest` garde par la source qu'il n'existe aucun autre `round(` de montant). Chaîne : montant de ligne = `manual_total_amount` arrondi → remise globale répartie au **plus fort reste** → ligne « Frais de livraison » (quantité 1) → écart d'arrondi absorbé par la plus grande ligne de produit (facture **REFUSÉE** si l'écart dépasse le nombre de lignes) → prix unitaire = montant ÷ quantité si la division tombe juste, sinon quantité 1 et la quantité réelle dans le libellé « (2,5 kg) » (60 caractères au plus, limite du boîtier).
- Modes de paiement : `especes`→`ESPECES`, `mobile_money`→`MOBILEMONEY`, `virement`→`VIREMENT`, `credit`→`CREDIT`, `avance`→`AUTRE`.
- Aucune taxe spécifique envoyée. Frais de livraison facturés **inclus** dans le total des nouvelles ventes (drapeau `delivery_in_total`).

### 2.4 Facture simple / normalisée à la vente (`ChoixFactureService`)
- UN point de passage, appelé par la caisse web **et** l'envoi du poste (`SyncController::pushSales`) ; **le serveur REVALIDE tout**.
- Type absent = **simple** (aucune transmission, même module actif) ; type inconnu = refus ; simple : identité fiscale jamais gardée ; normalisée : **nom et prénom obligatoires** (150 caractères au plus), **IFU facultatif** (vide = client sans IFU : champ omis ; présent = **13 chiffres exacts**, espaces retirés), **AIB dans la liste** (5 %, 1 %, N/A ; absent = refus, jamais deviné).
- Messages exacts : « Type de facture inconnu : choisissez « Facture simple » ou « Facture normalisée ». » · « Le nom et prénom du client sont obligatoires pour une facture normalisée. » · « L'IFU du client doit comporter 13 chiffres (laissez-le vide pour un client sans IFU). » · « Choisissez le taux d'AIB : 5 %, 1 % ou Aucun (N/A). »
- **Modale « Facture normalisée »** de la caisse (IFU + nom + AIB) : `x-modal name="modal-facture-normalisee"`, ouverte par **événement** (`open-modal`), **jamais** par un `@if`/`if` d'écran ; préremplie d'après le client ; « Annuler » ramène à « simple ». Une facture issue d'un **devis** est simple.
- Poste : `agrierp_flutter/lib/features/ventes/choix_facture.dart` (transposition, parité EXÉCUTÉE contre le vrai PHP : `agrierp_flutter/test/choix_facture_parite_php_test.dart`, 22 cas).

### 2.5 Verrou, avoir, QR, statuts
- **Facture normalisée verrouillée** : ni modifiable ni annulable (modèle `Sale::booted`, lignes figées, `AnnulerVenteAction` refuse **avant** de toucher au stock), web **et** poste, même message : « Facture normalisée : corrigez-la par un avoir. »
- **Avoir** : vente d'origine normalisée → avoir `FA` transmis par le même mécanisme (`FacturationMecefService::facturerAvoir`) ; vente non normalisée → rien. Module désactivé sur une vente normalisée : l'avoir **attend** (`en_attente`).
- **QR sur la facture** : PDF web `exports.facture-vente` (`simplesoftwareio/simple-qrcode`, QR en SVG) ; poste : `qr_flutter` à l'écran, `pw.BarcodeWidget` dans le PDF. Sans normalisation : « Facture émise sans certification MeCeF. » et rien d'autre.
- **Écran Facturation** : pastille « Facture simple », statuts Normalisée / En attente / Refusée / Expirée avec le motif sous la pastille, « Retransmettre » seulement pour une normalisée non aboutie ; module désactivé = comportement « registre » avec facture PDF (colonnes MeCeF masquées).
- **Hors ligne** : le poste écrit le choix, la vente part à la synchronisation, le **serveur** transmet ; le poste tire les champs `mecef_*` (jamais écrits par lui : `VENTE_CHAMPS_DU_POSTE` n'en contient aucun).
- **Jeton JWT = SECRET** : chiffré (cast `encrypted`), masqué (« •••• », « Remplacer », « Effacer »), **jamais servi au poste** (seuls le mode, l'adresse, l'opérateur et le booléen `mecef_jeton_configure` descendent), jamais journalisé (l'audit `company_settings.mecef_updated` ne porte aucune valeur). ⚠️ La sauvegarde du serveur le contient **chiffré par `APP_KEY`** : perdre `APP_KEY` = perdre le jeton.
- **« Tester la configuration »** (`MecefConfigurationTesteur`) : contrôles locaux puis **UN** `GET {url}/info/status` (lecture sans effet, **jamais** `POST /invoice`) ; écran détaillé au fichier `42_CONFIG_MECEF_SMTP_LOGO_FAVICON.md`.

### 2.6 Limites connues de la déclaration de TVA
La Déclaration de TVA ne retient que les ventes **normalisées** (règle M14 d'origine) : une facture simple n'y figure pas — **à confirmer avec le cabinet comptable** (question client).

---

## 3. Le pilote du boîtier et MECEF-2 (à venir)

Pilote relu : `/home/user/issotina/eltrade-cc300-driver/` (`Readme.md`, `bill.spec.json`, `server/server.go`, `server/handlers.go`).

| Point | Constat (relu dans le code) |
|---|---|
| Écoute | `http://localhost:38917` (`PORT = ":38917"` dans `server/server.go`) |
| Commandes | `GET /check` (état : `{"status":"Ready"}` ou 503 `DeviceNotConnected`) ; `GET /info` (NIM, IFU, compteurs, groupes de taxe `TaxA`…`TaxD`, société ; « cette requête prend 4 s ») ; `POST /bill` (JSON du schéma `bill.spec.json` ; réponse `{"qr_code":"…"}`) |
| **Réponse 200 même en échec** | `createBill` (`server/handlers.go`) : `res, err := cmd.CreateBill(...)` puis `WriteHeader(http.StatusOK)` **sans lire `err`** : en cas d'échec de l'appareil, la réponse est 200 avec un `qr_code` vide. **Toujours vérifier que `qr_code` est rempli, jamais le code HTTP.** Une requête invalide au schéma donne 400 avec `{"errors": …}` ; appareil absent : 503 |
| Authentification | **Aucune** (« Host Headers [NOT YET IMPLEMENTED] ») : n'écouter que `localhost`, ne jamais exposer le port |
| Schéma `/bill` | `seller_id`, `seller_name` (≤ 30), `payments` [{`mode` V/C/M/D/E/A, `amount`}], `products` [{`label` ≤ 60, `tax` A à F, `price` TTC, `items` (quantité), `original_price`, `price_change_explanation` ≤ 24, `specific_tax`…}], `buyer_ifu`, `buyer_name`, `aib` (`1%`/`5%`/`N/A`) ; **vente** : `vt` (FV/CV/EV/EC) ; **avoir** : `rt` (FA/CA/EA/ER) + `rn` (« NIM-TC ») |

### 3.1 MECEF-2 (construit sans l'appareil : voir § 3.3)
Contrat défini dans `docs/PLAN_FINALISATION.md` : le poste appelle `http://localhost:38917/check` puis `/bill`, **vérifie que `qr_code` est rempli**, puis synchronise le résultat. Question ouverte d'LogiAgriERP : le constructeur étant en PHP, MECEF-2 le fera soit porter en Dart avec parité exécutée, soit servir la charge par le serveur.

### 3.2 ⚠️ Précision à apporter au guide et au plan (écart relevé)
Le guide (bloc 19) et le plan disent que le boîtier utilisera « le MÊME `MecefFactureBuilder` ». **Ce n'est vrai que pour la logique** (prix entiers, répartition de remise, arrondi, groupes de taxe, libellés ≤ 60). Le **JSON** produit par `MecefFactureBuilder::enveloppe` suit l'API en ligne (`items`/`taxGroup`/`payment`/`type`/`reference`/`aib` = `A|B`) ; le pilote attend un **autre schéma** (`products`/`tax`/`payments`/`vt`|`rt`/`rn`/`aib` = `"1%"|"5%"|"N/A"`, `seller_id`, `seller_name`). MECEF-2 nécessite donc une **couche de traduction** (et, pour l'avoir, la référence « NIM-TC » au lieu de l'`uid`). Ne pas promettre « même charge utile ».

### 3.3 MECEF-2 — état au 09/11/2026 : CONSTRUIT SANS L'APPAREIL, NON VÉRIFIÉ AVEC UN VRAI BOÎTIER

> Plan d'exécution en prompts : `47_PLAN_BOITIER_MECEF_2.md`. Décision du client (09/11/2026) : « faut lancer le chantier, faut pas attendre le boîtier ». **Rien ci-dessous n'a été essayé avec un vrai boîtier** : tout est éprouvé contre un FAUX PILOTE (`agrierp_flutter/test/boitier_faux_pilote.dart`) qui rejoue ce que dit le `Readme.md` du pilote (succès, 200 + `qr_code` vide, 400, 503, réponse lente).

**Contexte (décisions du client du 07/11/2026).** La ferme a un COMPTE e-MECeF et utilise ce mode ; d'autres structures ont un BOÎTIER **Eltrade CC300** branché sur le poste. Les deux modes coexistent (`MecefMode` : `desactive` · `emecef` · `boitier`). Le libellé « Boîtier MeCeF (à venir) » est GARDÉ jusqu'au premier essai réel.

#### Décision B0 (une page) — OPTION A : porter le constructeur en Dart, parité exécutée contre le vrai PHP

| | A. Porter `MecefFactureBuilder` + `ChargeBoitierEltrade` en Dart | B. Faire servir la charge par le serveur |
|---|---|---|
| Hors ligne | **La facture sort du boîtier sans serveur** : le poste est offline-first, le boîtier est local | Impossible tant que la charge n'est pas servie : le caissier attendrait le réseau pour un boîtier posé à côté de lui |
| Parité | Prouvée par un test qui EXÉCUTE le vrai PHP (`charge_boitier_parite_php_test.dart`, ~40 cas : remise, livraison, écart d'arrondi, refus, TVA inactive, modes de paiement, libellés longs, avoirs) | Aucune à prouver (une seule implémentation) |
| Surface de code | +1 fichier Dart (`facture_mecef.dart`) à garder aligné | +1 route serveur, +1 état « charge demandée » |
| Risque d'arrondi | Une seule fonction d'arrondi (`FactureMecef.arrondi`, moitié vers le haut), prix entiers, mêmes libellés, mêmes groupes de taxe, même AIB ; mutations prouvées (arrondi → plancher, AIB `B` → `1%` : le test devient rouge) | Nul |

**Choix : A** (imposé par le client : le poste est offline-first, une facture doit sortir du boîtier sans serveur ; l'option B est écartée). Le risque d'écart est couvert par la parité exécutée : toute évolution du constructeur PHP casse le test Dart tant que la transposition n'est pas refaite.

**Changements de CONTRAT qu'implique l'écriture au poste des colonnes `mecef_*`** (jusqu'ici TIRÉES seulement) : voir « Ce qui est construit » ci-dessous. Le garde `mecef_emecef_poste_test` est RESSERRÉ, pas supprimé : la vente n'emporte la normalisation que par UN bloc `mecef`, en mode boîtier, vente en attente d'envoi, jamais un jeton, jamais `mecef_uid`, jamais l'AIB calculé ; l'avoir reste entièrement au serveur.

#### Ce qui est construit (poste Windows)

| Pièce | Fichier |
|---|---|
| Charge en Dart (vente `FV`) + traduction du boîtier + parité PHP exécutée | `agrierp_flutter/lib/core/mecef/facture_mecef.dart`, `test/charge_boitier_parite_php_test.dart` |
| Contrat `PasserelleBoitier` (résultats typés : certifiée · refusée · injoignable · incertaine), lecture du `qr_code` | `lib/core/mecef/passerelle_boitier.dart` |
| Client HTTP `http://localhost:38917` : **localhost seulement** (garde + mutation), client Dio À PART (jamais l'en-tête `Authorization`), délais explicites (connexion 2 s, `/check` 3 s, `/info` 8 s pour 4 s annoncées, `/bill` 30 s), succès **seulement si `qr_code` non vide**, 400 → motif français, 503 / connexion refusée → « Boîtier injoignable » (état, pas erreur rouge) | `lib/core/mecef/passerelle_boitier_native.dart` ; navigateur : `passerelle_boitier_web.dart` (aucun boîtier) ; choix par import conditionnel `passerelle_boitier_plateforme.dart` |
| Transmission par le poste (mode `boitier`) : réservation en base AVANT l'appel, états, reprise | `lib/features/ventes/transmission_boitier.dart` ; écritures de `sales` par l'unique écrivain `caisse_repository.dart` |
| Envoi du résultat : bloc `mecef` de la vente ; acquittement qui ne perd pas un résultat arrivé PENDANT l'envoi | `lib/core/sync/sync_engine.dart` (`_blocMecefDuPoste`) |
| Serveur : applique le bloc (mode boîtier seulement, facture à déclarer seulement, jamais par-dessus une facture normalisée, `qr_ref` non vide exigé) | `agrierp_laravel/app/Services/Mecef/ResultatBoitierDuPoste.php`, `SyncController::pushSales`, test `MecefBoitierPosteEnvoiTest` |
| Indicateur d'état du boîtier (Paramètres › Facturation normalisée : vérifier, informations de l'appareil, factures en attente / refusées / à vérifier ; caisse : version compacte) | `lib/features/ventes/bandeau_boitier.dart` |

**États (`sales.mecef_status`, clés inchangées).** `transmise` = « Normalisée » (le boîtier a rendu un `qr_code` non vide) · `erreur` = « Refusée » (400, 200 sans QR, ou charge refusée par le constructeur ; motif français ; reprise À LA MAIN seulement) · `en_attente` = boîtier injoignable (reprise AUTOMATIQUE à l'ouverture, après chaque tirage, toutes les 90 s, bouton de l'écran) · `expiree` n'existe pas en mode boîtier.

**Idempotence : jamais deux transmissions d'une même vente.** (1) La vente est réservée dans une transaction ; la MARQUE « Transmission au boîtier commencée, réponse non reçue : vérifiez sur l'appareil… » est posée dans `mecef_message` AVANT l'appel ; (2) une vente marquée est « incertaine » : jamais reprise seule (arrêt de l'application pendant l'appel, ou réponse perdue après envoi) — l'écran demande de vérifier sur l'appareil puis de relancer à la main ; (3) le tirage n'écrase jamais la marque ; (4) une vente normalisée n'est plus retransmise et est verrouillée (correction = avoir, inchangé) ; (5) verrou mémoire en plus. **Jamais de jeton** au poste (le pilote n'en a pas).

**Hors ligne.** Le boîtier est local : la facture se normalise sans réseau ; le résultat part à la synchronisation suivante. Si le boîtier n'est pas joint : « En attente », reprise à son retour.

**Limites connues / NON construit :**
1. **Avoir sur une facture normalisée par le boîtier** (`rt`/`rn`) : la charge Dart de l'avoir existe (parité exécutée) mais **la transmission de l'avoir par le poste n'est PAS branchée** ; la référence « NIM-TC » est non vérifiée. Le serveur en mode boîtier laisse l'avoir « en attente ».
2. **Un seul poste doit porter le boîtier.** Une vente faite au web en mode boîtier est transmise par le poste qui la tire ; deux postes avec un boîtier chacun peuvent certifier deux fois la même vente (le serveur garde la première normalisation, mais le boîtier a déjà certifié). À régler par l'organisation avant l'essai.
3. Annuler une vente « incertaine » n'est pas encore refusé par le poste.
4. Formats du `qr_code` (`F;NIM;code;IFU;AAAAMMJJHHMMSS`) tirés du seul exemple du `Readme.md` ; compteurs de l'appareil (`/info`) lus pour l'affichage, **non** stockés sur la facture.
5. Poste web (navigateur) : aucun boîtier (non étudié : contenu mixte / accès au réseau privé).
6. **Aucun essai réel, aucun essai sous Windows.**

#### Checklist du PREMIER ESSAI RÉEL du boîtier (à faire avec l'appareil, sur une vente de test)

0. Sauvegarde ; pilote `eltrade-cc300-driver` lancé sur le poste (port 38917) ; boîtier branché ; IFU du boîtier = IFU de la ferme.
1. Web : Paramètres › Facturation normalisée : mode « Boîtier MeCeF », IFU, **identifiant et nom de l'opérateur** (`seller_id` / `seller_name` ≤ 30) ; poste : synchroniser (le mode descend).
2. Poste : Paramètres › Facturation normalisée : **« Vérifier le boîtier »** → « Boîtier prêt » + NIM, IFU, compteurs. Noter la durée réelle de `/info` (annoncée 4 s). Débrancher : « Boîtier injoignable » (jamais d'erreur rouge).
3. Caisse : un produit, « Facture normalisée », nom (et IFU) ; valider. Contrôler : statut « Normalisée », QR rempli, code, NIM ; **noter le `qr_code` brut** (le format réel remplace l'exemple du Readme) et la réponse brute de `/info`.
4. Cas, un par un : (a) AIB 1 % puis 5 % (le boîtier accepte-t-il le champ `aib` ?) ; (b) remise ; (c) quantité décimale (2,5 kg) ; (d) libellé > 60 caractères ; (e) paiement mobile money, crédit, avance (modes `M`, `A`) ; (f) **boîtier éteint à la validation** : « En attente », puis rallumer : reprise automatique en ≤ 90 s, UNE seule facture sur l'appareil ; (g) **débrancher pendant la transmission** : la vente doit rester marquée « à vérifier » ; vérifier sur l'appareil, puis « Relancer après vérification » ; (h) refus (charge hors schéma) : motif lisible ; (i) vente hors ligne puis synchronisation : le web affiche « Normalisée » ; (j) deux ventes de suite rapides (débit) ; (k) impression du ticket.
5. Web : l'écran Facturation montre la facture « Normalisée » avec le QR du boîtier ; vérifier qu'aucun second envoi ne la modifie.
6. **Avoir** : non branché : à construire après l'essai (NIM-TC).
7. Consigner les réponses brutes, corriger les points « NON vérifié » ci-dessus, puis seulement retirer « (à venir) » du libellé du mode.

---

## 4. LIMITES et NON VÉRIFIÉ (à dire tel quel au client)

1. **AUCUN essai réel contre la DGI** (ni jeton, ni IFU de test). Tout est testé contre des simulations (`Http::fake`) : `agrierp_laravel/tests/Feature/MecefEmecefGatewayTest.php`.
2. **Adresses de l'API** : essai `https://developper.impots.bj/sygmef-emcf/api`, production `https://api.impots.bj/sygmef-emcf/api` (constantes `MecefMode::URL_ESSAI` et `URL_PRODUCTION`) viennent d'un **paquet non officiel** (Banelsems/laraSgmefQR, lu, jamais une dépendance) ; **non confirmées par la DGI**. MECEF-1 avait nommé l'adresse d'essai « production » à tort (corrigé en MECEF-3).
3. **Noms de champs et chemins** (`/invoice`, `/invoice/{uid}/confirm`, `/info/status`, `uid`, `qrCode`, `codeMECeFDGI`, `nim`, `counters`, `dateTime`, `errorCode`, `errorDesc`) : relevés dans ce paquet, **non confirmés**. Une réponse inattendue est dite telle quelle, jamais devinée.
4. **AIB** : champ `aib` `B` (5 %) / `A` (1 %) / omis (N/A), **montant jamais calculé par nous** (la DGI le renvoie, gardé dans `mecef_aib_montant`), règlement envoyé **sans** AIB (le paquet compare les paiements à la somme des lignes). **La DGI peut refuser un total avec AIB** : son motif s'affichera tel quel.
5. Détection de l'expiration et reprise par confirmation seule ; comportement d'une **confirmation d'une facture déjà confirmée** ; arrondis des prix non entiers : non vérifiés.
6. MySQL/MariaDB réel (migration `mecef_status` enum → texte essayée sous SQLite seulement) ; **rendu Windows réel du QR du PDF du poste** ; suites complètes.
7. Mode boîtier : construit contre un faux pilote, JAMAIS essayé avec un vrai boîtier (§ 3.3) ; avoir non branché.
8. Texte d'erreur d'LogiAgriERP à corriger dans LogiALVIA (incohérence relevée) : `EmecefGateway` renvoie « renseignez-le dans Paramètres, Données de l'Entreprise », alors que le formulaire du jeton est l'onglet **« Facturation normalisée (e-MECeF) »**. Dans LogiALVIA, citer le bon onglet.

---

## 5. Procédure du PREMIER ESSAI RÉEL, pas à pas

Source : `docs/PLAN_FINALISATION.md` (MECEF-3, « Parcours du premier essai réel »), complétée. **Toujours sur l'environnement d'ESSAI, jamais en production, avec une vente de test.**

0. **Avant** : sauvegarde de la base ; `APP_KEY` notée en lieu sûr ; compte e-MECeF de l'IFU actif ; jeton d'**essai** obtenu sur le portail de la DGI ; ne pas toucher aux ventes réelles.
1. Paramètres › « Facturation normalisée (e-MECeF) ».
2. Mode « e-MECeF (en ligne) » ; IFU de la ferme (13 chiffres).
3. Préréglage « Environnement d'essai (DGI) » (adresse par défaut) ; coller le jeton ; Enregistrer.
4. **« Tester la configuration »** : attendre « Configuration valide. » Si autre chose : lire la ligne en rouge (« Jeton refusé (401) », « Hôte injoignable », « Adresse introuvable (404) », « L'IFU du jeton (…) n'est pas celui de l'entreprise (…) », « Jeton expiré depuis le … »). **Un échec ici peut venir d'une adresse ou d'un chemin faux (point 2/3 de la section 4) : noter la réponse brute (sans le jeton) pour corriger les constantes.**
5. Caisse : un produit au panier, « Type de Facture » = « Facture normalisée » ; la modale s'ouvre : nom et prénom (IFU si le client en a un), AIB 5 % ; Valider ; « Valider la Vente ».
6. Écran Facturation : la ligne doit passer **« Normalisée »** (QR, code MeCeF/DGI, NIM, compteurs). Si « En attente » : lire le motif sous la pastille, puis « Retransmettre ». Si « Refusée » : le motif de la DGI est affiché tel quel (c'est l'information la plus précieuse du premier essai).
7. Imprimer la facture PDF : QR, IFU, nom, AIB (+ montant calculé par la DGI).
8. **Essais complémentaires, un par un** : (a) client avec IFU ; (b) AIB 1 % puis « Aucun » ; (c) vente avec remise et livraison facturée (prix entiers) ; (d) quantité décimale (2,5 kg) ; (e) **avoir** sur la facture normalisée (FA) ; (f) coupure réseau pendant la transmission puis « Retransmettre » (l'`uid` doit être repris, pas recréé : vérifier qu'une seule facture existe côté DGI) ; (g) une facture simple : rien ne part ; (h) au poste hors ligne puis synchronisation.
9. **Consigner** : date, environnement, jeton masqué, réponses de la DGI par cas, et mettre à jour la section 4 (ce qui devient « vérifié »).
10. **Passage en production** : seulement après accord écrit du client et du cabinet ; changer d'adresse (préréglage « Production (DGI) »), nouveau jeton **de production**, refaire 4 à 7 avec une vraie petite vente validée par le comptable.

---

## 6. LogiALVIA : ce qui existe (relu dans `/home/user/massenon/logialvia`)

Un module MeCeF **complet côté poste**, qui transmet lui-même : `logialvia_app/lib/commercial/domain/services/transmission_mecef.dart` (`ClientMecefHttp`, paquet `http`, **un seul `POST {url}/invoice`** avec jeton porteur, délai 20 s ; `ReponseMecef.depuisJson` essaie plusieurs noms de champs ; `DepotJetonMecef` dans `flutter_secure_storage`), `logialvia_app/lib/commercial/domain/entities/facture_mecef.dart` (`TypeFacture` FV/FA, `StatutFacture` `a_transmettre` · `normalisee` · `rejetee`, `GroupeTaxe` modifiable, groupe par défaut A exonéré), `logialvia_app/lib/commercial/data/tables/facturation_mecef_tables.dart`, `logialvia_app/lib/commercial/data/repositories/factures_mecef_repository_drift.dart`, `logialvia_app/lib/commercial/presentation/viewmodels/factures_mecef_view_model.dart`, `logialvia_app/lib/commercial/presentation/screens/factures_mecef_screen.dart`, `logialvia_app/lib/commercial/presentation/screens/documents_mecef.dart`, réglages `mecefActif`/`mecefUrl`/`mecefNim` dans `logialvia_app/lib/administration/data/tables/parametres_entreprise_table.dart` (BR-ADM-004 : activable seulement si IFU **et** RCCM), test `logialvia_app/test/commercial/factures_mecef_test.dart`. Le fichier de transmission **dit lui-même** que son contrat « n'a pas été éprouvé contre le service réel ».

**Écarts à connaître avant d'aligner (relevés dans `ClientMecefHttp._corps`)** :
- il envoie `price: l.prixUnitaireHt` (**hors taxe**) alors que le pilote documente le prix **avec TVA** (`bill.spec.json` : « Prix avec TVA ») et qu'LogiAgriERP envoie du **TTC** (`items[].price` TTC dans le constructeur) : **à trancher et prouver** ; une facture à prix HT serait fausse ;
- noms de champs différents de ceux d'LogiAgriERP (`client.nom` ↔ `client.name`, `dateTime`, `reference_origine`, `motif`) : **aucun des deux jeux n'est confirmé par la DGI** ;
- pas d'étape de confirmation, pas d'`uid` gardé, pas de verrou : un renvoi peut produire deux factures ;
- groupes de taxe modifiables « non figés » (LogiAgriERP : 0 % = A, 18 % = B, le reste refusé) ;
- numérotation `FV`/`FA` propre à logialvia (clé texte `ref`).

---

## 7. PROMPT — Aligner le module MeCeF de LogiALVIA (transmission côté SERVEUR)

~~~~text
RÔLE
Tu es l'ingénieur serveur (Laravel 12) et l'ingénieur poste (Flutter/Drift) de LogiALVIA. Tu alignes le module MeCeF de logialvia sur celui de LogiAgriERP : la transmission à la DGI se fait par le SERVEUR, le poste n'appelle plus jamais la DGI. Tout en français. Ne commite ni ne pousse sans demande expresse. Jamais de `pkill`.

PRÉREQUIS (si l'un manque : ARRÊTE-TOI et dis lequel)
- Le web de LogiALVIA existe (Laravel + Livewire, `02_ARCHITECTURE_WEB_ET_STACK.md`), l'appairage et la synchronisation du poste passent (`43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md`, S0 à S5), les ventes et leurs lignes sont des tables synchronisables à UUID.
- Réponses du client à la section 8 de `41_MECEF_EMECEF.md` (surtout : TVA autres que 0 et 18 %, AIB, boîtier ou non, qui saisit le jeton, reprise des factures existantes).
- Avant ces prérequis : NE TOUCHE PAS `logialvia_app/lib/commercial/domain/services/transmission_mecef.dart`.

LECTURE OBLIGATOIRE (référence LogiAgriERP, lecture seule)
/home/user/agrierp/agrierp_laravel/config/mecef.php ; app/Support/MecefMode.php, MecefEtat.php, AibTaux.php, FactureType.php ; app/Services/Mecef/MecefGatewayFactory.php, MecefGatewayInterface.php, MecefAvoirGatewayInterface.php, EmecefGateway.php, BoitierMecefGateway.php, FakeMecefGateway.php, MecefFactureBuilder.php, FacturationMecefService.php, ChoixFactureService.php, MecefReglage.php, MecefReglageService.php, MecefConfigurationTesteur.php ; app/Livewire/Parametres/FacturationEmecef.php ; migrations database/migrations/2026_11_07_000001_add_mecef_reglage_to_company_settings.php à …000005_add_delivery_in_total_to_sales_table.php ; tests tests/Feature/Mecef*.php, FactureNormaliseeVerrouTest.php, AvoirMecefTest.php, ModuleMecefDesactiveTest.php, EchecMecefEnvoiAuditTest.php ; poste : agrierp_flutter/lib/features/ventes/choix_facture.dart, agrierp_flutter/test/choix_facture_parite_php_test.dart, mecef_emecef_poste_test.dart, mecef_tirage_test.dart. Et /home/user/agrierp/docs/logialvia/41_MECEF_EMECEF.md (ce fichier), sections 2 à 4.
LogiALVIA (lecture seule) : /home/user/massenon/logialvia/logialvia_app/lib/commercial/domain/services/transmission_mecef.dart, domain/entities/facture_mecef.dart, data/tables/facturation_mecef_tables.dart, data/repositories/factures_mecef_repository_drift.dart, presentation/viewmodels/factures_mecef_view_model.dart, presentation/screens/factures_mecef_screen.dart, documents_mecef.dart, widgets/modale_facture_vente.dart, widgets/onglet_pos.dart ; administration/data/tables/parametres_entreprise_table.dart ; test/commercial/factures_mecef_test.dart.

TÂCHES (une tâche = un commit ; chacune finit vert)

M1 — Décisions écrites. Crée docs/MECEF_DECISIONS.md : taux de TVA admis et groupes de taxe (LogiAgriERP : 0 % = A, 18 % = B, tout autre taux REFUSÉ avec son motif ; ne copie pas sans l'accord du client), AIB (liste, défaut, assiette : « à confirmer »), boîtier oui/non, types FV/FA seulement (EV/EA hors périmètre sauf demande), qui saisit le jeton (administrateur, au web), retransmission automatique oui/non, numérotation de la facture normalisée (celle du serveur ; le code MeCeF/DGI est celui de la DGI), prix envoyés (TTC : à confirmer et à prouver).

M2 — Schéma (serveur ET Drift identiques, UUID, colonnes de synchro).
 company_settings : mecef_mode (desactive|emecef|boitier, NULL = jamais réglé), mecef_api_url, mecef_operateur_id, mecef_operateur_nom, mecef_jeton_encrypted (cast `encrypted`, JAMAIS au poste), ifu (13 chiffres exigés en mode emecef).
 ventes : facture_type (simple défaut|normalisee), client_ifu (13 chiffres, nullable), client_nom_facture (≤150), aib_taux ('5%'|'1%'|'N/A', nullable), mecef_status, mecef_uid, mecef_code, mecef_qr_ref, mecef_nim, mecef_compteurs, mecef_normalise_le, mecef_message, mecef_aib_montant ; avoirs : mêmes colonnes mecef_*. Clés d'état PROPRES dès le départ : en_attente · normalisee · refusee · expiree (pas les anciens noms d'LogiAgriERP).
 clients : ifu (13 chiffres, facultatif).
 Le poste n'ÉCRIT jamais les colonnes mecef_* ; il écrit seulement facture_type, client_ifu, client_nom_facture, aib_taux (liste blanche des champs du poste, comme VENTE_CHAMPS_DU_POSTE).
 Côté Flutter : lib/core/database/app_database.dart puis `dart run build_runner build` ; ne JAMAIS éditer le fichier généré à la main.

M3 — Serveur : reprendre (adapter, pas réécrire de zéro) : MecefMode, MecefEtat, AibTaux, FactureType, MecefGatewayInterface + MecefAvoirGatewayInterface, MecefGatewayFactory (choisit à CHAQUE demande), EmecefGateway, BoitierMecefGateway (squelette si le client n'a pas de boîtier : « Mode boîtier : transmission par le poste non encore disponible. »), FakeMecefGateway (dev et tests), MecefFactureBuilder (UNE fonction d'arrondi, prix entiers), ChoixFactureService, FacturationMecefService, MecefReglage, MecefReglageService, MecefConfigurationTesteur. Règles à conserver à l'identique :
 - UN SEUL essai de création ; `uid` GARDÉ ; reprise par GET /invoice/{uid} puis confirmation seule ; jamais de recréation ; expiree = oublier l'uid ;
 - une facture normalisée n'est JAMAIS retransmise (relue sous verrou) ;
 - la transmission se fait APRÈS la transaction de la vente, jamais dedans ; une panne de la DGI ne bloque ni n'annule jamais une vente ;
 - facture simple : JAMAIS transmise ;
 - jeton : jamais journalisé, jamais dans un message d'erreur, jamais servi au poste ;
 - corrige le texte d'erreur : le jeton se règle dans l'onglet « Facturation normalisée (e-MECeF) ».
 Constantes d'adresse : conserve URL_ESSAI par défaut ; commente EXPLICITEMENT « non confirmée par la DGI ».

M4 — Verrou et avoir. Une vente normalisée n'est ni modifiable ni annulable (modèle + lignes + annulation, web ET poste), message unique : « Facture normalisée : corrigez-la par un avoir. » ; l'avoir d'une vente normalisée part comme FA avec reference = mecef_uid de la facture d'origine ; vente non normalisée : l'avoir n'est pas transmis.

M5 — Poste : RETIRE ClientMecefHttp, DepotJetonMecef et le paquet `http` s'il n'a plus d'autre usage (vérifie par recherche avant de retirer) ; le poste (a) écrit son choix (type, IFU, nom, AIB) par une transposition de ChoixFactureService prouvée par un test de PARITÉ EXÉCUTÉ contre le vrai PHP (modèle : agrierp_flutter/test/choix_facture_parite_php_test.dart), (b) tire les champs mecef_*, (c) dessine le QR (qr_flutter à l'écran, pw.BarcodeWidget dans le PDF) à partir de mecef_qr_ref, (d) affiche les statuts Normalisée / En attente / Refusée / Expirée avec le motif. L'onglet « Facturation normalisée (e-MECeF) » du poste règle mode, IFU, adresse, opérateur par une DEMANDE rejouée par le serveur ; il n'a NI champ de jeton NI bouton « Tester » (voir 42_CONFIG_MECEF_SMTP_LOGO_FAVICON.md, écran (a)).

M6 — Migration des factures existantes de logialvia (table Factures) : a_transmettre → en_attente (facture_type = simple SAUF si le client a demandé la normalisation : à trancher, par défaut simple), normalisee → normalisee, rejetee → refusee ; les références FV/FA, les dates et les montants sont repris tels quels ; ne JAMAIS retransmettre une facture déjà normalisée ; l'ancien jeton du coffre du poste est supprimé à la mise à jour, le client le ressaisit au web (jamais relu). Un test de migration le prouve (base de départ réelle fournie par le client, sinon une base fabriquée dont on dit qu'elle est fabriquée).

M7 — Tests (voir critères) puis documentation : CLAUDE.md du web (section MeCeF) et du poste, manuel.

CONTRAINTES
1. Le serveur est la seule source de la transmission ; le poste ne fait aucun appel réseau vers la DGI.
2. Montants entiers FCFA ; UNE fonction d'arrondi ; aucun autre round( de montant (garde par la source, comme MecefEntiersTest).
3. Les messages de refus sont en français et IDENTIQUES au web et au poste (les mêmes que ceux de la section 2.4).
4. Aucune règle de TVA ou de groupe de taxe devinée : ce que le client n'a pas confirmé est REFUSÉ avec son motif, jamais envoyé.
5. Aucune adresse ni nom de champ présenté comme confirmé par la DGI.
6. Modales ouvertes par événement, jamais par un @if d'écran.

INTERDITS
- Transmettre dans la transaction de la vente. Retransmettre une facture normalisée. Recréer une facture dont l'uid est connu.
- Stocker le jeton au poste, en clair en base, dans une file, un journal, une sauvegarde lisible ou un message.
- Appeler « production » une adresse d'essai. Copier A/B sans l'accord du client.
- Toucher aux ventes réelles pendant les essais. Appeler la vraie DGI depuis les tests automatiques.

CRITÈRES D'ACCEPTATION (vérifiables)
C1. Tests `Http::fake` (Laravel), un par cas : succès (création + confirmation, champs gardés), refus 4xx (état refusee, motif français), 401/403 (en_attente, jeton signalé), 5xx et 429 (en_attente), expiration (expiree, uid oublié), réseau coupé (en_attente, uid conservé si connu), double clic (UNE seule création), reprise après confirmation perdue (GET puis PUT, JAMAIS un second POST /invoice : `Http::assertSentCount`), jeton absent, IFU invalide, mode desactive (rien envoyé), mode boitier (rien envoyé, message exact), charge utile (champs, prix entiers, groupe de taxe, AIB), avoir FA avec reference = uid, facture simple jamais transmise, PDF avec QR.
C2. `MecefEntiersTest` équivalent : jeu de cas écrits À LA MAIN (remise répartie au plus fort reste, écart d'arrondi absorbé, écart > nombre de lignes = REFUSÉE, quantité décimale = quantité 1 + libellé) ; garde par la source : un seul `round(` de montant.
C3. `ChoixFactureService` : type absent = simple ; type inconnu refusé ; nom manquant refusé ; IFU 12 ou 14 chiffres refusé, vide accepté ; AIB hors liste refusé ; messages exacts de 2.4.
C4. Verrou : modification, annulation, suppression de ligne d'une normalisée refusées au web ET à l'envoi du poste (rejet motivé, message exact).
C5. Jeton : jamais dans la réponse de /api/sync/pull (test sur le contenu brut), jamais dans les journaux (test qui écrit un jeton factice reconnaissable et le cherche dans storage/logs et dans la table d'audit), jamais dans un message d'erreur du Testeur.
C6. Poste : plus aucun import de `package:http` dans lib/commercial (recherche) ; test de parité ChoixFacture ↔ PHP exécuté ; test de tirage des champs mecef_* ; le poste ne peut pas écrire mecef_* (un envoi forcé est ignoré/refusé).
C7. Migration : toutes les anciennes factures reprises avec leurs statuts ; aucune retransmission déclenchée (aucun appel HTTP simulé pendant la migration).
C8. Hors ligne : vente normalisée saisie au poste hors ligne → « en attente » ; après synchronisation, le serveur transmet UNE fois ; le poste tire le statut et le QR.
C9. Suite de tests verte ; `flutter analyze` et `flutter test` verts ; docs à jour.
C10. Procédure d'essai réel (section 5 de 41_MECEF_EMECEF.md) recopiée dans la doc de LogiALVIA, avec la mention « NON VÉRIFIÉ contre la DGI » tant qu'elle n'a pas été jouée.

PIÈGES DÉJÀ PAYÉS PAR AGRIERP
- Une vieille vente « à facturer » partie à la DGI à l'insu du client (la migration range en `simple` tout ce qui n'était pas déjà normalisé).
- Prix décimaux envoyés à une API qui attend des entiers (plusieurs round() dispersés).
- Création réussie + confirmation perdue = doublon fiscal si on recrée : GARDER l'uid.
- Normaliser dans la transaction de la vente (rejouée sur interblocage : deux factures).
- Jeton en clair dans une file locale, une sauvegarde lisible ou un journal.
- « Production » écrit pour une adresse d'essai.
- Clés d'état conservées d'un ancien jeu (`transmise`, `erreur`) : 1 500 occurrences à migrer plus tard.
- Pilote du boîtier : 200 même en échec ; lire `qr_code`.

RAPPORT FINAL : fichiers, tests (verts/rouges/sautés), points « NON VÉRIFIÉ contre la DGI », écarts de champs entre logialvia et LogiAgriERP et choix retenu, questions restées ouvertes.
~~~~

---

## 8. Questions au client

1. **Compte e-MECeF existant** : IFU, jeton d'**essai** puis de **production** ? Qui les obtient sur le portail de la DGI ?
2. **Boîtier** (modèle, achat prévu) ou **seulement l'API en ligne** ? (le mode boîtier n'est pas construit, même dans LogiAgriERP)
3. **Qui saisit le jeton** (administrateur, au web, `manage-parametres`) ? Qui le renouvelle à son expiration ?
4. **TVA** : autres taux que 0 % et 18 % ? Groupes C à F nécessaires (export, régime d'exception, TPS, taxe de séjour) ?
5. **AIB** : taux (5 % / 1 %), qui le décide, sur quelle assiette ? (à confirmer avec la DGI ou le cabinet) Défaut 5 % acceptable ?
6. **Prix envoyés** : TTC (cas d'LogiAgriERP et du pilote) ? Les prix de LogiALVIA sont-ils HT ou TTC ?
7. Les ventes **sans client identifié** : facture simple par défaut ?
8. La **Déclaration de TVA** doit-elle inclure les factures simples ? (à confirmer avec le cabinet comptable)
9. **Numérotation** de la facture normalisée : celle du serveur, celle de la DGI (code MeCeF/DGI) ?
10. **Livraison facturée** incluse au total ? **Exportations** (EV/EA) ?
11. **Retransmission automatique** des factures « En attente » (LogiAgriERP : manuelle seulement) ?
12. **Reprise** des factures existantes de LogiALVIA (statuts) : acceptez-vous le rangement en « simple » de tout ce qui n'est pas déjà normalisé ?
13. **BR-ADM-004** de LogiALVIA (module activable seulement si IFU **et** RCCM) : conservé ? (LogiAgriERP exige seulement l'IFU à 13 chiffres en mode e-MECeF.)
14. **NIM** : saisi à la main dans LogiALVIA aujourd'hui (`mecefNim`) ; en e-MECeF il revient de la DGI par facture : garder le champ pour le boîtier seulement ?

---

## 9. Contrôle de ce fichier

Chemins vérifiés par `ls` le 07/11/2026 : tous ceux de `agrierp_laravel/app/Services/Mecef/`, `app/Support/MecefMode.php`, `MecefEtat.php`, `AibTaux.php`, `FactureType.php`, `app/Livewire/Parametres/FacturationEmecef.php`, `app/Livewire/Facturation/Facturation.php`, `config/mecef.php`, les tests `Mecef*Test.php`, `AvoirMecefTest.php`, `FactureNormaliseeVerrouTest.php`, `ModuleMecefDesactiveTest.php`, `EchecMecefEnvoiAuditTest.php` ; `/home/user/issotina/eltrade-cc300-driver/{Readme.md,bill.spec.json,server/server.go,server/handlers.go}` ; les fichiers de `logialvia_app/lib/commercial/...` cités. **Non vérifiés** : `docs/MECEF_DECISIONS.md` (à créer) ; l'existence d'un test `Http::fake` précis pour chaque cas listé en C1 dans LogiALVIA (à écrire) ; toute adresse ou champ de la DGI (section 4).
