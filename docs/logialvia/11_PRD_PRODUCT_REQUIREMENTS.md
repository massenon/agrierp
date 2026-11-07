# 11 — PRD : exigences produit de LogiALVIA (web Laravel + poste Windows Flutter)

## USAGE

- **Quand l'utiliser** : après le BRS (`10_BRS_BUSINESS_REQUIREMENTS.md`), avant d'écrire une ligne de code d'un module ; à relire à chaque jalon. Pour UN ticket précis, utiliser en plus le skill `prd` du dépôt (`.claude/skills/`) puis `plan`.
- **Ordre** : `10_BRS` → **`11_PRD`** → `12_SRS` → `13_FRS` → `14_NFRS` → `15_REGLES_METIER` → `20_MODULES_INDEX` et modules.
- **Entrées** : `logialvia/docs/B2_PRD_Product_Requirements.md`, `B1_BRS_Business_Requirements.md`, `03_INVENTAIRE_31_ECRANS.md`, `INDEX_MAITRE.md`, `I1_Matrice_RBAC.md`, `I2_Gestion_Modules_Actifs.md`, `docs/logialvia/GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md` (§1 ordre de portage, bloc 14), `docs/prd/*.md` (modèles de PRD d'AgriERP), `docs/PLAN_FINALISATION.md`.
- **Sorties** : ce fichier à jour (personas, parcours, exigences `PR-nnn` avec critère d'acceptation, phasage, métriques, risques).
- **Chemins** : `logialvia/…` = `/home/user/massenon/logialvia/…` (lecture seule) ; sans préfixe = monorepo `/home/user/agrierp`.

---

## 1. PROMPT — « Rédige / mets à jour le PRD de LogiALVIA »

> **Rôle.** Product manager senior d'un ERP agricole francophone, rigoureux sur la fidélité au terrain.
> **Contexte.** Voir `10_BRS_BUSINESS_REQUIREMENTS.md` §2. Surfaces : (a) le WEB (Laravel 12, Livewire 3, Alpine, Tailwind ; maître des règles), (b) le POSTE Windows Flutter hors ligne (Drift/SQLite ; fidèle au web, prouvé par garde-fous), (c) PWA du web (installable ; hors ligne navigateur À CONCEVOIR).
> **Tâches.** (1) Pour chaque persona, décris les parcours quotidiens réels (matin, caisse, fin de journée) ; (2) pour chaque module de `20_MODULES_INDEX.md`, écris les exigences produit `PR-nnn` au format « En tant que <rôle>, je veux <geste> afin de <valeur> » + critère d'acceptation mesurable ; (3) précise pour chaque exigence la surface (Web / Poste / Les deux) et le comportement hors ligne ; (4) tiens à jour phasage, hors périmètre, métriques, risques ; (5) liste les questions ouvertes.
> **Contraintes.** Fidélité au prototype et aux fiches papier (B2 §4 : « contrainte produit non négociable ») ; français ; une exigence = un geste vérifiable ; pas de règle métier inventée (À DÉFINIR AVEC LE CLIENT + question) ; pas d'exigence décorative (A1 §2.3) ; le web est le maître, le poste suit (doctrine : `docs/DOCTRINE_PORTAGE.md` art. 0 et 5).
> **Critères d'acceptation.** (a) ≥ 60 lignes `PR-` ; (b) chacune a Surface + Rôle + Hors ligne + Critère ; (c) chaque écran de `03_INVENTAIRE_31_ECRANS.md` est couvert par au moins une `PR-` (vérifier par les 31 noms de route) ; (d) le phasage reprend l'ordre du guide §1 ; (e) les statuts À DÉFINIR renvoient à une question numérotée.
> **Interdits.** Ne pas décrire une fonction d'AgriERP comme déjà présente dans LogiALVIA ; ne pas écrire de code ; ne pas affirmer que la PWA hors ligne, l'import xlsx ou la paie existent (ils n'existent pas : guide blocs 20, 21 ; B1 §6).

---

## 2. Vision et personas

**Vision** [B2 §1, reprise] : « l'outil de gestion quotidienne d'une exploitation agricole multi-filières, pensé pour qu'un animalier ou un caissier sans formation informatique puisse l'utiliser dès le premier jour — parce que sa structure reproduit fidèlement les fiches papier et le comptoir connus du personnel ». S'y ajoute (07/11/2026) : **les mêmes chiffres au web et au poste, sur plusieurs postes**.

| Persona | Rôle technique | Gestes quotidiens | Besoin critique | Surface principale |
|---|---|---|---|---|
| Animalier (Agent d'Élevage) | `animalier` | fiche journalière par filière, couvoir, soins, infirmerie, rappels du jour | ne jamais ressaisir, ne jamais voir un chiffre incohérent avec ce qu'il a compté | Poste (hors ligne) |
| Caissier (Agent de Vente) | `caissier` | caisse (panier, remise, règlement), historique, retours/avoirs, clients/créances | rapidité face au client, avances/créances simples | Poste (hors ligne) |
| Administratrice / Gérante / Direction | `admin` | tableaux de bord, stocks, achats, comptabilité, paramètres, utilisateurs, clôture | chiffres fiables au premier coup d'œil, traçabilité | Web |
| Comptable (persona B2, **sans rôle** en I1) | rattaché à `admin` (Q-ROL-1) | journal, balance, états, clôture | aucune écriture orpheline | Web |
| Administrateur système (nouveau) | hors application | serveur, sauvegardes, mises à jour | continuité de service | Hors application |

## 3. Portée par module (vue produit ; détail dans `20_MODULES_INDEX.md` et `21_` à `29_`)

| Module | Fonctionnalités clés | Surface | Fichier |
|---|---|---|---|
| Authentification & Compte | connexion, verrouillage 5 essais/15 min, mon profil, aide, contact | Web + Poste | `21_` |
| Pilotage | tableau de bord (8 KPI), dashboard élevage, rappels du jour | Web + Poste | `22_` |
| Élevage par filière | 6 filières, bandes, sujets, transferts, couvoir, soins, infirmerie, rationnement, paramètres élevage | Web + Poste | `23_` |
| Ventes, Clients, Facturation | caisse, devis, historique, avoirs, créances, relances, facture simple/normalisée | Web + Poste | `24_` |
| Stocks & Achats | intrants, produits vendables, fabrication de provende, achats, fournisseurs, dépenses | Web + Poste | `25_` |
| Comptabilité & exercices | journal, grand livre, balance, états, clôture, analytique, plan comptable, immobilisations | Web (poste : demandes) | `26_` |
| RH & Paie (option) | employés, stagiaires, pointage, paie | Web + Poste (si le client accepte) | `27_` |
| Rapports, exports, imports | 6 onglets de rapports, PDF, xlsx, import en masse | Web + Poste | `28_` |
| Paramètres & Administration | modules actifs, entreprise, logo/favicon, SMTP, MeCeF, utilisateurs, modes de paiement, sauvegardes, corbeille, audit | Web (+ Poste partiel) | `29_` |

## 4. Exigences produit

Surface : W = web, P = poste, WP = les deux. HL = comportement hors ligne au poste. Statut : C confirmé, P proposé, D à définir.

### 4.1 Compte et accès

| ID | Exigence (En tant que… je veux… afin de…) | Surf. | HL | Critère d'acceptation | Source | St. |
|---|---|---|---|---|---|---|
| PR-001 | Tout utilisateur se connecte avec identifiant + mot de passe ; le rôle vient du compte, jamais d'un sélecteur. | WP | 1re connexion du poste : réseau ; ensuite PIN | Un compte `animalier` ne voit pas `/comptabilite` (redirection) ; test RBAC par rôle | F1, I1 | C |
| PR-002 | Après 5 échecs consécutifs l'accès est bloqué 15 min avec bannière ; aucun toast au 5e échec. | WP | local | Au 5e échec : bouton désactivé, bannière « Trop de tentatives de connexion. Accès bloqué pendant 15min. », compte à rebours | F1 | C |
| PR-003 | « Se souvenir de moi » mémorise l'identifiant seul, jamais la session. | WP | oui | Relancer l'application : champ identifiant prérempli, session fermée | F1 | C |
| PR-004 | L'admin réinitialise le mot de passe d'un utilisateur (temporaire, changement forcé avant toute page). | W | non | Connexion suivante : écran de changement obligatoire avant l'accueil | guide bloc 2 | P |
| PR-005 | Je change mon mot de passe depuis Mon Profil (ancien requis, nouveau ≠ ancien, confirmation). | WP | réseau requis | refus si nouveau = ancien | F9 | C |
| PR-006 | Le poste se verrouille par PIN local au lancement et après inactivité. | P | oui | Rouvrir sans réseau avec le PIN | guide D-SRV-5 ; `docs/prd/verrou-web.md` | P |
| PR-007 | L'admin gère les utilisateurs (créer, modifier, archiver, réactiver) ; le dernier admin ne peut s'archiver. | W | non | archive = `is_active=false`, jamais DELETE | F8 onglet 3 ; guide bloc 2 | C/P |

### 4.2 Élevage

| ID | Exigence | Surf. | HL | Critère | Source | St. |
|---|---|---|---|---|---|---|
| PR-010 | L'animalier saisit la fiche du jour d'une filière (achats, nés, morts et dons par catégorie) et lit l'effectif CALCULÉ, jamais saisi. | WP | oui | cas de `15_REGLES_METIER.md` RM-ELV-01 | B6 BR-ELV-007 | C |
| PR-011 | Le tableau du mois (31 jours) charge le jour au clic, sans changer d'écran ; vue hebdomadaire disponible. | WP | oui | semaines calculées sur la longueur réelle du mois (28/29/30/31) ; somme 4 semaines = total du mois | F3 « Vue Hebdomadaire » | C |
| PR-012 | Les ventes de la fiche viennent de la caisse (champ « Ventes (POS) » en lecture seule). | WP | oui | une vente de 3 Goliathau fait +3 sur la fiche du jour | B4 FRS-ELV-10 | C |
| PR-013 | Pondeuses : suivi du stock d'œufs (SRH, TS, Stock final) ; SRH(J+1) = Stock final(J). | WP | oui | cas RM-ELV-08 | B6 BR-ELV-008 | C |
| PR-014 | Rationnement : provende du jour = Σ effectif × ration par catégorie ; barème éditable. | WP | oui | cas RM-ELV-09 | B6 BR-ELV-009 | C |
| PR-015 | Départ par catégorie obligatoire, une fois par bande (à l'ouverture de la fiche). | WP | oui | message de refus exact du guide bloc 1 | guide bloc 1 | P (Q-ELV-5) |
| PR-016 | Gestion des bandes : créer, modifier, archiver, restaurer ; transferts entre bandes ; sujets ; transformation (abattage) ; dons ventilés. | WP | oui | messages exacts du guide bloc 12 | guide bloc 12 | P |
| PR-017 | Couvoir en continu : machines, lots multi-âges, mirages J+7/J+14, éclosion, remplacement automatique, TER, statistiques. | WP | oui | cas RM-COU-01 à 04 | F3 | C |
| PR-018 | Calendrier de soins (3 onglets), infirmerie, décès reporté sur la fiche avec choix de catégorie. | WP | oui | décès : bouton « Confirmer » inactif tant qu'aucune catégorie n'est choisie | F3 | C |
| PR-019 | Prophylaxie datée par bande (mise en bande, jour de cycle) et fenêtre « Rappels du jour » une fois par session. | WP | oui | jamais de fenêtre vide ; jamais au déverrouillage | guide bloc 6 | P |
| PR-020 | Paramètres Élevage : rationnement, calendriers de prophylaxie, types de provende (lecture seule), numérotation (préfixes Enclos/Cage/Bande/Bassin). | WP | oui | préfixe vide refusé | F3 | C |
| PR-021 | Pisciculture : fiche, bassins, biomasse, aliment, vente. | WP | oui | **À DÉFINIR** : `15_REGLES_METIER.md` §7.1, questions Q-PIS-1 à Q-PIS-9 | configuration_espece.dart | D |
| PR-022 | Pintades : fiche et rationnement propres. | WP | oui | **À DÉFINIR** §7.2, Q-PIN-1 à Q-PIN-4 | idem | D |
| PR-023 | Goliaths : maturité 4 mois / 2,8 kg, vente déduite de « Goliathau ». | WP | oui | test dédié (vente ne touche pas Mature) | F3 | C (Q-GOL-1) |

### 4.3 Ventes, clients, facturation

| ID | Exigence | Surf. | HL | Critère | Source | St. |
|---|---|---|---|---|---|---|
| PR-030 | Le caissier encaisse en < 60 s : grille produits, panier, remise, Espèces / Mobile Money / Avance. | WP | oui | validation = 1 transaction atomique (vente + lignes + stock + fiche) | B4 FRS-VTE-03 | C |
| PR-031 | Une ligne ne dépasse pas le stock : « Stock insuffisant (X disponible). » | WP | oui | produit à stock 2, 3e unité refusée | B4 FRS-VTE-02 | C |
| PR-032 | Annuler une vente (motif obligatoire) restitue le stock et défait la fiche ; elle apparaît dans « Retours et Avoirs ». | WP | oui | stock + fiche rétablis | B4 FRS-VTE-05 | C |
| PR-033 | Devis : générer, suivre (brouillon, envoyé, accepté, refusé), archiver. | WP | oui | numéro DEV-AAAA-NNN attribué par le serveur | `docs/prd/devis-poste.md` | P |
| PR-034 | Clients et créances : clients, créances avec ancienneté, événements CRM (anniversaires), « Marquer contacté ». | WP | oui | solde recalculé à chaque lecture, jamais stocké | F4 | C |
| PR-035 | Facture : simple (jamais transmise) ou normalisée (IFU, nom, AIB) ; avoir pour corriger une normalisée. | WP | oui | une normalisée n'est plus modifiable ni annulable | guide bloc 19 | P |
| PR-036 | Lettre de relance / « Rappel de Solde » PDF selon présence d'une échéance. | W (P PDF) | oui | sans échéance : titre « Rappel de Solde » | F4, F7 | C |

### 4.4 Stocks, achats, comptabilité, rapports, administration

| ID | Exigence | Surf. | HL | Critère | Source | St. |
|---|---|---|---|---|---|---|
| PR-040 | Stocks d'intrants avec journal des mouvements, ajustement d'inventaire tracé, seuil critique. | WP | oui | écart journalisé signé | F5 | C |
| PR-041 | Fabrication de provende atomique avec référence FAB-AAAA-NNNN. | WP | oui | un intrant en dépassement bloque toute la fabrication | F5 | C |
| PR-042 | Achats : commande, réception (stock + PMP), dettes fournisseurs. | WP | oui | PMP = (stock×PMP + qté×prix)/(stock+qté) | F5 | C |
| PR-043 | Catalogue produits vendables (SKU, coût de revient, seuils) archivé, jamais supprimé s'il est vendu. | WP | oui | coût > tarif refusé | F4 | C |
| PR-044 | Dépenses multi-lignes avec écriture unique. | WP | oui | total = Σ lignes | `docs/prd/depenses-multilignes.md` | P |
| PR-050 | Comptabilité : Journal, Grand Livre (solde progressif), Balance (écart 0), Bilan, Compte de résultat, TAFIRE, Notes annexes. | W | lecture | Σ débits = Σ crédits | F6 | C |
| PR-051 | Exercices : sélecteur dans la barre du haut, N / N+1 / lecture seule, clôture mensuelle et annuelle gardées. | WP | demandes | refus d'écriture dans un exercice clos | `docs/prd/exercices-comptables.md` | P |
| PR-052 | Rapports : 6 onglets, export PDF de l'onglet actif, export xlsx. | WP | oui | KPI identiques à la comptabilité | F7 | C |
| PR-053 | Import en masse par xlsx (modèle à télécharger), aperçu, rapport d'erreurs, annulation. | WP | À CONCEVOIR | **D** : `28_` ; Q-IMP-1 | guide bloc 21 | D |
| PR-060 | Modules actifs, données de l'entreprise (IFU, RCCM), logo/favicon, SMTP, MeCeF, modes de paiement. | W | non | MeCeF refusé sans IFU et RCCM | F8 | C |
| PR-061 | Sauvegarde, restauration différée avec 4 contrôles, corbeille, remise à zéro (double verrou). | W (P local) | oui | restauration : base précédente conservée | F8 | C |
| PR-062 | Barre du haut : sélecteur d'exercice, cloche, recherche globale (Ctrl+K), modale de synchronisation. | WP | oui | aucun résultat de recherche vers un écran interdit | F2 ; guide bloc 17 | P |
| PR-063 | PWA installable avec service worker étroit (statique seulement). | W | page d'attente | aucun HTML authentifié en cache | `agrierp_laravel/public/sw.js` | P (D pour le hors ligne) |

## 5. Phasage recommandé

Reprise de B2 §7 (Fondations → Élevage → Commercial → Comptabilité → Transversal) **réordonnée** par la décision du 07/11/2026 (guide §1) : **socle serveur + UUID → appairage → synchronisation → modale de synchronisation → fiches/stocks/alertes → import en masse → MeCeF → comptabilité et exercices → build → PWA hors ligne seulement si confirmée**. Détail jalon par jalon : `20_MODULES_INDEX.md` §6 et guide 14.3 (W0 à W9).

## 6. Métriques de succès (reprise B2 §6, étendue)

| Métrique | Cible | Mesure |
|---|---|---|
| Saisie d'une fiche complète | < 3 min | chronométrage en recette |
| Transaction POS simple | < 60 s | idem |
| Écarts web/poste sur les calculs | 0 | parité exécutée (`31_TESTING_QA.md`) |
| Ventes perdues à la synchronisation | 0 | essai multipostes automatisé |
| Registres papier parallèles | 0 | audit à J+30 |

## 7. Hors périmètre (reprise B1 §6, mise à jour)

Passerelle Mobile Money réelle ; application mobile native ; paie (sauf décision, BR-033) ; PWA hors ligne (sauf décision, BR-025) ; SMS (AgriERP les a supprimés, AUT-3).

## 8. Risques produit

| Risque | Parade |
|---|---|
| Règles dupliquées web/poste qui divergent | un point de passage serveur par règle ; parité exécutée contre le vrai PHP |
| Migration UUID des bases existantes | sauvegarde auto avant, test sur vraie ancienne base (guide D-SRV-3) |
| Filières sans règle (pisciculture, pintades) codées « à la louche » | marqueur À DÉFINIR, aucune formule inventée ; filière neutre générique tant que non tranchée |
| Perte de saisies hors ligne navigateur | ne pas construire sans besoin explicite (guide bloc 20) |

## 9. Questions ouvertes

Voir `10_BRS_BUSINESS_REQUIREMENTS.md` §6 (liste maître). Aucune question n'est propre au PRD.
