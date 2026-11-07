# 43 — Appairage, synchronisation, modale de synchronisation, alertes, rappels, rationnement et prophylaxie automatiques

> **USAGE**
>
> - **Quand l'utiliser.** Pendant la construction du lien web ↔ poste de LogiALVIA : le jour où le client a décidé « on va créer le web » et où le poste Flutter existant doit se rattacher au serveur. Ce fichier est la version « PROMPT » détaillée des blocs 15 à 18 du guide (`GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md`), plus la construction des automatismes (alertes, rappels, rationnement, prophylaxie).
> - **Ordre (strict).** 1) Socle web et tables UUID (`02_ARCHITECTURE_WEB_ET_STACK.md`, `30_DATABASE.md`) → 2) **Section 1 : appairage** → 3) **Section 2 : synchronisation, étapes S0 à S5** → 4) **Section 3 : modale de synchronisation** (web d'abord) → 5) **Section 4 : alertes et rappels** (serveur planifié, puis poste) → 6) **Sections 5 et 6 : rationnement et prophylaxie** (règles dans `15_REGLES_METIER.md`). Ne pas inverser : une alerte, une modale ou un tirage sans appairage ne se testent pas.
> - **Entrées requises.** Le web de LogiALVIA (Laravel 12 + Livewire 3) ; le poste `logialvia_app/` ; `docs/BLUEPRINT_SYNCHRONISATION_MULTIPOSTES.md` d'AgriERP lu **en entier** ; les règles métier de LogiALVIA (`15_REGLES_METIER.md`, `logialvia/docs/B6_Regles_Metier.md`).
> - **Sorties.** Appairage révocable ; moteur de synchronisation prouvé par l'essai multipostes ; bouton et modale « Synchroniser » (web + poste) ; notifications serveur planifiées + cloche du poste copiée du serveur ; fenêtre « Rappels du jour » ; rationnement et prophylaxie branchés sur des règles uniques.
> - **Ce fichier ne recopie pas le blueprint** : il le résume, y renvoie, et ajoute les étapes de construction avec critères. En cas de doute, **le blueprint et le code d'AgriERP font foi**.
> - **Voir aussi.** `15_REGLES_METIER.md`, `20_MODULES_*`, `40_PWA_HORS_LIGNE.md` (un « poste navigateur » est un poste de plus), `41_MECEF_EMECEF.md` (transmission au serveur), `42_CONFIG_MECEF_SMTP_LOGO_FAVICON.md`, `31_TESTING_QA.md`.

### Cadre commun à coller en tête de CHAQUE prompt (P0)

~~~~text
P0 — CADRE COMMUN
Tu travailles sur LogiALVIA (web Laravel 12 + Livewire 3 ; poste Flutter/Drift) avec les conventions de LogiAgriERP (monorepo /home/user/agrierp, LECTURE SEULE). Tout en français (prose, libellés, commentaires, noms de tests, messages de commit). Avant d'écrire : le CLAUDE.md du projet où tu travailles ; /home/user/agrierp/docs/DOCTRINE_PORTAGE.md ; /home/user/agrierp/docs/BLUEPRINT_SYNCHRONISATION_MULTIPOSTES.md (en entier) ; la section traitée de /home/user/agrierp/docs/logialvia/43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md. Règles : (1) le serveur est la vérité ; le poste écrit un FAIT ou une DEMANDE que le serveur rejoue par le MÊME code que l'écran web (un point de passage unique par règle) ; (2) la vue web est le maître, le poste lui est fidèle, prouvé par un test qui LIT la vue ; (3) jamais d'échec silencieux ; hors ligne n'est pas une erreur ; (4) aucun secret en clair ; (5) schéma partagé : migration serveur ET Drift (app_database.dart puis `dart run build_runner build`, jamais d'édition du fichier généré) ; clés primaires UUID ; (6) tu n'inventes aucune règle métier : tu la lis dans 15_REGLES_METIER.md ou tu demandes ; (7) tu ne commites ni ne pousses sans demande expresse ; JAMAIS de pkill ; (8) chaque tâche finit vert (tests) avant la suivante, et tu dis ce que tu n'as PAS pu vérifier.
~~~~

---

## 1. Appairage web ↔ poste

### 1.1 Spécification (résumé ; référence : blueprint §2 et §8 ; guide bloc 15 — rien n'est recopié, tout est relu dans le code)

| Sujet | Règle | Source réelle |
|---|---|---|
| Appairage = connexion | `POST /api/auth/login {identifiant, password, device_name}` ; limiteur 5/minute ; nom d'utilisateur court OU e-mail (colonne `email` si « @ » présent, sinon `username`) ; compte inactif refusé : « Ce compte a été désactivé. Contactez un administrateur. » ; échec : « Identifiants incorrects. » (audit `login.failed`) | `agrierp_laravel/app/Http/Controllers/Api/AuthController.php`, `routes/api.php` |
| Un jeton par poste | `device_name` = **identifiant du poste (UUID)**, pas le nom de la machine ; se reconnecter **supprime l'ancien jeton du même nom** ; durée 90 jours (`SANCTUM_EXPIRATION`) | `AuthController::login`, `agrierp_laravel/config/sanctum.php` |
| Le jeton dit qui parle | le `device_id` envoyé au push doit être le **nom du jeton courant**, sinon 403 (ticket S-T2) ; un poste ne signe pas au nom d'un autre | `SyncController::refusPosteDifferentDuJeton`, test `agrierp_laravel/tests/Feature/SyncPosteJetonTest.php` |
| Identifiant du poste | UUID tiré **UNE fois** à la première ouverture, gardé en base locale, jamais régénéré (clé `poste.identifiant`) ; une réinstallation = un NOUVEAU poste, l'ancien jeton se révoque au web | `agrierp_flutter/lib/core/config/parametres_poste.dart` |
| Adresse du serveur | réglage du poste, **normalisée** (schéma ajouté, `/` final retiré, sinon `//api/sync/pull`), modifiable dans Paramètres › Appairage, effective au redémarrage (et le dit) | `agrierp_flutter/lib/core/config/environnement.dart`, `appairage_poste.dart` |
| Jeton au coffre, mot de passe nulle part | `flutter_secure_storage` ; le mot de passe n'est jamais conservé ni journalisé | `agrierp_flutter/lib/core/auth/auth_service.dart` |
| PIN local | 4 à 6 chiffres, PBKDF2, sel au coffre, 10 échecs = reconnexion en ligne exigée ; il rouvre une session déjà ouverte SANS réseau et ne remplace pas le mot de passe ; ordre à l'ouverture : connexion → changement de mot de passe forcé → PIN → application | `agrierp_flutter/lib/core/auth/verrou_local.dart`, `agrierp_flutter/lib/features/verrou/porte_session.dart`, `docs/DOCTRINE_PORTAGE.md` §5.6 |
| Révocation | l'administrateur (`manage-users`) supprime **tous** les jetons du poste nommé (tous comptes) : onglet web « Postes & Appairage » (`PostesAppairage`, audit `sync.appairage_revoque`) ou `POST /api/parametres/postes/revoquer` ; le poste nommé doit figurer dans la liste (un nom forgé ne supprime rien) ; le poste reçoit **401** | `agrierp_laravel/app/Livewire/Parametres/PostesAppairage.php`, `AdministrationEnLigneController.php` |
| 401/403 | la synchronisation automatique **s'ARRÊTE** (`suspendue`) jusqu'à une nouvelle connexion ; les saisies `pending` RESTENT ; « Synchroniser maintenant » reste possible et dit pourquoi ; l'onglet Appairage montre l'état du jeton (Présent / Session refusée / Absent / « — » si le coffre est illisible : jamais une affirmation) et propose « Réappairer » | `agrierp_flutter/lib/core/sync/synchronisation_automatique.dart`, `onglet_appairage.dart` |
| Mot de passe temporaire / compte désactivé | 403 avec motif français sur tout sauf le changement de mot de passe | `CompteActif`, `ChangementMotDePasseObligatoireApi` |
| Pas d'appairage « au nom de l'administrateur » | refusé (D-SYNC-5) : le jeton est par utilisateur ET par poste, droits contrôlés table par table | `docs/prd/synchronisation-barre-superieure.md` §9 |

Libellés de l'onglet « Appairage » du poste (relus) : « Adresse du serveur », « Tester la connexion » (`GET /api/auth/me`), « Réappairer » (modale « Réappairer ce poste »).

### 1.2 PROMPT — Appairage (serveur, puis web, puis poste)

~~~~text
[Colle P0 ici.]

OBJECTIF : rattacher chaque poste Windows de LogiALVIA au serveur de façon TRAÇABLE et RÉVOCABLE : un jeton par poste, nommé d'après le poste ; PIN local ; 401/403 → suspension ; l'administrateur voit les postes et peut en couper un. Spécification : 1.1 de /home/user/agrierp/docs/logialvia/43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md.

PRÉREQUIS : le web de LogiALVIA tourne avec Sanctum et un rôle administrateur (droit équivalent à manage-users) ; une table des utilisateurs avec `is_active` ; le poste a `dio`, `uuid`, `connectivity_plus`, `flutter_secure_storage` (versions d'AgriERP : /home/user/agrierp/agrierp_flutter/pubspec.yaml). État actuel de logialvia : authentification LOCALE (logialvia_app/lib/administration/domain/usecases/connecter_utilisateur_usecase.dart, hachage_mot_de_passe.dart SHA-256 + sel), aucun réseau.

RÉFÉRENCES (lecture seule) : /home/user/agrierp/agrierp_laravel/app/Http/Controllers/Api/AuthController.php, app/Http/Middleware/CompteActif.php, ChangementMotDePasseObligatoireApi.php, app/Http/Controllers/Api/AdministrationEnLigneController.php, app/Livewire/Parametres/PostesAppairage.php, config/sanctum.php, routes/api.php ; /home/user/agrierp/agrierp_flutter/lib/core/auth/auth_service.dart, verrou_local.dart, lib/core/config/parametres_poste.dart, environnement.dart, lib/features/parametres/appairage_poste.dart, onglet_appairage.dart, lib/features/verrou/porte_session.dart, lib/features/auth/login_screen.dart ; tests : tests/Feature/SyncPosteJetonTest.php, SyncPullDroitsEtCompteActifTest.php, SupervisionSynchronisationTest.php, ReinitialisationMotDePasseAdminTest.php ; flutter : test/verrou_local_test.dart, echec_synchronisation_test.dart, synchronisation_automatique_test.dart, migration_bases_reelles_test.dart.

TÂCHES
A1 (serveur) — POST /api/auth/login (limiteur 5/min), mêmes messages ; un jeton par nom d'appareil (le même appareil supprime l'ancien) ; réponse {token, user, must_change_password} ; audit `api.login` et `login.failed` ; middlewares CompteActif et ChangementMotDePasseObligatoireApi sur tout le reste de l'API ; mots de passe temporaires (guide bloc 2). Le jeton expire à 90 jours (variable d'environnement).
A2 (serveur) — refus du push dont le device_id n'est pas le nom du jeton courant (403, rien écrit, rien journalisé).
A3 (web) — onglet « Postes & Appairage » : liste des postes (jetons non expirés : nom du poste, utilisateur, dernier contact), bouton « Révoquer l'appairage » (modale de confirmation par événement) qui supprime TOUS les jetons du poste nommé ; refus d'un nom absent de la liste ; audit `sync.appairage_revoque` ; réservé à l'administrateur à l'ouverture (abort_unless) et à chaque action.
A4 (poste) — identifiant de poste UUID tiré une fois, gardé en base locale ; adresse du serveur normalisée ; AuthService (login par dio, jeton ET profil au coffre, mot de passe jamais conservé ni journalisé, reprise de session SANS réseau qui ne revalide pas le jeton) ; première connexion EN LIGNE obligatoire avec message clair hors ligne.
A5 (poste) — PIN local (PBKDF2, sel au coffre, temporisation dès le 5e échec, 10 échecs = reconnexion en ligne) ; routeur : connexion → changement forcé → PIN → application, dans cet ordre.
A6 (poste) — remplace ConnecterUtilisateurUseCase : plus de vérification locale du mot de passe ; l'ancien hash est abandonné après migration des comptes (migration de données prouvée par un test sur une base de départ).
A7 (poste) — onglet « Appairage » : identifiant du poste, adresse (« effective au redémarrage », dit), état du jeton (Présent / Session refusée / Absent / « — »), « Tester la connexion » (GET /api/auth/me), « Réappairer » (déconnexion propre puis écran de connexion, modale).
A8 (poste) — 401/403 du serveur : la synchronisation automatique est SUSPENDUE ; `pending` conservé ; « Synchroniser maintenant » possible et explique ; reprise après réappairage.

CONTRAINTES : mot de passe jamais stocké au poste ; jeton uniquement au coffre ; jamais d'appairage unique au nom de l'administrateur ; aucun aller-retour serveur obligatoire au démarrage (l'application doit s'ouvrir les jours de coupure) ; réessais infinis après 401 interdits ; durée de vie du jeton lue de la configuration, jamais en dur.
INTERDITS : constante partagée comme identifiant de poste ; Hash::check sur un mot de passe temporaire sans le refus 403 du reste de l'API ; adresse du serveur non normalisée ; recopier le contrôleur d'AgriERP sans adapter les rôles (3 rôles de LogiALVIA, pas ceux d'AgriERP).

CRITÈRES D'ACCEPTATION (chacun a un test)
1. Deux postes, deux jetons : le jeton de l'un ne peut pas signer au nom de l'autre (403).
2. Reconnexion du même poste : l'ancien jeton meurt, un seul jeton actif par nom.
3. Révocation au web : le poste reçoit 401 au tirage suivant, la synchronisation automatique est suspendue, les saisies `pending` sont intactes ; après réappairage la synchronisation reprend et envoie les `pending`.
4. Compte désactivé : 403 avec motif en français à tout sauf au changement de mot de passe ; mot de passe temporaire : changement forcé AVANT le PIN ; jetons détruits à la réinitialisation par l'administrateur.
5. Première connexion hors ligne : message clair, rien d'écrit.
6. Le coffre illisible : l'état du jeton affiche « — », jamais une affirmation fausse.
7. Limiteur : 6e tentative en une minute refusée.
8. Un nom de poste forgé dans la requête de révocation ne supprime rien.
9. Audit présent (`api.login`, `login.failed`, `sync.appairage_revoque`).
10. Suites verte côté serveur et côté poste (`flutter analyze`, `flutter test`).

PIÈGES PAYÉS (par AgriERP) : identifiant de poste partagé (deux postes indiscernables, révocation impossible) ; Hash::check d'un mot de passe temporaire sans le 403 du reste de l'API (le compte contourne le changement forcé) ; aller-retour serveur au démarrage (application inutilisable les jours de coupure) ; réessais infinis après 401 (chaque tentative = un refus de plus au journal) ; adresse non normalisée (panne déroutante).
~~~~

### 1.3 Questions au client
Durée de vie du jeton (90 jours) ? Un poste par utilisateur, ou plusieurs utilisateurs sur un poste (AgriERP : jeton par utilisateur ET par poste) ? Qui révoque (administrateur seul) ? Un poste neuf peut-il s'amorcer hors ligne (non : première connexion en ligne) ?

---

## 2. Synchronisation envoi / réception

### 2.1 Résumé opérationnel (le blueprint est la référence, rien n'est recopié)

Lire `docs/BLUEPRINT_SYNCHRONISATION_MULTIPOSTES.md` d'AgriERP, dont les sections : §1 architecture, §2 identité (appairage), §3 envoyer/recevoir, §4 une règle de conflit par nature de donnée, §5 « Renvoyer vers tous les postes », §6 remise à zéro, §7 installation/mise à jour/désinstallation, §8 sécurité, §9 checklist d'un nouveau projet, §10 pièges déjà payés.

Points durs à retenir (vérifiés dans `agrierp_laravel/app/Http/Controllers/Api/SyncController.php` et `routes/api.php`) :
- **Pull puis push**, jamais deux synchronisations en même temps. `GET /api/sync/pull?since=…&page=…&curseur_page=…` (limite 120/min) ; `POST /api/sync/push` (limite 30/min).
- **Curseur = `server_time` rendu par le SERVEUR** (début de la page 1 reculé d'un horizon), n'avance qu'à la **dernière page** ; tables d'historique découpées PAR PIÈCE (une pièce descend avec toutes ses lignes) ; tables servies en entier = remplacement complet ; `tables_servies` nommées à chaque page : si une table s'ajoute (changement de droit/rôle), le poste repart SANS `since`.
- **Droit de lecture par table** : `SyncController::PERMISSIONS_DE_TIRAGE` (seules les tables que le compte lit sont servies).
- **Absorbeurs stricts** : une ligne incohérente est REFUSÉE, jamais lissée ; une page absorbée en UNE transaction locale ; une table mixte n'écrase jamais un `pending`/`conflict`.
- **Push idempotent par UUID du poste**, toute la requête dans UNE transaction serveur (rejouée 3 fois sur interblocage), réponse table par table (acceptés, refusés avec motif français) ; clé qui n'est pas une liste → ignorée et signalée dans `cles_invalides` ; `synced` **seulement après l'accusé** ; refus → `conflict` avec motif ; lots sous la limite du mandataire (413).
- **Règles de conflit par nature** : voir le tableau du guide bloc 16 (référentiels : le serveur gagne ; fiche : dernier écrivain par UUID ; vente : jamais fusionnée ; stock : rejoué par l'action unique ; comptabilité/clôtures/paie : DEMANDE jouée par le serveur ; numéros de pièces : attribués par le serveur).
- **Déclencheurs du poste** (`synchronisation_automatique.dart`) : ouverture, retour du réseau, toutes les 5 minutes (réglable), après un geste (agrégé sur 5 s), fermeture, demande ; réessais 30 s, 2 min, 5 min, 15 min, 1 h ; un refus 4xx n'est PAS réessayé ; 401/403 suspend.
- **Demande de synchronisation du web** : drapeau déposé par `DemandeSynchronisationService` (valable 60 minutes, `VALIDITE_MINUTES`), lu par chaque poste toutes les 30 s (`GET /api/sync/demande`, limite 6/min), servi une seule fois par poste.
- **Renvoi complet** (« Renvoyer vers ce poste », `ResynchronisationPostesService`) : le serveur mémorise le curseur rendu à chaque poste ; le drapeau reste levé JUSQU'À l'acquittement (`POST /api/sync/resynchronisation/acquittement`) ; le poste repart d'un tirage COMPLET puis acquitte.
- **Remise à zéro** : le serveur vide les données d'activité derrière trois verrous et pose `data_reset_at` ; chaque envoi porte la marque connue ; marque inconnue ⇒ **409** ; le poste purge ses tables d'activité au tirage suivant et compte ses saisies perdues.
- **Essai multipostes** : `agrierp_laravel/tests/Feature/SyncEssaiMultipostesTest.php` (côté serveur) et `agrierp_flutter/test/essai_multipostes_test.dart` lancé par `agrierp_flutter/outils/essai_multipostes.sh` (cinq postes réels, coupures aléatoires : requête perdue, réponse perdue après traitement, délai, 500, 413, puis réseau parfait jusqu'à ce que plus rien ne soit `pending` ; il écrit sur le serveur et se SAUTE sans `AGRIERP_ESSAI_URL`).
- **Journal serveur** `journal_synchronisation` (serveur seul) : une ligne par tirage et par envoi ; son échec ne fait jamais échouer la synchronisation ; curseur par poste dans `poste_synchronisations` (serveur seul).

### 2.2 PROMPT — Construire la synchronisation par étapes S0 à S5

~~~~text
[Colle P0 ici.]

OBJECTIF : chaque poste de LogiALVIA travaille hors ligne sur sa base locale et se met d'accord avec le serveur : il REÇOIT d'abord, il ENVOIE ensuite, sans doublon, sans perte silencieuse, sans conflit non arbitré. Tu construis par étapes, chacune avec ses critères ; tu ne passes à l'étape suivante que si la précédente est verte.

PRÉREQUIS : appairage fait (section 1) ; web de LogiALVIA avec les services « point de passage unique » des règles métier (une vente, une fiche, un mouvement de stock se créent par UNE action serveur appelée par l'écran web ET par la synchronisation).

LECTURE : le blueprint en entier (/home/user/agrierp/docs/BLUEPRINT_SYNCHRONISATION_MULTIPOSTES.md), SyncController.php (relis section par section : pull, absorption, push, traiterEnvoi, refusPosteDifferentDuJeton, instantDeReinitialisation), sync_engine.dart du poste (long : ne le recopie pas d'un bloc, relis-le par sections : tirer, absorber, envoyer, accuser, reprendre ; piège de compilation : promotion de nullité dans une fermeture), synchronisation_automatique.dart, perimetre_tirage.dart, fusion_referentiels.dart.

ÉTAPES
S0 — TABLES D'ABORD (aucune ligne de moteur avant). Dresse, dans docs/SYNC_TABLES.md, le tableau de CHAQUE table de LogiALVIA : synchronisable ou non ; règle de conflit (tableau du guide bloc 16) ; droit de lecture ; droit d'écriture ; dépendance d'envoi (ordre). Schéma serveur + Drift identiques ; UUID ; colonnes `id`, `device_id`, `sync_status`, `updated_at` (instant de SAISIE). Les numéros de pièces ne sont JAMAIS inventés au poste.
  Critères S0 : une table sans règle de conflit écrite n'est pas synchronisable ; un test (lecture du tableau) prouve que chaque table envoyée a un droit d'écriture et que chaque table tirée a un droit de lecture.
S1 — LE MOTEUR SUR UNE TABLE DE RÉFÉRENCE (ex. produits) : login (section 1), tirage paginé, absorbeur strict, envoi idempotent, accusé, statuts pending/synced/conflict, curseur serveur (jamais l'horloge du poste).
  Critères S1 (tests) : le même lot renvoyé deux fois ne crée rien de plus ; réponse perdue après traitement puis renvoi = succès silencieux ; deux postes sur la même ligne (le serveur gagne) ; 401 puis reconnexion ; curseur n'avance qu'à la dernière page ; un échec au milieu d'un tirage repart du curseur précédent.
S2 — LES DÉCLENCHEURS (SynchronisationAutomatique) et le compteur « à envoyer » dont la liste de tables est PROUVÉE ÉGALE à celle de l'envoi (modèle : agrierp_flutter/test/compteur_attente_test.dart).
  Critères S2 : déclenchement à l'ouverture, au retour du réseau, par minuterie, après un geste (agrégé), à la fermeture, sur demande ; réessais 30 s/2 min/5 min/15 min/1 h ; 4xx non réessayé ; 401/403 suspend ; le compteur égale la liste d'envoi (test qui compare les deux listes).
S3 — L'EXTENSION TABLE PAR TABLE, par ordre de dépendance, chacune avec sa règle de conflit et son test : référentiels → clients/fournisseurs → ventes et lignes (faits indépendants) → mouvements de stock (rejoués par l'action unique) → fiches d'élevage (dernier écrivain) → demandes (comptabilité, clôtures, paie). Un bloc de code par table sur le modèle du contrôleur. Table mixte : jamais d'écrasement d'un pending/conflict. Droits : lecture par PERMISSIONS_DE_TIRAGE-équivalent, écriture contrôlée table par table.
  Critères S3 : pour chaque table, un test serveur d'envoi (accepté, refusé avec motif français, idempotent) et un test poste d'absorption stricte (ligne incohérente refusée) ; une vente en rupture de stock reçue d'un poste est ACCEPTÉE et SIGNALÉE (recommandation d'AgriERP D-SYNC-4 ; décision client à confirmer) ; une pièce descend toujours avec toutes ses lignes.
S4 — LE WEB FAIT REVENIR LES DONNÉES VERS LES POSTES : demande de synchronisation (drapeau valable 60 min, lu toutes les 30 s), renvoi complet (curseur mémorisé par poste, acquittement), journal serveur et curseurs par poste.
  Critères S4 : drapeau servi UNE fois par poste ; renvoi complet lève un drapeau qui reste levé jusqu'à l'acquittement ; un poste au jeton expiré ne reçoit aucun drapeau (message d'erreur au web).
S5 — REMISE À ZÉRO, ESSAI À PLUSIEURS POSTES, MIGRATION DEPUIS VIEILLES BASES, DÉSINSTALLATION/RÉINSTALLATION : marque `data_reset_at` (409 si inconnue), purge au tirage suivant, compte des saisies perdues ; essai multipostes (cinq postes, coupures aléatoires) avec des invariants CHOISIS pour LogiALVIA depuis B6 (trésorerie, stock, dettes égaux partout) ; migration d'une base réelle du poste (fournie par le client ; sinon fabriquée ET dit fabriquée) ; même AppId = données intactes.
  Critères S5 : l'essai multipostes finit avec ZÉRO `pending` et les invariants égaux sur tous les postes ; un envoi d'avant la remise à zéro est refusé (409) ; une base réelle migre sans perte.

CONTRAINTES : curseur = server_time du serveur (UTC, jamais l'heure murale) ; marquer synced seulement après l'accusé ; verrous pris dans un ordre FIXE (le stock d'abord, toujours) ; une table d'envoi oubliée est un défaut grave (garde par comparaison de listes) ; jamais deux synchronisations simultanées ; aucun accès réseau dans un ViewModel (NEW:logialvia_app/lib/core/sync/…, dépôts dans data/repositories).
INTERDITS : « dernier écrivain gagne » global ; numéro de pièce inventé au poste ; un second protocole ; lisser une ligne incohérente ; ignorer en silence un refus.

PIÈGES PAYÉS (blueprint §10) : curseur à l'heure murale du serveur au lieu de l'UTC ; compteur incrémenté sans verrou (deux ventes comptées une) ; colonne ajoutée par un palier mais absente de la copie de table d'une migration ; UNE TABLE D'ENVOI OUBLIÉE dans la liste « à envoyer » (elle ne part jamais, sans erreur) ; synced marqué à l'envoi ; un référentiel mis à jour en bloc qui fait perdre une bascule non acquittée ; un envoi plus gros que la limite du mandataire (413) sur une journée indivisible ; verrous dans un ordre qui varie ; marque de remise à zéro non portée par un envoi.

RAPPORT FINAL : tables synchronisées (tableau), tests verts/rouges/sautés avec raison, essai multipostes (résultat réel), ce qui n'a pas été essayé.
~~~~

### 2.3 Tests à reprendre
Serveur (`agrierp_laravel/tests/Feature/`) : `SyncEssaiMultipostesTest`, `ResynchronisationPostesTest`, `ReinitialisationCompleteTest`, `SyncPosteAbsentTest`, `SyncTiragePagineTest`, `SyncCurseurFuseauTest`, `SyncFusionReferentielsTest`, `SyncVenteHorsLigneTest`, `SyncMouvementsStockTest`. Poste (`agrierp_flutter/test/`) : `essai_multipostes_test.dart`, `sync_engine_test.dart`, `synchronisation_automatique_test.dart`, `resynchronisation_serveur_test.dart`, `demande_synchronisation_test.dart`, `perimetre_tirage_test.dart`, `compteur_attente_test.dart`, `migration_bases_reelles_test.dart`.

### 2.4 Questions au client
Intervalle automatique (5 min) ? Seuil d'« inactivité » d'un poste au web (3 jours) ? Une vente en rupture de stock reçue d'un poste : accepter et signaler (recommandé) ou refuser ? Quels postes (nombre, lieux) et quelle qualité de réseau (taille des lots) ?

---

## 3. Modale de synchronisation dans la barre du haut (web ET poste)

### 3.1 Spécification (relue : `agrierp_laravel/app/Livewire/Shared/EtatSynchronisationPostes.php`, vue `resources/views/livewire/shared/etat-synchronisation-postes.blade.php`, `app/Services/JournalSynchronisationService.php`, `ResynchronisationPostesService.php`, `DemandeSynchronisationService.php`, `agrierp_flutter/lib/core/sync/modale_synchronisation.dart`, `lib/features/sync/synchronisation_screen.dart`, `lib/core/widgets/barre_superieure.dart`, PRD `docs/prd/synchronisation-barre-superieure.md` et `docs/prd/modal-synchronisation-reduit.md`)

**Même bouton, même titre, mêmes libellés des deux côtés ; seul le contenu propre à chaque surface diffère.**

| | Poste | Web |
|---|---|---|
| **Bouton** | entre la recherche globale et la cloche (le sélecteur d'exercice est à sa gauche), icône `sync` au gabarit de la cloche, badge plafonné à « 9+ » ; clés de test `bouton-synchroniser`, `bouton-synchroniser-badge` ; remplace l'ancienne pastille | `<livewire:shared.etat-synchronisation-postes />` dans `layouts/app.blade.php`, à droite du sélecteur d'exercice ; **visible pour `manage-users` seulement** (abort 403 sinon) |
| **Contenu** | liaison « En ligne » / « Hors ligne » (**hors ligne n'est pas une erreur rouge**) ; trois cartes : « En attente d'envoi », « Refusés par le serveur », « Dernière synchronisation réussie » (heure du **serveur**, « — » si jamais) ; « Dernière réception », « Dernier envoi » (« Jamais ») ; résultat de la dernière tentative de la session (reçus, acceptés, refusés, **tous** les motifs, avertissements) ; « Resynchronisation demandée par le serveur » entre la lecture du drapeau et son acquittement | « Postes de la ferme » ; un poste par ligne (jetons non expirés) : Poste, Utilisateur, Dernier contact, Dernier envoi, Acceptés / Refusés, État ; « Modifications du site depuis son dernier tirage : N » (détail par type) ; « Dernier tirage » |
| **États** | badge : nombre d'enregistrements à envoyer, **toutes tables envoyées comprises** ; rouge s'il existe au moins un refus, émeraude sinon, absent à 0 | pastilles du plus grave au moins grave : « Refus à corriger » (rouge) · « Inactif depuis N jours » (jaune, plus de 3 jours, `JournalSynchronisationService`) · « À jour » (émeraude) ; retard : « En retard de N jours », « À recevoir », « Jamais synchronisé » (N affiché « — », **jamais 0**) |
| **Gestes** | pied : « Fermer », « Voir le détail » (écran Synchronisation : refus détaillés, « Remettre en file »), « Synchroniser maintenant » (désactivé pendant l'envoi ; la modale se met à jour sans se fermer) | « Demander la synchronisation de ce poste » / « Demander la synchronisation des postes », « Renvoyer vers ce poste » / « Renvoyer vers tous les postes », « Actualiser », « Fermer » ; audit `sync.renvoi_poste:{poste}`, `sync.renvoi_tous` |

**Jeu d'exemple calculé à la main (PRD §5) :** 2 fiches `pending` + 1 client `pending` + 1 article `pending` + 1 vente `conflict` → badge « **5** » rouge ; carte « En attente d'envoi » = **4** ; « Refusés par le serveur » = **1**.

**Toasts :** « Synchronisation terminée : N reçu(s), N envoyé(s). » · « N enregistrement(s) refusé(s) — voir le détail. » · hors ligne, avertissement « Serveur injoignable — les saisies restent sur ce poste et partiront à la prochaine synchronisation. » Demande depuis le web : « Demande envoyée : les postes connectés synchroniseront dans les 30 secondes. » / « Demande envoyée au poste {poste} : il synchronisera dans les 30 secondes s'il est connecté. » / « Poste inconnu du serveur : demande non envoyée. »

**Règles :** la modale web **ne synchronise rien elle-même** : elle demande et renvoie. Un poste au jeton expiré ne reçoit aucun drapeau (toast d'erreur) : il doit d'abord se reconnecter. « Dernière synchronisation » = `server_time`, jamais l'horloge du poste. La modale du poste ne liste pas les autres postes (D-SYNC-7).

**Piège d'affichage web (déjà payé) :** la modale vit dans l'en-tête (`sticky z-30`) qui crée son propre empilement : la barre latérale la recouvrait et rognait titre et colonne « Poste ». Correctif : `<x-modal>` accepte `teleport` (déplacée sous `<body>`), largeur réduite (`xl`), introduction ≈ 55 mots ; côté poste, test `agrierp_flutter/test/modale_au_dessus_barre_laterale_test.dart` (modale au-dessus de la barre latérale).

**Journal serveur** : `journal_synchronisation` (UUID, serveur seul, non synchronisé) : une ligne par tirage et par envoi (poste = nom du jeton, sens, `nb_recus`, `nb_acceptes`, `nb_refuses`) écrite **APRÈS** le calcul de la réponse ; son échec ne fait jamais échouer la synchronisation.

### 3.2 PROMPT — Modale « Synchronisation » (web d'abord, puis poste)

~~~~text
[Colle P0 ici.]

OBJECTIF : un bouton « Synchroniser » dans la barre du haut de LogiALVIA ouvre la modale « Synchronisation » : au poste, l'état de CE poste et le geste « Synchroniser maintenant » ; au web, l'état de tous les postes et les gestes pour les faire se resynchroniser. Spécification : section 3.1 de /home/user/agrierp/docs/logialvia/43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md. Le web est le maître : construis-le d'abord.

PRÉREQUIS : appairage et moteur S0 à S4 faits ; le web a une barre du haut (sélecteur d'exercice, recherche, cloche) ; modale unique (`<x-modal>` / AppModal) ; état actuel de logialvia : barre logialvia_app/lib/core/widgets/shell/app_top_bar.dart (recherche + cloche, aucun bouton), modale logialvia_app/lib/core/widgets/app_modal.dart, kpi_card.dart, app_toast.dart.

RÉFÉRENCES (lecture seule) : /home/user/agrierp/agrierp_laravel/app/Livewire/Shared/EtatSynchronisationPostes.php, resources/views/livewire/shared/etat-synchronisation-postes.blade.php, resources/views/layouts/app.blade.php, resources/views/components/modal.blade.php, app/Services/JournalSynchronisationService.php, ResynchronisationPostesService.php, DemandeSynchronisationService.php ; /home/user/agrierp/agrierp_flutter/lib/core/sync/modale_synchronisation.dart, lib/features/sync/synchronisation_screen.dart, lib/core/widgets/barre_superieure.dart, modale_agri.dart, carte_kpi.dart, toast_agri.dart, lib/core/sync/sync_engine.dart (SyncOutcome) ; PRD docs/prd/synchronisation-barre-superieure.md (§1 à §11) et modal-synchronisation-reduit.md ; tests : tests/Feature/EtatSynchronisationPostesTest.php, ResynchronisationPostesTest.php, SupervisionSynchronisationTest.php ; flutter test/synchronisation_barre_test.dart, modale_synchronisation_avertissement_test.dart, resynchronisation_serveur_test.dart, compteur_attente_test.dart, synchronisation_screen_test.dart.

TÂCHES
M1 (serveur) — table `journal_synchronisation` (serveur seul, UUID) et `poste_synchronisations` (curseur mémorisé à la dernière page d'un tirage) ; JournalSynchronisationService (écrit APRÈS la réponse ; un échec du journal ne fait jamais échouer la synchronisation ; `etatDesPostes`) ; seuil d'inactivité en constante (3 jours, décision client).
M2 (web) — composant Livewire de la modale + bouton `sync` dans la barre (entre le sélecteur d'exercice et la cloche), badge « 9+ », `manage-users` à l'ouverture et à chaque geste ; contenu, pastilles, libellés et toasts EXACTS de 3.1 ; `<x-modal … :teleport="true">` largeur `xl` pour éviter le recouvrement par la barre latérale ; gestes « Demander la synchronisation… » (drapeau 60 min) et « Renvoyer vers… » (renvoi complet), audit `sync.renvoi_poste:{poste}` / `sync.renvoi_tous`. La modale web NE synchronise RIEN : elle demande et renvoie.
M3 (poste) — NEW:logialvia_app/lib/core/sync/modale_synchronisation.dart sur AppModal ; le bouton de app_top_bar.dart appelle un SERVICE injecté (jamais le moteur dans le widget) ; badge calculé par le compteur « à envoyer » de S2 ; cartes KpiCard ; liaison En ligne / Hors ligne ; pied « Fermer », « Voir le détail », « Synchroniser maintenant » (désactivé pendant l'envoi, la modale se met à jour sans se fermer) ; écran « Synchronisation » (refus détaillés, « Remettre en file »).
M4 (poste) — libellés COPIÉS du web et prouvés par un test qui les LIT dans la vue ; heure « Dernière synchronisation réussie » = server_time ; « — » si jamais, « Jamais » pour réception/envoi vides.
M5 (poste) — drapeau « Resynchronisation demandée par le serveur » entre sa lecture (GET /api/sync/demande toutes les 30 s) et son acquittement ; « Synchroniser maintenant » force le tirage complet quand le drapeau est levé.

CONTRAINTES : hors ligne n'est jamais rouge ; compteur « à envoyer » = TOUTES les tables envoyées ; heure du serveur ; la modale du poste ne liste pas les autres postes ; boutons de fenêtre et sélecteur d'exercice touchent la même barre : les poser ensemble (blocs 3 et 4 du guide).
INTERDITS : bouton web qui fait semblant d'envoyer ; « Dernier tirage » inconnu affiché 0 ; modale ouverte par un @if ; modale rognée par la barre latérale.

CRITÈRES D'ACCEPTATION
1. Jeu d'exemple 3.1 : badge « 5 » rouge ; cartes 4 et 1 (test poste).
2. Hors ligne : liaison « Hors ligne », aucune couleur d'erreur, toast d'avertissement exact.
3. Le bouton web n'est visible que pour l'administrateur (test serveur) ; 403 sinon.
4. Jeu P1/P2/P3 au web : pastilles « Refus à corriger » > « Inactif depuis N jours » > « À jour » dans cet ordre ; « Jamais synchronisé » affiche « — », jamais 0.
5. Journal : un tirage et un envoi écrivent chacun une ligne (poste, sens, nb_recus, nb_acceptes, nb_refuses) ; un échec du journal n'empêche pas la synchronisation ; MUTATION : retirer la journalisation fait rougir le test.
6. « Demander » : le poste synchronise dans les 30 s ; « Renvoyer » : tirage complet puis acquittement ; un jeton expiré : toast d'erreur.
7. La modale web n'est pas recouverte par la barre latérale (test navigateur) ; celle du poste est au-dessus de la barre latérale.
8. Libellés web = libellés poste (test de lecture de la vue).

PIÈGES PAYÉS : compteur « en attente » faux (tables omises, le compteur d'origine en oubliait huit : un caissier croyait tout envoyé) ; dernière synchronisation lue à l'horloge du poste ; modale rognée par l'empilement de l'en-tête ; « dernier tirage » inconnu affiché 0.
~~~~

### 3.3 Questions au client
Qui voit le bouton au web (administrateur seul) ? Seuil d'inactivité (3 jours) ? La modale du poste doit-elle lister les autres postes (AgriERP : non) ?

---

## 4. Alertes de stock et rappels VMS automatiques

### 4.1 La vérité, par mécanisme (relue dans le code ; ne pas promettre davantage)

| Mécanisme | Où, quand, qui |
|---|---|
| **Alertes quotidiennes de la cloche** | `DailyElevageAlertsJob` planifié à **06:05, fuseau `Africa/Porto-Novo`** (`agrierp_laravel/routes/console.php`) → `AlertesElevageService::emettre()` : **stock sous seuil** (produits actifs, `alert_threshold` non nul et `stock_qty <= alert_threshold`, rôle `admin`, `critique` si stock ≤ 0 sinon `moyen`, lien `/seuils-alerte?produit=…`), **mortalité anormale** (pire jour des 7 derniers jours de chaque bande vivante ≥ `SEUIL_MORTALITE_JOUR = 5,0` %, rôle `animalier`), **soins planifiés** à venir ou en retard (délai `rappel_soins_jours`, `JOURS_RAPPEL_SOINS = 3` par défaut ; R-SOINS-01), **échecs de reproduction** (une seule fois, 30 derniers jours). Une notification par objet et par jour (même `type` + même `link_url`) : relancer la tâche n'empile rien. |
| **Prophylaxie du jour** | `DailyProphylaxyReminderJob` à **06:00** : pour chaque bande vivante dont l'espèce est active, traitement du barème dû au jour de cycle (règle unique `ProtocoleDuJourService`). ⚠️ Le push instantané (Reverb) **n'est PAS câblé** : la notification est persistée et se voit au prochain rafraîchissement. |
| **Événementiel (serveur)** | autonomie de provende (`RaiseFeedAutonomyAlertAction`, jamais bloquante) ; stock négatif après synchronisation et vente sous délai d'attente (`FlagNegativeStockFromSyncAction`, `FlagSaleUnderWithdrawalAction` : le serveur accepte et signale) |
| **Cloche du web** | `NotificationBell`, table `notifications` (colonnes `user_id`, `target_role`, `type`, `severity`, `title`, `message`, `icon`, `link_url`, `is_read`, `read_at`) ; relue à chaque rendu Livewire (**aucun `wire:poll`** dans `agrierp_laravel/resources` : pas de rafraîchissement automatique démontré) ; n'affiche que les notifications visibles du rôle ; Centre de notifications `app/Livewire/Notifications/Index.php` |
| **Fenêtre « Rappels du jour » (web)** | `RappelsDuJour` monté dans le layout ; ouverture décidée CÔTÉ SERVEUR : une fois par session de navigateur, rouverte à chaque connexion, « Ne plus afficher aujourd'hui » l'emporte, **jamais vide** ; calcul `RappelsDuJourService` (droit `view-elevage` exigé) |
| **Poste** | **le poste n'émet AUCUNE notification** (aucun `insert` local hors absorbeur). Sa **cloche est une copie** du serveur : chaque tirage remplace la table `notifications` en entier (`SyncEngine._absorberNotifications`), relue toutes les 30 s depuis la base locale (`BarreSuperieure.rafraichissementCloche`) ; « marquer lue » et « supprimer » EXIGENT le réseau (`POST /api/notifications/{id}/read`, `DELETE`) et ne sont PAS mis en file (hors ligne : refus avec une phrase, jamais appliqué en silence). Hors ligne : **pas de NOUVELLE notification**. |
| **Poste : « Alertes critiques » du tableau de bord** | recalculées LOCALEMENT, hors ligne, avec les mêmes règles que le serveur (stock critique, 5 articles au plus ; mortalité ≥ 5 %) : `agrierp_flutter/lib/features/pilotage/tableau_de_bord_repository.dart` |
| **Poste : fenêtre « Rappels du jour »** | calcul LOCAL (`rappels_du_jour_repository.dart`) ; `PorteSession.surOuverture` UNE fois par session (lancement après le PIN, chaque connexion, JAMAIS un déverrouillage) ; « Ne plus afficher aujourd'hui » au coffre |
| **Entretien** | purge hebdomadaire des notifications lues depuis plus de 90 jours ; rappel hebdomadaire (lundi 08:00) de télécharger la sauvegarde, adressé au rôle `admin` ; sauvegarde quotidienne 02:00 |

**Une phrase par cas.** Planifié au serveur : alertes de stock, de mortalité, de soins, d'échec de reproduction (06:05), prophylaxie du jour (06:00), entretien. Calculé au poste : « Alertes critiques » du tableau de bord, contenu de « Rappels du jour ». Déclenché à l'ouverture : la fenêtre « Rappels du jour » (poste et web). **Au poste, une alerte de stock se VOIT au tableau de bord (immédiat, hors ligne) et dans la cloche (après synchronisation) ; le poste n'en émet jamais.**

> ⚠️ **ERREUR RELEVÉE DANS LE GUIDE (bloc 18, tableau « Entretien » et « Pièges »).** Le guide affirme « un seul cron `schedule:run` en production ». **C'est incomplet et dangereux.** `DailyElevageAlertsJob` et `DailyProphylaxyReminderJob` sont des tâches **mises en file** (`implements ShouldQueue`) ; `.env.example` fixe `QUEUE_CONNECTION=database`. Sans **travailleur de file**, elles s'empilent dans la table `jobs` et **ne s'exécutent jamais, sans aucune erreur visible**. `docs/GUIDE_DEPLOIEMENT.md` §5 prescrit donc **DEUX** entrées cron : (1) `php artisan schedule:run` chaque minute ; (2) `php artisan queue:work --stop-when-empty --max-time=55` chaque minute (ou `QUEUE_CONNECTION=sync` si l'hébergeur interdit la seconde). Pour LogiALVIA : prévoir les deux, ou `sync`, et **tester** qu'une alerte planifiée arrive vraiment dans la table `notifications`.

Autres points d'attention : `onOneServer()` exige un magasin de cache qui gère les verrous (`CACHE_STORE=database` convient) ; le fuseau de la planification ET de « aujourd'hui » est celui du Bénin (`FuseauHorairesNotificationsTest`) ; colonnes `type`/`severity` : valeurs autorisées seulement (MySQL strict refuse sinon : `backup.reminder`, `error`, `warning` n'existent pas ; utiliser `system` et les gravités du référentiel) ; la divergence de formule de mortalité (pire jour des 7 derniers jours ≥ 5 % ↔ cumul hebdomadaire) reste un arbitrage client OUVERT.

### 4.2 PROMPT — Alertes de stock et rappels VMS (serveur planifié, cloche du poste, fenêtre « Rappels du jour »)

~~~~text
[Colle P0 ici.]

OBJECTIF : dire et construire EXACTEMENT ce qui est automatique dans LogiALVIA et par QUI : alertes planifiées au serveur, cloche du web, cloche du poste copiée du serveur, tableau de bord du poste calculé hors ligne, fenêtre « Rappels du jour » à l'ouverture. Spécification : section 4.1 de /home/user/agrierp/docs/logialvia/43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md.

PRÉREQUIS : synchronisation S0 à S4 faite ; règles métier de LogiALVIA (seuils, prophylaxie) lues dans 15_REGLES_METIER.md ; la règle du jour de cycle existe en UN service (section 6). État actuel de logialvia : tout est CALCULÉ au poste, rien de persisté ni planifié (logialvia_app/lib/pilotage/presentation/viewmodels/alertes_view_model.dart = source unique de la cloche ET du panneau « Alertes Critiques » ; app_top_bar.dart `_CloctheNotifications` ; modale_stock_critique.dart ; rappels_prophylaxie.dart ; modale_prophylaxie_du_jour.dart une fois par processus ; seuils : colonne `threshold`).

RÉFÉRENCES (lecture seule) : /home/user/agrierp/agrierp_laravel/routes/console.php, app/Jobs/DailyElevageAlertsJob.php, DailyProphylaxyReminderJob.php, app/Services/AlertesElevageService.php, RappelsDuJourService.php, ProtocoleDuJourService.php, app/Actions/RaiseFeedAutonomyAlertAction.php, FlagNegativeStockFromSyncAction.php, FlagSaleUnderWithdrawalAction.php, app/Livewire/Shared/NotificationBell.php, app/Livewire/Notifications/Index.php, app/Livewire/Shared/RappelsDuJour.php, app/Models/Notification.php, docs/GUIDE_DEPLOIEMENT.md §5 ; poste : agrierp_flutter/lib/features/notifications/notifications_repository.dart, notifications_screen.dart, lib/core/widgets/barre_superieure.dart, lib/features/pilotage/tableau_de_bord_repository.dart, lib/features/elevage/rappels_du_jour_repository.dart, rappels_du_jour_ouverture.dart, rappels_du_jour_modale.dart, lib/features/verrou/porte_session.dart, lib/core/sync/sync_engine.dart (_absorberNotifications) ; PRD docs/prd/popup-rappels.md ; tests : AlertesClocheTest, ApiNotificationsTest, FuseauHorairesNotificationsTest, RappelsDuJourTest, AlerteAutonomieAlimentaireTest, StockNegatifTest, VenteStockNegatifRecueTest ; flutter : notifications_test.dart, rappels_du_jour_test.dart, rappels_du_jour_parite_php_test.dart, rappels_du_jour_blade_test.dart, barre_superieure_test.dart.

TÂCHES
N1 (serveur) — table `notifications` (UUID, user_id nullable, target_role, type, severity, title, message, icon, link_url, is_read, read_at, created_at) ; types et gravités = valeurs AUTORISÉES seulement (liste fermée dans le code) ; modèle avec portée « visibles du rôle » ; synchronisée en TIRAGE SEUL (serveur seul).
N2 (serveur) — service d'émission (modèle AlertesElevageService) qui REPREND les règles que logialvia calcule déjà dans AlertesViewModel/TableauBordRepository : JAMAIS un seuil nouveau. Une notification par objet et par jour (même type + même lien) : relancer la tâche n'empile rien. Destinataires par rôle (stock → admin, élevage → animalier, comme AgriERP : décision client).
N3 (serveur) — tâches planifiées à l'heure du Bénin dans routes/console.php (alertes 06:05, prophylaxie 06:00, purge hebdomadaire des notifications lues depuis plus de 90 jours, rappel hebdomadaire de sauvegarde au rôle admin) ; `onOneServer()` ; DEUX crons documentés (schedule:run ET queue:work, ou QUEUE_CONNECTION=sync) ; test que la tâche planifiée écrit réellement dans `notifications`.
N4 (serveur) — événementiel : alerte d'autonomie à l'enregistrement d'une fiche (jamais bloquante), stock négatif / vente sous délai d'attente à la RÉCEPTION d'une vente du poste (le serveur accepte et signale).
N5 (web) — cloche (lue à chaque rendu ; aucun faux « temps réel » promis), Centre de notifications, « marquer lue » / supprimer ; fenêtre « Rappels du jour » décidée CÔTÉ SERVEUR (une fois par session de navigateur, rouverte à la connexion, « Ne plus afficher aujourd'hui » l'emporte, jamais vide, droit d'élevage exigé).
N6 (poste) — la cloche de app_top_bar.dart lit la COPIE locale tirée du serveur (chaque tirage la remplace en entier) ; « marquer lue » / « supprimer » EXIGENT le réseau et ne sont jamais mis en file (hors ligne : refus avec une phrase) ; le poste n'émet AUCUNE notification.
N7 (poste) — garder le calcul local de AlertesViewModel pour le tableau de bord (hors ligne) : les deux sources donnent le MÊME seuil (UN service de domaine, jamais deux formules).
N8 (poste) — fenêtre « Rappels du jour » à l'ouverture : use case pur NEW:logialvia_app/lib/elevage/domain/usecases/rappels_du_jour_usecase.dart qui COMPOSE les services existants ; déclenchée UNE fois par session par le flux splash → connexion → application (équivalent de PorteSession.surOuverture), au lancement APRÈS le PIN et à chaque connexion, JAMAIS à un déverrouillage ; « Ne plus afficher aujourd'hui » (jour AAAA-MM-JJ par utilisateur, au coffre ou dans preferences_poste) ; jamais de fenêtre vide ; une erreur de la fenêtre est avalée et ne bloque rien.

CONTRAINTES : aucune alerte inventée ; aucun push instantané promis (Reverb non câblé) ; heure et « aujourd'hui » = Bénin ; le poste calcule pour l'affichage immédiat, le serveur émet pour la cloche ; un lu/supprimé appliqué localement hors ligne ferait réapparaître la notification au tirage suivant : refuser plutôt que mentir.
INTERDITS : seuil recopié à deux endroits ; type/gravité hors liste ; un cron par tâche ; promesse d'e-mail ou de SMS non demandée ; fenêtre au déverrouillage.

CRITÈRES D'ACCEPTATION
1. Produit actif à stock ≤ seuil : UNE notification `critique` (stock ≤ 0) ou `moyen`, adressée au rôle admin, lien vers les seuils ; relancer la tâche le même jour : zéro notification de plus.
2. Mortalité : pire jour des 7 derniers jours ≥ seuil → notification au rôle animalier ; sous le seuil → rien.
3. Soins : « Soin à venir » dès N jours ou moins, « Soin en retard » dès que la date est dépassée, N = rappel_soins_jours (0 à 30, défaut 3, 0 = le jour même) ; une alerte par soin et par jour.
4. Échec de reproduction : signalé UNE seule fois.
5. Fuseau : à 06:05 heure de Porto-Novo (test avec horloge figée).
6. Queue : avec `QUEUE_CONNECTION=database` et un travailleur, la notification arrive ; sans travailleur la doc le dit (et un test de déploiement le détecte).
7. Cloche du poste : copie du serveur, remplacée à chaque tirage ; hors ligne : pas de nouvelle notification ; marquer lue hors ligne : refus avec phrase, rien d'appliqué.
8. Tableau de bord du poste hors ligne : mêmes seuils que le serveur (test de parité sur une grille de cas calculée à la main).
9. Fenêtre « Rappels du jour » : au lancement après le PIN et à chaque connexion ; JAMAIS à un déverrouillage ; « Ne plus afficher aujourd'hui » ; aucun rappel ⇒ aucune fenêtre ; sans droit d'élevage ⇒ aucune fenêtre.
10. Suites vertes ; les limites (pas de temps réel, pas d'e-mail) écrites dans le CLAUDE.md.

PIÈGES PAYÉS (par AgriERP) : alertes seulement AFFICHÉES sur leurs écrans (personne n'en était averti ; la cloche ne recevait que l'autonomie : ticket 15.49) ; aucun seuil inventé ; colonne type/severity hors valeurs autorisées (MySQL strict refuse l'écriture) ; fuseau du planificateur ; lu/supprimé local hors ligne qui fait réapparaître la notification ; tâches en file SANS travailleur (jamais exécutées, sans erreur) ; Reverb non câblé (ne pas promettre l'instantané).
~~~~

### 4.3 Questions au client
Qui reçoit quelle alerte (stock → admin, élevage → animalier, comme AgriERP) ? Heure d'émission (06:00 / 06:05, Bénin) ? Notification instantanée voulue (Reverb : non câblé même dans AgriERP) ? E-mail ou SMS en plus de la cloche (nécessite `42_CONFIG_MECEF_SMTP_LOGO_FAVICON.md` écran (b)) ? Délai de rappel des soins (3 jours) ? La formule de mortalité (pire jour ≥ 5 % ou cumul hebdomadaire) ?

---

## 5. Rationnement automatique

**Les règles sont dans `15_REGLES_METIER.md` (et le guide bloc 5) : ce fichier ne les duplique pas.** Rappel de leur existence : tableau par catégorie × ration du barème, `total_g` somme de TOUTES les catégories (null si une catégorie est inconnue, jamais 0), `total_kg` = `round(total_g / 1000, 2)`, clé stable par libellé en égalité stricte (normalisé : minuscules, sans accents, tranche d'âge ignorée), repli explicite si une ligne manque au barème, alerte d'autonomie (rouge en rupture, sous 3 jours ou sans produit de provende ; n'empêche jamais l'enregistrement).

### 5.1 PROMPT — Brancher le rationnement automatique

~~~~text
[Colle P0 ici.]

OBJECTIF : la provende servie et l'autonomie alimentaire d'une fiche de LogiALVIA se calculent SANS saisie, par UNE règle, au web et au poste, et alimentent la cloche. Les RÈGLES (formules, rations, seuils, jeux de cas) sont celles de 15_REGLES_METIER.md et du guide bloc 5 : ne les redéfinis pas ; si une règle manque, DEMANDE.

PRÉREQUIS : fiches journalières synchronisées (section 2, S3) ; barème `feed_ration_standards` éditable ; service d'alertes (section 4, N2).

RÉFÉRENCES (lecture seule) : /home/user/agrierp/agrierp_laravel/app/Support/StadePondeuse.php, CategorieVolaille.php, CategorieRationLapin.php, CategorieRationPorc.php, app/Services/AlerteAutonomieFicheService.php, AutonomieAlimentaireService.php, app/Actions/RaiseFeedAutonomyAlertAction.php, app/Models/FeedRationStandard.php, app/Livewire/Elevage/ParametresElevage.php ; poste : agrierp_flutter/lib/features/elevage/stade_pondeuse.dart, categorie_ration_lapin.dart, autonomie_alimentaire_carte.dart ; tests : tests/Feature/RationVolailleTest.php, RationnementLapinsTest.php, AlerteAutonomieAlimentaireTest.php, AutonomieProduitProvendeTest.php ; flutter : test/ration_volaille_test.dart, categorie_ration_lapin_test.dart, provende_autonomie_parite_test.dart, rationnement_infobulles_test.dart. LogiALVIA existant : logialvia_app/lib/elevage/data/tables/parametres_elevage_tables.dart (`BaremesRation`), CalculFicheJournaliere (rationsConfigurees, rationCategorie, provendeTotaleGrammes).

TÂCHES
R1 — UN service serveur de rationnement (clé stable par libellé, tableau, total) lisant le barème ; le web ET la synchronisation l'appellent. NEW:logialvia_app/lib/elevage/domain/services/rationnement.dart au poste (fonction pure `cleStable` + `tableauRationnement`), prouvé égal au PHP par un test de PARITÉ exécuté (grille de cas de 15_REGLES_METIER.md).
R2 — Alerte d'autonomie par fiche : service serveur appelé À L'ENREGISTREMENT d'une fiche (web, et fiche acceptée d'un poste à l'envoi), jamais bloquante, une alerte par objet et par jour ; au poste : fonction pure `autonomie(provendeDisponibleG, provendeJourG)` → jours, présentée par le ViewModel (aucun calcul dans le widget) ; l'alerte réelle (cloche) vient du serveur.
R3 — Barème éditable (créer, modifier, archiver) dans « Paramètres Élevage », web et poste ; une migration d'ajout est idempotente et ne réécrit JAMAIS une ration ajustée.

CRITÈRES D'ACCEPTATION : les jeux de cas de 15_REGLES_METIER.md donnent les totaux attendus (y compris la catégorie inconnue → total null, pas 0) ; renommer un libellé ne retombe PAS en silence sur la valeur de repli ; l'alerte ne bloque jamais la saisie ; parité PHP↔Dart exécutée ; suites vertes.
INTERDITS : ration retrouvée par sous-chaîne ; total qui ne somme qu'une catégorie ; alerte qui bloque ; valeur de repli silencieuse.
PIÈGES PAYÉS : ration par sous-chaîne (renommage → repli silencieux) ; total de la seule catégorie vendue ; barème « non confirmé » qui doit rester VISIBLE ; seuils « PROVISOIRES » périmés dans des commentaires.
~~~~

---

## 6. Prophylaxie automatique

**Les règles sont dans `15_REGLES_METIER.md` (et le guide bloc 6) : non dupliquées ici.** Elles existent en UN service : jour de cycle (J1 = jour de référence ; dernière saillie pour une bande en reproduction, sinon date de mise en bande ; bande en reproduction sans saillie = INDÉTERMINÉE), traitement dû si `jour_debut <= J <= jour_fin`, entrées « le 1er du mois » jamais évaluées mais comptées, calcul en jours calendaires entiers ; R-SOINS-01 (délai N) ; R-RAPPELS-01 (trois sources : soins planifiés, traitements dus, fins de délai d'attente ; tri : urgence, date, code de bande, type, libellé).

### 6.1 PROMPT — Brancher la prophylaxie automatique

~~~~text
[Colle P0 ici.]

OBJECTIF : les traitements prophylactiques du barème de LogiALVIA se projettent sur chaque bande, génèrent la notification quotidienne au serveur et alimentent la fenêtre « Rappels du jour » — par UN service de règle. Les règles viennent de 15_REGLES_METIER.md : ne les redéfinis pas, ne les recopie pas (une seconde copie d'une règle sanitaire diverge toujours) ; si une règle manque, DEMANDE.

PRÉREQUIS : bandes et calendrier de prophylaxie synchronisés ; alertes (section 4) et fenêtre de rappels (4.2, N8) en place ; `rappel_soins_jours` (0 à 30, défaut 3) réglable au web et au poste.

RÉFÉRENCES (lecture seule) : /home/user/agrierp/agrierp_laravel/app/Services/ProtocoleDuJourService.php, ProtocoleDuJour.php, RappelsDuJourService.php, AlertesElevageService.php, app/Jobs/DailyProphylaxyReminderJob.php, app/Actions/ValidateProphylaxisTreatmentsAction.php, RecordVeterinaryCareAction.php ; poste : agrierp_flutter/lib/features/elevage/soins_repository.dart (`protocoleDuJour`), rappels_du_jour_repository.dart ; tests : tests/Feature/ProtocoleDuJourServiceTest.php, RappelsDuJourTest.php ; flutter : test/protocole_du_jour_test.dart, protocole_du_jour_parite_test.dart, rappels_du_jour_test.dart, soins_infirmerie_calendrier_test.dart. LogiALVIA existant : logialvia_app/lib/elevage/domain/services/prophylaxie_de_la_bande.dart, rappels_prophylaxie.dart, modale_prophylaxie_du_jour.dart (une fois par processus), test/elevage/prophylaxie_du_jour_test.dart, rappels_prophylaxie_test.dart.

TÂCHES
P1 — Service serveur UNIQUE du jour de cycle et des traitements dus (ProtocoleDuJourService), appelé par la tâche quotidienne, par la fenêtre « Rappels du jour » et par les fiches ; calcul en jours calendaires ENTIERS (minuit à minuit : un `diffInDays` flottant fait manquer les traitements d'un seul jour).
P2 — Tâche quotidienne à 06:00 (heure du Bénin) : pour chaque bande vivante dont l'espèce est active, notification du traitement dû ; une notification par bande, traitement et jour ; bande indéterminable (pas de date de référence) ignorée sans erreur.
P3 — Poste : use case pur `rappels_du_jour_usecase.dart` qui COMPOSE `prophylaxie_de_la_bande`, `rappels_prophylaxie` et le calendrier des soins ; parité PHP↔Dart exécutée (modèle : protocole_du_jour_parite_test.dart).
P4 — Fenêtre « Rappels du jour » : voir 4.2 N5 et N8 (une fois par session, jamais au déverrouillage, jamais vide, « Ne plus afficher aujourd'hui », droit d'élevage).

CRITÈRES D'ACCEPTATION (cas à écrire À LA MAIN) : traitement J5–J5 dû le jour 5 d'une bande dont le jour de référence est le 1er ; soin planifié à J−1 → « En retard » ; N = 3 : soin à J+3 → « À venir », à J+4 → rien ; aucun rappel → aucune fenêtre ; bande en reproduction sans saillie → « indéterminée » affichée telle quelle ; entrée « le 1er du mois » : non évaluée mais comptée ; filière désactivée dans les modules actifs → aucun rappel ; le caissier (sans droit d'élevage) ne reçoit pas la fenêtre ; parité PHP↔Dart sur la même grille.
INTERDITS : calcul sur le jour du mois au lieu du jour de cycle (rejoue les traitements chaque 1er) ; fenêtre au déverrouillage ; fenêtre vide ; recopier la règle au lieu d'appeler le service unique.
PIÈGES PAYÉS : `diffInDays` flottant (traitements d'un jour manqués) ; fenêtre ouverte à chaque déverrouillage ; fenêtre vide ; entrées « le 1er du mois » évaluées à tort ; push instantané promis alors que Reverb n'est pas câblé.
~~~~

### 6.2 Questions au client (rationnement et prophylaxie)
Barèmes à confirmer par filière (Goliaths, Pintades : barème générique réutilisé ; Poissons-Chats : non confirmé dans AgriERP). Seuil d'autonomie : 3 jours ? Produit de provende rattaché à quelle filière ? Fenêtre au lancement ET à chaque connexion ? Délai N (3 jours) ? Le caissier la reçoit-il ? Les entrées « le 1er du mois » du calendrier : décision NON tranchée à AgriERP (non évaluées).

---

## 7. Contrôle de ce fichier

Chemins vérifiés par `ls` ou lecture le 07/11/2026 : tous ceux de `agrierp_laravel/app/Http/Controllers/Api/{AuthController,SyncController,AdministrationEnLigneController,SupervisionSynchronisationController}.php`, `app/Livewire/Parametres/PostesAppairage.php`, `app/Livewire/Shared/{EtatSynchronisationPostes,NotificationBell,RappelsDuJour}.php`, `app/Services/{AlertesElevageService,RappelsDuJourService,ProtocoleDuJourService,JournalSynchronisationService,DemandeSynchronisationService,ResynchronisationPostesService}.php`, `app/Jobs/*`, `routes/{api,console}.php`, `docs/{BLUEPRINT_SYNCHRONISATION_MULTIPOSTES,GUIDE_DEPLOIEMENT,DOCTRINE_PORTAGE}.md`, `docs/prd/{synchronisation-barre-superieure,modal-synchronisation-reduit,popup-rappels}.md`, les fichiers `agrierp_flutter/lib/core/sync/*`, `lib/core/auth/*`, `lib/features/parametres/{appairage_poste,onglet_appairage}.dart`, `lib/features/sync/synchronisation_screen.dart` ; la plupart des tests cités (listés par `ls`). Vérifiés aussi : `ReinitialisationCompleteTest.php`, `modale_au_dessus_barre_laterale_test.dart`, `outils/essai_multipostes.sh`. **Non vérifiés** : les fichiers à créer (`docs/SYNC_TABLES.md`, `rappels_du_jour_usecase.dart`, `rationnement.dart`) ; aucune exécution de suite (ni PHP ni Flutter) n'a été lancée pour ce document ; les fichiers `15_REGLES_METIER.md`, `30_DATABASE.md`, `02_ARCHITECTURE_WEB_ET_STACK.md` sont écrits en parallèle par d'autres agents et n'ont pas été relus ici.
