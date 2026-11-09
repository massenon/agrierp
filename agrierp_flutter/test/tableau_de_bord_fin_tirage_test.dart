import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/localisation/localisation_poste.dart';
import 'package:agrierp/features/pilotage/tableau_de_bord_repository.dart';
import 'package:agrierp/features/pilotage/tableau_de_bord_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// PWA-2b — le Tableau de bord affiché PENDANT un tirage se met à jour SEUL à la fin du tirage, sans changer d'écran :
/// les 0 du premier affichage (poste neuf, tirage en cours) deviennent les chiffres du serveur ; l'état saisi reste.
void main() {
  testWidgets('la fin de tirage relit le tableau, sans roue d\'attente ni changement d\'écran', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final fin = ValueNotifier<int>(0);
    addTearDown(fin.dispose);
    tester.view.physicalSize = const Size(1600, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: LocalisationPoste.locale,
        supportedLocales: LocalisationPoste.locales,
        localizationsDelegates: LocalisationPoste.delegues,
        home: TableauDeBordScreen(
          depot: TableauDeBordRepository(database: db, horloge: () => DateTime(2026, 10, 19, 14)),
          finDeTirage: fin,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('0'), findsWidgets, reason: 'poste neuf : zéro tête');
    expect(find.text('312'), findsNothing);

    // Le tirage apporte une bande de 312 têtes.
    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: 'b0b0b0b0-0000-4000-8000-000000000001',
            code: 'POR-2026-01',
            speciesId: 'e0e0e0e0-0000-4000-8000-000000000001',
            speciesCode: const Value('porciculture'),
            status: const Value('actif'),
            isActive: const Value(true),
            initialQuantity: const Value(312),
            currentQuantity: const Value(312),
          ),
        );
    // Sans notification, l'écran ne bouge pas (comportement d'avant).
    await tester.pumpAndSettle();
    expect(find.text('312'), findsNothing);

    fin.value++; // fin du tirage
    await tester.pump(); // relecture lancée…
    expect(find.byType(CircularProgressIndicator), findsNothing, reason: 'relecture silencieuse : le contenu reste affiché');
    await tester.pumpAndSettle();
    expect(find.text('312'), findsWidgets, reason: 'le tableau affiche les données tirées');
  });
}
