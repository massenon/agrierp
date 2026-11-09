import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;

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
/// PWA-2c — [restaurer] : la RESTAURATION de ce fichier au navigateur, tout ou rien, dans un état sûr (voir sa docstring).
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

/// PWA-2c — une restauration REFUSÉE, avec son motif français (rien n'a été modifié).
class RestaurationRefusee implements Exception {
  const RestaurationRefusee(this.message);

  final String message;

  @override
  String toString() => message;
}

/// PWA-2c — RESTAURATION d'une sauvegarde complète JSON dans la base ouverte du navigateur.
///
/// ÉTAT SÛR EXIGÉ : la base locale n'a AUCUNE ligne `pending` / `conflict` (sinon des saisies jamais parties seraient
/// effacées : refus, « synchronisez d'abord »). Contrôles STRICTS avant la moindre écriture, refus TOTAL au premier écart :
/// format, `schema_version` entier et pas plus récent que l'application, chaque table et chaque colonne du fichier connues de
/// la base, chaque ligne un objet. Puis UNE transaction : toutes les tables sont vidées et remplies (la base devient
/// EXACTEMENT la sauvegarde), sauf l'identité de ce poste (`poste.identifiant`, `poste.adresse_serveur`) qui n'est jamais
/// reprise d'un autre poste. Une erreur SQL en cours de route annule tout.
///
/// Une sauvegarde d'un schéma plus ANCIEN est acceptée si toutes ses tables et colonnes sont connues (les colonnes ajoutées
/// depuis prennent leur valeur par défaut) ; si une colonne obligatoire manque, la transaction échoue et rien ne change.
class RestaurationSauvegarde {
  const RestaurationSauvegarde._();

  static const motifEtatNonSur =
      'Des saisies ne sont pas encore envoyées au serveur : les remplacer par une sauvegarde les ferait disparaître. '
      'Synchronisez d\'abord, puis recommencez la restauration.';

  /// Clés de `app_settings` qui identifient CE poste : jamais écrasées par la sauvegarde.
  static const clesConservees = {'poste.identifiant', 'poste.adresse_serveur'};

  /// Nombre de lignes `pending` / `conflict` dans toutes les tables qui portent `sync_status`.
  static Future<int> saisiesNonEnvoyees(GeneratedDatabase db) async {
    var total = 0;
    for (final t in await SauvegardeCompleteJson.tables(db)) {
      final colonnes = {
        for (final r in await db.customSelect('PRAGMA table_info("$t")').get()) r.read<String>('name'),
      };
      if (!colonnes.contains('sync_status')) continue;
      final n = await db.customSelect("SELECT COUNT(*) AS n FROM \"$t\" WHERE sync_status <> 'synced'").getSingle();
      total += n.read<int>('n');
    }
    return total;
  }

  /// Restaure [octets] dans [db] ; rend le nombre de lignes reprises. Lève [RestaurationRefusee] (rien n'est modifié).
  ///
  /// [ecrire] faux : ne FAIT QUE contrôler (fichier strict + état sûr) et rend 0, sans rien écrire — c'est ce que l'écran joue
  /// AVANT de demander la confirmation.
  static Future<int> restaurer(GeneratedDatabase db, List<int> octets, {int? versionSchema, bool ecrire = true}) async {
    // 1. Lecture et validation STRICTE du fichier, sans toucher à la base.
    final Object? brut;
    try {
      brut = jsonDecode(utf8.decode(octets));
    } on FormatException {
      throw const RestaurationRefusee('Fichier de sauvegarde illisible : ce n\'est pas un JSON valide.');
    }
    if (brut is! Map || brut['format'] != SauvegardeCompleteJson.format || brut['tables'] is! Map) {
      throw const RestaurationRefusee('Ce fichier n\'est pas une sauvegarde complète du poste.');
    }
    final version = versionSchema ?? (db is AppDatabase ? db.schemaVersion : null);
    final dansFichier = brut['schema_version'];
    if (dansFichier is! int) {
      throw const RestaurationRefusee('Sauvegarde refusée : version du schéma absente ou illisible.');
    }
    if (version != null && dansFichier > version) {
      throw RestaurationRefusee(
        'Cette sauvegarde vient d\'une version plus récente de l\'application (schéma $dansFichier, ce poste est au schéma $version) : '
        'mettez l\'application à jour avant de la restaurer.',
      );
    }
    final presentes = (await SauvegardeCompleteJson.tables(db)).toSet();
    final colonnesDe = <String, Set<String>>{};
    for (final t in presentes) {
      colonnesDe[t] = {
        for (final r in await db.customSelect('PRAGMA table_info("$t")').get()) r.read<String>('name'),
      };
    }
    final lignesParTable = <String, List<Map<String, Object?>>>{};
    for (final e in (brut['tables'] as Map).entries) {
      final t = e.key;
      if (t is! String || !presentes.contains(t)) {
        throw RestaurationRefusee('Sauvegarde refusée : la table « $t » est inconnue de ce poste.');
      }
      if (e.value is! List) throw RestaurationRefusee('Sauvegarde refusée : la table « $t » n\'est pas une liste.');
      final lignes = <Map<String, Object?>>[];
      for (final l in e.value as List) {
        if (l is! Map) throw RestaurationRefusee('Sauvegarde refusée : une ligne de « $t » n\'est pas un objet.');
        for (final c in l.keys) {
          if (c is! String || !colonnesDe[t]!.contains(c)) {
            throw RestaurationRefusee('Sauvegarde refusée : la colonne « $c » de la table « $t » est inconnue de ce poste.');
          }
        }
        lignes.add({for (final c in l.entries) c.key as String: SauvegardeCompleteJson._depuisJson(c.value)});
      }
      lignesParTable[t] = lignes;
    }

    // 2. ÉTAT SÛR : rien ne doit attendre d'être envoyé.
    final enAttente = await saisiesNonEnvoyees(db);
    if (enAttente > 0) {
      throw const RestaurationRefusee(motifEtatNonSur);
    }

    if (!ecrire) return 0;

    // 3. Tout ou rien.
    var repris = 0;
    try {
      await db.transaction(() async {
        // Les clés étrangères éventuelles ne sont vérifiées qu'à la validation : l'ordre de remplissage est sans importance.
        await db.customStatement('PRAGMA defer_foreign_keys = ON');
        for (final t in presentes) {
          if (t == 'app_settings') {
            await db.customStatement(
              'DELETE FROM "app_settings" WHERE "key" NOT IN (${clesConservees.map((_) => '?').join(', ')})',
              clesConservees.toList(),
            );
          } else {
            await db.customStatement('DELETE FROM "$t"');
          }
        }
        for (final e in lignesParTable.entries) {
          for (final ligne in e.value) {
            if (e.key == 'app_settings' && clesConservees.contains(ligne['key'])) continue;
            final cles = ligne.keys.toList();
            if (cles.isEmpty) continue;
            await db.customStatement(
              'INSERT INTO "${e.key}" (${cles.map((c) => '"$c"').join(', ')}) VALUES (${List.filled(cles.length, '?').join(', ')})',
              [for (final c in cles) ligne[c]],
            );
            repris++;
          }
        }
      });
    } on Object catch (e) {
      if (e is RestaurationRefusee) rethrow;
      // Le détail technique (anglais) reste dans la console, jamais à l'écran.
      debugPrint(e.toString());
      throw const RestaurationRefusee('Restauration annulée : le contenu du fichier est incompatible avec ce poste. Rien n\'a été modifié.');
    }
    return repris;
  }
}
