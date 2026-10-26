# PRD — « Rappels du jour » : la fenêtre qui s'ouvre avec l'application (version courte)
**Statut :** brouillon (livré par les tickets POP1 à POP4) · **Date :** 2026-10-26 · **Ticket(s) :** POP1 à POP4 (`docs/PLAN_FINALISATION.md`, Sprint POP)

> Demande du client : « Quand on ouvre chaque fois le poste ou le web, la notification popup doit se déclencher pour afficher les rappels VMS, soins et vaccinations. » **Le web est le maître** (Doctrine, articles 0 et 5) : la fenêtre se construit d'abord au web, le poste la reprend à l'identique.

## 1. Problème
Les rappels existent, mais il faut aller les chercher : la cloche (alertes R-SOINS-01 émises par la tâche du matin), le bloc « Rappels VMS à venir » du Dashboard Élevage, l'onglet Soins et vaccins. Exemple : la bande LAP-A a un vaccin planifié le 20/10, en retard de 6 jours ; la bande POR-B a la vermifugation du barème dans 2 jours ; l'animalier ouvre le poste, va aux fiches du jour, et ne voit rien.

## 2. Existant
| Surface | Ce qui existe | Fichier |
|---|---|---|
| Web | Règle écrite **R-SOINS-01** (soins planifiés : « à venir » dès N jours, « en retard » après la date, N = `company_settings.rappel_soins_jours`, 0 à 30, 3 par défaut) ; la cloche reçoit une notification par soin et par jour | `AlertesElevageService` (`soinsAVenir`, `joursRappelSoins`) |
| Web | Rappels du barème prophylactique (traitements dus, non encore administrés) et rémanences en cours, 7 jours, dans le Dashboard Élevage | `DashboardElevage::getRappelsVmsProperty`, `ProtocoleDuJourService` |
| Poste | Les mêmes calculs en local : `DashboardElevageRepository._rappels`, `SoinsRepository.protocoleDuJour`, `ParametresElevageRepository` (délai servi au tirage, H9/H9b), tables `veterinary_calendar_events`, `veterinary_withdrawal_periods` (H8b) | — |
| Les deux | **Aucune fenêtre à l'ouverture.** Le poste a un verrou local (PIN, VL-1/VL-2) dont la porte `PorteSession` ouvre l'application. | `PorteSession` |

## 3. Utilisateurs et rôles
Seuls les rôles qui voient Soins et vaccins reçoivent la fenêtre : permission **`view-elevage`** (admin, animalier, et tout rôle qui la porte ; **pas le caissier**). Web : `can('view-elevage')` ; poste : `PermissionsPoste.peut(role, 'view-elevage')`. Le serveur / le calcul revérifie le droit : la fenêtre n'est jamais « cachée » seulement par l'interface.

## 4. Exigences fonctionnelles
- **EF1** À l'ouverture, une modale « Rappels du jour » liste les rappels par urgence : **En retard**, **Aujourd'hui**, **À venir** (sous N jours). Colonnes : Bande / sujet (`CODE (Espèce)`) · Rappel · Produit · Date prévue · Échéance. Pied : lien « Ouvrir Soins et vaccins », boutons « Plus tard » (ferme) et « Ne plus afficher aujourd'hui ».
- **EF2** **Rien à afficher ⇒ aucune fenêtre** (jamais une fenêtre vide).
- **EF3 Quand.** Web : à l'ouverture de session (connexion) ET au premier chargement d'une page de la session du navigateur, **une seule fois par session de navigateur** (pas à chaque changement de page). Poste : à chaque **lancement** (après le PIN) et à chaque **connexion** ; **pas** à chaque déverrouillage (manuel ou par inactivité).
- **EF4** « Ne plus afficher aujourd'hui » : par utilisateur, pour la date du jour seulement (le lendemain, la fenêtre revient). Stocké localement : `localStorage` au web, coffre du système au poste. Il l'emporte sur la connexion.
- **EF5** Une espèce désactivée (Modules Actifs) ne génère aucun rappel. Une bande qui n'est plus vivante non plus.
- **EF6** Une erreur de calcul est silencieuse côté fenêtre (journalisée), ne bloque ni le démarrage ni la synchronisation, jamais d'écran rouge.
- **EF7** Même résultat au web et au poste pour les mêmes données (parité exécutée contre le PHP du serveur).

## 5. Règles métier (R-RAPPELS-01, rédigée le 26/10/2026)
Horizon **N** = délai de rappel des soins déjà réglé (Paramètres Élevage, `rappel_soins_jours`, 0 à 30, 3 par défaut ; poste : valeur servie au tirage, 3 si jamais tirée). Aujourd'hui = date du Bénin. Trois sources, aucun seuil nouveau :
1. **Soin planifié** (calendrier vétérinaire, `status = planned`, bande vivante) : la fenêtre de R-SOINS-01 telle quelle — date dépassée = **En retard**, date du jour = **Aujourd'hui**, date ≤ aujourd'hui + N = **À venir**.
2. **Traitement du barème prophylactique** dû et **non encore administré** (moteur unique `ProtocoleDuJourService` / `protocoleDuJour`), pour chacun des jours J à J+N, bande vivante : **Aujourd'hui** (J) ou **À venir**. Un traitement du barème raté n'a pas d'« en retard » (le jour de cycle est passé, la règle ne le rattrape pas ; c'est la règle déjà en place au Dashboard).
3. **Fin de délai d'attente (rémanence)** : une interdiction de vente qui prend fin entre aujourd'hui et aujourd'hui + N : **Aujourd'hui** (finit ce jour) ou **À venir**.
Tri : urgence (retard, aujourd'hui, à venir), puis date prévue croissante, puis code de bande, puis type (soin, prophylaxie, délai d'attente), puis libellé.
Jeu d'exemple (aujourd'hui = 14/10/2026, N = 3), calculé à la main : soin « Vaccin Newcastle » LAP-A le 12/10 → En retard, « 2 jours de retard » ; soin « Déparasitage » LAP-A le 14/10 → Aujourd'hui ; soin « Vitamines » LAP-A le 17/10 → À venir « Dans 3 jours » ; soin le 18/10 → absent (4 jours > N) ; soin annulé → absent ; bande clôturée ou espèce désactivée → absent. Ordre : Vaccin, Déparasitage, Vitamines.

## 6. Hors ligne et synchronisation
Aucune table nouvelle, **aucune migration Drift** (le palier réservé 62 n'est pas consommé) : le poste calcule en local à partir des tables déjà synchronisées. Aucune donnée n'est écrite. Le masquage du jour est une préférence locale, jamais synchronisée.

## 7. Interface
Web : composant Livewire `Shared\RappelsDuJour` monté dans la mise en page, modale du gabarit existant. Poste : `ModaleAgri` / fenêtre du même titre, mêmes libellés (lus dans le Blade par le garde-fou).

## 8. Hors périmètre
Notifications du système d'exploitation (hors application), e-mail, son. Stock sous seuil et mortalité (alertes de la cloche, pas des rappels de soin).

## 9. Questions ouvertes pour le client
- **POP-Q1** Les entrées d'**infirmerie** (`infirmary_records`) n'ont **aucune date prévue** : aucune règle écrite n'en fait un rappel. Elles n'entrent donc pas dans la fenêtre ; les soins qu'on y planifie (calendrier) y entrent. Faut-il rappeler aussi « sujets encore à l'infirmerie depuis N jours » ? (recommandé : non tant que la règle n'est pas écrite).
- **POP-Q2** Il n'existe pas de « vaccin à renouveler » distinct : le renouvellement est porté par le barème prophylactique (source 2). Confirmer.
- **POP-Q3** Réafficher la fenêtre à chaque déverrouillage du poste ? (recommandé : non, seulement lancement et connexion).
- **POP-Q4** Une rémanence qui finit hors de l'horizon N n'est pas listée (le Dashboard liste toutes les rémanences en cours). Confirmer.
- **POP-Q5** La cloche (`AlertesElevageService::soinsAVenir`) ne filtre pas les espèces désactivées, la fenêtre si. Aligner la cloche ? (recommandé : oui).

## 10. Critères d'acceptation
Tests nommés : `agrierp_laravel/tests/Feature/RappelsDuJourTest.php` (règle, tri, droits, module désactivé, fenêtre vide, une fois par session, masquage du jour, connexion), `agrierp_flutter/test/rappels_du_jour_test.dart` (calcul local, modale, porte de session, masquage), `rappels_du_jour_parite_php_test.dart` (même résultat que le serveur), `rappels_du_jour_blade_test.dart` (libellés). Épreuve de mutation : retirer un contrôle de droit, la borne « > N », le filtre de module, le tri, le test « liste vide » ou la comparaison de date du masquage doit faire rougir au moins un test.
