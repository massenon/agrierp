import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/elevage/bandes_repository.dart';
import 'package:agrierp/features/elevage/gestion_bandes_screen.dart';
import 'package:agrierp/features/stocks/pmp_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket UNI — UNICITÉ DES CODES DE BANDE AU POSTE : refus avant l'écriture (message sous le champ, comme le web),
/// proposition du prochain code libre, bandes tirées du serveur comptées, renommage d'un doublon, refus du serveur
/// « code déjà utilisé » (la bande est gardée, se renomme, repart), bandeau « N doublons de code détectés ».
///
/// Maître : `UniqueNormalise::bande()`, `LivestockLot::messageCodePris()` et `SaisieBandeAction::modifier()`. Valeurs
/// attendues écrites à la main (les textes sont ceux du web, mot pour mot).
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

/// Serveur feint : garde chaque envoi ; les bandes de [refusees] sont rejetées avec leur motif, le reste accepté.
class _Serveur extends Interceptor {
  final List<Map<String, dynamic>> envois = [];
  final Map<String, String> refusees = {};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!options.path.contains('push')) {
      handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: {'server_time': '2026-10-21T12:00:00Z'}));
      return;
    }
    final corps = options.data as Map<String, dynamic>;
    envois.add(corps);
    final reponse = <String, dynamic>{};
    for (final MapEntry(:key, :value) in corps.entries) {
      if (value is! List) continue;
      final ids = [for (final e in value) if (e is Map && e['id'] is String) e['id'] as String];
      reponse[key] = {
        'accepted': [for (final id in ids) if (key != 'livestock_lots' || !refusees.containsKey(id)) id],
        'rejected': [
          if (key == 'livestock_lots')
            for (final id in ids)
              if (refusees.containsKey(id)) {'id': id, 'reason': refusees[id]},
        ],
      };
    }
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: reponse));
  }
}

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late SyncEngine moteur;
  late BandesRepository depot;

  const lapins = 'aaaaaaaa-0000-4000-8000-0000000000a1';
  final maintenant = DateTime(2026, 10, 21, 10, 30);
  String uuid(String graine) => graine.padRight(36, '0');

  const refusServeur =
      'Le code « AVI-2026-01 » est déjà utilisé par une autre bande (en cours ou archivée) : choisissez un autre code. '
      'Votre bande est conservée sur ce poste : renommez-la (Élevage > Bandes & Sujets, bouton « Modifier ») puis synchronisez de nouveau.';

  Future<void> bande(
    String id,
    String code, {
    bool active = true,
    SyncStatus sync = SyncStatus.synced,
    int courant = 10,
  }) => db.into(db.livestockLots).insert(
    LivestockLotsCompanion.insert(
      id: id,
      code: code,
      speciesId: lapins,
      speciesCode: const Value('cuniculture'),
      stage: const Value('reproduction'),
      initialQuantity: Value(courant),
      currentQuantity: Value(courant),
      createdDate: Value(DateTime(2026, 9, 1)),
      status: const Value('actif'),
      isActive: Value(active),
      syncStatus: Value(sync),
    ),
  );

  Future<LivestockLot> lue(String id) => (db.select(db.livestockLots)..where((t) => t.id.equals(id))).getSingle();

  FormulaireBande formulaire(String code) =>
      FormulaireBande(speciesId: lapins, code: code, stage: 'reproduction', createdDate: DateTime(2026, 10, 20), quantite: '12');

  Future<Map<String, String>> erreursDe(String code) async {
    try {
      await depot.creer(formulaire(code));
    } on BandeRefusee catch (e) {
      return e.erreurs;
    }
    return {};
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    depot = BandesRepository(database: db, deviceId: 'poste-test', horloge: () => maintenant);
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => maintenant,
    );
    await db.into(db.livestockSpecies).insert(LivestockSpeciesCompanion.insert(id: lapins, code: 'cuniculture', label: 'Cuniculture'));
    await db.into(db.modulesConfig).insert(ModulesConfigCompanion.insert(id: uuid('mod'), speciesCode: 'cuniculture'));
  });

  tearDown(() async {
    ToastAgri.toutRetirer();
    await db.close();
  });

  group('la clé de comparaison', () {
    test('ignore la casse, les accents, les espaces autour et doublés (celle de CleUnicite côté serveur)', () {
      expect(cleUnicite('  AVI-2026-01 '), 'avi-2026-01');
      expect(cleUnicite("LOT\t LAP   7"), 'lot lap 7');
      expect(cleUnicite('Œufs'), 'oeufs');
    });
  });

  group('créer : le code doit être libre', () {
    test('⚠️ refusé s\'il est déjà pris : même casse, espaces autour, bande archivée, bande tirée du serveur', () async {
      await bande(uuid('b1'), 'AVI-2026-01');
      await bande(uuid('b2'), 'ARCH-1', active: false);
      await bande(uuid('b3'), 'LOT-LAP-7', sync: SyncStatus.synced); // tirée du serveur : déjà synchronisée

      const message = 'Le code « %s » est déjà utilisé par une autre bande (en cours ou archivée) : choisissez un autre code.';
      String m(String code) => message.replaceFirst('%s', code);
      expect(await erreursDe('AVI-2026-01'), {'code': m('AVI-2026-01')});
      expect(await erreursDe('avi-2026-01'), {'code': m('avi-2026-01')});
      expect(await erreursDe('  AVI-2026-01  '), {'code': m('AVI-2026-01')});
      expect(await erreursDe('arch-1'), {'code': m('arch-1')});
      expect(await erreursDe('Lot-Lap-7'), {'code': m('Lot-Lap-7')});
      expect(await db.select(db.livestockLots).get(), hasLength(3), reason: 'aucune bande créée');
    });

    test('un code libre est accepté et rangé sans espaces autour', () async {
      await bande(uuid('b1'), 'AVI-2026-01');

      final creee = await depot.creer(formulaire('  AVI-2026-02 '));

      expect(creee.code, 'AVI-2026-02');
      expect(creee.syncStatus, SyncStatus.pending);
    });

    test('le message est celui de LivestockLot::messageCodePris(), mot pour mot', () {
      expect(
        BandesRepository.messageCodeDejaUtilise('AVI-2026-01'),
        'Le code « AVI-2026-01 » est déjà utilisé par une autre bande (en cours ou archivée) : choisissez un autre code.',
      );
    });
  });

  group('proposer le prochain code libre', () {
    test('le code suggéré suit le plus grand numéro, y compris celui d\'une bande tirée du serveur ou archivée', () async {
      await bande(uuid('b1'), 'LOT-LAP-3');
      await bande(uuid('b2'), ' lot-lap-9 ', active: false);

      expect(await depot.codeSuggere(lapins), 'LOT-LAP-10');
    });
  });

  group('compter et reconnaître les doublons déjà présents', () {
    test('un groupe par code partagé, casse et espaces ignorés ; archivées et tirées du serveur comprises', () async {
      await bande(uuid('b1'), 'AVI-2026-01');
      await bande(uuid('b2'), 'avi-2026-01 ', active: false);
      await bande(uuid('b3'), 'AVI-2026-01 ');
      await bande(uuid('b4'), 'LOT-LAP-1');
      await bande(uuid('b5'), 'LOT-LAP-1', sync: SyncStatus.pending);
      await bande(uuid('b6'), 'LOT-LAP-2');

      expect(await depot.nombreDeCodesEnDouble(), 2);
      expect(await depot.codeRenommable(uuid('b1')), isTrue);
      expect(await depot.codeRenommable(uuid('b6')), isFalse);
      expect([for (final l in await depot.bandes()) l.codeRenommable], [true, true, true, true, false]);
    });

    test('aucun doublon : zéro', () async {
      await bande(uuid('b1'), 'AVI-2026-01');
      await bande(uuid('b2'), 'AVI-2026-02');

      expect(await depot.nombreDeCodesEnDouble(), 0);
    });
  });

  group('renommer une bande au code partagé (jamais automatiquement)', () {
    test('⚠️ le code change, la bande repart EN FILE avec son identifiant ; le reste ne bouge pas', () async {
      await bande(uuid('b1'), 'AVI-2026-01');
      await bande(uuid('b2'), 'avi-2026-01 ');

      final renommee = await depot.modifier(uuid('b2'), stage: 'reproduction', quantite: '10', status: 'actif', code: 'AVI-2026-02');

      expect([renommee.id, renommee.code, renommee.syncStatus, renommee.currentQuantity], [uuid('b2'), 'AVI-2026-02', SyncStatus.pending, 10]);
      expect((await lue(uuid('b1'))).code, 'AVI-2026-01');
      expect(await depot.nombreDeCodesEnDouble(), 0);
    });

    test('vers un code déjà pris : refusé sous le champ, rien n\'est écrit', () async {
      await bande(uuid('b1'), 'AVI-2026-01');
      await bande(uuid('b2'), 'avi-2026-01 ');
      await bande(uuid('b3'), 'AVI-2026-05');

      await expectLater(
        depot.modifier(uuid('b2'), stage: 'reproduction', quantite: '10', status: 'actif', code: 'avi-2026-05'),
        throwsA(isA<BandeRefusee>().having((e) => e.erreurs, 'erreurs', {
          'code': 'Le code « avi-2026-05 » est déjà utilisé par une autre bande (en cours ou archivée) : choisissez un autre code.',
        })),
      );
      expect((await lue(uuid('b2'))).code, 'avi-2026-01 ');
    });

    test('⚠️ un code qui n\'est pas partagé reste immuable', () async {
      await bande(uuid('b1'), 'AVI-2026-01');

      await expectLater(
        depot.modifier(uuid('b1'), stage: 'reproduction', quantite: '10', status: 'actif', code: 'AUTRE-1'),
        throwsA(isA<BandeRefusee>().having((e) => e.erreurs['code'], 'code', BandesRepository.messageCodeImmuable)),
      );
      expect((await lue(uuid('b1'))).code, 'AVI-2026-01');
    });
  });

  group('deux postes créent le même code hors ligne : le second est rejeté proprement', () {
    test('⚠️⚠️ le refus est montré mot pour mot, la bande saisie est GARDÉE, se renomme, repart et est acceptée', () async {
      final creee = await depot.creer(formulaire('AVI-2026-01'));
      serveur.refusees[creee.id] = refusServeur;

      await moteur.synchroniser();

      // La donnée saisie n'est pas perdue : la bande est là, en conflit, avec le motif du serveur et la marche à suivre.
      final refusee = await lue(creee.id);
      expect([refusee.code, refusee.initialQuantity, refusee.syncStatus], ['AVI-2026-01', 12, SyncStatus.conflict]);
      final ligne = (await depot.bandes()).single;
      expect(ligne.motifRefus, refusServeur);
      expect(ligne.motifRefus, contains('renommez-la'));
      // Même sans bande jumelle encore tirée sur ce poste, le code du refus est à renommer.
      expect(ligne.codeRenommable, isTrue);

      final renommee = await depot.modifier(creee.id, stage: 'reproduction', quantite: '12', status: 'actif', code: 'AVI-2026-02');
      expect([renommee.code, renommee.syncStatus], ['AVI-2026-02', SyncStatus.pending]);
      expect(await db.select(db.syncConflicts).get(), isEmpty, reason: 'le refus périmé est levé');

      serveur.refusees.clear();
      serveur.envois.clear();
      await moteur.synchroniser();

      final envoyee = (serveur.envois.single['livestock_lots'] as List).single as Map;
      expect([envoyee['id'], envoyee['code'], envoyee['initial_quantity']], [creee.id, 'AVI-2026-02', 12]);
      expect((await lue(creee.id)).syncStatus, SyncStatus.synced);
    });
  });

  group('l\'écran', () {
    Future<void> attendre(WidgetTester t) async {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
      await t.pumpAndSettle();
    }

    Future<void> monter(WidgetTester t) async {
      t.view.physicalSize = const Size(1400, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: GestionBandesScreen(depot: depot, horloge: () => maintenant)));
      await attendre(t);
    }

    String texteDe(WidgetTester t, String cle) => (t.widget(find.byKey(Key(cle))) as Text).data!;

    testWidgets('⚠️ le formulaire refuse un code déjà pris SOUS LE CHAMP, rien n\'est écrit', (t) async {
      await t.runAsync(() => bande(uuid('b1'), 'AVI-2026-01'));
      await monter(t);
      await t.tap(find.byKey(const Key('bande-nouvelle')));
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: find.byKey(const Key('bande-espece')), matching: find.byType(DropdownButton<String>)));
      await t.pumpAndSettle();
      await t.tap(find.text('Cuniculture').last);
      await attendre(t);

      await t.enterText(find.descendant(of: find.byKey(const Key('bande-code')), matching: find.byType(TextField)), ' avi-2026-01');
      await t.enterText(find.descendant(of: find.byKey(const Key('bande-quantite')), matching: find.byType(TextField)), '12');
      await t.tap(find.byKey(const Key('bande-creer')));
      await attendre(t);

      expect(
        texteDe(t, 'bande-erreur-code'),
        'Le code « avi-2026-01 » est déjà utilisé par une autre bande (en cours ou archivée) : choisissez un autre code.',
      );
      expect(await t.runAsync(() => db.select(db.livestockLots).get()), hasLength(1));
    });

    testWidgets('⚠️ le bandeau « N doublons de code détectés — à renommer » ne bloque rien et « Modifier » ouvre le code', (t) async {
      await t.runAsync(() async {
        await bande(uuid('b1'), 'AVI-2026-01');
        await bande(uuid('b2'), 'avi-2026-01 ');
        await bande(uuid('b3'), 'LOT-LAP-2');
      });
      await monter(t);

      expect(find.byKey(const Key('bandes-doublons-codes')), findsOneWidget);
      expect(find.textContaining('1 doublon de code détecté — à renommer.'), findsOneWidget);

      // Une bande au code partagé : le champ code est ouvert ; une bande au code unique : il reste grisé.
      await t.tap(find.byKey(Key('bande-modifier-${uuid('b2')}')));
      await t.pumpAndSettle();
      expect(find.text('Ce code est partagé avec une autre bande : corrigez-le (il redeviendra non modifiable ensuite).'), findsOneWidget);
      await t.enterText(find.descendant(of: find.byKey(const Key('bande-edit-code')), matching: find.byType(TextField)), 'AVI-2026-02');
      await t.tap(find.byKey(const Key('bande-enregistrer')));
      await attendre(t);

      expect((await t.runAsync(() => lue(uuid('b2'))))!.code, 'AVI-2026-02');
      expect(find.byKey(const Key('bandes-doublons-codes')), findsNothing, reason: 'plus aucun doublon : le bandeau disparaît');
      await t.pump(ToastAgri.duree);
    });

    testWidgets('sans doublon : pas de bandeau', (t) async {
      await t.runAsync(() => bande(uuid('b1'), 'AVI-2026-01'));
      await monter(t);

      expect(find.byKey(const Key('bandes-doublons-codes')), findsNothing);
    });
  });
}
