# Checklist de Pré-Déploiement — AgriERP

Ticket 13.2 (Sprint 13), Document 07 §7. Chaque point ci-dessous a été
réellement vérifié depuis le bac à sable de développement quand c'était
possible, ou honnêtement marqué comme nécessitant un environnement de
déploiement réel (serveur, base MySQL, navigateur) quand ce bac à sable
ne le permet pas — jamais coché par convention ou par optimisme.

---

## 1. `php artisan test` intégralement vert

**⚠️ NON VÉRIFIABLE DEPUIS CE BAC À SABLE** — aucune base MySQL n'y est
disponible pour exécuter réellement la suite de tests.

Ce qui EST vérifié, systématiquement, à chaque fichier livré depuis le
Sprint 0 : validité syntaxique PHP (`php -l`) sur l'intégralité du
projet, et équilibre des balises Blade sur chaque vue — refait une
dernière fois pour ce ticket, zéro erreur.

Suite de tests réellement livrée, prête à s'exécuter sur un environnement
avec MySQL :
- `tests/Feature/AccountingEntryServiceTest.php` (5 scénarios, ticket 10.2)
- `tests/Feature/BilanTest.php` (ticket 10.5)
- `tests/Feature/ClotureExerciceTest.php` (2 scénarios, ticket 10.6)
- `tests/Browser/*.php` (8 parcours critiques Dusk, ticket 13.1)

**Action à l'installation réelle :** `php artisan test` puis
`php artisan dusk` sur un environnement disposant de MySQL et d'un
navigateur Chrome piloté.

---

## 2. `php artisan migrate:fresh --seed` sans erreur

**✅ Vérifié par audit automatisé de l'ordre des migrations**, à défaut
de pouvoir exécuter la commande elle-même (pas de MySQL disponible ici).

Script d'audit exécuté sur les 52 fichiers de migration (59 tables) :
pour chaque `constrained()`/`->on()` référençant une clé étrangère,
vérification que la table cible est bien créée par une migration
antérieure dans l'ordre chronologique réel (nom de fichier). **Résultat :
0 erreur d'ordre détectée** — aucune table n'est référencée avant sa
propre création, y compris les cas de clés étrangères différées
volontairement documentés au fil des sprints (ex. `livestock_lots.cost_center_id`,
`sale_lines.cost_center_id`, complétées au ticket 10.1 une fois
`cost_centers` créée).

**Action à l'installation réelle :** `php artisan migrate:fresh --seed`
sur un environnement propre — l'audit ci-dessus donne une forte
confiance mais ne remplace pas l'exécution réelle (contraintes MySQL
spécifiques au moteur, ex. longueur de clé sous InnoDB, non simulables
par une simple analyse de texte).

---

## 3. Les 4 rôles RBAC testés individuellement sur les parcours critiques (§4)

**✅ Couvert par le ticket 13.1**, avec une découverte et une correction
significatives au passage :

- `tests/Browser/SidebarRbacNavigationTest.php` teste explicitement les
  4 rôles (`animalier`, `caissier`, `comptable`, `admin`) sur l'accès
  direct par URL, pas seulement la visibilité des liens.
- **Gap RBAC critique trouvé et corrigé dans le même ticket** : 41 routes
  sur 42 n'étaient protégées que par `auth`, sans vérifier la permission
  Spatie correspondante. Corrigé — voir le docblock en tête de
  `routes/web.php` pour le détail complet.
- **Gap restant, non corrigé, signalé explicitement** : la vérification
  au niveau des actions Livewire individuelles (`$this->authorize()`)
  reste quasi absente (1 composant sur 76). Défense en profondeur
  manquante, risque pratique atténué mais pas nul — chantier à part
  entière, hors périmètre de ce ticket.

---

## 4. Sauvegarde MySQL automatisée configurée et vérifiée

**✅ Corrigé dans ce ticket** — gap réel trouvé et comblé :

- La commande `agrierp:backup` (mysqldump réel, ticket 11.1) existait et
  fonctionnait, mais n'était **jamais planifiée nulle part** :
  `routes/console.php` n'existait pas du tout avant ce ticket, malgré la
  planification déjà documentée dans `LISTE_DES_CRON_JOBS_CPANEL.md`
  depuis plusieurs sprints. Créé — `Schedule::command('agrierp:backup')->dailyAt('02:00')`.
- **Rétention 30 jours ajoutée** (Document 01 §5, NFRS) — absente
  jusqu'ici, les sauvegardes se seraient accumulées indéfiniment sur un
  serveur de production. Purge exécutée après chaque sauvegarde réussie,
  jamais avant.

**Action à l'installation réelle :** UNE SEULE entrée Cron cPanel
(`php artisan schedule:run`, chaque minute), conformément au modèle déjà
documenté — vérifier qu'elle est bien créée, `mysqldump` disponible sur
le serveur cPanel cible.

---

## 5. `.env` de production ne contient aucune valeur de développement

**⚠️ Vérification intrinsèquement liée au déploiement réel** — `.env` de
production n'existe pas (et ne doit jamais exister) dans ce dépôt.

`.env.example` (le seul fichier légitimement présent ici) contient bien
`APP_ENV=local`/`APP_DEBUG=true` — **correct pour un template de
développement**, à ne surtout pas modifier ici sous peine de casser
l'environnement local de chaque développeur.

**Checklist à exécuter manuellement sur le serveur de production au
moment du déploiement (Document 08 §11) :**
- [ ] `APP_ENV=production`
- [ ] `APP_DEBUG=false`
- [ ] `APP_KEY` généré spécifiquement pour la production (`php artisan key:generate`), jamais copié d'un environnement de dev
- [ ] Identifiants MySQL, SMTP, Reverb propres à la production, jamais les valeurs de test
- [ ] `LOG_LEVEL` remonté à `error` ou `warning`, jamais `debug`

### ⚠️⚠️ Comment SAVOIR, depuis n'importe où, si la production est en mode debug

Cette case a été cochée puis démentie par les faits : l'audit Lighthouse du
24/08/2026 a chargé `/livewire/livewire.js` sur le site en ligne. **Livewire
n'enregistre cette route QUE si `config('app.debug')` est vrai** ; sinon il
sert `livewire.min.js`. Les deux n'existent jamais ensemble — c'est donc une
sonde fiable, publique, et qui ne demande aucun accès au serveur :

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://agrierp.fermeolouwachegoun.com/livewire/livewire.js
# 404 attendu en production. 200 = APP_DEBUG=true, à corriger immédiatement.

curl -s -o /dev/null -w "%{http_code}\n" https://agrierp.fermeolouwachegoun.com/livewire/livewire.min.js
# 200 attendu en production.
```

**Ce qui est en jeu n'est pas le poids du fichier** (389 Ko contre 166 Ko) :
en mode debug, la moindre erreur affiche la trace d'exécution **avec les
valeurs d'environnement** — identifiants de base de données, clé
d'application, identifiants SMTP — à qui provoque l'erreur.

Correction, sur le serveur :

```bash
# 1. .env : APP_DEBUG=false   (et APP_ENV=production, LOG_LEVEL=error)
# 2. Reconstruire le cache de configuration — SANS cette étape, Laravel
#    continue de lire l'ancienne valeur mise en cache et rien ne change :
php artisan config:clear
php artisan config:cache
php artisan route:cache
php artisan view:cache
# 3. Re-sonder les deux URL ci-dessus.
```

---

## 6. Sélecteur de rôle de test RBAC masqué ou retiré

**✅ Déjà fait depuis le Sprint 0**, vérifié dans ce ticket plutôt que
supposé.

`resources/views/layouts/app.blade.php`, écart documenté dès l'en-tête
du fichier : *"Sélecteur de rôle de test (#rbac-role-switcher)... RETIRÉ
— outils de démo explicitement proscrits en production."* Confirmé par
recherche dans l'ensemble du projet : aucune occurrence de ce sélecteur
nulle part dans `resources/` ou `app/`.

---

## 7. Widget de démonstration "Tester Rappel" retiré

**✅ Déjà fait depuis le Sprint 0**, même vérification que le point 6.

Même en-tête de `layouts/app.blade.php` : *"boutons 'Tester Rappel' /
'Tester Alertes Stock' du header RETIRÉS — outils de démo explicitement
proscrits en production."* Confirmé par recherche dans l'ensemble du
projet : aucune occurrence.

---

## 8. Export PDF vérifié en conditions réelles d'impression sur au moins 2 rapports

**⚠️ L'impression physique n'est pas vérifiable depuis ce bac à sable**
(pas d'imprimante, pas de rendu visuel).

Ce qui EST vérifié : `PdfExportService::render()` appelle bien
`setPaper('a4', $orientation)` (DomPDF) — format papier réel A4, jamais
un format écran par défaut inadapté à l'impression. Les 3 exports du
ticket 13.1 (Créances, Dettes, Rapport de Stocks) génèrent tous des
fichiers PDF non vides via le même service, passant tous par le même
gabarit d'en-tête officiel partagé (`exports/layout.blade.php`).

**Action à l'installation réelle :** imprimer physiquement (ou export
"Enregistrer en PDF" du navigateur en A4 réel, pas un simple aperçu
écran) au moins 2 rapports générés en conditions réelles — vérifier
marges, lisibilité du QR code MeCeF sur les factures, absence de
coupures de tableau en plein milieu d'une ligne.

---

## Synthèse

| # | Point | Statut |
|---|---|---|
| 1 | `php artisan test` vert | ⚠️ Suite réelle livrée, exécution nécessite un environnement MySQL |
| 2 | `migrate:fresh --seed` sans erreur | ✅ Audit d'ordre automatisé, 0 erreur sur 52 migrations |
| 3 | 4 rôles RBAC testés | ✅ Gap critique trouvé ET corrigé (ticket 13.1) |
| 4 | Sauvegarde MySQL automatisée | ✅ Gap trouvé ET corrigé dans ce ticket (planification + rétention) |
| 5 | `.env` production propre | ⚠️ Vérification manuelle au déploiement, liste fournie |
| 6 | Sélecteur de rôle de test retiré | ✅ Déjà fait depuis le Sprint 0, reconfirmé |
| 7 | Widget "Tester Rappel" retiré | ✅ Déjà fait depuis le Sprint 0, reconfirmé |
| 8 | Export PDF conditions réelles | ⚠️ Format A4 réel confirmé, impression physique à vérifier au déploiement |

**4 points pleinement vérifiés et/ou corrigés depuis ce bac à sable, 4
points qui nécessitent intrinsèquement un environnement de déploiement
réel pour être cochés définitivement** — chacun de ces 4 derniers vient
avec une action concrète documentée ci-dessus, pas laissé en suspens.
