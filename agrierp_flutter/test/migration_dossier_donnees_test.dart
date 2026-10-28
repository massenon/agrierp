import 'dart:io';

import 'package:agrierp/core/demarrage/migration_dossier_donnees.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket DES-2 — le dossier des données passe de `bj.olouwachegoun` à `OLOUWACHEGOUN` sans rien perdre.
void main() {
  late Directory racine;

  setUp(() async => racine = await Directory.systemTemp.createTemp('appdata_test'));
  tearDown(() async => racine.delete(recursive: true));

  Directory ancien() => Directory('${racine.path}/bj.olouwachegoun/agrierp');
  Directory nouveau() => Directory('${racine.path}/OLOUWACHEGOUN/agrierp');

  test('⚠️ un poste en service retrouve sa base, ses sous-dossiers et ses journaux sous le nouveau nom', () async {
    await Directory('${ancien().path}/sauvegardes').create(recursive: true);
    await File('${ancien().path}/agrierp.sqlite').writeAsString('BASE');
    await File('${ancien().path}/demarrage.log').writeAsString('journal');
    await File('${ancien().path}/sauvegardes/b.sqlite').writeAsString('copie');

    expect(await MigrationDossierDonnees.migrer(nouveau: nouveau()), isTrue);

    expect(await File('${nouveau().path}/agrierp.sqlite').readAsString(), 'BASE');
    expect(await File('${nouveau().path}/demarrage.log').readAsString(), 'journal');
    expect(await File('${nouveau().path}/sauvegardes/b.sqlite').readAsString(), 'copie');
    expect(await ancien().exists(), isFalse);
    expect(await Directory('${racine.path}/bj.olouwachegoun').exists(), isFalse, reason: 'le dossier éditeur vide disparaît');
  });

  test('⚠️ un dossier courant qui porte déjà une base n\'est JAMAIS écrasé', () async {
    await ancien().create(recursive: true);
    await File('${ancien().path}/agrierp.sqlite').writeAsString('ANCIENNE');
    await nouveau().create(recursive: true);
    await File('${nouveau().path}/agrierp.sqlite').writeAsString('COURANTE');

    expect(await MigrationDossierDonnees.migrer(nouveau: nouveau()), isFalse);

    expect(await File('${nouveau().path}/agrierp.sqlite').readAsString(), 'COURANTE');
    expect(await File('${ancien().path}/agrierp.sqlite').readAsString(), 'ANCIENNE');
  });

  test('un poste neuf (aucun ancien dossier) ne change rien et la migration ne se rejoue pas', () async {
    expect(await MigrationDossierDonnees.migrer(nouveau: nouveau()), isFalse);

    await ancien().create(recursive: true);
    await File('${ancien().path}/agrierp.sqlite').writeAsString('BASE');
    expect(await MigrationDossierDonnees.migrer(nouveau: nouveau()), isTrue);
    expect(await MigrationDossierDonnees.migrer(nouveau: nouveau()), isFalse);
  });
}
