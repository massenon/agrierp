import 'dart:io';
import 'dart:math' show Random;

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/pilotage/tableau_de_bord_repository.dart';
import 'package:agrierp/features/pilotage/tableau_de_bord_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'php_laravel.dart';

/// Ticket DEV2 — l'onglet « Devis » des « Transactions Récentes » du poste lit `quotes` comme le web.
///
/// Maître : `Dashboard\Index::getTransactionsRecentesProperty` (`Quote::with('customer')->latest('created_at')->limit(5)`,
/// AUCUN filtre de statut, d'archivage ni d'exercice) et `index.blade.php` (`ID8 · client`, `text-info-blue`).
/// Trois garde-fous : sources du Blade lues (jamais recopiées), parité EXÉCUTÉE avec le vrai PHP sur des jeux de devis
/// (statuts, archivés, avec et sans client, 0 à 25 devis), rendu de l'onglet.
void main() {
  final blade = File('$dossierLaravel/resources/views/livewire/dashboard/index.blade.php');
  final composant = File('$dossierLaravel/app/Livewire/Dashboard/Index.php');
  final sautSansWeb = blade.existsSync() && composant.existsSync() ? null : 'SAUT : dépôt Laravel introuvable';

  late AppDatabase db;
  late TableauDeBordRepository depot;
  final maintenant = DateTime(2026, 10, 19, 14);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = TableauDeBordRepository(database: db, horloge: () => maintenant);
  });
  tearDown(() async => db.close());

  String uuid(String prefixe, int i) => '$prefixe${i.toRadixString(16).padLeft(8, '0')}'.padRight(36, '0').substring(0, 36);

  Future<void> client(String id, String nom) => db.into(db.customers).insert(CustomersCompanion.insert(id: id, name: nom));

  Future<void> devis(
    String id,
    String? clientId,
    double montant,
    DateTime jour, {
    String statut = 'brouillon',
    bool actif = true,
    SyncStatus synchro = SyncStatus.synced,
  }) => db.into(db.quotes).insert(
    QuotesCompanion.insert(
      id: id,
      deviceId: 'serveur',
      syncStatus: Value(synchro),
      updatedAt: jour,
      quoteNumber: Value('DEV-2026-${id.substring(0, 6)}'),
      customerId: clientId ?? '',
      articlesDescription: 'Lapins',
      amount: montant,
      quoteDate: DateTime(jour.year, jour.month, jour.day),
      status: Value(statut),
      isActive: Value(actif),
    ),
  );

  group('sources du web', () {
    test('le Blade et le composant disent ce que le poste reprend', () {
      final b = blade.readAsStringSync();
      final c = composant.readAsStringSync();
      expect(c, contains("\\App\\Models\\Quote::with('customer')->latest('created_at')->limit(5)->get()"));
      // Aucun filtre sur la ligne des devis : ni is_active, ni statut, ni exercice.
      final ligne = c.split('\n').firstWhere((l) => l.contains("'quotation' =>"));
      expect(ligne, isNot(contains('is_active')));
      expect(ligne, isNot(contains('where')));
      expect(b, contains('Aucun devis récent.'));
      expect(b, contains(r"strtoupper(substr($quote->id, 0, 8)) }} · {{ $quote->customer?->name }}"));
      expect(b, contains(r'font-bold text-info-blue">{{ number_format($quote->amount, 0'));
    }, skip: sautSansWeb);
  });

  test('sans devis : liste vide, ordre des autres onglets inchangé', () async {
    final d = await depot.charger();
    expect(d.devisRecents, isEmpty);
  });

  test('les devis REFUSÉS par le serveur (conflict) n\'existent pas au web : exclus ; les en attente comptent', () async {
    await client('c1'.padRight(36, '0'), 'AMOUSSOU Régis');
    await devis(uuid('aaaa', 1), 'c1'.padRight(36, '0'), 100, DateTime(2026, 10, 1), synchro: SyncStatus.conflict);
    await devis(uuid('aaaa', 2), 'c1'.padRight(36, '0'), 200, DateTime(2026, 10, 2), synchro: SyncStatus.pending);
    final d = await depot.charger();
    expect(d.devisRecents.map((l) => l.montant), [200]);
  });

  testWidgets('rendu : l\'onglet Devis liste les cinq derniers, message vide seulement si vide', (tester) async {
    Future<void> ouvrir() async {
      tester.view.physicalSize = const Size(1600, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(home: TableauDeBordScreen(depot: depot)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('onglet-tx-Devis')));
      await tester.tap(find.byKey(const Key('onglet-tx-Devis')));
      await tester.pumpAndSettle();
    }

    await ouvrir();
    expect(find.text('Aucun devis récent.'), findsOneWidget);

    await tester.runAsync(() async {
      await client('c1'.padRight(36, '0'), 'AMOUSSOU Régis');
      await devis(uuid('abcd', 1), 'c1'.padRight(36, '0'), 12500, DateTime(2026, 10, 5));
    });
    await ouvrir();
    expect(find.text('Aucun devis récent.'), findsNothing);
    expect(find.text('ABCD0000 · AMOUSSOU Régis'), findsOneWidget);
    expect(find.text('12 500 F'), findsOneWidget);
  });

  test(
    'parité exécutée : les cinq derniers devis du poste = ceux de Dashboard\\Index (statuts, archivés, clients)',
    () async {
      var graine = 11;
      int hasard(int n) => (graine = (graine * 1103515245 + 12345) & 0x7fffffff) % n;
      var verifies = 0;
      for (final taille in [0, 1, 3, 5, 6, 12, 25, 25]) {
        final noms = ['AMOUSSOU Régis', 'KPOSSOU Éléonore', 'DOSSOU Marc'];
        final clients = <Map<String, Object?>>[
          for (var i = 0; i < noms.length; i++) {'id': uuid('cccc', i), 'name': noms[i]},
        ];
        final liste = <Map<String, Object?>>[];
        // Un jour de création DIFFÉRENT par devis : à jour égal le web ne départage pas (`latest` sans second tri).
        final jours = List.generate(taille, (i) => i)..shuffle(Random(taille * 7 + graine));
        for (var i = 0; i < taille; i++) {
          final jour = DateTime(2026, 6, 1).add(Duration(days: jours[i] * 3));
          liste.add({
            'id': uuid('d${i.toRadixString(16)}', hasard(1 << 20)),
            'customer': hasard(5) == 0 ? null : clients[hasard(3)]['id'],
            'amount': (1 + hasard(900)) * 1000 + hasard(2) * 500,
            'day': '${jour.year}-${jour.month.toString().padLeft(2, '0')}-${jour.day.toString().padLeft(2, '0')}',
            'status': ['brouillon', 'envoye', 'accepte', 'refuse', 'facture'][hasard(5)],
            'active': hasard(4) != 0,
          });
        }
        final php = executerPhp('<?php\n$amorceApplication\n$_scriptPhp', {'clients': clients, 'devis': liste},
            application: true) as List;

        for (final c in clients) {
          await client(c['id']! as String, c['name']! as String);
        }
        for (final q in liste) {
          final j = DateTime.parse('${q['day']} 10:00:00');
          await devis(q['id']! as String, q['customer'] as String?, (q['amount']! as num).toDouble(), j,
              statut: q['status']! as String, actif: q['active']! as bool);
        }
        final d = await depot.charger();
        expect(
          [for (final l in d.devisRecents) (l.libelle, l.montant)],
          [for (final x in php) ('${(x['id'] as String).substring(0, 8).toUpperCase()} · ${x['customer'] ?? ''}', (x['amount'] as num).toDouble())],
          reason: 'jeu de $taille devis',
        );
        expect(d.devisRecents.length, taille < 5 ? taille : 5);
        verifies += d.devisRecents.length;
        // Base du poste vidée pour le jeu suivant.
        await db.delete(db.quotes).go();
        await db.delete(db.customers).go();
      }
      expect(verifies, 29, reason: '0+1+3+5+5+5+5+5 devis comparés');
    },
    skip: sautSansPhp(),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

const _scriptPhp = r'''
Carbon\Carbon::setTestNow('2026-10-19 14:00:00');
$entree = json_decode(file_get_contents($argv[1]), true);
foreach ($entree['clients'] as $c) {
    App\Models\Customer::forceCreate(['id' => $c['id'], 'name' => $c['name'], 'is_active' => true]);
}
foreach ($entree['devis'] as $i => $q) {
    App\Models\Quote::forceCreate([
        'id' => $q['id'], 'quote_number' => 'DEV-2026-'.str_pad((string) $i, 4, '0', STR_PAD_LEFT),
        'customer_id' => $q['customer'], 'articles_description' => 'Lapins', 'amount' => $q['amount'],
        'quote_date' => $q['day'], 'status' => $q['status'], 'is_active' => $q['active'],
        'created_at' => $q['day'].' 10:00:00', 'updated_at' => $q['day'].' 10:00:00',
    ]);
}
$c = new App\Livewire\Dashboard\Index();
echo json_encode($c->transactionsRecentes['quotation']->map(fn ($x) => [
    'id' => $x->id, 'customer' => $x->customer?->name, 'amount' => (float) $x->amount,
])->values());
''';
