import 'package:drift/drift.dart';

/// Statut de synchronisation d'un enregistrement local.
///
/// Le CDC n'en connaît que deux (`pending|synced`). `conflict` est ajouté ici
/// pour l'enregistrement que le serveur a REJETÉ : sans lui, un rejet ne
/// pourrait être représenté que par un retour à `pending`, et l'appareil
/// réessaierait indéfiniment un envoi voué à échouer — une boucle silencieuse.
enum SyncStatus { pending, synced, conflict }

/// Métadonnées obligatoires sur toute table synchronisable (CDC §292).
///
/// ⚠️ `id` EST UN UUID, JAMAIS UN ENTIER AUTO-INCRÉMENTÉ. Deux appareils
/// travaillant hors ligne attribueraient tous deux l'identifiant 42 à des
/// enregistrements différents ; à la synchronisation, l'un des deux écraserait
/// l'autre sans que rien ne le signale. L'UUID est généré CÔTÉ CLIENT à la
/// création et le serveur le conserve tel quel — il ne le régénère jamais.
///
/// ⚠️ `deviceId` identifie l'appareil d'origine. Sans lui, un conflit ne peut
/// pas être expliqué à l'utilisateur (« qui a écrit quoi, et où ? ») et la
/// règle de dernière-écriture-gagnante devient un arbitrage aveugle.
///
/// ⚠️ `updatedAt` porte la résolution de conflits. Il doit refléter l'instant
/// de la SAISIE et non celui de l'envoi : un appareil resté trois jours hors
/// ligne verrait sinon toutes ses écritures horodatées à la reconnexion, et
/// gagnerait contre des saisies plus récentes faites ailleurs.
mixin SyncColumns on Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();

  TextColumn get deviceId => text().withLength(min: 1, max: 64)();

  TextColumn get syncStatus =>
      textEnum<SyncStatus>().withDefault(const Constant('pending'))();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
