import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/modale_synchronisation.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/theme/agri_theme.dart';
import 'package:agrierp/core/theme/agri_tokens.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'coque_poste.dart';

/// Ticket H2 — BOUTON « SYNCHRONISER » DE LA BARRE SUPÉRIEURE ET MODALE DU POSTE
/// (PRD `docs/prd/synchronisation-barre-superieure.md`, §5 et §10).
///
/// Jeu du PRD, calculé à la main : 2 fiches journalières `pending`, 1 client `pending`, 1 article `pending`,
/// 1 vente `conflict`.
/// - 🔴 avant : `pendingCount()` = 3 (fiches + vente) — le client et l'article étaient oubliés ;
/// - après : 5 non synchronisés, badge « 5 » ROUGE (un refus) ; modale : 4 à envoyer, 1 refusé, « — » (jamais
///   réussie).
class _Connectivite implements Connectivity {
  _Connectivite(this.enLigne);

  final bool enLigne;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [enLigne ? ConnectivityResult.wifi : ConnectivityResult.none];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async {
    ToastAgri.toutRetirer();
    await db.close();
  });

  Future<void> jeuDuPrd() async {
    final maintenant = DateTime(2026, 10, 19, 8);
    for (final (id, jour) in [('aaaaaaaa-0000-4000-8000-000000000001', 18), ('aaaaaaaa-0000-4000-8000-000000000002', 19)]) {
      await db.into(db.livestockDailyEntries).insert(
        LivestockDailyEntriesCompanion.insert(
          id: id,
          deviceId: 'poste-test',
          updatedAt: maintenant,
          lotId: 'bbbbbbbb-0000-4000-8000-000000000001',
          entryDate: DateTime(2026, 10, jour),
        ),
      );
    }
    await db.into(db.customers).insert(
      CustomersCompanion.insert(
        id: 'cccccccc-0000-4000-8000-000000000001',
        name: 'Client hors ligne',
        syncStatus: const Value(SyncStatus.pending),
      ),
    );
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        id: 'dddddddd-0000-4000-8000-000000000001',
        sku: 'HL-001',
        name: 'Article hors ligne',
        unit: 'u',
        pricingMode: 'fixe',
        syncStatus: const Value(SyncStatus.pending),
      ),
    );
    await db.into(db.sales).insert(
      SalesCompanion.insert(
        id: 'eeeeeeee-0000-4000-8000-000000000001',
        deviceId: 'poste-test',
        updatedAt: maintenant,
        paymentMode: 'especes',
        total: 1500,
        soldAt: maintenant,
        syncStatus: const Value(SyncStatus.conflict),
      ),
    );
  }

  test('🔴 le compteur couvre les tables envoyées : client et article comptés', () async {
    await jeuDuPrd();

    final c = await db.compteursSynchronisation();
    expect((c.aEnvoyer, c.refuses), (4, 1));
    expect(await db.pendingCount(), 5);
  });

  Future<void> monterCoque(WidgetTester t, Size taille) async {
    t.view.physicalSize = taille;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: AgriTheme.light, home: coqueDeTest(db)));
    await t.pumpAndSettle();
  }

  testWidgets('la barre supérieure porte le bouton : badge « 5 » rouge, sans pastille ni bouton de pied de barre', (
    t,
  ) async {
    await t.runAsync(jeuDuPrd);
    await monterCoque(t, const Size(1600, 900));

    final badge = find.byKey(const Key('bouton-synchroniser-badge'));
    expect(find.descendant(of: badge, matching: find.text('5')), findsOneWidget);
    expect((t.widget<Container>(badge).decoration! as BoxDecoration).color, AgriColors.errorRed);
    expect(find.byKey(const Key('pastille-sync')), findsNothing);
    // L'ancien bouton jaune du pied de la barre latérale a disparu : une seule entrée pour la même action.
    expect(
      find.descendant(of: find.byKey(const Key('barre-laterale')), matching: find.text('Synchroniser')),
      findsNothing,
    );
  });

  testWidgets('la modale montre 4 à envoyer, 1 refusé et « — » pour la dernière réussite', (t) async {
    await t.runAsync(jeuDuPrd);
    final moteur = SyncEngine(
      database: db,
      client: Dio(),
      deviceId: 'poste-test',
      connectivity: _Connectivite(false),
    );
    t.view.physicalSize = const Size(1400, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: ModaleSynchronisation(engine: moteur, database: db))));
    for (var i = 0; i < 5; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }

    String valeur(String cle) => (t
            .widgetList<Text>(find.descendant(of: find.byKey(Key(cle)), matching: find.byType(Text)))
            .map((w) => w.data)
            .toList())
        .join(' | ');

    expect(valeur('sync-en-attente'), contains('4'));
    expect(valeur('sync-refuses'), contains('1'));
    expect(valeur('sync-derniere-reussie'), contains('—'));
    expect(find.text('Hors ligne'), findsOneWidget);
    expect(find.text('Synchronisation'), findsOneWidget);
    expect(find.text('Poste poste-test'), findsOneWidget);

    // Hors ligne : avertissement jaune, jamais d'erreur rouge.
    await t.tap(find.byKey(const Key('sync-maintenant')));
    for (var i = 0; i < 5; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    expect(find.byKey(const Key('toast-avertissement')), findsOneWidget);
    expect(find.byKey(const Key('toast-erreur')), findsNothing);
    expect(find.textContaining('Serveur injoignable'), findsWidgets);
    ToastAgri.toutRetirer();
  });

  testWidgets('🔴 la barre latérale défile : la dernière entrée est atteignable en 1280 × 600', (t) async {
    await monterCoque(t, const Size(1280, 600));

    expect(
      find.descendant(of: find.byKey(const Key('barre-laterale-navigation')), matching: find.byType(Scrollable)),
      findsOneWidget,
    );
    // « Synchronisation » : dernier groupe (POSTE), ouvert à tous les rôles.
    final derniere = find.byKey(const Key('nav-synchronisation'));
    await t.scrollUntilVisible(
      derniere,
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('barre-laterale-navigation')),
        matching: find.byType(Scrollable),
      ),
    );
    await t.tap(derniere);
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.byKey(const Key('fil-ariane'))).data, contains('Synchronisation'));
  });
}
