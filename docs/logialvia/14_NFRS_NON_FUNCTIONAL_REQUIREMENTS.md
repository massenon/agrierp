# 14 — NFRS : exigences non fonctionnelles de LogiALVIA (web + poste)

## USAGE

- **Quand l'utiliser** : après le FRS ; avant la première recette ; à chaque jalon de performance ou de sécurité. Règle de B5 conservée : **une exigence non fonctionnelle sans seuil chiffré n'a pas sa place ici** — un seuil sans source est marqué PROPOSÉ (à valider avec la Direction) et n'est pas bloquant tant qu'il n'est pas confirmé.
- **Ordre** : `10` → `11` → `12` → `13` → **`14_NFRS`** → `15_REGLES_METIER`. Mesures et outils : `31_TESTING_QA.md` ; design et accessibilité : `04_UI_UX_DESIGN_SYSTEM.md` ; standards : `03_DEVELOPMENT_STANDARDS.md`.
- **Entrées** : `logialvia/docs/B5_NFRS_NonFunctional_Requirements.md`, `I3_Security_Strict.md`, `E8_Responsive.md`, `E9_Impression_PDF.md`, `K1_Standards_Code.md`, `K2_Checklist_Recette_Visuelle.md`, `docs/logialvia/GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md`, `agrierp_laravel/CLAUDE.md`, `docs/GUIDE_DEPLOIEMENT.md`, `docs/INSTALLATION_LOCALE.md`.
- **Sorties** : ce fichier à jour (`NFR-nnn` : seuil, méthode de mesure, source, statut C/P/D).
- **Chemins** : `logialvia/…` = `/home/user/massenon/logialvia/…` ; sans préfixe = `/home/user/agrierp`.

---

## 1. PROMPT — « Rédige / mets à jour le NFRS de LogiALVIA »

> **Rôle.** Ingénieur qualité et exploitation senior (performance, sécurité applicative, accessibilité, continuité de service).
> **Contexte.** B5 fixe 20 exigences pour le poste Flutter seul. Le web ajoute : latence réseau, concurrence multi-postes, HTTPS, sessions, sauvegardes serveur, PWA, navigateurs, disponibilité.
> **Tâches.** (1) Reprends les 20 exigences de B5 (`NFRS-…` → `NFR-`) avec colonne « Ancêtre » ; (2) ajoute les exigences du web et de la synchronisation ; (3) pour chacune : seuil chiffré, méthode de mesure (outil, jeu de données, environnement), source ; (4) marque PROPOSÉ ce qui vient d'AgriERP ou de la bonne pratique, À DÉFINIR ce qui dépend du client (volumes, hébergeur, durée hors ligne) ; (5) relie chaque `NFR-` à un test ou un contrôle de `31_TESTING_QA.md`.
> **Contraintes.** Français ; aucun chiffre inventé : tout chiffre sans source = PROPOSÉ ; les mesures s'écrivent avec un volume (« 5 000 lignes ») et un environnement (« poste Windows 10, 8 Go »). Sécurité : aucune dérogation à `docs/logialvia/GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md` D-SRV-5.
> **Critères d'acceptation.** (a) ≥ 60 lignes `NFR-` ; (b) 100 % ont un seuil ou la mention À DÉFINIR + question ; (c) chaque ligne a une méthode de mesure ; (d) les 20 exigences de B5 sont présentes ; (e) les sections sécurité, accessibilité, compatibilité, disponibilité, sauvegardes, PWA, hors ligne existent.
> **Interdits.** « Rapide », « sécurisé », « convivial » sans chiffre ; copier un SLA d'AgriERP ; promettre une disponibilité sans hébergeur choisi ; affaiblir un seuil pour qu'un test passe.

---

## 2. Performance

| ID | Exigence | Seuil | Mesure | Ancêtre / source | St. |
|---|---|---|---|---|---|
| NFR-PERF-01 | Chargement d'un écran depuis la navigation (poste) | < 300 ms perçu | chronomètre widget test + profil release | NFRS-PERF-01 | C |
| NFR-PERF-02 | Lecture de l'historique des ventes (jusqu'à 5 000 lignes) | < 500 ms | requête sur base de test à 5 000 ventes | NFRS-PERF-02 | C |
| NFR-PERF-03 | Validation d'une vente (transaction complète FR-VTE-03) | < 200 ms au poste | test d'intégration chronométré | NFRS-PERF-03 | C |
| NFR-PERF-04 | Tableau de 1 000 lignes | pas de gel ; pagination (25 lignes) ou virtualisation obligatoire | test de rendu | NFRS-PERF-04 ; guide bloc 4 | C |
| NFR-PERF-05 | Première peinture d'une page Livewire (web) | < 2 s sur connexion 3G rapide simulée | Lighthouse (profil mobile) | aucune source | P |
| NFR-PERF-06 | Action Livewire de saisie (enregistrer une fiche) | < 1 s serveur hors réseau | test Feature chronométré | aucune source | P |
| NFR-PERF-07 | Poids de la synchronisation : lot d'envoi sous la limite du mandataire (erreur 413 gérée) ; tirage paginé | jamais une page sans sa pièce | essai multipostes | guide bloc 16 | C |
| NFR-PERF-08 | Navigation sans rechargement complet (hubs en composants Livewire imbriqués, jamais iframes) | 0 rechargement de page entre onglets d'un hub | Dusk | `agrierp_laravel/CLAUDE.md` ; `docs/prd/navigation-sans-rechargement.md` | P |

## 3. Fiabilité et intégrité

| ID | Exigence | Seuil | Mesure | Source | St. |
|---|---|---|---|---|---|
| NFR-FIAB-01 | Calculs de fiche journalière | 0 écart sur les jeux de cas calculés à la main (`15_REGLES_METIER.md`) ; parité PHP↔Dart exécutée sur ≥ 500 jours aléatoires dès que le web du module existe | tests unitaires + parité | NFRS-FIAB-01 ; guide bloc 1 | C |
| NFR-FIAB-02 | Atomicité d'une vente | 0 état intermédiaire après coupure | test : insérer une ligne invalide, vérifier la base | NFRS-FIAB-02 ; F4 | C |
| NFR-FIAB-03 | Perte de données à la fermeture brutale | 0 perte de saisie confirmée | kill du processus après validation | NFRS-FIAB-03 | C |
| NFR-FIAB-04 | Idempotence de la synchronisation | un lot renvoyé n'écrit rien de plus ; réponse perdue = cas normal | test de rejeu | guide bloc 16 | C |
| NFR-FIAB-05 | Équilibre comptable | Σ débit = Σ crédit à la décime sur 100 % des pièces ; écart de balance 0 | requête de contrôle | B6 BR-CPT-004 | C |
| NFR-FIAB-06 | Migration de schéma (UUID, versions Drift) | lignes avant = après ; `foreign_key_check` vide ; relançable | test sur VRAIE ancienne base | guide D-SRV-3 | C |
| NFR-FIAB-07 | Concurrence : deux envois simultanés sur la même fiche | compteur `vente` exact (relecture `lockForUpdate()`) | test à deux processus | `agrierp_laravel/CLAUDE.md` S-T12 | P |
| NFR-FIAB-08 | Ordre des verrous | stock avant fiche, UUID croissants ; 0 interblocage non rejoué (3 essais) | test | idem | P |

## 4. Utilisabilité

| ID | Exigence | Seuil | Mesure | Source | St. |
|---|---|---|---|---|---|
| NFR-UTIL-01 | Prise en main (utilisateur du prototype) | < 15 min | essai chronométré avec 2 utilisateurs | NFRS_UTIL-01 | C |
| NFR-UTIL-02 | Clics pour atteindre une fonction depuis l'accueil | ≤ 3 | grille de parcours | NFRS-UTIL-02 | C |
| NFR-UTIL-03 | Saisie d'une fiche complète | < 3 min par espèce | chronométrage | B2 §6 | C |
| NFR-UTIL-04 | Transaction POS simple | < 60 s | chronométrage | B1 OB-3 | C |
| NFR-UTIL-05 | Messages | français, phrase complète, même texte au web, au poste et à l'envoi ; jamais un message technique | grep des messages | guide 14.1 | C |
| NFR-UTIL-06 | Champs de saisie : hauteur 44 px (`h-11`) ; un seul composant de champ numérique | 44 px | test de widget | F3 | C |
| NFR-UTIL-07 | Aide par écran + visite guidée ; entrée d'aide pour chaque route authentifiée | 100 % des routes | test de garde routes ↔ textes | guide bloc 13f | P |

## 5. Accessibilité et affichage

| ID | Exigence | Seuil | Mesure | Source | St. |
|---|---|---|---|---|---|
| NFR-ACC-01 | Contraste texte normal | ≥ 4,5:1 (WCAG 2.2 AA), lisible en plein jour | outil de contraste sur les tokens (`tailwind.config.js`, thème Flutter) | NFRS-UTIL-03 | C |
| NFR-ACC-02 | Navigation clavier complète sur les écrans de saisie (Tab, Entrée, Échap des modales) | 100 % des formulaires | test Dusk | WCAG 2.2 (bonne pratique) | P |
| NFR-ACC-03 | Étiquettes : chaque champ a un libellé associé ; chaque `<td>` a `data-label` (vue carte mobile) | 100 % | garde sur les sources | `agrierp_laravel/CLAUDE.md` | C |
| NFR-ACC-04 | Responsive : tableau → cartes à 640 px EXACTEMENT ; grille KPI 2 → 4 colonnes à 1280 px (largeur de FENÊTRE) | breakpoints Tailwind `sm` 640, `md` 768, `lg` 1024, `xl` 1280 | tests de largeur | F2 ; E8 | C |
| NFR-ACC-05 | Information jamais portée par la seule couleur (badges de statut avec libellé) | 100 % | revue | WCAG 2.2 | P |
| NFR-ACC-06 | Mode d'impression/PDF : en-tête entreprise, tableau, pied de page ; logo si configuré | conforme E9 | revue du PDF | E9 | C |

## 6. Sécurité

| ID | Exigence | Seuil | Mesure | Source | St. |
|---|---|---|---|---|---|
| NFR-SEC-01 | Accès par rôle | 0 accès non autorisé par URL directe, au web ET dans les écrans du poste (4 rôles : admin, comptable, caissier, animalier ; DV-07) | test par (rôle, route) | NFRS-SEC-01 ; `agrierp_laravel/CLAUDE.md` | C |
| NFR-SEC-02 | Injection SQL | 0 requête construite par concaténation ; API typée (Eloquent/Drift) ; `grep customSelect\|customStatement` justifié | grep avant livraison | NFRS-SEC-02 ; I3 §1 | C |
| NFR-SEC-03 | Secrets | 0 secret en dur ni versionné ; `.env` non versionné | recherche statique + `git ls-files` | NFRS-SEC-03 ; `CLAUDE.md` racine | C |
| NFR-SEC-04 | Mots de passe | hachés au serveur (`Hash::make`) ; politique indiquée au champ de Mon Profil de logialvia : « Min. 8 caractères, 1 majuscule, 1 chiffre » (à confirmer, Q-ADM-1) ; jamais journalisés ; jamais SHA-256+sel après la bascule | test de garde sur les colonnes du poste | guide D-SRV-5 ; F8 ; `logialvia/docs/manuel/libelles/31-mon-profil.json` | C/D |
| NFR-SEC-05 | PIN local du poste | PBKDF2-HMAC-SHA256 ≥ 100 000 itérations, sel 16 octets | test unitaire | guide D-SRV-5 | P |
| NFR-SEC-06 | Verrou de connexion | 5 échecs → 15 min, persisté côté serveur | test | F1 ; I3 §6 | C |
| NFR-SEC-07 | HTTPS obligatoire en production (jeton et mot de passe circulent) | 100 % des requêtes `/api` | test d'environnement | guide D-SRV-7 | P |
| NFR-SEC-08 | Jetons : un jeton par poste, nommé ; révocable ; expiration 90 jours | révocation → 401 au prochain appel | test | guide bloc 15, 20 | P |
| NFR-SEC-09 | Secrets applicatifs côté serveur : jeton e-MECeF chiffré (`APP_KEY`), masqué, jamais servi au poste, jamais journalisé | 0 occurrence dans les réponses `/api` | test de contrat | guide bloc 19 | C |
| NFR-SEC-10 | Téléversements | signature réelle, ≤ 2 Mo, nom UUID | test | I3 §2 | C |
| NFR-SEC-11 | CSRF/XSS web : jetons CSRF Laravel ; Blade échappe ; PDF n'interprète pas de balises | 0 `{!! !!}` sur donnée utilisateur | grep | I3 §1 (adapté au web) | P |
| NFR-SEC-12 | Journalisation : audit (suppression, clôture, déclôture, réinitialisation), sécurité (échecs) | 100 % des actions listées | test par action | B6 BR-ADM-003 ; I3 §6 | C |
| NFR-SEC-13 | Base du poste : droits du dossier applicatif ; chiffrement au repos (`sqlcipher`) non tranché | À DÉFINIR | — | I3 §4 | D |
| NFR-SEC-14 | Verrou de session inactif (web et poste) | durée réglable, À DÉFINIR par le client | test | `docs/prd/verrou-web.md` | D |
| NFR-SEC-15 | La matrice des droits est la source unique : aucune permission du code n'est plus large que la matrice (caissier : pas d'`/inventaire`, `view-facturation` sans `manage-facturation`) ; si le client veut d'autres accès, on corrige la matrice | 0 écart matrice ↔ code ; test par (rôle, route, action) | test | `16_` DV-06 | C |

## 7. Compatibilité et portabilité

| ID | Exigence | Seuil | Mesure | Source | St. |
|---|---|---|---|---|---|
| NFR-COMP-01 | Poste : Windows 10/11 64 bits ; VC++ Redistributable requis | installateur refuse sans runtime | recette sur machine propre | NFRS-PORT-01 ; B3 §6 | C |
| NFR-COMP-02 | Navigateurs du web : dernières versions de Chrome, Edge, Firefox ; Safari (iOS) à valider | À DÉFINIR (Q-PWA-1) : appareils réels du client | Dusk + essai manuel | aucune source | D |
| NFR-COMP-03 | Écrans : poste ≥ 1280×720 ; web de 360 px à 1920 px sans défilement horizontal de la page | — | tests de largeur | E8 | P |
| NFR-COMP-04 | Versions : PHP 8.3, Laravel 12, Livewire 3, Flutter figé (`.fvmrc`), Drift (API de la version de logialvia : `&` sur `Expression<bool>`, pas `.and()`) | — | CI | guide §0 contradiction 8 ; bloc 8 | C |
| NFR-COMP-05 | Base : MariaDB/MySQL prod ; SQLite `:memory:` en tests Feature | — | CI | `agrierp_laravel/CLAUDE.md` | C |
| NFR-COMP-06 | Fuseau : dates métier à l'heure du Bénin (UTC+1) quel que soit le fuseau de la machine | test passe avec `TZ=America/New_York` | test | guide 14.1 | C |
| NFR-COMP-07 | Interopérabilité : mise à jour du poste avec même AppId = données intactes | essai de mise à jour | guide bloc 16 ; blueprint §7 | P |

## 8. Hors ligne, synchronisation, PWA

| ID | Exigence | Seuil | Mesure | Source | St. |
|---|---|---|---|---|---|
| NFR-OFF-01 | Fonctionnement hors ligne du poste | 100 % du périmètre B1 §5 sauf : première connexion, marquer une notification lue, modifier un référentiel serveur, MeCeF | recette réseau coupé | NFRS-PORT-02 ; guide bloc 16, 18 | C |
| NFR-OFF-02 | Latence de reprise : synchronisation automatique au retour du réseau | déclenchée à l'événement + toutes les 5 min (réglable) ; échec : 30 s, 2 min, 5 min, 15 min, 1 h | test | guide bloc 16 | C |
| NFR-OFF-03 | Perte de ventes hors ligne | 0 ; chaque vente est un fait indépendant | essai multipostes | guide bloc 16 | C |
| NFR-OFF-04 | Durée hors ligne maximale | À DÉFINIR (jeton 90 jours en borne dure) | — | Q-PWA-1 | D |
| NFR-PWA-01 | Service worker étroit : statique seulement ; `/api/`, `/livewire/`, pages de session exclues ; `VERSION` à chaque déploiement ; purge à `activate` | 0 HTML authentifié en cache | `PwaEtPolicesLocalesTest` | `agrierp_laravel/public/sw.js` ; guide bloc 20 | C |
| NFR-PWA-02 | Hors ligne dans le navigateur (IndexedDB, Background Sync) | À CONCEVOIR : seulement sur besoin explicite du client | — | guide bloc 20 | D |
| NFR-PWA-03 | Installabilité | manifeste valide, icônes, `display: standalone` | Lighthouse PWA | `agrierp_laravel/public/manifest.webmanifest` | P |

## 9. Disponibilité, sauvegardes, exploitation

| ID | Exigence | Seuil | Mesure | Source | St. |
|---|---|---|---|---|---|
| NFR-DISP-01 | Disponibilité du serveur web | À DÉFINIR avec l'hébergeur (Q-HEB-1) ; le poste reste utilisable serveur coupé | — | guide D-SRV-7 | D |
| NFR-DISP-02 | Mise en production | serveur d'abord, postes ensuite ; essai multipostes vert sur plusieurs graines | procédure `docs/GUIDE_DEPLOIEMENT.md` | guide 14.3 W9 | C |
| NFR-SAV-01 | Sauvegarde automatique avant migration de schéma ; refus de migrer si elle échoue | 100 % | test | guide D-SRV-3 | C |
| NFR-SAV-02 | Sauvegarde quotidienne du serveur ; rappel hebdomadaire de téléchargement (lundi 08:00) au rôle admin | quotidienne 02:00 ; rétention À DÉFINIR | planificateur | `agrierp_laravel/CLAUDE.md` (AgriERP) | P |
| NFR-SAV-03 | Restauration : 4 contrôles avant le moindre octet ; base précédente conservée ; différée au redémarrage au poste | 4/4 | test | F8 | C |
| NFR-SAV-04 | Restauration testée périodiquement sur une copie | À DÉFINIR (fréquence) | — | I3 / F8 « le jour où on en a besoin » | D |
| NFR-SAV-05 | Planificateur : un seul cron `schedule:run` | 1 | revue | `agrierp_laravel/routes/console.php` | P |
| NFR-OBS-01 | Journal de synchronisation (par poste, par lot) consultable ; erreurs jamais avalées | 100 % des refus tracés | test | `JournalSynchronisationService` | P |
| NFR-OBS-02 | Mode release sans informations de débogage ; `APP_DEBUG=false` en production | 0 trace | contrôle | I3 §3 | C |

## 10. Maintenabilité et scalabilité

| ID | Exigence | Seuil | Mesure | Source | St. |
|---|---|---|---|---|---|
| NFR-MAINT-01 | Couverture des calculs métier | 100 % des `domain/usecases` de calcul (poste) et des `Services/Actions` (web) ; test de mutation manuel (retirer le plancher/le refus doit faire rougir ≥ 1 test) | rapport | NFRS-MAINT-01 ; guide bloc 1 | C |
| NFR-MAINT-02 | Duplication | 0 bloc > 5 lignes dupliqué entre 2 fichiers sans extraction | revue / outil | NFRS-MAINT-02 | C |
| NFR-MAINT-03 | Qualité statique | `flutter analyze` sans avertissement injustifié ; `php artisan test --testsuite=Feature` vert (⚠️ `php artisan test` seul échoue si `tests/Unit` absent) | CI | NFRS-MAINT-03 ; `agrierp_laravel/CLAUDE.md` | C |
| NFR-MAINT-04 | Traçabilité | chaque règle codée porte son `BR-`/`RM-` en commentaire | grep | B6 « Traçabilité » | C |
| NFR-MAINT-05 | Gardes qui lisent les sources (libellés, structure des colonnes, composants) | jamais affaiblis | tests de conformité | guide 14.1 | C |
| NFR-SCAL-01 | Historique | ≥ 5 années de ventes et fiches sans repenser la persistance | base de test 5 ans | NFRS-SCAL-01 | C |
| NFR-SCAL-02 | Nouvelle filière | par configuration (`ConfigurationEspece`), pas par duplication d'écran | revue | NFRS-SCAL-02 | C |
| NFR-SCAL-03 | Nombre de postes simultanés | À DÉFINIR (Q-SCAL-1) | essai multipostes | aucune source | D |

## 11. Questions ouvertes

**Q-HEB-1** hébergeur et disponibilité attendue (heures ouvrées seulement ?) ; **Q-PWA-1** appareils, navigateurs, durée hors ligne ; **Q-ADM-1** politique de mot de passe ; **Q-SCAL-1** combien de postes et d'utilisateurs simultanés ; **Q-SAV-1** durée de rétention des sauvegardes et responsable du téléchargement hebdomadaire ; **Q-SEC-1** chiffrement de la base du poste (`sqlcipher`) souhaité ?
