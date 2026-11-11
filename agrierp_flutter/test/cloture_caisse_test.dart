import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/ventes/cloture_caisse_repository.dart';
import 'package:agrierp/features/ventes/cloture_caisse_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sprint C — Clôture de caisse (côté poste).
///
/// Vérifie le repository (calculs de ventes par mode) et l'écran (affichage
/// des KPI, formule d'écart, protection double-clôture).
void main() {
  late AppDatabase db;
  late ClotureCaisseRepository depot;
  const poste = 'poste-test';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = ClotureCaisseRepository(db);
  });

  tearDown(() async => db.close());

  // ─── Repository ─────────────────────────────────────────────────────────

  test('⚠️ ventesJourParMode : répartit correctement les ventes par mode', () async {
    final date = '2026-11-11';

    // Espèces : 1 000
    await db.into(db.sales).insert(SalesCompanion.insert(
      id: const Value('uuid-v1'),
      soldAt: DateTime(2026, 11, 11, 9, 0),
      total: const Value(1000.0),
      paymentMode: const Value('especes'),
      status: const Value('normalisee'),
      deviceId: Value(poste),
    ));

    // Mobile money : 500
    await db.into(db.sales).insert(SalesCompanion.insert(
      id: const Value('uuid-v2'),
      soldAt: DateTime(2026, 11, 11, 10, 0),
      total: const Value(500.0),
      paymentMode: const Value('mobile_money'),
      status: const Value('normalisee'),
      deviceId: Value(poste),
    ));

    // Virement : 300
    await db.into(db.sales).insert(SalesCompanion.insert(
      id: const Value('uuid-v3'),
      soldAt: DateTime(2026, 11, 11, 11, 0),
      total: const Value(300.0),
      paymentMode: const Value('virement'),
      status: const Value('normalisee'),
      deviceId: Value(poste),
    ));

    // Annulée : ignorée
    await db.into(db.sales).insert(SalesCompanion.insert(
      id: const Value('uuid-v4'),
      soldAt: DateTime(2026, 11, 11, 12, 0),
      total: const Value(999.0),
      paymentMode: const Value('especes'),
      status: const Value('annulee'),
      deviceId: Value(poste),
    ));

    final modes = await depot.ventesJourParMode(closureDate: date, deviceId: poste);

    expect(modes['especes'], 1000.0);
    expect(modes['mobile_money'], 500.0);
    expect(modes['virement'], 300.0);
  });

  test('⚠️ dejaValideAujourdhui : vrai si une clôture validée existe', () async {
    await db.into(db.cashClosures).insert(CashClosuresCompanion.insert(
      id: const Value('uuid-cc1'),
      fiscalYearId: const Value('fy-2026'),
      closureDate: const Value('2026-11-11'),
      deviceId: Value(poste),
      ventesEspeces: const Value(0),
      ventesMobileMoney: const Value(0),
      ventesVirement: const Value(0),
      fondDeCaisse: const Value(100),
      montantCompte: const Value(100),
      ecart: const Value(0),
      statut: const Value('validée'),
    ));

    final dejaFaite = await depot.dejaValideAujourdhui(poste);
    expect(dejaFaite, isTrue, reason: 'Une clôture validée ce jour doit retourner true');
  });

  test('⚠️ dejaValideAujourdhui : faux si aucune clôture pour ce poste', () async {
    final dejaFaite = await depot.dejaValideAujourdhui(poste);
    expect(dejaFaite, isFalse);
  });

  test('⚠️ dernieresCloturesPoste : retourne au plus 10 clôtures pour ce poste', () async {
    for (var i = 1; i <= 12; i++) {
      final jour = i.toString().padLeft(2, '0');
      await db.into(db.cashClosures).insert(CashClosuresCompanion.insert(
        id: Value('uuid-cc-$i'),
        fiscalYearId: const Value('fy-2026'),
        closureDate: Value('2026-11-$jour'),
        deviceId: Value(poste),
        ventesEspeces: const Value(0),
        ventesMobileMoney: const Value(0),
        ventesVirement: const Value(0),
        fondDeCaisse: const Value(100),
        montantCompte: const Value(100),
        ecart: const Value(0),
        statut: const Value('validée'),
      ));
    }

    final dernieres = await depot.dernieresCloturesPoste(poste);
    expect(dernieres.length, 10, reason: 'Limité à 10 même si 12 existent');
  });

  // ─── Écran ───────────────────────────────────────────────────────────────

  testWidgets('⚠️ écran affiche les trois KPI (Espèces, Mobile Money, Virement)', (tester) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(MaterialApp(
      home: ClotureCaisseScreen(depot: depot, deviceId: poste),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Espèces'), findsOneWidget);
    expect(find.text('Mobile Money'), findsOneWidget);
    expect(find.text('Virement'), findsOneWidget);
  });

  testWidgets('⚠️ écran affiche le champ fond de caisse et montant compté', (tester) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(MaterialApp(
      home: ClotureCaisseScreen(depot: depot, deviceId: poste),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cloture-fond-de-caisse')), findsOneWidget);
    expect(find.byKey(const Key('cloture-montant-compte')), findsOneWidget);
  });

  testWidgets('⚠️ badge « Clôture déjà validée » visible quand une clôture existe', (tester) async {
    // Insérer une clôture pour aujourd'hui.
    final aujourdhui = DateTime.now();
    final dateStr =
        '${aujourdhui.year.toString().padLeft(4, '0')}-'
        '${aujourdhui.month.toString().padLeft(2, '0')}-'
        '${aujourdhui.day.toString().padLeft(2, '0')}';

    await db.into(db.cashClosures).insert(CashClosuresCompanion.insert(
      id: const Value('uuid-cc-auj'),
      fiscalYearId: const Value('fy-2026'),
      closureDate: Value(dateStr),
      deviceId: Value(poste),
      ventesEspeces: const Value(0),
      ventesMobileMoney: const Value(0),
      ventesVirement: const Value(0),
      fondDeCaisse: const Value(200),
      montantCompte: const Value(200),
      ecart: const Value(0),
      statut: const Value('validée'),
    ));

    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(MaterialApp(
      home: ClotureCaisseScreen(depot: depot, deviceId: poste),
    ));
    await tester.pumpAndSettle();

    expect(
      find.text('Clôture déjà validée pour cette date'),
      findsOneWidget,
      reason: 'Le badge doit apparaître quand une clôture validée existe pour le jour courant',
    );
  });
}
