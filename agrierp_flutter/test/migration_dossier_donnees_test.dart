import 'dart:io';

import 'package:agrierp/core/demarrage/migration_dossier_donnees.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket DES-2 — le dossier des données passe de `bj.olouwachegoun` à `OLOUWACHEGOUN` sans rien perdre.
void main() {
  late Directory racine;

  setUp(() async => racine = await Directory.systemTemp.createTemp('appdata_test'));
  tearDown(() async => racine.delete(recursive: true));

  Directory bj() => Directory('${racine.path}/bj.olouwachegoun/agrierp');
  Directory intermediaire() => Directory('${racine.path}/OLOUWACHEGOUN/agrierp');
  Directory donnees() => Directory('${racine.path}/OLOUWACHEGOUN/donnees');
  Future<bool> migrer() => MigrationDossierDonnees.migrer(appData: racine);

  test('⚠️ le dossier des données est OLOUWACHEGOUN\\donnees', () {
    expect(DossierDonnees.nomEditeur, 'OLOUWACHEGOUN');
    expect(DossierDonnees.nom, 'donnees');
  });

  test('⚠️ un poste en service (ancien nom bj.olouwachegoun) retrouve base, sous-dossiers et journaux sous OLOUWACHEGOUN\\donnees', () async {
    await Directory('${bj().path}/sauvegardes').create(recursive: true);
    await File('${bj().path}/agrierp.sqlite').writeAsString('BASE');
    await File('${bj().path}/demarrage.log').writeAsString('journal');
    await File('${bj().path}/sauvegardes/b.sqlite').writeAsString('copie');

    expect(await migrer(), isTrue);

    expect(await File('${donnees().path}/agrierp.sqlite').readAsString(), 'BASE');
    expect(await File('${donnees().path}/demarrage.log').readAsString(), 'journal');
    expect(await File('${donnees().path}/sauvegardes/b.sqlite').readAsString(), 'copie');
    expect(await bj().exists(), isFalse);
    expect(await Directory('${racine.path}/bj.olouwachegoun').exists(), isFalse, reason: 'le dossier éditeur vide disparaît');
  });

  test('le premier renommage (OLOUWACHEGOUN\\agrierp) est repris lui aussi, et son dossier vide ne reste pas', () async {
    await intermediaire().create(recursive: true);
    await File('${intermediaire().path}/agrierp.sqlite').writeAsString('BASE2');

    expect(await migrer(), isTrue);

    expect(await File('${donnees().path}/agrierp.sqlite').readAsString(), 'BASE2');
    expect(await intermediaire().exists(), isFalse);
  });

  test('⚠️ un dossier courant qui porte déjà une base n\'est JAMAIS écrasé', () async {
    await bj().create(recursive: true);
    await File('${bj().path}/agrierp.sqlite').writeAsString('ANCIENNE');
    await donnees().create(recursive: true);
    await File('${donnees().path}/agrierp.sqlite').writeAsString('COURANTE');

    expect(await migrer(), isFalse);

    expect(await File('${donnees().path}/agrierp.sqlite').readAsString(), 'COURANTE');
    expect(await File('${bj().path}/agrierp.sqlite').readAsString(), 'ANCIENNE');
  });

  test('un poste neuf ne change rien (le dossier vide laissé par path_provider disparaît) et la migration ne se rejoue pas', () async {
    await intermediaire().create(recursive: true);
    expect(await migrer(), isFalse);
    expect(await intermediaire().exists(), isFalse);

    await bj().create(recursive: true);
    await File('${bj().path}/agrierp.sqlite').writeAsString('BASE');
    expect(await migrer(), isTrue);
    expect(await migrer(), isFalse);
  });
}
