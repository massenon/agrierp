import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';

/// PWA-2b — SAUVEGARDE COMPLÈTE au navigateur : export de TOUTES les tables de la base locale, en JSON (UTF-8), téléchargé
/// comme un fichier.
///
/// POURQUOI CE FORMAT et pas la copie d'octets de la base (`VACUUM INTO`, `serialize`) : dans le navigateur la base vit dans
/// le système de fichiers IndexedDB du worker de drift ; `VACUUM INTO` écrit dans CE système de fichiers, que la page ne sait
/// pas relire en octets, et le worker ne rend pas `sqlite3_serialize`. Le vidage des tables est, lui, entièrement fait par
/// des `SELECT` : fiable, lisible, et indépendant du moteur. Contrepartie : ce n'est PAS un fichier `.sqlite` (il ne s'ouvre
/// pas dans un outil SQLite) ; il porte le numéro de version du schéma, et [importer] le refuse si la base cible est d'un
/// autre palier.
///
/// Les octets (BLOB) sont portés par `{"__b64": "..."}` : les entiers, réels, textes et NULL gardent leur type JSON.
class SauvegardeCompleteJson {
  const SauvegardeCompleteJson._();

  /// Version du format du fichier (pas du schéma de la base).
  static const format = 1;

  static const _marqueOctets = '__b64';

  /// Les tables de l'utilisateur (hors tables internes de SQLite).
  static Future<List<String>> tables(GeneratedDatabase db) async => [
    for (final r in await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name").get())
      r.read<String>('name'),
  ];

  /// Le fichier de sauvegarde (octets UTF-8) : version du schéma, horodatage, et toutes les lignes de toutes les tables.
  static Future<Uint8List> exporter(GeneratedDatabase db, {required DateTime maintenant, int? versionSchema}) async {
    final version = versionSchema ?? (db is AppDatabase ? db.schemaVersion : null);
    final contenu = <String, Object?>{
      'format': format,
      'schema_version': version,
      'genere_le': maintenant.toIso8601String(),
      'tables': <String, Object?>{},
    };
    final cibles = contenu['tables']! as Map<String, Object?>;
    for (final t in await tables(db)) {
      cibles[t] = [
        for (final r in await db.customSelect('SELECT * FROM "$t"').get())
          {for (final e in r.data.entries) e.key: _versJson(e.value)},
      ];
    }
    return Uint8List.fromList(utf8.encode(jsonEncode(contenu)));
  }

  static Object? _versJson(Object? v) => v is List<int> ? {_marqueOctets: base64Encode(v)} : v;

  static Object? _depuisJson(Object? v) =>
      v is Map && v.containsKey(_marqueOctets) ? Uint8List.fromList(base64Decode(v[_marqueOctets] as String)) : v;

  /// Rejoue une sauvegarde dans [db] : chaque table du fichier est VIDÉE puis remplie (colonnes communes), dans UNE
  /// transaction (tout ou rien). Rend le nombre de lignes reprises. ⚠️ Réservé aux essais et à une future restauration :
  /// la restauration depuis l'écran reste REFUSÉE au navigateur (une base ouverte ne se remplace pas à chaud).
  static Future<int> importer(GeneratedDatabase db, List<int> octets, {int? versionSchema}) async {
    final Object? brut;
    try {
      brut = jsonDecode(utf8.decode(octets));
    } on FormatException {
      throw const FormatException('Fichier de sauvegarde illisible.');
    }
    if (brut is! Map || brut['format'] != format || brut['tables'] is! Map) {
      throw const FormatException('Ce fichier n\'est pas une sauvegarde complète du poste.');
    }
    final Map<dynamic, dynamic> doc = brut;
    final version = versionSchema ?? (db is AppDatabase ? db.schemaVersion : null);
    if (version != null && doc['schema_version'] != version) {
      throw FormatException('Sauvegarde du schéma ${doc['schema_version']} : cette base est au schéma $version.');
    }
    final presentes = (await tables(db)).toSet();
    var repris = 0;
    await db.transaction(() async {
      for (final e in (doc['tables'] as Map).entries) {
        final t = e.key as String;
        if (!presentes.contains(t)) continue;
        final colonnes = {
          for (final r in await db.customSelect('PRAGMA table_info("$t")').get()) r.read<String>('name'),
        };
        await db.customStatement('DELETE FROM "$t"');
        for (final ligne in (e.value as List).cast<Map<String, dynamic>>()) {
          final cles = [for (final c in ligne.keys) if (colonnes.contains(c)) c];
          if (cles.isEmpty) continue;
          await db.customStatement(
            'INSERT INTO "$t" (${cles.map((c) => '"$c"').join(', ')}) VALUES (${List.filled(cles.length, '?').join(', ')})',
            [for (final c in cles) _depuisJson(ligne[c])],
          );
          repris++;
        }
      }
    });
    return repris;
  }
}
