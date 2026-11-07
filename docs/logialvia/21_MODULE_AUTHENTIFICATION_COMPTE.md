# 21 — MODULE AUTHENTIFICATION & COMPTE (Splash, Accueil, Connexion, Mon Profil, Aide & À Propos, Contactez l'Éditeur)

## USAGE

- **Quand l'utiliser** : pour construire (ou auditer) les 6 écrans d'entrée et de compte, au web puis au poste, au jalon W3 (`20_MODULES_INDEX.md` §6). Prérequis : socle serveur W1, rôles semés. Ce module conditionne tous les autres (aucun écran métier sans session).
- **Ordre** : `20_MODULES_INDEX` → **`21_`** → `29_` (utilisateurs) → `43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md` (appairage, jeton, PIN).
- **Entrées** : `logialvia/docs/F1_Module_Authentification.md`, `F9_Module_Compte_Utilisateur.md`, `I3_Security_Strict.md`, `I1_Matrice_RBAC.md`, `docs/logialvia/GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md` blocs 2, 3, 14, 15 ; code `logialvia_app/lib/administration/presentation/screens/{auth,compte}/`, `logialvia_app/lib/administration/domain/services/hachage_mot_de_passe.dart`, `logialvia_app/lib/administration/domain/usecases/connecter_utilisateur_usecase.dart`, libellés `logialvia/docs/manuel/libelles/{00-connexion,31-mon-profil,32-aide-a-propos,33-contact-editeur}.json` ; AgriERP : `agrierp_laravel/app/Actions/ChangerMotDePasseAction.php`, `agrierp_laravel/app/Http/Middleware/ChangementMotDePasseObligatoire.php`, `agrierp_laravel/app/Services/CodeSecoursService.php`, `agrierp_flutter/lib/core/auth/verrou_local.dart`, `docs/CODE_SECOURS_ADMIN.md`, `docs/prd/verrou-web.md`.
- **Sorties** : migrations (`users` UUID, `security_logs`, `audit_logs`), Actions, composants Livewire, vues, écrans Dart, tests.
- **Chemins** : `logialvia/…` = `/home/user/massenon/logialvia/…` ; sans préfixe = `/home/user/agrierp`.

---

## 1. Objectif

Authentifier un utilisateur (identifiant + mot de passe), poser son rôle en session, protéger l'accès (5 essais, 15 minutes), lui permettre de changer son mot de passe, de lire l'aide et de contacter l'éditeur. **Aucune fonction décorative** : un bouton écrit réellement ou n'existe pas (`A1_MASTER_PROMPT.md` §2.3).

## 2. Écrans

| Route | Écran | Rôles | Droit web | Surface | Notes |
|---|---|---|---|---|---|
| `/` | Splash | public | — | Poste (au web : redirection directe) | contrôle de la base locale ; destination `/welcome` au premier lancement sinon `/login` |
| `/welcome` | Accueil | public | — | Poste (+ page publique web optionnelle) | un seul bouton primaire « Se Connecter » centré en bas |
| `/login` | Connexion | public | — | Web + Poste | bannière de verrouillage, modale d'information |
| `/profil` | Mon Profil | A K C N | auth | Web + Poste | seul écran qui change un secret |
| `/aide` | Aide & À Propos | A K C N | auth | Web + Poste | grille de modules + FAQ |
| `/contact` | Contactez l'Éditeur | A K C N | auth | Web + Poste | 2 onglets |

## 3. Splash (poste)

Ordre strict : (1) emblème cercle 80 px fond blanc 10 %, bordure blanche 2 px, icône `egg` 44 px ; (2) mot-symbole « Logi**ALVIA** » (« ALVIA » en `brand-gold`) ; (3) « GESTION ET SUIVI AVICOLE INTÉGRÉ » ; (4) « Couveuse • Élevage • Stocks • Ventes • Relances Clients » ; (5) « ALLMANY ET COMPAGNIE » ; (6) « Projet d'Appui à l'Entrepreneuriat au Bénin (PAEB) » ; (7) barre de progression 6 px, 0 → 100 % en 3 s linéaire (PAS de spinner) ; (8) cinq messages rotatifs toutes les 600 ms : « Vérification de la base de données locale… », « Initialisation du moteur de synchronisation… », « Chargement des cycles de couveuse en cours… », « Sécurisation de l'espace de stockage… », « Chargement du catalogue de stocks et de vaccins… » ; (9) « v1.0.0 — © 2026 FAGUEZ SARL ».
Comportement : ouvre réellement la base et applique les migrations ; sème rôles + compte `admin` si base vierge ; destination = `/welcome` si le semis vient de créer l'admin, sinon `/login` ; durée minimale 3 s ; **état d'erreur** : message explicite + bouton « Réessayer » (jamais un écran figé). Au web : aucun splash ; la vérification d'état serveur est faite par le démarrage de l'application (au poste, le splash vérifie aussi le jeton et l'état de synchronisation : `43_`).

## 4. Connexion

**Sections (ordre strict)** : carte blanche centrée 460 px max, `rounded-2xl`, `shadow-2xl`, padding 32 px, fond dégradé navy 165° + grain. (1) barre langue/version : pilule « 🌐 Français » puis « v1.0.0 » ; (2) en-tête de marque : icône `egg` 38 px, « Logi**ALVIA** » 22 px, « ALLMANY ET COMPAGNIE » 9 px, filet, « GESTION ET SUIVI AVICOLE INTÉGRÉ » ; (3) bandeau de 7 icônes (`egg`, `inventory_2`, `point_of_sale`, `receipt`, `vaccines`, `campaign`, `account_balance`) ; (4) « Bienvenue ! » + « Connectez-vous à votre espace LogiALVIA. » ; (5) bannière de verrouillage (masquée) ; (6) champ « NOM D'UTILISATEUR OU EMAIL » (icône `person`) ; (7) champ « MOT DE PASSE » (icône `lock`, œil afficher/masquer) ; (8) case « Se souvenir de moi » + texte NON cliquable « Contactez l'administrateur » (clé `login-contacter-administrateur` ; remplace « Mot de passe oublié ? » depuis MDP-1) ; (9) bouton « SE CONNECTER » pleine largeur 44 px ; (10) pied : « © 2026 LogiALVIA — Projet d'Appui à l'Entrepreneuriat au Bénin (PAEB) — FAGUEZ SARL ».

| Champ | Règle | Message |
|---|---|---|
| Nom d'utilisateur ou email | requis, non vide après `trim()` | « L'adresse e-mail est obligatoire. » |
| Mot de passe | requis, non vide après `trim()` | « Le mot de passe est obligatoire. » |
| Identifiants inconnus/faux | même message, ne dit jamais lequel | « Adresse e-mail ou mot de passe incorrect. Veuillez réessayer. (n/5) » |
| Formulaire invalide | bordure `error-deep` + fond `error-container` (`.is-invalid`), message rouge 11 px | toast « Veuillez renseigner tous les champs requis. » (accompagne, ne remplace pas) |
| 5e échec | compte bloqué 900 s ; bouton désactivé ; bannière ; AUCUN toast | « Trop de tentatives de connexion. Accès bloqué pendant 15min. » puis `Mmin Ss` à chaque seconde |
| Succès | toast « Connexion réussie — Bienvenue ! », attente 700 ms, `/dashboard` | — |

**Règles** : chaque échec → `security_logs` (`typeEvenement = 'echec_connexion'`, jamais le mot de passe) ; succès/déconnexion → `audit_logs` (`action = 'connexion'`/`'deconnexion'`). « Se souvenir de moi » mémorise l'IDENTIFIANT (table `preferences_poste`, clé dédiée), jamais la session ; n'écrit qu'après connexion réussie ; décocher efface ; la case reflète l'état réel au retour. Placeholder identifiant = `admin` (écart délibéré : le prototype affichait `gerante@allmany.bj`, compte fictif).
**Rôles** : quatre (`admin`, `comptable`, `caissier`, `animalier`) : TRANCHÉ (DV-07) ; le rôle `comptable` se crée depuis Paramètres, jamais `admin`. **Droits (DV-06, DV-08, DV-15)** : le caissier voit et enregistre ses retours dans « Retours et Avoirs » de `/ventes` (DV-08) mais n'a ni `/inventaire` ni `manage-facturation` ; `/inventaire` : administrateur seul par défaut (DV-15) ; comptable : périmètre par défaut calqué sur AgriERP (Q-DV-7 ouverte).
**Compte initial** : `admin`, « Administratrice Principale », rôle `admin`, semis idempotent ; mot de passe initial `ALLMANY2026` (arbitré par la Gérante le 25/08/2026 ; `AdminSeeder.motDePasseInitialAdmin`) — **doit être changé de force à la première connexion** (dette `TODO` de F1 ; BR-038). Le seul rôle `admin` n'est jamais créable par l'écran ; le dernier admin ne s'archive pas.
**Web** (nouveau) : verrouillage persisté côté serveur (le prototype et le poste ne persistent pas : fermer/rouvrir remet à zéro) ; limite `5/min` sur `POST /api/auth/login` ; jeton Sanctum NOMMÉ d'après le poste ; compte archivé refusé ; mot de passe temporaire → écran de changement obligatoire AVANT le PIN et l'accueil (middleware `ChangementMotDePasseObligatoire`).
**Poste hors ligne** : première connexion d'un poste = réseau obligatoire ; ensuite ouverture par PIN local (4 à 6 chiffres, PBKDF2 ≥ 100 000 itérations) ; le poste ne conserve NI mot de passe NI hash.
**Questions** : Q-ADM-1 (politique de mot de passe), Q-AUT-1 verrouillage de session inactive : durée ?

## 5. Mon Profil

Structure : (1) carte d'informations du compte : Nom, Identifiant, Rôle (lecture seule) ; (2) formulaire de changement de mot de passe ; (3) « MÉTADONNÉES DE SESSION » ; (4) journal d'audit personnel (20 dernières actions). **Pas de bouton Déconnexion ici** : il vit dans le menu profil de la barre du haut sur toutes les pages.

| Champ | Règle | Message |
|---|---|---|
| ANCIEN MOT DE PASSE * | doit correspondre (temps constant, vérifié AVANT toute écriture) | message distinct « ancien mot de passe incorrect » (l'utilisateur est déjà authentifié) |
| NOUVEAU MOT DE PASSE * | « Min. 8 caractères, 1 majuscule, 1 chiffre » (les 3 règles appliquées, testées une à une) ; différent de l'ancien (et du temporaire) | refus par règle |
| CONFIRMER LE NOUVEAU MOT DE PASSE * | identique | refus |
| Bouton « Mettre à jour le mot de passe » | écrit réellement ; trace `audit_logs` SANS aucun des deux mots de passe | toast de succès après écriture seulement |

Métadonnées : « Dernière connexion » = l'avant-dernière (lue dans `audit_logs`, tri par date puis `id`) ; « Connexions enregistrées » (pas d'adresse IP au poste) ; statut du compte « Actif » (désormais réel : `is_active`). Journal : colonnes DATE, ACTION, MODULE ; entité technique traduite en module affichable (`Vente` → « Point de Vente », `Ecriture` → « Comptabilité »…). Au web : réglage du verrouillage de session (VW3). Au poste : le changement exige le réseau (le mot de passe part au serveur qui le hache).
**Sync** : aucune table synchronisée en écriture au poste ; `users` serveur seule. **Notifications** : aucune.

## 6. Aide & À Propos

3 sections : (1) « MODULES DU LOGICIEL » : grille de 8 vignettes (Ventes & Clients, Élevage & Couveuse, Stocks & Catalogue, Achats & Fournisseurs, Santé Animale, Comptabilité, Rapports & États, Clients & Relances) qui CONDUISENT au module (jamais inertes) ; (2) « FOIRE AUX QUESTIONS » : 5 questions repliables avec recherche (« Rechercher dans l'aide (ex : vente, stock, module...) ») portant sur mots-clés normalisés (sans accents) ET texte visible ; questions : « Comment enregistrer une nouvelle vente ? », « Comment fonctionne l'alerte de stock critique ? », « Comment relancer un client avec un solde impayé ? », « Comment activer ou désactiver une filière (ex. Lapins) ? », « Comment administrer une dose et décrémenter le stock ? » ; (3) pied de page éditeur. Aide par écran et visite guidée (42 étapes sur 21 écrans côté poste : `logialvia_app/lib/core/tour/`) ; règle AgriERP proposée : une entrée d'aide pour chaque route authentifiée, vérifiée par un test (`agrierp_laravel/lang/fr/aide_ecrans.php`, guide bloc 13f ; Q-AID-1 : textes rédigés par le client ou proposés ?).

## 7. Contactez l'Éditeur

2 onglets : « Question Générale » (OBJET *, MESSAGE *) et « Signaler un Problème » (module concerné parmi 7 + description). Le prototype affichait « Message envoyé » sans rien envoyer (anti-patron interdit). **Comportement retenu au poste** : le message est enregistré (`messages_editeur`), copié dans le presse-papiers sous forme prête à envoyer (en-tête, version, identité, corps, étapes de reproduction), bouton « Enregistrer et copier le message » ; numéro de l'éditeur avec bouton de copie ; liste des messages conservés ; zone « Capture d'Écran » non reprise (aucune pièce jointe, raison affichée). **Avec le web et SMTP** (`42_CONFIG_MECEF_SMTP_LOGO_FAVICON.md`) : l'envoi par e-mail devient possible — **Q-CON-1** : envoyer réellement (SMTP) ou garder « enregistrer et copier » ? Tant que non tranché : comportement du poste, aucune promesse d'envoi.

## 8. Critères d'acceptation

- [ ] Un compte `animalier` en URL directe `/comptabilite` : redirection `/dashboard`.
- [ ] DV-08 : un compte `caissier` voit l'onglet « Retours et Avoirs » de `/ventes` ; DV-15 : un compte `comptable` en URL directe `/inventaire` est refusé.
- [ ] Quatre rôles semés (`admin`, `comptable`, `caissier`, `animalier`) ; un compte `caissier` en URL directe `/inventaire` : redirection `/dashboard` ; sur `/factures-mecef` il voit et réimprime, `annuler`, `retransmettre` et `avoir` sont refusés par le serveur (TRANCHÉ DV-06, DV-07).
- [ ] 5 échecs → bannière + bouton désactivé + aucun toast ; relancer l'application ne remet pas le verrou à zéro (web).
- [ ] Mot de passe jamais présent dans `security_logs`, `audit_logs`, ni dans une table du poste (garde : aucune colonne `password`, `token`, `secret`).
- [ ] Changement de mot de passe : refus si nouveau = ancien ; < 8 car., sans majuscule ou sans chiffre → refus propre à chaque règle.
- [ ] Compte créé depuis Paramètres peut ouvrir une session (preuve que l'écran n'est pas décoratif).
- [ ] « Se souvenir de moi » : relance → identifiant prérempli, session fermée ; décocher efface.
- [ ] Splash : 5 messages rotatifs mot pour mot ; erreur d'initialisation → « Réessayer ».

## 9. Tests

Feature (web) : `ConnexionTest`, `VerrouConnexionTest`, `ChangementMotDePasseObligatoireTest`, `ReinitialisationMotDePasseAdminTest`, `RbacParRouteTest` (matrice à 4 rôles : DV-06, DV-07) (modèles : `agrierp_laravel/tests/Feature/ChangementMotDePasseObligatoireTest.php`, `…/ReinitialisationMotDePasseAdminTest.php`, `…/CodeSecoursAdminTest.php`, `…/ConnexionSansReinitialisationParEmailTest.php`). Poste : étendre `logialvia_app/test/administration/` (`compte_utilisateur_test.dart`, `parametres_generaux_test.dart`) ; garde de libellés lus dans la source ; test « le journal ne contient jamais le mot de passe » (parcourt tout `audit_logs`). Modèles poste AgriERP : `agrierp_flutter/test/reinitialisation_mot_de_passe_test.dart`.

## 10. PROMPT de construction du module

> Construis le module **Authentification & Compte** (web puis poste) d'après ce fichier. Lis d'abord `20_MODULES_INDEX.md` §7, `F1`, `F9`, `I3`, `docs/logialvia/GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md` blocs 2, 14, 15. Ordre : **(1) migration** `users` (UUID, `identifiant` unique sans arobase, `role`, `is_active`, `must_change_password`, mot de passe haché serveur), `security_logs`, `audit_logs`, `messages_editeur` ; **(2) modèles** ; **(3) Actions** `ConnecterUtilisateurAction` (verrou 5/15 min persisté, journaux), `ChangerMotDePasseAction` (ancien vérifié en temps constant, nouveau ≠ ancien, politique, audit sans mot de passe), `ReinitialiserMotDePasseAction` (temporaire, sessions et jetons détruits, audit `user.password_reset`), `EnregistrerMessageEditeurAction` ; **(4) composants Livewire** `Auth\Connexion`, `Auth\ChangementMotDePasseObligatoire`, `Profil\MonProfil`, `Aide\AideAPropos`, `Contact\ContactEditeur` ; **(5) vues Blade** fidèles aux sections ci-dessus (messages mot pour mot) ; **(6) portage poste** : `POST /api/auth/login` (jeton nommé), PIN PBKDF2, écran de changement forcé AVANT PIN/accueil, suppression de `hachage_mot_de_passe.dart` après bascule (D-SRV-5), splash avec état d'erreur ; **(7) tests** : ceux du §9 + parité des messages web/poste lus dans la source. **Interdits** : « Mot de passe oublié » par e-mail, SHA-256+sel au poste après la bascule, toast de succès sans écriture, case « Se souvenir de moi » qui rouvre la session, mot de passe journalisé, chemin d'écran sans `can:`.
