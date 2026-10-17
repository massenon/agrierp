# RAPPORT DE FIDÉLITÉ n° 2 — poste Flutter vs prototype HTML

Généré par `outils/audit_fidelite.py` (ticket AF1.0). **Ce rapport remplace l'annexe A de `AUDIT_FIDELISATION.md`** : il est reproductible, l'association page → écran est déduite et non plus écrite à la main.

> ⚠️ La classe (a)/(b) de chaque motif est **une proposition**, rangée par motif (table `MOTIFS` de `outils/audit_fidelite.py`). Les motifs viennent des tickets passés ; leur rangement n'a pas été validé par le client. Un motif inconnu est signalé `?`, jamais rangé en (a) par défaut.

## 1. Les trois taux

| Taux | Définition | Valeur |
|---|---|---|
| **Strict** | libellé trouvé dans un littéral de l'écran, sans aucune exemption | 63.4 % (1330 / 2099) |
| **Assumé** | strict + écarts (a) motivés + données de démonstration | 79.1 % (1660 / 2099) |
| **Non porté** | écarts (b) : fonctionnalité absente, ticket à ouvrir | 10.9 % (229) |
| **Oubli / non classé** | (c) : sur une page portée, ni trouvé ni exempté | 10.0 % (210) |

Pour mémoire, l'audit n° 1 donnait **58,4 %** (1 351 / 2 314) — un taux qui mélangeait ces quatre réalités. Le dénominateur peut différer de quelques unités : les cartes et onglets sont comptés ici par page portée.

## 2. Par catégorie (strict)

| Catégorie | Retrouvés | Total | Taux strict |
|---|---|---|---|
| titres | 147 | 297 | 49.5 % |
| boutons | 256 | 537 | 47.7 % |
| colonnes | 482 | 595 | 81.0 % |
| etiquettes | 253 | 417 | 60.7 % |
| cartes | 145 | 206 | 70.4 % |
| onglets | 47 | 47 | 100.0 % |

## 3. Association page → écran

91 pages mesurées. Sources des associations : carte 5, carte+test 4, enum 17, enum+hub+parent 1, enum+test 11, enum+test+parent 1, hors-enum 1, hub 1, hub+parent 2, hub+test 32, hub+test+parent 3, parent 10, test 1, test+parent 2.

**Sans écran (0)** : .

**Écran parent mais page non portée (6)** — le titre de la page est absent de l'écran associé et moins de la moitié de son vocabulaire y figure : devis.html, enregistrer-sujets.html, fiche-volailles.html, gestion-bandes.html, rapport-bilan.html, transformation.html.

## 4. Les exemptions du test, classées

322 exemptions (204 globales, 118 par page).

| Classe | Nombre | Sens |
|---|---|---|
| A | 237 | divergence assumée et motivée — reste une exemption |
| B | 60 | fonctionnalité non portée — devient un ticket |
| D | 15 | donnée de démonstration / composant porteur — sans objet |
| ? | 10 | motif non reconnu — à classer à la main |

### 4.1 Exemptions (b) — ce qui devient un ticket

- **écran qui n'appelle pas la chaîne d'édition (F0.52)** — 14 libellés : Format d'export * · Exporter · Exporter PDF · Exporter · Imprimer · Exporter PDF · Exporter PDF · Exporter PDF …
- **chaîne d'édition non embarquée** — 9 libellés : Télécharger PDF · Exporter Courrier · Exporter les Clients · Télécharger clients.xlsx · PDF · Exporter le Bon (PDF) · Exporter le Journal · + Exporter le Journal …
- **module non embarqué au poste** — 7 libellés : Détail de la Vente · Annuler la Vente · Émettre l'Avoir · Relancer · Qté · P.U · Désignation
- **chaîne d'import non embarquée** — 7 libellés : Importer des Clients · Parcourir les fichiers · Télécharger le modèle client_sample.xlsx · Importer des Fournisseurs · Telecharger le modele supplier_sample.xlsx · Importer · Importer
- **import de fichier non embarqué** — 3 libellés : Importer un Inventaire · Telecharger inventory_template.xlsx · Importer des Soins (CSV/Excel)
- **historique de l'an dernier non synchronisé** — 3 libellés : Maladies les Plus Fréquentes — 2026 vs 2025 · Cas 2025 · Cas 2026
- **taxonomie des maladies absente du schéma** — 3 libellés : Maladie / Symptôme · Période de Sensibilité · Répartition Saisonnière des Cas (2026)
- **absences de stagiaire non embarquées** — 3 libellés : Absences / Abandon · Date de l'absence · Motif
- **référentiel des emplacements absent du schéma** — 2 libellés : Parc / Bâtiment · Parc / Fosse
- **bilan technico-économique non embarqué** — 2 libellés : Détail des Coûts · Détail des Revenus
- **infirmerie non synchronisée** — 2 libellés : Dossier Clinique · Alertes Sanitaires du Jour
- **création à la volée non portée ici : elle se fait dans Fournisseurs** — 2 libellés : Nouveau Fournisseur · Nouveau Fournisseur
- **création à la volée non portée ici : elle se fait au Catalogue Produits** — 2 libellés : Nouveau Produit · Nouveau Produit
- **ni sélecteur de fichier ni canal de pièce jointe** — 1 libellés : Piece Justificative

### 4.2 Motifs non reconnus

- `global` › Importer des Achats — « import xlsx/csv non porté : décision D10, le serveur (Laravel) n'a aucun import d'achats »
- `global` › Télécharger purchase_sample.xlsx — « import xlsx/csv non porté : décision D10, le serveur (Laravel) n'a aucun import d'achats »
- `historique-avances.html` › Importer — « import xlsx/csv non porté : décision D10, le serveur (Laravel) n'a aucun import d'avances »
- `historique-avances.html` › Importer des Avances — « import xlsx/csv non porté : décision D10, le serveur (Laravel) n'a aucun import d'avances »
- `historique-avances.html` › Télécharger advances_template.xlsx — « import xlsx/csv non porté : décision D10, le serveur (Laravel) n'a aucun import d'avances »
- `liste-achats.html` › Importer — « import xlsx/csv non porté : décision D10, le serveur (Laravel) n'a aucun import d'achats »
- `feuille-pointage.html` › Date * — « ÉCART À ARBITRER (F0.81, 09/10/2026) : la maquette attend « Date * » dans la modale de pointage, l'écran ne le porte pas ; écran non modifié, décision client »
- `liste-clients.html` › Téléphone * — « libellé de modale : le web n'exige pas le téléphone, le poste suit le web »
- `facturation.html` › Client * — « libellé non repris par l'écran, masqué jusqu'ici par une exemption globale devenue fausse (F0.73) — à examiner »
- `notifications.html` › Résumé des alertes — « panneau repliable des petits écrans (md:hidden) »

## 5. Faux négatifs probables (5)

Libellé absent à la lettre mais dont une chaîne de l'écran est très proche (ratio ≥ 0,82). **À trancher à la main** : reformulation à rétablir, ou équivalence à documenter. Non comptés comme trouvés.

- `declaration-tva.html` — « Montant HT » ≈ « Montant » (0.82)
- `fiche-volailles-pondeuses.html` — « Fiches Pondeuses - Aviculture Ponte » ≈ « Fiches Pondeuses - Aviculture » (0.91)
- `suivi-reproduction.html` — « N° Lapine ($R_1..R_n$) * » ≈ « N° Lapine (R1..Rn) * » (0.90)
- `suivi-reproduction.html` — « Nés Vivants » ≈ « Nés (Vivants) » (0.92)
- `suivi-reproduction.html` — « N° Truie ($T_1..T_n$) * » ≈ « N° Truie (T1..Tn) * » (0.89)

## 6. Page par page

Colonnes : S = strict, A = assumé (a), B = non porté (b), C = oubli (c), D = démonstration.

| Page | Écran | Total | Strict | S | A | B | C | D |
|---|---|---|---|---|---|---|---|---|
| rapport-bilan.html | comptabilite_screen.dart | 4 | 0.0 % | 0 | 0 | 4 | 0 | 0 |
| transformation.html | gestion_elevage_screen.dart | 19 | 0.0 % | 0 | 0 | 18 | 0 | 1 |
| fiche-volailles.html | gestion_elevage_screen.dart | 58 | 3.4 % | 2 | 0 | 54 | 0 | 2 |
| gestion-bandes.html | gestion_elevage_screen.dart | 40 | 5.0 % | 2 | 1 | 35 | 0 | 2 |
| enregistrer-sujets.html | gestion_elevage_screen.dart | 24 | 8.3 % | 2 | 1 | 18 | 0 | 3 |
| cloture-exercice.html | comptabilite_screen.dart | 26 | 11.5 % | 3 | 0 | 0 | 22 | 1 |
| devis.html | ventes_devis_screen.dart | 42 | 14.3 % | 6 | 2 | 26 | 0 | 8 |
| gestion-elevage.html | gestion_elevage_screen.dart | 7 | 14.3 % | 1 | 0 | 0 | 6 | 0 |
| comptabilite-hub.html | comptabilite_screen.dart | 5 | 20.0 % | 1 | 0 | 0 | 4 | 0 |
| comptabilite-analytique.html | comptabilite_screen.dart | 9 | 22.2 % | 2 | 0 | 0 | 6 | 1 |
| declaration-tva.html | comptabilite_screen.dart | 16 | 25.0 % | 4 | 0 | 0 | 12 | 0 |
| etats-financiers.html | comptabilite_screen.dart | 20 | 25.0 % | 5 | 0 | 0 | 15 | 0 |
| retours-avoirs.html | ventes_devis_screen.dart | 30 | 30.0 % | 9 | 0 | 1 | 20 | 0 |
| suivi-sanitaire-analyse.html | dashboard_elevage_screen.dart | 10 | 30.0 % | 3 | 0 | 7 | 0 | 0 |
| vms-calendrier.html | soins_vaccins_screen.dart | 12 | 33.3 % | 4 | 4 | 0 | 2 | 2 |
| ajouter-produit.html | ajouter_produit_screen.dart | 22 | 36.4 % | 8 | 11 | 0 | 2 | 1 |
| vms-suivi.html | soins_vaccins_screen.dart | 24 | 37.5 % | 9 | 0 | 1 | 14 | 0 |
| pos-interface.html | caisse_screen.dart | 40 | 42.5 % | 17 | 1 | 4 | 17 | 1 |
| seuils-alerte.html | catalogue_produits_screen.dart | 19 | 47.4 % | 9 | 5 | 1 | 1 | 3 |
| audit-logs.html | parametres_generaux_screen.dart | 16 | 50.0 % | 8 | 0 | 5 | 0 | 3 |
| journal-comptable.html | comptabilite_screen.dart | 25 | 52.0 % | 13 | 9 | 0 | 0 | 3 |
| profile-client.html | clients_creances_screen.dart | 25 | 52.0 % | 13 | 0 | 0 | 12 | 0 |
| modes-paiement.html | parametres_generaux_screen.dart | 23 | 52.2 % | 12 | 9 | 0 | 0 | 2 |
| plan-comptable.html | comptabilite_screen.dart | 19 | 52.6 % | 10 | 6 | 0 | 0 | 3 |
| rapprochement-bancaire.html | comptabilite_screen.dart | 17 | 52.9 % | 9 | 0 | 0 | 8 | 0 |
| animal-details.html | fiche_sujet_screen.dart | 43 | 53.5 % | 23 | 15 | 0 | 3 | 2 |
| registre-stagiaires.html | personnel_stages_screen.dart | 26 | 53.8 % | 14 | 8 | 3 | 0 | 1 |
| suivi-reproduction.html | suivi_reproduction_screen.dart | 102 | 54.9 % | 56 | 25 | 2 | 18 | 1 |
| gestion-utilisateurs.html | parametres_generaux_screen.dart | 20 | 55.0 % | 11 | 5 | 1 | 0 | 3 |
| suivi-dettes.html | clients_creances_screen.dart | 20 | 55.0 % | 11 | 6 | 1 | 0 | 2 |
| facturation.html | facturation_screen.dart | 25 | 56.0 % | 14 | 7 | 0 | 1 | 3 |
| bons-commande.html | achats_commandes_screen.dart | 31 | 58.1 % | 18 | 9 | 3 | 0 | 1 |
| registre-employes.html | personnel_stages_screen.dart | 22 | 59.1 % | 13 | 7 | 1 | 0 | 1 |
| fiches-fournisseurs.html | fournisseurs_screen.dart | 30 | 60.0 % | 18 | 5 | 5 | 0 | 2 |
| historique-ventes.html | ventes_devis_screen.dart | 33 | 60.6 % | 20 | 0 | 10 | 1 | 2 |
| liste-clients.html | clients_creances_screen.dart | 33 | 63.6 % | 21 | 3 | 7 | 0 | 2 |
| dettes-fournisseurs.html | fournisseurs_screen.dart | 23 | 65.2 % | 15 | 3 | 1 | 3 | 1 |
| roles-permissions.html | parametres_generaux_screen.dart | 45 | 66.7 % | 30 | 12 | 1 | 0 | 2 |
| catalogue-view.html | catalogue_produits_screen.dart | 22 | 68.2 % | 15 | 6 | 0 | 1 | 0 |
| relances-clients.html | clients_creances_screen.dart | 16 | 68.8 % | 11 | 3 | 1 | 0 | 1 |
| parametres-elevage.html | parametres_elevage_screen.dart | 61 | 68.9 % | 42 | 16 | 1 | 0 | 2 |
| rapport-mensuel.html | rapports_exports_screen.dart | 13 | 69.2 % | 9 | 1 | 0 | 3 | 0 |
| elevage-dashboard.html | dashboard_elevage_screen.dart | 56 | 69.6 % | 39 | 2 | 9 | 4 | 2 |
| gestion-stocks.html | gestion_stocks_screen.dart | 49 | 71.4 % | 35 | 6 | 2 | 3 | 3 |
| parametres.html | parametres_generaux_screen.dart | 15 | 73.3 % | 11 | 4 | 0 | 0 | 0 |
| fiche-lapins.html | fiche_lapins_screen.dart | 46 | 73.9 % | 34 | 0 | 0 | 5 | 7 |
| fiche-volailles-reproducteurs.html | fiche_reproducteurs_screen.dart | 46 | 73.9 % | 34 | 1 | 0 | 4 | 7 |
| feuille-pointage.html | personnel_stages_screen.dart | 24 | 75.0 % | 18 | 2 | 1 | 1 | 2 |
| liste-achats.html | achats_commandes_screen.dart | 36 | 75.0 % | 27 | 0 | 0 | 3 | 6 |
| saisie-depenses.html | saisie_depenses_screen.dart | 24 | 75.0 % | 18 | 0 | 0 | 5 | 1 |
| rh-attestations.html | personnel_stages_screen.dart | 19 | 78.9 % | 15 | 4 | 0 | 0 | 0 |
| fiche-escargots.html | fiche_escargots_screen.dart | 48 | 79.2 % | 38 | 1 | 0 | 3 | 6 |
| fiche-volailles-pondeuses.html | fiche_pondeuses_screen.dart | 51 | 80.4 % | 41 | 1 | 0 | 4 | 5 |
| historique-avances.html | clients_creances_screen.dart | 28 | 82.1 % | 23 | 0 | 0 | 3 | 2 |
| gestion-paie.html | personnel_stages_screen.dart | 17 | 82.4 % | 14 | 1 | 1 | 0 | 1 |
| vms-registre.html | soins_vaccins_screen.dart | 34 | 82.4 % | 28 | 1 | 3 | 0 | 2 |
| fiche-porcs.html | fiche_porcs_screen.dart | 46 | 82.6 % | 38 | 0 | 0 | 2 | 6 |
| enregistrer-achat.html | achats_commandes_screen.dart | 30 | 83.3 % | 25 | 2 | 2 | 0 | 1 |
| bilan-technico-economique.html | bilan_technico_economique_vue.dart | 7 | 85.7 % | 6 | 1 | 0 | 0 | 0 |
| dashboard.html | tableau_de_bord_screen.dart | 31 | 87.1 % | 27 | 2 | 0 | 0 | 2 |
| login.html | login_screen.dart | 10 | 90.0 % | 9 | 0 | 0 | 1 | 0 |
| ajouter-fournisseur.html | fournisseurs_screen.dart | 22 | 90.9 % | 20 | 1 | 0 | 0 | 1 |
| notifications.html | notifications_screen.dart | 11 | 90.9 % | 10 | 0 | 0 | 1 | 0 |
| analyse-croissance.html | dashboard_elevage_screen.dart | 14 | 92.9 % | 13 | 1 | 0 | 0 | 0 |
| archivage-documents.html | administration_screen.dart | 21 | 95.2 % | 20 | 0 | 0 | 0 | 1 |
| documents-administratifs.html | administration_screen.dart | 21 | 95.2 % | 20 | 0 | 0 | 0 | 1 |
| gestion-courriers.html | administration_screen.dart | 23 | 95.7 % | 22 | 0 | 0 | 0 | 1 |
| rapport-elevage-synth.html | rapports_exports_screen.dart | 49 | 98.0 % | 48 | 0 | 0 | 0 | 1 |
| achats-commandes.html | achats_commandes_screen.dart | 6 | 100.0 % | 6 | 0 | 0 | 0 | 0 |
| administration.html | administration_screen.dart | 6 | 100.0 % | 6 | 0 | 0 | 0 | 0 |
| aide-a-propos.html | aide_a_propos_screen.dart | 10 | 100.0 % | 10 | 0 | 0 | 0 | 0 |
| balance-generale.html | comptabilite_screen.dart | 12 | 100.0 % | 12 | 0 | 0 | 0 | 0 |
| catalogue-produits.html | catalogue_produits_screen.dart | 4 | 100.0 % | 4 | 0 | 0 | 0 | 0 |
| contact-editeur.html | contact_editeur_screen.dart | 11 | 100.0 % | 11 | 0 | 0 | 0 | 0 |
| creances-clients.html | clients_creances_screen.dart | 8 | 100.0 % | 8 | 0 | 0 | 0 | 0 |
| fournisseurs.html | fournisseurs_screen.dart | 6 | 100.0 % | 6 | 0 | 0 | 0 | 0 |
| grand-livre.html | comptabilite_screen.dart | 12 | 100.0 % | 12 | 0 | 0 | 0 | 0 |
| modules-actifs.html | parametres_generaux_screen.dart | 1 | 100.0 % | 1 | 0 | 0 | 0 | 0 |
| mon-profil.html | mon_profil_screen.dart | 10 | 100.0 % | 10 | 0 | 0 | 0 | 0 |
| parametres-hub.html | parametres_generaux_screen.dart | 12 | 100.0 % | 12 | 0 | 0 | 0 | 0 |
| personnel-stages.html | personnel_stages_screen.dart | 10 | 100.0 % | 10 | 0 | 0 | 0 | 0 |
| prevision-croissance.html | dashboard_elevage_screen.dart | 9 | 100.0 % | 9 | 0 | 0 | 0 | 0 |
| profile-fournisseur.html | profil_fournisseur_screen.dart | 18 | 100.0 % | 18 | 0 | 0 | 0 | 0 |
| rapport-creances.html | rapports_exports_screen.dart | 7 | 100.0 % | 7 | 0 | 0 | 0 | 0 |
| rapport-dettes.html | rapports_exports_screen.dart | 7 | 100.0 % | 7 | 0 | 0 | 0 | 0 |
| rapport-recettes-depenses.html | rapports_exports_screen.dart | 11 | 100.0 % | 11 | 0 | 0 | 0 | 0 |
| rapport-stocks-synth.html | rapports_exports_screen.dart | 7 | 100.0 % | 7 | 0 | 0 | 0 | 0 |
| rapport-tresorerie.html | rapports_exports_screen.dart | 8 | 100.0 % | 8 | 0 | 0 | 0 | 0 |
| rapports-exports.html | rapports_exports_screen.dart | 15 | 100.0 % | 15 | 0 | 0 | 0 | 0 |
| soins-vaccins-hub.html | soins_vaccins_screen.dart | 6 | 100.0 % | 6 | 0 | 0 | 0 | 0 |
| ventes-devis.html | ventes_devis_screen.dart | 8 | 100.0 % | 8 | 0 | 0 | 0 | 0 |

## 7. Oublis (c) — à corriger

- **cloture-exercice.html** (22) : Bascule & Clôture d'Exercice Comptable [titres] · Historique des Clôtures Périodiques [titres] · Assistant de Clôture d'Exercice (2026 → 2027) [titres] · Clôturer l'Exercice 2026 ? [titres] · Clôturer ce Mois ? [titres] · Déclôturer ce Mois ? [titres] · Clôture Annuelle [boutons] · Clôturer le Mois Sélectionné [boutons] · Déclôturer (exceptionnel) [boutons] · Marquer comme terminé [boutons] · Calculer et Solder [boutons] · Clôturer l'Exercice 2026 [boutons] · Confirmer la Clôture [boutons] · Confirmer la Clôture du Mois [boutons] …
- **retours-avoirs.html** (20) : Nouveau Retour — Assistant en 5 étapes [titres] · Nouveau Retour [boutons] · Précédent [boutons] · Suivant [boutons] · Exporter l'Avoir (PDF) [boutons] · Décision [colonnes] · Numéro de la facture d'origine [etiquettes] · Sélection des articles à retourner [etiquettes] · Lapin vivant (vendu : 5) [etiquettes] · Œufs de table (vendu : 8 plateaux) [etiquettes] · Motif du retour [etiquettes] · Inspection sanitaire (animaux vivants) [etiquettes] · Réintégration Animal sain — hausse du stock d'élevage, rattaché au lot d'origine. [etiquettes] · Quarantaine Risque sanitaire mineur — isolement en infirmerie d'élevage. [etiquettes] …
- **suivi-reproduction.html** (18) : N° Lapine ($R_1..R_n$) * [etiquettes] · Résultat de Palpation (J+14) [etiquettes] · Total Petits Nés [etiquettes] · Nés Vivants [etiquettes] · Sevrés Mâles [etiquettes] · Sevrés Femelles [etiquettes] · Poids Général des Lapereaux Sevrés (g) [etiquettes] · Total Porcelets Nés Vivants [etiquettes] · Code Lot Incubation * [etiquettes] · Bande Reproducteurs * [etiquettes] · Date Incubation (J0) * [etiquettes] · Œufs Couvés (Mise en couvoir) * [etiquettes] · N° Truie ($T_1..T_n$) * [etiquettes] · Parc / Fosse * [etiquettes] …
- **pos-interface.html** (17) : Livraison [titres] · Nouveau Client [titres] · Nouveau Produit [titres] · Choisir le compte [titres] · Ajouter Produit Ferme [boutons] · Livraison concernée ✓ [boutons] · Aviculture [boutons] · Cuniculture [boutons] · Porciculture [boutons] · Héliciculture [boutons] · Produits finis [boutons] · Maraîchage [boutons] · Équipements [boutons] · Télécharger la Facture [boutons] …
- **etats-financiers.html** (15) : Actif (Emplois) [titres] · Passif (Ressources) [titres] · Compte de Résultat — Structure en Cascade SYSCOHADA [titres] · Tableau des Flux de Trésorerie (TAFIRE simplifié) [titres] · Note 1 — Méthodes Comptables [titres] · Note 2 — Immobilisations [titres] · Note 3 — Stocks [titres] · Note 4 — Créances et Dettes [titres] · Note 5 — Engagements Hors Bilan [titres] · Exporter PDF (Onglet Actif) [boutons] · Flux de Trésorerie [boutons] · Notes Annexes [boutons] · Valeur Brute [colonnes] · Amort. Cumulés [colonnes] …
- **vms-suivi.html** (14) : Déclarer le Décès ? [titres] · Nouvelle Entrée Infirmerie [titres] · Nouvelle Entrée Infirmerie [boutons] · KPIs de l'Infirmerie [boutons] · Confirmer le Décès [boutons] · Date d'entrée [colonnes] · Lot / Sujet [colonnes] · Lot / Sujet * [etiquettes] · Motif * [etiquettes] · Date d'Entrée * [etiquettes] · Guéris (mois) [cartes] · Sous Traitement [cartes] · Décès (mois) [cartes] · Taux d'Infirmerie [cartes]
- **declaration-tva.html** (12) : TVA Collectée — Ventes Assujetties [titres] · TVA Déductible — Achats Assujettis [titres] · Générer la Déclaration PDF [boutons] · N° Facture [colonnes] · Client [colonnes] · Montant HT [colonnes] · Montant TTC [colonnes] · Référence [colonnes] · Fournisseur [colonnes] · Période de déclaration : [etiquettes] · TVA Collectée (4431) [cartes] · TVA Déductible (4452) [cartes]
- **profile-client.html** (12) : Profil Client [titres] · Enregistrer un Reglement [titres] · Modifier la fiche [boutons] · Enregistrer un reglement [boutons] · Envoyer une relance rapide [boutons] · Avances & Acomptes [boutons] · Regler [boutons] · + Enregistrer une nouvelle avance [boutons] · Valider le Reglement [boutons] · Articles [colonnes] · Anciennete [colonnes] · Montant du Reglement (FCFA) [etiquettes]
- **rapprochement-bancaire.html** (8) : Grand Livre (Compte 521) [titres] · Relevé Bancaire Importé [titres] · Historique des Rapprochements Clôturés [titres] · Importer un Relevé (CSV) [boutons] · Statut [colonnes] · Solde Livre (Grand Livre) [cartes] · Solde Relevé Bancaire [cartes] · Opérations en Instance [cartes]
- **comptabilite-analytique.html** (6) : Chiffre d'Affaires vs Coûts Directs par Espèce [titres] · Top 3 Charges (Espèce Sélectionnée) [titres] · Chiffre d'Affaires Analytique [cartes] · Charges Directes [cartes] · Marge Brute Opérationnelle [cartes] · Taux de Rentabilité [cartes]
- **gestion-elevage.html** (6) : Registres par Espèce [titres] · Accès Rapides — Élevage & Soins [titres] · Effectif Total Vivant [cartes] · Bandes Actives [cartes] · Alertes Stock Aliment [cartes] · Taux Mortalité (mois) [cartes]
- **fiche-lapins.html** (5) : Exporter PDF [boutons] · Espèce [colonnes] · Sevrés [colonnes] · Poids Général Pesé (g) (Pré-rempli de J-1) [etiquettes] · Taille Échantillon (Auto = Effectif Final) [etiquettes]
- **saisie-depenses.html** (5) : Détail de la Dépense [titres] · Confirmer l'Archivage [titres] · Exporter PDF [boutons] · Oui, Archiver Définitivement [boutons] · Actions [colonnes]
- **comptabilite-hub.html** (4) : Total Actif (Bilan) [cartes] · Trésorerie Totale [cartes] · Marge Nette (Analytique) [cartes] · Résultat de l'Exercice [cartes]
- **elevage-dashboard.html** (4) : Coût Total du Lot [cartes] · Revenu Total du Lot [cartes] · Marge Nette [cartes] · Coût de Revient / Sujet [cartes]
- **fiche-volailles-pondeuses.html** (4) : Fiches Pondeuses - Aviculture Ponte [titres] · Exporter PDF [boutons] · Date / Jour [colonnes] · Bâtiment Démarrage D1 [etiquettes]
- **fiche-volailles-reproducteurs.html** (4) : Fiches Volailles - Reproducteurs, Poussins & Goliath [titres] · Exporter PDF [boutons] · Espèce [colonnes] · Date [colonnes]
- **animal-details.html** (3) : Consommation du Mois [cartes] · Coût Alimentaire (Mois) [cartes] · Ration Journalière Moyenne [cartes]
- **dettes-fournisseurs.html** (3) : Dettes totales [cartes] · En retard [cartes] · Fournisseurs concernés [cartes]
- **fiche-escargots.html** (3) : Exporter PDF [boutons] · Espèce [colonnes] · Date [colonnes]
- **gestion-stocks.html** (3) : Date du Nouveau Stock * [etiquettes] · Quantité Ajoutée * [etiquettes] · PMP (FCFA) * [etiquettes]
- **rapport-mensuel.html** (3) : Rapport Mensuel de Synthèse [titres] · Juillet [colonnes] · Juin [colonnes]
- **ajouter-produit.html** (2) : Références catalogue [cartes] · Nouveaux (mois) [cartes]
- **fiche-porcs.html** (2) : Exporter PDF [boutons] · Date [colonnes]
- **vms-calendrier.html** (2) : Type de Tâche * [etiquettes] · Date Planifiée * [etiquettes]
- **catalogue-view.html** (1) : Fourchette de Prix (FCFA) — laisser vide si Sur devis [etiquettes]
- **facturation.html** (1) : Statut "Transmise" (simulation) [cartes]
- **feuille-pointage.html** (1) : Présents (jour) [cartes]
- **historique-ventes.html** (1) : MOTIF DU RETOUR / DE L'ANNULATION [etiquettes]
- **login.html** (1) : Envoyer le lien de réinitialisation [boutons]
- **seuils-alerte.html** (1) : Nouveau seuil minimum * [etiquettes]
