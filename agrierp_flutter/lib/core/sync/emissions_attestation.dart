import 'dart:convert';

import '../database/app_database.dart';

/// Une attestation fabriquée au poste dont le serveur n'a pas encore enregistré l'émission (hors ligne, réponse perdue).
class EmissionEnAttente {
  const EmissionEnAttente({required this.id, required this.type, required this.instant});

  /// Identifiant d'émission, tiré au poste : le serveur s'en sert pour ne compter qu'une fois un envoi rejoué.
  final String id;

  /// `employe` ou `stagiaire`.
  final String type;

  /// L'instant de l'ÉMISSION (UTC) — jamais celui de l'envoi : l'année du numéro et le registre en dépendent.
  final DateTime instant;

  Map<String, Object?> versJson() => {'id': id, 'type': type, 'instant': instant.toUtc().toIso8601String()};

  static EmissionEnAttente? depuisJson(Object? brut) {
    if (brut is! Map) return null;
    final instant = DateTime.tryParse('${brut['instant']}');
    final id = brut['id'];
    final type = brut['type'];
    if (instant == null || id is! String || type is! String) return null;

    return EmissionEnAttente(id: id, type: type, instant: instant.toUtc());
  }
}

/// La file des émissions d'attestation à déclarer au serveur (ATT-3).
///
/// ⚠️⚠️ **LE POSTE FABRIQUE LE PDF, LE SERVEUR GARDE LE NUMÉRO ET LA TRACE.** Hors ligne, l'attestation s'imprime quand
/// même (mode normal de la ferme) avec un numéro vide — jamais inventé au poste, comme le numéro d'un devis — et son
/// émission attend ici le retour du réseau. Le serveur la reçoit idempotente (par l'identifiant d'émission) : un envoi
/// rejoué ne compte qu'une fois au registre « Attestations émises ».
///
/// Stockée dans `app_settings` : aucune migration, et la file survit au redémarrage.
class FileEmissionsAttestation {
  FileEmissionsAttestation(this._db);

  final AppDatabase _db;

  static const cle = 'attestation_emissions_en_attente';

  Future<List<EmissionEnAttente>> lire() async {
    final ligne = await (_db.select(_db.appSettings)..where((s) => s.key.equals(cle))).getSingleOrNull();
    if (ligne == null) return const [];

    try {
      final decode = jsonDecode(ligne.value);
      if (decode is! List) return const [];

      return [for (final e in decode) ?EmissionEnAttente.depuisJson(e)];
    } on FormatException {
      return const [];
    }
  }

  Future<void> _ecrire(List<EmissionEnAttente> liste) async {
    if (liste.isEmpty) {
      await (_db.delete(_db.appSettings)..where((s) => s.key.equals(cle))).go();
      return;
    }

    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: cle, value: jsonEncode([for (final e in liste) e.versJson()])),
        );
  }

  Future<void> ajouter(EmissionEnAttente emission) async {
    final liste = await lire();
    if (liste.any((e) => e.id == emission.id)) return;

    await _ecrire([...liste, emission]);
  }

  /// Déclare au serveur, dans l'ordre, chaque émission en attente.
  ///
  /// [envoyer] rend `true` quand le serveur l'a prise (ou la refuse pour toujours : retirée, sinon elle bloquerait la file),
  /// `false` pour réessayer plus tard — la file s'arrête alors, le réseau est probablement coupé. Rend le nombre retiré.
  /// ⚠️ Rien n'est retiré avant l'accord du serveur : une émission perdue en route n'existerait nulle part.
  Future<int> vider(Future<bool> Function(EmissionEnAttente) envoyer) async {
    var liste = await lire();
    var retirees = 0;

    for (final e in List.of(liste)) {
      if (!await envoyer(e)) break;

      liste = liste.where((x) => x.id != e.id).toList();
      await _ecrire(liste);
      retirees++;
    }

    return retirees;
  }
}
