# 10 — BRS : exigences métier (Business Requirements) de LogiALVIA, web + poste

## USAGE

- **Quand l'utiliser** : au tout début du chantier « WEB de LogiALVIA » (après `01_MASTER_PROMPT.md`), puis à chaque fois que le client change de périmètre ou tranche une question ouverte. C'est le document de plus haut niveau : il dit POURQUOI ; le PRD (`11_`) dit QUOI pour QUI ; le SRS (`12_`) dit COMMENT le système se comporte ; le FRS (`13_`) dit les fonctions testables ; le NFRS (`14_`) dit les seuils ; `15_REGLES_METIER.md` dit les formules.
- **Ordre** : `01_MASTER_PROMPT` → `02_ARCHITECTURE_WEB_ET_STACK` → **10 → 11 → 12 → 13 → 14 → 15** → `20_MODULES_INDEX` et modules `21_` à `29_`. (Documents voisins écrits en parallèle : `README`, `03_DEVELOPMENT_STANDARDS`, `04_UI_UX_DESIGN_SYSTEM`, `30_DATABASE`, `31_TESTING_QA`, `32_SKILLS_LIBRARY`, `40_PWA_HORS_LIGNE`, `41_MECEF_EMECEF`, `42_CONFIG_MECEF_SMTP_LOGO_FAVICON`, `43_APPAIRAGE_SYNCHRO_MODALE_ALERTES`.)
- **Entrées** : `logialvia/docs/B1_BRS_Business_Requirements.md`, `B2_PRD_Product_Requirements.md`, `B6_Regles_Metier.md`, `I1_Matrice_RBAC.md`, `I2_Gestion_Modules_Actifs.md`, `INDEX_MAITRE.md`, `docs/logialvia/GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md` (§0 et bloc 14), `docs/DOCTRINE_PORTAGE.md`, `docs/PLAN_FINALISATION.md`.
- **Sorties** : ce fichier mis à jour (exigences `BR-nnn` numérotées, sourcées, avec statut CONFIRMÉ / PROPOSÉ / À DÉFINIR AVEC LE CLIENT) + la liste des questions ouvertes (section 6).
- **Convention de chemins** : `logialvia/docs/…` = `/home/user/massenon/logialvia/docs/…` (dépôt public `massenon/logialvia`, LECTURE SEULE) ; `logialvia_app/…` = `/home/user/massenon/logialvia/logialvia_app/…` ; sans préfixe = monorepo `/home/user/agrierp` (`agrierp_laravel/…`, `agrierp_flutter/…`, `docs/…`). Chemins vérifiés par `ls` le 07/11/2026.

---

## 1. PROMPT — « Rédige / mets à jour le BRS de LogiALVIA »

> **Rôle.** Tu es analyste métier senior (agriculture tropicale, ERP, droit comptable OHADA/Bénin). Tu rédiges en français.
> **Contexte.** LogiALVIA (ALLMANY ET COMPAGNIE, Natitingou, Bénin) est aujourd'hui une application Flutter Windows hors ligne (Drift, 31 écrans, 6 filières). Décision du client du 07/11/2026 : « on va CRÉER LE WEB » (Laravel + Livewire, mêmes conventions que LogiAgriERP, monorepo `/home/user/agrierp`). Le poste Windows reste, devient client du serveur (appairage, synchronisation).
> **Tâches.** (1) Relis les sources listées en USAGE ; (2) pour chaque exigence de la section 3, vérifie qu'elle est vraie dans la source citée ; corrige-la sinon ; (3) ajoute toute exigence manquante, une par ligne, `BR-nnn`, texte à l'indicatif, mesurable, avec source ; (4) classe chaque ligne CONFIRMÉ (source écrite du client ou de logialvia), PROPOSÉ (reprise d'AgriERP, à valider) ou À DÉFINIR ; (5) tiens à jour la section 5 (écarts de périmètre) et la section 6 (questions).
> **Contraintes.** Tout en français. Aucune règle métier inventée : ce qui n'est dans aucune source est marqué « À DÉFINIR AVEC LE CLIENT » avec une question précise (fermée, à réponse courte). Les exigences d'AgriERP sont des PROPOSITIONS pour LogiALVIA, jamais des faits (AgriERP est l'exploitation Ferme École OLOUWACHEGOUN, un autre client). Citer la source de chaque ligne (fichier + section).
> **Critères d'acceptation (vérifiables).** (a) chaque `BR-nnn` a : id unique, énoncé, source, statut, priorité (M/S/C) ; (b) `grep -c '^| BR-' 10_BRS_BUSINESS_REQUIREMENTS.md` ≥ 40 ; (c) aucun `BR-` sans source ; (d) la section 6 liste TOUTES les lignes « À DÉFINIR » ; (e) les contradictions B1/B2/B3 (4 rôles) vs I1 (3 rôles), B1 §6 (« pas de multi-poste ») vs décision du 07/11/2026, sont écrites en section 5 ; (f) aucun chemin cité n'est inexistant (`ls`).
> **Interdits.** Ne pas modifier le dépôt `logialvia` ; ne pas écrire hors `docs/logialvia/` ; ne pas copier un chiffre d'AgriERP comme s'il était celui d'ALLMANY ; ne pas résoudre une contradiction en silence ; ne pas promettre la PWA hors ligne ni la paie comme acquises.

---

## 2. Contexte de l'entreprise et parties prenantes

ALLMANY ET COMPAGNIE (promoteur : SIDI ALI Raïmatou ; « la Gérante » dans les sources), Natitingou, Bénin. Élevage avicole (Goliaths, Pintades, Poulets de chair, Pondeuses) avec couvoir, cuniculture (Lapins), pisciculture (Poissons-Chats), commerce annexe (fournitures scolaires, textile) au même point de vente [B1 §1]. Effectif de référence : 31 Goliaths matures, 28 Pintades matures [B1 §1 ; F2 « Cohérence transversale »]. Fournisseur type : Maïs Local ; client débiteur type : AGOSSOU Prudence [F7].

| Partie prenante | Intérêt | Source |
|---|---|---|
| Direction / Gérante (admin) | Pilotage, rentabilité, chiffres fiables, arbitre les questions ouvertes | B1 §3 |
| Animalier (« Agent d'Élevage ») | Saisie quotidienne rapide, sans ambiguïté | B1 §3, I1 |
| Caissier (« Agent de Vente ») | Encaissement fluide devant un client | B1 §3, I1 |
| Comptable | Rôle à part entière : TRANCHÉ (DV-07, `16_DECISIONS_VALIDEES.md`) ; celui qui encaisse n'est pas celui qui comptabilise (voir §5, E-ROL) | B1 §5, DV-07 |
| Éditeur / FAGUEZ SARL – PAEB | Livre et maintient ; support | F1 pied de carte, F9 |
| DGI (Bénin) | Facturation normalisée MeCeF/e-MECeF | B6 BR-ADM-004, guide bloc 19 |
| Administrateur du serveur web (NOUVEAU) | Hébergement, sauvegardes, mises à jour | guide 14.2 D-SRV-7 |

## 3. Exigences métier de départ

Statut : **C** = confirmé par une source de logialvia ; **P** = proposé (reprise AgriERP) ; **D** = À DÉFINIR AVEC LE CLIENT. Priorité : M = must, S = should, C = could.

| ID | Exigence | Source | Statut | Prio |
|---|---|---|---|---|
| BR-001 | Éliminer la ressaisie des fiches papier : 100 % des mouvements journaliers (achats, naissances, morts, dons, ventes) saisis dans l'application, zéro registre papier parallèle après déploiement. | B1 OB-1 | C | M |
| BR-002 | Le stock vendable affiché est exact en temps réel : une vente le décrémente immédiatement, sans écart avec le physique. | B1 OB-2 ; B4 FRS-VTE-01 | C | M |
| BR-003 | Une vente simple (sélection → encaissement → reçu) se fait en moins de 60 secondes. | B1 OB-3 ; B2 §6 | C | M |
| BR-004 | Le tableau de bord consolide effectifs, mortalité et ventes du jour de toutes les filières sans recalcul manuel. | B1 OB-4 | C | M |
| BR-005 | Le travail du poste continue sans réseau (zone rurale). Avec le web : le poste reste utilisable hors ligne et se synchronise au retour du réseau. | B1 OB-5 ; guide bloc 16 | C | M |
| BR-006 | Les écrans reproduisent fidèlement les fiches papier et le prototype validé (colonnes, libellés, position des boutons). | B1 §2 ; B2 §4 | C | M |
| BR-007 | Six filières d'élevage sont gérées : `goliaths`, `pintades`, `lapins`, `poulets`, `pondeuses`, `poissons-chats`, par UN seul écran générique configuré. | `logialvia_app/lib/elevage/domain/entities/configuration_espece.dart` ; B5 NFRS-SCAL-02 | C | M |
| BR-008 | L'exploitation suit le cycle de couvoir/incubation (Goliaths, Pintades) en continu, avec mirages J+7 et J+14. | F3 « Couveuse multi-âges » | C | M |
| BR-009 | Un calendrier de soins et de prophylaxie par bande, un suivi d'infirmerie, des délais d'attente (rémanence) exploités. | F3 ; guide bloc 6 | C | M |
| BR-010 | Un point de vente (panier, remise, Espèces / Mobile Money / Avance), des devis, un historique, des retours et avoirs. | B1 §5 ; H1 | C | M |
| BR-011 | Les produits vendables et les intrants (provende, vétérinaire) sont deux stocks distincts. | B6 BR-VTE-006 ; B4 FRS-STK-01 | C | M |
| BR-012 | La comptabilité est conforme SYSCOHADA : journal, grand livre, balance, bilan, compte de résultat, TAFIRE, notes annexes ; chaque opération commerciale génère ses écritures équilibrées. | F6 ; B6 BR-CPT-003 | C | M |
| BR-013 | Exercices comptables : clôture annuelle définitive avec report à nouveau, clôture mensuelle déblocable par l'admin ; lecture seule d'un exercice clos. | J1 ; B6 BR-CPT-001/002/006 | C | M |
| BR-014 | La conformité fiscale MeCeF n'est activable que si IFU et RCCM sont renseignés. | B6 BR-ADM-004 ; F8 onglet 2 | C | M |
| BR-015 | La facturation distingue facture simple (jamais transmise) et facture normalisée (transmise à la DGI), avec avoir pour toute correction d'une facture normalisée. | guide bloc 19 ; `logialvia_app/lib/commercial/data/tables/facturation_mecef_tables.dart` | P | M |
| BR-016 | Devise unique : franc CFA (entiers pour les montants facturés). Dates métier à l'heure du Bénin (UTC+1 fixe). Interface exclusivement en français. | B1 §7 ; B3 §5 ; guide 14.1 | C | M |
| BR-017 | **Quatre rôles** (administrateur, comptable, caissier, animalier) ; chacun ne voit que ses modules ; le comptable comptabilise, le caissier encaisse. TRANCHÉ (DV-07). | I1 ; B6 BR-ADM-001 ; `16_` DV-07 | C | M |
| BR-018 | Les filières Poissons-Chats, Poulets/Pondeuses et Lapins sont activables/désactivables sans perte de données (désactivées par défaut) ; Goliaths et Pintades sont toujours actives. | I2 ; F8 onglet 1 | C | M |
| BR-019 | Toute suppression significative est journalisée (qui, quand, quoi) ; « supprimer » archive et passe par une corbeille ; seule l'admin purge ; **les écritures comptables n'entrent jamais en corbeille** (contre-passation). TRANCHÉ (DV-05). | B6 BR-ADM-003 ; F8 « Corbeille » | C | M |
| BR-020 | Un serveur web central existe (Laravel + Livewire) : décision du client du 07/11/2026. Le web devient le maître des règles, le poste lui est fidèle. | guide §0 et 14.1 | C | M |
| BR-021 | Plusieurs postes et le web partagent les mêmes données ; la synchronisation est automatique, jamais silencieuse en cas d'échec ; la règle de conflit dépend de la nature de la donnée. | guide bloc 16 | P | M |
| BR-022 | Un compte se crée, se modifie, s'archive, se réactive ; l'admin réinitialise un mot de passe oublié (temporaire, changement forcé) ; pas de réinitialisation par e-mail. | guide bloc 2 | P | M |
| BR-023 | Sauvegarde de la base, restauration contrôlée, remise à zéro des données de test derrière double verrou. | F8 ; guide D-SRV-7 | C | M |
| BR-024 | Importation en masse par tableur xlsx (stocks d'abord) avec modèle à télécharger : « très important » selon le client. N'existe NI dans logialvia NI dans AgriERP : conception à valider. | guide bloc 21 | D | M |
| BR-025 | Le web est installable (PWA). Le travail hors connexion DANS LE NAVIGATEUR n'existe pas dans AgriERP : seulement si le client le confirme. | guide bloc 20 ; `agrierp_laravel/tests/Feature/PwaEtPolicesLocalesTest.php` | D | S |
| BR-026 | Créances et dettes : aucune échéance n'est inventée ; sans délai fixé, la créance est « Sans échéance », jamais « en retard ». | F4 « Échéances de paiement » | C | M |
| BR-027 | Le stock de produits finis est valorisé au coût de revient (jamais au prix de vente) ; un article sans coût est « Non valorisé » et sort des totaux. | F4 « Coût de revient » | C | M |
| BR-028 | Le Mobile Money n'est qu'une information de traçabilité, pas une transaction bancaire réelle. | B1 §6 | C | M |
| BR-029 | Aucun bouton, message ou donnée décoratif : tout bouton écrit réellement ou n'existe pas ; un message de succès n'est affiché qu'après écriture effective. | `logialvia/docs/A1_MASTER_PROMPT.md` §2.3 ; F1 | C | M |
| BR-030 | Une donnée inconnue s'affiche « — », jamais 0 (moyenne sur zéro échantillon, total non calculable). | F2 ; guide 14.1 | C | M |
| BR-031 | Rapports et exports : PDF pour tous les états ; export tableur (xlsx) ; lettre de relance. | F7 ; J2 ; guide bloc 7 | P | S |
| BR-032 | Notifications : alertes de stock sous seuil, mortalité anormale, soins à venir ou en retard, éclosion imminente, rappels de prophylaxie. | F2 ; guide bloc 18 | P | M |
| BR-033 | Module Paie/RH : B1 §6 le déclare hors périmètre ; AgriERP en possède un complet (barème béninois). Décision du client requise. | B1 §6 ; `agrierp_laravel/app/Services/PayrollCalculationService.php` | D | C |
| BR-034 | Pisciculture : les stades, la mortalité, la biomasse, le cycle bassin, l'aliment et la vente au poids ne sont définis que partiellement (voir `15_REGLES_METIER.md` §7). | F3 ; configuration_espece.dart | D | M |
| BR-035 | Pintades : stades et durées, rations, reproducteurs distincts non confirmés. | F3 ; I2 | D | M |
| BR-036 | Goliaths : barème de ration générique, à valider avec la Gérante. | configuration_espece.dart `noteRationnement` | D | M |
| BR-037 | Mise en production : serveur d'abord, postes ensuite ; essai multipostes avant livraison. | guide 14.3 W9 ; `docs/GUIDE_DEPLOIEMENT.md` | P | M |
| BR-038 | Un compte administrateur initial existe au premier lancement ; son mot de passe initial doit être changé de force à la première connexion. | F1 « Compte Administrateur Initial » (`TODO(dette)`) | C | M |
| BR-039 | Le verrouillage de connexion après 5 échecs consécutifs dure 15 minutes (au web : persistant côté serveur). | F1 « Verrouillage après 5 échecs » | C | M |
| BR-040 | Modes de règlement : Espèces et Mobile Money ; « Avance » est une condition de paiement (statut), non un canal. | F8 onglet 4 | C | M |
| BR-041 | Un module bien documenté pour l'utilisateur : aide par écran, visite guidée, manuel PDF. | `logialvia_app/lib/core/tour/tour_guide.dart` ; `logialvia/docs/manuel/` | C | S |
| BR-042 | Un seul vocabulaire par filière : « couveuse » n'apparaît que chez Goliaths et Pintades ; les poissons ne « naissent » pas en couveuse (colonne « Nés »). | F3 « Glossaire des filières » | C | M |
| BR-043 | La ration des poissons-chats se calcule en pourcentage de la biomasse par jour (effectif × poids moyen × taux), par classe de poids, barème éditable ; poids moyen recalculé par pesée d'échantillon tous les 15 jours. TRANCHÉ (DV-01) ; taux = repères à valider. | `16_` DV-01 ; `15_` RM-ELV-09b | C | M |
| BR-044 | À chaque vente ou récolte de poisson, le poids (kg) ET le nombre de sujets sont saisis ; si le nombre est inconnu il est estimé (kg ÷ poids moyen de la dernière pesée) et la ligne est marquée « estimé ». TRANCHÉ (DV-02). | `16_` DV-02 ; `15_` RM-ELV-12 | C | M |
| BR-045 | Pintades : stade « pintadeaux » ; incubation 28 jours, durée PARAMÉTRABLE avec fenêtre 26–28 j, deux modes (couveuse, couvaison naturelle), rappels J7, J14, J25. TRANCHÉ (DV-03) ; repères d'incubateur à valider. | `16_` DV-03 ; `15_` RM-COU-01, RM-COU-06 | C | M |
| BR-046 | L'autonomie de provende a deux seuils paramétrables par ferme : alerte à 7 jours (défaut = délai d'approvisionnement + marge de sécurité), critique à 3 jours. TRANCHÉ (DV-04). | `16_` DV-04 ; `15_` RM-ELV-10 | C | M |
| BR-047 | Une écriture comptable ne se supprime pas et ne se restaure pas : elle se contre-passe ; elle n'entre jamais dans la corbeille (intangibilité OHADA). TRANCHÉ (DV-05). | `16_` DV-05 ; `15_` RM-CPT-09 | C | M |
| BR-048 | Le caissier n'accède pas à `/inventaire` (administrateur, et responsable stock s'il existe) ; sur `/factures-mecef` il consulte et réimprime, sans annuler, retransmettre ni créer d'avoir. La matrice fait foi, le code la suit. TRANCHÉ (DV-06). | `16_` DV-06 ; `20_` §3 | C | M |
| BR-049 | Séparation des fonctions : le périmètre du comptable (comptabilité, rapports, gestes de facturation interdits au caissier) est distinct de celui du caissier ; périmètre exact à confirmer (Q-DV-7). | `16_` DV-07 | P | M |

## 4. Objectifs mesurables (reprise de B1/B2)

| Objectif | Cible | Source |
|---|---|---|
| Temps de saisie d'une fiche journalière complète | < 3 min par espèce | B2 §6 |
| Transaction POS simple | < 60 s | B1 OB-3 |
| Écrans à données réellement persistées | 100 % avant production | B2 §6 |
| Registres papier parallèles après déploiement | 0 | B2 §6 |
| Prise en main (utilisateur du prototype) | < 15 min | B5 NFRS_UTIL-01 |
| Clics pour toute fonction depuis l'accueil | ≤ 3 | B5 NFRS-UTIL-02 |

## 5. Écarts, contradictions et changements de périmètre (à ne pas résoudre en silence)

| Réf. | Constat | Décision proposée |
|---|---|---|
| E-ROL | B1 §5, B2 §3, B3 SRS-F-09 parlent de 4 rôles (« Comptable ») ; I1 (corrigé par K4) prouvait 3 rôles ; AgriERP en a 4. | **TRANCHÉ (DV-07)** : 4 rôles (admin, comptable, caissier, animalier). Corriger I1/K4 dans logialvia. |
| E-SRV | B1 §6 : « pas de synchronisation multi-postes, pas de serveur central » ; A1 §5 : « pas de backend » ; F3 : « aucun serveur HTTP n'est embarqué ». | Périmètre élargi par la décision du 07/11/2026 (BR-020/021) ; amender B1 §6 et A1 §5. |
| E-MOB | B1 §6 : « application mobile hors périmètre ». | Le web est responsive/PWA ; mobile natif reste hors périmètre ; hors ligne navigateur : BR-025 (D). |
| E-RH | B1 §6 : RH/paie hors périmètre ; le client la liste dans la mission « paie ». | BR-033 (D) ; module `27_MODULE_RH_PAIE.md` écrit en option. |
| E-PIN | `docs/logialvia/GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md` §0 : 5 filières (B1) vs 6 identifiants dans le code (`poulets` et `pondeuses` séparés). | Compter 6 identifiants, 5 écrans de fiche (poulets+pondeuses = 1 écran à 2 onglets). |
| E-INC | Incubation Pintade : prototype et INDEX_MAITRE 27 j ; F3 v21 : 28 j (correction de la Gérante). | **TRANCHÉ (DV-03)** : 28 j, paramétrable, fenêtre 26–28 j ; corriger `INDEX_MAITRE`. |
| E-SEC | F1 : SHA-256 + sel au poste ; avec le web : hash serveur, jeton par poste, PIN PBKDF2 (guide D-SRV-5). | Appliquer D-SRV-5 ; reprise des comptes par mots de passe temporaires. |
| E-ID | logialvia : clés entières autoincrémentées ; web partagé : UUID. | Migration UUID (guide D-SRV-3), palier Drift `from < 27`. |

## 6. Questions ouvertes au client (à poser telles quelles)

1. **Q-ROL-1** TRANCHÉ (DV-07) : rôle « comptable » distinct, 4 rôles. Reste le périmètre exact du comptable : Q-DV-7.
2. **Q-RH-1** La paie et le registre du personnel (employés, stagiaires, pointage) doivent-ils entrer dans LogiALVIA ? Si oui : combien d'employés, quel barème d'impôt sur salaires et quels taux CNSS/VPS pratiqués chez ALLMANY ?
3. **Q-IMP-1** Quels modules importer par xlsx (stocks, produits, clients, fournisseurs, plan comptable, effectifs de départ des bandes) et dans quel ordre ?
4. **Q-PWA-1** Besoin explicite de travailler sans réseau dans un navigateur (tablette, téléphone) ? Quels appareils, combien de temps hors ligne ?
5. **Q-HEB-1** Hébergeur, nom de domaine, qui administre le serveur et télécharge les sauvegardes ?
6. **Q-MEC-1** Mode MeCeF visé : e-MECeF en ligne (sans boîtier) ou boîtier ? Jeton e-MECeF, IFU et RCCM disponibles ?
7. **Q-PIS-1 … Q-GOL-1** : voir `15_REGLES_METIER.md` §7 (pisciculture, pintades, goliaths) ; Q-PIS-5, Q-PIS-6 et Q-PIN-4 TRANCHÉES (DV-01, DV-02, DV-03).
8. **Q-ELV-1 … Q-ELV-7** : voir `15_REGLES_METIER.md` §1 (glossaire lapins, départ obligatoire, cascade, ventes ventilées).
9. **Q-CPT-1 … Q-CPT-5** (Q-CPT-3 TRANCHÉE, DV-05) : voir `15_REGLES_METIER.md` §5 et `26_MODULE_COMPTABILITE_EXERCICES.md`.
10. **Q-TVA-1** Entreprise assujettie à la TVA (taux 0 % et 18 % seulement) ? Une facture simple figure-t-elle dans la déclaration de TVA ?
11. **Q-ADM-1** Politique de mot de passe (longueur, majuscule, chiffre) ? (logialvia : 8 caractères minimum.)
12. **Q-VTE-1** Délai de paiement par défaut des ventes à crédit (jours) ?
13. **Q-DV-1 … Q-DV-8** : nouvelles questions nées des décisions validées du 08/11/2026 (barème en % de biomasse, arrondi de l'estimation, mortalité des pintadeaux, marge de sécurité, responsable stock, onglet Retours et Avoirs, périmètre du comptable, libellé du jeune pintade) : voir `16_DECISIONS_VALIDEES.md` §4.
14. Questions FERMÉES le 08/11/2026 : Q-ROL-1, Q-ALR-1, Q-CPT-3, Q-PIS-5, Q-PIS-6, Q-PIN-4 (voir `16_`).

## 7. Critères d'acceptation du document

- [ ] Toute ligne `BR-` : source présente, statut C/P/D.
- [ ] Les 8 écarts de la section 5 sont présents et chacun a une décision proposée.
- [ ] La section 6 liste chaque statut D.
- [ ] `ls` des chemins cités sans erreur (script : extraire les `…` entre accents graves contenant `/`).
