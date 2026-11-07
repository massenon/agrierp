# 42 — Écrans de configuration : MeCeF, SMTP, logo, favicon (web ET poste)

> **USAGE**
>
> - **Quand l'utiliser.** Quand le web de LogiALVIA a son hub « Paramètres » et que l'on construit, écran par écran, les quatre réglages que le client a demandés : (a) configuration MeCeF, (b) configuration e-mail SMTP avec envoi d'essai, (c) logo de l'entreprise, (d) favicon (icône d'onglet). Ce fichier donne, pour chaque écran, la **spécification relue dans AgriERP** puis **deux prompts : web d'abord, poste ensuite** (doctrine : la vue web est le maître, le poste lui est fidèle).
> - **Ordre.** Socle web et hub Paramètres → rôles et droits (`manage-parametres`) → (b) SMTP (le plus simple, il sert d'étalon) → (c) logo → (d) favicon → (a) MeCeF (après `41_MECEF_EMECEF.md`, tâches M1 à M3). Chaque écran : web, puis poste (le poste exige l'appairage et la synchronisation : `43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md`).
> - **Entrées requises.** Le web de LogiALVIA avec le hub Paramètres ; la table des réglages d'entreprise (AgriERP : `company_settings`, ligne unique) ; l'appairage ; `04_UI_UX_DESIGN_SYSTEM.md` pour les composants (modale unique, toasts, dropzone) ; `03_DEVELOPMENT_STANDARDS.md`.
> - **Sorties.** Quatre écrans web + quatre écrans poste, leurs services « point de passage unique », migrations, audit, tests de garde, et la liste des écarts assumés.
> - **Avertissements.** (1) Le jeton MeCeF et le mot de passe SMTP du web sont des **secrets** : jamais servis au poste. (2) Le **logo et le favicon** téléversés au web d'AgriERP **ne servent à rien en l'état** (voir (c), « Écart n° 1 ») : LogiALVIA doit les utiliser réellement. (3) Les adresses de l'API MeCeF ne sont **pas confirmées** par la DGI : ne rien inventer.
> - **Voir aussi.** `41_MECEF_EMECEF.md`, `43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md`, `04_UI_UX_DESIGN_SYSTEM.md`, `31_TESTING_QA.md`, `GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md` (blocs 13, 15, 19).

---

## 0. Socle commun aux quatre écrans (AgriERP, relu)

| Sujet | Règle (source) |
|---|---|
| Hub | `agrierp_laravel/app/Livewire/Parametres/ParametresHub.php` : onglets par clé d'URL (`?tab=…`), le hub n'exige que `view-parametres` ; les onglets sensibles gardent leur droit propre. Onglets concernés : `entreprise` « Données de l'Entreprise » (logo, favicon), `facturation` « Facturation normalisée (e-MECeF) », `email` « Email (SMTP) ». Test d'ordre : `agrierp_laravel/tests/Feature/ParametresConfigurationsTest.php`. |
| Droit | `manage-parametres` (créé dans `agrierp_laravel/database/seeders/RolesAndPermissionsSeeder.php`), contrôlé **à chaque écriture** par `$this->authorize('manage-parametres')`. `EmailSmtp::mount()` fait en plus `abort_unless(Gate::allows('manage-parametres'), 403)`. ⚠️ **Écart relevé : `FacturationEmecef::mount()` et `DonneesEntreprise::mount()` n'ont PAS ce `abort_unless`** : qui a seulement `view-parametres` peut ouvrir ces onglets et voir mode, IFU, adresse, opérateur et « jeton configuré » (jamais le jeton lui-même) ; seules les écritures sont refusées. Dans LogiALVIA : mettre le `abort_unless` partout (décision à valider). |
| Secrets | Cast `encrypted` du modèle (`CompanySetting` : `smtp_password_encrypted`, `mecef_jeton_encrypted`). Jamais réaffichés (« •••• », « Remplacer », « Effacer » ; champ vide = **inchangé**), jamais journalisés, jamais servis au poste. ⚠️ La sauvegarde du serveur contient ces secrets **chiffrés par `APP_KEY`**. |
| Audit | `AuditLog::record(action, module)` : `company_settings.updated`, `company_settings.mecef_updated`, `company_settings.smtp_updated`, `company_settings.smtp_tested`, `company_settings.smtp_password_cleared`. Le journal dit **qu'un réglage a changé, jamais sa valeur**. Libellés français côté poste : `agrierp_flutter/lib/core/audit/libelles_audit.dart`. |
| Messages | `agrierp_laravel/lang/fr/validation.php` + jeux d'attributs passés par chaque composant ; toasts via `$this->dispatch('toast', message: …, type: 'success'|'error')`. |
| Modales | `<x-modal>` ouverte par **événement** (`open-modal`), jamais par un `@if` (guide bloc 14). Confirmation destructive : `<x-modal-confirm-hard-delete …>`. |
| Poste | Les réglages d'entreprise se synchronisent par une **DEMANDE** de type `entreprise` rejouée par le **même service** que l'écran web (`EntrepriseService`, `MecefReglageService`) ; le poste ne porte jamais un secret du web. Les réglages SMTP du poste sont **locaux** à chaque poste. |

### Bloc commun à coller en tête de CHAQUE prompt ci-dessous (P0)

~~~~text
P0 — CADRE COMMUN
Tu travailles sur LogiALVIA (web Laravel 12 + Livewire 3 ; poste Flutter/Drift), mêmes conventions que LogiAgriERP (monorepo /home/user/agrierp, lecture seule). Tout en français (prose, libellés, commentaires, noms de tests, messages de commit). Lis avant d'écrire : le CLAUDE.md du projet où tu travailles ; /home/user/agrierp/docs/DOCTRINE_PORTAGE.md ; /home/user/agrierp/docs/logialvia/42_CONFIG_MECEF_SMTP_LOGO_FAVICON.md (la section de l'écran traité). Règles : (1) la vue web est le maître, le poste lui est fidèle à 100 % (structure, libellés, retours), prouvé par un test qui LIT la vue Blade (modèle : /home/user/agrierp/agrierp_flutter/test/email_smtp_blade_test.dart) ; (2) un seul point de passage serveur par règle (un service), appelé par l'écran web ET par la demande du poste ; (3) droit `manage-parametres` à chaque écriture ; (4) aucun secret en clair, ni au poste, ni en journal, ni en message ; (5) une modale s'ouvre par événement, jamais par un @if ; (6) si le schéma change : serveur (migration) ET poste (app_database.dart puis `dart run build_runner build`, jamais d'édition du fichier généré) ; clés primaires UUID ; (7) ne commite ni ne pousse sans demande expresse ; jamais de pkill ; (8) tu n'inventes aucune règle : ce qui n'est pas dans la spécification, tu le demandes.
~~~~

---

## (a) Configuration MeCeF

### a.1 Spécification (relue : `agrierp_laravel/app/Livewire/Parametres/FacturationEmecef.php`, `resources/views/livewire/parametres/facturation-emecef.blade.php`, `app/Services/Mecef/MecefReglageService.php`, `MecefConfigurationTesteur.php`, `MecefReglage.php`, `app/Support/MecefMode.php`)

**Titre :** icône `receipt_long`, « Facturation normalisée (e-MECeF) ». Introduction : « Renseignez ici le compte e-MECeF de la ferme pour transmettre ses factures normalisées à la DGI. Une facture normalisée n'est plus modifiable ni annulable : elle se corrige par un avoir. Une facture simple n'est jamais transmise. » Encadré « Où trouver le jeton ? » : le jeton (JWT) est délivré par la DGI pour le compte e-MECeF de l'IFU ; il est secret : chiffré sur le serveur, jamais affiché, jamais envoyé aux postes.

| Champ | Libellé exact | Contrôle | Règle de validation | Message exact |
|---|---|---|---|---|
| `mecefMode` | « Mode de facturation normalisée » | liste : « Désactivé » · « e-MECeF (en ligne) » · « Boîtier MeCeF (à venir) » | `required`, `in:desactive,emecef,boitier` | « Choisissez le mode de facturation normalisée. » / « Le mode de facturation normalisée doit être : désactivé, e-MECeF ou boîtier. » |
| `ifu` | « IFU de l'entreprise » | texte numérique, `maxlength 13`, indice « 13 chiffres » ; note « 13 chiffres, celui du compte e-MECeF. C'est le même IFU que celui de « Données de l'Entreprise » : une seule saisie. » | `nullable|string|regex:/^[0-9]+$/|max:50` ; **en mode e-MECeF : exactement 13 chiffres**, refusé AVANT toute écriture | « L'IFU doit contenir uniquement des chiffres. » / « L'IFU doit comporter 13 chiffres pour la facturation e-MECeF. » |
| `mecefApiUrl` (mode e-MECeF seulement) | « Adresse de l'API e-MECeF » | type `url`, indice `https://…`, deux boutons : « Production (DGI) » · « Environnement d'essai (DGI) » (défaut : essai) | `nullable|url|max:255` | « L'adresse de l'API e-MECeF doit être une adresse web complète (https://…). » |
| `mecefJeton` (mode e-MECeF seulement) | « Jeton e-MECeF (JWT) » | si un jeton existe : « •••••••••••• » + « Remplacer » + « Effacer » (confirmation : « Effacer le jeton ? Plus aucune facture ne sera transmise tant qu'un nouveau jeton n'est pas saisi. ») ; sinon champ mot de passe, indice « Collez le jeton délivré par la DGI » | `nullable|string|max:4000` ; **vide = conservé** | (règles génériques de `validation.php`) |
| `mecefOperateurId` | « Identifiant de l'opérateur » (indice `1`) | texte | `nullable|string|max:50` | — |
| `mecefOperateurNom` | « Nom de l'opérateur (caissier par défaut) » (indice `Caissier`) | texte | `nullable|string|max:100` | — |

Notes d'affichage par mode : boîtier → « Mode boîtier : la transmission se fera par le poste Windows où le boîtier est branché. Le réglage est enregistré, mais rien n'est encore transmis : les factures restent en attente. » ; désactivé → « Aucune facture n'est transmise : la facture reste un registre avec facture PDF. » ; e-MECeF → « Les ventes choisies en « Facture normalisée » à l'encaissement sont transmises à la DGI par le serveur. » Note sous les adresses : « Pour un premier essai sans valeur fiscale, choisissez l'environnement d'essai. Ces deux adresses sont relevées dans le paquet de référence : confirmez-les avec le portail e-MECeF de la DGI. »

**Boutons :** « Tester la configuration » (icône `cloud_done`, `dusk="tester-mecef"`, désactivé pendant l'appel) et « Enregistrer ». **Adresses (constantes, NON confirmées par la DGI)** : essai `https://developper.impots.bj/sygmef-emcf/api` (défaut), production `https://api.impots.bj/sygmef-emcf/api` : **ne pas les présenter comme officielles**.

**Toasts :** « Réglage de la facturation normalisée enregistré. » · « Jeton effacé : rien ne part plus à la DGI tant qu'un nouveau jeton n'est pas saisi. »

**« Tester la configuration »** (teste la **saisie**, sans l'enregistrer ; ne crée **jamais** de facture). Contrôles locaux (aucun réseau) : mode (« e-MECeF (en ligne). » ; boîtier : « Mode boîtier : la transmission par le poste n'est pas encore disponible. Choisissez « e-MECeF (en ligne) » pour tester. » ; désactivé : « Facturation normalisée désactivée : choisissez « e-MECeF (en ligne) » pour tester. »), IFU (« L'IFU doit comporter 13 chiffres. »), adresse (« Adresse invalide : elle doit commencer par https://. »), jeton (« Aucun jeton : saisissez celui du compte e-MECeF de votre IFU (portail de la DGI). » ; « Jeton expiré depuis le JJ/MM/AAAA : demandez-en un nouveau sur le portail e-MECeF. » ; « Présent, valable jusqu'au … » ; « Présent. »). Si un point bloque : « Configuration incomplète : corrigez les points signalés, aucun appel n'a été fait. » Sinon **UN** `GET {adresse}/info/status` (jeton en Bearer, délai 8 s, connexion 5 s) : « Hôte injoignable : vérifiez l'adresse de l'API et la connexion internet. » · « Appel impossible : l'adresse de l'API est inutilisable. » · « Jeton refusé (401|403) : vérifiez-le ou remplacez-le. » · « Adresse introuvable (404) : l'hôte répond mais ce n'est pas l'API e-MECeF attendue. » · « Service e-MECeF indisponible (429|5xx) : réessayez plus tard. » · « Réponse inattendue de l'API e-MECeF (…). » · « Réponse inattendue : l'hôte répond, mais pas comme l'API e-MECeF. » · « Jeton refusé par la DGI (jeton non valide). » · « Le service e-MECeF se déclare indisponible. » · « L'IFU du jeton (…) n'est pas celui de l'entreprise (…) : corrigez l'IFU ou utilisez le jeton de cet IFU. » · succès « Le service e-MECeF répond et accepte le jeton. » → résumé « Configuration valide. » Affichage : bloc vert/rouge avec le résumé, puis une ligne par contrôle (« OK — … » / « À corriger — … ») et « Le test ne crée aucune facture : il vérifie la configuration puis lit l'état du service e-MECeF. » **Le jeton n'est jamais affiché ni journalisé** (ni dans le résultat, ni dans une exception). ⚠️ Chemin `/info/status` et champs `tokenValid`, `status`, `ifu` : non confirmés par la DGI.

**Droits :** `manage-parametres` (écritures, test, effacement). **Audit :** `company_settings.mecef_updated` si le mode, l'adresse ou le jeton changent (sans valeur) ; `company_settings.updated` si l'IFU change.

**Stockage :** colonnes `mecef_mode`, `mecef_api_url`, `mecef_operateur_id`, `mecef_operateur_nom`, `mecef_jeton_encrypted` (cast `encrypted`), `ifu` (même colonne que « Données de l'Entreprise »).

**Synchronisation vers le poste :** le tirage sert `mecef_actif` (dérivé), `mecef_mode`, `mecef_api_url`, `mecef_operateur_id`, `mecef_operateur_nom`, `mecef_jeton_configure` (booléen) ; **jamais le jeton**. Le poste écrit mode, IFU, adresse, opérateur par une demande `entreprise` ; clés `mecef*` absentes = réglage conservé (un poste ancien n'efface rien).

**Poste (relu : `agrierp_flutter/lib/features/parametres/reglages_ferme_ui.dart`, `PageFacturationEmecef`) :** même onglet, mêmes libellés, mêmes deux préréglages ; le jeton est seulement « •••••••••••• » ou « Aucun jeton enregistré », avec « Secret : chiffré sur le serveur, jamais affiché, jamais envoyé aux postes. Il se saisit, se remplace, s'efface et se teste sur le web (« Tester la configuration »). » ; **pas de bouton « Tester »** ; enregistrement refusé tant que l'identité de la ferme n'est pas synchronisée (« Identité de la ferme non synchronisée : lancez une synchronisation avant de régler la facturation normalisée. »).

**Tests de garde d'AgriERP à reprendre :** serveur `agrierp_laravel/tests/Feature/MecefModeReglageTest.php` (l'écran enregistre mode et champs, chiffre le jeton ; IFU 13 chiffres exigé en e-MECeF et rien d'écrit sinon ; demande d'un poste ancien sans clés mecef laisse le réglage), `agrierp_laravel/tests/Feature/MecefTestConfigurationTest.php` (`Http::fake` : tous les messages ci-dessus, **jamais** `POST /invoice`) ; poste `agrierp_flutter/test/mecef_emecef_poste_test.dart`, `agrierp_flutter/test/mecef_tirage_test.dart`, `agrierp_flutter/test/reglages_ferme_poste_test.dart`.

### a.2 PROMPT — Écran (a) WEB

~~~~text
[Colle P0 ici.]

OBJECTIF : construire l'onglet « Facturation normalisée (e-MECeF) » du hub Paramètres de LogiALVIA, à l'identique de la spécification a.1 de /home/user/agrierp/docs/logialvia/42_CONFIG_MECEF_SMTP_LOGO_FAVICON.md.

PRÉREQUIS : docs/MECEF_DECISIONS.md de LogiALVIA existe (voir 41_MECEF_EMECEF.md, tâche M1) ; les colonnes mecef_* de company_settings (tâche M2) existent ; MecefMode et MecefReglage existent. Sinon, arrête-toi.

RÉFÉRENCES (lecture seule) : /home/user/agrierp/agrierp_laravel/app/Livewire/Parametres/FacturationEmecef.php ; resources/views/livewire/parametres/facturation-emecef.blade.php ; app/Services/Mecef/MecefReglageService.php, MecefConfigurationTesteur.php, MecefReglage.php ; app/Support/MecefMode.php ; tests/Feature/MecefModeReglageTest.php, MecefTestConfigurationTest.php.

TÂCHES
1. Service MecefReglageService (règles, messages, `enregistrer`, `effacerJeton`, `colonnes`, `aChange`) : reprise adaptée ; `verifierIfu` refuse AVANT toute écriture un IFU qui n'a pas 13 chiffres en mode e-MECeF.
2. Service MecefConfigurationTesteur : reprise adaptée, mêmes contrôles locaux puis UN seul GET {adresse}/info/status ; messages exacts de a.1 ; teste la saisie sans l'enregistrer ; jamais le jeton ni le message d'une exception dans le résultat.
3. Composant Livewire FacturationEmecef + vue Blade : champs, libellés, notes, boutons, toasts et bloc de résultat EXACTS de a.1. Le jeton n'est JAMAIS relu : l'état Livewire ne le porte que le temps de la frappe et il est vidé à l'enregistrement. Le champ « Adresse » et le jeton n'apparaissent qu'en mode e-MECeF.
4. `mount()` : `abort_unless(Gate::allows('manage-parametres'), 403)` (écart assumé par rapport à AgriERP, à consigner dans le CLAUDE.md : `// ECART_DELIBERE`). Chaque action : `$this->authorize('manage-parametres')`.
5. Onglet `facturation` dans le hub, placé juste avant « Email (SMTP) », et renvoi depuis « Données de l'Entreprise » (« Le mode de facturation normalisée, le jeton et l'adresse de l'API e-MECeF se règlent dans l'onglet Facturation normalisée (e-MECeF). »).
6. Audit : `company_settings.mecef_updated` (sans valeur), `company_settings.updated` quand l'IFU change.
7. Corrige les messages de la passerelle qui citent « Paramètres, Données de l'Entreprise » : le jeton se règle dans l'onglet « Facturation normalisée (e-MECeF) ».
8. Tests (équivalents de MecefModeReglageTest et MecefTestConfigurationTest) : `Http::fake` pour chaque message du Testeur ; assertions que le jeton est chiffré en base (valeur brute ≠ clair), absent de la réponse, absent du journal d'audit, absent des logs ; que `POST /invoice` n'est JAMAIS appelé par le test ; qu'un utilisateur sans manage-parametres reçoit 403 à l'ouverture et à chaque action.

CRITÈRES D'ACCEPTATION : tous les libellés et messages de a.1 présents mot pour mot (un test lit la vue et la liste) ; IFU de 12 chiffres refusé en e-MECeF, aucune colonne écrite ; « Effacer » demande confirmation et le dit ; « Tester la configuration » ne change aucune donnée ; jeton jamais dans /api/sync/pull ; suite Feature verte.
INTERDITS : afficher ou journaliser le jeton ; appeler POST /invoice depuis le test de configuration ; appeler la vraie DGI depuis un test ; présenter les adresses comme confirmées.
PIÈGES PAYÉS : adresse d'essai appelée « production » ; jeton envoyé au poste dans une file locale ; la saisie non enregistrée testée alors que l'écran dit le contraire.
~~~~

### a.3 PROMPT — Écran (a) POSTE

~~~~text
[Colle P0 ici.]

OBJECTIF : l'onglet « Facturation normalisée (e-MECeF) » du poste de LogiALVIA, fidèle à la vue web (a.1), SANS jeton ni bouton « Tester ».

PRÉREQUIS : l'onglet web (a.2) existe et passe ; l'appairage et la synchronisation du poste fonctionnent ; le tirage de company_settings sert mecef_actif, mecef_mode, mecef_api_url, mecef_operateur_id, mecef_operateur_nom, mecef_jeton_configure ; le poste sait envoyer une demande `entreprise`.

RÉFÉRENCES (lecture seule) : /home/user/agrierp/agrierp_flutter/lib/features/parametres/reglages_ferme_ui.dart (PageFacturationEmecef), reglages_ferme_repository.dart (enregistrerMecef), parametres_generaux_screen.dart (ongletFacturationEmecef) ; tests mecef_emecef_poste_test.dart, mecef_tirage_test.dart, reglages_ferme_poste_test.dart.

TÂCHES
1. Dans logialvia_app/lib/administration/presentation/screens/parametres_generaux_screen.dart : retirer la bascule locale `mecefActif` / `mecefUrl` / `mecefNim` et le widget `_JetonMecef` (le jeton quitte le poste : voir 41_MECEF_EMECEF.md, M5) ; ajouter l'onglet « Facturation normalisée (e-MECeF) » dans le même ordre que le web.
2. Champs : mode (liste de 3 valeurs, mêmes libellés), IFU (13 chiffres exigés en e-MECeF, mêmes messages), adresse (mode e-MECeF, deux préréglages), opérateur (id, nom) ; jeton : texte d'état seulement (« •••••••••••• » ou « Aucun jeton enregistré ») et la phrase « Secret : chiffré sur le serveur… ».
3. Enregistrement = DEMANDE `entreprise` rejouée par le serveur (même service que le web) ; un envoi sans clé mecef* ne change rien ; refus en français si l'identité de la ferme n'est pas encore synchronisée.
4. Droits : réservé à qui a manage-parametres ; lecture seule sinon.
5. Test qui LIT la vue Blade et compare titres, libellés, notes et messages (modèle : agrierp_flutter/test/email_smtp_blade_test.dart) ; test que la demande ne contient JAMAIS un jeton (inspection de la charge) ; test que le poste affiche le bon état quand mecef_jeton_configure vaut 0 ou 1.

CRITÈRES D'ACCEPTATION : aucun champ de saisie de jeton au poste ; aucune clé `jeton` dans la demande ; le poste hors ligne enregistre la demande et la montre « à envoyer » ; libellés identiques au web (test) ; flutter analyze et flutter test verts.
INTERDITS : coffre ou base locale pour le jeton ; appel réseau vers la DGI ; édition de app_database.g.dart.
~~~~

---

## (b) Configuration e-mail SMTP : envoi et test

### b.1 Spécification (relue : `agrierp_laravel/app/Livewire/Parametres/EmailSmtp.php`, `resources/views/livewire/parametres/email-smtp.blade.php`, `app/Models/CompanySetting.php` `applyMailConfig()`/`adresseExpedition()`, `agrierp_flutter/lib/features/parametres/onglet_email_smtp.dart`, `lib/core/config/parametres_smtp.dart`, `envoi_email.dart`, `envoi_email_test.dart`)

**Ce que c'est et à quoi ça sert (une seule configuration pour toute l'application web) :** relances clients par e-mail (`agrierp_laravel/app/Services/RelanceClientService.php`, `Ventes/RelancesClients`), « Contactez l'Éditeur » (`app/Livewire/Contact/Index.php`, `app/Http/Controllers/Api/ContactController.php`, `app/Mail/ContactEditorMail.php`), notifications et réinitialisation des mots de passe. Chaque envoi appelle `CompanySetting::current()->applyMailConfig()` : si `smtp_host` est vide, **rien n'est changé** et Laravel utilise `MAIL_MAILER` (`.env.example` : `MAIL_MAILER=log`, `config/mail.php` : défaut `log`).

> ⚠️ **PIÈGE `MAIL_MAILER=log`.** Avec `log` (défaut) et aucun hôte SMTP enregistré, `Mail::send` **réussit** en écrivant le message dans `storage/logs` : l'application croit avoir envoyé. `RelanceClientService::envoyerEmail` n'a aucun garde : la relance est tracée « envoyée » (`journaliser`, audit `customer_reminder.sent_email`) alors qu'**aucun e-mail n'est parti**. Dans LogiALVIA : (1) en production, `MAIL_MAILER=smtp` ou refus explicite d'envoyer quand aucun hôte n'est enregistré (« Aucun serveur d'e-mail n'est configuré : Paramètres > Email (SMTP). ») ; (2) garder `log` pour le développement et les tests ; (3) ne jamais écrire la trace d'une relance sans envoi réel.

**Écran web (titre, icône `mail`) :** « Email (SMTP) » — « Serveur d'envoi des e-mails de la ferme (relances, notifications, réinitialisation des mots de passe). Une seule configuration pour toute l'application. » Deux cartes.

Carte « **Serveur SMTP** » :

| Champ | Libellé exact | Règle | Message exact (jeu d'attributs du composant) |
|---|---|---|---|
| `smtpHost` | « Hôte SMTP * », indice « ex : smtp.gmail.com » | `required|string|max:150` | « Le champ hôte SMTP est obligatoire. » / « Le champ hôte SMTP ne doit pas dépasser 150 caractères. » |
| `smtpPort` | « Port * », indice « 587 » (défaut 587) | `required|integer|min:1|max:65535` | « Le champ port est obligatoire. » / « Le champ port doit être un nombre entier. » / « Le champ port doit être au moins égal à 1. » / « Le champ port ne doit pas dépasser 65535. » |
| `smtpSecurity` | « Sécurité » : TLS · SSL · Aucune (valeurs `tls`, `ssl`, ``) | `nullable|in:tls,ssl` | « La valeur sélectionnée pour le champ sécurité n'est pas valide. » |
| `smtpUser` | « Utilisateur SMTP », indice « ex : notifications@fermeolouwachegoun.com » | `nullable|string|max:150` | — |
| `smtpPassword` | « Mot de Passe SMTP », indice « Laisser vide pour conserver le mot de passe actuel » | `nullable|string|max:255` ; **vide = inchangé** | — |
| `fromAddress` | « Adresse d'Expédition », indice = e-mail de contact ou « ex : contact@fermeolouwachegoun.com » | `nullable|email|max:150` | « Le champ adresse d'expédition doit être une adresse e-mail valide. » |

État du mot de passe : « Mot de passe enregistré » (icône `lock`, vert) + lien « Effacer le mot de passe » ; sinon « Aucun mot de passe enregistré » ; sous le champ : « Chiffré en base — jamais réaffiché en clair une fois enregistré, jamais envoyé aux postes. » Effacement : modale `x-modal-confirm-hard-delete` (nom `effacer-mot-de-passe-smtp`, « Le mot de passe SMTP enregistré », avertissement « Si le serveur d'envoi exige une authentification, aucun e-mail ne partira plus tant qu'un nouveau mot de passe n'aura pas été saisi. »). Bouton « Enregistrer la Configuration SMTP ». Toasts : « Configuration SMTP enregistrée avec succès. » · « Mot de passe SMTP effacé. »

Expéditeur effectif : `adresseExpedition()` = adresse d'expédition SMTP, sinon e-mail de contact de l'entreprise ; nom d'expéditeur = raison sociale.

Carte « **Envoyer un e-mail de test** » : « Le test emploie la configuration **enregistrée** : enregistrez d'abord une modification avant de la tester. Un e-mail part réellement. » Champ « Destinataire du test » (indice « Envoyer un e-mail de test à... », préremplie avec l'adresse d'expédition ; règle `required|email`, attribut « destinataire du test ») ; bouton « Envoyer un e-mail de test » (icône `send`). Comportement : sans hôte enregistré → toast d'erreur « Enregistrez d'abord l'hôte SMTP avant d'envoyer un e-mail de test. » ; sinon `applyMailConfig()` puis `Mail::raw` réel, sujet « LogiAgriERP — Test de configuration SMTP » (à renommer LogiALVIA), corps « Ceci est un e-mail de test envoyé depuis LogiAgriERP (Paramètres > Email (SMTP)) — configuration SMTP validée avec succès. » ; succès → « E-mail de test envoyé à {adresse}. » (audit `company_settings.smtp_tested`) ; échec → « Échec de l'envoi — vérifiez la configuration SMTP ({message technique}). » Note de la carte : « Chaque poste Windows a son propre réglage SMTP (Paramètres > Email (SMTP) du poste) : son mot de passe reste dans le coffre du système de ce poste et ne transite jamais par le serveur. » ⚠️ Écart relevé : le toast d'échec reprend `$e->getMessage()` tel quel ; LogiALVIA doit le **passer par un filtre** (jamais le mot de passe ; l'hôte et la réponse du serveur SMTP sont acceptables).

**Droit :** `manage-parametres` à l'ouverture (`abort_unless`) et à chaque écriture. **Audit :** `company_settings.smtp_updated`, `company_settings.smtp_tested`, `company_settings.smtp_password_cleared` (poste : « Configuration SMTP modifiée », « Test SMTP envoyé », « Mot de passe SMTP effacé »). **Stockage :** colonnes `smtp_host`, `smtp_port`, `smtp_security`, `smtp_user`, `smtp_from_address`, `smtp_password_encrypted` (cast `encrypted`). **Jamais servi au poste** (ticket 14.84).

**Poste :** réglages **locaux** par poste (clés `smtp.hote`, `smtp.port`, `smtp.securite`, `smtp.utilisateur`, `smtp.expediteur` dans `app_settings`, jamais synchronisées) ; **mot de passe au coffre du système** (`flutter_secure_storage`, clé `agrierp.smtp.mot_de_passe`), **jamais en base**, jamais synchronisé ; même onglet, mêmes libellés, mêmes messages (prouvé par `agrierp_flutter/test/email_smtp_blade_test.dart` : textes, choix de sécurité dans l'ordre du web, toasts, modale d'effacement, messages de validation, place de l'onglet). L'envoi d'essai et les relances partent **du poste lui-même** par le paquet `mailer` (`envoi_email_test.dart`, `envoi_email.dart`), **jamais par le serveur** ; **hors ligne, l'envoi est refusé en le disant** (« Poste hors ligne : l'e-mail exige le réseau. Réessayez une fois le poste connecté. ») ; refus avant envoi : « L'adresse e-mail du destinataire n'est pas valide. » · « Enregistrez d'abord l'hôte SMTP (Paramètres > Email (SMTP)) avant d'envoyer un e-mail. » · « Renseignez l'adresse d'expédition (ou l'utilisateur SMTP) avant d'envoyer un e-mail. » ; délai d'envoi 30 s ; la trace d'une relance n'est écrite **qu'après** un envoi réussi. Expéditeur du poste : adresse d'expédition, sinon e-mail de contact descendu du serveur, sinon utilisateur SMTP.

**Tests de garde d'AgriERP :** serveur `agrierp_laravel/tests/Feature/ParametresConfigurationsTest.php` (mot de passe jamais en clair en base, champ vidé après enregistrement, audit, ordre des onglets) ; poste `agrierp_flutter/test/email_smtp_blade_test.dart`, `agrierp_flutter/test/parametres_smtp_test.dart` (seules les clés de `clesReglages` s'écrivent dans `app_settings`), `agrierp_flutter/test/relances_poste_test.dart`, `agrierp_flutter/test/administration_locale_test.dart`.

### b.2 PROMPT — Écran (b) WEB

~~~~text
[Colle P0 ici.]

OBJECTIF : l'onglet « Email (SMTP) » du hub Paramètres de LogiALVIA avec « Envoyer un e-mail de test », à l'identique de b.1 de /home/user/agrierp/docs/logialvia/42_CONFIG_MECEF_SMTP_LOGO_FAVICON.md, et l'usage de cette configuration par les envois réels (relances clients, « Contactez l'Éditeur », réinitialisation de mot de passe).

RÉFÉRENCES (lecture seule) : /home/user/agrierp/agrierp_laravel/app/Livewire/Parametres/EmailSmtp.php ; resources/views/livewire/parametres/email-smtp.blade.php ; app/Models/CompanySetting.php (applyMailConfig, adresseExpedition) ; app/Services/RelanceClientService.php ; app/Livewire/Contact/Index.php ; app/Http/Controllers/Api/ContactController.php ; app/Mail/ContactEditorMail.php ; config/mail.php ; tests/Feature/ParametresConfigurationsTest.php.

TÂCHES
1. Colonnes smtp_host, smtp_port (défaut 587), smtp_security, smtp_user, smtp_from_address, smtp_password_encrypted (cast `encrypted`) dans la table des réglages d'entreprise (ligne unique) ; migration + modèle.
2. Composant Livewire EmailSmtp + vue : champs, libellés, indices, règles et messages EXACTS de b.1 (passe le jeu d'attributs au validateur : « hôte SMTP », « port », « sécurité », « utilisateur SMTP », « mot de passe SMTP », « adresse d'expédition », « destinataire du test »). `mount()` : abort_unless(manage-parametres). Champ mot de passe : JAMAIS rempli depuis la base ; vide à l'enregistrement = inchangé ; « Effacer le mot de passe » = geste explicite avec modale de confirmation (par événement).
3. `applyMailConfig()` : applique hôte, port, chiffrement, utilisateur, mot de passe, expéditeur ; sans hôte, ne change rien. Vérifie que la configuration appliquée est BIEN utilisée par l'envoi (les mailers de Laravel sont mis en cache par processus : teste un envoi après changement de configuration dans le même processus ; si un worker de file est utilisé, purge le mailer — `Mail::forgetMailers()` — avant l'envoi).
4. « Envoyer un e-mail de test » RÉEL (jamais une simulation de succès) : configuration ENREGISTRÉE ; messages exacts de b.1 ; le message technique de l'échec est filtré (jamais le mot de passe).
5. Garde contre le piège MAIL_MAILER=log : en production, un envoi réel (relance, Contactez l'Éditeur) sans hôte enregistré est REFUSÉ avec « Aucun serveur d'e-mail n'est configuré : Paramètres > Email (SMTP). » ; la trace d'une relance n'est écrite qu'APRÈS un envoi réussi.
6. Audit : smtp_updated, smtp_tested, smtp_password_cleared (sans valeur). Libellés français ajoutés au tableau d'audit du poste.
7. Documente MAIL_MAILER=log (développement/tests) et smtp (production) dans le CLAUDE.md et le guide de déploiement.
8. Tests : mot de passe chiffré en base (valeur brute ≠ clair), champ vidé après enregistrement, vide = inchangé, effacement explicite, test d'envoi avec `Mail::fake()` ET un test d'intégration contre un serveur SMTP local jetable si le dépôt en dispose (sinon dit qu'il n'a pas été joué), droit 403, audit, jeu de messages de validation, refus d'envoi sans hôte en production.

CRITÈRES D'ACCEPTATION : libellés/messages identiques à b.1 (test qui lit la vue) ; le mot de passe n'apparaît ni dans le HTML rendu, ni dans l'état Livewire sérialisé, ni dans /api/sync/pull, ni dans le journal, ni dans le toast d'échec ; un e-mail de test part vraiment avec une configuration valide (essai manuel documenté) ; relance sans hôte : refusée, aucune ligne `customer_reminders` écrite ; suite verte.
INTERDITS : réafficher le mot de passe ; l'envoyer au poste ; simuler un succès ; saisir le SMTP à deux endroits (AgriERP l'a payé : deux jeux de valeurs).
PIÈGES PAYÉS : configuration SMTP saisie à DEUX endroits ; `TLS` vs `tls` (le transport attend des minuscules) ; champ vide écrasant le mot de passe et coupant tous les e-mails sans rien dire ; MAIL_MAILER=log qui « envoie » dans un fichier.
~~~~

### b.3 PROMPT — Écran (b) POSTE

~~~~text
[Colle P0 ici.]

OBJECTIF : l'onglet « Email (SMTP) » du poste de LogiALVIA, fidèle à la vue web (b.1), avec réglages LOCAUX, mot de passe au coffre, envoi d'essai réel et envoi des relances par le SMTP du poste.

PRÉREQUIS : l'onglet web (b.2) passe ; flutter_secure_storage est déjà une dépendance ; ajouter `mailer` et `connectivity_plus` (versions d'AgriERP : /home/user/agrierp/agrierp_flutter/pubspec.yaml).

RÉFÉRENCES (lecture seule) : /home/user/agrierp/agrierp_flutter/lib/features/parametres/onglet_email_smtp.dart ; lib/core/config/parametres_smtp.dart, envoi_email.dart, envoi_email_test.dart ; test/email_smtp_blade_test.dart, parametres_smtp_test.dart, relances_poste_test.dart ; lib/features/parametres/parametres_generaux_screen.dart (ongletEmailSmtp).

TÂCHES
1. Retire de logialvia_app/lib/administration/presentation/screens/parametres_generaux_screen.dart le bloc « Configuration Email (SMTP) » de l'onglet Données de l'Entreprise et les colonnes smtp* de `ParametresEntreprise` (le poste ne stocke plus le SMTP en base d'entreprise) ; migration Drift qui reprend l'existant vers `app_settings` (hôte, port, sécurité) sans jamais toucher à un secret.
2. ParametresSmtp : réglages dans la table de réglages locaux (clés smtp.hote, smtp.port, smtp.securite, smtp.utilisateur, smtp.expediteur), NON synchronisés ; mot de passe UNIQUEMENT au coffre (clé dédiée) ; champ vide = inchangé ; effacement = geste explicite avec modale.
3. Onglet « Email (SMTP) » : mêmes cartes, libellés, indices, messages, toasts que le web (b.1) ; mêmes trois choix de sécurité dans le même ordre ; modale d'effacement reprenant celle du web.
4. EnvoiEmailTest : envoi RÉEL des réglages ENREGISTRÉS, mot de passe repris au coffre à l'envoi ; hors ligne : refus immédiat avec « Poste hors ligne : l'e-mail exige le réseau. Réessayez une fois le poste connecté. » ; mêmes messages que le web ; délai 30 s.
5. EnvoiEmail pour les relances clients : même configuration, mêmes refus ; la trace d'une relance n'est écrite QU'APRÈS un envoi réussi.
6. Tests : un test qui LIT la vue Blade et compare textes, choix de sécurité, toasts, modale et messages de validation (modèle : email_smtp_blade_test.dart) ; un garde-fou qui lit parametres_smtp.dart et prouve que seules les clés de `clesReglages` s'écrivent en base ; test hors ligne ; test d'envoi avec un envoyeur injecté (aucun réseau).

CRITÈRES D'ACCEPTATION : le mot de passe n'est ni en base, ni dans la file de synchronisation, ni dans un journal, ni relu à l'écran ; libellés identiques au web ; hors ligne : message exact, aucune attente de délai ; une copie du fichier SQLite ne donne pas accès à la boîte mail ; flutter analyze et flutter test verts.
INTERDITS : synchroniser le SMTP du poste avec le serveur ; envoyer l'e-mail du poste par le serveur ; mot de passe en base.
~~~~

---

## (c) Logo de l'entreprise

### c.1 Spécification (relue : `agrierp_laravel/resources/views/livewire/parametres/donnees-entreprise.blade.php`, `app/Livewire/Parametres/DonneesEntreprise.php`, `app/Services/EntrepriseService.php`, `app/Http/Controllers/Api/SyncController.php` `fichierEntreprise`, `agrierp_flutter/lib/core/config/fichiers_entreprise.dart`)

**Zone web (onglet « Données de l'Entreprise », carte « Logo de l'Entreprise »)** : cadre en pointillés (`border-2 border-dashed`, survol vert), icône Material `add_photo_alternate` (40 px), texte « **Glisser-déposer ou cliquer pour choisir un logo** » (remplacé par le nom du fichier choisi), consigne « **PNG carré, fond transparent recommandé, max 2 Mo** » ; aperçu du logo actuel (hauteur 48 px, `alt="Logo actuel"`) au-dessus de l'icône quand il existe. Entrée `<input type="file" accept="image/*" class="hidden">` liée à `wire:model="logoFile"`.

**Validation web :** `logoFile` : `nullable|image|max:2048` (2 048 Ko = « 2 Mo »). `image` de Laravel 12 accepte **jpg, jpeg, png, gif, bmp, webp** (SVG exclu). Messages (attribut « logo » de `lang/fr/validation.php`) : « Le champ logo doit être une image. » · « Le fichier logo ne doit pas dépasser 2048 kilo-octets. » · échec de téléversement : « Le téléversement du fichier logo a échoué. »

**Stockage :** `Storage::disk('public')`, dossier `company`, nom **généré** (`store('company', 'public')`, jamais le nom d'origine) ; colonne `company_settings.logo_path` ; servi par le lien `public/storage` (`php artisan storage:link`). Droit `manage-parametres` ; audit `company_settings.updated` (ne dit pas qu'un logo a changé).

**Synchronisation vers le poste (ticket AUT-2) :** le tirage sert `logo_path` ; le poste télécharge `GET /api/sync/company-file/logo` quand le chemin change (`agrierp_laravel/routes/api.php`, `SyncController::fichierEntreprise` : 404 « Aucun fichier. » si absent ; réservé aux comptes authentifiés) ; le poste garde le fichier **hors base, hors réseau** (`<dossier de données>/entreprise/logo.<ext>` + `logo.source` = chemin du serveur). Un logo choisi au poste est enregistré **tout de suite** puis envoyé au serveur dans la demande `entreprise` (`logoB64`, `EntrepriseService::fichiersDepuisBase64` : mêmes limites que le web, 2 048 Ko ; refus « Le logo doit être une image (png, jpg, gif, bmp ou webp). » / « Le logo ne doit pas dépasser 2048 Ko. » ; ⚠️ la boucle du service écrit le logo AVANT de valider le favicon : si le favicon est refusé, le logo déjà rangé sur le disque reste orphelin — LogiALVIA valide les deux fichiers avant d'en écrire un). Poste : zone « Cliquer pour choisir un logo » (sélecteur de fichier, **pas** de glisser-déposer), formats png/jpg/jpeg/gif/bmp/webp.

### c.2 Écarts et défauts relevés dans AgriERP (à NE PAS reproduire, à corriger dans LogiALVIA)

1. **Écart n° 1 — le logo téléversé ne sert à rien au web.** Recherche faite dans `agrierp_laravel/app` et `agrierp_laravel/resources` : `logo_path` n'est lu que par l'écran de réglage (aperçu) et par le tirage du poste. L'en-tête des PDF web (`agrierp_laravel/resources/views/exports/layout.blade.php` via `PdfExportService` : `public_path('assets/images/logo.png')`), l'attestation (`AttestationService` : `resource_path('attestation/images/logo-ferme.png')`), la page de connexion et le menu utilisent des **fichiers fixes**. **Seul le poste** utilise le logo choisi, pour ses PDF (`FichiersEntreprise.logoPourPdf`, PNG ou JPEG seulement, repli sur le logo embarqué) : le poste est en avance sur le web, contre la doctrine (le web est le maître). **LogiALVIA doit utiliser le logo téléversé partout dès le web** : menu/barre latérale, page de connexion, en-tête de la facture PDF et des documents (attestations, bons, rapports), avec repli sur le logo d'installation.
2. **« Glisser-déposer » n'est pas câblé** : la zone est un `<label>` autour d'un `<input type="file" class="hidden">` et **aucun gestionnaire `dragover`/`drop` n'existe** dans la vue (recherche faite). Le texte promet un geste que la vue ne traite pas (**à vérifier dans un navigateur** : un dépôt de fichier sur la zone ouvre en général le fichier au lieu de le téléverser). LogiALVIA : soit câbler un vrai dépôt (Alpine `@dragover.prevent`, `@drop.prevent`, transmission du fichier à Livewire), soit retirer « Glisser-déposer » du texte.
3. **Pas de suppression ni de remplacement propre** : aucun bouton « Supprimer le logo » ; remplacer un logo **ne supprime pas l'ancien fichier** (fichiers orphelins qui s'accumulent dans `storage/app/public/company`).
4. **Messages différents selon la porte d'entrée** : le formulaire web donne « Le champ logo doit être une image. » ; le poste et l'API donnent « Le logo doit être une image (png, jpg, gif, bmp ou webp). » (chaîne de `EntrepriseService::fichiersDepuisBase64`). La doctrine veut les mêmes mots : à unifier (une constante de service).
5. **Aucun test web du téléversement du logo** : seul `agrierp_laravel/tests/Feature/SyncReglagesTest.php` couvre le chemin du poste (`test_le_logo_et_le_favicon_du_poste_sont_ranges_comme_au_web_et_servis_au_poste`, `test_un_logo_qui_n_est_pas_une_image_ou_trop_gros_est_refuse`).
6. Le moteur PDF du poste ne lit que PNG et JPEG : un logo GIF/BMP/WebP est affiché à l'écran mais le PDF garde le logo d'installation (test `reglages_ferme_poste_test.dart`).

### c.3 PROMPT — Écran (c) WEB

~~~~text
[Colle P0 ici.]

OBJECTIF : la carte « Logo de l'Entreprise » de l'onglet « Données de l'Entreprise » de LogiALVIA, ET l'utilisation réelle du logo partout où il doit apparaître. Spécification : c.1 et c.2 de /home/user/agrierp/docs/logialvia/42_CONFIG_MECEF_SMTP_LOGO_FAVICON.md.

RÉFÉRENCES (lecture seule) : /home/user/agrierp/agrierp_laravel/resources/views/livewire/parametres/donnees-entreprise.blade.php ; app/Livewire/Parametres/DonneesEntreprise.php ; app/Services/EntrepriseService.php (fichiersDepuisBase64, TAILLES_FICHIERS) ; app/Services/PdfExportService.php ; resources/views/exports/layout.blade.php ; tests/Feature/SyncReglagesTest.php. LogiALVIA : colonnes `cheminLogo` / `cheminFavicon` existent déjà dans logialvia_app/lib/administration/data/tables/parametres_entreprise_table.dart (jamais alimentées : l'écran actuel dit « Le dépôt de logo sera disponible avec le module d'impression »).

TÂCHES
1. Colonne `logo_path` (réglages d'entreprise) ; migration.
2. Service unique EntrepriseService::enregistrerFichier(genre, fichier) : validation, rangement sur le disque public, dossier `company`, nom GÉNÉRÉ (jamais le nom d'origine), suppression de l'ancien fichier du même genre APRÈS l'écriture réussie ; service `supprimerFichier(genre)` ; constantes de messages communes au web, à l'API et au poste.
3. Carte web : zone en pointillés, icône `add_photo_alternate`, « Glisser-déposer ou cliquer pour choisir un logo » (remplacé par le nom du fichier choisi), « PNG carré, fond transparent recommandé, max 2 Mo », aperçu du logo actuel, bouton « Remplacer » (reclic sur la zone) et bouton « Supprimer le logo » avec confirmation par modale (événement). Le glisser-déposer doit FONCTIONNER (Alpine @dragover.prevent / @drop.prevent → upload Livewire) et se tester avec Playwright (`setInputFiles` ET un vrai événement `drop`).
4. Validation : `nullable|image|max:2048` ; messages exacts de c.1 ; refus d'un SVG (script embarqué) ; vérifie le contenu réel (`getimagesizefromstring`), pas seulement l'extension.
5. Droit manage-parametres à l'ouverture et à chaque écriture. Audit : `company_settings.logo_updated` et `company_settings.logo_deleted` (nouveaux : écart assumé par rapport à AgriERP qui ne distingue pas ; sans valeur).
6. UTILISATION (obligatoire, c'est l'écart n° 1) : un helper unique `logoEntreprise()` (URL du logo téléversé, repli sur l'asset d'installation) utilisé par le menu/la barre latérale, la page de connexion, l'en-tête de la facture PDF et de tous les documents PDF (attestations, bons, rapports) ; le moteur PDF reçoit un chemin disque lisible ou une image encodée, jamais une URL distante ; paramètre de cache (`?v=<updated_at>`) pour que le changement se voie tout de suite.
7. Tirage vers le poste : `logo_path` dans `company_settings` du tirage ; `GET /api/sync/company-file/logo` (authentifié, 404 « Aucun fichier. » si absent, jamais d'autre chemin que celui de la colonne).
8. Tests : téléversement valide (fichier présent sur le disque, colonne écrite, ancien fichier supprimé), refus d'un fichier non image, d'un fichier > 2 048 Ko, d'un SVG, d'un utilisateur sans manage-parametres (403), suppression (fichier et colonne effacés, repli sur le logo d'installation), audit, présence du logo dans le HTML du menu, de la connexion et dans le PDF d'une facture (octets de l'image présents), endpoint company-file (200 / 404).

CRITÈRES D'ACCEPTATION : libellés mot pour mot ; le logo téléversé apparaît dans le menu, la connexion, la facture PDF et au moins un autre document (tests) ; changement visible immédiatement ; aucun fichier orphelin après remplacement/suppression ; le glisser-déposer marche (test navigateur) ; suite verte.
INTERDITS : garder le nom d'origine du fichier ; accepter un SVG ; stocker le logo en base ; afficher « Glisser-déposer » sans geste réel.
~~~~

### c.4 PROMPT — Écran (c) POSTE

~~~~text
[Colle P0 ici.]

OBJECTIF : la zone « Logo de l'Entreprise » du poste de LogiALVIA, fidèle à la vue web (c.1 et c.3) : choix, aperçu, remplacement, suppression, synchronisation, usage dans les PDF et l'interface.

PRÉREQUIS : l'écran web (c.3) passe ; le tirage sert `logo_path` ; `GET /api/sync/company-file/{genre}` existe ; ajouter `file_picker` (version d'AgriERP : /home/user/agrierp/agrierp_flutter/pubspec.yaml).

RÉFÉRENCES (lecture seule) : /home/user/agrierp/agrierp_flutter/lib/core/config/fichiers_entreprise.dart ; lib/features/parametres/reglages_ferme_ui.dart (_depotFichier, choisirImage) ; reglages_ferme_repository.dart ; lib/core/sync/sync_engine.dart (_tirerFichiersEntreprise, envoi de logoB64) ; lib/core/export/document_officiel.dart (chargerLogo) ; test/reglages_ferme_poste_test.dart.

TÂCHES
1. Classe FichiersEntreprise (dossier de données du poste, sous-dossier `entreprise`, fichiers `logo.<ext>` et `logo.source`) : lire, enregistrer (efface l'ancien d'une autre extension), effacer, sourceServeur ; `valider(genre, nom, octets)` avec les MÊMES mots que le serveur (constantes communes) ; tailleMax logo = 2 048 Ko ; formats png, jpg, jpeg, gif, bmp, webp.
2. Zone de l'écran : icône add_photo_alternate, texte « Cliquer pour choisir un logo » (ou « Glisser-déposer ou cliquer… » si le glisser-déposer est réellement géré sur Windows : sinon, texte honnête), consigne « PNG carré, fond transparent recommandé, max 2 Mo », aperçu, remplacement, suppression avec confirmation. Fichier gardé TOUT DE SUITE sur le poste (il reste autonome) ; la demande `entreprise` n'emporte que le nom, les octets partent à l'envoi (`logoB64`) ; refus AVANT d'écrire (format, taille) avec le message du serveur.
3. Synchronisation : à chaque tirage, si `logo_path` du serveur diffère du `logo.source` mémorisé, télécharger `/api/sync/company-file/logo` et remplacer ; le même chemin ne se retélécharge pas ; hors ligne : on garde l'ancien sans erreur.
4. Usage : barre latérale/connexion du poste et en-tête de tous les PDF (document officiel) utilisent le logo choisi ; le moteur PDF ne lit que PNG et JPEG : pour GIF/BMP/WebP, l'écran l'affiche et le PDF garde le logo d'installation, ET l'écran le DIT (« Ce format s'affiche à l'écran ; les documents PDF utiliseront le logo d'origine »).
5. Test qui LIT la vue Blade : mêmes textes (hors la phrase « Glisser-déposer » si non gérée, écart consigné `// ECART_DELIBERE`) ; tests : fichier gardé tout de suite, refus d'un format inconnu et d'un fichier trop gros sans rien écrire, nouveau chemin du serveur → téléchargement, même chemin → pas de retéléchargement, PDF avec le logo choisi (PNG) et avec repli (GIF).

CRITÈRES D'ACCEPTATION : aucun octet de logo en base Drift ; le fichier survit à un redémarrage ; un logo posé au web arrive au poste à la synchronisation suivante ; un logo choisi au poste arrive au web et aux autres postes ; flutter analyze et flutter test verts.
INTERDITS : nom d'origine du fichier ; octets du logo dans la base ou dans la file de synchronisation en dehors de la demande ; message d'erreur différent de celui du serveur.
~~~~

---

## (d) Favicon (icône d'onglet)

### d.1 Spécification (mêmes sources que (c))

**Zone web (carte « Favicon (Icône d'Onglet) »)** : même cadre en pointillés, icône `web`, texte « **Glisser-déposer ou cliquer pour choisir un favicon** », consigne « **ICO ou PNG 32x32px, max 500 Ko** », aperçu du favicon actuel (hauteur 32 px, `alt="Favicon actuel"`). Validation web : `faviconFile` : `nullable|image|max:500`. Messages (attribut « icône du site ») : « Le champ icône du site doit être une image. » · « Le fichier icône du site ne doit pas dépasser 500 kilo-octets. » Stockage : même disque et dossier `company`, colonne `favicon_path`. Synchronisation : `GET /api/sync/company-file/favicon`. Poste : « Cliquer pour choisir un favicon », mêmes formats que le logo, 500 Ko ; **le poste n'a pas d'onglet de navigateur** : il garde et montre le fichier dans l'écran de réglage seulement (relu : seul l'écran des réglages l'affiche).

### d.2 Écarts et défauts relevés dans AgriERP

1. **Écart n° 2 — la consigne dit « ICO » mais la validation le REFUSE.** La règle `image` de Laravel 12 n'accepte que jpg, jpeg, png, gif, bmp, webp (`ValidatesAttributes::validateImage`) : un fichier `.ico` est refusé (« Le champ icône du site doit être une image. »). Le sélecteur (`accept="image/*"`) l'offre pourtant. Le poste et l'API (`EntrepriseService::EXTENSIONS`, `FichiersEntreprise.extensions`) le refusent aussi. **LogiALVIA doit trancher** : (a) accepter ICO et PNG (règle `mimes:png,ico` + contrôle du contenu ; `getimagesizefromstring` lit les ICO) et ajouter `image/vnd.microsoft.icon` aux types admis du service ; ou (b) corriger la consigne en « PNG 32x32 px ». Le test doit couvrir **le cas annoncé par la consigne**.
2. **Écart n° 3 — le favicon téléversé ne sert à rien.** Les deux layouts (`agrierp_laravel/resources/views/layouts/app.blade.php` et `guest.blade.php`, ligne 8) posent `<link rel="icon" type="image/png" href="{{ asset('assets/images/logo_favicon.webp') }}">` : un fichier **fixe** ; `favicon_path` n'est jamais lu pour l'onglet. (Et le type déclaré `image/png` ne correspond pas à un `.webp`.) Le service worker précache aussi cet asset fixe (`SOCLE` de `public/sw.js`).
3. **Dimensions non contrôlées** : « 32x32px » n'est qu'une consigne, aucun contrôle ne l'applique (ni web ni poste) — décision client : contrôle souple (image carrée, au moins 32 px ?) ou aucune.
4. Mêmes défauts que le logo : glisser-déposer non câblé, pas de suppression, fichier précédent non supprimé, messages différents selon la porte d'entrée.

### d.3 PROMPT — Écran (d) WEB

~~~~text
[Colle P0 ici.]

OBJECTIF : la carte « Favicon (Icône d'Onglet) » de l'onglet « Données de l'Entreprise » de LogiALVIA, ET le rendu RÉEL du favicon dans l'onglet du navigateur. Spécification : d.1 et d.2 de /home/user/agrierp/docs/logialvia/42_CONFIG_MECEF_SMTP_LOGO_FAVICON.md. Prérequis : la carte « Logo » (c.3) existe : le favicon réutilise le MÊME service de fichiers (EntrepriseService::enregistrerFichier / supprimerFichier).

RÉFÉRENCES (lecture seule) : /home/user/agrierp/agrierp_laravel/resources/views/livewire/parametres/donnees-entreprise.blade.php ; app/Livewire/Parametres/DonneesEntreprise.php ; app/Services/EntrepriseService.php ; resources/views/layouts/app.blade.php et guest.blade.php (ligne `<link rel="icon">`) ; public/sw.js ; tests/Feature/SyncReglagesTest.php.

TÂCHES
1. Décision écrite du client sur ICO (d.2, point 1) AVANT le code ; sans réponse, arrête-toi.
2. Colonne `favicon_path` ; service de fichiers commun avec le logo, limite 500 Ko ; nom généré ; suppression de l'ancien fichier après écriture réussie ; contrôle du contenu réel.
3. Carte web : icône `web`, « Glisser-déposer ou cliquer pour choisir un favicon », consigne « ICO ou PNG 32x32px, max 500 Ko » (ou la consigne corrigée selon la décision), aperçu 32 px, remplacement, suppression avec confirmation (événement), glisser-déposer RÉEL.
4. Validation et messages exacts de d.1 ; la règle ACCEPTE le format annoncé par la consigne (test sur un vrai fichier .ico si ICO est retenu).
5. RENDU dans l'onglet : dans les deux layouts, `<link rel="icon">` pointe vers le favicon téléversé s'il existe (URL du disque public avec `?v=<updated_at>` : les navigateurs gardent les favicons très longtemps), sinon vers l'asset d'installation ; `type` déduit du fichier (image/png, image/x-icon) et JAMAIS un type faux ; même `<link rel="apple-touch-icon">` si le client le veut. Le service worker (si PWA) ne précache pas un favicon téléversé (statique d'installation seulement) et sa VERSION est incrémentée si un asset précaché change.
6. Droit manage-parametres ; audit `company_settings.favicon_updated` / `favicon_deleted` ; tirage `favicon_path` vers le poste ; `GET /api/sync/company-file/favicon`.
7. Tests : téléversement valide (ICO si retenu ET PNG), refus non-image, > 500 Ko, SVG, 403 sans droit, suppression et repli, le HTML des deux layouts contient l'URL du favicon téléversé avec son paramètre de version et le bon `type`, endpoint 200/404. Un test navigateur (Playwright) lit `document.querySelector('link[rel~=icon]').href` après changement.

CRITÈRES D'ACCEPTATION : libellés mot pour mot ; le favicon téléversé s'affiche dans l'onglet (vérifié) ; la consigne annoncée est acceptée par la validation ; aucun fichier orphelin ; suite verte.
INTERDITS : consigne qui promet un format que la règle refuse ; `type` du lien contredisant le fichier ; favicon dans le cache d'un service worker sans purge.
~~~~

### d.4 PROMPT — Écran (d) POSTE

~~~~text
[Colle P0 ici.]

OBJECTIF : la zone « Favicon (Icône d'Onglet) » du poste de LogiALVIA, fidèle à la vue web (d.1, d.3). Le poste n'a pas d'onglet de navigateur : il garde, montre et synchronise le fichier, rien de plus.

PRÉREQUIS : zone « Logo » du poste (c.4) faite : même classe FichiersEntreprise, genre `favicon`, limite 500 Ko.

RÉFÉRENCES (lecture seule) : /home/user/agrierp/agrierp_flutter/lib/core/config/fichiers_entreprise.dart ; lib/features/parametres/reglages_ferme_ui.dart ; lib/core/sync/sync_engine.dart ; test/reglages_ferme_poste_test.dart.

TÂCHES
1. Zone « Cliquer pour choisir un favicon » avec la même consigne que le web ; formats selon la décision ICO du web (si ICO est retenu au web, l'ajouter à la liste du poste ET prouver qu'il s'affiche à l'écran ; sinon rester sur png/jpg/gif/bmp/webp) ; limite 500 Ko ; aperçu 32 px ; remplacement ; suppression avec confirmation.
2. Même mécanisme que le logo : gardé tout de suite, envoyé dans la demande `entreprise` (faviconB64), téléchargé quand `favicon_path` change.
3. Message d'erreur identique à celui du serveur (constantes communes).
4. Test qui LIT la vue Blade pour les textes ; tests de validation (format, 500 Ko), d'enregistrement immédiat, de téléchargement au changement de chemin.

CRITÈRES D'ACCEPTATION : fichier hors base ; survit au redémarrage ; synchronisé dans les deux sens ; textes identiques au web ; flutter analyze et flutter test verts.
INTERDITS : prétendre que le favicon change l'icône de la fenêtre Windows (ce n'est pas le cas ; l'icône de l'application vient de l'installateur : voir `build_windows.bat` d'AgriERP, bloc 10 du guide).
~~~~

---

## 1. Questions au client (pour ces quatre écrans)

1. **MeCeF** : voir `41_MECEF_EMECEF.md` section 8 (jeton, environnement, qui saisit).
2. **SMTP** : fournisseur d'e-mail de la ferme (hôte, port, chiffrement, compte d'envoi) ? Le poste doit-il envoyer lui-même (cas d'AgriERP) ou toujours via le serveur ? Adresse d'expédition à afficher aux clients ?
3. **Relances** : acceptez-vous le refus d'envoi (au lieu d'une relance « tracée mais non partie ») quand aucun SMTP n'est configuré ?
4. **Logo** : formats acceptés (PNG/JPEG seulement, ou aussi GIF/WebP/SVG nettoyé) ? Où doit-il apparaître (menu, connexion, factures, attestations, rapports, courriels) ?
5. **Favicon** : **ICO accepté** (oui/non) ? Contrôle des dimensions (32x32 strict, carré minimum, aucun) ?
6. **Droits** : `manage-parametres` seul ? Un rôle « gérant » peut-il changer le logo sans pouvoir toucher au jeton MeCeF ni au SMTP ?
7. **Audit** : veut-on savoir QUI a changé le logo/favicon (événements dédiés, recommandés) ?

---

## 2. Contrôle de ce fichier

Chemins vérifiés par `ls`/lecture le 07/11/2026 : `agrierp_laravel/app/Livewire/Parametres/{FacturationEmecef,EmailSmtp,DonneesEntreprise,ParametresHub}.php`, les vues `facturation-emecef.blade.php`, `email-smtp.blade.php`, `donnees-entreprise.blade.php`, `app/Services/EntrepriseService.php`, `app/Services/Mecef/*`, `app/Models/CompanySetting.php`, `app/Services/RelanceClientService.php`, `app/Http/Controllers/Api/SyncController.php`, `routes/api.php`, `lang/fr/validation.php`, `config/mail.php`, `.env.example`, `agrierp_flutter/lib/core/config/{fichiers_entreprise,parametres_smtp,envoi_email,envoi_email_test}.dart`, `agrierp_flutter/lib/features/parametres/{onglet_email_smtp,reglages_ferme_ui,reglages_ferme_repository,parametres_generaux_screen}.dart`, `agrierp_flutter/lib/core/audit/libelles_audit.dart`, tests cités. **Rectification d'une consigne de mission** : le nom d'onglet est `ParametresGenerauxScreen.ongletEmailSmtp` (= « Email (SMTP) ») et le widget est dans `onglet_email_smtp.dart`. **Non vérifiés** : rendu réel d'un dépôt de fichier sur la zone web (aucun navigateur lancé) ; comportement de l'envoi `Mail::raw` contre un vrai serveur SMTP ; `Mail::forgetMailers()` selon la version de Laravel du projet cible ; écrans du poste exécutés (aucun `flutter` lancé).
