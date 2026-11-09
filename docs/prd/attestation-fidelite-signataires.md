# PRD — Attestation : fidélité au modèle officiel, signataires selon la durée (web et poste) · et boutons de « Bandes & Sujets » sur une ligne
**Statut :** livré · **Date :** 2026-10-27 · **Ticket :** ATT-2 (suite d'ATT-1) · **Surfaces :** web (`AttestationService`, Livewire `RH\Attestations`), poste (`attestations_vue.dart`), serveur (API du poste)

## 1. Problème
- **L'attestation ne ressemble pas au modèle fourni par le client** (attestation de formation du 24/10/2026) : pas de logo, pas de filigrane, pas de décor, police et composition différentes, signatures en trois blocs fixes, libellés des domaines abrégés, aucune formule « En foi de quoi… », texte sans gras.
- **Qui signe n'était pas une règle.** Les trois blocs (Examinateur, Président du Jury, Directeur) étaient toujours imprimés. Le client veut : **d'un mois à un an, seul le promoteur signe ; au-delà d'un an, trois personnes signent**, et que cela soit **paramétrable**.
- **Le poste divergeait du web** : numérotation des signataires inversée (position 1 = Examinateur au poste, = Directeur au serveur), civilité et signataires envoyés par le poste mais **ignorés** par l'API (arguments passés dans le mauvais ordre : l'appréciation tombait dans la civilité), constantes locales à la place des valeurs du modèle.
- **« Bandes & Sujets » :** les trois boutons d'en-tête (Enregistrer des Sujets, Registre des Reproducteurs, Nouvelle Bande) se répartissaient sur deux lignes.

## 2. Objectifs
- Le PDF reproduit le modèle : **logo réel de la ferme** en en-tête, **logo en filigrane**, décor floral des coins, titre, corps en gras / vert, puces ➢, appréciation, formule de clôture, signataires, pied de page.
- **Un seul visuel**, deux fabriques fidèles : le serveur produit le PDF du web (DomPDF), le poste produit le sien (package `pdf`, hors ligne comprise) — mêmes mesures, mêmes polices libres, mêmes images, mêmes règles de signature (ATT-3, demande du client : « le poste doit produire aussi »).
- La règle de signature est **une donnée du modèle**, modifiable au web et au poste : seuil de durée, signataires, palier de chacun.
- Les trois boutons de « Bandes & Sujets » restent **sur une ligne**.

## 3. Non-objectifs
- Les cases « Filigrane / En-tête / Signature / Cachet » du modèle (ignorées du PDF) : hors périmètre, le filigrane et l'en-tête sont toujours imprimés.
- Signature manuscrite ou cachet numérique (images) : non demandé.
- Un second gabarit (portrait, autre ferme) : non demandé.
- ~~Le poste ne fabrique pas le PDF~~ — **corrigé (ATT-3)** : le poste fabrique le PDF. Ce que le serveur garde : **le numéro** (`N°04/2026/FEO/DG`, jamais inventé au poste) et **la trace d'audit** (`POST /api/attestations/emissions`, idempotent par l'identifiant d'émission tiré au poste, table `attestation_emissions`). Hors ligne : PDF produit quand même, numéro vide `N°—/AAAA/FEO/DG`, émission mise en file (`app_settings`) et déclarée à la synchronisation suivante. Question ouverte : le numéro vide d'un document imprimé hors ligne n'est pas rétro-imprimé ; le numéro attribué s'affiche au registre.

## 4. Règle de signature (paramétrable)
| Palier | Durée (début → fin, à aujourd'hui sans fin) | Signataires par défaut |
|---|---|---|
| **court** | jusqu'à **12 mois inclus** (`seuil_signature_mois`) | le promoteur seul : **Directeur Général** |
| **long** | au-delà | **Examinateur**, **Président du Jury**, **Directeur Général** (de gauche à droite) |

- Par modèle (employé / stagiaire) : `seuil_signature_mois` (1 à 120), et pour chaque signataire (position 1 = Directeur, 2 = Examinateur, 3 = Président du Jury) : intitulé, nom, fonction, « signe le palier court », « signe le palier long ».
- Durée comptée en mois calendaires depuis la date de début : **du 15/10/2025 au 15/10/2026 = 12 mois = palier court ; le 16/10/2026 = palier long.** Sans date de début : palier court.
- À l'émission, intitulé / nom / fonction se **modifient pour cette attestation** (champ vide = le modèle) ; on ne peut pas faire signer un signataire que la règle n'appelle pas.
- Une appréciation par défaut (phrase standard du modèle fourni) s'imprime ; le modèle peut la supprimer (`appreciation_imprimee`) ; la saisie de l'émetteur la remplace toujours.

## 5. Exigences et critères d'acceptation (P0)
- **R1 — PDF fidèle.** A4 paysage, polices libres équivalentes (Caladea ≈ Cambria, Carlito ≈ Calibri, Bevan pour le titre), logo `resources/attestation/images/logo-ferme.png` (identique au logo officiel du site, test), filigrane, décor extrait du modèle.
  - [ ] Un seul A4, aucun débordement avec les quatre domaines, l'appréciation et trois signataires.
  - [ ] Les positions (en-tête, date, numéro, titre, corps, puces, signatures, pied) sont celles du modèle à ± 4 pt (relevées sur la capture 2000 × 1413 px).
- **R2 — Règle de signature.** Migration `2026_10_27_000001` ; `AttestationService::palier()` / `signataires()`.
  - [ ] 12 mois exacts : le promoteur seul ; 12 mois et un jour : trois signataires, dans l'ordre Examinateur, Président, Directeur.
  - [ ] Seuil, palier de chaque signataire, intitulés, noms, fonctions : modifiables (web : « Personnaliser les Modèles » ; poste : même onglet, `PUT /api/attestation-templates/{type}`), refus du seuil hors 1 à 120 avec les mêmes mots des deux côtés.
- **R3 — Web et poste identiques.** Le poste reçoit la règle au tirage (`attestation_templates`), la calcule en local pour l'aperçu (**parité exécutée contre le PHP** : `test/attestations_parite_php_test.dart`, 31 cas dont fins de mois et années bissextiles) et envoie civilité et signataires modifiés sous les clés du serveur (`sig2_nom`…). Drift **v66**.
- **R4 — « Bandes & Sujets ».** Dès `xl` (1280 px), `xl:flex-nowrap` + `whitespace-nowrap` (web), `Row` au lieu de `Wrap` (poste) ; sous `xl` les boutons passent sous le titre.

## 6. Questions ouvertes
- **Un an exactement (bloquante pour le client).** Le modèle fourni est une formation d'**un an** (15/10/2025 → 15/10/2026) signée par **trois** personnes, alors que la consigne dit « d'un mois à un an : le promoteur seul ». Le défaut applique la consigne à la lettre (12 mois inclus = promoteur seul). Si un an doit être signé par trois : régler le seuil à **11** dans « Personnaliser les Modèles » — aucun code à changer.
- **Signataires par défaut.** Examinateur et Président du Jury sont ceux du modèle fourni (SOGNIGBE Gbédjinou Serge Bruno, Elisée Kocou HOUNKPONOU) : à confirmer ou remplacer dans les modèles.
- **Décor.** Il est extrait d'une **capture** du modèle : si le client fournit le fichier d'origine (Word / PDF), remplacer `decor-floral.png` pour une fidélité parfaite.
- **Polices.** Le modèle emploie Constantia / Cambria / Rockwell (propriétaires) : les équivalents libres s'en approchent sans être identiques (coupes de lignes reproduites sur l'exemple fourni).

## 7. Skills identifiés pour l'implémentation
| Besoin | Skill |
|---|---|
| Conventions Laravel / Livewire / RBAC du projet (web) | `anthropic-skills:agrierp-laravel` |
| Production et contrôle du PDF (rendu, comparaison) | `anthropic-skills:pdf` |
| Spécification puis plan d'un ticket | `prd`, `plan` (dépôt), `product-management:write-spec` |
| Poste Flutter | règles de `agrierp_flutter/CLAUDE.md` (aucun skill dédié) |
