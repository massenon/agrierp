# Audit de Fidélité — Les 94 Écrans du Prototype AgriERP

Document de référence unique, consolidant les ~12 passes d'audit menées
dans cette session. Réponse directe à la question : *"la conformité et
fidélité visuelle des 94 écrans est-elle vérifiée ?"*

---

## Méthode — ce que cet audit EST et n'EST PAS

**Ce qu'il EST** : une comparaison rigoureuse du code source entre
chaque écran HTML du prototype et sa vue Blade réelle — classes
Tailwind exactes (couleurs, bordures, typographie), structure DOM,
libellés littéraux, présence des éléments interactifs (modales,
onglets, boutons, filtres).

**Ce qu'il n'EST PAS** : un rendu pixel réel dans un navigateur. Ce bac
à sable ne dispose d'aucun navigateur piloté. Un test visuel réel
(capture d'écran comparée, ou simplement ouvrir les deux versions
côte à côte) reste à faire de votre côté — c'est le complément naturel
de ce document, pas un substitut.

**Fiabilité de la méthode** : élevée pour tout ce qui est structurel
(présence/absence d'éléments, classes de couleur, libellés, logique)
— cette méthode a réellement trouvé et corrigé 8 écrans avec un vrai
écart, 2 écrans manquants, et des pièges de faux positifs de ma propre
méthode automatisée (documentés au fil de l'audit, pour la
transparence). Ne peut PAS détecter : un problème de rendu CSS
spécifique au navigateur, un espacement visuel subtil qui "a l'air"
correct dans le code mais ne l'est pas à l'écran, une police mal
chargée.

---

## Résultat global

| Statut | Nombre | Signification |
|---|---|---|
| ✅ Fidèle | 73 | Vérifié conforme, aucun écart trouvé |
| 🔧 Corrigé | 8 | Écart réel trouvé ET corrigé dans cette session |
| 🔨 Reconstruit | 2 | Écran manquant ou non-fidèle, reconstruit intégralement |
| ⚠️ Écart documenté | 2 | Limite de schéma réelle, signalée honnêtement plutôt que bricolée |
| 🚫 Orphelin | 4 | Confirmé jamais référencé par la navigation réelle, non porté à raison |
| — N/A | 4 | Page publique/technique hors périmètre applicatif RBAC |
| **Total** | **94** | |

**94/94 écrans du prototype individuellement examinés et statués.**

---

## Table complète des 94 écrans

| # | Écran prototype | Vue Blade | Statut | Détail |
|---|---|---|---|---|
| 1 | dashboard.html | dashboard/index.blade.php | ✅ | |
| 2 | login.html | auth/login.blade.php | ✅ | couleur via token `brand-maize`, rendu identique au hex du prototype |
| 3 | mon-profil.html | profil/mon-profil.blade.php | ✅ | plus réel que le prototype (vraie session, vrai audit) |
| 4 | notifications.html | notifications/index.blade.php | ✅ | |
| 5 | aide-a-propos.html | aide/index.blade.php | ✅ | |
| 6 | contact-editeur.html | contact/index.blade.php | ✅ | |
| 7 | audit-logs.html | parametres/audit-logs.blade.php | ✅ | |
| 8 | catalogue-produits.html | stocks/catalogue-produits.blade.php | ✅ | toggle grille/liste réel |
| 9 | catalogue-view.html | *(même composant, vue grille)* | ✅ | |
| 10 | ajouter-produit.html | stocks/ajouter-produit.blade.php | ✅ | |
| 11 | gestion-stocks.html | stocks/gestion-stocks.blade.php | ✅ | RBAC CRUD niveau action |
| 12 | ajustements-stock.html | *(onglet interne)* | ✅ | |
| 13 | mouvement-stock.html | *(onglet interne)* | 🔧 | Modifier/Archiver démo non repris (grand livre immuable) — documenté |
| 14 | seuils-alerte.html | stocks/seuils-alerte.blade.php | ✅ | |
| 15 | tableau-stocks.html | *(onglet interne)* | ✅ | |
| 16 | gestion-elevage.html | elevage/gestion-elevage.blade.php | ✅ | |
| 17 | gestion-bandes.html | elevage/gestion-bandes.blade.php | ✅ | RBAC CRUD niveau action |
| 18 | enregistrer-sujets.html | elevage/enregistrer-sujets.blade.php | 🔧 | Statut/Actions démo non repris ; champ Bande ajouté (justifié) |
| 19 | fiche-lapins.html | elevage/fiche-lapins.blade.php | 🔧 | colonne Traitements & Prophylaxie restaurée |
| 20 | fiche-porcs.html | elevage/fiche-porcs.blade.php | 🔧 | colonne Traitements & Prophylaxie restaurée |
| 21 | fiche-escargots.html | elevage/fiche-escargots.blade.php | 🔧 | colonne Traitements & Prophylaxie restaurée |
| 22 | fiche-volailles-pondeuses.html | elevage/fiche-pondeuses.blade.php | 🔧 | colonne Traitements & Rappels + bordure restaurées |
| 23 | fiche-volailles-reproducteurs.html | elevage/fiche-reproducteurs.blade.php | ⚠️ | Morts Repro/Poulet/Poussin sommés avant stockage — décision de schéma à trancher |
| 24 | fiche-volailles.html | — | 🚫 | orphelin, aucune page ne le référence, supplanté par 22+23 |
| 25 | suivi-reproduction.html | elevage/suivi-reproduction.blade.php | ✅ | 4 onglets (lapins/volailles/porcs/escargots) confirmés |
| 26 | soins-vaccins-hub.html | elevage/soins-vaccins-hub.blade.php | ✅ | 3 sections VMS internes confirmées |
| 27 | vms-calendrier.html | *(section interne)* | ✅ | |
| 28 | vms-registre.html | *(section interne)* | ✅ | |
| 29 | vms-suivi.html | *(section interne)* | ✅ | |
| 30 | transformation.html | elevage/transformation-form.blade.php | ✅ | |
| 31 | elevage-dashboard.html | elevage/dashboard-elevage.blade.php | 🔧 | libellé "GMQ (g/j)"→"(g/jour)" corrigé |
| 32 | analyse-croissance.html | *(onglet interne)* | ✅ | |
| 33 | prevision-croissance.html | *(onglet interne)* | ✅ | |
| 34 | suivi-sanitaire-analyse.html | *(onglet interne)* | ✅ | |
| 35 | bilan-technico-economique.html | elevage/bilan-technico-economique.blade.php | ✅ | |
| 36 | parametres-elevage.html | elevage/parametres-elevage.blade.php | ✅ | 3 tables internes confirmées |
| 37 | ventes-devis.html | ventes/ventes-devis-hub.blade.php | ✅ | |
| 38 | pos-interface.html | ventes/pos-interface.blade.php | ✅ | RBAC CRUD niveau action |
| 39 | devis.html | ventes/devis.blade.php | ✅ | |
| 40 | historique-ventes.html | ventes/historique-ventes.blade.php | ✅ | |
| 41 | retours-avoirs.html | ventes/retours-avoirs.blade.php | ✅ | |
| 42 | creances-clients.html | ventes/creances-clients-hub.blade.php | ✅ | |
| 43 | liste-clients.html | ventes/liste-clients.blade.php | ✅ | lien profil client ajouté |
| 44 | suivi-dettes.html | *(onglet interne)* | ✅ | |
| 45 | historique-avances.html | *(onglet interne)* | ✅ | |
| 46 | relances-clients.html | ventes/relances-clients.blade.php | ✅ | lien profil client ajouté |
| 47 | profile-client.html | ventes/profile-client.blade.php | 🔨 | écran manquant, reconstruit (4 onglets + 1er règlement créance réel du projet) |
| 48 | achats-commandes.html | achats/achats-commandes-hub.blade.php | ✅ | |
| 49 | enregistrer-achat.html | achats/enregistrer-achat.blade.php | ✅ | RBAC CRUD niveau action |
| 50 | liste-achats.html | achats/liste-achats.blade.php | ✅ | |
| 51 | bons-commande.html | achats/bons-commande.blade.php | ✅ | |
| 52 | fournisseurs.html | achats/fournisseurs-hub.blade.php | ✅ | |
| 53 | ajouter-fournisseur.html | achats/ajouter-fournisseur.blade.php | ✅ | |
| 54 | fiches-fournisseurs.html | achats/fiches-fournisseurs.blade.php | ✅ | lien profil complet ajouté |
| 55 | dettes-fournisseurs.html | achats/dettes-fournisseurs.blade.php | ✅ | |
| 56 | profile-fournisseur.html | achats/profile-fournisseur.blade.php | 🔨 | tiroir remplacé par écran standalone fidèle (3 onglets) |
| 57 | saisie-depenses.html | achats/saisie-depenses.blade.php | ✅ | |
| 58 | facturation.html | facturation/facturation.blade.php | ✅ | |
| 59 | personnel-stages.html | rh/personnel-stages-hub.blade.php | ✅ | |
| 60 | registre-employes.html | rh/registre-employes.blade.php | ✅ | |
| 61 | registre-stagiaires.html | rh/registre-stagiaires.blade.php | ✅ | |
| 62 | feuille-pointage.html | rh/feuille-pointage.blade.php | ✅ | |
| 63 | gestion-paie.html | rh/gestion-paie.blade.php | ✅ | RBAC CRUD niveau action |
| 64 | rh-attestations.html | rh/attestations.blade.php | ✅ | |
| 65 | administration.html | administration/administration-hub.blade.php | ✅ | gap historique critique résolu Sprint 9 |
| 66 | gestion-courriers.html | administration/gestion-courriers.blade.php | ✅ | RBAC CRUD niveau action |
| 67 | archivage-documents.html | administration/archivage-documents.blade.php | ✅ | |
| 68 | documents-administratifs.html | administration/documents-administratifs.blade.php | ✅ | |
| 69 | plan-comptable.html | comptabilite/plan-comptable.blade.php | ✅ | RBAC CRUD niveau action (écran de référence) |
| 70 | journal-comptable.html | comptabilite/journal-comptable.blade.php | ✅ | RBAC CRUD niveau action |
| 71 | rapport-bilan.html | comptabilite/bilan.blade.php | ✅ | |
| 72 | cloture-exercice.html | comptabilite/cloture-exercice.blade.php | ✅ | |
| 73 | comptabilite-analytique.html | comptabilite/comptabilite-analytique.blade.php | 🔧 | en-têtes "(FCFA)" complétés |
| 74 | comptabilite-hub.html | comptabilite/comptabilite-hub.blade.php | ✅ | 4 KPI dynamiques, zéro donnée statique |
| 75 | parametres-hub.html | parametres/parametres-hub.blade.php | ✅ | |
| 76 | parametres.html | parametres/donnees-entreprise.blade.php | ✅ | |
| 77 | roles-permissions.html | parametres/roles-permissions.blade.php | ✅ | rôles dynamiques confirmés réels |
| 78 | gestion-utilisateurs.html | parametres/gestion-utilisateurs.blade.php | ✅ | RBAC CRUD niveau action (écran le plus sensible) |
| 79 | modes-paiement.html | parametres/modes-paiement.blade.php | ✅ | |
| 80 | modules-actifs.html | parametres/modules-actifs.blade.php | ✅ | |
| 81 | rapports-exports.html | rapports/rapports-exports-hub.blade.php | ✅ | `export-X` RBAC ajouté sur les 6 enfants |
| 82 | rapport-recettes-depenses.html | rapports/recettes-depenses.blade.php | ✅ | |
| 83 | rapport-tresorerie.html | rapports/tresorerie.blade.php | ✅ | |
| 84 | rapport-creances.html | rapports/creances.blade.php | ✅ | |
| 85 | rapport-dettes.html | rapports/dettes.blade.php | ✅ | champ recherche fidèle (écart volontaire vs Créances) |
| 86 | rapport-elevage-synth.html | rapports/elevage-synth.blade.php | ⚠️ | Tableau 1 catégories fusionnées + Tableau 3 stock œufs indisponible — documentés |
| 87 | rapport-stocks-synth.html | rapports/stocks-synth.blade.php | ✅ | PMP extrait en méthode partagée |
| 88 | rapport-mensuel.html | — | 🚫 | orphelin, documenté dès le plan d'exécution |
| 89 | rapport-recettes.html | — | 🚫 | orphelin, documenté dès le plan d'exécution |
| 90 | rapport-depenses.html | — | 🚫 | orphelin, documenté dès le plan d'exécution |
| 91 | index.html | — | N/A | page technique du prototype |
| 92 | landing-page.html | — | N/A | page publique marketing |
| 93 | welcome.html | — | N/A | page publique marketing |
| 94 | logout.html | — | N/A | action seule, pas de vue |

---

## Les 2 écarts de schéma non corrigés — signalés honnêtement, pas bricolés

### `fiche-volailles-reproducteurs.html` (#23)
Le formulaire capture bien 3 champs séparés (Morts Repro/Poulet/Poussin)
mais ils sont sommés en un seul avant stockage, car
`livestock_daily_entries` est une table universelle partagée par 5
espèces. La ventilation par catégorie est réellement perdue à
l'enregistrement — corriger proprement demande une décision de schéma
(colonnes dédiées vs table de détail séparée), pas une retouche hâtive.

### `rapport-elevage-synth.html` (#86)
Même cause racine côté rapport : Tableau 1 affiche les colonnes
génériques disponibles plutôt que la ventilation Mères Pondeuses/
Couveuses/Éleveuses du prototype. Tableau 3 : "Stock Restant Hier/Total
Stock/Sorties Vente" supposent un grand livre de stock d'œufs qui
n'existe pas — non affiché plutôt qu'un chiffre inventé.

---

## Les 2 écrans reconstruits intégralement

### Profil Client (#47)
N'existait pas du tout. Construit : route standalone, 4 onglets
(Ventes/Créances/Avances/Relances), et surtout la **première
implémentation réelle du règlement de créance client** dans tout le
projet.

### Profil Fournisseur (#56)
Existait seulement comme tiroir d'aperçu à un onglet — le prototype est
une page complète à 3 onglets (Achats/Dettes/Commandes). Reconstruit à
l'identique de Profil Client, réutilisant la logique de règlement déjà
réelle côté Dettes Fournisseurs.

---

## Ce que cet audit a changé, au-delà de la fidélité visuelle

En cherchant des écarts visuels, l'audit a aussi trouvé et corrigé :
- Un gap RBAC critique (41 routes sur 42 non protégées par permission)
- Une 3e dimension RBAC (`export-X`) jamais vérifiée nulle part
- Un compte comptable manquant (411 Clients)
- Une notification de bienvenue périmée ("Sprint 1")
- Un pattern de sécurité CRUD au niveau action établi sur 10 écrans de référence

Le détail complet de chaque correction est dans `README_SPRINT0.md`
(sections "Audit de fidélité", 12 passes documentées).

---

## ⚠️ MISE À JOUR IMPORTANTE — 3 niveaux de vérification distincts, à ne pas confondre

Ce document initial (tableau ci-dessus, 94 écrans) reflète le **Niveau 1**
uniquement. Deux niveaux supplémentaires ont été appliqués depuis, à des
échelles différentes — la question directe "le balayage automatisé
respecte-t-il l'ordre des sections, les onglets, la position des
boutons, l'espacement, le responsive, les filtres de datatable, les
modales CRUD, l'absence de placeholders ?" mérite une réponse précise
par niveau, pas une réponse globale trompeuse.

### Niveau 1 — Comparaison par ensemble (les 94 écrans du tableau ci-dessus)
Classes de couleur, libellés, présence des éléments — **comparés comme
un ensemble, sans tenir compte de l'ordre**. Rapide, mais peut manquer
un écran dont les bons éléments existent dans le mauvais ordre ou à la
mauvaise position. C'est ce niveau qui donne le tableau "73 ✅ / 8 🔧 /
2 🔨" plus haut dans ce document.

### Niveau 2 — Vérification rigoureuse section-par-section (31 écrans à ce jour)
Lecture intégrale ligne par ligne, comparaison de l'**ordre réel** des
sections, onglets, position des boutons dans leur barre d'outils, nombre
exact de colonnes de chaque tableau. C'est ce niveau qui a trouvé le gap
systémique du Tableau de Bord, la modale Livraison manquante du POS, les
2 colonnes manquantes de Gestion des Stocks — des écarts que le Niveau 1
n'aurait pas détectés puisque les éléments existaient, juste pas au bon
endroit ou pas tous.

**Liste des 31 écrans passés au Niveau 2** : Notifications, Mon Profil,
Aide & À Propos, Contactez l'Éditeur, Dashboard, Gestion Élevage,
Gestion des Stocks, Catalogue Produits, POS Interface, Ventes & Devis
(hub), Devis, Retours et Avoirs, Achats & Commandes (hub), Liste
d'Achats, Personnel & Stages (hub), Registre Employés, Registre
Stagiaires, Feuille de Pointage, Gestion de la Paie, Enregistrer un
Achat, Bons de Commande, Fournisseurs (hub), Dettes Fournisseurs, Fiches
Fournisseurs, Fiche Lapins, Fiche Porcs, Fiche Escargots, Fiche
Pondeuses, Fiche Reproducteurs, Gestion des Bandes.

### Niveau 3 — Balayage automatisé ciblé (48 écrans, 1 seul critère)
**Une seule question posée, pour aller vite sur demande explicite** :
"le prototype a-t-il un bouton d'export PDF, et le Blade a-t-il un
`wire:click` d'export correspondant ?" — **rien d'autre**. Ne vérifie NI
l'ordre des sections, NI la structure des onglets, NI la position des
boutons, NI l'espacement, NI le responsive (jamais possible sans
navigateur), NI les filtres de datatable, NI les modales CRUD, NI les
placeholders "en attente" périmés. Un écran "propre" au Niveau 3 n'a
été vérifié QUE sur ce point précis — pas une garantie de fidélité
totale.

**Résultat du Niveau 3** : 29 alertes sur 48 écrans, 6 faux positifs
écartés après vérification manuelle (export réel au niveau hub), 23
gaps réels confirmés, 6 corrigés à ce jour (les 5 fiches d'élevage +
Gestion des Bandes), **17 restants** : `liste-clients`, `suivi-dettes`,
`historique-avances`, `relances-clients`, `historique-ventes`,
`saisie-depenses`, `seuils-alerte`, `gestion-courriers`,
`archivage-documents`, `documents-administratifs`, `plan-comptable`,
`journal-comptable`, `cloture-exercice`, `comptabilite-analytique`,
`roles-permissions`, `gestion-utilisateurs`, `parametres-elevage`.

### Ce que ça veut dire concrètement
Un écran marqué ✅ au Niveau 1 mais jamais passé au Niveau 2 **peut**
encore avoir un écart d'ordre, de position ou un placeholder périmé —
le Tableau de Bord était justement dans ce cas exact avant d'être
repassé au Niveau 2. **63 écrans sur 94 n'ont encore reçu QUE le Niveau
1** (et pour 48 d'entre eux, le Niveau 3 en plus, mais seulement sur le
point export). Aucun des 3 niveaux, seul ou combiné, ne remplace un test
visuel réel dans un navigateur — capacité que ce bac à sable n'a
toujours pas.

