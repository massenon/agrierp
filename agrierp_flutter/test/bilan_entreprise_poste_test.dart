import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/comptabilite/comptabilite_repository.dart';
import 'package:agrierp/features/comptabilite/comptabilite_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Carte « Bilan de l'Entreprise » du hub : page du poste = `Livewire\Comptabilite\Bilan` (route `/rapport-bilan`, web
/// maître). Les montants viennent de `bilanComparatif` (parité PHP exécutée du ticket EX8) ; ce fichier garde la PAGE :
/// libellés lus dans le Blade, bandeau d'équilibre, cartes Actif / Passif, date d'arrêté.
void main() {
  final blade = File('$dossierLaravel/resources/views/livewire/comptabilite/bilan.blade.php');
  final sautBlade = blade.existsSync() ? null : 'SAUT : Blade absent ($dossierLaravel)';

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  String uuid(String g) => g.padRight(36, '0').substring(0, 36);

  Future<void> compte(String cle, String code, String libelle, int classe) => db.into(db.chartOfAccounts).insert(
    ChartOfAccountsCompanion.insert(id: uuid(cle), code: code, label: libelle, accountClass: Value(classe)),
  );

  Future<void> ecriture(String cle, double montant, String debit, String credit) async {
    await db.into(db.accountingEntries).insert(AccountingEntriesCompanion.insert(
      id: uuid(cle),
      fiscalYearId: Value(uuid('ex')),
      entryDate: DateTime(2026, 8, 10),
      reference: const Value('OD — essai'),
    ));
    await db.into(db.accountingEntryLines).insert(AccountingEntryLinesCompanion.insert(
      id: uuid('${cle}d'), entryId: uuid(cle), accountId: uuid(debit), debit: Value(montant)));
    await db.into(db.accountingEntryLines).insert(AccountingEntryLinesCompanion.insert(
      id: uuid('${cle}c'), entryId: uuid(cle), accountId: uuid(credit), credit: Value(montant)));
  }

  Future<void> jeu() async {
    await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(
      id: uuid('ex'), year: 2026, startDate: Value(DateTime(2026, 1, 1)), endDate: Value(DateTime(2026, 12, 31)), status: const Value('ouvert')));
    await compte('c101', '101', 'Capital', 1);
    await compte('c231', '231', 'Bâtiments', 2);
    await compte('c531', '531', 'Caisse', 5);
    await ecriture('e1', 4500000, 'c531', 'c101'); // apport en caisse
    await ecriture('e2', 2400000, 'c231', 'c531'); // bâtiment payé en caisse
  }

  Future<void> ouvrirPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1700, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: ComptabiliteScreen(depot: ComptabiliteRepository(database: db), maintenant: () => DateTime(2026, 8, 31)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('carte-bilan')));
    await tester.pumpAndSettle();
  }

  test('titres, phrases et libellés de la page sont ceux du Blade', () {
    final source = blade.readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
    final ecran = File('lib/features/comptabilite/comptabilite_screen.dart').readAsStringSync() +
        File('lib/features/comptabilite/etats_comparatifs.dart').readAsStringSync();
    for (final t in [
      "Bilan Simplifié de l'Entreprise",
      'Situation patrimoniale de la Ferme École OLOUWACHEGOUN au',
      'Bilan équilibré — Total Actif = Total Passif =',
      'Déséquilibre détecté — Actif',
      'Actif (Emplois)',
      'Passif (Ressources)',
      'Actif Immobilisé (Classe 2)',
      'Actif Circulant (Classes 3 & 4)',
      'Trésorerie Actif (Classe 5)',
      'Capitaux Propres (Classe 1)',
      'Dettes (Classe 4)',
      "Résultat de l'exercice",
      "Aucune écriture sur cette classe pour l'instant.",
      "Aucune écriture sur ces classes pour l'instant.",
      "Le passif reflète les ressources ayant financé les emplois inscrits à l'actif",
    ]) {
      expect(source, contains(t), reason: 'Blade : $t');
      expect(ecran.replaceAll('&amp;', '&'), contains(t), reason: 'poste : $t');
    }
  }, skip: sautBlade);

  testWidgets('la carte du hub ouvre la page : situation datée, bandeau équilibré, totaux actif = passif', (tester) async {
    await jeu();
    await ouvrirPage(tester);

    expect(find.text("Bilan Simplifié de l'Entreprise"), findsOneWidget);
    expect(find.text('Situation patrimoniale de la Ferme École OLOUWACHEGOUN au 31/08/2026.'), findsOneWidget);
    // Calcul à la main : actif = 2 400 000 (bâtiment) + 2 100 000 (caisse) = 4 500 000 = capital.
    expect(find.text('Bilan équilibré — Total Actif = Total Passif = 4 500 000 FCFA'), findsOneWidget);
    expect(find.text('231 - Bâtiments'), findsOneWidget);
    expect(find.text('531 - Caisse'), findsOneWidget);
    expect(find.text('101 - Capital'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('bilan-actif-9-n'))).data, '4 500 000');
    expect(tester.widget<Text>(find.byKey(const Key('bilan-passif-7-n'))).data, '4 500 000');
    expect(find.text('Aucun exercice antérieur'), findsWidgets);
  });
}
