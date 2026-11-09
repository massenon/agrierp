import 'dart:io';

import 'package:agrierp/core/systeme/dossier_documents.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Renommage du produit en LogiAgriERP : le dossier « Documents\AgriERP » des postes déjà installés est REPRIS dans
/// « Documents\LogiAgriERP » — aucun export, archive ni reçu n'est abandonné, rien n'est écrasé.
void main() {
  late Directory documents;

  setUp(() => documents = Directory.systemTemp.createTempSync('docs_poste_'));
  tearDown(() => documents.deleteSync(recursive: true));

  String chemin(String dossier, [String? nom]) => nom == null ? p.join(documents.path, dossier) : p.join(documents.path, dossier, nom);

  test('poste neuf : le dossier LogiAgriERP est créé, aucun ancien dossier n\'apparaît', () async {
    final d = await dossierDocumentsPoste(racine: documents);
    expect(d.path, chemin('LogiAgriERP'));
    expect(d.existsSync(), isTrue);
    expect(Directory(chemin('AgriERP')).existsSync(), isFalse);
  });

  test('ancien dossier seul : renommé, son contenu est conservé', () async {
    Directory(chemin('AgriERP')).createSync();
    File(chemin('AgriERP', 'rapport.xlsx')).writeAsStringSync('ancien');
    Directory(chemin('AgriERP', 'sauvegardes')).createSync();
    File(chemin('AgriERP', 'sauvegardes/a.json')).writeAsStringSync('a');

    await dossierDocumentsPoste(racine: documents);

    expect(Directory(chemin('AgriERP')).existsSync(), isFalse);
    expect(File(chemin('LogiAgriERP', 'rapport.xlsx')).readAsStringSync(), 'ancien');
    expect(File(chemin('LogiAgriERP', 'sauvegardes/a.json')).readAsStringSync(), 'a');
  });

  test('les deux dossiers : fusion sans jamais écraser, l\'élément en collision reste dans l\'ancien', () async {
    Directory(chemin('AgriERP')).createSync();
    File(chemin('AgriERP', 'seul-dans-ancien.pdf')).writeAsStringSync('ancien');
    File(chemin('AgriERP', 'commun.pdf')).writeAsStringSync('ancien commun');
    Directory(chemin('LogiAgriERP')).createSync();
    File(chemin('LogiAgriERP', 'commun.pdf')).writeAsStringSync('nouveau commun');

    await dossierDocumentsPoste(racine: documents);

    expect(File(chemin('LogiAgriERP', 'seul-dans-ancien.pdf')).readAsStringSync(), 'ancien');
    expect(File(chemin('LogiAgriERP', 'commun.pdf')).readAsStringSync(), 'nouveau commun', reason: 'jamais écrasé');
    expect(File(chemin('AgriERP', 'commun.pdf')).readAsStringSync(), 'ancien commun', reason: 'la collision reste en place');
  });

  test('les deux dossiers sans collision : l\'ancien, devenu vide, est supprimé', () async {
    Directory(chemin('AgriERP')).createSync();
    File(chemin('AgriERP', 'a.pdf')).writeAsStringSync('a');
    Directory(chemin('LogiAgriERP')).createSync();

    await dossierDocumentsPoste(racine: documents);

    expect(Directory(chemin('AgriERP')).existsSync(), isFalse);
    expect(File(chemin('LogiAgriERP', 'a.pdf')).existsSync(), isTrue);
  });

  test('la reprise est idempotente : un second appel ne change rien', () async {
    Directory(chemin('AgriERP')).createSync();
    File(chemin('AgriERP', 'a.pdf')).writeAsStringSync('a');
    await dossierDocumentsPoste(racine: documents);
    await dossierDocumentsPoste(racine: documents);
    expect(File(chemin('LogiAgriERP', 'a.pdf')).readAsStringSync(), 'a');
    expect(Directory(chemin('AgriERP')).existsSync(), isFalse);
  });
}
