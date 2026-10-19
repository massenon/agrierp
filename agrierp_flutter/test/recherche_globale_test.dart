import 'dart:io';

import 'package:agrierp/core/auth/permissions_poste.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/recherche/recherche_globale_champ.dart';
import 'package:agrierp/features/recherche/recherche_globale_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Ticket H1b — RECHERCHE GLOBALE DU POSTE (`App\Livewire\Shared\GlobalSearch`, le maître).
///
/// 🔴 Avant : champ désactivé « Recherche (application web) ». Les libellés des domaines et le placeholder sont LUS
/// dans le composant et la vue du web ; le filtrage par droit est vérifié rôle par rôle.
void main() {
  late AppDatabase db;
  late RechercheGlobaleRepository depot;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = RechercheGlobaleRepository(database: db);
    await db.into(db.livestockSpecies).insert(LivestockSpeciesCompanion.insert(id: 'aaaaaaaa-0000-4000-8000-0000000000e1', code: 'cuniculture', label: 'Cuniculture'));
    await db.into(db.livestockLots).insert(LivestockLotsCompanion.insert(
      id: 'aaaaaaaa-0000-4000-8000-000000000001', code: 'LOT-ŒUF-01', speciesId: 'aaaaaaaa-0000-4000-8000-0000000000e1',
      speciesCode: const Value('cuniculture'), currentQuantity: const Value(42),
    ));
    await db.into(db.customers).insert(CustomersCompanion.insert(id: 'aaaaaaaa-0000-4000-8000-000000000002', name: 'Œuvre Saint-Joseph', phone: const Value('0197000000')));
    await db.into(db.products).insert(ProductsCompanion.insert(
      id: 'aaaaaaaa-0000-4000-8000-000000000003', sku: 'OEU-001', name: 'Œufs de table', unit: 'plateau', pricingMode: 'fixe',
      stockQty: const Value(2), alertThreshold: const Value(5),
    ));
  });
  tearDown(() => db.close());

  test('accents et ligatures ignorés : « oeu » trouve le lot, le client et l article', () async {
    final domaines = await depot.rechercher('oeu', 'admin');
    final parCle = {for (final d in domaines) d.cle: d};

    expect(parCle['elevage']!.resultats.single.sousLibelle, 'Cuniculture — 42 sujets');
    expect(parCle['commercial']!.resultats.single.libelle, 'Œuvre Saint-Joseph');
    final article = parCle['achats_stocks']!.resultats.single;
    expect((article.sousLibelle, article.critique, article.cible), ('Stock : 2 plateau — Alerte Critique', true, EcranPoste.gestionStocks));
  });

  test('moins de 2 caractères : aucune recherche', () async {
    expect(await depot.rechercher('o', 'admin'), isEmpty);
  });

  test('⚠️ un domaine non autorisé n est jamais interrogé (droits du web)', () async {
    String domaines(List<DomaineRecherche> d) => d.map((x) => x.cle).join(',');
    expect(domaines(await depot.rechercher('oeu', 'caissier')), 'commercial');
    expect(domaines(await depot.rechercher('oeu', 'animalier')), 'elevage');
    expect(domaines(await depot.rechercher('oeu', 'comptable')), '');
  });

  test('libellés des domaines et placeholder : ceux du web', () {
    final composant = File('$dossierLaravel/app/Livewire/Shared/GlobalSearch.php').readAsStringSync();
    final libellesWeb = RegExp(r"'key' => '(\w+)', 'label' => '([^']+)'").allMatches(composant).map((m) => '${m.group(1)}=${m.group(2)}').toList();
    expect(libellesWeb, [
      'elevage=Élevage & Cheptel',
      'sante=Vétérinaire & Soins',
      'commercial=Commercial & Caisse',
      'achats_stocks=Achats & Stocks',
      'comptabilite_admin=Comptabilité & Admin',
    ]);
    final vue = File('$dossierLaravel/resources/views/livewire/shared/global-search.blade.php').readAsStringSync();
    expect(vue, contains('placeholder="Recherche globale ERP… (Ctrl+K)"'));
    expect(vue, contains('Aucun résultat pour « {{ \$query }} ».'));
  }, skip: Directory(dossierLaravel).existsSync() ? false : 'dépôt Laravel absent');

  testWidgets('Ctrl+K donne le focus ; saisir, flèche bas, Entrée : navigation vers l écran', (t) async {
    EcranPoste? ouvert;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(child: RechercheGlobaleChamp(depot: depot, role: 'admin', onNaviguer: (e) => ouvert = e)),
      ),
    ));
    expect(find.text('Recherche globale ERP… (Ctrl+K)'), findsOneWidget);

    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyK);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pump();
    expect(t.widget<TextField>(find.byKey(const Key('recherche-globale-saisie'))).focusNode!.hasFocus, isTrue);

    await t.enterText(find.byKey(const Key('recherche-globale-saisie')), 'saint');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    await t.pumpAndSettle();
    expect(find.text('COMMERCIAL & CAISSE (1)'), findsOneWidget);

    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(ouvert, EcranPoste.clientsEtCreances);
    expect(find.byKey(const Key('recherche-globale-panneau')), findsNothing);
  });

  testWidgets('rien ne correspond : le message du web', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: RechercheGlobaleChamp(depot: depot, role: 'admin', onNaviguer: (_) {})),
    ));
    await t.enterText(find.byKey(const Key('recherche-globale-saisie')), 'zzz');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    await t.pumpAndSettle();
    expect(find.text('Aucun résultat pour « zzz ».'), findsOneWidget);
  });
}
