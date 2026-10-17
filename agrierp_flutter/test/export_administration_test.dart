import 'dart:convert';
import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/export/document_officiel.dart';
import 'package:agrierp/features/administration/administration_repository.dart';
import 'package:agrierp/features/administration/administration_screen.dart';
import 'package:agrierp/features/administration/documents_administration.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.82 — « Exporter PDF » des trois pages du hub Administration
/// (`gestion-courriers.html`, `archivage-documents.html`, `documents-administratifs.html`).
///
/// ⚠️⚠️ **TITRES, SOUS-TITRES, COLONNES ET ORDRE SONT CEUX DES FONCTIONS DE LA MAQUETTE**
/// (`exportCourriersPDF`, `exportDocumentsPDF`, `exportDocAdminPDF`), lus dans le HTML par un
/// test. ⚠️ **LES LIGNES EXPORTÉES SONT CELLES AFFICHÉES** : actifs seulement. Les valeurs
/// attendues sont écrites à la main, SANS passer par le dépôt de la page.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AdministrationRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  final maintenantFixe = DateTime(2027, 3, 1, 9, 30);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = AdministrationRepository(database: db);
  });

  tearDown(() async => db.close());

  Future<void> courrier(
    String cle, {
    String? reference,
    String type = 'entrant',
    String objet = 'Objet',
    String? partie,
    required DateTime date,
    bool actif = true,
    SyncStatus sync = SyncStatus.synced,
  }) => db
      .into(db.mails)
      .insert(
        MailsCompanion.insert(
          id: uuid(cle),
          reference: Value(reference),
          type: type,
          subject: objet,
          party: Value(partie),
          mailDate: Value(date),
          isActive: Value(actif),
          syncStatus: Value(sync),
        ),
      );

  Future<void> archive(
    String cle, {
    required String titre,
    String? categorie,
    required DateTime archivage,
    DateTime? echeance,
    bool actif = true,
    SyncStatus sync = SyncStatus.synced,
  }) => db
      .into(db.archivedDocuments)
      .insert(
        ArchivedDocumentsCompanion.insert(
          id: uuid(cle),
          title: titre,
          category: Value(categorie),
          archivedDate: Value(archivage),
          expiryDate: Value(echeance),
          isActive: Value(actif),
          syncStatus: Value(sync),
        ),
      );

  Future<void> docAdmin(
    String cle, {
    required String titre,
    String? type,
    String? beneficiaire,
    required DateTime date,
    String? statut,
    bool actif = true,
    SyncStatus sync = SyncStatus.synced,
  }) => db
      .into(db.administrativeDocuments)
      .insert(
        AdministrativeDocumentsCompanion.insert(
          id: uuid(cle),
          title: titre,
          type: Value(type),
          beneficiary: Value(beneficiaire),
          docDate: Value(date),
          status: Value(statut),
          isActive: Value(actif),
          syncStatus: Value(sync),
        ),
      );

  Future<void> jeuCourriers() async {
    await courrier(
      'c1',
      reference: 'CR-2026-054',
      objet: 'Convocation DDAEP',
      partie: 'DDAEP',
      date: DateTime(2026, 7, 12),
    );
    await courrier(
      'c2',
      type: 'sortant',
      objet: 'Demande de subvention',
      partie: 'PAEB',
      date: DateTime(2026, 7, 15),
      sync: SyncStatus.pending,
    );
    await courrier(
      'c3',
      reference: 'CR-2026-001',
      objet: 'Archivé, ne s’exporte pas',
      date: DateTime(2026, 1, 3),
      actif: false,
    );
    await courrier(
      'c4',
      reference: 'CR-2026-002',
      objet: 'Archivage refusé, ne s’exporte pas',
      date: DateTime(2026, 2, 3),
      actif: false,
      sync: SyncStatus.conflict,
    );
    await courrier(
      'c5',
      reference: 'CR-2026-055',
      objet: 'Note sans partie',
      date: DateTime(2026, 6, 1),
    );
  }

  Future<void> jeuArchives() async {
    await archive(
      'a1',
      titre: 'RCCM',
      categorie: 'Juridique',
      archivage: DateTime(2026, 1, 2),
    );
    await archive(
      'a2',
      titre: 'Agrément vétérinaire',
      categorie: 'Agréments',
      archivage: DateTime(2026, 3, 15),
      echeance: DateTime(2027, 2, 24),
    );
    await archive(
      'a3',
      titre: 'Retiré, ne s’exporte pas',
      categorie: 'Fiscal',
      archivage: DateTime(2026, 2, 2),
      actif: false,
    );
    await archive(
      'a4',
      titre: 'Bail',
      categorie: 'Foncier',
      archivage: DateTime(2025, 12, 1),
      echeance: DateTime(2027, 3, 11),
    );
    await archive(
      'a6',
      titre: 'Sans catégorie',
      archivage: DateTime(2025, 6, 1),
    );
    await archive(
      'a5',
      titre: 'Retrait refusé, ne s’exporte pas',
      categorie: 'Fiscal',
      archivage: DateTime(2026, 2, 3),
      actif: false,
      sync: SyncStatus.conflict,
    );
  }

  Future<void> jeuDocuments() async {
    await docAdmin(
      'd1',
      titre: 'Attestation de stage',
      type: 'Attestation',
      beneficiaire: 'AGOSSOU Félicité',
      date: DateTime(2026, 7, 12),
      statut: 'signe',
    );
    await docAdmin(
      'd2',
      titre: 'Note de service',
      type: 'Note interne',
      beneficiaire: 'Tout le personnel',
      date: DateTime(2026, 7, 10),
      statut: 'en_attente',
    );
    await docAdmin(
      'd3',
      titre: 'Retiré, ne s’exporte pas',
      type: 'Certificat',
      beneficiaire: 'X',
      date: DateTime(2026, 5, 1),
      statut: 'signe',
      actif: false,
    );
    await docAdmin(
      'd5',
      titre: 'Retrait refusé, ne s’exporte pas',
      type: 'Certificat',
      beneficiaire: 'Y',
      date: DateTime(2026, 9, 1),
      statut: 'signe',
      actif: false,
      sync: SyncStatus.conflict,
    );
    await docAdmin(
      'd4',
      titre: 'Courrier au maire',
      type: 'Correspondance',
      date: DateTime(2026, 8, 1),
    );
  }

  /// Cellules des lignes de données d'un document.
  List<List<String>> donnees(DocumentOfficiel d) => [
    for (final l in d.lignes.whereType<DonneesDocument>()) l.cellules,
  ];

  /// Glyphes manquants dessinés en carré barré (même lecture que F0.75).
  int glyphesManquants(Uint8List pdf) {
    final brut = latin1.decode(pdf);
    final signature = RegExp(
      r'0 0 m [\d.]+ [\d.]+ l 0 [\d.]+ m [\d.]+ 0 l 0 0 [\d.]+ [\d.]+ re',
    );
    var total = 0;
    for (final debut in RegExp(r'(?<!end)stream\r?\n').allMatches(brut)) {
      final fin = brut.indexOf('endstream', debut.end);
      if (fin < 0) continue;
      try {
        final flux = latin1.decode(
          ZLibDecoder().convert(pdf.sublist(debut.end, fin)),
          allowInvalid: true,
        );
        total += signature.allMatches(flux).length;
      } catch (_) {}
    }
    return total;
  }

  group('documents (constructeurs purs) — lignes recalculées SANS le dépôt', () {
    test(
      '⚠️⚠️ courriers : titre, sous-titre, colonnes de la maquette ; actifs seulement, '
      'référence non attribuée = « — »',
      () async {
        await jeuCourriers();
        final d = await depot.charger();

        final doc = DocumentsAdministration.courriers(d.courriers);

        expect(doc.titre, 'Registre des Courriers');
        expect(doc.sousTitre, 'Courriers entrants et sortants');
        expect(doc.entetes, ['Référence', 'Type', 'Objet', 'Partie', 'Date']);
        // Ordre de l'écran : date décroissante. Écrit à la main.
        expect(donnees(doc), [
          ['—', 'Sortant', 'Demande de subvention', 'PAEB', '15/07/2026'],
          [
            'CR-2026-054',
            'Entrant',
            'Convocation DDAEP',
            'DDAEP',
            '12/07/2026',
          ],
          ['CR-2026-055', 'Entrant', 'Note sans partie', '—', '01/06/2026'],
        ]);
        expect(doc.lignes.length, 3, reason: 'ni archivé, ni archivage refusé');
      },
    );

    test(
      '⚠️⚠️ archives : statut de la règle du serveur à la date injectée',
      () async {
        await jeuArchives();
        final d = await depot.charger();

        final doc = DocumentsAdministration.archives(
          d.archives,
          maintenantFixe,
        );

        expect(doc.titre, 'Archivage des Documents');
        expect(
          doc.sousTitre,
          'Documents administratifs, juridiques et fiscaux archivés',
        );
        expect(doc.entetes, [
          'Document',
          'Catégorie',
          'Date Archivage',
          'Expiration',
          'Statut',
        ]);
        // Horloge injectée au 01/03/2027 : 24/02/2027 est passé de 5 jours (Expiré), 11/03/2027 est dans
        // 10 jours (Bientôt). L'horloge réelle donnerait « Valide » : le test distingue les deux.
        expect(donnees(doc), [
          [
            'Agrément vétérinaire',
            'Agréments',
            '15/03/2026',
            '24/02/2027',
            'Expiré',
          ],
          ['RCCM', 'Juridique', '02/01/2026', '—', 'Valide'],
          ['Bail', 'Foncier', '01/12/2025', '11/03/2027', 'Bientôt expiré'],
          ['Sans catégorie', '—', '01/06/2025', '—', 'Valide'],
        ]);
        expect(doc.lignes.length, 4, reason: 'ni retiré, ni retrait refusé');
      },
    );

    test(
      '⚠️⚠️ documents administratifs : donnée absente = « — », jamais 0',
      () async {
        await jeuDocuments();
        final d = await depot.charger();

        final doc = DocumentsAdministration.documents(d.documents);

        expect(doc.titre, 'Documents Administratifs Générés');
        expect(doc.sousTitre, 'Attestations, certificats et correspondances');
        expect(doc.entetes, [
          'Document',
          'Type',
          'Bénéficiaire',
          'Date',
          'Statut',
        ]);
        expect(donnees(doc), [
          ['Courrier au maire', 'Correspondance', '—', '01/08/2026', '—'],
          [
            'Attestation de stage',
            'Attestation',
            'AGOSSOU Félicité',
            '12/07/2026',
            'Signé',
          ],
          [
            'Note de service',
            'Note interne',
            'Tout le personnel',
            '10/07/2026',
            'En attente',
          ],
        ]);
        expect(doc.lignes.length, 3, reason: 'le retiré ne s’exporte pas');
      },
    );

    test(
      '⚠️⚠️ un type de document libre reçu du serveur s’exporte tel quel',
      () async {
        await docAdmin(
          'd9',
          titre: 'PV',
          type: 'Procès-verbal',
          beneficiaire: 'CA',
          date: DateTime(2026, 9, 1),
          statut: 'signe',
        );
        final d = await depot.charger();

        expect(
          donnees(DocumentsAdministration.documents(d.documents)).single[1],
          'Procès-verbal',
        );
      },
    );

    test(
      'les titres, sous-titres et colonnes sont ceux des fonctions de la maquette',
      () {
        const dossier = 'C:/Projects/agrierp_laravel/prototype_html/';
        if (!File('${dossier}gestion-courriers.html').existsSync()) {
          markTestSkipped('maquette absente de ce poste de travail');
          return;
        }
        final cas = <String, DocumentOfficiel>{
          'gestion-courriers.html': DocumentsAdministration.courriers(const []),
          'archivage-documents.html': DocumentsAdministration.archives(
            const [],
            maintenantFixe,
          ),
          'documents-administratifs.html': DocumentsAdministration.documents(
            const [],
          ),
        };
        for (final e in cas.entries) {
          final html = File('$dossier${e.key}').readAsStringSync();
          final titre = RegExp(r"title: '([^']+)'").firstMatch(html)!.group(1)!;
          final sous = RegExp(
            r"subtitle: '([^']+)'",
          ).firstMatch(html)!.group(1)!;
          final tete = RegExp(
            r"tableHeadHtml: '<tr>(.*?)</tr>'",
          ).firstMatch(html)!.group(1)!;
          final colonnes = [
            for (final m in RegExp(r'<th>([^<]+)</th>').allMatches(tete))
              m.group(1)!,
          ];

          expect(e.value.titre, titre, reason: e.key);
          expect(e.value.sousTitre, sous, reason: e.key);
          expect(e.value.entetes, colonnes, reason: e.key);
        }
      },
    );

    test(
      '⚠️⚠️ aucun tiret ni apostrophe n’est dessiné en carré barré (polices passées)',
      () async {
        await jeuCourriers();
        await jeuArchives();
        await jeuDocuments();
        final d = await depot.charger();
        final polices = await ExportOfficiel.chargerPolices();

        for (final doc in [
          DocumentsAdministration.courriers(d.courriers),
          DocumentsAdministration.archives(d.archives, maintenantFixe),
          DocumentsAdministration.documents(d.documents),
        ]) {
          final octets = await ExportOfficiel.construire(
            doc,
            maintenant: maintenantFixe,
            polices: polices,
          );
          expect(octets.sublist(0, 4), [
            0x25,
            0x50,
            0x44,
            0x46,
          ], reason: doc.titre);
          expect(glyphesManquants(octets), 0, reason: doc.titre);
        }

        // Le pied de page est celui de ExportOfficiel : les trois structures.
        const credits = ExportOfficiel.creditsProjet;
        expect(credits, contains('PAEB'));
        expect(credits, contains('Cabinet FAGUEZ SARL'));
        expect(credits, contains('MASSENON Rhodes'));
      },
    );
  });

  group('F0.82-bis — trous de test relevés par l’audit', () {
    const piedUnique =
        '1 ligne(s) saisie(s) sur ce poste, pas encore reçue(s) par la ferme '
        '(en attente de synchronisation).';

    /// Horloge TARDIVE : la règle du serveur compte en jours calendaires, l'heure est ignorée.
    final tard = DateTime(2027, 3, 1, 23, 30);

    Future<void> echeances() async {
      await archive(
        'e0',
        titre: 'Échéance aujourd’hui',
        categorie: 'Juridique',
        archivage: DateTime(2027, 1, 1),
        echeance: DateTime(2027, 3, 1),
      );
      await archive(
        'e1',
        titre: 'Échéance +1',
        categorie: 'Juridique',
        archivage: DateTime(2027, 1, 2),
        echeance: DateTime(2027, 3, 2),
      );
      await archive(
        'e30',
        titre: 'Échéance +30',
        categorie: 'Juridique',
        archivage: DateTime(2027, 1, 3),
        echeance: DateTime(2027, 3, 31),
      );
      await archive(
        'e31',
        titre: 'Échéance +31',
        categorie: 'Juridique',
        archivage: DateTime(2027, 1, 4),
        echeance: DateTime(2027, 4, 1),
      );
    }

    // Ordre de l'écran : date d'archivage décroissante, soit +31, +30, +1, aujourd'hui.
    const attendus = ['Valide', 'Bientôt expiré', 'Bientôt expiré', 'Expiré'];

    test(
      '⚠️⚠️ export : échéance du jour = Expiré, +1 et +30 = Bientôt, +31 = Valide, à 23 h 30',
      () async {
        await echeances();
        final d = await depot.charger();

        final doc = DocumentsAdministration.archives(d.archives, tard);

        expect(donnees(doc).map((c) => c[4]), attendus);
        expect(donnees(doc).map((c) => c[3]), [
          '01/04/2027',
          '31/03/2027',
          '02/03/2027',
          '01/03/2027',
        ]);
      },
    );

    testWidgets(
      '⚠️⚠️ écran : mêmes statuts à 23 h 30, en pastilles et dans l’export',
      (tester) async {
        await echeances();
        final editions = <DocumentOfficiel>[];
        tester.view.physicalSize = const Size(1600, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: AdministrationScreen(
              depot: depot,
              maintenant: () => tard,
              imprimer: (document, quand) async {
                editions.add(document);
                return null;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const Key('onglet-administration-Archivage des Documents'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Expiré'), findsNWidgets(1));
        expect(find.text('Bientôt expiré'), findsNWidgets(2));
        expect(find.text('Valide'), findsNWidgets(1));

        await tester.tap(find.byKey(const Key('exporter-pdf-archives')));
        await tester.pumpAndSettle();
        expect(donnees(editions.single).map((c) => c[4]), attendus);
      },
    );

    test(
      '⚠️ une valeur faite d’espaces sort « — » (partie, catégorie, type, bénéficiaire)',
      () async {
        await courrier(
          'b1',
          objet: 'Courrier',
          partie: '   ',
          date: DateTime(2026, 7, 1),
        );
        await archive(
          'b2',
          titre: 'Archive',
          categorie: '  ',
          archivage: DateTime(2026, 7, 1),
        );
        await docAdmin(
          'b3',
          titre: 'Document',
          type: '   ',
          beneficiaire: '  ',
          date: DateTime(2026, 7, 1),
          statut: 'signe',
        );
        final d = await depot.charger();

        expect(
          donnees(DocumentsAdministration.courriers(d.courriers)).single[3],
          '—',
        );
        expect(
          donnees(
            DocumentsAdministration.archives(d.archives, maintenantFixe),
          ).single[1],
          '—',
        );
        final cellules = donnees(
          DocumentsAdministration.documents(d.documents),
        ).single;
        expect(cellules[1], '—');
        expect(cellules[2], '—');
      },
    );

    test(
      '⚠️ pied : une ligne ACTIVE en conflit compte comme « pas encore reçue »',
      () async {
        await docAdmin(
          'p1',
          titre: 'Synchronisé',
          type: 'Attestation',
          beneficiaire: 'A',
          date: DateTime(2026, 7, 1),
          statut: 'signe',
        );
        await docAdmin(
          'p2',
          titre: 'Création refusée',
          type: 'Attestation',
          beneficiaire: 'B',
          date: DateTime(2026, 7, 2),
          statut: 'signe',
          sync: SyncStatus.conflict,
        );
        final d = await depot.charger();

        expect(
          DocumentsAdministration.documents(d.documents).noteDePied,
          piedUnique,
        );
      },
    );

    test(
      '⚠️ pied : texte exact, en attente + conflit cumulés, et rien quand tout est reçu',
      () async {
        await docAdmin(
          'q1',
          titre: 'A',
          type: 'T',
          beneficiaire: 'B',
          date: DateTime(2026, 7, 1),
          statut: 'signe',
        );
        var d = await depot.charger();
        expect(
          DocumentsAdministration.documents(d.documents).noteDePied,
          isNull,
        );

        await docAdmin(
          'q2',
          titre: 'En attente',
          type: 'T',
          beneficiaire: 'B',
          date: DateTime(2026, 7, 2),
          statut: 'signe',
          sync: SyncStatus.pending,
        );
        await docAdmin(
          'q3',
          titre: 'Refusé',
          type: 'T',
          beneficiaire: 'B',
          date: DateTime(2026, 7, 3),
          statut: 'signe',
          sync: SyncStatus.conflict,
        );
        d = await depot.charger();

        expect(
          DocumentsAdministration.documents(d.documents).noteDePied,
          '2 ligne(s) saisie(s) sur ce poste, pas encore reçue(s) par la ferme '
          '(en attente de synchronisation).',
        );
      },
    );

    test(
      '⚠️ pied des courriers : mention de référence + lignes non reçues, texte exact',
      () async {
        await courrier(
          'r1',
          objet: 'Sans référence',
          date: DateTime(2026, 7, 1),
          sync: SyncStatus.pending,
        );
        final d = await depot.charger();

        expect(
          DocumentsAdministration.courriers(d.courriers).noteDePied,
          "« — » en Référence : le serveur l'attribue à la synchronisation. "
          '$piedUnique',
        );
      },
    );
  });

  group('câblage (lecture du code source : invisible au rendu)', () {
    test(
      '⚠️⚠️ l’éditeur de production passe les POLICES à ExportOfficiel.construire',
      () {
        final src = File(
          'lib/features/rapports/rapports_exports_screen.dart',
        ).readAsStringSync();
        final debut = src.indexOf('static Future<String?> imprimer(');
        final fin = src.indexOf('static Future<String?> enregistrer(');
        final corps = src.substring(debut, fin);

        expect(corps, contains('ExportOfficiel.chargerPolices()'));
        expect(corps, contains('polices: polices'));
      },
    );

    test(
      '⚠️ main.dart branche l’éditeur de production sur l’écran Administration',
      () {
        final src = File('lib/main.dart').readAsStringSync();
        final debut = src.indexOf('EcranPoste.administrationEtDocument =>');
        final fin = src.indexOf('EcranPoste.personnelEtStages =>');

        expect(
          src.substring(debut, fin),
          contains('imprimer: EditeursRapports.imprimer'),
        );
      },
    );
  });

  group('écran', () {
    late List<(DocumentOfficiel, DateTime)> editions;

    Future<void> afficher(WidgetTester tester, String onglet) async {
      editions = [];
      tester.view.physicalSize = const Size(1600, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: AdministrationScreen(
            depot: depot,
            maintenant: () => maintenantFixe,
            imprimer: (document, quand) async {
              editions.add((document, quand));
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('onglet-administration-$onglet')));
      await tester.pumpAndSettle();
    }

    testWidgets(
      '⚠️⚠️ courriers : « Exporter PDF » édite les lignes affichées',
      (tester) async {
        await jeuCourriers();
        await afficher(tester, 'Gestion des Courriers');

        expect(find.text('Exporter PDF'), findsOneWidget);
        await tester.tap(find.byKey(const Key('exporter-pdf-courriers')));
        await tester.pumpAndSettle();

        final (doc, quand) = editions.single;
        expect(doc.titre, 'Registre des Courriers');
        expect(quand, maintenantFixe);
        expect(donnees(doc).length, 3);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Document envoyé à l’impression.'), findsOneWidget);
      },
    );

    testWidgets('⚠️⚠️ archives : « Exporter PDF » édite les lignes affichées', (
      tester,
    ) async {
      await jeuArchives();
      await afficher(tester, 'Archivage des Documents');

      await tester.tap(find.byKey(const Key('exporter-pdf-archives')));
      await tester.pumpAndSettle();

      final (doc, _) = editions.single;
      expect(doc.titre, 'Archivage des Documents');
      expect(donnees(doc).map((c) => c[0]), [
        'Agrément vétérinaire',
        'RCCM',
        'Bail',
        'Sans catégorie',
      ]);
      // Statuts à l'horloge injectée (01/03/2027), pas à l'horloge réelle.
      expect(donnees(doc).map((c) => c[4]), [
        'Expiré',
        'Valide',
        'Bientôt expiré',
        'Valide',
      ]);
    });

    testWidgets(
      '⚠️⚠️ documents : « Exporter PDF » édite les lignes affichées',
      (tester) async {
        await jeuDocuments();
        await afficher(tester, 'Documents Administratifs');

        await tester.tap(find.byKey(const Key('exporter-pdf-documents')));
        await tester.pumpAndSettle();

        final (doc, _) = editions.single;
        expect(doc.titre, 'Documents Administratifs Générés');
        expect(donnees(doc).map((c) => c[0]), [
          'Courrier au maire',
          'Attestation de stage',
          'Note de service',
        ]);
      },
    );

    for (final (onglet, cle, message) in [
      (
        'Gestion des Courriers',
        'exporter-pdf-courriers',
        'Aucun courrier à exporter.',
      ),
      (
        'Archivage des Documents',
        'exporter-pdf-archives',
        'Aucun document archivé à exporter.',
      ),
      (
        'Documents Administratifs',
        'exporter-pdf-documents',
        'Aucun document à exporter.',
      ),
    ]) {
      testWidgets('⚠️ $onglet sans ligne : rien n’est édité, l’écran le dit', (
        tester,
      ) async {
        await afficher(tester, onglet);

        await tester.tap(find.byKey(Key(cle)));
        await tester.pumpAndSettle();

        expect(editions, isEmpty);
        expect(find.text(message), findsOneWidget);
      });
    }

    testWidgets('⚠️ le message rendu par l’éditeur est celui qui s’affiche', (
      tester,
    ) async {
      await jeuDocuments();
      tester.view.physicalSize = const Size(1600, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // Éditeur qui écrit un fichier et le dit (variante « Enregistrer au format PDF »).
      await tester.pumpWidget(
        MaterialApp(
          home: AdministrationScreen(
            depot: depot,
            maintenant: () => maintenantFixe,
            imprimer: (document, quand) async => 'Fichier enregistré.',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('onglet-administration-Documents Administratifs')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('exporter-pdf-documents')));
      await tester.pumpAndSettle();

      expect(find.text('Fichier enregistré.'), findsOneWidget);
      expect(find.text('Document envoyé à l’impression.'), findsNothing);
    });

    testWidgets(
      '⚠️⚠️ un éditeur qui lève ne produit ni erreur non gérée ni silence : un message',
      (tester) async {
        await jeuDocuments();
        tester.view.physicalSize = const Size(1600, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: AdministrationScreen(
              depot: depot,
              maintenant: () => maintenantFixe,
              imprimer: (document, quand) async =>
                  throw StateError('imprimante absente'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const Key('onglet-administration-Documents Administratifs'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('exporter-pdf-documents')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.text(
            'L’édition du document a échoué. Réessayez ou vérifiez l’imprimante.',
          ),
          findsOneWidget,
        );
        expect(find.text('Document envoyé à l’impression.'), findsNothing);
      },
    );

    testWidgets(
      '⚠️ seuls des retirés : rien n’est édité (la liste affichée est vide)',
      (tester) async {
        await docAdmin(
          'd3',
          titre: 'Retiré',
          type: 'Certificat',
          beneficiaire: 'X',
          date: DateTime(2026, 5, 1),
          statut: 'signe',
          actif: false,
        );
        await afficher(tester, 'Documents Administratifs');

        await tester.tap(find.byKey(const Key('exporter-pdf-documents')));
        await tester.pumpAndSettle();

        expect(editions, isEmpty);
        expect(find.text('Aucun document à exporter.'), findsOneWidget);
      },
    );

    testWidgets(
      '⚠️ sans éditeur injecté, le bouton ne fait rien (et ne plante pas)',
      (tester) async {
        await jeuCourriers();
        tester.view.physicalSize = const Size(1600, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(home: AdministrationScreen(depot: depot)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('exporter-pdf-courriers')));
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets('⚠️⚠️ exporter n’écrit rien (lecture seule)', (tester) async {
      await jeuCourriers();
      final avant =
          (await db.select(db.mails).get())
              .map(
                (m) => '${m.id}|${m.syncStatus}|${m.isActive}|${m.reference}',
              )
              .toList()
            ..sort();
      await afficher(tester, 'Gestion des Courriers');

      await tester.tap(find.byKey(const Key('exporter-pdf-courriers')));
      await tester.pumpAndSettle();

      final apres =
          (await db.select(db.mails).get())
              .map(
                (m) => '${m.id}|${m.syncStatus}|${m.isActive}|${m.reference}',
              )
              .toList()
            ..sort();
      expect(apres, avant);
    });
  });
}
