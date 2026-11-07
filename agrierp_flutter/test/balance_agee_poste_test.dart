import 'dart:io';
import 'dart:math';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/comptabilite/balance_agee.dart';
import 'package:agrierp/features/comptabilite/comptabilite_repository.dart';
import 'package:agrierp/features/comptabilite/comptabilite_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'php_laravel.dart';

/// Carte « Balance Âgée » du hub : page du poste = `Livewire\Comptabilite\BalanceAgee` (web, maître).
///
///  1. libellés lus dans le Blade ; 2. règles à la main (échéance, reste dû, bornes 30 / 31 jours) ;
///  3. PARITÉ EXÉCUTÉE avec le vrai `AgedBalanceService` (jeu tiré à graine fixe, deux volets) ; 4. l'écran.
void main() {
  final blade = File('$dossierLaravel/resources/views/livewire/comptabilite/balance-agee.blade.php');
  final sautBlade = blade.existsSync() ? null : 'SAUT : Blade absent ($dossierLaravel)';
  final arrete = DateTime(2026, 8, 31);

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  String uuid(String g) => g.padRight(36, '0').substring(0, 36);
  String uuidN(String p, int i) => '$p${'0' * 7}-0000-0000-0000-${i.toString().padLeft(12, '0')}';

  Future<void> client(String cle, String nom) =>
      db.into(db.customers).insert(CustomersCompanion.insert(id: uuid(cle), name: nom));

  Future<void> creance(String cle, String client, double montant, double regle, DateTime? echeance) =>
      db.into(db.receivables).insert(ReceivablesCompanion.insert(
        id: uuid(cle),
        customerId: uuid(client),
        amount: montant,
        amountPaid: Value(regle),
        dueDate: Value(echeance),
      ));

  Future<void> creanceN(String id, String client, double montant, double regle, DateTime? echeance) =>
      db.into(db.receivables).insert(ReceivablesCompanion.insert(
        id: id,
        customerId: client,
        amount: montant,
        amountPaid: Value(regle),
        dueDate: Value(echeance),
      ));

  group('libellés du Blade', () {
    test('titre, phrases et libellés du poste sont ceux du Blade', () {
      final source = blade.readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
      for (final t in [
        'Balance Âgée',
        'Encours par ancienneté de retard — qui relancer, et dans quel ordre.',
        "Écran ajouté hors maquette, à la demande. L'âge se compte depuis l'",
        "— pas depuis l'émission — et seul le",
        'Créances clients',
        'Dettes fournisseurs',
        'Aucun encours à cette date — tout est soldé.',
        'Total général',
      ]) {
        expect(source, contains(t), reason: t);
      }
      final ecran = File('lib/features/comptabilite/comptabilite_screen.dart').readAsStringSync();
      for (final t in [
        'Encours par ancienneté de retard — qui relancer, et dans quel ordre.',
        "Écran ajouté hors maquette, à la demande. L'âge se compte depuis l'",
        'Aucun encours à cette date — tout est soldé.',
        'Créances clients',
        'Dettes fournisseurs',
      ]) {
        expect(ecran, contains(t), reason: t);
      }
      // Les tranches du serveur, dans son ordre.
      final service = File('$dossierLaravel/app/Services/AgedBalanceService.php').readAsStringSync();
      final serveur = RegExp(r"'([^']+)' => (?:\d+|null),").allMatches(service.substring(service.indexOf('TRANCHES'))).map((m) => m[1]!).take(5);
      expect([for (final (l, _) in BalanceAgee.tranches) l], serveur.toList());
    }, skip: sautBlade);
  });

  group('règles (jeu fait à la main)', () {
    test('⚠️ l âge se compte depuis l échéance : non échu, 30 et 31 jours, 90 et 91 jours, sans échéance', () {
      expect(BalanceAgee.tranche(DateTime(2026, 9, 15), arrete), 'Non échu');
      expect(BalanceAgee.tranche(arrete, arrete), 'Non échu');
      expect(BalanceAgee.tranche(null, arrete), 'Non échu');
      expect(BalanceAgee.tranche(DateTime(2026, 8, 30), arrete), '1 à 30 jours');
      expect(BalanceAgee.tranche(DateTime(2026, 8, 1), arrete), '1 à 30 jours'); // 30 jours
      expect(BalanceAgee.tranche(DateTime(2026, 7, 31), arrete), '31 à 60 jours'); // 31 jours
      expect(BalanceAgee.tranche(DateTime(2026, 6, 2), arrete), '61 à 90 jours'); // 90 jours
      expect(BalanceAgee.tranche(DateTime(2026, 6, 1), arrete), 'Plus de 90 jours'); // 91 jours
    });

    test('⚠️ le reste dû est ventilé, le plus gros encours d abord, les soldées sont ignorées', () async {
      await client('c1', 'Boutique ABC');
      await client('c2', 'Hôtel XYZ');
      await creance('r1', 'c1', 100000, 90000, DateTime(2026, 8, 20)); // reste 10 000, 1 à 30
      await creance('r2', 'c2', 50000, 0, DateTime(2026, 5, 1)); // 50 000, plus de 90
      await creance('r3', 'c2', 20000, 20000, DateTime(2026, 5, 1)); // soldée : ignorée
      await creance('r4', 'c1', 7000, 0, null); // sans échéance : non échu

      final donnees = await DonneesBalanceAgee.charger(db);
      final b = donnees.calculer('creances', arrete);

      expect([for (final t in b.tiers) t.nom], ['Hôtel XYZ', 'Boutique ABC']);
      expect(b.tiers[0].total, 50000);
      expect(b.tiers[1].tranches['1 à 30 jours'], 10000);
      expect(b.tiers[1].tranches['Non échu'], 7000);
      expect(b.totaux['Plus de 90 jours'], 50000);
      expect(b.total, 67000);
    });
  });

  group('parité exécutée avec AgedBalanceService', () {
    const script = r'''
$in = json_decode(file_get_contents($argv[1]), true);
$sortie = [];
foreach ($in['clients'] as $c) { App\Models\Customer::create(['name' => $c['nom'], 'is_active' => true]); }
foreach ($in['fournisseurs'] as $f) { App\Models\Supplier::create(['name' => $f['nom'], 'is_active' => true]); }
$clients = App\Models\Customer::orderBy('created_at')->orderBy('name')->get()->keyBy('name');
$fournisseurs = App\Models\Supplier::orderBy('name')->get()->keyBy('name');
foreach ($in['creances'] as $r) {
    App\Models\Receivable::create(['customer_id' => $clients[$r['tiers']]->id, 'amount' => $r['montant'], 'amount_paid' => $r['regle'], 'due_date' => $r['echeance'], 'status' => 'en_cours']);
}
foreach ($in['dettes'] as $r) {
    App\Models\Payable::create(['supplier_id' => $fournisseurs[$r['tiers']]->id, 'amount' => $r['montant'], 'amount_paid' => $r['regle'], 'due_date' => $r['echeance'], 'status' => 'en_cours']);
}
$service = app(App\Services\AgedBalanceService::class);
$date = Illuminate\Support\Carbon::parse($in['arrete']);
echo json_encode(['creances' => $service->creances($date), 'dettes' => $service->dettes($date)]);
''';

    test('⚠️⚠️ le poste produit les mêmes tiers, tranches et totaux que le serveur, sur les deux volets', () async {
      final sans = sautSansPhp();
      if (sans != null) {
        markTestSkipped(sans);
        return;
      }
      final hasard = Random(20261107);
      final tiersNoms = ['Alpha', 'Bravo', 'Charlie', 'Delta', 'Écho', 'Foxtrot'];
      List<Map<String, Object?>> lignes() => [
        for (var i = 0; i < 40; i++)
          () {
            final montant = (1 + hasard.nextInt(200)) * 1000.0;
            final soldee = hasard.nextInt(6) == 0;
            final regle = soldee ? montant : (hasard.nextBool() ? 0.0 : (hasard.nextInt(montant ~/ 1000)) * 1000.0);
            final jours = hasard.nextInt(7) == 0 ? null : hasard.nextInt(150) - 25;
            final echeance = jours == null ? null : arrete.subtract(Duration(days: jours));
            return <String, Object?>{
              'tiers': tiersNoms[hasard.nextInt(tiersNoms.length)],
              'montant': montant,
              'regle': regle,
              'echeance': echeance == null
                  ? null
                  : '${echeance.year}-${echeance.month.toString().padLeft(2, '0')}-${echeance.day.toString().padLeft(2, '0')}',
            };
          }(),
      ];
      final creances = lignes();
      final dettes = lignes();
      final entree = {
        'clients': [for (final n in tiersNoms) {'nom': n}],
        'fournisseurs': [for (final n in tiersNoms) {'nom': n}],
        'creances': creances,
        'dettes': dettes,
        'arrete': '2026-08-31',
      };
      final web = executerPhp('<?php\n$amorceApplication\n$script', entree, application: true) as Map<String, dynamic>;

      for (final (i, n) in tiersNoms.indexed) {
        await db.into(db.customers).insert(CustomersCompanion.insert(id: uuidN('c', i), name: n));
        await db.into(db.suppliers).insert(SuppliersCompanion.insert(id: uuidN('f', i), name: n));
      }
      DateTime? lire(Object? t) => t == null ? null : DateTime.parse(t as String);
      for (final (i, r) in creances.indexed) {
        await creanceN(uuidN('r', i), uuidN('c', tiersNoms.indexOf(r['tiers']! as String)), r['montant']! as double, r['regle']! as double, lire(r['echeance']));
      }
      for (final (i, r) in dettes.indexed) {
        await db.into(db.payables).insert(PayablesCompanion.insert(
          id: uuidN('p', i),
          supplierId: uuidN('f', tiersNoms.indexOf(r['tiers']! as String)),
          amount: r['montant']! as double,
          amountPaid: Value(r['regle']! as double),
          dueDate: Value(lire(r['echeance'])),
        ));
      }

      final donnees = await DonneesBalanceAgee.charger(db);
      for (final volet in ['creances', 'dettes']) {
        final attendu = web[volet] as Map<String, dynamic>;
        final poste = donnees.calculer(volet, arrete);
        expect(poste.total, closeTo((attendu['total'] as num).toDouble(), 0.001), reason: '$volet total');
        for (final (t, _) in BalanceAgee.tranches) {
          expect(poste.totaux[t], closeTo(((attendu['totaux'] as Map)[t] as num).toDouble(), 0.001), reason: '$volet $t');
        }
        final tiersWeb = (attendu['tiers'] as List).cast<Map<String, dynamic>>();
        expect([for (final t in poste.tiers) t.nom], [for (final t in tiersWeb) t['nom']], reason: '$volet ordre des tiers');
        for (final (i, t) in tiersWeb.indexed) {
          expect(poste.tiers[i].total, closeTo((t['total'] as num).toDouble(), 0.001), reason: '$volet ${t['nom']}');
          for (final (tr, _) in BalanceAgee.tranches) {
            expect(poste.tiers[i].tranches[tr], closeTo(((t['tranches'] as Map)[tr] as num).toDouble(), 0.001), reason: '$volet ${t['nom']} $tr');
          }
        }
      }
    });
  });

  group('écran', () {
    Future<void> ouvrirPage(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1700, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: ComptabiliteScreen(depot: ComptabiliteRepository(database: db), maintenant: () => arrete),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('carte-balanceAgee')));
      await tester.pumpAndSettle();
    }

    testWidgets('la carte du hub ouvre la page : titre, cinq cartes, tableau, total général', (tester) async {
      await client('c1', 'Boutique ABC');
      await creance('r1', 'c1', 100000, 90000, DateTime(2026, 8, 20));
      await ouvrirPage(tester);

      expect(find.text('Balance Âgée'), findsOneWidget);
      expect(find.text('Encours par ancienneté de retard — qui relancer, et dans quel ordre.'), findsOneWidget);
      for (final (t, _) in BalanceAgee.tranches) {
        expect(find.byKey(Key('agee-kpi-$t')), findsOneWidget, reason: t);
      }
      expect(find.text('Boutique ABC'), findsOneWidget);
      expect(find.text('TOTAL GÉNÉRAL'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('agee-kpi-1 à 30 jours')), matching: find.text('10 000 F')), findsOneWidget);
    });

    testWidgets('sans encours, la page le dit ; le volet Dettes fournisseurs change l en-tête de colonne', (tester) async {
      await ouvrirPage(tester);
      expect(find.text('Aucun encours à cette date — tout est soldé.'), findsOneWidget);
      expect(find.text('CLIENT'), findsOneWidget);

      await tester.tap(find.byKey(const Key('agee-volet')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dettes fournisseurs').last);
      await tester.pumpAndSettle();
      expect(find.text('FOURNISSEUR'), findsOneWidget);
    });
  });
}
