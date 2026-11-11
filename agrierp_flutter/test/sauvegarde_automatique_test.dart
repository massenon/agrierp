import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sauvegarde_automatique.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late Directory dossierTemp;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dossierTemp = await Directory.systemTemp.createTemp('sauvegarde_auto_test_');
  });

  tearDown(() async {
    await db.close();
    if (await dossierTemp.exists()) await dossierTemp.delete(recursive: true);
  });

  Future<Directory> monDossier() async => dossierTemp;

  group('avantMigration', () {
    test('crée un fichier _migration.sqlite dans le dossier', () async {
      final maintenant = DateTime(2026, 11, 11, 8, 30);

      await SauvegardeAutomatique.avantMigration(
        db,
        86,
        87,
        maintenant: () => maintenant,
        dossier: monDossier,
      );

      final fichiers = await dossierTemp.list().toList();
      expect(fichiers.whereType<File>().length, 1);
      expect(
        p.basename(fichiers.first.path),
        contains('_migration.sqlite'),
      );
      expect(
        p.basename(fichiers.first.path),
        contains('v86_vers_v87'),
      );
    });

    test('le nom contient l horodatage du jour', () async {
      final maintenant = DateTime(2026, 11, 11, 8, 5);

      await SauvegardeAutomatique.avantMigration(
        db,
        85,
        87,
        maintenant: () => maintenant,
        dossier: monDossier,
      );

      final fichiers = await dossierTemp.list().toList();
      expect(
        p.basename(fichiers.first.path),
        startsWith('backup_2026-11-11_0805'),
      );
    });

    test('supprime les fichiers migration de plus de 7 jours', () async {
      // Vieux fichier (8 jours)
      final vieux = File(p.join(dossierTemp.path, 'backup_2026-11-03_0800_v85_vers_v86_migration.sqlite'));
      await vieux.writeAsString('x');
      // Modifier la date de modification à 8 jours
      final dateVieille = DateTime(2026, 11, 3, 8, 0);
      await vieux.setLastModified(dateVieille);

      await SauvegardeAutomatique.avantMigration(
        db,
        86,
        87,
        maintenant: () => DateTime(2026, 11, 11, 8, 0),
        dossier: monDossier,
      );

      expect(await vieux.exists(), isFalse);
    });

    test('conserve les fichiers migration de moins de 7 jours', () async {
      // Fichier récent (3 jours)
      final recent = File(p.join(dossierTemp.path, 'backup_2026-11-08_0800_v85_vers_v86_migration.sqlite'));
      await recent.writeAsString('x');
      await recent.setLastModified(DateTime(2026, 11, 8, 8, 0));

      await SauvegardeAutomatique.avantMigration(
        db,
        86,
        87,
        maintenant: () => DateTime(2026, 11, 11, 8, 0),
        dossier: monDossier,
      );

      expect(await recent.exists(), isTrue);
    });
  });

  group('quotidienne', () {
    test('crée un fichier _quotidien.sqlite', () async {
      final maintenant = DateTime(2026, 11, 11, 9, 0);

      await SauvegardeAutomatique.quotidienne(
        db,
        maintenant: () => maintenant,
        dossier: monDossier,
      );

      final fichiers = await dossierTemp.list().toList();
      expect(fichiers.whereType<File>().length, 1);
      expect(p.basename(fichiers.first.path), contains('_quotidien.sqlite'));
    });

    test('ne crée pas un second fichier si un quotidien du jour existe', () async {
      final maintenant = DateTime(2026, 11, 11, 10, 0);

      // Premier appel
      await SauvegardeAutomatique.quotidienne(
        db,
        maintenant: () => maintenant,
        dossier: monDossier,
      );
      // Second appel le même jour
      await SauvegardeAutomatique.quotidienne(
        db,
        maintenant: () => maintenant.add(const Duration(hours: 1)),
        dossier: monDossier,
      );

      final fichiers = await dossierTemp.list().where((f) => f is File && p.basename(f.path).endsWith('_quotidien.sqlite')).toList();
      expect(fichiers.length, 1);
    });

    test('crée un nouveau fichier le lendemain', () async {
      final jour1 = DateTime(2026, 11, 11, 9, 0);
      final jour2 = DateTime(2026, 11, 12, 9, 0);

      await SauvegardeAutomatique.quotidienne(
        db,
        maintenant: () => jour1,
        dossier: monDossier,
      );
      await SauvegardeAutomatique.quotidienne(
        db,
        maintenant: () => jour2,
        dossier: monDossier,
      );

      final fichiers = await dossierTemp
          .list()
          .where((f) => f is File && p.basename(f.path).endsWith('_quotidien.sqlite'))
          .toList();
      expect(fichiers.length, 2);
    });

    test('supprime les fichiers quotidiens de plus de 7 jours', () async {
      final vieux = File(p.join(dossierTemp.path, 'backup_2026-11-03_0900_quotidien.sqlite'));
      await vieux.writeAsString('x');
      await vieux.setLastModified(DateTime(2026, 11, 3, 9, 0));

      await SauvegardeAutomatique.quotidienne(
        db,
        maintenant: () => DateTime(2026, 11, 11, 9, 0),
        dossier: monDossier,
      );

      expect(await vieux.exists(), isFalse);
    });
  });
}
