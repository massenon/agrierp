# Code de secours de l'administrateur : à imprimer et ranger au coffre

**Ticket MDP-1 (29/10/2026) · décision du client : plus de réinitialisation du mot de passe par e-mail.**

## Qui réinitialise quoi

| Situation | Geste | Qui |
|---|---|---|
| Un employé a oublié son mot de passe | Gestion des Utilisateurs > icône « Réinitialiser le mot de passe » (web **et** poste) : l'administrateur choisit un mot de passe **temporaire** | Un administrateur (`manage-users`) |
| Le **dernier administrateur** oublie son mot de passe | `php artisan agrierp:reinitialiser-admin <identifiant>` avec le **code de secours** | La personne qui a accès au serveur ET au code imprimé |

L'écran de connexion dit simplement « Contactez l'administrateur » (texte non cliquable). Un administrateur **ne peut pas réinitialiser son propre compte** par le geste de l'écran (message : « Vous ne pouvez pas réinitialiser votre propre mot de passe : utilisez Mon Profil. ») : c'est précisément le rôle du code de secours.

## Ce que fait une réinitialisation (écran ou secours)

- le mot de passe temporaire remplace l'ancien (mêmes règles que la création d'un compte, `Password::defaults()`) ;
- le compte est marqué `must_change_password` : à la connexion suivante, le web n'ouvre que la page « Changement de mot de passe obligatoire » et le poste affiche le même écran avant l'accueil ; l'API refuse tout le reste (403) tant que ce n'est pas fait ;
- tous les jetons des postes du compte sont révoqués, ses sessions web sont fermées ;
- une ligne d'audit dit **qui** a réinitialisé **quel** compte (`user.password_reset`, ou `user.password_reset_secours`) : jamais le mot de passe, jamais le code.

## Le code de secours

- **24 caractères lisibles** (ni 0/O ni 1/I/L), groupés par quatre : `K7QM-4WTD-9PXH-C3VR-8NZB-2FYG`.
- **Usage unique** : une fois utilisé, il est invalidé et un **nouveau** code est généré et affiché, une seule fois.
- Seule son **empreinte** (SHA-256) est conservée, dans la table `recovery_codes` ; le code lui-même ne peut pas être relu. Un code perdu se **remplace**, il ne se retrouve pas.
- **5 échecs de code, puis blocage de 15 minutes** (même limiteur que la connexion web) ; chaque échec et le blocage sont écrits au journal d'audit et au journal de l'application.

### 1. Générer le premier code (à faire à l'installation, une fois)

```bash
php artisan agrierp:code-secours
```

Le code s'affiche **une seule fois**. **Imprimez-le, rangez la feuille au coffre** (pas dans un fichier du serveur, pas dans un courriel). Relancer la commande quand un code est déjà actif demande confirmation (`--force` pour l'imposer) : l'ancien code cesse alors de fonctionner.

### 2. Réinitialiser un administrateur

```bash
php artisan agrierp:reinitialiser-admin admin
```

La commande demande, en saisie masquée : le code de secours, puis le nouveau mot de passe **temporaire** (deux fois). Elle affiche ensuite le **nouveau code de secours** : imprimez-le et remplacez la feuille du coffre. L'administrateur se connecte avec le temporaire et choisit aussitôt son propre mot de passe.

- Le compte doit être un administrateur **actif** (rôle `admin`).
- Un mot de passe faible ou mal confirmé ne consomme **pas** le code.
- Le code n'est jamais un argument de la commande (il resterait dans l'historique du shell).

## Pour qui connaît le serveur

- La table `recovery_codes` (UUID) n'est **jamais synchronisée** vers les postes et survit à « Réinitialisation des données ».
- Le code n'est pas lié à `APP_KEY` : une restauration de la base sur un autre serveur garde le code valable.
- Avoir un accès shell au serveur suffit à générer un nouveau code (`agrierp:code-secours --force`) : la protection du serveur reste la première barrière ; le code protège contre l'oubli, pas contre un administrateur système malveillant.
- Gardes : `tests/Feature/CodeSecoursAdminTest.php` (génération, empreinte seule, usage unique, nouveau code, échec, blocage, temps constant).
