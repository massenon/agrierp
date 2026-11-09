import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/achats/achats_commandes_screen.dart';
import 'package:agrierp/features/achats/achats_repository.dart';
import 'package:agrierp/features/achats/depenses_repository.dart';
import 'package:agrierp/features/achats/saisie_depenses_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'depenses_aide.dart';

/// Ticket AC-3 — LES JUSTIFICATIFS SONT SYNCHRONISÉS (`POST /api/sync/receipts`).
///
/// Le contrat de `/sync/push` ne transporte aucun fichier : le moteur envoie le fichier d'un achat ou d'une dépense APRÈS
/// que l'enregistrement a été acquitté, une fois (`receipt_sent`). Un refus définitif (format, taille) ou un fichier
/// disparu est signalé et n'est pas réessayé ; un échec passager l'est à la synchronisation suivante.
class _Serveur extends Interceptor {
  /// Réponse à `/api/sync/receipts` : code HTTP, puis corps.
  int codeRecus = 200;
  Map<String, dynamic> corpsRecus = {'stored': true};
  final List<FormData> recus = [];
  final List<Map<String, dynamic>> envois = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('/sync/receipts')) {
      recus.add(options.data as FormData);
      if (codeRecus >= 400) {
        handler.reject(
          DioException(
            requestOptions: options,
            response: Response<Map<String, dynamic>>(requestOptions: options, statusCode: codeRecus, data: corpsRecus),
            type: DioExceptionType.badResponse,
          ),
          true,
        );
        return;
      }
      handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: corpsRecus));
      return;
    }
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      envois.add(corps);
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            for (final MapEntry(:key, :value) in corps.entries)
              if (value is List)
                key: {
                  'accepted': [for (final e in value) if (e is Map && e['id'] is String) e['id']],
                  'rejected': <dynamic>[],
                },
          },
        ),
      );
      return;
    }
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: {'server_time': '2026-10-28T12:00:00Z'}));
  }
}

class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late SyncEngine moteur;
  late AchatsRepository achats;
  late Directory dossier;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => DateTime(2026, 10, 28, 14),
    );
    achats = AchatsRepository(database: db, identifiantPoste: 'poste-test');
    dossier = Directory.systemTemp.createTempSync('agrierp_just_');
    await db.into(db.suppliers).insert(SuppliersCompanion.insert(id: uuid('f1'), name: 'Provenderie du Plateau', category: const Value('Aliments')));
    await db.into(db.products).insert(ProductsCompanion.insert(id: uuid('p1'), sku: 'ALI-25', name: 'Aliment ponte 25kg', unit: 'sac', pricingMode: 'fourchette'));
    await db.into(db.treasuryAccounts).insert(TreasuryAccountsCompanion.insert(id: uuid('t1'), label: 'Caisse principale', balance: const Value(100000)));
  });
  tearDown(() async {
    await db.close();
    dossier.deleteSync(recursive: true);
  });

  File fichier(String nom, {String contenu = 'reçu'}) => File('${dossier.path}/$nom')..writeAsStringSync(contenu);

  Future<String> achatAvecRecu(String chemin) async => achats.enregistrer(
    fournisseurId: uuid('f1'),
    lignes: [LigneSaisieAchat(produit: (await db.select(db.products).get()).single, quantite: 2, prixUnitaire: 5900)],
    modePaiement: 'especes',
    compteId: uuid('t1'),
    montantPaye: 11800,
    receiptLocalPath: chemin,
  );

  Future<Purchase> achat() => db.select(db.purchases).getSingle();

  group('moteur', () {
    test('⚠️⚠️ le fichier part APRÈS l\'acquittement de l\'achat, avec la table, l\'identifiant et le fichier, une seule fois', () async {
      final id = await achatAvecRecu(fichier('recu.pdf', contenu: 'PDF-CONTENU').path);
      expect((await achat()).receiptSent, isFalse);
      expect((await achat()).receiptLocalPath, endsWith('recu.pdf'));

      await moteur.synchroniser();

      expect(serveur.recus, hasLength(1));
      final envoi = serveur.recus.single;
      expect({for (final f in envoi.fields) f.key: f.value}, {'table': 'purchases', 'id': id});
      expect(envoi.files.single.key, 'file');
      expect(envoi.files.single.value.filename, 'recu.pdf');
      expect((await achat()).syncStatus, SyncStatus.synced);
      expect((await achat()).receiptSent, isTrue);

      await moteur.synchroniser();
      expect(serveur.recus, hasLength(1), reason: 'déjà reçu : jamais renvoyé');
    });

    test('un achat sans justificatif n\'envoie aucun fichier', () async {
      await achats.enregistrer(
        fournisseurId: uuid('f1'),
        lignes: [LigneSaisieAchat(produit: (await db.select(db.products).get()).single, quantite: 1, prixUnitaire: 5900)],
        modePaiement: 'especes',
        compteId: uuid('t1'),
        montantPaye: 5900,
      );

      await moteur.synchroniser();

      expect(serveur.recus, isEmpty);
    });

    test('⚠️ 422 (format ou taille) : signalé avec le motif du serveur et plus jamais réessayé', () async {
      await achatAvecRecu(fichier('lourd.pdf').path);
      serveur.codeRecus = 422;
      serveur.corpsRecus = {'message': 'Le champ fichier ne doit pas dépasser 5120 Ko.'};

      final r = await moteur.synchroniser();

      expect(r.avertissements.single, allOf(contains('refusé par le serveur'), contains('5120 Ko')));
      expect((await achat()).receiptSent, isTrue);
      await moteur.synchroniser();
      expect(serveur.recus, hasLength(1));
    });

    test('404 ou panne passagère : on réessaiera à la synchronisation suivante, sans bruit', () async {
      await achatAvecRecu(fichier('recu.pdf').path);
      serveur.codeRecus = 404;
      serveur.corpsRecus = {'message': 'Enregistrement inconnu du serveur'};

      final r = await moteur.synchroniser();

      expect(r.avertissements, isEmpty);
      expect((await achat()).receiptSent, isFalse);

      serveur.codeRecus = 200;
      await moteur.synchroniser();
      expect((await achat()).receiptSent, isTrue);
      expect(serveur.recus, hasLength(2));
    });

    test('un fichier disparu du disque est signalé et n\'est plus attendu', () async {
      final f = fichier('perdu.pdf');
      await achatAvecRecu(f.path);
      f.deleteSync();

      final r = await moteur.synchroniser();

      expect(r.avertissements.single, contains('introuvable sur ce poste'));
      expect((await achat()).receiptSent, isTrue);
      expect(serveur.recus, isEmpty);
    });

    test('un enregistrement NON acquitté n\'envoie pas son fichier (le serveur ne le connaît pas)', () async {
      await achatAvecRecu(fichier('recu.pdf').path);
      await (db.update(db.purchases)).write(const PurchasesCompanion(syncStatus: Value(SyncStatus.conflict)));

      await moteur.synchroniser();

      expect(serveur.recus, isEmpty);
    });

    test('la dépense envoie aussi son fichier, et en changer le renvoie', () async {
      final depenses = DepensesRepository(database: db, deviceId: 'poste-test');
      await semerPlanDeCharge(db);
      const ligne = LigneSaisie(libelle: 'Réparation', compteChargeId: compte601, montant: '10000');
      Future<Expense> saisir({String? id, String? recu}) => depenses.enregistrer(
        date: DateTime(2026, 10, 28),
        modePaiement: 'especes',
        compteTresorerieId: uuid('t1'),
        centreCoutId: centreGeneral,
        lignes: const [ligne],
        idEnModification: id,
        receiptLocalPath: recu,
      );

      final d = await saisir(recu: fichier('facture.png').path);
      await moteur.synchroniser();

      expect({for (final f in serveur.recus.single.fields) f.key: f.value}, {'table': 'expenses', 'id': d.id});
      expect((await db.select(db.expenses).getSingle()).receiptSent, isTrue);

      await saisir(id: d.id, recu: d.receiptLocalPath);
      expect((await db.select(db.expenses).getSingle()).receiptSent, isTrue, reason: 'même fichier : pas renvoyé');

      await saisir(id: d.id, recu: fichier('autre.png').path);
      expect((await db.select(db.expenses).getSingle()).receiptSent, isFalse, reason: 'nouveau fichier : à envoyer');
    });
  });

  group('écran', () {
    testWidgets('⚠️ le cadre « Associer une photo du reçu » choisit un fichier ; l\'achat enregistré le porte', (tester) async {
      tester.view.physicalSize = const Size(1600, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(ToastAgri.toutRetirer);
      final f = fichier('recu-marche.jpg');
      var appels = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AchatsCommandesScreen(
            depot: achats,
            maintenant: () => DateTime(2026, 10, 28, 10),
            choisirJustificatif: () async {
              appels++;
              return f.path;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pièce Justificative'.toUpperCase()), findsOneWidget);
      expect(find.byKey(const Key('achat-recu-invite')), findsOneWidget);
      expect(find.textContaining('se joint depuis la surface web'), findsNothing, reason: 'l\'ancienne mention a disparu');

      await tester.tap(find.byKey(const Key('achat-recu-choisir')));
      await tester.pumpAndSettle();
      expect(appels, 1);
      expect(tester.widget<Text>(find.byKey(const Key('achat-recu-nom'))).data, 'recu-marche.jpg');

      await tester.tap(find.byKey(const Key('achat-recu-retirer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('achat-recu-invite')), findsOneWidget);
    });

    testWidgets('⚠️ la dépense qui porte un fichier affiche le trombone « Pièce justificative » et l\'ouvre', (tester) async {
      tester.view.physicalSize = const Size(1600, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(ToastAgri.toutRetirer);
      final depenses = DepensesRepository(database: db, deviceId: 'poste-test');
      await semerPlanDeCharge(db);
      final f = fichier('facture.png');
      final avec = await depenses.enregistrer(
        date: DateTime.now(),
        modePaiement: 'especes',
        compteTresorerieId: uuid('t1'),
        centreCoutId: centreGeneral,
        lignes: const [LigneSaisie(libelle: 'Réparation', compteChargeId: compte601, montant: '10000')],
        receiptLocalPath: f.path,
      );
      final sans = await depenses.enregistrer(
        date: DateTime.now(),
        modePaiement: 'especes',
        compteTresorerieId: uuid('t1'),
        centreCoutId: centreGeneral,
        lignes: const [LigneSaisie(libelle: 'Transport', compteChargeId: compte601, montant: '2000')],
      );
      final ouverts = <String>[];
      await tester.pumpWidget(
        MaterialApp(home: SaisieDepensesScreen(depot: depenses, ouvrirFichier: (u) async => ouverts.add(u))),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(Key('depense-justificatif-${sans.id}')), findsNothing);
      await tester.tap(find.byKey(Key('depense-justificatif-${avec.id}')));
      await tester.pump();

      expect(ouverts, [f.path]);
    });
  });
}
