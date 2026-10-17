# AgriERP — ADDENDUM_FULL_MIGRATIONS_DATABASE_FLUTTER.md
### 4 tables construites côté Laravel, absentes du schéma Drift documenté — à incorporer côté chat Flutter

> ⚠️ **Même limite que le document source** : Dart n'est pas disponible
> dans cet environnement — ce code Drift n'a pas été compilé ni vérifié
> syntaxiquement. À compiler réellement (`flutter pub run build_runner build`)
> et corriger dans le chat Flutter, pas à copier-coller en confiance
> aveugle.
>
> **Contexte** : `FULL_MIGRATIONS_DATABASE_FLUTTER.md` couvre fidèlement
> le schéma qui avait été planifié conjointement dès le départ (vérifié
> ligne à ligne pour la section Comptabilité — correspondance exacte).
> Ces 4 tables sont différentes : elles ont été conçues *pendant* la
> session Laravel, à partir des champs réels des écrans concernés,
> jamais anticipées dans la documentation Drift d'origine. Ce document
> comble cet écart précis, pas une revue générale du schéma Flutter.

---

## 1. `Correspondence` (→ `mails`) — Sprint 9, ticket 9.1

```dart
class Mails extends Table {
  TextColumn get id => text()();
  TextColumn get reference => text().withLength(min: 1, max: 30).unique()();
  TextColumn get type => text()(); // entrant | sortant
  TextColumn get subject => text().withLength(min: 1, max: 255)();
  TextColumn get party => text().withLength(min: 1, max: 150)();
  DateTimeColumn get mailDate => dateTime()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```
**Nommage** : la classe Laravel s'appelle `Correspondence`, pas `Mail`
— collision volontairement évitée avec `Illuminate\Support\Facades\Mail`
(le projet a un dossier `app/Mail/` pour l'envoi d'e-mails). Le nom de
la TABLE reste `mails` des deux côtés ; seul le nom de classe Eloquent
diffère. Côté Dart, `Mails` ne pose pas ce risque de collision — nom de
classe libre, mais garder `mails` comme nom de table pour la
correspondance.

## 2. `ArchivedDocument` (→ `archived_documents`)

```dart
class ArchivedDocuments extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 255)();
  TextColumn get category => text().withLength(min: 1, max: 100)();
  DateTimeColumn get archivedDate => dateTime()();
  DateTimeColumn get expiryDate => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```
**Statut dérivé, jamais stocké** : Valide/Bientôt expiré/Expiré se
calcule depuis `expiryDate` au niveau du `use_case` Dart (même règle que
côté Laravel, `ArchivedDocument::getStatusAttribute()`) — jamais une
colonne `status` séparée qui pourrait diverger de la vraie date.

## 3. `AdministrativeDocument` (→ `administrative_documents`)

```dart
class AdministrativeDocuments extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 255)();
  TextColumn get type => text().withLength(min: 1, max: 100)();
  TextColumn get beneficiary => text().withLength(min: 1, max: 150)();
  DateTimeColumn get docDate => dateTime()();
  TextColumn get status => text().withDefault(const Constant('en_attente'))(); // signe | en_attente
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

## 4. `AttestationTemplate` (→ `attestation_templates`) — Sprint 8

```dart
class AttestationTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get type => text().unique()(); // employe | stagiaire
  TextColumn get bodyText => text()();
  TextColumn get format => text().withDefault(const Constant('A4 Paysage'))();
  BoolColumn get showWatermark => boolean().withDefault(const Constant(true))();
  BoolColumn get showHeader => boolean().withDefault(const Constant(true))();
  BoolColumn get showSignature => boolean().withDefault(const Constant(true))();
  BoolColumn get showStamp => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```
**2 lignes seulement** (`employe`, `stagiaire`) — table de
configuration, pas un registre qui grossit. Génération PDF réelle
(aperçu live + export) reste côté Laravel/Livewire uniquement pour
l'instant ; si un besoin de génération d'attestation hors-ligne
apparaît côté Flutter, ce serait un chantier séparé (moteur PDF Dart),
pas juste une question de schéma.

---

## Également absente : `cycle_day_start`/`cycle_day_end` sur `prophylaxis_schedule_standards`

Colonnes ajoutées côté Laravel pour rendre le rappel de prophylaxie
réellement calculable (`DailyProphylaxyReminderJob`). Si le même calcul
doit un jour tourner localement côté Flutter (mode hors-ligne), la table
Drift existante `FeedRationStandards`-like pour la prophylaxie (à
vérifier si elle existe déjà côté Flutter — non trouvée dans le schéma
documenté à ce jour) aurait besoin des mêmes 2 colonnes nullable.

## À ajouter dans `database.dart` (point d'entrée Drift)

Ces 4 classes doivent rejoindre la liste `@DriftDatabase(tables: [...])`
existante, au même titre que les 28 tables déjà listées en fin de
`FULL_MIGRATIONS_DATABASE_FLUTTER.md` §"Fichier database.dart — Version
Complète".

## Ce que ce document NE couvre PAS

Cette liste de 4 tables a été identifiée en comparant le schéma Laravel
réel (52 migrations à ce jour) au schéma Flutter documenté, MAIS
seulement pour les tables ajoutées de façon organique en cours de
session (pas anticipées dans la documentation d'origine). Le reste du
schéma Laravel (Comptabilité, RH, Achats, Ventes...) a été vérifié
correspondre fidèlement à ce qui était déjà documenté côté Flutter —
pas besoin de le revalider entièrement, seul cet addendum comble un
écart réel et précis.

---

## Réconciliation avec l'implémentation Flutter réelle (mise à jour)

La session Flutter parallèle a comparé son implémentation déjà construite
(avant réception de cet addendum) contre les 3 tables ci-dessus et
trouvé une vraie divergence — confirmée en relisant les migrations
Laravel réelles ci-dessus, pas de mémoire :

| Table | Flutter (avant réconciliation) | Laravel (réel, confirmé) |
|---|---|---|
| Courriers | `correspondences` / `objet`/`partie`/`correspondenceDate` / `isProcessed` (inventé) | `mails` / `subject`/`party`/`mail_date` / (`isProcessed` n'existe pas côté Laravel) |
| Documents archivés | `name`/`expirationDate`/`filePath` | `title`/`expiry_date` (pas de `file_path`) |
| Documents administratifs | table `generated_documents`, `beneficiaire`, pas de `status` | table `administrative_documents`, `beneficiary`, `status` réel (`signe`/`en_attente`) |

**Direction de la réconciliation confirmée** : Flutter s'aligne sur
Laravel (source de vérité unique, principe déjà établi dans
`LARAVEL_SYNC_FLUTTER.md`) — les 3 tables Drift ci-dessus sont à
corriger côté Flutter, pas les migrations Laravel.

### ⚠️ Point critique trouvé pendant cette réconciliation : `mails.reference`

`reference` (`CR-{année}-{séquence}`, colonne `unique()` réelle côté
Laravel) est **générée et stockée à la création**
(`Correspondence::generateReference()`, incrémente le dernier numéro de
l'année en cours), **jamais recalculée à la lecture**. Si Flutter calcule
ce numéro dynamiquement au moment de l'affichage plutôt que de le
stocker au moment de la création : (1) la contrainte `unique()` de
Laravel rejettera l'enregistrement à la synchronisation si deux
courriers créés hors-ligne sur des postes différents obtiennent le même
numéro calculé localement, (2) le numéro affiché avant synchronisation
ne correspondra pas forcément à celui finalement stocké. **Le champ
`reference` doit être un vrai champ de table Drift, rempli une seule
fois à la création côté Flutter** (avec un schéma qui évite les
collisions inter-postes — par exemple un préfixe par poste, ou laisser
le serveur définitivement assigner `reference` lors du push et renvoyer
la valeur réelle dans la réponse de synchronisation plutôt que de faire
confiance à la valeur générée hors-ligne). Ce même risque existe pour
tout autre numéro séquentiel généré côté serveur ailleurs dans le
projet (`quote_number`, etc.) si jamais leur création hors-ligne est un
jour permise — à garder en tête au moment de construire l'API de
synchronisation elle-même (toujours pas construite à ce jour, voir
`LARAVEL_SYNC_FLUTTER.md`).

### Sur `isProcessed` (Flutter uniquement)
N'existe nulle part côté Laravel. Si ce champ sert un vrai besoin UI
local (ex. cocher un courrier comme traité avant même la synchronisation),
le garder en colonne Drift **locale, jamais synchronisée** est
défendable — mais il ne doit alors jamais être envoyé dans le payload de
`POST /api/sync/push`, puisque Laravel n'a nulle part où le recevoir.

### Contexte de déploiement transmis par la session Flutter
L'URL réelle testée est `http://127.0.0.1:8000/agrierp/api` (sous-dossier
`/agrierp`, pas la racine) — à retenir pour la configuration
`APP_URL`/routes une fois l'API Laravel (`routes/api.php`, toujours
absente à ce jour) effectivement construite, pour que les deux
implémentations se rejoignent au bon chemin dès le premier essai.

