# Runbook de Déploiement cPanel — AgriERP (spécifique à ce projet)

Ticket 13.3 (Sprint 13), Document 08 Partie B. Ce document ne remplace
pas `CPANEL_DEPLOYMENT.md` (déjà fourni, référence générique) — il le
complète en traduisant chaque étape en commandes exactes pour CE
dépôt précis (vrais noms de seeders, vraie commande de sauvegarde, vrais
comptes de démonstration), et en documentant ce qui a été réellement
vérifié depuis ce bac à sable plutôt que simplement recopié.

**⚠️ Honnêteté en tête, comme pour chaque ticket de ce sprint** : ce bac
à sable n'a accès ni à un hébergement cPanel réel, ni au domaine cible
`agrierp.fermeolouwachegoun.com` (hors de la liste des domaines
autorisés pour cet environnement), ni à `packagist.org` (vérifié dans ce
ticket — voir §2). Le déploiement réel reste un acte à exécuter sur
l'hébergement final, pas quelque chose que je peux effectuer moi-même
d'ici. Ce document prépare ce travail aussi précisément que possible.

---

## 1. Ce qui A été vérifié depuis ce bac à sable dans ce ticket

- **`composer.json` valide** : `composer validate --strict` passe sans
  erreur.
- **Aucun `.env` accidentellement livré** dans l'archive du projet —
  vérifié explicitement (règle Document 08 §11).
- **PHP 8.3 disponible et conforme** à l'exigence hébergeur (§8 du
  document générique).
- **Aucun Job en file d'attente réel n'existe dans ce projet**
  (recherche explicite de `ShouldQueue`, `app/Jobs/`, `Mail::queue()` —
  zéro résultat). Conséquence concrète : le Cron Job `queue:work`
  mentionné dans `CPANEL_DEPLOYMENT.md` §5 n'a aujourd'hui rien à
  traiter — sans danger de le configurer par anticipation (l'architecture
  documentée le prévoit pour un usage futur), mais ce n'est pas encore
  un point bloquant du déploiement initial si le temps manque pour le
  configurer immédiatement.

## 2. Ce qui n'a PAS pu être vérifié, et pourquoi

- **`composer install --no-dev`** a été tenté réellement dans ce ticket
  — `packagist.org` n'est pas dans la liste des domaines autorisés pour
  ce bac à sable (confirmé par une tentative réelle, HTTP 403 sur
  `repo.packagist.org`), pas seulement supposé. **Conséquence concrète
  pour le déploiement réel** : suivre impérativement l'Option B de
  `CPANEL_DEPLOYMENT.md` §2 (packager `vendor/` en local, sur un poste
  avec accès Internet complet, avant upload) plutôt que de tenter
  `composer install` directement sur l'hébergeur ou depuis un
  environnement à accès réseau restreint comme celui-ci.
- **`npm run build`** : ce projet n'embarque pas de `package.json`/
  configuration Vite dans les fichiers livrés (Tailwind chargé via CDN
  dans le prototype d'origine, jamais migré vers un pipeline de build
  Node.js au fil des sprints) — à vérifier/construire sur le poste de
  développement local avant le premier déploiement réel si un pipeline
  d'assets compilés est finalement souhaité ; sinon, aucune étape "build"
  n'est nécessaire pour ce projet tel qu'il existe aujourd'hui.

## 3. Commandes réelles pour CE projet (traduction de Document 08 §10)

```bash
# Étape 3 — .env réel
cp .env.example .env
# Éditer .env : DB_DATABASE, DB_USERNAME, DB_PASSWORD (identifiants cPanel réels)
#              APP_URL=https://agrierp.fermeolouwachegoun.com
#              APP_ENV=production
#              APP_DEBUG=false

# Étape 4 — clé d'application (une seule fois)
php artisan key:generate

# Étape 5 — migrations + seeders réels de ce projet
php artisan migrate --force
php artisan db:seed --force --class=Database\\Seeders\\DatabaseSeeder
# DatabaseSeeder appelle déjà, dans le bon ordre, tous les seeders
# nécessaires (RolesAndPermissionsSeeder, DemoUsersSeeder,
# LivestockSpeciesSeeder, ChartOfAccountsSeeder, CostCentersSeeder...)
# — ne jamais appeler un seeder individuel isolément en production, l'ordre
# des dépendances (ex. CostCentersSeeder après LivestockSpeciesSeeder)
# ne serait plus garanti.

# Étape 8 — Cron Job cPanel (une seule entrée, chemin à adapter au
# chemin réel du compte cPanel)
* * * * * cd /home/UTILISATEUR/agrierp && php artisan schedule:run >> /dev/null 2>&1
# Déclenche automatiquement, entre autres, la sauvegarde quotidienne
# 02h00 configurée au ticket 13.2 (routes/console.php).
```

## 4. Comptes de démonstration — à changer immédiatement (Document 08 §11, rappelé)

| Rôle | Email | Mot de passe démo |
|---|---|---|
| admin | dg@fermeolouwachegoun.com | AgriERP@2026 |
| comptable | compta@fermeolouwachegoun.com | AgriERP@2026 |
| caissier | caisse@fermeolouwachegoun.com | AgriERP@2026 |
| animalier | elevage@fermeolouwachegoun.com | AgriERP@2026 |

**Dès la mise en donnée réelle** : changer ces 4 mots de passe depuis
l'écran Mon Profil de chaque compte, ou via `php artisan tinker` en SSH
(`User::where('email', '...')->first()->update(['password' => Hash::make('...')])`).

## 5. Vérification post-déploiement (Document 08 §11, à exécuter sur le vrai domaine)

- [ ] `https://agrierp.fermeolouwachegoun.com/.env` retourne 403/404.
- [ ] Page de connexion accessible, connexion avec un compte de démonstration réussie.
- [ ] `CHECKLIST_PRE_DEPLOIEMENT.md` (ticket 13.2) rejouée intégralement sur ce domaine réel.
- [ ] Export PDF d'au moins 2 rapports vérifié en impression réelle (point 8 de la checklist, non vérifiable avant ce moment).
- [ ] Sauvegarde manuelle immédiate (`php artisan agrierp:backup`) pour confirmer que `mysqldump` est bien disponible sur cet hébergeur précis, avant de compter sur la planification automatique.

---

*Ce runbook complète `CPANEL_DEPLOYMENT.md` et `CHECKLIST_PRE_DEPLOIEMENT.md` — les trois documents ensemble couvrent la totalité de Document 08 Partie B et Document 07 §7 pour ce projet précis.*
