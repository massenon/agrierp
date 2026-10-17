import 'dart:convert';
import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/export/document_officiel.dart';
import 'package:agrierp/features/achats/achats_commandes_screen.dart';
import 'package:agrierp/features/achats/achats_repository.dart';
import 'package:agrierp/features/achats/fournisseurs_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.75 — `liste-achats.html` : « Détail de l'Achat », « Exporter PDF »
/// et « Imprimer ».
///
/// ⚠️⚠️ **LECTURE SEULE.** Ni détail ni édition n'écrivent quoi que ce soit : un
/// test le compare, table par table, avant et après.
///
/// ⚠️ **TOUT CHIFFRE AFFICHÉ OU IMPRIMÉ EST RECALCULÉ INDÉPENDAMMENT** — par une
/// lecture directe de la base et un `int.parse` sur les chiffres de la cellule,
/// jamais en réutilisant le formateur testé.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AchatsRepository depot;
  late FournisseursRepository depotFournisseurs;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  final maintenantFixe = DateTime(2026, 10, 8, 9, 30);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = AchatsRepository(database: db, identifiantPoste: 'poste-test');
    depotFournisseurs = FournisseursRepository(
      database: db,
      deviceId: 'poste-test',
    );
  });

  tearDown(() async => db.close());

  Future<void> fournisseur(String cle, String nom) => db
      .into(db.suppliers)
      .insert(
        SuppliersCompanion.insert(
          id: uuid(cle),
          name: nom,
          category: const Value('Aliments'),
        ),
      );

  Future<void> achat(
    String cle, {
    required String cleFournisseur,
    required String nomFournisseur,
    required double total,
    required DateTime date,
    String? categorie = 'Aliments',
    bool envoye = true,
    bool dette = false,
    double regle = 0,
  }) => db
      .into(db.purchases)
      .insert(
        PurchasesCompanion.insert(
          id: uuid(cle),
          deviceId: envoye ? 'serveur' : 'poste-test',
          updatedAt: date,
          syncStatus: Value(envoye ? SyncStatus.synced : SyncStatus.pending),
          supplierId: uuid(cleFournisseur),
          supplierName: Value(nomFournisseur),
          supplierCategory: Value(categorie),
          paymentMode: 'especes',
          total: total,
          amountPaid: Value(regle),
          hasDebt: Value(dette),
          purchaseDate: date,
        ),
      );

  /// Jeu : deux achats reçus du serveur et un saisi ici, pas encore parti.
  Future<void> jeu() async {
    await fournisseur('f1', 'Provenderie du Plateau');
    await fournisseur('f2', 'Véto-Santé Bénin');
    await achat(
      'a1',
      cleFournisseur: 'f1',
      nomFournisseur: 'Provenderie du Plateau',
      total: 185000,
      date: DateTime(2026, 7, 14),
    );
    await achat(
      'a2',
      cleFournisseur: 'f2',
      nomFournisseur: 'Véto-Santé Bénin',
      total: 62500,
      date: DateTime(2026, 7, 10),
      categorie: null,
      dette: true,
      regle: 20000,
    );
    await achat(
      'a3',
      cleFournisseur: 'f1',
      nomFournisseur: 'Provenderie du Plateau',
      total: 285500,
      date: DateTime(2026, 8, 2),
      envoye: false,
    );
  }

  /// Instantané des tables financières : la lecture ne doit rien y changer.
  Future<List<int>> empreinte() async => [
    (await db.select(db.purchases).get()).length,
    (await db.select(db.purchaseLines).get()).length,
    (await db.select(db.payables).get()).length,
    (await db.select(db.supplierPayments).get()).length,
    (await db.select(db.expenses).get()).length,
    (await db.select(db.accountingEntries).get()).length,
    (await db.select(db.accountingEntryLines).get()).length,
  ];

  /// Seuls les chiffres d'une cellule « 185 000 FCFA » — sans passer par le
  /// formateur testé.
  int chiffres(String cellule) =>
      int.parse(cellule.replaceAll(RegExp(r'[^0-9]'), ''));

  /// Nombre de glyphes manquants dessinés en carré barré : décompresse chaque
  /// flux du PDF et compte la signature « diagonales + rectangle » du moteur.
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
      } catch (_) {
        // Flux binaire non compressé (image) : pas du texte.
      }
    }
    return total;
  }

  group('documents (constructeurs purs)', () {
    test('⚠️ la liste reprend titre, sous-titre et cinq colonnes de la '
        'maquette', () async {
      await jeu();
      final d = await depot.charger();

      final doc = DocumentsAchats.liste(d.achats);

      expect(doc.titre, 'Liste des Achats');
      expect(doc.sousTitre, 'Historique des achats et bons de commande');
      expect(doc.entetes, [
        'Référence Achat',
        'Date',
        'Fournisseur',
        'Catégorie',
        'Montant Total',
      ]);
      expect(doc.colonnes, 5);
    });

    /// ⚠️⚠️ Le total imprimé = la somme de la base, relue sans le dépôt.
    test('⚠️⚠️ les montants imprimés se recalculent depuis la base', () async {
      await jeu();
      final doc = DocumentsAchats.liste((await depot.charger()).achats);

      final lignes = doc.lignes.cast<DonneesDocument>();
      expect(lignes.length, 3);

      final imprime = lignes
          .map((l) => chiffres(l.cellules[4]))
          .fold<int>(0, (t, v) => t + v);
      final enBase = (await db.select(db.purchases).get()).fold<double>(
        0,
        (t, p) => t + p.total,
      );

      expect(imprime, 185000 + 62500 + 285500);
      expect(imprime, enBase.round());

      // Une cellule précise, au caractère près (espace séparateur de milliers).
      expect(lignes[1].cellules[4], '185 000 FCFA');
    });

    test('l ordre est celui de l écran : le plus récent d abord', () async {
      await jeu();
      final doc = DocumentsAchats.liste((await depot.charger()).achats);

      final dates = doc.lignes
          .cast<DonneesDocument>()
          .map((l) => l.cellules[1])
          .toList();

      expect(dates, ['02/08/2026', '14/07/2026', '10/07/2026']);
    });

    /// ⚠️⚠️ Référence et catégorie absentes : un tiret, jamais un numéro
    /// inventé ni « null ».
    test('⚠️⚠️ référence et catégorie inconnues sont des tirets', () async {
      await jeu();
      final doc = DocumentsAchats.liste((await depot.charger()).achats);

      final sansCategorie = doc.lignes.cast<DonneesDocument>().firstWhere(
        (l) => l.cellules[2] == 'Véto-Santé Bénin',
      );

      expect(sansCategorie.cellules[0], '—');
      expect(sansCategorie.cellules[3], '—');
      for (final l in doc.lignes.cast<DonneesDocument>()) {
        expect(l.cellules[0], '—');
        expect(l.cellules.join(' '), isNot(contains('null')));
        expect(l.cellules.join(' '), isNot(contains('ACH-')));
      }
    });

    /// ⚠️⚠️ Un achat saisi ici et pas encore parti s'imprime comme tel.
    test('⚠️⚠️ la note de pied compte les achats pas encore envoyés', () async {
      await jeu();
      final doc = DocumentsAchats.liste((await depot.charger()).achats);

      expect(doc.noteDePied, contains('1 achat(s) saisi(s) sur ce poste'));
      expect(doc.noteDePied, contains('en attente de synchronisation'));
    });

    test('sans achat en attente, la note ne parle pas de saisie', () async {
      await fournisseur('f1', 'Provenderie du Plateau');
      await achat(
        'a1',
        cleFournisseur: 'f1',
        nomFournisseur: 'Provenderie du Plateau',
        total: 1000,
        date: DateTime(2026, 7, 14),
      );
      final doc = DocumentsAchats.liste((await depot.charger()).achats);

      expect(doc.noteDePied, isNot(contains('saisi(s)')));
    });

    /// ⚠️⚠️ **UN DOCUMENT QUI SORT DE LA FERME NE DIT PAS « 0 » POUR CE QU'IL
    /// IGNORE.** La TVA récupérable se ventile sur le serveur, ligne par ligne.
    test(
      '⚠️⚠️ le bon de réception : TVA, opérateur, référence en tirets',
      () async {
        await jeu();
        final d = await depot.charger();
        final recu = d.achats.firstWhere((l) => l.achat.total == 185000);

        final doc = DocumentsAchats.bonReception(recu);
        final rangees = {
          for (final l in doc.lignes.whereType<DonneesDocument>())
            l.cellules[0]: l.cellules[1],
        };

        expect(doc.titre, 'Bon de Réception');
        expect(rangees['Référence'], '—');
        expect(rangees['Opérateur'], '—');
        expect(rangees['TVA Récupérable (18%)'], '—');
        expect(rangees['Date'], '14/07/2026');
        expect(rangees['Fournisseur'], 'Provenderie du Plateau');
        expect(rangees['Montant Total'], '185 000 FCFA');
        expect(rangees['Statut'], 'Payé entièrement');
        expect(doc.noteDePied, isNull);
      },
    );

    test('le bon suit l ordre des trois blocs du tiroir', () async {
      await jeu();
      final d = await depot.charger();
      final doc = DocumentsAchats.bonReception(d.achats.first);

      final bandes = doc.lignes
          .whereType<BandeDocument>()
          .map((b) => b.libelle)
          .toList();

      expect(bandes, [
        'Informations générales',
        'Fiche Fournisseur',
        'Détails Financiers',
      ]);
    });

    test('⚠️⚠️ le bon d un achat non envoyé le dit', () async {
      await jeu();
      final d = await depot.charger();
      final local = d.achats.firstWhere((l) => !l.envoye);

      final doc = DocumentsAchats.bonReception(local);
      final statut = doc.lignes
          .whereType<DonneesDocument>()
          .firstWhere((l) => l.cellules[0] == 'Statut')
          .cellules[1];

      expect(statut, 'En attente de synchronisation');
      expect(doc.noteDePied, contains('pas encore reçu par la ferme'));
    });

    /// ⚠️⚠️ **DÉFAUT TROUVÉ EN ÉCRIVANT CE TICKET.** La police par défaut du
    /// moteur PDF (Helvetica) n'a pas Unicode : « — » et « ’ » sortaient en
    /// CARRÉ BARRÉ — dans le pied des trois structures, dans l'adresse de la
    /// ferme et dans chaque valeur inconnue. Aucune erreur, seulement un
    /// avertissement de journal. Le test lit les flux du PDF et cherche la
    /// signature du glyphe manquant (deux diagonales dans un rectangle).
    test(
      '⚠️⚠️ aucun tiret ni apostrophe n est dessiné en carré barré',
      () async {
        await jeu();
        final d = await depot.charger();
        final polices = await ExportOfficiel.chargerPolices();

        for (final doc in [
          DocumentsAchats.liste(d.achats),
          DocumentsAchats.bonReception(d.achats.first),
        ]) {
          final octets = await ExportOfficiel.construire(
            doc,
            maintenant: maintenantFixe,
            polices: polices,
          );

          expect(glyphesManquants(octets), 0, reason: doc.titre);
          expect(latin1.decode(octets), contains('/FontFile2'));
        }
      },
    );

    test(
      'le contrôle voit bien le défaut : sans police, des carrés barrés',
      () async {
        await jeu();
        final d = await depot.charger();

        final octets = await ExportOfficiel.construire(
          DocumentsAchats.liste(d.achats),
          maintenant: maintenantFixe,
        );

        // Au moins le « — » de la colonne Référence et le pied de page.
        expect(glyphesManquants(octets), greaterThan(3));
      },
    );

    test(
      '⚠️⚠️ les deux documents se rendent en PDF, trois structures au pied',
      () async {
        await jeu();
        final d = await depot.charger();

        for (final doc in [
          DocumentsAchats.liste(d.achats),
          DocumentsAchats.bonReception(d.achats.first),
        ]) {
          final octets = await ExportOfficiel.construire(
            doc,
            maintenant: maintenantFixe,
          );
          expect(octets.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
        }

        // Le pied est celui de ExportOfficiel : les trois structures.
        const credits = ExportOfficiel.creditsProjet;
        expect(credits, contains('PAEB'));
        expect(credits, contains('Cabinet FAGUEZ SARL'));
        expect(credits, contains('MASSENON Rhodes'));
      },
    );
  });

  group('écran', () {
    late List<(DocumentOfficiel, DateTime)> editions;

    Future<void> afficher(
      WidgetTester tester, {
      bool avecFournisseurs = true,
    }) async {
      editions = [];
      tester.view.physicalSize = const Size(1600, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: AchatsCommandesScreen(
            depot: depot,
            depotFournisseurs: avecFournisseurs ? depotFournisseurs : null,
            imprimer: (doc, quand) async {
              editions.add((doc, quand));
              return null;
            },
            maintenant: () => maintenantFixe,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key("onglet-achats-Liste d'Achats")));
      await tester.pumpAndSettle();
    }

    Future<void> ouvrirDetail(WidgetTester tester, int index) async {
      await tester.tap(find.byKey(Key('voir-achat-$index')));
      await tester.pumpAndSettle();
    }

    testWidgets('⚠️ l œil ouvre « Détail de l Achat » et ses trois blocs', (
      tester,
    ) async {
      await jeu();
      await afficher(tester);

      // Ligne 1 = 14/07/2026 (la liste est triée du plus récent au plus ancien).
      await ouvrirDetail(tester, 1);

      expect(find.text("Détail de l'Achat"), findsOneWidget);
      for (final bloc in [
        'INFORMATIONS GÉNÉRALES',
        'FICHE FOURNISSEUR',
        'DÉTAILS FINANCIERS',
      ]) {
        expect(find.text(bloc), findsOneWidget, reason: bloc);
      }
      for (final libelle in [
        'Référence',
        'Date',
        'Opérateur',
        'Montant Total',
        'TVA Récupérable (18%)',
        'Statut',
      ]) {
        expect(
          find.descendant(
            of: find.byKey(const Key('detail-achat')),
            matching: find.text(libelle),
          ),
          findsOneWidget,
          reason: libelle,
        );
      }
    });

    testWidgets('⚠️⚠️ les valeurs affichées sont celles de la base', (
      tester,
    ) async {
      await jeu();
      await afficher(tester);
      await ouvrirDetail(tester, 1);

      final detail = find.byKey(const Key('detail-achat'));

      expect(
        find.descendant(of: detail, matching: find.text('185 000 FCFA')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: detail, matching: find.text('14/07/2026')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: detail, matching: find.text('Payé entièrement')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: detail,
          matching: find.text('Provenderie du Plateau'),
        ),
        findsOneWidget,
      );
    });

    /// ⚠️⚠️ TROIS TIRETS (référence, opérateur, TVA) ET LEUR LÉGENDE — jamais
    /// un zéro.
    testWidgets('⚠️⚠️ référence, opérateur et TVA sont des tirets légendés', (
      tester,
    ) async {
      await jeu();
      await afficher(tester);
      await ouvrirDetail(tester, 1);

      final detail = find.byKey(const Key('detail-achat'));

      expect(
        find.descendant(of: detail, matching: find.text('—')),
        findsNWidgets(3),
      );
      expect(find.byKey(const Key('legende-detail-achat')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('legende-detail-achat')),
          matching: find.textContaining('ligne par ligne'),
        ),
        findsOneWidget,
      );
      expect(find.text('0 FCFA'), findsNothing);
    });

    testWidgets('⚠️ un achat non envoyé annonce son attente dans le détail', (
      tester,
    ) async {
      await jeu();
      await afficher(tester);
      await ouvrirDetail(tester, 0);

      expect(
        find.descendant(
          of: find.byKey(const Key('detail-achat')),
          matching: find.text('En attente de synchronisation'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('detail-achat')),
          matching: find.text('285 500 FCFA'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      '⚠️ le nom du fournisseur ouvre son profil, et Retour revient',
      (tester) async {
        await jeu();
        await afficher(tester);
        await ouvrirDetail(tester, 1);

        await tester.tap(find.byKey(const Key('detail-fournisseur')));
        await tester.pumpAndSettle();

        expect(find.text('Profil Fournisseur'), findsOneWidget);
        expect(find.text("Détail de l'Achat"), findsNothing);

        await tester.tap(find.byKey(const Key('profil-retour')));
        await tester.pumpAndSettle();

        expect(find.text('Profil Fournisseur'), findsNothing);
        expect(find.byKey(const Key('voir-achat-1')), findsOneWidget);
      },
    );

    testWidgets('sans dépôt fournisseurs, le nom s affiche sans lien', (
      tester,
    ) async {
      await jeu();
      await afficher(tester, avecFournisseurs: false);
      await ouvrirDetail(tester, 1);

      expect(
        find.descendant(
          of: find.byKey(const Key('detail-fournisseur')),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
    });

    testWidgets('⚠️⚠️ « Exporter PDF » édite la liste, effets injectés', (
      tester,
    ) async {
      await jeu();
      await afficher(tester);

      await tester.tap(find.byKey(const Key('exporter-pdf-achats')));
      await tester.pumpAndSettle();

      expect(editions.length, 1);
      final (doc, quand) = editions.single;
      expect(doc.titre, 'Liste des Achats');
      expect(doc.lignes.length, 3);
      expect(quand, maintenantFixe);
      expect(find.text('Document envoyé à l’impression.'), findsOneWidget);
    });

    testWidgets('⚠️ sans achat, rien n est édité et l écran le dit', (
      tester,
    ) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('exporter-pdf-achats')));
      await tester.pumpAndSettle();

      expect(editions, isEmpty);
      expect(find.text('Aucun achat à exporter.'), findsOneWidget);
    });

    testWidgets('⚠️⚠️ « Imprimer » du détail édite le bon de cet achat', (
      tester,
    ) async {
      await jeu();
      await afficher(tester);
      await ouvrirDetail(tester, 2);

      await tester.tap(find.byKey(const Key('detail-imprimer')));
      await tester.pumpAndSettle();

      expect(editions.length, 1);
      final doc = editions.single.$1;
      expect(doc.titre, 'Bon de Réception');
      // Ligne 2 = 10/07/2026, 62 500 FCFA, à crédit.
      final rangees = {
        for (final l in doc.lignes.whereType<DonneesDocument>())
          l.cellules[0]: l.cellules[1],
      };
      expect(rangees['Montant Total'], '62 500 FCFA');
      expect(rangees['Statut'], 'Dette fournisseur');
      expect(find.text("Détail de l'Achat"), findsNothing);
    });

    /// ⚠️⚠️ **LECTURE SEULE, PROUVÉE PAR COMPARAISON.**
    testWidgets('⚠️⚠️ ouvrir, exporter, imprimer n écrit rien', (tester) async {
      await jeu();
      final avant = await empreinte();
      final achatsAvant =
          (await db.select(db.purchases).get())
              .map((p) => '${p.id}|${p.total}|${p.amountPaid}|${p.syncStatus}')
              .toList()
            ..sort();

      await afficher(tester);
      await tester.tap(find.byKey(const Key('exporter-pdf-achats')));
      await tester.pumpAndSettle();
      await ouvrirDetail(tester, 0);
      await tester.tap(find.byKey(const Key('detail-imprimer')));
      await tester.pumpAndSettle();

      final achatsApres =
          (await db.select(db.purchases).get())
              .map((p) => '${p.id}|${p.total}|${p.amountPaid}|${p.syncStatus}')
              .toList()
            ..sort();

      expect(await empreinte(), avant);
      expect(achatsApres, achatsAvant);
    });

    /// ⚠️⚠️ La phrase datée de l'onglet disait que l'export PDF se faisait sur la
    /// surface web : fausse depuis ce ticket.
    testWidgets('⚠️⚠️ la mention de l onglet ne prétend plus que le PDF est web', (
      tester,
    ) async {
      await jeu();
      await afficher(tester);

      expect(find.textContaining('export PDF'), findsNothing);
      // F0.74 : la mention ne dit plus que retours et remboursements se font sur le
      // web (faux depuis ce ticket) ; elle dit que le poste enregistre la DEMANDE.
      expect(find.textContaining('se font sur la surface web'), findsNothing);
      expect(find.textContaining('contre-passation réservée'), findsNothing);
      expect(
        find.textContaining('Retour fournisseur et remboursement'),
        findsOneWidget,
      );
    });
  });

  group('câblage', () {
    /// ⚠️⚠️ Un écran dont l'éditeur n'est pas passé par `main` imprime… rien, sans
    /// erreur. Le test lit donc la source, comme les autres garde-fous.
    test('⚠️⚠️ main.dart passe le dépôt fournisseurs et l éditeur réel', () {
      final src = File('lib/main.dart').readAsStringSync();
      final debut = src.indexOf('EcranPoste.achatsEtCommandes =>');
      final bloc = src.substring(debut, src.indexOf('),', debut));

      expect(bloc, contains('depotFournisseurs: widget.fournisseurs'));
      expect(bloc, contains('imprimer: EditeursRapports.imprimer'));
    });
  });
}
