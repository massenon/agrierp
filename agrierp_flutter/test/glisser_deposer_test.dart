import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agrierp/core/config/apercu_image.dart';
import 'package:agrierp/core/config/fichiers_entreprise.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/widgets/zone_depot.dart';
import 'package:agrierp/features/importation/importation_repository.dart';
import 'package:agrierp/features/importation/importation_screen.dart';
import 'package:agrierp/features/parametres/parametres_generaux_repository.dart';
import 'package:agrierp/features/parametres/parametres_generaux_screen.dart';
import 'package:agrierp/features/parametres/reglages_ferme_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Ticket CONF-2 (08/11/2026) — GLISSER-DÉPOSER AU POSTE (`desktop_drop`) et APERÇU DE L'ICO.
///
/// Le plugin natif est absent en test : la source de dépôt est INJECTÉE (`SourceDepot.courante`), comme le sélecteur de
/// fichier. Le dépôt suit le MÊME chemin que le clic : mêmes refus, mêmes messages (`FichiersEntreprise.valider`).
class _SourceSimulee implements SourceDepot {
  final fichiers = <String, Uint8List>{};
  final zones = <({ValueChanged<bool> survol, Future<void> Function(List<String>) chemins})>[];

  @override
  Future<Uint8List?> lire(String chemin) async => fichiers[chemin];

  @override
  Widget envelopper({
    required Widget enfant,
    required ValueChanged<bool> surSurvol,
    required Future<void> Function(List<String> chemins) surChemins,
    required bool actif,
  }) {
    zones.add((survol: surSurvol, chemins: surChemins));
    return enfant;
  }

  /// Dernière construction de la zone `i` (chaque reconstruction en ajoute une).
  ({ValueChanged<bool> survol, Future<void> Function(List<String>) chemins}) zone(int i, int nombreDeZones) => zones[zones.length - nombreDeZones + i];
}

/// Fichiers de l'entreprise en mémoire (les E/S réelles n'avancent pas dans le temps simulé de `testWidgets`).
class _FichiersMemoire extends FichiersEntreprise {
  final octets = <String, Uint8List>{};

  @override
  Future<Uint8List?> lire(String genre) async => octets[genre];

  @override
  Future<void> effacer(String genre) async => octets.remove(genre);

  @override
  Future<void> enregistrer(String genre, Uint8List o, String nom, {String? sourceServeur}) async => octets[genre] = o;
}

Uint8List png([int cote = 16]) => Uint8List.fromList(img.encodePng(img.Image(width: cote, height: cote)));

/// Un `.ico` GÉNÉRÉ : en-tête, annuaire de deux images (16 et 32 px) qui contiennent chacune un PNG (ICO modernes).
Uint8List ico() {
  final images = [png(16), png(32)];
  final tailles = [16, 32];
  final sortie = BytesBuilder()..add([0, 0, 1, 0, images.length, 0]);
  var decalage = 6 + 16 * images.length;
  for (var i = 0; i < images.length; i++) {
    final e = ByteData(16)
      ..setUint8(0, tailles[i])
      ..setUint8(1, tailles[i])
      ..setUint16(4, 1, Endian.little)
      ..setUint16(6, 32, Endian.little)
      ..setUint32(8, images[i].length, Endian.little)
      ..setUint32(12, decalage, Endian.little);
    sortie.add(e.buffer.asUint8List());
    decalage += images[i].length;
  }
  for (final d in images) {
    sortie.add(d);
  }
  return sortie.toBytes();
}

void main() {
  late AppDatabase db;
  late _SourceSimulee source;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    source = _SourceSimulee();
    SourceDepot.courante = source;
  });
  tearDown(() async {
    SourceDepot.courante = const SourceDepotNative();
    await db.close();
  });

  group('aperçu de l\'ICO (D)', () {
    test('un ICO généré est décodé en PNG (la plus grande image) ; un PNG reste tel quel ; un ICO illisible vaut null', () {
      final fichier = ico();
      expect(FichiersEntreprise.typeDuContenu(fichier), 'ico');
      final apercu = apercuAffichable(fichier)!;
      expect(FichiersEntreprise.typeDuContenu(apercu), 'png');
      final decode = img.decodePng(apercu)!;
      expect(decode.width, 32);

      final p = png();
      expect(apercuAffichable(p), same(p));

      // En-tête ICO valide mais image tronquée.
      final casse = Uint8List.fromList([0, 0, 1, 0, 1, 0, 16, 16, 0, 0, 1, 0, 32, 0, 99, 0, 0, 0, 22, 0, 0, 0, 1, 2]);
      expect(apercuAffichable(casse), isNull);
    });
  });

  group('glisser-déposer · modale « Données de l\'Entreprise »', () {
    Future<void> ouvrir(WidgetTester tester, _FichiersMemoire fichiers) async {
      tester.view.physicalSize = const Size(1700, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await db.into(db.companySettings).insert(
        CompanySettingsCompanion.insert(
          id: const Value('unique'), companyName: const Value('Ferme'), ifu: const Value('3201700000000'), vpsRate: const Value(4), cnssEmployeeRate: const Value(3.6),
          cnssEmployerPensionRate: const Value(6.4), cnssEmployerFamilyRate: const Value(9), cnssEmployerRiskRate: const Value(2),
        ),
      );
      final depot = ReglagesFermeRepository(database: db, deviceId: 'poste-test', horloge: () => DateTime(2026, 11, 8, 10), fichiersEntreprise: fichiers);
      await tester.pumpWidget(MaterialApp(home: ParametresGenerauxScreen(
        depot: ParametresGenerauxRepository(database: db), reglages: depot, estAdmin: true, ongletInitial: "Données de l'Entreprise",
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('entreprise-modifier')));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
    }

    testWidgets('les invites annoncent le glisser-déposer (mêmes mots que le Blade)', (tester) async {
      await ouvrir(tester, _FichiersMemoire());
      expect(find.text('Glisser-déposer ou cliquer pour choisir un logo'), findsOneWidget);
      expect(find.text('Glisser-déposer ou cliquer pour choisir un favicon'), findsOneWidget);
    });

    testWidgets('un logo déposé s\'affiche (nom et aperçu), le survol s\'allume puis s\'éteint, et il est envoyé comme avec le clic', (tester) async {
      await ouvrir(tester, _FichiersMemoire());
      source.fichiers['/tmp/mon logo.png'] = png();
      final z = source.zone(0, 2);

      z.survol(true);
      await tester.pump();
      final decorationSurvol = tester.widget<Container>(find.descendant(of: find.byKey(const Key('entreprise-logo')), matching: find.byType(Container)).first).decoration! as BoxDecoration;
      expect(decorationSurvol.color, isNotNull, reason: 'fond de survol');

      z.survol(false); // le plugin éteint le survol au dépôt
      await z.chemins(['/tmp/mon logo.png']);
      await tester.pumpAndSettle();
      expect(find.text('mon logo.png'), findsOneWidget);
      expect(find.byKey(const Key('entreprise-logo-apercu')), findsOneWidget);
      final z2 = source.zone(0, 2);
      final sansSurvol = tester.widget<Container>(find.descendant(of: find.byKey(const Key('entreprise-logo')), matching: find.byType(Container)).first).decoration! as BoxDecoration;
      expect(sansSurvol.color, isNull, reason: 'le survol s\'éteint au dépôt');
      expect(z2, isNotNull);

      await tester.ensureVisible(find.byKey(const Key('entreprise-enregistrer')));
      await tester.tap(find.byKey(const Key('entreprise-enregistrer')));
      await tester.pumpAndSettle();
      final d = (await tester.runAsync(() => db.select(db.settingsRequests).get()))!.single;
      final charge = jsonDecode(d.payload) as Map;
      expect(charge['logoNom'], 'mon logo.png');
    });

    testWidgets('un ICO déposé sur le favicon est DESSINÉ (aperçu), pas seulement nommé', (tester) async {
      await ouvrir(tester, _FichiersMemoire());
      source.fichiers['/tmp/site.ico'] = ico();
      await source.zone(1, 2).chemins(['/tmp/site.ico']);
      await tester.pumpAndSettle();
      expect(find.text('site.ico'), findsOneWidget);
      expect(find.byKey(const Key('entreprise-favicon-apercu')), findsOneWidget);
    });

    testWidgets('même validation et mêmes messages que le clic : faux PNG, mauvais format, trop gros', (tester) async {
      await ouvrir(tester, _FichiersMemoire());
      source.fichiers['/tmp/faux.png'] = Uint8List.fromList(utf8.encode('ceci est du texte'));
      await source.zone(0, 2).chemins(['/tmp/faux.png']);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('entreprise-enregistrer')));
      await tester.tap(find.byKey(const Key('entreprise-enregistrer')));
      await tester.pumpAndSettle();
      expect(find.text(FichiersEntreprise.messages['logo']!['format']!), findsOneWidget);
      expect(await tester.runAsync(() => db.select(db.settingsRequests).get()), isEmpty, reason: 'rien n\'est écrit');

      // Un ICO sur le LOGO est refusé comme au clic.
      source.fichiers['/tmp/logo.ico'] = ico();
      await source.zone(0, 2).chemins(['/tmp/logo.ico']);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('entreprise-enregistrer')));
      await tester.pumpAndSettle();
      expect(find.text(FichiersEntreprise.messages['logo']!['format']!), findsOneWidget);

      // Trop gros pour le favicon (500 Ko).
      final gros = BytesBuilder()..add(png())..add(Uint8List(600 * 1024));
      source.fichiers['/tmp/gros.png'] = gros.toBytes();
      await source.zone(1, 2).chemins(['/tmp/gros.png']);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('entreprise-enregistrer')));
      await tester.pumpAndSettle();
      expect(find.text(FichiersEntreprise.messages['favicon']!['taille']!), findsOneWidget);
    });

    testWidgets('un seul fichier : le premier est retenu ; un dossier ou un fichier illisible ne choisit rien', (tester) async {
      await ouvrir(tester, _FichiersMemoire());
      source.fichiers['/tmp/a.png'] = png();
      source.fichiers['/tmp/b.png'] = png(20);
      await source.zone(0, 2).chemins(['/tmp/a.png', '/tmp/b.png']);
      await tester.pumpAndSettle();
      expect(find.text('a.png'), findsOneWidget);
      expect(find.text('b.png'), findsNothing);

      await source.zone(1, 2).chemins(['/tmp/dossier']); // absent de la source : illisible
      await tester.pumpAndSettle();
      expect(find.text('Glisser-déposer ou cliquer pour choisir un favicon'), findsOneWidget);
    });
  });

  group('glisser-déposer · Importation en masse', () {
    testWidgets('un fichier déposé suit le chemin du clic : un fichier qui n\'est pas un classeur affiche le même refus', (tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ImportationScreen(
          depot: ImportationRepository(database: db),
          role: 'admin',
          choisirFichier: () async => null,
          enregistrer: (nom, o) async => '/docs/$nom',
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('module-clients')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('importation-vers-depot')));
      await tester.pumpAndSettle();
      expect(find.text('Glissez votre fichier .xlsx (ou .csv) ici, ou cliquez pour le choisir'), findsOneWidget);

      source.fichiers['/tmp/liste.xlsx'] = Uint8List.fromList('pas un classeur'.codeUnits);
      await source.zones.last.chemins(['/tmp/liste.xlsx']);
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('importation-erreur')), findsOneWidget);
      expect(find.textContaining("n'est pas un classeur Excel (.xlsx) lisible"), findsOneWidget);
    });
  });

  group('garde de sources', () {
    test('le plugin `desktop_drop` n\'est déclaré qu\'une fois et n\'est importé que par la zone de dépôt', () {
      expect(File('pubspec.yaml').readAsStringSync(), contains('desktop_drop: ^0.8.4'));
      expect(File('pubspec.yaml').readAsStringSync(), contains('image: ^4.3.0'));
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('zone_depot.dart')) continue;
        expect(f.readAsStringSync(), isNot(contains('package:desktop_drop')), reason: f.path);
      }
      expect(File('.fvmrc').readAsStringSync(), contains('3.47.7'));
    });
  });
}
