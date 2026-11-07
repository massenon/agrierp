# 15 — RÈGLES MÉTIER reportables de LogiALVIA (formules + jeux de cas calculés à la main)

## USAGE

- **Quand l'utiliser** : avant d'écrire tout calcul (effectif, rationnement, stock, comptabilité, TVA, paie, facture) ; chaque règle ci-dessous se recopie en test unitaire AVANT le code (TDD), au web (PHP) comme au poste (Dart). Les jeux de cas sont calculés À LA MAIN : ils ne sont jamais produits par le code testé. Dès que le web d'un module existe, la parité est EXÉCUTÉE contre le vrai PHP (modèle : `agrierp_flutter/test/php_laravel.dart`) et les cas à la main restent la vérité de départ.
- **Ordre** : `10_BRS` → `11_PRD` → `12_SRS` → `13_FRS` → `14_NFRS` → **`15_REGLES_METIER`** → modules `21_` à `29_` (qui citent les `RM-`). Le guide `docs/logialvia/GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md` (blocs 1 à 13) reste la référence détaillée des pièges ; ce fichier n'en recopie que les formules et les cas.
- **Entrées** : `logialvia/docs/B6_Regles_Metier.md`, `05_LOGIQUE_CALCUL_FORMULAIRES.md`, `F3` à `F6`, `H2`, `J1`, `logialvia_app/lib/elevage/domain/entities/configuration_espece.dart`, `logialvia_app/lib/elevage/domain/services/*.dart`, `logialvia_app/lib/comptabilite/domain/services/moteur_comptable.dart`, `agrierp_laravel/app/Services/{EffectifParCategorieService,PayrollCalculationService,VatDeclarationService,TvaSettingService,AvoirClientService}.php`, `agrierp_laravel/database/seeders/IncomeTaxBracketsSeeder.php`.
- **Sorties** : ce fichier à jour ; toute nouvelle règle reçoit un `BR-…` dans `logialvia/docs/B6_Regles_Metier.md` (convention de logialvia : numérotation `BR-ELV-011…`) PUIS un `RM-` ici.
- **Légende** : **[LOGIALVIA]** règle écrite dans les sources de logialvia (CONFIRMÉE) ; **[AGRIERP→PROPOSÉE]** règle d'AgriERP proposée pour LogiALVIA (à valider par le client) ; **À DÉFINIR AVEC LE CLIENT** : aucune source ne la tranche, aucune formule n'est donnée.
- **Chemins** : `logialvia/…` = `/home/user/massenon/logialvia/…` (lecture seule) ; sans préfixe = monorepo `/home/user/agrierp`.

---

## 0. PROMPT — « Rédige / mets à jour les règles métier de LogiALVIA »

> **Rôle.** Expert métier (zootechnie, comptabilité SYSCOHADA/Bénin, gestion de stocks) et ingénieur de test.
> **Contexte.** Les règles de logialvia (B6, 05) couvrent un poste monoposte ; AgriERP en a affiné d'autres (départ obligatoire, passages de stade, ventes ventilées, exercices, avoirs, MeCeF, paie). Le web de LogiALVIA les centralisera en un point de passage serveur chacune.
> **Tâches.** (1) Pour chaque règle : identifiant `RM-`, énoncé, formule exacte, source, statut ([LOGIALVIA] / [AGRIERP→PROPOSÉE] / À DÉFINIR), et AU MOINS un jeu de cas chiffré à la main avec résultat attendu ; (2) vérifie chaque cas par un calcul indépendant (tableur ou calculette), jamais en exécutant le code à tester ; (3) signale toute contradiction entre sources dans la section 9 ; (4) pour tout ce qui est À DÉFINIR, écris des questions fermées numérotées ; (5) ne crée AUCUNE règle de pisciculture, de pintade ou de goliath au-delà de ce que les sources disent.
> **Contraintes.** Formules sans ambiguïté (arrondi, plancher, ordre des opérations) ; entiers en FCFA ; planchers à 0 pour les effectifs ; dates à l'heure du Bénin ; messages de refus mot pour mot.
> **Critères d'acceptation.** (a) chaque `RM-` a un jeu de cas avec entrées, calcul détaillé et résultat ; (b) une règle [AGRIERP→PROPOSÉE] n'est jamais présentée comme confirmée ; (c) la section 7 sépare « défini dans logialvia » de « À DÉFINIR » pour les trois filières ; (d) chaque contradiction de la section 9 a une question ou une décision proposée ; (e) les formules de ce fichier se retrouvent dans les tests (`31_TESTING_QA.md`).
> **Interdits.** Inventer une durée de stade, une ration, un seuil de mortalité, un poids de maturité ou une formule de biomasse ; recopier un taux d'AgriERP comme s'il était celui d'ALLMANY ; valider un cas en lançant le code.

---

## 1. Effectif calculé par catégorie (fiches journalières)

### RM-ELV-01 — Effectif par catégorie, famille « neutre » [LOGIALVIA : B6 BR-ELV-001 à 007 ; 05 §1, §3]
Trois catégories par filière (Jeune, Commercialisée, Adulte ; libellés propres à chaque filière : tableau §7). Chaque jour, pour chaque catégorie, plancher à 0 :
- Jeune = max(0, Jeune_veille + Achats + Nés − Morts_J − Dons_J)
- Commercialisée = max(0, Comm_veille − Ventes − Morts_C − Dons_C)
- Adulte = max(0, Adulte_veille − Morts_A − Dons_A)
- Effectif total = somme des trois (BR-ELV-005) ; jamais saisi (BR-ELV-007).
- Aucune répartition en pourcentage fixe (le 35/35/30 de `05 §2` est une donnée de démonstration, jamais une règle).

**Cas à la main (Goliaths).** Veille : Poussins 20, Goliathau 40, Mature 31 (total 91). Jour : achats 5, nés 10, vente 8, morts (Poussins 2, Goliathau 1, Mature 0), dons (Goliathau 3).
Poussins = 20 + 5 + 10 − 2 = **33** ; Goliathau = 40 − 8 − 1 − 3 = **28** ; Mature = 31 − 0 − 0 = **31** ; total **92**. Contrôle croisé : 91 + 5 + 10 − 8 − 3 morts − 3 dons = 92 ✓.
**Cas plancher** : Goliathau veille 4, vente 6, aucune mort → max(0, 4 − 6) = **0** (jamais −2).
**Cas isolement** : une mort de 2 sur Mature seule → Mature 29, Poussins et Goliathau inchangés.
**Cas piège « vente ≠ Mature »** : vente de 3 → seul Goliathau baisse de 3 ; Mature reste 31.

### RM-ELV-02 — Cascade [LOGIALVIA : BR-ELV-006 ; F3]
Toute modification d'un jour recalcule tous les jours postérieurs déjà enregistrés. Un décès d'infirmerie, une vente de caisse ou un transfert passent par la MÊME fonction d'écriture. L'effectif de la bande affiché est celui de la DERNIÈRE fiche.
**Cas** : jours 5, 6, 7 saisis ; on ajoute +5 achats au jour 5 → la catégorie Jeune des jours 6 et 7 augmente de 5 (si aucune autre contrainte). **Point ouvert Q-ELV-6** : logialvia s'arrête au premier jour non saisi ; AgriERP franchit les jours sautés.

### RM-ELV-03 — Départ obligatoire par catégorie [AGRIERP→PROPOSÉE : guide bloc 1 (D4) ; Q-ELV-5]
Effectif de départ saisi UNE fois par bande ; somme des catégories = effectif total au début du jour de départ ; jamais déduit à l'insu de l'éleveur (le stade propose, un bouton « Reprendre la proposition… » reprend) ; demandé à l'ouverture de la fiche ; jours antérieurs non saisissables.
Messages exacts : « Effectif de départ incomplet : les trois catégories doivent être renseignées (0 si la catégorie est vide). » ; « La somme des catégories de départ (35) ne correspond pas à l'effectif total au début du jour de départ (36). » (quatre stades : « … les quatre stades doivent être renseignés (0 si le stade est vide). »).
**Cas** : départ (10, 5, 20) = 35 contre total 35 → valide ; contre 36 → refus avec « (35) » et « (36) ». Départ avec une catégorie vide (« ») → refus « incomplet ». État actuel de logialvia : le jour 1 part de 0 (`repartitionInitiale(0)`).

### RM-ELV-04 — Passage de stade [AGRIERP→PROPOSÉE : guide bloc 1 (D3) ; Q-ELV-1]
Transfert d'une catégorie source vers la suivante, total inchangé ; refusé au-delà de la source APRÈS ses autres mouvements du jour (plancher 0, entrée du passage précédent incluse) ; le passage appliqué est ramené à la source ; message : « Passage de stade refusé : 15 sujet(s) à faire passer, mais la catégorie source n'en compte que 12. »
**Cas volailles reproductrices (VOL-1)** — veille R=10, P=20, J=30 ; achat 5, éclosions 8, vente_R 1, vente_J 4, mort_J 2, mort_P 1, passage Poussin→Jeune p=6 :
R = 10 − 1 = **9** ; J = 30 + 5 − 4 − 2 + 6 = **35** ; P = 20 + 8 − 1 − 6 = **21** ; total **65** (veille 60 + 5 + 8 − 1 − 4 − 2 − 1 = 65 ✓). Refus si p=30 : source P après autres mouvements = 20 + 8 − 1 = 27 → appliqué 27 ; **P=0, J=56** (30+5−4−2+27).
**Cas lapins** (famille à catégorie « inconnue », AgriERP) — veille R=10, S=5, J=20 ; achat 3, né 4, vente 6, mort_R 1, mort_J 2, passage 5 : R = **9** ; S_avant = 5+3+4 = 12, passage 5, S = **7** ; J = 20 + 5 − 6 − 2 = **17** ; total **33**. Passage demandé 15 → appliqué 12 : S=**0**, J = 20 + 12 − 6 − 2 = **24**.
**Pondeuses VOL-2 (quatre stades)** — veille PP=100, PC=50, PL=30, PO=200 ; éclosions 20, achat 10, vente_PO 5, vente_PL 2, mort_PP 3, mort_PC 1, mort_PO 4, p1=40, p2=10, p3=5 : PP = 100+20−3−40 = **77** ; PC = 50−1+40−10 = **79** ; PL = 30+10−2+10−5 = **43** ; PO = 200−5−4+5 = **196** ; total **395**. (Dans AgriERP, l'achat va à Poulette ; dans logialvia `configuration_espece.dart`, achats et nés vont à Poussin Ponte : **Q-ELV-4**.)

### RM-ELV-05 — Ventes ventilées par catégorie [AGRIERP→PROPOSÉE : guide bloc 1 ; Q-ELV-7]
Chaque produit vendable porte `categorie_effectif` (nullable). La vente décrémente cette catégorie. Refus AVANT toute écriture : produit sans catégorie ; bande sans départ ; vente datée avant le départ ; catégorie d'une autre famille. Aujourd'hui (logialvia) : toute vente va à la seule catégorie « commercialisée » (RM-ELV-01).

### RM-ELV-06 — Bandes, sujets, transferts [AGRIERP→PROPOSÉE : guide bloc 12]
- Création : effectif initial = effectif courant = quantité ; refusée dans un exercice clos.
- Dès qu'une bande a des fiches, son effectif n'est plus modifiable à la main : « L'effectif de cette bande est tenu par ses fiches journalières : corrigez-le depuis la fiche, la bande suit automatiquement. »
- Archivage refusé si effectif vivant > 0 : « Cette bande compte encore 200 sujets vivants : archivez-la après avoir sorti ou transféré les sujets restants. » ; restauration refusée si le code est pris : « Le code « X » est déjà utilisé par une bande en cours : cette bande ne peut pas être restaurée. »
- Transfert : bandes distinctes, même espèce, non archivées ; date ni future ni antérieure à la création ; source suffisante CE JOUR et chaque jour suivant ; fait daté, jamais annulé. **Constitution** : le transfert inscrit la SORTIE de la bande mère sans entrée dans la cible.
**Cas constitution** : bande mère 40 sujets, création d'une bande fille de 10 (portée déjà comptée) → mère **30**, fille **10**, total **40** (jamais 50).
**Cas source insuffisante** : transfert de 12 un jour où la source en a 15, mais un mouvement du lendemain la ramène à 10 → refusé.

### RM-ELV-07 — Pondeuses : stock d'œufs [LOGIALVIA : B6 BR-ELV-008 ; H2]
SRH(J) = Stock final(J−1) (JAMAIS TS(J−1)) ; TS = (pondus − cassés) + SRH ; Sorties = plateaux × 30 ; Stock final = TS − sorties. Validations : pondus ≥ 0 ; 0 ≤ cassés ≤ pondus ; sorties ≥ 0. SRH, TS et Stock final sont rendus par des textes (invariant structurel).
**Cas** : J : SRH 100, pondus 60, cassés 5, sorties 2 plateaux → TS = 55 + 100 = **155** ; sorties 60 ; Stock final = **95**. J+1 : SRH = **95** (pas 155) ; pondus 58, cassés 3, sorties 0 → TS = 55 + 95 = **150** ; Stock final **150**. Le bug historique donnerait 155 + 55 = 210 ✗.
**Taux de ponte** = pondus du jour ÷ effectif Pondeuse × 100 : 60 ÷ 191 × 100 = **31,4 %** (191 = effectif du cas RM-ELV-01 pondeuses logialvia ci-dessous).
**Cas pondeuses logialvia (achats et nés → Poussin Ponte, vente → Pondeuse)** : veille 100/50/30/200 ; achat 10, né 20, vente 5, morts (3,1,0,4) → PP = 100+10+20−3 = **127** ; PC = 50−1 = **49** ; PL = **30** ; PO = 200−5−4 = **191** ; total **397**.
**À DÉFINIR (Q-ELV-9)** : que fait-on si Sorties > TS (stock final négatif) ? refus ou plancher à 0 ? La source ne le dit pas.

### RM-ELV-08 — Mortalité (indicateurs) [LOGIALVIA : F3 §1, 05 §3]
Taux du jour = morts ÷ effectif total de la veille × 100 (0 si veille = 0) ; taux du mois = Σ morts du mois ÷ effectif de début de mois × 100. Effectif de début de mois = reconstitué depuis la première journée saisie : fin + morts + dons + ventes − achats − nés.
**Cas** : 5 morts / 200 = **2,5 %** ; mois : 12 morts / 240 = **5,0 %** ; première journée : fin 98, mort 2 → début **100**. Une semaine sans saisie s'affiche « — », jamais « 0 mort ».
**Seuil d'alerte de mortalité anormale** : AgriERP = pire jour des 7 derniers jours ≥ 5 % (rôle animalier). **logialvia : aucun seuil défini** (B2 §3 cite l'alerte sans le chiffre) → **À DÉFINIR (Q-ALR-2)**.

### RM-ELV-09 — Rationnement [LOGIALVIA : B6 BR-ELV-009 ; F3 ; guide bloc 5]
Pour chaque catégorie : effectif calculé × ration (g/j/sujet) ; total = SOMME DE TOUTES les catégories ; `total_kg` = round(total_g ÷ 1000, 2) ; catégorie inconnue → total « — ». Clé de ration par libellé normalisé en égalité stricte (minuscules, sans accents, tranche d'âge entre parenthèses ignorée), jamais par sous-chaîne ; barème absent → valeur de référence de `ConfigurationEspece`, jamais 0.
**Cas Pondeuses (30/60/80/110)** avec (77, 79, 43, 196) : 2 310 + 4 740 + 3 440 + 21 560 = **32 050 g = 32,05 kg**. **Cas reproducteurs (130/80/30)** avec R=9, J=35, P=21 : 1 170 + 2 800 + 630 = **4 600 g = 4,6 kg**. **Cas Goliaths (30/60/110)** avec (33, 28, 31) : 990 + 1 680 + 3 410 = **6 080 g = 6,08 kg**. Relever la ration Mature de 110 à 130 : 31 × 130 = 4 030 → total **6 700 g**.
Rations de référence de logialvia : Goliaths, Pintades, Poulets 30/60/110 ; Lapins 30/60/110 (code) mais **120** en base seedée (`parametres_elevage_seeder.dart`) ; Pondeuses 30/60/80/110 ; Poissons-Chats 30/60/110 (code) mais **8/25/45** en base seedée : voir §9, contradictions C-3 et C-4.

### RM-ELV-10 — Autonomie de provende [AGRIERP→PROPOSÉE ; logialvia H2 : seuil 7 jours ; Q-ALR-1]
Autonomie (jours) = provende disponible (g) ÷ provende journalière calculée (g). Alerte rouge : rupture ou autonomie sous le seuil, ou aucun produit de provende ; n'empêche JAMAIS l'enregistrement ; une alerte par objet et par jour. Seuil : AgriERP **3 jours** ; logialvia H2 (pondeuses) **7 jours** → À CONFIRMER.
**Cas** : ration du jour 6 080 g (Goliaths ci-dessus). Stock 50 kg → 50 000 ÷ 6 080 = **8,2 jours** (pas d'alerte aux deux seuils). Stock 30 kg → **4,9 jours** : alerte au seuil 7 j, pas au seuil 3 j. Stock 15 kg → **2,5 jours** : alerte aux deux.

### RM-ELV-11 — Vue hebdomadaire [LOGIALVIA : F3]
Semaines [1-7], [8-14], [15-21], [22-fin du mois] avec fin = longueur réelle (28, 29, 30, 31). Cumuls = somme des journées ENREGISTRÉES ; effectif de fin de semaine = effectif du dernier jour saisi ; taux de mortalité de semaine = morts ÷ effectif de début de semaine ; sans saisie = « — ». Σ des 4 semaines = total du mois.
**Cas** : février 2027 → 4e semaine 22-28 ; avril → 22-30 ; semaine 1 : début 100, morts 3 → **3,0 %**.

---

## 2. Couvoir (Goliaths, Pintades) [LOGIALVIA : F3 « Couveuse multi-âges », `cycle_incubation.dart`, `statistiques_mirages.dart`]

### RM-COU-01 — Calendrier prévisionnel
Éclosion prévue = chargement + durée (Goliath **21 j**, Pintade **28 j**, corrigé par la Gérante ; le prototype disait 27) ; mirage 1 = J+7 et mirage 2 = J+14 (dates exactes) ; éclosion en FENÊTRE ± 2 jours. Espèce inconnue : retombe sur Goliath.
**Cas** : chargé le 01/08/2026. Goliath : mirage 1 le **08/08**, mirage 2 le **15/08**, éclosion **22/08**, fenêtre **20/08 → 24/08**. Pintade : éclosion **29/08**, fenêtre **27/08 → 31/08**.

### RM-COU-02 — Éclosion
Invariant : éclos + perdus ≤ chargés. « Recharger la machine immédiatement » crée un sous-lot DANS la même transaction (statut du parent « Remplacé ») ; le sous-lot hérite de la machine, jamais du calendrier. Supprimer un lot ne supprime pas ses sous-lots.
**Cas** : chargés 200 ; éclos 120 + perdus 90 = 210 > 200 → refusé.

### RM-COU-03 — Taux
Lot de 200 œufs, clairs J7 = 40, gâtés J14 = 10, éclos 120 :
- retenus = 200 − (40 + 10) = **150** ; **TER = 120 ÷ 150 = 80 %** ; taux brut 120 ÷ 200 = **60 %** ;
- infertilité = 40 ÷ 200 = **20 %** (sur les seuls lots mirés) ;
- mortalité embryonnaire = 10 ÷ (200 − 40) = **6,25 %** ;
- perte totale (lots clôturés) = (200 − 120) ÷ 200 = **40 %**.
TER = `null` (« — ») tant que l'éclosion manque et si le dénominateur est nul (lot entièrement vidé aux mirages).

### RM-COU-04 — TER moyen pondéré
Moyenne pondérée par les œufs retenus, pas moyenne des taux. Lot A : 120 éclos / 150 retenus ; lot B : 12 chargés, 1 clair, 1 gâté, 5 éclos → retenus 10, TER 50 %. Pondéré = (120 + 5) ÷ (150 + 10) = **78,125 %** (moyenne arithmétique fautive : 65 %).

### RM-COU-05 — Alertes
Une échéance reste due tant que la saisie manque ; un mirage oublié est signalé avec ses jours de retard, les plus anciens d'abord. **Cas** : lot du 01/08, mirage 2 non saisi au 20/08 → retard **5 jours** (échéance 15/08). Capacité d'incubateur : signal de surcharge, jamais blocage.

---

## 3. Santé animale

### RM-PRO-01 — Jour de cycle et traitements dus [LOGIALVIA : `bande.dart`, `prophylaxie_de_la_bande.dart` ; F3 v25 ; AgriERP : `ProtocoleDuJourService`]
Date du jour de cycle n = date de mise en bande + (n − 1) jours ; jour de cycle d'une date = écart en JOURS CALENDAIRES (minuit à minuit) + 1 ; traitement dû si `jour_debut ≤ J ≤ jour_fin` ; rien n'est projeté sans bande ; fin du délai d'attente = date prévue + rémanence (0 = aucun délai). Les entrées « le 1er du mois » (bornes nulles) ne sont jamais évaluées (AgriERP).
**Cas** (calendrier semé de logialvia, Goliaths) : mise en bande le **01/11/2026** → J1 Déparasitage (Levamisole, rémanence 7) le 01/11, fin de délai **08/11** ; J5 Anti-coccidien (Amprolium, rémanence 5) le **05/11**, fin **10/11** ; J15 Vaccin Newcastle Rappel (HB1, rémanence 0) le **15/11**, aucun délai. Le 05/11 le jour de cycle vaut 5.
Calendrier semé (11 échéances, confirmé = faux sauf lapins) : Goliaths J1, J5, J15 ; Pintades J1, J5, J6 (Complément Calcium), J12 (Vaccin Gumboro Rappel) ; Lapins J1, J9 ; Poissons-Chats J1 (Traitement antifongique du bassin, Bleu de Méthylène, rémanence 3), J14 (Contrôle oxygénation / ammoniac).

### RM-PRO-02 — Soins planifiés et rappels [AGRIERP→PROPOSÉE : guide bloc 6 ; Q-ALR-3]
N = `rappel_soins_jours` (0 à 30, défaut 3, 0 = le jour même). Soin « planifié » : « À venir » dès qu'il reste N jours ou moins ; « En retard » dès que la date est dépassée ; une alerte par soin et par jour. Fenêtre « Rappels du jour » : une fois par session, jamais au déverrouillage, jamais vide ; bandes vivantes seulement ; filière désactivée = aucun rappel.
**Cas** (N=3, aujourd'hui = 10/11) : soin au 09/11 → « En retard » ; au 10/11 → « Aujourd'hui » ; au 13/11 → « À venir » ; au 14/11 → rien.

### RM-PRO-03 — Décès d'infirmerie [LOGIALVIA : F3 v24]
Le décès s'AJOUTE aux mouvements du jour via l'écriture de fiche (cascade), crée la journée si besoin (marquée saisie), relit la vente du POS. L'infirmerie ne connaît pas la catégorie : la modale la DEMANDE (ou « Déjà saisie sur la fiche — ne rien ajouter »). Ordre : clôture écrite AVANT le report ; marque « décédé et compté » après.
**Cas** : fiche du jour avec mort Goliathau 1 ; décès infirmerie imputé à Goliathau → mort Goliathau **2**, vente du POS inchangée, effectif Goliathau recalculé et cascade propagée.

### RM-PRO-04 — Délai d'attente [LOGIALVIA : F3]
Les produits d'un animal sous délai d'attente ne sont pas vendables : une bannière liste les délais en cours avec leur date de fin. AgriERP signale (notification) une vente sous délai sans la refuser. Refuser ou signaler : **Q-VTE-3**.

---

## 4. Ventes, créances, stocks

### RM-VTE-01 — Total et remise [LOGIALVIA : B6 BR-VTE-003]
Total = Σ lignes − remise ; jamais recalculé ensuite à partir de la seule somme brute. **Cas** : 3 × 1 500 + 2 × 2 000 = 8 500 ; remise 500 → **8 000**.

### RM-VTE-02 — Règlement et solde [LOGIALVIA : F4]
Espèces ou Mobile Money : `paye` = total (pas le montant remis, qui peut inclure la monnaie). Avance : `paye` = montant reçu ; statut « Avance » tant que `paye < total`. Solde client = Σ (total − paye) des ventes Avance non annulées, recalculé à chaque lecture (jamais stocké).
**Cas** : vente 8 000 en Avance, reçu 3 000 → solde **5 000**. Encaissement de 5 000 → `paye` 8 000 = total → statut « Payée », solde **0**. Annulation de la vente avant paiement complet → solde client **0**.

### RM-VTE-03 — Atomicité [LOGIALVIA : B6 BR-VTE-002]
Vente + lignes + décrément de stock + incrément de la fiche d'élevage : tout ou rien. Annulation symétrique (stock restitué, compteur de la fiche défait ; la vente reste visible dans l'historique zootechnique du jour, BR-VTE-004).

### RM-VTE-04 — Échéance et retard [LOGIALVIA : F4 « Échéances de paiement » ; Q-VTE-1]
Échéance = date de vente + délai par défaut (paramètre, VIDE tant que le client ne l'a pas communiqué) ou date saisie (« Payable le », visible en Avance). Sans échéance : « Sans échéance », jamais en retard ; délai ≤ 0 = non fixé. Retard = jours calendaires depuis l'échéance.
**Cas** : délai 15 j, vente 01/11 → échéance **16/11** ; au 20/11 retard **4 jours** ; délai vide → « Sans échéance », PDF « Rappel de Solde ».

### RM-VTE-05 — Clients : indicateurs [LOGIALVIA : F4]
« Soldes anciens (> 10 j) » = ancienneté mesurée depuis la date de la vente. Anniversaire client (J−1) alimente « Événements CRM » et l'alerte du tableau de bord.

### RM-VTE-06 — Facture normalisée MeCeF — voir RM-MEC (§5.4).

### RM-VTE-07 — Retours et avoirs [AGRIERP→PROPOSÉE : `AvoirClientService` ; Q-VTE-2]
Retournable d'un produit sur une vente = vendu − déjà retourné (tous avoirs confondus) ; montant ≤ montant de la ligne − déjà crédité ; exercice absent/clos et plan comptable incomplet jugés AVANT d'écrire ; une seule transaction ; écriture inverse datée du jour du RETOUR (AgriERP : D 701 / D 443 / C 411 ; sans TVA : D 701 / C 411). Un avoir ne modifie jamais la facture d'origine.
**Cas** : vente de 10 plaquettes à 1 000 F (ligne 10 000). Retour de 4 (montant 4 000) accepté ; retour suivant de 7 → refusé (retournable 6) ; montant maximal restant 10 000 − 4 000 = **6 000**. Avoir commercial partiel : 3 000 accepté tant que ≤ 6 000.

### RM-STK-01 — PMP des intrants [LOGIALVIA : F5, « déduit, à confirmer » ; Q-STK-1]
PMP' = (stock × PMP + quantité reçue × prix d'achat) ÷ (stock + quantité reçue). **Cas** : 18 kg à 600 F + 82 kg reçus à 700 F → (10 800 + 57 400) ÷ 100 = **682** ; valeur 100 × 682 = **68 200 F**. Stock 0 : PMP' = prix d'achat.

### RM-STK-02 — Stock critique [LOGIALVIA : F2, B4 FRS-STK-02]
Critique si stock ≤ seuil. **Cas** : Maïs stock 18, seuil 25 → critique ; stock 25 → critique ; stock 26 → normal. Stock négatif : message et drapeau (H14) ; le serveur accepte et SIGNALE une vente de poste qui passe sous 0.

### RM-STK-03 — Valorisation [LOGIALVIA : F4 « Coût de revient »]
Intrants : PMP. Produits finis : coût de revient ; sans coût = « — » + « Non valorisé », hors totaux, avec la mention « Hors N article(s) sans coût de revient renseigné ». Coût négatif refusé ; coût > tarif refusé ; coût = tarif accepté.
**Cas** : Goliath mature 31 sujets, coût 4 500, tarif 6 000 → valeur au coût **139 500** ; valeur à la vente **186 000** ; marge unitaire **1 500**. Produit B sans coût : exclu du total, « Hors 1 article ».

### RM-STK-04 — Ajustement et fabrication [LOGIALVIA : F5]
Ajustement : stock physique remplace le théorique ; écart signé = physique − théorique, journalisé. Fabrication de provende : première passe vérifie TOUS les stocks, puis décrément atomique ; référence commune `FAB-AAAA-NNNN` ; sorties négatives. **Cas** : composition 25/10/5/3/2 = **45 kg** ; Maïs 18 kg disponible < 25 → toute la fabrication refusée, aucun stock bougé. Ajustement : théorique 18, physique 15 → écart **−3**.

---

## 5. Comptabilité SYSCOHADA, exercices, TVA, MeCeF

### RM-CPT-01 — Équilibre débit = crédit [LOGIALVIA : B6 BR-CPT-003 ; `moteur_comptable.dart` ; AgriERP : `AccountingEntryService`]
Une ligne porte un débit OU un crédit (jamais les deux, jamais aucun, jamais négatif) ; un lot (pièce) doit être équilibré à 0,01 F : sinon « Pièce déséquilibrée : débit X ≠ crédit Y. » ; date dans un exercice OUVERT ; archivage = contre-passation exacte.
Comptes d'écritures automatiques de logialvia (`generer_ecritures_automatiques.dart`) : Caisse 531, Mobile Money 512, Clients 411, Clients avances 419, Fournisseurs 401, Ventes avicoles 701, Ventes marchandises 707, Achats matières 601, Achats marchandises 602, Frais vétérinaires 622 — numérotation reprise telle quelle, **à faire valider par l'expert-comptable** (Q-CPT-1).
**Cas** : vente Espèces 8 000 sans TVA : D 531 8 000 / C 701 8 000. Vente à crédit : D 411 / C 701. Règlement client : D 531 / C 411. Achat à crédit : D 601 / C 401. Pièce D 531 8 000 + C 701 7 999 → refusée (écart 1).

### RM-CPT-02 — Grand Livre : solde progressif [LOGIALVIA : F6 §2, BR-CPT-007]
solde += (compte débiteur par nature) ? débit − crédit : crédit − débit, ordre chronologique, depuis le solde d'ouverture.
**Cas** : compte 531 (débiteur), ouverture 10 000 ; D 8 000 ; C 2 000 → **16 000**. Compte 701 (créditeur), ouverture 0 ; C 10 000 ; D 500 → **9 500**.

### RM-CPT-03 — Balance [LOGIALVIA : B6 BR-CPT-004 ; F6 §3]
Σ soldes finaux débiteurs = Σ soldes finaux créditeurs (tolérance 0,01) ; écart affiché, rouge si ≠ 0 ; toute clôture vérifie l'équilibre en premier.
**Cas** : ouverture 531 D 10 000 / 101 C 10 000 ; vente 8 000 espèces ; achat 5 000 espèces. Soldes finaux : 531 D **13 000** ; 601 D **5 000** ; 701 C **8 000** ; 101 C **10 000** → ΣD = 18 000 = ΣC = 18 000, écart **0**.

### RM-CPT-04 — Résultat net, source unique [LOGIALVIA : B6 BR-CPT-005]
Résultat = Σ produits (classe 7) − Σ charges (classe 6) ; UNE seule fonction alimente Compte de résultat, compte 13 du bilan et départ du TAFIRE. Seules les classes 6 et 7 comptent dans recettes/dépenses des rapports (les contreparties 531, 512, 411, 401 doubleraient les totaux).
**Cas** précédent : 8 000 − 5 000 = **3 000**. Bilan : Actif (trésorerie 13 000) = Passif (capital 10 000 + résultat 3 000) = **13 000** ✓.

### RM-CPT-05 — Clôture mensuelle [LOGIALVIA : B6 BR-CPT-006 ; F6 §6]
Écriture d'un mois clôturé non modifiable, sauf déblocage exceptionnel par admin (journalisé) ; pas de report à nouveau ; vérification de la balance obligatoire.

### RM-CPT-06 — Clôture annuelle et report à nouveau [LOGIALVIA : B6 BR-CPT-001/002 ; J1 ; AgriERP : guide bloc 11]
1. Balance équilibrée ; 2. soldes des comptes de bilan (classes 1 à 5) ; 3. verrouillage de TOUTES les écritures (`isLocked`) ; 4. RAN dans N+1 pour chaque compte de bilan à solde non nul, même sens ; 5. exercice N+1 activé. Tout dans UNE transaction (atomicité renforcée). Confirmation textuelle « CLOTURER ».
[AGRIERP→PROPOSÉE] étapes gardées : échéance passée (refus avant la fin de l'exercice), étape 1 et étape 2 (solde des comptes de gestion classes 6 et 7 vers le résultat) faites, N−1 clos, à-nouveau équilibré ; un compte de classe 8 avec solde bloque la clôture ; à-nouveau verrouillé ; jamais « historique + à-nouveau » dans les états.
**Cas** (suite RM-CPT-03) : étape 2 solde 6 et 7 : D 701 8 000 / C 601 5 000 / C 131 3 000. RAN 2027 : 531 D 13 000 ; 101 C 10 000 ; 131 C 3 000 → D 13 000 = C 13 000 ✓. **Affectation du résultat (13 → 11/12)** : non définie par les sources → **Q-CPT-2**.
**Cas de refus** : clôture de 2026 demandée le 15/11/2026 → refusée (échéance non passée) ; le 02/01/2027 avec étapes faites → acceptée.

### RM-CPT-07 — Exercices N / N+1 [AGRIERP→PROPOSÉE : guide bloc 4 ; Q-CPT-1]
Statut : « Clôturé » si clos ; « Ouvert » si pas d'exercice antérieur ou si celui qui contient la veille est clos ; « Provisoire » sinon (N+1 ouvert alors que N n'est pas clos). Une saisie appartient à l'exercice qui contient SA DATE, jugé au moment d'écrire, quel que soit l'exercice affiché. Défaut = exercice contenant aujourd'hui (heure du Bénin), sinon le plus récent. Bandeau : « Exercice 2026 clôturé — lecture seule. Les saisies se font dans l'exercice 2027. » `arreteDe(année)` : aujourd'hui si l'exercice est en cours ; sa date de fin s'il est passé ; son premier jour s'il est à venir.
**Cas** (exercice 2026 = 01/01–31/12) : aujourd'hui 15/03/2026 → **15/03/2026** ; 10/01/2027 → **31/12/2026** ; 10/06/2025 → **01/01/2026**. 2026 non clos, 2027 ouvert → 2027 « Provisoire » ; 2026 clos → 2027 « Ouvert ».

### RM-CPT-08 — Numérotation [AGRIERP→PROPOSÉE ; logialvia : `OD-AAAA-…`, `FV-`, `FA-`, `FAB-`]
Numéro attribué par le SERVEUR, dans la transaction de l'écriture, jamais recalculé ; l'année est celle de l'écriture. Les numéros déjà attribués ne changent jamais (migration UUID). **Cas** : écriture datée 31/12/2026 saisie le 03/01/2027 (exercice 2026 ouvert) → `OD-2026-…`. Format et reprise : **Q-SYN-2**.

### RM-TVA-01 — TVA [AGRIERP→PROPOSÉE : `TvaSettingService`, `VatDeclarationService` ; Q-TVA-1]
Drapeau « assujetti » (défaut oui). Inactif : montants HT, AUCUNE ligne 443/445, taux effectif 0. Actif : montants TTC ; HT = round(TTC ÷ (1 + taux)) à l'unité (au plus proche, moitié vers le haut) ; TVA = TTC − HT. Déclaration : seules les ventes transmises/normalisées (facture simple absente : à confirmer avec le cabinet). Frais de livraison inclus au taux de la ligne de plus grand montant (à égalité, le plus haut).
**Cas** : TTC 11 800 à 18 % → HT **10 000**, TVA **1 800**. TTC 5 000 → 5 000 ÷ 1,18 = 4 237,29 → HT **4 237**, TVA **763**. TTC 100 → 84,75 → HT **85**, TVA **15**. Écriture vente 11 800 TVA active : D 531 11 800 / C 701 10 000 / C 443 1 800 ; TVA inactive : D 531 11 800 / C 701 11 800.

### RM-MEC-01 — Facture normalisée [AGRIERP→PROPOSÉE : guide bloc 19 ; logialvia `facturation_mecef_tables.dart` ; Q-MEC-1]
Facture simple : jamais transmise. Normalisée : nom du client obligatoire, IFU vide (omis) ou 13 chiffres ; AIB 5 % (défaut), 1 % ou N/A ; MONTANT d'AIB jamais calculé localement (renvoyé par la DGI). Groupes de taxe : 0 % = A, 18 % = B, tout autre taux REFUSÉ avec motif (grille modifiable : logialvia n'amorce que « exonéré » et « 18 % »). Prix ENTIERS, une seule fonction d'arrondi ; remise globale répartie au plus fort reste ; écart d'arrondi absorbé par la plus grande ligne, facture REFUSÉE si l'écart dépasse le nombre de lignes ; prix unitaire = montant ÷ quantité si la division tombe juste, sinon quantité 1 et quantité réelle au libellé (60 caractères au plus). Une normalisée est verrouillée : correction par avoir `FA` lié (`origineRef`).
**Cas remise** : lignes 600, 300, 100 (total 1 000), remise 52 → parts exactes 31,2 ; 15,6 ; 5,2 → planchers 31, 15, 5 (= 51) ; reste 1 → à la ligne au plus fort reste fractionnaire (15,6) → **31, 16, 5** (= 52 ✓). **Cas prix unitaire** : ligne 1 000 F pour 4 unités → 250 × 4 ; ligne 1 000 F pour 3 unités → quantité 1, prix 1 000, libellé portant « 3 ».
États : `aTransmettre` (logialvia) = `en_attente` (AgriERP) → `normalisee` ou `rejetee`/`erreur` ; une facture « normalisée » n'est affichée que si les champs rendus par la DGI (code, NIM, compteur) sont présents.

---

## 6. Paie (OPTION — absente de logialvia ; Q-PAI-1)

B1 §6 déclare RH/paie hors périmètre ; AgriERP la possède. **[AGRIERP→PROPOSÉE ; rien ici n'est une règle ALLMANY]** (`agrierp_laravel/app/Services/PayrollCalculationService.php`, barème semé `IncomeTaxBracketsSeeder.php` : validé par le client d'AgriERP, pas par ALLMANY).
Formules (jours ouvrés 26) : retenue d'absence = round(brut ÷ 26 × jours d'absence, 2) ; salaire dû = max(0, brut − retenue) ; CNSS salariale = dû × 3,6 % ; net imposable = dû − CNSS salariale (jamais le brut) ; ITS = Σ par tranche de (min(net imposable, plafond) − plancher) × taux ; net = net imposable − ITS ; charges patronales (en plus, hors net) = dû × (VPS 4 % + pensions 6,4 % + prestations familiales 9 % + risques professionnels 2 % [1 à 4 % selon le risque]) ; coût employeur = dû + charges patronales. Barème d'AgriERP : 0–60 000 : 0 % ; 60 000–150 000 : 10 % ; 150 000–250 000 : 15 % ; 250 000–500 000 : 19 % ; > 500 000 : 30 % (en base, modifiable).
**Cas A** brut 200 000, 0 absence : CNSS = 7 200 ; imposable **192 800** ; ITS = 90 000 × 10 % + 42 800 × 15 % = 9 000 + 6 420 = **15 420** ; net = **177 380** ; charges patronales = 8 000 + 12 800 + 18 000 + 4 000 = **42 800** ; coût employeur **242 800**.
**Cas B** brut 130 000, 2 jours d'absence : retenue 130 000 ÷ 26 × 2 = **10 000** ; dû 120 000 ; CNSS **4 320** ; imposable **115 680** ; ITS = 55 680 × 10 % = **5 568** ; net **110 112**.
**Cas C** brut 50 000 : CNSS 1 800 ; imposable 48 200 ; ITS **0** (sous 60 000) ; net **48 200**.
Si aucun barème n'est renseigné : l'indiquer (`bareme_its_renseigne = faux`), jamais un ITS nul silencieux. Écritures de paie : uniquement au serveur, exercice ouvert exigé.
**À DÉFINIR AVEC LE CLIENT** : Q-PAI-1 la paie entre-t-elle dans LogiALVIA ? Q-PAI-2 barème ITS et taux CNSS/VPS pratiqués ? Q-PAI-3 jours ouvrés (26) ? Q-PAI-4 stagiaires et pointage utiles ?

---

## 7. PARTICULARITÉS FILIÈRES : pisciculture, pintades, goliaths

Principe : **rien n'est inventé**. Pour chaque filière : (a) ce qui est DÉFINI dans logialvia (code `configuration_espece.dart`, seeders, docs F3/H2/I2) ; (b) ce qui est À DÉFINIR AVEC LE CLIENT, avec questions. Les filières Lapins, Poulets et Pondeuses : voir §1 et §9.

Tableau de configuration (source : `logialvia_app/lib/elevage/domain/entities/configuration_espece.dart`) :

| Filière | Cat. 1 (reçoit achats + nés) | Cat. 2 (déduite des ventes) | Cat. 3 / 4 | Libellé achats | Libellé nés | Ration code (g/j) |
|---|---|---|---|---|---|---|
| Goliaths | Poussins | **Goliathau** | Mature | Achats | Nés (Couveuse) | 30 / 60 / 110 |
| Pintades | Poussins | **Pintadau** | Mature | Achats | Nés (Couveuse) | 30 / 60 / 110 |
| Poissons-Chats | Alevin | **Juvénile** | Mature | Achats | Nés | 30 / 60 / 110 |
| Lapins | Lapereau | Chair | Reproducteur | Achats | Nés (Mise bas) | 30 / 60 / 110 |
| Poulets | Poussin | Poulette | Adulte | Achats | Nés / Transferts | 30 / 60 / 110 |
| Pondeuses | Poussin Ponte | (Pondeuse = 4e) | Poussin Croissance, Poulette, Pondeuse | Achats / Entrées | Nés / Transferts | 30 / 60 / 80 / 110 |

### 7.1 Pisciculture (Poissons-Chats) — module `pisciculture`, désactivé par défaut

**Défini dans logialvia** :
- Identifiant `poissons-chats`, route `/elevage/poissons-chats`, module activable `pisciculture` (« fiche construite, paramètres non confirmés », désactivé par défaut) [I2, F8].
- Trois catégories **Alevin / Juvénile / Mature** ; Alevin reçoit achats et nés ; **Juvénile est la catégorie commercialisée** (la vente est déduite de Juvénile) ; Mature ne reçoit rien [configuration_espece.dart, 05 §3]. Mécanisme = famille « neutre » RM-ELV-01 (morts et dons par catégorie, plancher 0, cascade).
- Étapes de cycle affichées : Alevin → Juvénile → Mature. Aucune durée, aucun poids de passage.
- Libellés : colonne 1 « Achats » (l'**empoissonnement**, achat d'alevins pour peupler un bassin, se saisit ICI) ; colonne 2 « Nés » (écart délibéré arbitré par la Gérante ; « couveuse » interdit pour cette filière) [F3 « Glossaire »].
- Rationnement : `noteRationnement` = « Seuils non confirmés pour cette filière — barème à valider avant usage réel ». **Deux jeux de valeurs coexistent** : 30/60/110 g/j dans `ConfigurationEspece` (valeur de repli) et **8 / 25 / 45 g/j** dans le barème semé `BaremesRation` (`logialvia_app/lib/elevage/data/seed/parametres_elevage_seeder.dart`, tous « non confirmé »). Comme le calcul lit d'abord le barème en base par libellé exact (`rationsConfigurees[categorie.libelle]`, repli sur la configuration), la valeur EFFECTIVE à la première installation est probablement 8/25/45 : **à vérifier dans le code avant de tester** (contradiction C-3).
- Numérotation : préfixe « Bassin » (`B1, B2, B3`), modifiable, jamais vide [F3 Paramètres Élevage, D1].
- Prophylaxie semée : J1 « Traitement Antifongique (bassin) », Bleu de Méthylène, rémanence 3 j ; J14 « Contrôle Oxygénation / Ammoniac », produit « — », rémanence 0 [seeder]. Le « type d'action » d'un soin est une liste fermée (Vaccination, Traitement curatif, Vermifuge, Vitamines) qui ne contient pas « contrôle de l'eau » : l'utilisateur choisit le type à la planification [F3 v25].
- Produit vendable : catégorie de catalogue « Pisciculture » ; produit « **Poisson-chat vif (kg)** » vendu AU KILO (libellé du catalogue, `logialvia/docs/manuel/libelles/12-ventes.json`) alors que l'effectif de la fiche se tient en SUJETS : la conversion kg vendus ↔ sujets sortis n'est définie nulle part [D1 §Écart ; F4].
- Champ « Poids Général (g) » entier, facultatif, présent sur TOUTES les fiches (`poidsGeneralG`) ; le GMQ du Dashboard Élevage était « non modélisable » (F2) puis la colonne a été ajoutée ; aucune formule de GMQ ni de biomasse n'est documentée.
- Une alerte de maturité existe en DONNÉES pour Goliaths seulement (poids 2 800 g, âge 120 j) ; pas pour le poisson.

**À DÉFINIR AVEC LE CLIENT (aucune formule n'est donnée tant que non tranché)** :
- **Q-PIS-1 Stades.** Alevin / Juvénile / Mature sont-ils confirmés ? Le passage de stade se décide-t-il à l'âge, au poids moyen, ou au tri manuel ? Valeurs (jours ou grammes) ?
- **Q-PIS-2 Mortalité.** La mortalité se saisit-elle par stade comme les autres filières, ou par bassin ? À partir de quel taux (par jour, par semaine) faut-il alerter ?
- **Q-PIS-3 Biomasse et poids moyen.** Faut-il suivre la biomasse (nombre × poids moyen) ? Comment mesure-t-on le poids moyen (échantillon : nombre de poissons pesés et poids total ?), à quelle fréquence ? Le champ « Poids général » actuel suffit-il ? Veut-on un gain moyen quotidien ?
- **Q-PIS-4 Cycle bassin/étang.** Une bande = un bassin ? Un bassin reçoit-il plusieurs bandes successives ? Durée d'un cycle de la mise en eau à la vente ? Vide sanitaire entre deux cycles ? Un étang diffère-t-il d'un bassin ?
- **Q-PIS-5 Aliment.** Ration en g/j/sujet (8/25/45 de la base ou 30/60/110 du code ?) ou en pourcentage de la biomasse ? Quel produit d'aliment (granulé flottant ?) ? Suit-on l'indice de conversion alimentaire ?
- **Q-PIS-6 Vente.** Le catalogue vend le « Poisson-chat vif (kg) » au kilo : comment une vente en kg décrémente-t-elle l'effectif en sujets (poids moyen d'un poisson vendu ? saisie du nombre de sujets en plus du poids ?) ? Vend-on au poids (prix au kg) ou à la pièce ? La catégorie vendue reste-t-elle Juvénile ? Y a-t-il un poids minimum de vente ? Délai d'attente avant vente après traitement (3 j du bleu de méthylène confirmé) ?
- **Q-PIS-7 Entrées.** Les alevins viennent-ils seulement d'achats (empoissonnement) ou aussi d'une reproduction interne ? Si achat seul, la colonne « Nés » reste-t-elle affichée ?
- **Q-PIS-8 Qualité de l'eau.** Faut-il saisir des relevés (température, pH, oxygène, ammoniac) ? Le contrôle de J14 en est-il le déclencheur ?
- **Q-PIS-9 Calendrier de traitements.** Les deux échéances (J1 antifongique, J14 contrôle) sont-elles confirmées ? D'autres (vaccins, parasites) ?

### 7.2 Pintades — module toujours actif

**Défini dans logialvia** :
- Identifiant `pintades`, route `/elevage/pintades`, TOUJOURS actives, non désactivables [I2, F8] ; effectif de référence : 28 matures [B1 §1].
- Catégories **Poussins / Pintadau / Mature** ; Poussins reçoit achats et nés ; **la vente est déduite de Pintadau** ; mécanisme famille « neutre » RM-ELV-01 ; libellés « Achats » et « Nés (Couveuse) » [configuration_espece.dart].
- Étapes de cycle : « Naissance (Couveuse) », « Pintadau (0 → 4 mois) », « Mature — Éligible à la Vente » (aucun seuil de poids ni d'âge pour la pintade, contrairement à Goliaths).
- **Incubation : 28 jours** (corrigé par la Gérante ; prototype et INDEX_MAITRE disaient 27) [`cycle_incubation.dart`, F3 v21] ; mirages J+7 et J+14 ; éclosion en fenêtre ± 2 j (RM-COU-01).
- Ration : barème générique 30 / 60 / 110 g/j (« aucun barème spécifique confirmé », badge « Générique (Aviculture, à confirmer) » [seeder, F3]). ⚠️ Le barème semé nomme le premier stade « **Alevins** » au lieu de « Poussins » (`parametres_elevage_seeder.dart`) : le rapprochement par libellé exact manquerait la ligne et le calcul retomberait sur la valeur de repli 30 (contradiction C-4, à vérifier).
- Prophylaxie semée : J1 Déparasitage (Levamisole Volaille, rémanence 7), J5 Anti-coccidien 1/4 (Amprolium, rémanence 5), J6 Complément Calcium (CalciBoost), J12 Vaccin Gumboro Rappel (rémanence 0) [seeder].
- AgriERP ne contient AUCUNE règle de pintade (seul un produit « Pintade », SKU AVI-002) [guide bloc 1].

**À DÉFINIR AVEC LE CLIENT** :
- **Q-PIN-1 Stades.** Durée exacte du stade pintadeau (« 0 → 4 mois » indicatif) ? Seuil de maturité en âge et en poids (comme les 120 j et 2,8 kg du Goliath) ?
- **Q-PIN-2 Rations.** Le barème générique 30/60/110 est-il celui d'ALLMANY pour la pintade ? Valeurs par stade ?
- **Q-PIN-3 Reproducteurs et ponte.** Les reproducteurs (et une éventuelle ponte de pintades) forment-ils une catégorie ou une bande distincte ? Les œufs de pintade se suivent-ils comme ceux des pondeuses (stock d'œufs) ?
- **Q-PIN-4 Incubation et prophylaxie.** Confirmer 28 jours et le calendrier J1/J5/J6/J12 (calcium à J6 : produit et dose ?).

### 7.3 Goliaths — module toujours actif

**Défini dans logialvia** :
- Identifiant `goliaths`, route `/elevage/goliaths`, toujours actifs ; effectif de référence : 31 matures [B1, F2].
- Catégories **Poussins / Goliathau / Mature** ; achats et nés → Poussins ; **la vente est déduite de Goliathau, PAS de Mature** (« Éligible à la Vente » qualifie la maturité commerciale, pas la catégorie décrémentée) ; test dédié [F3 « Piège majeur », RM-ELV-01].
- Étapes : « Naissance (Couveuse) », « Goliathau (0 → 4 mois) », « Mature (≥ 4 mois, ≥ 2,8 kg) — Éligible à la Vente » ; constantes `poidsMaturiteGrammes = 2800`, `ageMaturiteJours = 120` (aucune règle d'alerte codée à ce jour : les seuils ne sont que des données ; vérifié par recherche dans `logialvia_app/lib/elevage`).
- Incubation 21 jours ; mirages J+7, J+14 (RM-COU) ; deux espèces seulement dans le couvoir (Goliath, Pintade).
- Ration : 30/60/110 g/j, générique (« à valider avec la Gérante ») ; prophylaxie semée : J1 Déparasitage (Levamisole, rémanence 7), J5 Anti-coccidien 1/4 (Amprolium, rémanence 5), J15 Vaccin Newcastle Rappel (HB1) [seeder].
- AgriERP : « Poulet goliath (sujet vif) » est rangé en Jeune par défaut d'après le nom du produit ; catégorie commercialisée de logialvia = Goliathau (milieu) : même place [guide bloc 1].

**À DÉFINIR AVEC LE CLIENT** :
- **Q-GOL-1** Confirmer que la vente se déduit de Goliathau et jamais de Mature (note de `calcul_fiche_journaliere.dart`). Que devient un Goliathau vendu après 4 mois ?
- **Q-GOL-2** Barème de ration propre au Goliath (par stade) ?
- **Q-GOL-3** Alerte de maturité (4 mois et 2,8 kg) : souhaitée ? Où se saisit le poids pesé (champ « Poids général ») ? Passage Goliathau → Mature : manuel ou automatique à l'âge ?
- **Q-ELV-8** Registre nominatif des reproducteurs (fonction BS3 d'AgriERP) utile à ALLMANY ?

---

## 8. Récapitulatif des décisions et questions du client sur l'élevage (rappel des numéros)

Q-ELV-1 glossaire lapins (Lapereau/Chair/Reproducteur de logialvia contre Reproducteur/Sous-mères/Jeune d'AgriERP) · Q-ELV-2 ration lapins reproducteur 110 (code) / 120 (base semée et AgriERP) · Q-ELV-3 poulets : Poussin/Poulette/Adulte confirmé ? chair ou reproducteurs ? « Jeune » ou « Poulet » · Q-ELV-4 où vont les achats d'une volaille (Poussin selon BR-ELV-002 ; Jeune ou Poulette chez AgriERP) · Q-ELV-5 départ obligatoire, à la création de la bande ou à l'ouverture de la fiche · Q-ELV-6 cascade qui s'arrête ou franchit les jours sautés · Q-ELV-7 produit vendable porteur d'une catégorie d'effectif, refus sinon · Q-ELV-8 registre nominatif · Q-ELV-9 stock d'œufs négatif · Q-REP-1 suivi de reproduction (saillies, mises bas, échecs) voulu pour les lapins ? · Q-ALR-1 seuil d'autonomie (3 ou 7 jours) · Q-ALR-2 seuil de mortalité anormale · Q-ALR-3 horizon des rappels de soins N (3 j) et fenêtre au lancement + à chaque connexion · Q-VTE-1 délai de paiement par défaut · Q-VTE-2 règles d'avoir (retournable, montant maximal) · Q-VTE-3 vente sous délai d'attente : refuser ou signaler · Q-STK-1 PMP ou FIFO / dernier prix · Q-STK-2 la provende fabriquée devient-elle un article de stock (unité, seuil, valorisation ?) · Q-STK-3 recettes types de provende · Q-CPT-1 exercice = année civile ; numéros de comptes (531/512/…) validés par l'expert-comptable ; N+1 « provisoire » voulu ? · Q-CPT-2 affectation du résultat · Q-CPT-3 suppression d'écriture (logialvia `supprimerPiece`) ou contre-passation seule (AgriERP) · Q-CPT-4 immobilisations : méthode d'amortissement (linéaire seule ?), durées, prorata au mois ou au jour, mois entiers ou à virgule (`CalculAmortissement.moisEntre` d'AgriERP donne des mois à virgule : 31/01 → 28/02 = 0,903) · Q-CPT-5 axe analytique par filière et clé de répartition des charges communes · Q-TVA-1 assujettissement et facture simple dans la déclaration · Q-TVA-2 taux autres que 0 % et 18 % ? · Q-MEC-1 mode e-MECeF ou boîtier.

## 9. Contradictions entre sources (à ne pas résoudre en silence)

| Réf. | Contradiction | Décision proposée |
|---|---|---|
| C-1 | B6 BR-ELV-006 : la cascade s'arrête « au premier jour non saisi » ; AgriERP franchit les jours sautés. | Q-ELV-6 ; en attendant, comportement de logialvia. |
| C-2 | B6 BR-ELV-002 : achats → catégorie la plus jeune ; AgriERP VOL-1 : achats → Jeune ; VOL-2 : achat → Poulette. | Garder la règle de logialvia ; Q-ELV-4. |
| C-3 | Poissons-Chats : ration 30/60/110 (`configuration_espece.dart`) contre **8/25/45** (`parametres_elevage_seeder.dart`). | Q-PIS-5 ; vérifier laquelle s'applique à la 1re installation. |
| C-4 | Pintades : le barème semé nomme « Alevins » le stade « Poussins » du code. | Vérifier le rapprochement par libellé ; corriger le seeder côté LogiALVIA (hors de ce dépôt de documentation). |
| C-5 | Lapins : reproducteur 110 g/j (code) contre 120 g/j (base semée, confirmé « Référence Cuniculture » ; AgriERP 120). | Q-ELV-2. |
| C-6 | Incubation Pintade : 27 j (prototype, INDEX_MAITRE) contre 28 j (F3 v21, code `cycle_incubation.dart`). | Retenir 28 ; Q-PIN-4. |
| C-7 | Autonomie de provende : H2 « sous 7 jours » contre AgriERP « sous 3 jours ». | Q-ALR-1. |
| C-8 | `05 §2` : répartition initiale 35/35/30 (donnée de démonstration) contre départ obligatoire AgriERP. | Q-ELV-5 ; ne jamais appeler la répartition en production. |
| C-9 | Rôles : 4 (B1/B2/B3) contre 3 (I1). | Q-ROL-1 ; garder 3. |
| C-10 | F6 §10.15 / `supprimerPiece` : suppression d'une pièce ; AgriERP : contre-passation jamais suppression. | Q-CPT-3 (BR-ADM-003 exige la journalisation). |
| C-11 | Alerte de stock d'AgriERP : critique à stock ≤ 0 ; logialvia : critique à stock ≤ seuil. | Garder logialvia (RM-STK-02). |
| C-12 | `docs/prd/rh-crud-poste.md` : le comptable a `view-rh` ; le seeder `RolesAndPermissionsSeeder.php` ne le lui donne pas. | Sans objet tant que Q-ROL-1/Q-PAI-1 ne sont pas tranchées ; relever dans AgriERP. |

## 10. Critères d'acceptation du document

- [ ] Chaque `RM-` a un jeu de cas chiffré, recalculé de tête par un relecteur.
- [ ] Les sections 7.1 à 7.3 distinguent « Défini dans logialvia » et « À DÉFINIR », sans formule inventée.
- [ ] Toute question de la section 8 est reprise dans `10_BRS_BUSINESS_REQUIREMENTS.md` §6.
- [ ] Les 12 contradictions sont présentes.
