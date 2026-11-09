import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/elevage/bandes_repository.dart';
import 'package:agrierp/features/elevage/gestion_bandes_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket du 27/10/2026 — « Bandes & Sujets » : les trois boutons de l'en-tête restent SUR UNE LIGNE
/// (Enregistrer des Sujets, Registre des Reproducteurs, Nouvelle Bande). Au web : `xl:flex-nowrap`.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> monter(WidgetTester t, double largeur) async {
    t.view.physicalSize = Size(largeur, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final depot = BandesRepository(database: db, deviceId: 'poste-test', horloge: () => DateTime(2026, 10, 27, 10));
    await t.pumpWidget(MaterialApp(home: GestionBandesScreen(depot: depot, horloge: () => DateTime(2026, 10, 27, 10))));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
    await t.pumpAndSettle();
  }

  for (final largeur in [1280.0, 1400.0, 1920.0]) {
    testWidgets('⚠️ les trois boutons de l\'en-tête sont sur une seule ligne à $largeur px', (t) async {
      await monter(t, largeur);

      final hauts = [
        for (final cle in ['bandes-enregistrer-sujets', 'bandes-registre-reproducteurs', 'bande-nouvelle'])
          t.getRect(find.byKey(Key(cle))),
      ];
      expect(hauts[1].top, closeTo(hauts[0].top, 1), reason: 'Registre sur la ligne de Enregistrer des Sujets');
      expect(hauts[2].top, closeTo(hauts[0].top, 1), reason: 'Nouvelle Bande sur la même ligne');
      expect(hauts[0].right, lessThan(hauts[1].left));
      expect(hauts[1].right, lessThan(hauts[2].left));
    });
  }
}
