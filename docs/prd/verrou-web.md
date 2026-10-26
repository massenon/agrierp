# PRD — Verrou de session sur le web
**Statut :** brouillon · **Date :** 2026-10-26 · **Ticket(s) :** VW1 à VW6 (`docs/PLAN_FINALISATION.md`, sprint VW)

> **Demande du client :** « Il faut appliquer aussi le module de verrou session sur le web. »

## 1. Problème

Le poste Windows a un verrou depuis le 21/10/2026 (VL-1 : code PIN à chaque lancement et entrée « Verrouiller » ; VL-2 : verrouillage après inactivité). Le web n'en a aucun : la caissière qui s'éloigne du comptoir laisse le navigateur ouvert sur la caisse (POS), les créances et la paie, jusqu'à l'expiration de la session Laravel (`SESSION_LIFETIME`, 480 min dans `.env.example`, soit huit heures de présence sans aucune protection). Exemple : le poste de la caisse est partagé par deux caissières ; à 12 h 05 la première part déjeuner sans se déconnecter, la seconde (ou un visiteur) peut lire les ventes du jour et saisir une dépense au nom de la première jusqu'à 20 h 00.

## 2. Existant

- **Web :** rien. Une seule protection de session : l'expiration (`config/session.php`, `lifetime`) et la déconnexion manuelle (`LogoutController`). Le limiteur de connexion (`Livewire\Auth\Login`, `RateLimiter`, 5 essais / 900 s, clé identifiant + IP) et la journalisation (`AuditLog::record()`) existent et sont réutilisés. Le menu du compte est `layouts/app.blade.php` (`#dd-profile`) ; Mon Profil est `Livewire\Profil\MonProfil`.
- **Poste :** VL-1 et VL-2 (`lib/core/auth/verrou_local.dart`, `verrou_inactivite.dart`, `lib/features/verrou/`). Libellés : « Verrouiller » (icône `lock`), « Application verrouillée », « NOM D'UTILISATEUR », « DÉVERROUILLER », « Verrouillage automatique », durées Jamais / 1 minute / 5 / 15 / 30 minutes, défaut 5 minutes, « Trop d'essais. Réessayez dans … », 10 échecs cumulés = reconnexion.
- **Doctrine :** l'article 5.6 faisait de ce verrou une exception « propre au poste » (le web n'en avait pas et n'avait pas à l'inventer). **La décision du client change cela** : le web devient le maître (article 0 : on le construit d'abord au web), le poste garde son mécanisme (PIN, hors ligne) et s'aligne sur le web pour tout ce qui est commun.
- **Prototype HTML :** aucun écran de verrouillage. Fonctionnalité nouvelle, sans maquette : la présentation reprend celle de la page de connexion web (`livewire/auth/login.blade.php`), comme l'a demandé le client pour le poste.

## 3. Utilisateurs et rôles

Les quatre rôles (admin, comptable, caissier, animalier), sans distinction : le verrou protège la session de **tout compte connecté**. Aucune permission `view-*` / `manage-*` : comme `/mon-profil`, les routes sont `auth` seul (elles figurent parmi les routes universelles). Chacun règle **sa propre** durée d'inactivité dans Mon Profil. L'administrateur ne peut pas déverrouiller la session d'un autre (le secret est le mot de passe de la personne).

## 4. Exigences fonctionnelles

- **EF1 — Verrouillage manuel.** Une entrée « Verrouiller » (icône `lock`) dans le menu du compte, entre « Paramètres » et le séparateur de « Déconnexion » (même place et même libellé que le poste).
- **EF2 — Verrouillage automatique.** Après N minutes sans geste (pointeur, clavier, défilement, toucher) dans **aucun** onglet de l'application, le navigateur demande le verrouillage au serveur. N = Jamais / 1 / 5 / 15 / 30 minutes, **défaut 5 minutes** (valeurs du poste), réglé par l'utilisateur dans Mon Profil, mémorisé **sur le serveur** (colonne `users.verrouillage_minutes`) : le réglage suit la personne d'un navigateur à l'autre.
- **EF3 — Écran de verrouillage.** Même présentation que la connexion (logo, image, titre), titre « Application verrouillée », identifiant en lecture seule (libellé « NOM D'UTILISATEUR »), champ « MOT DE PASSE » (le mot de passe du compte), bouton « DÉVERROUILLER », lien « Se déconnecter ».
- **EF4 — Effectif côté serveur.** Un état `session_locked` est tenu dans la session Laravel. Un middleware refuse toute requête web (page, `POST /livewire/update`, envoi de fichier, formulaire) tant que la session est verrouillée, hors : l'écran et l'action de déverrouillage, la déconnexion, le verrouillage lui-même (idempotent), les pages publiques, la sonde `/up`, les fichiers de Livewire. Page : redirection vers l'écran de verrouillage ; requête JavaScript ou Livewire : **423 Locked**. La minuterie du navigateur n'est qu'un déclencheur qui appelle `POST /verrouiller`. L'état résiste au rechargement et vaut pour tous les onglets.
- **EF5 — Pas de perte de saisie.** Voir § 7 : écran en surcouche qui ne démonte pas la page.
- **EF6 — Pas de coupure d'une opération en cours.** Pas de verrouillage automatique tant qu'une requête Livewire est en vol, ni dans les 60 s qui suivent un clic sur un export / téléchargement ; pas de minuterie sur la page de connexion ni sur les pages publiques (elles n'ont pas le gabarit de l'application).
- **EF7 — Déverrouillage.** Mot de passe vérifié **côté serveur** ; limiteur de connexion réutilisé (5 essais par 15 minutes, par compte et adresse IP) ; **10 échecs cumulés dans la session = déconnexion complète** (session invalidée, retour à la connexion avec le message « Trop d'échecs : vous avez été déconnecté. Reconnectez-vous. »).
- **EF8 — Audit.** `AuditLog` : `session.verrouillee`, `session.deverrouillee`, `session.deverrouillage_echec`, `session.deconnexion_apres_echecs`. Le mot de passe n'est **jamais** journalisé.
- **EF9 — Expiration.** La durée de vie de la session Laravel reste indépendante (§ 6).
- **EF10 — Parité poste.** Le poste reprend les libellés et durées communs (Mon Profil, menu du compte, écran), prouvé par un garde-fou lu dans le Blade.

## 5. Règles métier

- **Durées** : `VerrouSessionService::DUREES = [0, 1, 5, 15, 30]` (0 = Jamais), `DUREE_PAR_DEFAUT = 5`. Libellés : 0 → « Jamais » ; 1 → « 1 minute » ; n → « n minutes ». Une valeur hors liste, en base ou reçue, est refusée / ramenée à 5.
- **Échéance** (exemple calculé à la main, il devient le test JavaScript) : dernière activité à t = 0, durée 5 min = 300 000 ms. À t = 299 999 ms : ne rien faire. À t = 300 000 ms : verrouiller. Durée « Jamais » : jamais. Requête en vol à t = 300 000 ms : attendre. Suspension (clic sur un export) valable jusqu'à t = 360 000 ms : attendre jusqu'à cet instant.
- **Essais** : échecs 1 à 4 : « Mot de passe incorrect. » ; le 5e : blocage 15 minutes (« Trop d'essais. Réessayez dans 15 min 00 s. », comme le poste) ; après le déblocage, 5 essais encore ; le **10e échec** : déconnexion. Un succès remet le compteur de la session à zéro.
- Aucun effet comptable, stock ni effectif. Aucune synchronisation d'une donnée métier.

## 6. Hors ligne et synchronisation

**Rien à synchroniser.** La colonne `users.verrouillage_minutes` n'est pas dans la liste de colonnes que `/api/sync/pull` expose pour `users` (`id, name, username, email, is_active`) : elle ne descend pas au poste, qui garde son propre réglage au coffre (`agrierp.inactivite.<id>`). Raison : le poste verrouille avec un PIN et sans réseau, le web avec le mot de passe en ligne ; deux mécanismes, deux réglages, **mêmes libellés et mêmes durées**. Aucune migration Drift (poste inchangé hors libellés). Les routes d'API (`routes/api.php`, jetons Sanctum) n'ont pas de session : le middleware n'y passe pas.

**Interaction avec `SESSION_LIFETIME`.** Le verrou ne prolonge ni ne raccourcit la session : l'expiration de Laravel reste glissante (renouvelée à chaque requête) et indépendante. Cas : (a) session verrouillée qui atteint son expiration : le déverrouillage répond « session expirée » (401/419) et la page renvoie à la connexion ; (b) le déverrouillage réussi est lui-même une requête, il renouvelle la session ; (c) une personne active qui ne fait que lire (défilement, sans requête) n'est pas verrouillée, mais sa session peut expirer côté serveur : comportement inchangé. **Cookie « Se souvenir de moi » :** il rouvrirait une session neuve et déverrouillée après suppression du cookie de session. Au verrouillage, le cookie de rappel est donc retiré du navigateur et rétabli au déverrouillage.

## 7. Interface

- **Menu du compte** (`layouts/app.blade.php`) : bouton « Verrouiller » (icône `lock`), `dusk="verrouiller"`.
- **Écran de verrouillage :** composant Blade `x-verrou-session`, posé une fois dans le gabarit de l'application. Surcouche plein écran (`fixed inset-0`, au-dessus de tout, opaque) reprenant la page de connexion. La même surcouche s'affiche sur la page `/verrouillage` (atteinte au rechargement ou depuis un autre onglet).
- **Choix « pas de perte » (recommandé et retenu) : surcouche qui ne démonte pas la page.** Le navigateur garde l'état des composants Livewire (instantané côté client) ; l'application est rendue `inert` et masquée par une surcouche opaque, aucune requête ne part (423). Au déverrouillage réussi, la surcouche disparaît : le formulaire non enregistré est intact, sans nouveau rendu. Les requêtes Livewire refusées en 423 n'affichent pas d'erreur : elles font apparaître la surcouche. Limites dites franchement : (1) cela tient tant que la page n'est pas rechargée ni quittée : après un rechargement, la page `/verrouillage` remplace l'application et la saisie non enregistrée est **perdue** (inévitable : l'état d'un composant Livewire n'existe que dans la page) ; (2) ce qui était **déjà affiché** reste dans la mémoire du navigateur (outils de développement) : le verrou protège contre le passant, pas contre quelqu'un qui manipule le navigateur ; ce que le serveur refuse, lui, est refusé même si le navigateur est manipulé ; (3) un fichier envoyé (téléversement) en cours n'est pas protégé par le brouillon.
- **Mon Profil** : carte « Verrouillage automatique » sous « Modifier le Mot de Passe » (liste déroulante, `wire:model.live`, effet immédiat).
- **Textes communs au web et au poste** (garde-fou `verrou_parite_web_test.dart`) : « Verrouiller », « Application verrouillée », « NOM D'UTILISATEUR », « DÉVERROUILLER », « Verrouillage automatique », « Jamais / 1 minute / N minutes », « Après ce délai sans toucher à la souris ni au clavier, l'application se verrouille : », « Session de {nom}. Saisissez votre », « Trop d'essais. Réessayez dans ». Textes propres à chaque mécanisme : « MOT DE PASSE » / « CODE PIN », « Se déconnecter » / « PIN oublié ? Se reconnecter ».
- **Poste** : aucun écran nouveau ; textes alignés sur le Blade (libellé de la carte de Mon Profil, phrase d'aide, sous-titre de l'écran).

## 8. Hors périmètre

- Un PIN au web (le web est en ligne : le mot de passe suffit) ; l'authentification à deux facteurs.
- Verrouiller à la fermeture de l'onglet ou au changement d'onglet (non demandé).
- Une durée imposée par l'administrateur à tous les comptes (voir Q2).
- La synchronisation du réglage entre le web et le poste (voir Q3).
- Le verrou de l'API (jetons Sanctum du poste) : inchangé.

## 9. Questions ouvertes pour le client

- **VW-Q1** — Défaut à 5 minutes pour **tous** les comptes web dès la mise en service (la caisse, en pleine vente, verrouille après 5 minutes sans geste). *Recommandé : oui, comme le poste ; chacun peut passer à « Jamais ».*
- **VW-Q2** — L'administrateur peut-il interdire « Jamais » ou imposer un plafond ? *Recommandé : non pour l'instant ; à décider après une semaine d'usage.*
- **VW-Q3** — Un seul réglage partagé entre le web et le poste d'un même utilisateur ? *Recommandé : non (deux mécanismes, deux appareils) ; le coût serait une colonne synchronisée et une migration Drift.*
- **VW-Q4** — Faut-il, après le déverrouillage, réafficher la page où l'on était après un **rechargement** ? *Retenu : oui (la page demandée est mémorisée et rouverte), la saisie non enregistrée restant perdue.*

## 10. Critères d'acceptation

Tests écrits **rouges d'abord**, avec mutation :

- **Laravel** `tests/Feature/VerrouSessionMiddlewareTest.php` : requête refusée verrouillée (redirection pour une page, 423 pour le JSON et pour `POST /livewire/update`), acceptée déverrouillée, exemptions (déverrouillage, déconnexion, public, `/up`, fichiers Livewire), invité non concerné. Mutation : retirer le test de l'état dans le middleware ; retirer une exemption.
- `VerrouSessionDeverrouillageTest.php` : bon / mauvais mot de passe, limiteur au 5e échec, **10 échecs = déconnexion**, compteur remis à zéro, cookie de rappel. Mutation : seuil 10 → 11 ; ne pas vérifier le hash.
- `VerrouSessionReglageTest.php` : défaut 5, valeurs admises, refus d'une valeur hors liste, réglage propre à chaque utilisateur. `VerrouSessionAuditTest.php` : les quatre clés, aucun mot de passe dans la base. `VerrouSessionLivewireTest.php` : Mon Profil enregistre la durée. `VerrouSessionBladeTest.php` : garde-fou lu dans le Blade (menu « Verrouiller », surcouche et minuterie présentes dans le gabarit, absentes de `guest`, durées du service = durées du JavaScript = durées du poste).
- **JavaScript** `tests/Js/verrou-logique.test.mjs` (`node --test`) : l'exemple chiffré du § 5.
- **Flutter** `test/verrou_parite_web_test.dart` : libellés et durées lus dans le Blade et le service PHP ; `chassis_web_test.dart` : le menu du compte compte « Verrouiller ».
