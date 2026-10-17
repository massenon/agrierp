import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/administration/administration_repository.dart';
import 'package:agrierp/features/administration/administration_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';

/// Ticket F0.49 — HUB ADMINISTRATION & DOCUMENT (`administration.html`).
///
/// ⚠️⚠️ Les trois onglets s'écrivent au poste : courriers (F0.78), documents archivés (F0.79) et
/// documents administratifs (F0.80) — voir `courriers_poste_test.dart`,
/// `archives_poste_test.dart` et `documents_poste_test.dart`. Ce fichier ne garde que les
/// contrôles communs au hub.
void main() {
  late AppDatabase db;
  late AdministrationRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  final aujourdhui = DateTime.now();

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = AdministrationRepository(database: db);
  });

  tearDown(() async => db.close());

  Future<void> courrier(
    String cle, {
    required String type,
    String objet = 'Accusé de réception du dossier de subvention',
    String? partie = 'PAEB',
    String? reference = 'CA-2026-007',
    DateTime? date,
  }) => db
      .into(db.mails)
      .insert(
        MailsCompanion.insert(
          id: uuid(cle),
          reference: Value(reference),
          type: type,
          subject: objet,
          party: Value(partie),
          mailDate: Value(date ?? aujourdhui),
        ),
      );

  Future<void> archive(
    String cle, {
    String titre = 'Agrément vétérinaire',
    String? categorie = 'Agréments',
    DateTime? expiration,
  }) => db
      .into(db.archivedDocuments)
      .insert(
        ArchivedDocumentsCompanion.insert(
          id: uuid(cle),
          title: titre,
          category: Value(categorie),
          archivedDate: Value(aujourdhui),
          expiryDate: Value(expiration),
        ),
      );

  Future<void> document(
    String cle, {
    String titre = 'Attestation de travail',
    String statut = 'signe',
    String? beneficiaire = 'Kossi AGBODJI',
  }) => db
      .into(db.administrativeDocuments)
      .insert(
        AdministrativeDocumentsCompanion.insert(
          id: uuid(cle),
          title: titre,
          type: const Value('Attestation'),
          beneficiary: Value(beneficiaire),
          docDate: Value(aujourdhui),
          status: Value(statut),
        ),
      );

  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      MaterialApp(home: AdministrationScreen(depot: depot)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ouvrir(WidgetTester tester, String onglet) async {
    await tester.tap(find.byKey(Key('onglet-administration-$onglet')));
    await tester.pumpAndSettle();
  }

  group('dépôt', () {
    test('les courriers du mois se comptent par sens', () async {
      await courrier('c1', type: 'entrant');
      await courrier('c2', type: 'sortant');
      await courrier(
        'vieux',
        type: 'entrant',
        date: DateTime(aujourdhui.year - 1, 3, 12),
      );

      final d = await depot.charger();

      expect(d.courriersDuMois.length, 2);
      expect(d.recus, 1);
      expect(d.envoyes, 1);
    });

    /// ⚠️⚠️ UNE ARCHIVE EXPIRÉE EST UN AGRÉMENT PÉRIMÉ, pas une ligne de
    /// tableau : c'est la seule donnée de cet écran qui doit alerter.
    // F0.79 : l'ancien seuil « À renouveler » (60 j) n'existait ni dans la maquette ni sur le
    // serveur ; « Bientôt expiré » est celui du serveur (1 à 30 jours, 30 inclus).
    test(
      '⚠️⚠️ les archives expirées se distinguent de celles bientôt expirées',
      () async {
        final jour = DateTime(
          aujourdhui.year,
          aujourdhui.month,
          aujourdhui.day,
        );

        await archive(
          'perime',
          expiration: jour.subtract(const Duration(days: 5)),
        );
        await archive(
          'bientot',
          expiration: jour.add(const Duration(days: 30)),
        );
        await archive(
          'valide',
          expiration: jour.add(const Duration(days: 400)),
        );
        await archive('sans', expiration: null);

        final d = await depot.charger();

        expect(d.expirees(jour).length, 1);
        expect(
          d.bientotExpirees(jour).length,
          1,
          reason: '+30 jours : dans le seuil du serveur',
        );
      },
    );

    // F0.80 : la carte « Signés » (absente de la maquette) est retirée ; « En attente »
    // (signature) est un écart assumé. Les cartes sont recalculées en détail dans
    // `documents_poste_test.dart`.
    test('les documents en attente de signature se comptent', () async {
      await document('d1', statut: 'signe');
      await document('d2', statut: 'en_attente');

      final d = await depot.charger();

      expect(d.documentsEnAttente, 1);
    });
  });

  group('écran', () {
    /// ⚠️⚠️ **LE NOMBRE DE CARTES, ONGLET PAR ONGLET** (ticket F0.54). Chaque
    /// onglet du hub est une page distincte de la maquette : le contrôle se fait
    /// donc page par page, sans arbitrage sur la répartition.
    testWidgets('⚠️⚠️ chaque onglet rend le nombre de cartes de sa page', (
      tester,
    ) async {
      await afficher(tester);

      const pages = <String, String>{
        'Gestion des Courriers': 'gestion-courriers.html',
        'Archivage des Documents': 'archivage-documents.html',
        'Documents Administratifs': 'documents-administratifs.html',
      };

      for (final onglet in pages.keys) {
        await ouvrir(tester, onglet);
        expect(
          find.byType(CarteKpi),
          findsNWidgets(cartesAttendues(pages[onglet]!)),
          reason: onglet,
        );
      }
    });

    testWidgets('⚠️ les trois onglets du hub sont là, dans son ordre', (
      tester,
    ) async {
      await afficher(tester);

      for (final onglet in [
        'Gestion des Courriers',
        'Archivage des Documents',
        'Documents Administratifs',
      ]) {
        expect(find.text(onglet), findsWidgets, reason: onglet);
      }
    });

    testWidgets('les courriers portent les six colonnes de la maquette', (
      tester,
    ) async {
      await afficher(tester);

      for (final colonne in [
        'RÉFÉRENCE',
        'TYPE',
        'OBJET',
        'PARTIE',
        'DATE',
        'ACTIONS',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
    });

    testWidgets('un courrier descendu est affiché avec son sens', (
      tester,
    ) async {
      await courrier('c1', type: 'entrant');

      await afficher(tester);

      expect(find.text('CA-2026-007'), findsOneWidget);
      expect(find.text('Entrant'), findsOneWidget);
      expect(find.text('PAEB'), findsOneWidget);
    });

    testWidgets('les archives portent les six colonnes de la maquette', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Archivage des Documents');

      for (final colonne in [
        'DOCUMENT',
        'CATÉGORIE',
        'DATE ARCHIVAGE',
        'EXPIRATION',
        'STATUT',
        'ACTIONS',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
    });

    /// ⚠️⚠️ L'ALERTE QUI JUSTIFIE L'ÉCRAN : un agrément périmé expose la ferme.
    testWidgets('⚠️⚠️ une archive expirée est signalée comme telle', (
      tester,
    ) async {
      final jour = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);
      await archive(
        'perime',
        titre: 'Agrément vétérinaire',
        expiration: jour.subtract(const Duration(days: 5)),
      );

      await afficher(tester);
      await ouvrir(tester, 'Archivage des Documents');

      expect(find.text('Agrément vétérinaire'), findsOneWidget);
      expect(find.text('Expiré'), findsOneWidget);
    });

    // F0.79 : « À renouveler » (60 j) est devenu « Bientôt expiré » (1 à 30 j, serveur).
    testWidgets('une archive proche de son échéance est « Bientôt expiré »', (
      tester,
    ) async {
      final jour = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);
      await archive('bientot', expiration: jour.add(const Duration(days: 20)));

      await afficher(tester);
      await ouvrir(tester, 'Archivage des Documents');

      expect(find.text('Bientôt expiré'), findsOneWidget);
      expect(find.text('À renouveler'), findsNothing);
    });

    testWidgets('les documents portent les six colonnes de la maquette', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Documents Administratifs');

      for (final colonne in [
        'DOCUMENT',
        'TYPE',
        'BÉNÉFICIAIRE',
        'DATE',
        'STATUT',
        'ACTIONS',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
    });

    testWidgets('un document en attente de signature le dit', (tester) async {
      await document('d1', statut: 'en_attente');

      await afficher(tester);
      await ouvrir(tester, 'Documents Administratifs');

      expect(find.text('En attente'), findsWidgets);
      expect(find.text('Kossi AGBODJI'), findsOneWidget);
    });

    /// ⚠️⚠️ Chaque onglet dit pourquoi il ne crée rien — trois raisons
    /// différentes, jamais un « non embarqué » générique.
    testWidgets('⚠️⚠️ chaque onglet porte son motif de lecture seule', (
      tester,
    ) async {
      await afficher(tester);
      // F0.78 : l'onglet courriers s'écrit au poste ; l'ancien motif « la pièce scannée »
      // était faux (ni la maquette ni le schéma n'ont de pièce jointe). Sa mention dit
      // désormais d'où vient la référence.
      expect(find.textContaining('attribuée par le serveur'), findsOneWidget);

      await ouvrir(tester, 'Archivage des Documents');
      // F0.79 : l'archivage s'écrit au poste ; l'ancien motif « se fait sur la surface web »
      // était faux. La mention dit désormais d'où vient le statut.
      expect(
        find.textContaining("se calcule sur le poste d'après sa date"),
        findsOneWidget,
      );

      // F0.80 : le document administratif s'écrit au poste, mais ne produit AUCUN fichier :
      // la mention le dit (libellé « Générer » de la maquette = risque de promesse trompeuse).
      await ouvrir(tester, 'Documents Administratifs');
      expect(find.textContaining('aucun fichier'), findsOneWidget);
    });

    testWidgets('sans donnée, chaque tableau le dit', (tester) async {
      await afficher(tester);
      // F0.78 : l'état vide des courriers est celui de la maquette (avec son bouton).
      expect(find.text('Aucun résultat trouvé'), findsOneWidget);
      expect(find.byKey(const Key('nouveau-courrier-vide')), findsOneWidget);

      await ouvrir(tester, 'Archivage des Documents');
      // F0.79 : l'état vide des archives est celui de la maquette (avec son bouton).
      expect(find.text('Aucun résultat trouvé'), findsOneWidget);
      expect(find.byKey(const Key('nouveau-archive-vide')), findsOneWidget);

      await ouvrir(tester, 'Documents Administratifs');
      // F0.80 : l'état vide des documents administratifs est celui de la maquette.
      expect(find.text('Aucun résultat trouvé'), findsOneWidget);
      expect(find.byKey(const Key('nouveau-document-vide')), findsOneWidget);
    });
  });
}
