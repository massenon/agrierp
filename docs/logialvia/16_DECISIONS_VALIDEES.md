# 16 — REGISTRE DES DÉCISIONS VALIDÉES PAR LE CLIENT (DV-01 à DV-07)

## USAGE

- **Quand l'utiliser** : avant de toucher à une ration, une vente de poisson, l'incubation des pintades, une alerte d'autonomie, la corbeille, les droits ou les rôles. Ce registre est la SOURCE de ce qui est TRANCHÉ ; les autres fichiers de `docs/logialvia/` portent le texte normatif et renvoient ici par « TRANCHÉ (DV-xx) ».
- **Ordre** : `10_BRS` → … → `15_REGLES_METIER` → **`16_DECISIONS_VALIDEES`** → modules `20_` à `29_`. En cas de conflit entre ce registre et un autre fichier, ce registre prévaut et l'autre fichier est corrigé.
- **Date de validation** : 08/11/2026 (sept décisions, validées ensemble par le client).
- **Chemins** : `logialvia/…` = `/home/user/massenon/logialvia/…` (lecture seule) ; sans préfixe = monorepo `/home/user/agrierp`.

> **Avertissement général.** Les repères zootechniques de ce registre (taux de ration, températures, humidités, durées, poids, rations par âge, indices de conversion, âges d'abattage) sont des **ORDRES DE GRANDEUR donnés par l'assistant, à confirmer par le technicien/vétérinaire et les fiches techniques des aliments ; seule la décision d'adopter la règle est validée.** Aucune valeur de ce registre ne s'écrit en dur dans le code comme « vérité ferme » : barèmes, seuils et durées sont des PARAMÈTRES éditables, marqués « repère terrain, à valider » tant que le technicien ne les a pas confirmés.

Statut de chaque ligne ci-dessous : **validé par le client** (la règle) ; les valeurs numériques sont des **repères à valider** sauf mention contraire (durée d'incubation 28 j, seuils d'autonomie 7 j et 3 j : valeurs par défaut validées, paramétrables).

---

## 1. Tableau récapitulatif

| Id | Date | Décision (résumé) | Statut | Questions fermées | Reste À DÉFINIR |
|---|---|---|---|---|---|
| DV-01 | 08/11/2026 | Ration des poissons-chats = % de la biomasse par jour | validé par le client | Q-PIS-5, C-3 ; Q-PIS-3 (en partie) | taux retenus par classe, validation technicien |
| DV-02 | 08/11/2026 | Vente/récolte de poisson : poids (kg) ET nombre de sujets ; estimation marquée « estimé » | validé par le client | Q-PIS-6 | arrondi, seuil de tolérance, poids minimum de vente |
| DV-03 | 08/11/2026 | Pintades : « pintadeaux » ; incubation 28 j paramétrable (26–28), deux modes, rappels | validé par le client | Q-PIN-4, C-4, C-6 ; Q-PIN-2 (en partie) | repères d'incubateur, seuil de mortalité, poussinière, rations |
| DV-04 | 08/11/2026 | Autonomie de provende : alerte 7 j, critique 3 j, paramétrables par ferme | validé par le client | Q-ALR-1, C-7 | marge de sécurité par fournisseur |
| DV-05 | 08/11/2026 | Corbeille : jamais d'écriture comptable ; contre-passation | validé par le client | Q-CPT-3, C-10 | — |
| DV-06 | 08/11/2026 | Droits du caissier : `/inventaire` interdit ; `/factures-mecef` consultation + réimpression | validé par le client | écarts documentation↔code (1) et (2) de `20_` §3 | rôle « responsable stock » ; onglet « Retours et Avoirs » |
| DV-07 | 08/11/2026 | 4 rôles : administrateur, comptable, caissier, animalier | validé par le client | Q-ROL-1, C-9, E-ROL | périmètre exact du comptable |

---

## 2. Fiches de décision

### DV-01 — Ration des poissons-chats (Clarias gariepinus) en pourcentage de la biomasse
- **Décision (texte normatif).** La ration journalière d'une catégorie de poissons = **effectif × poids moyen (g) × taux (% de biomasse par jour)**, jamais des grammes par poisson. Le barème est exprimé en **pourcentage de la biomasse par classe de poids**, éditable (CRUD, archivage) dans `/parametres/elevage` > « Rationnement ». Le poids moyen se recalcule par une **pesée d'échantillon tous les 15 jours** sur 5 à 10 % des sujets (minimum 30 poissons). La biomasse (effectif × poids moyen) est une grandeur de suivi.
- **Repères (ordres de grandeur, à valider par le technicien)** :

| Classe de poids | Taux de ration (% de la biomasse par jour) |
|---|---|
| alevin < 5 g | 10–20 % |
| fingerling 5–20 g | 6–8 % |
| juvénile 20–100 g | 3–5 % |
| grossissement 100–500 g | 2–3 % |
| > 500 g | 1–2 % |

  Indice de conversion visé 1,0–1,8 avec un granulé de qualité ; température optimale 26–30 °C, réduire la ration sous 22 °C.
- **Justification zootechnique.** Un poisson-chat grossit vite et son appétit relatif décroît avec la taille : la ration rapportée à la biomasse reste stable, alors qu'une ration « g/tête » oblige à ressaisir un barème à chaque pesée. La biomasse suit la croissance ; la ration en grammes par tête ne la suit pas.
- **Écart de LogiALVIA, vérifié dans le code (08/11/2026, lecture seule).** `logialvia_app/lib/elevage/domain/entities/configuration_espece.dart` porte `rationGrammesParJour` (« Ration normative en g/j ») : l'unité est le **gramme par jour et par sujet**, et la série **30 / 60 / 110 croît avec la taille** (Alevin 30, Juvénile 60, Mature 110). L'hypothèse « 30/60/110 = 3 %/6 %/11 % de la biomasse » **n'est donc PAS confirmée** : elle supposait l'unité « g par kg de biomasse et par jour » et un ordre inverse de la taille, ce qui n'est pas le cas. La série **30/60/110 ET la série 8/25/45** du barème semé (`data/seed/parametres_elevage_seeder.dart`, tous « non confirmé ») sont **à écarter** pour la pisciculture : le barème en % de biomasse les remplace, aucune des deux n'est convertie.
- **Impact par fichier** : `15_` RM-ELV-09b (nouvelle règle), §7.1, §9 (C-3) ; `23_` §3 (rationnement), §4.5, §8 ; `30_` (colonnes `poids_moyen_g`, `biomasse_g`, barème en %) ; `31_` cas T-DV01-* ; `13_` FR-ELV-31 et FR-ELV-33 ; `12_` SR-054 ; `10_` BR-043 ; `11_` PR-021.
- **Reste À DÉFINIR.** Taux unique retenu dans chaque fourchette (valeur par ferme, saisie par le technicien) ; bornes exactes des classes (5, 20, 100, 500 g : à confirmer) ; poids moyen initial d'un lot avant la première pesée (poids déclaré à l'achat ?) ; produit d'aliment (granulé flottant, taille du granulé) ; suivi de l'indice de conversion (Q-PIS-5 en partie).
- **Statut** : validé par le client le 08/11/2026.

### DV-02 — Vente et récolte de poisson : on vend au poids, on compte en sujets
- **Décision (texte normatif).** À **chaque vente ou récolte de poisson**, saisir **DEUX valeurs : le poids en kg ET le nombre de sujets**. L'effectif de la bande baisse du **nombre de sujets**. Si le nombre est inconnu, il est **estimé** = poids vendu (kg) × 1 000 ÷ poids moyen de la dernière pesée (g), et la ligne est marquée **« estimé »** (indicateur persisté, affiché, jamais présenté comme mesuré). La biomasse reste une grandeur de suivi (calculée, jamais saisie). Le produit « **Poisson-chat vif (kg)** » reste vendu **au kilo** ; le prix se calcule sur le poids.
- **Justification.** Le client facture au poids mais l'effectif d'un bassin se compte en têtes : sans les deux valeurs, l'effectif dérive. Une estimation honnête, marquée, vaut mieux qu'un nombre inventé ou qu'un effectif qui ne baisse pas.
- **Impact par fichier** : `15_` RM-ELV-12 (nouvelle règle), RM-ELV-05, §7.1 ; `24_` §3 (grille produits, panier : champ « Nombre de sujets », case « estimé ») ; `23_` §4.5 ; `30_` (`sale_lines.sold_weight_kg`, `sold_count`, `count_is_estimated`) ; `31_` cas T-DV02-* ; `12_` SR-054 ; `13_` FR-VTE-19 ; `10_` BR-044.
- **Refus** : poids ≤ 0 ; nombre ≤ 0 saisi ; nombre > effectif disponible de la catégorie ; nombre inconnu ET aucune pesée antérieure (estimation impossible : la saisie du nombre devient obligatoire).
- **Reste À DÉFINIR.** Arrondi de l'estimation (proposé : à l'entier le plus proche, moitié vers le haut, au moins 1, plafonné à l'effectif) ; écart toléré entre nombre saisi et nombre estimé avant avertissement ; poids minimum de vente ; délai d'attente après traitement (3 j du bleu de méthylène confirmé en prophylaxie).
- **Statut** : validé par le client le 08/11/2026.

### DV-03 — Pintades : « pintadeaux », incubation 28 jours paramétrable
- **Décision (texte normatif).**
  1. Le stade s'appelle **« pintadeaux »** ; le terme « Alevins » (poisson) est interdit pour une pintade. Le barème semé de LogiALVIA est à corriger (`parametres_elevage_seeder.dart` : ligne `pintades / Alevins`).
  2. **Incubation : 28 jours** (code `cycle_incubation.dart` et F3) ; `INDEX_MAITRE` qui dit 27 est à corriger. Mais la durée est un **PARAMÈTRE** (défaut 28 j) avec une **fenêtre d'éclosion 26–28 j** : 26–27 j ont été observés en climat chaud ou en couvaison naturelle.
  3. **Deux modes** : couveuse artificielle ; couvaison naturelle (sous poule ou pintade).
  4. **Date d'éclosion prévue = mise en incubation + 28 j**, avec plage affichée 26–28 j ; **mirages vers J7 et J14** ; **transfert à l'éclosoir vers J25** ; rappels automatiques pour ces trois échéances (mirages et transfert : en mode artificiel ; en couvaison naturelle, mirages possibles, pas de transfert).
  5. Suivi du **taux de fertilité** et du **taux d'éclosion** : à MESURER sur la ferme, aucune valeur imposée (RM-COU-03 existant).
  6. **Mortalité forte des premières semaines** du pintadeau (froid, humidité) : alerte prévue, **seuil À DÉFINIR**.
  7. Élevage des pintadeaux en **poussinière chauffée**.
- **Repères terrain, à valider (ordres de grandeur)** : incubateur 37,5–37,8 °C ; humidité 55–60 %, puis 65–75 % les trois derniers jours ; retournements plusieurs fois par jour jusqu'à J25 ; œufs conservés ≤ 7–10 jours avant la mise en incubation ; poussinière ≈ 35 °C la première semaine puis réduction progressive ; ration **10–60 g/jour par pintadeau selon l'âge**, **90–120 g/jour adulte** (à confirmer avec la fiche de l'aliment) ; abattage : élevage amélioré vers 14–16 semaines, élevage traditionnel bien plus tard.
- **Justification.** 28 j est la durée de référence (code et F3, corrigée par la Gérante) ; la fenêtre reconnaît les écarts de terrain sans les masquer ; les rappels évitent l'oubli des mirages (RM-COU-05).
- **Impact par fichier** : `15_` RM-COU-01 (mise à jour), RM-COU-06 (nouvelle), §7.2, §9 (C-4, C-6) ; `23_` §4.4, §6 ; `30_` (`cycle_couveuse.duree_incubation_jours`, `fenetre_min_jours`, `fenetre_max_jours`, `mode_incubation`) ; `31_` cas T-DV03-* ; `12_` SR-055 ; `13_` FR-ELV-19, FR-ELV-32, FR-ELV-34 ; `10_` BR-045, E-INC.
- **Reste À DÉFINIR.** Libellé exact de la catégorie 1 (Q-DV-8) ; tous les repères d'incubateur et de poussinière (technicien) ; seuil de l'alerte de mortalité des pintadeaux (valeur et fenêtre) ; durée exacte du stade pintadeau et seuil de maturité (Q-PIN-1) ; ration définitive par âge (Q-PIN-2 : l'ordre de grandeur est donné, le barème reste à valider) ; reproducteurs et œufs de pintade (Q-PIN-3).
- **Statut** : validé par le client le 08/11/2026.

### DV-04 — Autonomie de provende : deux seuils paramétrables par ferme
- **Décision (texte normatif).** Deux seuils, **paramétrables par ferme** : **alerte à 7 jours** (avertissement) et **critique à 3 jours**. Règle de calcul du **premier** seuil : **délai d'approvisionnement du fournisseur + marge de sécurité** ; la valeur **7** est le défaut. Autonomie (jours) = provende disponible (g) ÷ provende journalière calculée (g) (RM-ELV-10). Ne bloque JAMAIS l'enregistrement ; une alerte par objet et par jour. Contrainte : seuil critique < seuil d'alerte.
- **Justification.** Le délai d'achat de provende à Natitingou n'est pas celui d'une autre ferme : le seuil d'alerte doit couvrir au moins le délai de réapprovisionnement ; le seuil critique signale la rupture imminente.
- **Impact par fichier** : `15_` RM-ELV-10, §8, §9 (C-7) ; `25_` (seuils) ; `29_` (paramètres) ; `23_` §3 (KPI Pondeuses) ; `30_` (`farm_settings.autonomy_alert_days`, `autonomy_critical_days`) ; `31_` cas T-DV04-* ; `13_` FR-ELV-30, FR-ADM-14 ; `12_` SR-056 ; `10_` BR-046.
- **Reste À DÉFINIR.** Marge de sécurité (valeur par défaut, en jours) ; le délai d'approvisionnement est-il saisi par fournisseur ou une seule fois par ferme ?
- **Statut** : validé par le client le 08/11/2026.

### DV-05 — Corbeille : les écritures comptables n'y entrent jamais
- **Décision (texte normatif).** Les **écritures comptables n'entrent JAMAIS dans la corbeille** (intangibilité OHADA) : une écriture **ne se supprime pas et ne se restaure pas** ; elle se **CONTRE-PASSE**, puis on en saisit une nouvelle. LogiALVIA retire les écritures de sa corbeille (AgriERP avait raison) : `supprimerPiece` est supprimée, le type `Ecriture` sort de la liste blanche `TypeArchivable`.
- **Justification réglementaire.** Les principes comptables SYSCOHADA/OHADA exigent l'intangibilité et la traçabilité des écritures : toute correction laisse la trace de l'écriture d'origine et de son extourne. Restaurer une écriture supprimée ferait diverger le Bilan.
- **Impact par fichier** : `15_` RM-CPT-09 (nouvelle), §9 (C-10), §8 ; `26_` §4 ; `29_` onglet 6 « Corbeille » (7 types au lieu de 8) ; `12_` SR-007 (déjà conforme) ; `13_` FR-ADM-08, FR-CPT-08, FR-CPT-17 ; `30_` ; `31_` cas T-DV05-* ; `10_` BR-019, BR-047.
- **Reste À DÉFINIR.** Rien sur le principe. Reprise : les écritures déjà présentes dans une corbeille existante du poste doivent être restituées au journal par migration (hors périmètre de ce registre).
- **Statut** : validé par le client le 08/11/2026.

### DV-06 — Droits du caissier : la matrice fait foi, le code la suit
- **Décision (texte normatif).**
  - **`/inventaire`** : réservé à l'**administrateur** (et à un **responsable stock** s'il existe). Le caissier n'y accède pas (ni menu, ni URL directe).
  - **`/factures-mecef`** : le caissier **CONSULTE** et **RÉIMPRIME** ses factures ; il ne peut ni **annuler**, ni **retransmettre**, ni **créer d'avoir**.
  - **Le code suit la matrice des droits.** Si le client veut d'autres accès, on corrige la matrice (puis le code), jamais l'inverse. Les « arbitrages de la Gérante » consignés dans `permission_service.dart` (inventaire ouvert au caissier, facturation complète au caissier) sont **annulés** par cette décision.
- **Traduction en permissions** : `/inventaire` exige `view-stocks` (donc plus `view-ventes`) ; le caissier reçoit `view-facturation` SANS `manage-facturation` ; la réimpression est une lecture.
- **Justification.** Séparation des tâches : celui qui encaisse ne corrige pas la facture normalisée et ne voit pas le coût de revient ni la valorisation.
- **Impact par fichier** : `20_` §3 (matrice), §4 (routes 17 et 18) ; `21_` §8 ; `24_` §3, §5, §6 ; `25_` §8 ; `29_` (matrice en lecture) ; `12_` SR-057 ; `13_` FR-VTE-20, FR-STK-12 ; `14_` NFR-SEC-15 ; `10_` BR-048 ; `31_` T-DV06-*.
- **Reste À DÉFINIR.** Existence et nom du rôle « responsable stock » (cinquième rôle, ou permission donnée à un compte, ou absent) ; sort de l'onglet « Retours et Avoirs » de `/ventes` pour le caissier (le retour de marchandise est-il un geste de comptoir ? l'avoir lié à une facture normalisée est interdit au caissier par DV-06 ; en attendant, aucun avoir pour le caissier).
- **Statut** : validé par le client le 08/11/2026.

### DV-07 — Quatre rôles
- **Décision (texte normatif).** Quatre rôles : **administrateur (`admin`), comptable (`comptable`), caissier (`caissier`), animalier (`animalier`)**. Celui qui encaisse n'est pas celui qui comptabilise. LogiALVIA n'en avait que trois (le comptable était rattaché à `admin`).
- **Justification.** Séparation des fonctions ; alignement sur le web d'AgriERP (`RolesAndPermissionsSeeder.php` : `admin`, `comptable`, `caissier`, `animalier`).
- **Périmètre du comptable (PROPOSÉ, calqué sur AgriERP, à confirmer)** : `view/manage-comptabilite`, `export` et `view-rapports`/`export-rapports` ; consultation des ventes, de la facturation et des achats ; **gestes de facturation que le caissier n'a pas** (annuler, retransmettre, avoir) ; `close-fiscal-year` : à confirmer entre comptable et admin ; aucune saisie d'encaissement, aucun accès élevage ni paramètres.
- **Impact par fichier** : `20_` §3 ; `21_` §2, §8 ; `26_` §2 ; `29_` onglet 3 (libellés de rôle : « Comptable » à ajouter) et §4 ; `10_` BR-017, BR-049, E-ROL ; `11_` §2 (persona comptable) ; `12_` SR-057 ; `13_` FR-ADM-13 ; `31_` `RbacParRouteTest` ; `15_` §9 (C-9, C-12).
- **Reste À DÉFINIR.** Périmètre exact du comptable (RH et paie si le module existe : Q-RH-1/Q-PAI-1) ; libellé affiché du rôle (« Comptable »).
- **Statut** : validé par le client le 08/11/2026.

---

## 3. Repère noté, NON ADOPTÉ (pour plus tard) — ruminants

Aucune filière ruminants n'existe aujourd'hui. **Non adopté, pour plus tard** : la ration d'un ruminant se calcule en **matière sèche de 2,5 à 3,5 % du poids vif par jour**, sur le **poids moyen** du groupe (et non sur le nombre de têtes). Ordre de grandeur non validé ; aucune règle, aucune colonne, aucun test n'en découle tant que le client n'ouvre pas la filière.

## 4. Nouvelles questions ouvertes nées de ces décisions

| Id | Question | Décision liée |
|---|---|---|
| Q-DV-1 | Quel technicien/vétérinaire valide le barème en % de biomasse (taux par classe) et le poids moyen initial d'un lot avant la première pesée ? | DV-01 |
| Q-DV-2 | Arrondi de l'estimation du nombre de sujets, écart toléré et poids minimum de vente (proposition : entier le plus proche, au moins 1, plafonné à l'effectif) ? | DV-02 |
| Q-DV-3 | Seuil et fenêtre de l'alerte de mortalité des pintadeaux (premières semaines) ; repères d'incubateur et de poussinière validés par qui ? | DV-03 |
| Q-DV-4 | Marge de sécurité par défaut et délai d'approvisionnement : par fournisseur ou par ferme ? | DV-04 |
| Q-DV-5 | Un « responsable stock » existe-t-il (rôle, permission donnée à un compte, ou non) ? | DV-06 |
| Q-DV-6 | Le caissier garde-t-il l'onglet « Retours et Avoirs » de `/ventes` (retour de marchandise sans avoir sur facture normalisée) ? | DV-06 |
| Q-DV-7 | Périmètre exact du comptable (RH, achats, `close-fiscal-year`) ? | DV-07 |
| Q-DV-8 | Libellé exact du premier stade des pintades dans la fiche et le barème (« Poussins » du code ou « Pintadeaux ») et conséquence sur la catégorie 2 « Pintadau » ? (le rapprochement du barème se fait par libellé exact) | DV-03 |

## 5. Critères d'acceptation du registre

- [ ] Chaque DV porte date, décision, justification, impact par fichier, reste À DÉFINIR, statut.
- [ ] En tête : l'avertissement « ordres de grandeur… » (présent).
- [ ] Chaque question fermée est remplacée dans son fichier par « TRANCHÉ (DV-xx) ».
- [ ] Aucun repère zootechnique n'est codé en dur : barèmes, seuils, durées et fenêtres sont des paramètres.
